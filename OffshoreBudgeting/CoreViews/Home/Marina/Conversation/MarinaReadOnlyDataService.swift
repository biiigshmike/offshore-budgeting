import Foundation
import SwiftData

/// Bound to one workspace. Every call fetches fresh data; the model never supplies a workspace.
@MainActor
final class MarinaReadOnlyDataService {
    private let workspace: Workspace
    private let modelContext: ModelContext
    private let homeContext: MarinaPanelHomeContext?
    private let now: Date
    private let defaultBudgetingPeriod: BudgetingPeriod
    private let calendar = Calendar.current

    init(workspace: Workspace, modelContext: ModelContext, homeContext: MarinaPanelHomeContext? = nil, now: Date = Date(), defaultBudgetingPeriod: BudgetingPeriod = .monthly) {
        self.workspace = workspace
        self.modelContext = modelContext
        self.homeContext = homeContext
        self.now = now
        self.defaultBudgetingPeriod = defaultBudgetingPeriod
    }

    func execute(_ request: MarinaDataRequest) throws -> MarinaDataResult {
        var request = request
        if request.purpose == .upcomingPresets {
            request.operation = .transactions
            request.scope = .planned
            request.state = .planned
            request.expenseMeasure = .planned
            request.includeFuture = true
            request.sort = .oldest
            if request.relativePeriod == nil && request.startDate == nil && request.endDate == nil && !request.allTime {
                request.relativePeriod = .nextSevenDays
            }
        }
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(for: workspace, modelContext: modelContext, homeContext: homeContext, now: now)
        do {
            if request.purpose == .budgetPace && request.budgetID == nil {
                let requestedRange = try dateRange(request, snapshot: snapshot)
                let matching = snapshot.budgets.filter { budget in requestedRange.map { budget.startDate <= $0.endDate && budget.endDate >= $0.startDate } ?? false }
                if matching.count == 1 { request.budgetID = matching[0].id.uuidString }
            }
            try validate(request, snapshot: snapshot)
            let range = try dateRange(request, snapshot: snapshot)
            if let range, request.periodUnit != nil,
               (calendar.dateComponents([.day], from: range.startDate, to: range.endDate).day ?? 0) > 36600 {
                throw RequestError(message: "Please choose a range of 100 years or less for period summaries.")
            }
            var result: MarinaDataResult
            switch request.tool {
            case .findRecords: result = findRecords(request, snapshot: snapshot)
            case .expenses: result = summarize(expenses(request, snapshot: snapshot, range: range), request: request, range: range)
            case .income:
                result = summarize(incomes(request, snapshot: snapshot, range: range), request: request, range: range)
                var stateRequest = request
                stateRequest.state = .actual
                let received = incomes(stateRequest, snapshot: snapshot, range: range).reduce(0) { $0 + $1.amount }
                stateRequest.state = .planned
                let expected = incomes(stateRequest, snapshot: snapshot, range: range).reduce(0) { $0 + $1.amount }
                result.metrics += [.init(label: "Actual income", value: received), .init(label: "Planned income", value: expected)]
                if expected > 0 { result.metrics.append(.init(label: "Income progress percent", value: received / expected * 100, unit: .percent)) }
            case .budgetSummary: result = budgetSummary(request, snapshot: snapshot, range: range)
            case .accounts: result = accounts(request, snapshot: snapshot, range: range)
            }
            if (request.tool == .expenses || request.tool == .income),
               request.cardID != nil || request.categoryID != nil || request.presetID != nil || request.search != nil {
                var wholeRequest = request
                wholeRequest.cardID = nil; wholeRequest.categoryID = nil
                wholeRequest.presetID = nil; wholeRequest.search = nil
                let wholeRows = request.tool == .expenses
                    ? expenses(wholeRequest, snapshot: snapshot, range: range)
                    : incomes(wholeRequest, snapshot: snapshot, range: range)
                let whole = wholeRows.reduce(0) { $0 + $1.amount }
                let part = result.metrics.first { $0.label == "Total" }?.value ?? 0
                if whole != 0 { result.metrics.append(.init(label: "Share of unfiltered period total percent", value: part / whole * 100, unit: .percent)) }
            }
            var comparisonLabel: String?
            var comparisonResolvedRange: HomeQueryDateRange?
            if request.tool == .expenses || request.tool == .income,
               request.comparisonAllTime || request.comparisonPeriod != nil || request.comparisonStartDate != nil || request.comparisonEndDate != nil || request.comparisonFilter != nil {
                var comparison = request
                if request.comparisonStartDate != nil || request.comparisonEndDate != nil {
                    comparison.allTime = false
                    comparison.relativePeriod = nil
                    comparison.startDate = request.comparisonStartDate
                    comparison.endDate = request.comparisonEndDate
                }
                if request.comparisonAllTime {
                    comparison.relativePeriod = nil; comparison.startDate = nil; comparison.endDate = nil
                    comparison.allTime = true
                }
                if let period = request.comparisonPeriod {
                    comparison.relativePeriod = period
                    comparison.startDate = nil; comparison.endDate = nil; comparison.allTime = false
                }
                if let filter = request.comparisonFilter {
                    comparison.cardID = filter.cardID; comparison.categoryID = filter.categoryID
                    comparison.budgetID = filter.budgetID; comparison.presetID = filter.presetID
                    comparison.search = filter.search
                }
                try validate(comparison, snapshot: snapshot)
                let comparisonRange = try dateRange(comparison, snapshot: snapshot)
                comparisonResolvedRange = comparisonRange
                comparisonLabel = displayScope(comparison, snapshot: snapshot, range: comparisonRange)
                let rows = request.tool == .expenses ? expenses(comparison, snapshot: snapshot, range: comparisonRange) : incomes(comparison, snapshot: snapshot, range: comparisonRange)
                let previous = rows.reduce(0) { $0 + $1.amount }
                let current = result.metrics.first(where: { $0.label == "Total" })?.value ?? 0
                result.metrics.append(.init(label: "Comparison total", value: previous))
                result.metrics.append(.init(label: "Difference", value: current - previous))
                if previous != 0 { result.metrics.append(.init(label: "Change percent", value: (current - previous) / abs(previous) * 100, unit: .percent)) }
            }
            var filters: [String] = []
            if let id = request.cardID { filters.append("card: " + (snapshot.cards.first { $0.id == UUID(uuidString: id) }?.name ?? id)) }
            if let id = request.categoryID { filters.append("category: " + (snapshot.categories.first { $0.id == UUID(uuidString: id) }?.name ?? id)) }
            if let id = request.budgetID { filters.append("budget: " + (snapshot.budgets.first { $0.id == UUID(uuidString: id) }?.name ?? id)) }
            if let search = request.search { filters.append("text: " + search) }
            result.appliedFilters = filters.isEmpty ? nil : filters.joined(separator: "; ")
            result.presentation = presentation(for: result, request: request, snapshot: snapshot, range: range, comparisonLabel: comparisonLabel, comparisonRange: comparisonResolvedRange)
            return result
        } catch let error as RequestError {
            return MarinaDataResult(status: "invalidRequest", scope: workspace.name, explanation: error.message)
        }
    }

