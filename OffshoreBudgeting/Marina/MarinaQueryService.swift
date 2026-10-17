import Foundation
import SwiftData

/// Swift alone retrieves records and computes amounts. The model never supplies workspace IDs.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class MarinaQueryService {
    private let context: ModelContext
    let workspaceID: UUID
    private let startDate: Date
    private let endDate: Date
    private let calendar: Calendar
    private let defaults: UserDefaults
    private let now: Date
    private(set) var results: [MarinaResult] = []
    private(set) var followUpSummary: String = ""
    private(set) var clarificationMessage: String?
    private(set) var failureMessage: String?
    private var toolCallCount = 0
    private var requiresEntityChoice = false

    func resetResults() { results = []; clarificationMessage = nil; failureMessage = nil; toolCallCount = 0; requiresEntityChoice = false }

    func beginToolCall() throws {
        try Task.checkCancellation()
        toolCallCount += 1
        guard toolCallCount <= 8 else {
            failureMessage = "Marina could not resolve this request. Try asking one question at a time."
            throw MarinaQueryError.toolLimitExceeded
        }
    }

    func clarify(_ message: String) -> String {
        clarificationMessage = message
        return message
    }

    func entityCatalog() throws -> String {
        do {
            var catalog: [String: [String]] = [:]
            for kind in [MarinaEntityKind.card, .category, .budget, .savingsAccount, .reconciliationAccount] {
                catalog[kind.rawValue] = try entities(kind).prefix(10).map { String($0.1.prefix(60)) }
            }
            return String(data: try JSONEncoder().encode(catalog), encoding: .utf8) ?? "{}"
        } catch {
            failureMessage = "Marina could not load workspace names. Please try again."
            throw error
        }
    }

    init(context: ModelContext, workspaceID: UUID, startDate: Date, endDate: Date,
         calendar: Calendar = .current, defaults: UserDefaults = .standard, now: Date = .now) {
        self.context = context; self.workspaceID = workspaceID
        self.startDate = startDate; self.endDate = endDate
        self.calendar = calendar; self.defaults = defaults; self.now = now
    }

    func resolve(_ request: MarinaEntityRequest) throws -> String {
        try Task.checkCancellation()
        let candidates: [(UUID, String)]
        do { candidates = try entities(request.kind) }
        catch { failureMessage = "Database query failed. Please retry."; throw error }
        if normalized(request.name).isEmpty {
            return "Available \(request.kind.rawValue) names: " + candidates.prefix(20).map { "\($0.1) [\($0.0.uuidString)]" }.joined(separator: "; ")
        }
        let matches = candidates.filter { normalized($0.1) == normalized(request.name) }
        guard matches.count == 1 else {
            if matches.isEmpty { let message = "No \(request.kind.rawValue) named \(request.name) exists in this workspace. Available names: \(candidates.prefix(10).map(\.1).joined(separator: ", "))."; clarificationMessage = message; return message }
            let choices = matches.map { "\($0.1) [\($0.0.uuidString)]" }.joined(separator: "; ")
            let message = "\(matches.count) \(request.kind.rawValue) records share the name \(request.name). Which one did you mean? Choices: \(choices)"
            clarificationMessage = message
            requiresEntityChoice = true
            return message
        }
        return "Resolved \(request.kind.rawValue): \(matches[0].1), ID \(matches[0].0.uuidString)."
    }

    func find(_ request: MarinaQueryRequest) throws -> String { try perform(request, statistics: false) }
    func statistics(_ request: MarinaQueryRequest) throws -> String { try perform(request, statistics: true) }

    private func perform(_ request: MarinaQueryRequest, statistics: Bool) throws -> String {
        try Task.checkCancellation()
        do {
            let output = try run(request, statistics: statistics)
            if !requiresEntityChoice { clarificationMessage = nil }
            return output
        }
        catch let error as MarinaQueryError { clarificationMessage = error.localizedDescription; return "Clarification required: " + error.localizedDescription }
        catch { failureMessage = "Database query failed. Please retry."; throw error }
    }

    private func entities(_ kind: MarinaEntityKind) throws -> [(UUID, String)] {
        let id = workspaceID
        switch kind {
        case .card: return try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.workspace?.id == id })).map { ($0.id, $0.name) }
        case .category: return try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.workspace?.id == id })).map { ($0.id, $0.name) }
        case .budget: return try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.workspace?.id == id })).map { ($0.id, $0.name) }
        case .savingsAccount: return try context.fetch(FetchDescriptor<SavingsAccount>(predicate: #Predicate { $0.workspace?.id == id })).map { ($0.id, $0.name) }
        case .reconciliationAccount: return try context.fetch(FetchDescriptor<AllocationAccount>(predicate: #Predicate { $0.workspace?.id == id })).map { ($0.id, $0.name) }
        }
    }
    private func entityID(_ name: String?, selectedID: String? = nil, kind: MarinaEntityKind) throws -> UUID? {
        guard name != nil || selectedID != nil else { return nil }
        let candidates = try entities(kind)
        if let selectedID {
            guard let id = UUID(uuidString: selectedID), let match = candidates.first(where: { $0.0 == id }) else { throw MarinaQueryError.invalid("That \(kind.rawValue) is unavailable in this workspace. Please choose another.") }
            if let name, normalized(match.1) != normalized(name) { throw MarinaQueryError.invalid("The selected \(kind.rawValue) does not match the supplied name. Please clarify.") }
            return id
        }
        let name = name!
        let matches = candidates.filter { normalized($0.1) == normalized(name) }
        guard matches.count == 1 else {
            if !matches.isEmpty { requiresEntityChoice = true }
            throw MarinaQueryError.invalid(matches.isEmpty ? "No \(kind.rawValue) named \(name) in this workspace. Available names: \(candidates.prefix(10).map(\.1).joined(separator: ", "))." : "The name \(name) is ambiguous. Which record did you mean? " + matches.map { "\($0.1) [\($0.0.uuidString)]" }.joined(separator: "; "))
        }
        return matches[0].0
    }
    private func normalized(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    private func date(_ value: String?, fallback: Date) throws -> Date {
        guard let value else { return calendar.startOfDay(for: fallback) }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let result = formatter.date(from: value), formatter.string(from: result) == value else { throw MarinaQueryError.invalid("Which dates did you mean? Please give a start and end date.") }
        return result
    }
    private func run(_ request: MarinaQueryRequest, statistics: Bool) throws -> String {
        var lower = request.metric == .balance ? Date.distantPast : try date(request.startDate, fallback: startDate)
        var lastDay = try date(request.endDate, fallback: endDate)
        guard let initialUpper = calendar.date(byAdding: .day, value: 1, to: lastDay) else { throw MarinaQueryError.invalid("That end date could not be interpreted.") }
        var upper = initialUpper
        if let min = request.minAmount, !min.isFinite { throw MarinaQueryError.invalid("Amount must be finite.") }
        if let max = request.maxAmount, !max.isFinite { throw MarinaQueryError.invalid("Amount must be finite.") }
        if let min = request.minAmount, let max = request.maxAmount, min > max { throw MarinaQueryError.invalid("Minimum amount exceeds maximum.") }
        let cardID = try entityID(request.cardName, selectedID: request.cardID, kind: .card)
        let asksUncategorized = request.categoryName.map { normalized($0) == normalized("Uncategorized") } ?? false
        let asksUnclassified = request.categoryName.map { normalized($0) == normalized("Unclassified") } ?? false
        let storedUncategorized = asksUncategorized && request.categoryID == nil ? try entities(.category).contains(where: { normalized($0.1) == normalized("Uncategorized") }) : false
        if storedUncategorized {
            requiresEntityChoice = true
            throw MarinaQueryError.invalid("Do you mean the stored Uncategorized category or records with no category? Choose the category ID, or ask for Unclassified records.")
        }
        let isUncategorized = request.categoryID == nil && (asksUncategorized || asksUnclassified)
        let categoryID = try entityID(isUncategorized ? nil : request.categoryName, selectedID: request.categoryID, kind: .category)
        let budgetID = try entityID(request.budgetName, selectedID: request.budgetID, kind: .budget)
        var accountID = try entityID(request.accountName, selectedID: request.accountID, kind: request.domain == .savings ? .savingsAccount : .reconciliationAccount)
        if request.metric == .categoryBreakdown && ![MarinaDomain.expenses, .plannedExpenses].contains(request.domain) { throw MarinaQueryError.invalid("Category breakdowns apply only to expenses.") }
        if ![MarinaDomain.expenses, .plannedExpenses, .income].contains(request.domain) && request.state != .all { throw MarinaQueryError.invalid("Planned/actual state applies only to expenses and income.") }
        if request.metric == .ledger && request.domain != .expenses { throw MarinaQueryError.invalid("Signed card ledger totals apply only to variable expenses.") }
        if [.budgetImpact, .owned].contains(request.metric) && ![MarinaDomain.expenses, .plannedExpenses].contains(request.domain) { throw MarinaQueryError.invalid("Owned amount and budget impact apply only to expenses.") }
        if request.domain == .expenses && request.state == .planned { throw MarinaQueryError.invalid("Variable expenses are ledger records. Use plannedExpenses for expected costs.") }
        if request.metric == .balance && (request.text != nil || request.minAmount != nil || request.maxAmount != nil) { throw MarinaQueryError.invalid("Account balance includes every ledger entry. Remove transaction text or amount filters, or ask for filtered period activity.") }
        if request.metric == .balance && ![MarinaDomain.savings, .reconciliation].contains(request.domain) { throw MarinaQueryError.invalid("Balance is supported only for savings and reconciliation accounts.") }
        if (request.accountName != nil || request.accountID != nil) && ![MarinaDomain.savings, .reconciliation].contains(request.domain) { throw MarinaQueryError.invalid("Account filters apply only to savings or reconciliation.") }
        if [MarinaDomain.savings, .reconciliation, .budgets].contains(request.domain) && (request.cardName != nil || request.cardID != nil || request.categoryName != nil || request.categoryID != nil || (request.budgetName != nil || request.budgetID != nil) && request.domain != .budgets) { throw MarinaQueryError.invalid("These filters are not supported for this domain. Ask for an account or period instead.") }
        if request.domain == .income && (request.categoryName != nil || request.categoryID != nil) { throw MarinaQueryError.invalid("Income does not have categories.") }
        let id = workspaceID
        if request.domain == .savings && accountID == nil {
            accountID = try context.fetch(FetchDescriptor<SavingsAccount>(predicate: #Predicate { $0.workspace?.id == id }, sortBy: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)])).first?.id
        }
        let budget = try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.workspace?.id == id })).first { $0.id == budgetID }
        if let budget {
            if request.startDate == nil { lower = calendar.startOfDay(for: budget.startDate) }
            if request.endDate == nil { lastDay = calendar.startOfDay(for: budget.endDate) }
            guard lower <= lastDay, let budgetUpper = calendar.date(byAdding: .day, value: 1, to: lastDay) else { throw MarinaQueryError.invalid("Invalid budget date range.") }
            upper = budgetUpper
        }
        guard lower <= lastDay else { throw MarinaQueryError.invalid("Start date must precede end date.") }
        let budgetCards = Set((budget?.cardLinks ?? []).compactMap { $0.card?.id })
        if [.projectedSavings, .actualSurplus].contains(request.metric) {
            guard statistics && request.domain == .budgets else { throw MarinaQueryError.invalid("Savings outlook metrics require statistics for the budgets domain.") }
            guard request.cardName == nil, request.cardID == nil, request.categoryName == nil, request.categoryID == nil, request.accountName == nil, request.accountID == nil, request.text == nil, request.minAmount == nil, request.maxAmount == nil else { throw MarinaQueryError.invalid("Savings outlook supports a period and optional budget, without transaction filters.") }
            return try savingsOutlook(request, lower: lower, upper: upper, budget: budget, budgetCards: budgetCards)
        }
        let futureKey = "general_\(statistics ? "excludeFuture" : "hideFuture")\(request.domain == .plannedExpenses ? "Planned" : "Variable")Expenses\(statistics ? "FromCalculations" : "")"
        let isExpenseDomain = request.domain == .expenses || request.domain == .plannedExpenses
        let includeFuture = request.includeFuture ?? (isExpenseDomain ? !defaults.bool(forKey: futureKey) : true)
        func accepts(_ date: Date, _ amount: Double, _ title: String, _ card: Card? = nil, _ category: Category? = nil) -> Bool {
            guard date >= lower && date < upper, amount.isFinite else { return false }
            if !includeFuture && calendar.startOfDay(for: date) > calendar.startOfDay(for: now) { return false }
            if let cardID, card?.id != cardID { return false }
            if let categoryID, category?.id != categoryID { return false }
            if isUncategorized && category != nil { return false }
            if let text = request.text, !normalized(title).contains(normalized(text)) { return false }
            if let min = request.minAmount, abs(amount) < min { return false }
            if let max = request.maxAmount, abs(amount) > max { return false }
            return true
        }
        var records: [MarinaRecord] = []
        var labels: [UUID: String] = [:]
        var categoryIDs: [UUID: UUID] = [:]
        switch request.domain {
        case .expenses:
            for item in try context.fetch(FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.workspace?.id == id })) {
                if budget != nil && (!budgetCards.contains(item.card?.id ?? UUID()) || item.transactionDate < calendar.startOfDay(for: budget!.startDate) || calendar.startOfDay(for: item.transactionDate) > calendar.startOfDay(for: budget!.endDate)) { continue }
                let amount: Double
                switch request.metric {
                case .count: amount = item.ledgerDisplayAmount()
                case .ledger: amount = item.ledgerSignedAmount()
                case .budgetImpact: amount = SavingsMathService.variableBudgetImpactAmount(for: item)
                case .owned: amount = item.kind == .debit ? SavingsMathService.ownedAmount(for: item) : item.kind == .credit ? item.ledgerSignedAmount() : 0
                default: amount = statistics ? item.spendingAmount() : item.ledgerSignedAmount()
                }
                if statistics && ![MarinaMetric.ledger, .budgetImpact, .owned].contains(request.metric) && request.metric != .count && item.kind != .debit { continue }
                if accepts(item.transactionDate, amount, item.descriptionText, item.card, item.category) {
                    labels[item.id] = item.category?.name ?? "Uncategorized"
                    categoryIDs[item.id] = item.category?.id
                    records.append(MarinaRecord(id: item.id, domain: .expenses, title: item.descriptionText, date: item.transactionDate, amount: amount, subtitle: "\(item.card?.name ?? "Unassigned") · \(item.kind.rawValue)"))
                }
            }
        case .plannedExpenses:
            for item in try context.fetch(FetchDescriptor<PlannedExpense>(predicate: #Predicate { $0.workspace?.id == id })) {
                if let budget { guard item.sourceBudgetID == budget.id, let card = item.card, budgetCards.contains(card.id), item.expenseDate >= calendar.startOfDay(for: budget.startDate), calendar.startOfDay(for: item.expenseDate) <= calendar.startOfDay(for: budget.endDate) else { continue } }
                if request.state == .actual && item.actualAmount <= 0 { continue }
                if request.state == .planned && item.actualAmount > 0 { continue }
                let amount: Double
                switch request.metric {
                case .budgetImpact: amount = SavingsMathService.plannedBudgetImpactAmount(for: item)
                case .owned: amount = SavingsMathService.ownedEffectiveAmount(for: item)
                default: amount = request.state == .planned ? item.plannedAmount : SavingsMathService.grossEffectiveAmount(for: item)
                }
                if accepts(item.expenseDate, amount, item.title, item.card, item.category) {
                    labels[item.id] = item.category?.name ?? "Uncategorized"
                    categoryIDs[item.id] = item.category?.id
                    records.append(MarinaRecord(id: item.id, domain: .plannedExpenses, title: item.title, date: item.expenseDate, amount: amount, subtitle: item.actualAmount > 0 ? "Recorded planned expense" : "Expected planned expense"))
                }
            }
        case .income:
            for item in try context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.workspace?.id == id })) {
                if request.state != .planned && item.isPlanned && request.state != .all { continue }
                if request.state == .planned && !item.isPlanned { continue }
                // Unqualified statistics use received income, never mix expected and received.
                if statistics && request.state == .all && item.isPlanned { continue }
                if budget != nil && (item.date < calendar.startOfDay(for: budget!.startDate) || calendar.startOfDay(for: item.date) > calendar.startOfDay(for: budget!.endDate)) { continue }
                if accepts(item.date, item.amount, item.source, item.card) { records.append(MarinaRecord(id: item.id, domain: .income, title: item.source, date: item.date, amount: item.amount, subtitle: item.isPlanned ? "Expected income" : "Received income")) }
            }
        case .budgets:
            guard request.metric == .count || !statistics else { throw MarinaQueryError.invalid("For a budget total, specify its income, spending, planned costs, projected savings, or surplus.") }
            for item in try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.workspace?.id == id })) where item.startDate < upper && item.endDate >= lower {
                if let budgetID, item.id != budgetID { continue }
                if let text = request.text, !normalized(item.name).contains(normalized(text)) { continue }
                records.append(MarinaRecord(id: item.id, domain: .budgets, title: item.name, date: item.startDate, amount: 0, subtitle: "Through \(item.endDate.formatted(date: .abbreviated, time: .omitted))"))
            }
        case .savings:
            for item in try context.fetch(FetchDescriptor<SavingsLedgerEntry>(predicate: #Predicate { $0.workspace?.id == id })) {
                if let accountID, item.account?.id != accountID { continue }
                if item.kind == .reconciliationSettlement { continue }
                if accepts(item.date, item.amount, item.note) { records.append(MarinaRecord(id: item.id, domain: .savings, title: item.note.isEmpty ? item.kindRaw : item.note, date: item.date, amount: item.amount, subtitle: item.account?.name ?? "Savings")) }
            }
        case .reconciliation:
            for item in try context.fetch(FetchDescriptor<ExpenseAllocation>(predicate: #Predicate { $0.workspace?.id == id })) {
                if let accountID, item.account?.id != accountID { continue }
                let date = item.expense?.transactionDate ?? item.plannedExpense?.expenseDate ?? item.createdAt
                let title = item.expense?.descriptionText ?? item.plannedExpense?.title ?? "Allocation"
                if accepts(date, max(0, item.allocatedAmount), title) { records.append(MarinaRecord(id: item.id, domain: .reconciliation, title: title, date: date, amount: max(0, item.allocatedAmount), subtitle: item.account?.name ?? "Reconciliation")) }
            }
            for item in try context.fetch(FetchDescriptor<AllocationSettlement>(predicate: #Predicate { $0.workspace?.id == id })) {
                if let accountID, item.account?.id != accountID { continue }
                if accepts(item.date, item.amount, item.note) { records.append(MarinaRecord(id: item.id, domain: .reconciliation, title: item.note, date: item.date, amount: item.amount, subtitle: item.account?.name ?? "Settlement")) }
            }
        }
        records.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        let sum = records.reduce(0) { $0 + $1.amount }
        var points: [MarinaChartPoint] = []
        if statistics && request.metric == .categoryBreakdown {
            // Category identity matters: duplicate names and a stored Uncategorized category
            // must remain distinct from the virtual nil classification, as on Home.
            let groups = Dictionary(grouping: records) { categoryIDs[$0.id]?.uuidString ?? "uncategorized" }
            let names = groups.mapValues { labels[$0[0].id] ?? "Uncategorized" }
            let nameCounts = Dictionary(grouping: names.values, by: { $0 }).mapValues(\.count)
            points = groups.map { key, rows in
                let name = names[key] ?? "Uncategorized"
                let suffix = key == "uncategorized" ? "unclassified" : String(key.suffix(8))
                let label = nameCounts[name, default: 0] > 1 ? "\(name) · \(suffix)" : name
                return MarinaChartPoint(id: key, label: label, value: rows.reduce(0) { $0 + $1.amount }, date: nil)
            }.sorted { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }
        } else if statistics && request.metric == .timeTrend {
            let groups = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            points = groups.map { MarinaChartPoint(id: $0.key.ISO8601Format(), label: $0.key.formatted(date: .abbreviated, time: .omitted), value: $0.value.reduce(0) { $0 + $1.amount }, date: $0.key) }.sorted { $0.date! < $1.date! }
        } else if statistics && request.metric == .comparison {
            guard let comparisonStart = request.comparisonStartDate, let comparisonEnd = request.comparisonEndDate else { throw MarinaQueryError.invalid("Comparison needs an explicit second date range.") }
            var comparison = request; comparison.startDate = comparisonStart; comparison.endDate = comparisonEnd; comparison.metric = .total
            let originalCount = results.count
            _ = try run(comparison, statistics: true)
            let other = results.removeLast()
            assert(results.count == originalCount)
            points = [MarinaChartPoint(id: "current", label: "Selected period", value: sum, date: lower), MarinaChartPoint(id: "comparison", label: "Comparison period", value: other.total ?? 0, date: try date(comparisonStart, fallback: lower))]
        }
        let total = request.metric == .count ? Double(records.count) : request.metric == .average ? (records.isEmpty ? 0 : sum / Double(records.count)) : sum
        let periodLabel = request.metric == .balance ? "Through \(lastDay.formatted(date: .abbreviated, time: .omitted))" : "\(lower.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted))"
        var filters = [periodLabel, "Future records \(includeFuture ? "included" : "excluded")"]
        if request.metric == .comparison, let comparisonStart = request.comparisonStartDate, let comparisonEnd = request.comparisonEndDate {
            let first = try date(comparisonStart, fallback: lower)
            let last = try date(comparisonEnd, fallback: lastDay)
            filters.append("Compared with \(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        for (kind, selectedID) in [(MarinaEntityKind.card, cardID), (.category, categoryID), (.budget, budgetID), (request.domain == .savings ? .savingsAccount : .reconciliationAccount, accountID)] {
            if let selectedID, let name = try entities(kind).first(where: { $0.0 == selectedID })?.1 { filters.append(name) }
        }
        if isUncategorized { filters.append("Uncategorized") }
        if let text = request.text { filters.append("Description contains: " + text) }
        if request.minAmount != nil || request.maxAmount != nil { filters.append("Amount \(request.minAmount.map(String.init(describing:)) ?? "any") to \(request.maxAmount.map(String.init(describing:)) ?? "any")") }
        let baseDefinition = request.domain == .expenses ? (request.metric == .count ? "Card ledger record count (debits, credits, and adjustments)" : request.metric == .ledger ? "Signed ledger activity" : request.metric == .budgetImpact ? "Budget impact after allocations and savings offsets" : request.metric == .owned ? "Owned amount after allocations" : statistics ? "Recorded debit spending" : "Card ledger records") : request.domain == .savings ? (request.metric == .balance ? "Savings balance from ledger through selected end date" : "Savings ledger change during range (not account balance)") : request.domain == .reconciliation ? (request.metric == .balance ? "Reconciliation balance through selected end date" : "Allocations plus signed settlements during range (not lifetime balance)") : request.domain == .income ? (statistics && request.state != .planned ? "Received income" : "Income records") : request.domain == .plannedExpenses ? "Planned costs: recorded actual when positive, otherwise expected amount" : "Budget periods"
        let definition = request.metric == .average ? "Average per record · " + baseDefinition : request.metric == .count ? "Record count · " + baseDefinition : baseDefinition
        let result = MarinaResult(id: UUID().uuidString, title: definition, detail: filters.joined(separator: " · "), createdAt: now, records: records, points: points, total: statistics ? total : nil, count: records.count, metric: request.metric, valueKind: request.metric == .count ? "count" : "currency", chartKind: request.metric == .comparison ? "comparison" : request.metric == .timeTrend ? "timeTrend" : request.metric == .categoryBreakdown ? "categoryBreakdown" : nil)
        try Task.checkCancellation()
        results.append(result)
        // Compact, exact tool output; full records are held by the app for paginated display.
        let summary = "resultID: \(result.id); definition: \(definition); filters: \(result.detail); count: \(records.count); metric: \(request.metric.rawValue); exactValue: \(statistics ? String(total) : "not calculated")"
        var resolvedRequest = request
        let dateFormatter = DateFormatter(); dateFormatter.calendar = Calendar(identifier: .gregorian); dateFormatter.timeZone = calendar.timeZone; dateFormatter.locale = Locale(identifier: "en_US_POSIX"); dateFormatter.dateFormat = "yyyy-MM-dd"
        resolvedRequest.startDate = request.metric == .balance ? nil : dateFormatter.string(from: lower)
        resolvedRequest.endDate = dateFormatter.string(from: lastDay)
        resolvedRequest.includeFuture = includeFuture
        let encodedQuery = try JSONEncoder().encode(MarinaToolQuery(query: resolvedRequest))
        var filterContext = try JSONSerialization.jsonObject(with: encodedQuery) as? [String: Any] ?? [:]
        filterContext.removeValue(forKey: "metric")
        let filterData = try JSONSerialization.data(withJSONObject: filterContext, options: [.sortedKeys])
        followUpSummary = "Previously applied filters: " + String(decoding: filterData, as: UTF8.self)
        let chart = points.prefix(31).map { "\($0.label)=\($0.value)" }.joined(separator: "; ")
        return summary + (chart.isEmpty ? "" : "; chart: \(chart)")
    }
    /// Matches Home savings outlook: planned income minus planned owned costs; actual income
    /// minus effective planned and variable budget impacts, plus manual savings adjustments.
    private func savingsOutlook(_ request: MarinaQueryRequest, lower: Date, upper: Date, budget: Budget?, budgetCards: Set<UUID>) throws -> String {
        let id = workspaceID
        let projected = request.metric == .projectedSavings
        func inRange(_ date: Date) -> Bool {
            guard date >= lower && date < upper else { return false }
            if let budget { return calendar.startOfDay(for: date) >= calendar.startOfDay(for: budget.startDate) && calendar.startOfDay(for: date) <= calendar.startOfDay(for: budget.endDate) }
            return true
        }
        func futureAllowed(_ date: Date, planned: Bool) -> Bool {
            let include = request.includeFuture ?? !defaults.bool(forKey: planned ? "general_excludeFuturePlannedExpensesFromCalculations" : "general_excludeFutureVariableExpensesFromCalculations")
            return include || calendar.startOfDay(for: date) <= calendar.startOfDay(for: now)
        }
        let incomes = try context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.workspace?.id == id })).filter { inRange($0.date) && $0.isPlanned == projected }
        let planned = try context.fetch(FetchDescriptor<PlannedExpense>(predicate: #Predicate { $0.workspace?.id == id })).filter { item in
            guard inRange(item.expenseDate), futureAllowed(item.expenseDate, planned: true) else { return false }
            if let budget { return item.sourceBudgetID == budget.id && item.card.map { budgetCards.contains($0.id) } == true }
            return true
        }
        let variable = try context.fetch(FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.workspace?.id == id })).filter { item in
            inRange(item.transactionDate) && futureAllowed(item.transactionDate, planned: false) && (budget == nil || item.card.map { budgetCards.contains($0.id) } == true)
        }
        let entries = try context.fetch(FetchDescriptor<SavingsLedgerEntry>(predicate: #Predicate { $0.workspace?.id == id })).filter { inRange($0.date) }
        let incomeTotal = incomes.reduce(0) { $0 + $1.amount }
        let plannedTotal = planned.reduce(0) { $0 + (projected ? SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) : SavingsMathService.plannedBudgetImpactAmount(for: $1)) }
        let variableTotal = projected ? 0 : variable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let adjustmentTotal = projected ? 0 : entries.reduce(0) { $0 + SavingsMathService.actualSavingsAdjustmentAmount(for: $1) }
        let total = incomeTotal - plannedTotal - variableTotal + adjustmentTotal
        let title = projected ? "Projected savings from expected income and planned costs" : "Actual surplus using effective costs and manual savings adjustments"
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let lastDay = calendar.date(byAdding: .day, value: -1, to: upper)!
        let detail = "\(lower.formatted(date: .abbreviated, time: .omitted)) – \(lastDay.formatted(date: .abbreviated, time: .omitted)) · \(budget?.name ?? "Workspace") · \(projected ? "Expected data" : "Recorded income; unrecorded planned costs use expected amounts") · Future expense calculations: planned \(request.includeFuture ?? !defaults.bool(forKey: "general_excludeFuturePlannedExpensesFromCalculations") ? "included" : "excluded"), variable \(request.includeFuture ?? !defaults.bool(forKey: "general_excludeFutureVariableExpensesFromCalculations") ? "included" : "excluded")"
        let points = [MarinaChartPoint(id: "income", label: projected ? "Expected income" : "Received income", value: incomeTotal, date: nil), MarinaChartPoint(id: "planned", label: projected ? "Planned owned costs" : "Effective planned costs", value: -plannedTotal, date: nil), MarinaChartPoint(id: "variable", label: "Variable budget impact", value: -variableTotal, date: nil), MarinaChartPoint(id: "adjustments", label: "Manual savings adjustments", value: adjustmentTotal, date: nil)]
        let result = MarinaResult(id: UUID().uuidString, title: title, detail: detail, createdAt: now, records: [], points: points, total: total, count: incomes.count + planned.count + (projected ? 0 : variable.count), metric: request.metric, valueKind: "currency", chartKind: "breakdown")
        try Task.checkCancellation()
        results.append(result)
        var resolved = request; resolved.startDate = formatter.string(from: lower); resolved.endDate = formatter.string(from: lastDay)
        followUpSummary = "Resolved previous query: " + (String(data: try JSONEncoder().encode(MarinaToolQuery(query: resolved)), encoding: .utf8) ?? "")
        return "resultID: \(result.id); definition: \(title); filters: \(detail); exactValue: \(total); income: \(incomeTotal); plannedCosts: \(plannedTotal); variableBudgetImpact: \(variableTotal); manualAdjustments: \(adjustmentTotal). This is period surplus, not the savings account balance."
    }

}