    /// Reload one consistent prefix so changed data cannot create duplicates or mismatched totals.
    func loadMore(presentation previous: MarinaPresentation) throws -> MarinaDataResult {
        guard let pagination = previous.pagination, pagination.workspaceID == workspace.id else {
            return .init(status: "invalidRequest", scope: workspace.name, explanation: "This result belongs to a different workspace or has no more records.")
        }
        var request = pagination.request
        request.offset = 0
        request.limit = pagination.visibleCount + 5
        let frozenContext = MarinaPanelHomeContext(dateRange: nil,
                                                    excludeFuturePlannedExpensesFromCalculations: pagination.excludeFuturePlanned,
                                                    excludeFutureVariableExpensesFromCalculations: pagination.excludeFutureVariable)
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: modelContext, homeContext: frozenContext,
                                               now: pagination.calculationDate, defaultBudgetingPeriod: defaultBudgetingPeriod)
        var result = try service.execute(request)
        if var presentation = result.presentation {
            presentation.id = previous.id
            let oldPrefix = Array(presentation.records.prefix(previous.records.count))
            let priorChart = previous.chartPoints.filter { $0.id != "remaining-groups" }
            let refreshedChart = Array(presentation.chartPoints.filter { $0.id != "remaining-groups" }.prefix(priorChart.count))
            presentation.isUpdated = previous.isUpdated || oldPrefix != previous.records || refreshedChart != priorChart || presentation.metrics != previous.metrics || presentation.totalCount != previous.totalCount
            result.presentation = presentation
        }
        return result
    }

    private func presentation(for result: MarinaDataResult, request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?, comparisonLabel: String?, comparisonRange: HomeQueryDateRange?) -> MarinaPresentation? {
        guard result.status == "success" || result.status == "empty" || result.status == "candidates" else { return nil }
        let card = snapshot.cards.first { $0.id == UUID(uuidString: request.cardID ?? "") }
        var operation = request.operation
        // These are structured query fields, never interpretations of the user's wording.
        if request.tool == .findRecords { operation = .inventory }
        else if request.periodUnit != nil { operation = .trend }
        else if request.comparisonFilter != nil || request.comparisonPeriod != nil || request.comparisonStartDate != nil || request.comparisonAllTime { operation = .comparison }
        else if request.grouping != .none && operation != .share { operation = .ranking }
        let rows: [MarinaPresentation.Record] = result.records.map { record in
            let variable = snapshot.variableExpenses.first { $0.id == UUID(uuidString: record.id) }
            let planned = snapshot.plannedExpenses.first { $0.id == UUID(uuidString: record.id) }
            let rowCategory = variable?.category ?? planned?.category
            let usesPresetRow = request.purpose == .upcomingPresets || (request.tool == .findRecords && record.kind == "preset")
            let preset = usesPresetRow ? snapshot.presets.first { $0.id == (planned?.sourcePresetID ?? UUID(uuidString: record.id)) } : nil
            let presetSnapshot: MarinaPresentation.PresetSnapshot? = preset.map { preset in
                .init(id: preset.id.uuidString, title: preset.title, plannedAmount: preset.plannedAmount,
                      schedule: PresetScheduleFormatter.humanReadableSchedule(for: preset),
                      assignedBudgetCount: snapshot.budgets.filter { ($0.presetLinks ?? []).contains { $0.preset?.id == preset.id } }.count)
            }
            return .init(id: record.id, kind: record.kind, title: record.title, date: record.date, amount: record.amount,
                         detail: (variable != nil || planned != nil) ? nil : record.detail,
                         categoryName: rowCategory?.name ?? ((variable != nil || planned != nil) ? "Uncategorized" : nil),
                         categoryColorHex: rowCategory?.hexColor, cardName: variable?.card?.name ?? planned?.card?.name,
                         plannedAmount: planned?.plannedAmount, actualAmount: planned?.actualAmount, preset: presetSnapshot)
        }
        var title: String
        switch request.tool {
        case .expenses: title = request.expenseMeasure == .planned || request.scope == .planned ? "Planned spending" : "Spending"
        case .income: title = request.state == .planned ? "Planned income" : request.state == .actual ? "Received income" : "Income"
        case .budgetSummary: title = "Budget overview"
        case .accounts: title = "Account balances"
        case .findRecords: title = result.status == "candidates" ? "Which did you mean?" : "Matching records"
        }
        if operation == .transactions { title = request.tool == .income ? "Income records" : request.limit == 1 && request.sort == .largest ? "Largest expense" : "Expenses" }
        if operation == .ranking { title = "\(request.tool == .income ? "Income" : "Spending") by \(request.grouping.rawValue)" }
        if operation == .trend { title = request.tool == .budgetSummary ? "Savings over time" : request.tool == .income ? "Income over time" : "Spending over time" }
        if operation == .comparison { title = request.tool == .income ? "Income comparison" : "Spending comparison" }
        var metrics = result.metrics.filter { $0.label == "Total" }
        if request.tool == .budgetSummary {
            let labels = request.hypotheticalSpending == nil ? ["Remaining room", "Safe spend today", "Projected savings"] : ["Hypothetical additional spending", "Projected savings after hypothetical spending"]
            metrics = result.metrics.filter { labels.contains($0.label) }
        } else if request.tool == .accounts { metrics = result.metrics.filter { $0.label.hasSuffix("current balance") || $0.label.hasSuffix("current reconciliation balance") } }
        if operation == .comparison { metrics = result.metrics.filter { ["Total", "Comparison total", "Difference", "Change percent"].contains($0.label) } }
        var chartPoints: [MarinaPresentation.ChartPoint]
        if operation == .comparison {
            chartPoints = result.metrics.filter { ["Total", "Comparison total"].contains($0.label) }.map {
                .init(id: $0.label, label: $0.label == "Total" ? displayScope(request, snapshot: snapshot, range: range) : comparisonLabel ?? "Compared period", value: $0.value)
            }
        } else if [.ranking, .share, .trend].contains(operation) {
            chartPoints = result.records.compactMap { record in
                if request.tool == .budgetSummary && operation == .trend && record.kind != "savingsPeriod" { return nil }
                guard let amount = record.amount else { return nil }
                let color = snapshot.categories.first { $0.name == record.title }?.hexColor
                let label: String
                if (record.kind == "period" || record.kind == "savingsPeriod"), let date = presentationDate(record.id) { label = date.formatted(date: .abbreviated, time: .omitted) }
                else { label = record.title }
                return .init(id: record.id, label: label, value: amount, colorHex: color, date: (record.kind == "period" || record.kind == "savingsPeriod") ? record.id : record.date)
            }
        } else { chartPoints = [] }
        if operation == .trend, request.tool == .expenses, let unit = request.periodUnit, let range {
            let selected = expenses(request, snapshot: snapshot, range: range)
            let periods = periodRanges(unit, range: range)
            for index in chartPoints.indices {
                guard let period = periods.first(where: { dateText($0.startDate) == chartPoints[index].id }) else { continue }
                let groups = Dictionary(grouping: selected.filter { contains($0.date, period) }, by: \.category)
                chartPoints[index].slices = groups.keys.sorted().map { category in
                    .init(name: category, colorHex: snapshot.categories.first { $0.name == category }?.hexColor ?? "#808080",
                          amount: groups[category, default: []].reduce(0) { $0 + $1.amount })
                }
            }
        }
        if operation == .share, result.nextOffset != nil, let total = result.metrics.first(where: { $0.label == "Total" })?.value {
            let remainder = total - chartPoints.reduce(0) { $0 + $1.value }
            chartPoints.append(.init(id: "remaining-groups", label: "Other", value: remainder))
        }
        var frozen = request
        frozen.relativePeriod = nil
        if comparisonLabel != nil {
            frozen.comparisonPeriod = nil
            frozen.comparisonStartDate = comparisonRange.map { dateText($0.startDate) }
            frozen.comparisonEndDate = comparisonRange.map { dateText($0.endDate) }
            frozen.comparisonAllTime = comparisonRange == nil
        }
        if let range { frozen.startDate = dateText(range.startDate); frozen.endDate = dateText(range.endDate); frozen.allTime = false }
        else { frozen.allTime = true }
        let canPage = result.nextOffset != nil && [.transactions, .inventory, .ranking, .share, .trend].contains(operation) && !(operation == .transactions && request.limit == 1)
        let qualifier: String?
        if request.tool == .expenses {
            switch request.expenseMeasure {
            case .budgetImpact:
                let selected = expenses(request, snapshot: snapshot, range: range)
                let includesPlanned = selected.contains { $0.kind == "plannedExpense" }
                let adjusted = selected.contains { row in
                    if let expense = snapshot.variableExpenses.first(where: { $0.id == row.id }) { return abs(row.amount - expense.amount) > 0.005 }
                    if let expense = snapshot.plannedExpenses.first(where: { $0.id == row.id }) { return abs(row.amount - (expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount)) > 0.005 }
                    return false
                }
                let notes = [includesPlanned ? "Includes planned expenses." : nil, adjusted ? "Reflects your share after credits, splits and savings offsets." : nil].compactMap { $0 }.joined(separator: " ")
                qualifier = notes.isEmpty ? nil : notes
            case .planned: qualifier = "Planned amounts."
            case .actual: qualifier = "Recorded amounts."
            case .ledger: qualifier = "Ledger amounts, including credits and adjustments."
            case .spending: qualifier = "Debit spending."
            }
        } else if request.purpose == .budgetPace {
            qualifier = "Uses budget-impact spending, including planned amounts for unrecorded expenses due by today."
        } else { qualifier = nil }
        func value(_ label: String) -> Double { result.metrics.first { $0.label == label }?.value ?? 0 }
        var canonical = frozen
        canonical.offset = 0; canonical.limit = 0; canonical.forcePresentation = nil
        canonical.operation = operation
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let identity = (try? encoder.encode(canonical)).flatMap { String(data: $0, encoding: .utf8) }.map { workspace.id.uuidString + ":futurePlannedExcluded=\(!request.includeFuture && (homeContext?.excludeFuturePlannedExpensesFromCalculations ?? false)):futureVariableExcluded=\(!request.includeFuture && (homeContext?.excludeFutureVariableExpensesFromCalculations ?? false)):" + $0 }
        let incomeProgress: MarinaPresentation.IncomeProgressSnapshot? = request.purpose == .incomeProgress ? .init(actual: value("Actual income"), planned: value("Planned income")) : nil
        let budgetPace: MarinaPresentation.BudgetPaceSnapshot? = request.purpose == .budgetPace ? .init(actual: value("Pace actual spending"), expected: value("Expected spending by now"), planned: value("Planned spending"), difference: value("Spending pace difference"), elapsedPercent: value("Elapsed period percent") / 100) : nil
        if request.purpose == .incomeProgress { title = "Income progress"; metrics = result.metrics.filter { ["Actual income", "Planned income"].contains($0.label) } }
        if request.purpose == .budgetPace { title = "Budget pace"; metrics = result.metrics.filter { ["Pace actual spending", "Expected spending by now", "Spending pace difference"].contains($0.label) } }
        if request.purpose == .upcomingPresets { title = "Upcoming preset expenses" }
        return .init(id: UUID().uuidString, purpose: request.purpose, forcePresentation: request.forcePresentation, identityKey: identity,
                     topicKey: [request.tool.rawValue, request.purpose?.rawValue ?? "", operation.rawValue, request.grouping.rawValue].joined(separator: ":"),
                     incomeProgress: incomeProgress, budgetPace: budgetPace, operation: operation, title: title, scopeLabel: displayScope(request, snapshot: snapshot, range: range), qualifier: qualifier,
                     metrics: metrics, records: operation == .summary || operation == .comparison ? [] : rows,
                     chartPoints: chartPoints, card: card.map { .init(id: $0.id.uuidString, name: $0.name, theme: $0.theme, effect: $0.effect) },
                     totalCount: result.totalCount,
                     pagination: canPage ? .init(workspaceID: workspace.id, request: frozen, visibleCount: request.offset + result.records.count, calculationDate: now, excludeFuturePlanned: homeContext?.excludeFuturePlannedExpensesFromCalculations ?? false, excludeFutureVariable: homeContext?.excludeFutureVariableExpensesFromCalculations ?? false) : nil,
                     isEmpty: result.status == "empty" && (request.tool == .expenses || request.tool == .income || request.tool == .findRecords))
    }

    private func presentationDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func displayScope(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> String {
        var names: [String] = []
        if let card = snapshot.cards.first(where: { $0.id == UUID(uuidString: request.cardID ?? "") }) { names.append(card.name) }
        if let category = snapshot.categories.first(where: { $0.id == UUID(uuidString: request.categoryID ?? "") }) { names.append(category.name) }
        if request.categoryID == "uncategorized" { names.append("Uncategorized") }
        if let budget = snapshot.budgets.first(where: { $0.id == UUID(uuidString: request.budgetID ?? "") }) { names.append(budget.name) }
        if let account = snapshot.savingsAccounts.first(where: { $0.id == UUID(uuidString: request.accountID ?? "") }) { names.append(account.name) }
        if let account = snapshot.reconciliationAccounts.first(where: { $0.id == UUID(uuidString: request.accountID ?? "") }) { names.append(account.name) }
        if let search = request.search { names.append(search) }
        if names.isEmpty { names.append(workspace.name) }
        names.append(range.map { friendlyRange($0) } ?? "All time")
        return names.joined(separator: " · ")
    }

    private func friendlyRange(_ range: HomeQueryDateRange) -> String {
        let formatter = DateFormatter()
        if let month = calendar.dateInterval(of: .month, for: range.startDate), calendar.isDate(month.start, inSameDayAs: range.startDate), calendar.isDate(month.end.addingTimeInterval(-1), inSameDayAs: range.endDate) {
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: range.startDate)
        }
        formatter.dateStyle = .medium
        if calendar.isDate(range.startDate, inSameDayAs: range.endDate) { return formatter.string(from: range.startDate) }
        return "\(formatter.string(from: range.startDate)) – \(formatter.string(from: range.endDate))"
    }

    private struct RequestError: Error { let message: String }
    private struct Row {
        let id: UUID
        let kind: String
        let title: String
        let date: Date
        let amount: Double
        let card: String
        let category: String
    }

    private func validate(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot) throws {
        func check(_ value: String?, ids: [UUID], label: String) throws {
            guard let value else { return }
            guard let id = UUID(uuidString: value), ids.contains(id) else {
                throw RequestError(message: "Unknown \(label) in the current workspace. Use findRecords to resolve the name; never omit this filter as a fallback.")
            }
        }
        try check(request.presetID, ids: snapshot.presets.map(\.id), label: "preset")
        try check(request.cardID, ids: snapshot.cards.map(\.id), label: "card")
        if request.categoryID != "uncategorized" { try check(request.categoryID, ids: snapshot.categories.map(\.id), label: "category") }
        try check(request.budgetID, ids: snapshot.budgets.map(\.id), label: "budget")
        try check(request.accountID, ids: snapshot.savingsAccounts.map(\.id) + snapshot.reconciliationAccounts.map(\.id), label: "account")
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw RequestError(message: message) } }
        try require(request.purpose != .budgetPace || request.tool == .budgetSummary, "Budget pace requires budgetSummary.")
        try require(request.purpose != .incomeProgress || request.tool == .income, "Income progress requires income.")
        try require(request.purpose != .upcomingPresets || request.tool == .expenses, "Upcoming presets require expenses.")
        try require(request.purpose == nil || (request.grouping == .none && request.periodUnit == nil && request.comparisonFilter == nil && request.comparisonPeriod == nil && request.comparisonStartDate == nil && !request.comparisonAllTime), "Choose an analytical purpose or a grouped, trend, or comparison operation.")
        if request.purpose == .budgetPace && request.budgetID == nil {
            let range = try dateRange(request, snapshot: snapshot)
            let matches = snapshot.budgets.filter { budget in range.map { budget.startDate <= $0.endDate && budget.endDate >= $0.startDate } ?? false }
            try require(matches.count <= 1, "Multiple budgets overlap this period. Ask which budget to use and provide its budgetID.")
        }
        try require(request.operation != .comparison || request.comparisonFilter != nil || request.comparisonAllTime || request.comparisonPeriod != nil || request.comparisonStartDate != nil, "A comparison requires a second target and date selection.")
        try require(request.operation != .trend || request.periodUnit != nil, "A time series requires a period unit.")
        try require((request.operation != .ranking && request.operation != .share) || request.grouping != .none, "A ranking or share breakdown requires a grouping dimension.")
        try require(!(request.allTime && request.budgetID != nil), "A selected budget has its own finite date range.")
        try require(!(request.allTime && (request.startDate != nil || request.endDate != nil)), "Choose allTime or an explicit date range, not both.")
        try require(request.tool == .findRecords || request.recordKind == nil, "recordKind is only supported by findRecords.")
        try require(request.tool == .expenses || request.presetID == nil, "Preset filtering is only supported for expenses.")
        try require(request.tool == .accounts || request.accountID == nil, "Account filtering is only supported by accounts.")
        try require(request.tool == .budgetSummary || request.hypotheticalSpending == nil, "Spending scenarios require budgetSummary.")
        try require(request.tool == .expenses || request.expenseMeasure == .budgetImpact, "Expense measures require expenses.")
        try require(request.tool == .expenses || request.tool == .income || request.grouping == .none, "Grouping requires expenses or income.")
        try require(request.tool == .expenses || request.tool == .budgetSummary || request.categoryID == nil, "Category filtering is unsupported for this tool.")
        try require(request.tool == .expenses || request.tool == .income || request.purpose == .budgetPace || request.cardID == nil, "Card filtering requires expenses or income.")
        try require(request.tool == .expenses || request.tool == .income || request.tool == .budgetSummary || request.budgetID == nil, "Budget filtering is unsupported for this tool.")
        try require(request.tool != .budgetSummary || request.search == nil, "Resolve a budget name with findRecords, then provide budgetID.")
        try require(request.tool != .accounts || request.search == nil, "Resolve an account name with findRecords, then provide accountID.")
        try require(request.periodUnit == nil || !request.allTime, "Period aggregation requires a finite date range.")
        try require(request.periodUnit == nil || request.grouping == .none, "Choose period aggregation or grouping, not both.")
        try require(request.tool != .accounts || request.periodUnit == nil, "Use budgetSummary for savings period averages; accounts returns ledger balances and activity.")
        try require(request.tool != .budgetSummary || !request.allTime, "Budget summaries require a finite date range.")
        try require(request.tool == .expenses || request.tool == .income || (!request.comparisonAllTime && request.comparisonPeriod == nil && request.comparisonStartDate == nil && request.comparisonEndDate == nil && request.comparisonFilter == nil), "Date comparisons require expenses or income.")
        if let spending = request.hypotheticalSpending, !spending.isFinite || spending < 0 { throw RequestError(message: "Hypothetical spending must be a finite nonnegative amount.") }
        guard request.offset >= 0, request.limit > 0 else { throw RequestError(message: "Offset must be nonnegative and limit must be positive.") }
    }

    private func dateRange(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot) throws -> HomeQueryDateRange? {
        if let period = request.relativePeriod {
            guard request.startDate == nil, request.endDate == nil, !request.allTime else {
                throw RequestError(message: "Choose one relative period or explicit dates, not both.")
            }
            var explicit = request
            explicit.relativePeriod = nil
            var selection = explicit
            // Explicit period selection uses the Home/default period, even for accounts
            // whose omitted dates intentionally mean all ledger history.
            selection.tool = .expenses
            let selected = try dateRange(selection, snapshot: snapshot)
                ?? HomeQueryDateRange(startDate: calendar.startOfDay(for: now), endDate: endOfDay(now))
            let resolved: HomeQueryDateRange
            switch period {
            case .selectedPeriod: return selected
            case .previousPeriod:
                let end = selected.startDate.addingTimeInterval(-0.001)
                let standard = defaultBudgetingPeriod.defaultRange(containing: selected.startDate, calendar: calendar)
                if calendar.isDate(selected.startDate, inSameDayAs: standard.start),
                   calendar.isDate(selected.endDate, inSameDayAs: standard.end) {
                    let previous = defaultBudgetingPeriod.defaultRange(containing: end, calendar: calendar)
                    resolved = .init(startDate: previous.start, endDate: endOfDay(previous.end))
                } else {
                    let days = (calendar.dateComponents([.day], from: selected.startDate, to: selected.endDate).day ?? 0) + 1
                    let start = calendar.date(byAdding: .day, value: -days, to: selected.startDate) ?? end
                    resolved = .init(startDate: start, endDate: end)
                }
            case .currentMonth, .previousMonth:
                let anchor = period == .previousMonth ? (calendar.date(byAdding: .month, value: -1, to: now) ?? now) : now
                guard let interval = calendar.dateInterval(of: .month, for: anchor) else { throw RequestError(message: "Unable to resolve this calendar month.") }
                resolved = .init(startDate: interval.start, endDate: interval.end.addingTimeInterval(-0.001))
            case .yearToDate:
                guard let interval = calendar.dateInterval(of: .year, for: now) else { throw RequestError(message: "Unable to resolve this calendar year.") }
                resolved = .init(startDate: interval.start, endDate: endOfDay(now))
            case .nextSevenDays:
                resolved = .init(startDate: calendar.startOfDay(for: now), endDate: endOfDay(calendar.date(byAdding: .day, value: 6, to: now) ?? now))
            }
            explicit.startDate = dateText(resolved.startDate)
            explicit.endDate = dateText(resolved.endDate)
            return try dateRange(explicit, snapshot: snapshot)
        }
        if request.allTime { return nil }
        if request.startDate != nil || request.endDate != nil {
            guard let startText = request.startDate, let endText = request.endDate,
                  let start = parseDate(startText), let end = parseDate(endText), start <= end else {
                throw RequestError(message: "Provide both inclusive dates as yyyy-MM-dd, with start on or before end.")
            }
            if let budget = snapshot.budgets.first(where: { $0.id == UUID(uuidString: request.budgetID ?? "") }) {
                let clippedStart = max(start, calendar.startOfDay(for: budget.startDate))
                let clippedEnd = min(endOfDay(end), endOfDay(budget.endDate))
                guard clippedStart <= clippedEnd else { throw RequestError(message: "Requested dates do not overlap the selected budget.") }
                return .init(startDate: clippedStart, endDate: clippedEnd)
            }
            return HomeQueryDateRange(startDate: start, endDate: endOfDay(end))
        }
        if let budget = snapshot.budgets.first(where: { $0.id.uuidString.caseInsensitiveCompare(request.budgetID ?? "") == .orderedSame }) {
            return HomeQueryDateRange(startDate: calendar.startOfDay(for: budget.startDate), endDate: endOfDay(budget.endDate))
        }
        if request.tool == .findRecords || request.tool == .accounts { return nil }
        if let range = homeContext?.dateRange { return HomeQueryDateRange(startDate: calendar.startOfDay(for: range.startDate), endDate: endOfDay(range.endDate)) }
        let period = defaultBudgetingPeriod.defaultRange(containing: now, calendar: calendar)
        return HomeQueryDateRange(startDate: calendar.startOfDay(for: period.start), endDate: endOfDay(period.end))
    }

    private func findRecords(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot) -> MarinaDataResult {
        var records: [MarinaDataResult.Record] = [.init(id: workspace.id.uuidString, kind: "workspace", title: workspace.name, detail: workspace.hexColor)]
        records += snapshot.cards.map { .init(id: $0.id.uuidString, kind: "card", title: $0.name, detail: "\($0.theme) / \($0.effect)") }
        records += snapshot.categories.map { .init(id: $0.id.uuidString, kind: "category", title: $0.name, detail: $0.hexColor) }
        records.append(.init(id: "uncategorized", kind: "category", title: "Uncategorized"))
        records += snapshot.budgets.map { .init(id: $0.id.uuidString, kind: "budget", title: $0.name, detail: "\(dateText($0.startDate)) through \(dateText($0.endDate))") }
        records += snapshot.presets.map { .init(id: $0.id.uuidString, kind: "preset", title: $0.title, amount: $0.plannedAmount, detail: $0.isArchived ? "Archived" : "Active") }
        records += snapshot.savingsAccounts.map { .init(id: $0.id.uuidString, kind: "savingsAccount", title: $0.name) }
        records += snapshot.reconciliationAccounts.map { .init(id: $0.id.uuidString, kind: "reconciliationAccount", title: $0.name) }
        records += Set(snapshot.incomes.map(\.source)).sorted().map { .init(id: $0, kind: "incomeSource", title: $0) }
        records += Set(snapshot.variableExpenses.map(\.descriptionText)).sorted().map { .init(id: $0, kind: "merchant", title: $0) }
        if let kind = request.recordKind, request.search == nil { records = records.filter { $0.kind == kind } }
        if let search = request.search, !search.isEmpty { records = records.filter { matches($0.title, search) } }
        var result = page(records, request: request, scope: workspace.name)
        result.metrics = [.init(label: "Matching record count", value: Double(records.count), unit: .number)]
        if request.recordKind == "preset" {
            result.metrics.append(.init(label: "Total preset planned amounts", value: records.reduce(0) { $0 + ($1.amount ?? 0) }))
        }
        if request.search != nil && records.count > 1 {
            result.status = "candidates"
            result.explanation = "Multiple records match. Clarify the intended kind and record before applying an ambiguous name filter."
        }
        return result
    }

    private func expenses(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [Row] {
        let budget = snapshot.budgets.first { $0.id.uuidString.caseInsensitiveCompare(request.budgetID ?? "") == .orderedSame }
        let budgetCards = Set((budget?.cardLinks ?? []).compactMap { $0.card?.id })
        func accepts(card: Card?, category: Category?, title: String, date: Date) -> Bool {
            guard contains(date, range) else { return false }
            if let budget, (!budgetCards.contains(card?.id ?? UUID()) || date < calendar.startOfDay(for: budget.startDate) || date > endOfDay(budget.endDate)) { return false }
            if let id = request.cardID, card?.id != UUID(uuidString: id) { return false }
            if let id = request.categoryID {
                if id == "uncategorized" { if category != nil { return false } }
                else if category?.id != UUID(uuidString: id) { return false }
            }
            if let search = request.search, !matches(title, search) { return false }
            return true
        }
        var rows: [Row] = []
        if request.scope != .planned && request.state != .planned && request.presetID == nil && request.expenseMeasure != .planned {
            rows += (request.includeFuture ? snapshot.variableExpenses : snapshot.homeCalculationVariableExpenses).filter { accepts(card: $0.card, category: $0.category, title: $0.descriptionText, date: $0.transactionDate) }.map {
                Row(id: $0.id, kind: "variableExpense", title: $0.descriptionText, date: $0.transactionDate, amount: variableAmount($0, measure: request.expenseMeasure), card: $0.card?.name ?? "No card", category: $0.category?.name ?? "Uncategorized")
            }
        }
        if request.scope != .variable {
            rows += (request.includeFuture ? snapshot.homePlannedExpenses : snapshot.homeCalculationPlannedExpenses).filter {
                accepts(card: $0.card, category: $0.category, title: $0.title, date: $0.expenseDate)
                && (request.purpose != .upcomingPresets || ($0.sourcePresetID != nil && $0.actualAmount == 0))
                && (request.presetID == nil || $0.sourcePresetID == UUID(uuidString: request.presetID ?? ""))
                && (budget == nil || $0.sourceBudgetID == budget?.id)
                && ((request.state != .actual && request.expenseMeasure != .actual) || $0.actualAmount > 0)
            }.map {
                Row(id: $0.id, kind: "plannedExpense", title: $0.title, date: $0.expenseDate,
                    amount: plannedAmount($0, measure: request.state == .planned ? .planned : request.expenseMeasure), card: $0.card?.name ?? "No card", category: $0.category?.name ?? "Uncategorized")
            }
        }
        return rows
    }

    private func incomes(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [Row] {
        snapshot.incomes.filter {
            contains($0.date, range)
            && (request.state == .all || $0.isPlanned == (request.state == .planned))
            && (request.cardID == nil || $0.card?.id == UUID(uuidString: request.cardID ?? ""))
            && (request.search == nil || matches($0.source, request.search ?? ""))
        }.map { Row(id: $0.id, kind: "income", title: $0.source, date: $0.date, amount: $0.amount, card: $0.card?.name ?? "No card", category: $0.isPlanned ? "Planned" : "Actual") }
    }

    private func summarize(_ rows: [Row], request: MarinaDataRequest, range: HomeQueryDateRange?) -> MarinaDataResult {
        let total = rows.reduce(0) { $0 + $1.amount }
        var records: [MarinaDataResult.Record]
        if let unit = request.periodUnit, let range {
            let periods = periodRanges(unit, range: range)
            records = periods.map { period in
                let matching = rows.filter { contains($0.date, period) }
                return .init(id: dateText(period.startDate), kind: "period", title: "\(dateText(period.startDate)) through \(dateText(period.endDate))", amount: matching.reduce(0) { $0 + $1.amount }, detail: "Count: \(matching.count)")
            }
        } else if request.grouping == .none {
            records = sorted(rows, sort: request.sort).map { .init(id: $0.id.uuidString, kind: $0.kind, title: $0.title, date: dateText($0.date), amount: $0.amount, detail: "\($0.card) · \($0.category)") }
        } else {
            let groups = Dictionary(grouping: rows) { row in
                switch request.grouping { case .card: row.card; case .category: row.category; default: row.title }
            }
            records = groups.map { key, rows in
                let amount = rows.reduce(0) { $0 + $1.amount }
                return .init(id: key, kind: "group", title: key, amount: amount, detail: "Count: \(rows.count); share percent: \(total == 0 ? 0 : amount / total * 100)")
            }.sorted { ($0.amount ?? 0) == ($1.amount ?? 0) ? $0.id < $1.id : (request.sort == .smallest ? ($0.amount ?? 0) < ($1.amount ?? 0) : ($0.amount ?? 0) > ($1.amount ?? 0)) }
        }
        var result = page(records, request: request, scope: scopeText(range))
        result.metrics = [.init(label: "Total", value: total), .init(label: "Count", value: Double(rows.count), unit: .number)]
        if let unit = request.periodUnit, let range {
            let count = periodRanges(unit, range: range).count
            if count > 0 { result.metrics.append(.init(label: "Average per \(unit.rawValue)", value: total / Double(count))) }
        }
        if !rows.isEmpty { result.metrics.append(.init(label: "Average per record", value: total / Double(rows.count))) }
        if let range {
            let days = (calendar.dateComponents([.day], from: calendar.startOfDay(for: range.startDate), to: calendar.startOfDay(for: range.endDate)).day ?? 0) + 1
            if days > 0 { result.metrics.append(.init(label: "Average per calendar day", value: total / Double(days))) }
        }
        result.explanation = request.tool == .expenses ? "Expense measure: \(request.expenseMeasure.rawValue). Budget impact applies allocations and savings offsets, credits reduce spending, adjustments have zero impact. Include future override: \(request.includeFuture). Otherwise future-expense calculation preferences apply. Totals include all matching records, not only this page." : "Income state: \(request.state.rawValue). Totals include all matching records, not only this page."
        return result
    }

    private func budgetSummary(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> MarinaDataResult {
        guard let range else { return .init(status: "invalidRequest", scope: workspace.name, explanation: "A budget summary needs a date range.") }
        let budget = snapshot.budgets.first { $0.id == UUID(uuidString: request.budgetID ?? "") }
        let cardIDs = Set((budget?.cardLinks ?? []).compactMap { $0.card?.id })
        let planned = snapshot.homeCalculationPlannedExpenses.filter { expense in
            if request.purpose == .budgetPace {
                if let cardID = request.cardID, expense.card?.id != UUID(uuidString: cardID) { return false }
                if let categoryID = request.categoryID {
                    if categoryID == "uncategorized" { if expense.category != nil { return false } }
                    else if expense.category?.id != UUID(uuidString: categoryID) { return false }
                }
            }
            guard let budget else { return true }
            return expense.sourceBudgetID == budget.id && cardIDs.contains(expense.card?.id ?? UUID())
                && expense.expenseDate >= calendar.startOfDay(for: budget.startDate)
                && expense.expenseDate <= endOfDay(budget.endDate)
        }
        let variable = snapshot.homeCalculationVariableExpenses.filter { expense in
            if request.purpose == .budgetPace {
                if let cardID = request.cardID, expense.card?.id != UUID(uuidString: cardID) { return false }
                if let categoryID = request.categoryID {
                    if categoryID == "uncategorized" { if expense.category != nil { return false } }
                    else if expense.category?.id != UUID(uuidString: categoryID) { return false }
                }
            }
            guard let budget else { return true }
            return cardIDs.contains(expense.card?.id ?? UUID()) && expense.transactionDate >= calendar.startOfDay(for: budget.startDate) && expense.transactionDate <= endOfDay(budget.endDate)
        }
        let incomes = snapshot.incomes.filter { contains($0.date, range) }
        let forecast = MarinaSavingsForecastCalculator.calculate(range: range, incomes: incomes, plannedExpenses: planned, variableExpenses: variable, savingsEntries: snapshot.savingsEntries)
        let safe = SafeSpendTodayCalculator.calculate(
            budgetingPeriod: calendar.isDate(range.startDate, inSameDayAs: range.endDate) ? .daily : .monthly,
            rangeStart: range.startDate, rangeEnd: range.endDate,
            budgets: budget.map { [$0] } ?? snapshot.budgets, categories: snapshot.categories,
            incomes: incomes, plannedExpenses: planned, variableExpenses: variable,
            savingsEntries: snapshot.savingsEntries, now: now, calendar: calendar,
            virtualSpendAmount: request.hypotheticalSpending ?? 0,
            virtualSpendCategoryID: request.categoryID.flatMap(UUID.init(uuidString:)))
        let progress = MarinaBudgetFormulaCalculator.dayProgress(for: range, now: now, calendar: calendar)
        let actualIncome = incomes.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount }
        let plannedIncome = incomes.filter(\.isPlanned).reduce(0) { $0 + $1.amount }
        let plannedTotal = planned.filter { contains($0.expenseDate, range) }.reduce(0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        let recurring = planned.filter { $0.sourcePresetID != nil && contains($0.expenseDate, range) }.reduce(0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        var metrics: [MarinaDataResult.Metric] = [
            .init(label: "Actual income", value: actualIncome), .init(label: "Planned income", value: plannedIncome),
            .init(label: "Planned spending", value: plannedTotal), .init(label: "Actual savings", value: forecast.actualSavings),
            .init(label: "Projected savings", value: forecast.projectedSavings), .init(label: "Gap to projected savings", value: forecast.gapToProjected),
            .init(label: "Remaining room", value: safe.periodRemainingRoom), .init(label: "Unclamped remaining room", value: safe.basePeriodRoom),
            .init(label: "Safe spend today", value: safe.safeToSpendToday), .init(label: "Actual spend so far", value: safe.actualSpendSoFar),
            .init(label: "Remaining planned spending", value: safe.plannedSpendingRemaining), .init(label: "Recurring commitments", value: recurring)
        ]
        let toDate = HomeQueryDateRange(startDate: range.startDate, endDate: min(endOfDay(now), range.endDate))
        let actualToDate = now < range.startDate ? 0 : planned.filter { contains($0.expenseDate, toDate) }.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) } + variable.filter { contains($0.transactionDate, toDate) }.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        metrics += [.init(label: "Pace actual spending", value: actualToDate), .init(label: "Elapsed period percent", value: progress.elapsedPercent * 100, unit: .percent), .init(label: "Projected spending", value: safe.actualSpendSoFar + safe.plannedSpendingRemaining),
                    .init(label: "Expected spending by now", value: plannedTotal * progress.elapsedPercent),
                    .init(label: "Spending pace difference", value: actualToDate - plannedTotal * progress.elapsedPercent)]
        if let burn = MarinaBudgetFormulaCalculator.burnRate(actualSpend: actualToDate, elapsedDays: progress.elapsedDays) {
            metrics += [.init(label: "Spending per elapsed day", value: burn), .init(label: "Projected spending at current pace", value: burn * Double(progress.totalDays))]
        }
        if plannedTotal > 0 {
            metrics += [.init(label: "Income coverage percent", value: (actualIncome > 0 ? actualIncome : plannedIncome) / plannedTotal * 100, unit: .percent), .init(label: "Recurring burden percent", value: recurring / plannedTotal * 100, unit: .percent)]
        }
        if let amount = request.hypotheticalSpending {
            metrics += [.init(label: "Hypothetical additional spending", value: amount), .init(label: "Projected savings after hypothetical spending", value: forecast.projectedSavings - amount)]
        }
        let availability = HomeCategoryLimitsAggregator.build(
            budgets: budget.map { [$0] } ?? snapshot.budgets, categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: range.startDate, rangeEnd: range.endDate)
        metrics += [.init(label: "Categories over limit", value: Double(availability.overCount), unit: .number), .init(label: "Categories near limit", value: Double(availability.nearCount), unit: .number)]
        var records: [MarinaDataResult.Record] = availability.metrics.filter { request.categoryID == nil || $0.categoryID == UUID(uuidString: request.categoryID ?? "") }.map { item in
            .init(id: item.categoryID.uuidString, kind: "categoryLimit", title: item.name,
                  amount: item.availableRaw(for: .all),
                  detail: "Active budget: \(availability.activeBudget?.name ?? "None"); maximum: \(item.maxAmount.map(String.init(describing:)) ?? "unlimited"); spent: \(item.spentTotal); status: \(item.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold))")
        }
        if let unit = request.periodUnit {
            let periods = periodRanges(unit, range: range)
            let summaries = periods.map { period in MarinaSavingsForecastCalculator.calculate(range: period, incomes: incomes, plannedExpenses: planned, variableExpenses: variable, savingsEntries: snapshot.savingsEntries) }
            if !summaries.isEmpty {
                metrics += [.init(label: "Average actual savings per \(unit.rawValue)", value: summaries.reduce(0) { $0 + $1.actualSavings } / Double(summaries.count)), .init(label: "Average projected savings per \(unit.rawValue)", value: summaries.reduce(0) { $0 + $1.projectedSavings } / Double(summaries.count))]
                records += zip(periods, summaries).map { period, summary in .init(id: dateText(period.startDate), kind: "savingsPeriod", title: "\(dateText(period.startDate)) through \(dateText(period.endDate))", amount: summary.actualSavings, detail: "Projected savings: \(summary.projectedSavings)") }
            }
        }
        if request.periodUnit != nil { records = records.filter { $0.kind == "savingsPeriod" } }
        var result = page(records, request: request, scope: scopeText(range))
        result.metrics = metrics
        result.explanation = "Financial calculations use existing savings and safe-spend services. Safe spend and remaining room are clamped to zero and may be constrained by category limits. Future-expense calculation preferences apply. Budget income is workspace income for the period. Hypothetical spending does not change stored records."
        return result
    }

    private func accounts(_ request: MarinaDataRequest, snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> MarinaDataResult {
        var records: [MarinaDataResult.Record] = []
        var metrics: [MarinaDataResult.Metric] = []
        let accountID = request.accountID.flatMap(UUID.init(uuidString:))
        if request.scope != .reconciliation {
            for account in snapshot.savingsAccounts where accountID == nil || account.id == accountID {
                let entries = snapshot.savingsEntries.filter { $0.account?.id == account.id }
                let balance = entries.reduce(0) { $0 + $1.amount }
                metrics.append(.init(label: "\(account.name) current balance", value: balance))
                if accountID != nil {
                    records += entries.filter { contains($0.date, range) }.map { .init(id: $0.id.uuidString, kind: "savingsLedgerEntry", title: $0.note.isEmpty ? $0.kindRaw : $0.note, date: dateText($0.date), amount: $0.amount, detail: $0.kindRaw) }
                } else { records.append(.init(id: account.id.uuidString, kind: "savingsAccount", title: account.name, amount: balance)) }
            }
        }
        if request.scope != .savings {
            for account in snapshot.reconciliationAccounts where accountID == nil || account.id == accountID {
                let allocations = snapshot.expenseAllocations.filter { $0.account?.id == account.id }
                let settlements = snapshot.allocationSettlements.filter { $0.account?.id == account.id }
                let balance = allocations.reduce(0) { $0 + max(0, $1.allocatedAmount) } + settlements.reduce(0) { $0 + $1.amount }
                metrics.append(.init(label: "\(account.name) current reconciliation balance", value: balance))
                if accountID != nil {
                    records += allocations.compactMap { allocation in
                        let date = allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate ?? allocation.createdAt
                        guard contains(date, range) else { return nil }
                        return .init(id: allocation.id.uuidString, kind: "expenseAllocation", title: allocation.expense?.descriptionText ?? allocation.plannedExpense?.title ?? "Allocation", date: dateText(date), amount: max(0, allocation.allocatedAmount))
                    }
                    records += settlements.filter { contains($0.date, range) }.map { .init(id: $0.id.uuidString, kind: "reconciliationItem", title: $0.note.isEmpty ? "Settlement" : $0.note, date: dateText($0.date), amount: $0.amount) }
                } else { records.append(.init(id: account.id.uuidString, kind: "reconciliationAccount", title: account.name, amount: balance)) }
            }
        }
        if let search = request.search { records = records.filter { matches($0.title, search) } }
        if accountID != nil {
            let activityTotal = records.reduce(0) { $0 + ($1.amount ?? 0) }
            metrics.append(.init(label: "Selected period activity total", value: activityTotal))
            metrics.append(.init(label: "Selected period activity count", value: Double(records.count), unit: .number))
            if !records.isEmpty { metrics.append(.init(label: "Average per activity record", value: activityTotal / Double(records.count))) }
        }
        records.sort { ($0.date ?? "", $0.id) > ($1.date ?? "", $1.id) }
        var result = page(records, request: request, scope: scopeText(range))
        result.metrics = metrics
        result.explanation = "Balances are current all-time ledger balances; date filters apply to displayed activity only. Savings and reconciliation are separate. A positive reconciliation balance means money is owed to you; a negative balance means you owe money."
        return result
    }

    private func periodRanges(_ unit: MarinaDataRequest.PeriodUnit, range: HomeQueryDateRange) -> [HomeQueryDateRange] {
        let component: Calendar.Component
        switch unit { case .day: component = .day; case .week: component = .weekOfYear; case .month: component = .month; case .quarter: component = .quarter; case .year: component = .year }
        var cursor = range.startDate
        var periods: [HomeQueryDateRange] = []
        while cursor <= range.endDate, let interval = calendar.dateInterval(of: component, for: cursor), interval.end > cursor {
            periods.append(.init(startDate: max(interval.start, range.startDate), endDate: min(interval.end.addingTimeInterval(-0.001), range.endDate)))
            cursor = interval.end
        }
        return periods
    }

    private func variableAmount(_ expense: VariableExpense, measure: MarinaDataRequest.ExpenseMeasure) -> Double {
        switch measure {
        case .budgetImpact: SavingsMathService.variableBudgetImpactAmount(for: expense)
        case .ledger, .actual: expense.ledgerSignedAmount()
        case .spending: expense.spendingAmount()
        case .planned: 0
        }
    }
    private func plannedAmount(_ expense: PlannedExpense, measure: MarinaDataRequest.ExpenseMeasure) -> Double {
        switch measure {
        case .budgetImpact: SavingsMathService.plannedBudgetImpactAmount(for: expense)
        case .planned: expense.plannedAmount
        case .actual: SavingsMathService.grossRecordedActualAmount(for: expense)
        case .ledger, .spending: SavingsMathService.grossEffectiveAmount(for: expense)
        }
    }

    private func page(_ records: [MarinaDataResult.Record], request: MarinaDataRequest, scope: String) -> MarinaDataResult {
        let limit = request.limit
        let page = Array(records.dropFirst(request.offset).prefix(limit))
        let next = request.offset + page.count
        return .init(status: records.isEmpty ? "empty" : "success", scope: scope, records: page, totalCount: records.count, nextOffset: next < records.count ? next : nil)
    }

    private func sorted(_ rows: [Row], sort: MarinaDataRequest.Sort) -> [Row] {
        rows.sorted { lhs, rhs in
            switch sort {
            case .newest: return lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date > rhs.date
            case .oldest: return lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
            case .largest: return lhs.amount == rhs.amount ? lhs.id.uuidString < rhs.id.uuidString : lhs.amount > rhs.amount
            case .smallest: return lhs.amount == rhs.amount ? lhs.id.uuidString < rhs.id.uuidString : lhs.amount < rhs.amount
            }
        }
    }
    private func contains(_ date: Date, _ range: HomeQueryDateRange?) -> Bool { range.map { date >= $0.startDate && date <= $0.endDate } ?? true }
    private func matches(_ value: String, _ search: String) -> Bool { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) }
    private func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
    private func parseDate(_ text: String) -> Date? {
        let formatter = dateFormatter()
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }
    private func dateText(_ date: Date) -> String { dateFormatter().string(from: date) }
    private func endOfDay(_ date: Date) -> Date { (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date).addingTimeInterval(-0.001) }
    private func scopeText(_ range: HomeQueryDateRange?) -> String { workspace.name + (range.map { " · \(dateText($0.startDate)) through \(dateText($0.endDate)) (inclusive)" } ?? " · all dates") }
}
