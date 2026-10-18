import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Serializes SwiftData access on the main actor, even when the model calls tools concurrently.
@available(iOS 26.0, macCatalyst 26.0, *)
@MainActor
final class MarinaToolBridge {
#if DEBUG
    var diagnostics: MarinaTokenDiagnostics?
#endif
    private var service: MarinaReadOnlyDataService?
    private var onResult: (() -> Void)?
    var onStatus: ((MarinaResponseState) -> Void)?
    private var results: [MarinaDataResult] = []
    private var evidence: [(tool: MarinaDataRequest.Tool, verified: Bool, answer: HomeAnswer)] = []
    private var previousPresentations: [MarinaPresentation] = []
    private var calls = 0
    private var requiresClarification = false
    private(set) var requests: [MarinaDataRequest] = []
    var hasResults: Bool { !results.isEmpty }
    var hasFinancialResults: Bool { evidence.contains { $0.tool != .findRecords && $0.verified } }
    var hasInvalidRequest: Bool { results.last?.status == "invalidRequest" }

    func begin(service: MarinaReadOnlyDataService, history: [HomeAnswer] = [], onResult: @escaping () -> Void) {
        previousPresentations = MarinaPresentationDisplayPolicy.previousResults(in: history)
        self.service = service
        self.onResult = onResult
        results = []
        evidence = []
        requests = []
        calls = 0
        requiresClarification = false
    }

    func end() { service = nil; onResult = nil; onStatus = nil }

    func call(_ request: MarinaDataRequest, diagnosticAttempt: Int? = nil) throws -> String {
#if DEBUG
        if let diagnosticAttempt { diagnostics?.mapped(attempt: diagnosticAttempt, request: request) }
        var diagnosticOutput: String?
        var diagnosticStatus = "needsClarification"
        defer {
            if let diagnosticAttempt, let diagnosticOutput {
                diagnostics?.output(attempt: diagnosticAttempt, text: diagnosticOutput, status: diagnosticStatus)
            }
        }
#endif
        try Task.checkCancellation()
        guard let service else { throw CancellationError() }
        calls += 1
        guard calls <= 8 else { throw ToolLimitError() }
        if requiresClarification && request.tool != .findRecords {
            let output = "{\"status\":\"needsClarification\",\"explanation\":\"A lookup found competing records. Ask the person which candidate they mean before reading financial data.\"}"
#if DEBUG
            diagnosticOutput = output
#endif
            return output
        }
        let status: MarinaResponseState
        switch request.tool {
        case .findRecords: status = .readingRecords
        case .expenses: status = .readingExpenses
        case .income: status = .readingIncome
        case .budgetSummary: status = .readingBudget
        case .accounts: status = .readingAccounts
        }
        onStatus?(status)
        requests.append(request)
#if DEBUG
        if let diagnosticAttempt { diagnostics?.database(attempt: diagnosticAttempt) }
#endif
        let result = try service.execute(request)
#if DEBUG
        diagnosticStatus = result.status
#endif
        results.append(result)
        if result.status == "candidates" { requiresClarification = true }
        let card = result.homeAnswer
        let verified = result.status == "success" || result.status == "empty"
        let notice = !verified ? result.explanation.map { [HomeAnswerRow(title: $0, value: "", role: .assumption)] } ?? [] : []
        evidence.append((request.tool, verified, HomeAnswer(queryID: card.queryID, kind: card.kind,
            title: card.title, subtitle: card.subtitle,
            rows: [HomeAnswerRow(title: result.scope, value: "", role: .assumption)] + notice + card.rows,
            explanation: card.explanation)))
        onResult?()
        onStatus?(.responding)
        let display = result.presentation.map {
            MarinaPresentationDisplayPolicy.shouldShow($0, after: previousPresentations + results.dropLast().compactMap(\.presentation)) ? "displayed" : "alreadyShown"
        } ?? "none"
        // Presentation metadata describes app behavior; it never chooses or changes the query.
        var facts = (try? JSONSerialization.jsonObject(with: Data(result.modelFactsJSON.utf8))) as? [String: Any] ?? [:]
        facts["visualPresentation"] = display
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
#if DEBUG
            diagnosticOutput = json
#endif
            return json
        }
#if DEBUG
        diagnosticOutput = result.modelFactsJSON
#endif
        return result.modelFactsJSON
    }

    func answer(id: UUID, prompt: String, narration: String) -> HomeAnswer {
        let financial = evidence.filter { $0.tool != .findRecords && $0.verified }
        let visible = financial.isEmpty ? Array(evidence.suffix(1)) : financial
        // Preserve typed, independently scoped results rather than flattening their UI.
        var presentations: [MarinaPresentation] = []
        for (index, result) in results.enumerated() {
            guard let presentation = result.presentation else { continue }
            let request = requests[index]
            if request.tool == .findRecords && request.search != nil && result.status != "candidates" { continue }
            if let existing = presentations.firstIndex(where: { $0.id == presentation.id }) {
                presentations[existing] = presentation
            } else { presentations.append(presentation) }
        }
        presentations = MarinaPresentationDisplayPolicy.coalesced(presentations)
        var answer = HomeAnswer(id: id, queryID: id, kind: .message,
                          userPrompt: prompt, title: "", rows: visible.flatMap { $0.answer.rows },
                          explanation: narration, presentations: presentations)
        answer.suppressedPresentationIDs = presentations.filter {
            !MarinaPresentationDisplayPolicy.shouldShow($0, after: previousPresentations)
        }.map(\.id)
        return answer
    }

    private struct ToolLimitError: LocalizedError {
        var errorDescription: String? { "This question needs too many data requests. Try a narrower question." }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDateSelection {
    case selectedPeriod, previousPeriod, currentMonth, previousMonth, yearToDate, nextSevenDays, allTime
    case dates(start: String, end: String)
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseScope { case all, variable, planned }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeState { case all, actual, planned }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDataGrouping { case none, card, category, merchant, source }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDataSort { case newest, oldest, largest, smallest }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseMeasure { case budgetImpact, ledger, spending, planned, actual }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaPeriodUnit { case day, week, month, quarter, year }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaRecordKind: String { case card, category, budget, preset, savingsAccount, reconciliationAccount, incomeSource, merchant, workspace }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaAccountScope { case all, savings, reconciliation }

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaRecordLookup {
    case resolveName(name: String)
    case inventory(kind: MarinaRecordKind?, offset: Int)
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFindRecordsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "findRecords"
    let description = "Resolve a named card, category, merchant, budget or account. Copy the returned selection into readExpenses, or the filter keys into other financial queries. Never use this to list or rank purchases; readExpenses provides those."
    typealias Arguments = RecordLookupArguments
    @Generable struct RecordLookupArguments {
        @Guide(description: "Set true only when the person explicitly asks to see the visual again. Otherwise omit; the app avoids repeating unchanged visuals.")
        var showVisual: Bool? = nil
        @Guide(description: "resolveName identifies what a name refers to and returns a selection to copy. inventory lists a requested kind of workspace record.")
        var lookup: MarinaRecordLookup
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .findRecords)
            request.forcePresentation = arguments.showVisual
            request.operation = .inventory
            request.limit = 5
            switch arguments.lookup {
            case .resolveName(let name): request.search = name
            case .inventory(let kind, let offset): request.recordKind = kind?.rawValue; request.offset = offset
            }
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseOperation: String {
    case summary, transactions, upcomingPresets, largestPurchase, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals, compare
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseFilter {
    case expenseCard(id: String)
    case expenseCategory(id: String)
    case expenseBudget(id: String)
    case expensePreset(id: String)
    case expenseMerchant(name: String)
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseSelection {
    case expenseWorkspace
    case expenseMatching(filters: [MarinaExpenseFilter])
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaExpenseComparison {
    @Guide(description: "expenseWorkspace for the whole workspace, or copy a resolved selection from findRecords. expenseMatching requires at least one filter, with at most one per kind.")
    var selection: MarinaExpenseSelection
    var dates: MarinaDateSelection
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeOperation {
    case summary
    case progress
    case transactions(order: MarinaDataSort, offset: Int)
    case groups(by: MarinaDataGrouping, offset: Int)
    case periodTotals(unit: MarinaPeriodUnit, offset: Int)
    case compareIncome(source: String?, cardID: String?, dates: MarinaDateSelection)
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaExpensesTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readExpenses"
    let description = "Read spending totals and purchases. For highest-spending categories use categoryTotals; no category name lookup is needed. Always preserve a resolved card/category filter on follow-ups."
    typealias Arguments = ExpenseQueryArguments
    @Generable struct ExpenseQueryArguments {
        @Guide(description: "Set true only when the person explicitly asks to see the visual again. Otherwise omit; the app avoids repeating unchanged visuals.")
        var showVisual: Bool? = nil
        @Guide(description: "Use expenseWorkspace for the whole workspace. For named targets, copy the selection from findRecords and preserve it on follow-ups. expenseMatching requires at least one filter. Combine different kinds when needed; at most one filter per kind.")
        var selection: MarinaExpenseSelection
        var dates: MarinaDateSelection
        @Guide(description: "summary for totals, transactions for a list, upcomingPresets for scheduled unrecorded preset expenses due soon (use nextSevenDays unless another range is requested), largestPurchase for the biggest purchase, categoryTotals/cardTotals/merchantTotals for rankings, categoryShares/cardShares/merchantShares for proportions, periodTotals for a time series, compare only for a requested comparison.")
        var operation: MarinaExpenseOperation
        @Guide(description: "Order for transactions. Omit otherwise.") var sort: MarinaDataSort?
        @Guide(description: "Time bucket for periodTotals. Omit otherwise.") var periodUnit: MarinaPeriodUnit?
        var offset: Int?
        @Guide(description: "Second target and period, only for compare. Omit otherwise.") var comparison: MarinaExpenseComparison?
        var scope: MarinaExpenseScope?
        @Guide(description: "Normally budgetImpact. Only use ledger/spending/planned/actual when explicitly requesting that measure.")
        var measure: MarinaExpenseMeasure?
        @Guide(description: "True to inspect upcoming costs despite calculation exclusions.") var includeFuture: Bool?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .expenses)
            request.forcePresentation = arguments.showVisual
            try applyExpenseSelection(arguments.selection, to: &request)
            applyDates(arguments.dates, to: &request)
            request.limit = 5
            request.offset = arguments.offset ?? 0
            switch arguments.operation {
            case .summary: request.operation = .summary
            case .upcomingPresets: request.purpose = .upcomingPresets
            case .largestPurchase: request.operation = .transactions; request.sort = .largest; request.limit = 1
            case .categoryShares: request.operation = .share; request.grouping = .category
            case .cardShares: request.operation = .share; request.grouping = .card
            case .merchantShares: request.operation = .share; request.grouping = .merchant
            case .transactions: request.operation = .transactions; request.sort = sort(arguments.sort)
            case .categoryTotals: request.operation = .ranking; request.grouping = .category
            case .cardTotals: request.operation = .ranking; request.grouping = .card
            case .merchantTotals: request.operation = .ranking; request.grouping = .merchant
            case .periodTotals: request.operation = .trend; request.periodUnit = periodUnit(arguments.periodUnit)
            case .compare:
                request.operation = .comparison
                if let other = arguments.comparison {
                    var selection = MarinaDataRequest(tool: .expenses)
                    try applyExpenseSelection(other.selection, to: &selection)
                    request.comparisonFilter = .init(cardID: selection.cardID, categoryID: selection.categoryID,
                                                     budgetID: selection.budgetID, presetID: selection.presetID, search: selection.search)
                    applyComparisonDates(other.dates, to: &request)
                }
            }
            switch arguments.scope { case .variable: request.scope = .variable; case .planned: request.scope = .planned; default: break }
            request.includeFuture = arguments.includeFuture ?? false
            switch arguments.measure { case .ledger: request.expenseMeasure = .ledger; case .spending: request.expenseMeasure = .spending; case .planned: request.expenseMeasure = .planned; case .actual: request.expenseMeasure = .actual; default: break }
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaIncomeTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readIncome"
    let description = "Read expected or received income. Use progress for actual versus planned income completion, not compareIncome. Use compareIncome only for different targets or date ranges."
    typealias Arguments = IncomeQueryArguments
    @Generable struct IncomeQueryArguments {
        @Guide(description: "Resolved budget ID only when requesting income for that budget's period. Omit for general workspace income.")
        var budgetID: String? = nil
        @Guide(description: "Set true only when the person explicitly asks to see the visual again. Otherwise omit; the app avoids repeating unchanged visuals.")
        var showVisual: Bool? = nil
        @Guide(description: "Only a specific income source name requested by the person. Omit for all income in the workspace.")
        var source: String?
        @Guide(description: "Only a card UUID returned by findRecords when explicitly filtering income by card. Omit for workspace income.")
        var cardID: String?
        var dates: MarinaDateSelection
        var state: MarinaIncomeState
        @Guide(description: "progress compares received income with planned income in the SAME date range. summary gives a total. compareIncome compares DIFFERENT date ranges or DIFFERENT named sources/cards, never actual versus planned.")
        var operation: MarinaIncomeOperation
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .income)
            request.forcePresentation = arguments.showVisual
            request.budgetID = arguments.budgetID
            request.search = arguments.source
            request.cardID = arguments.cardID
            applyDates(arguments.dates, to: &request)
            switch arguments.state { case .planned: request.state = .planned; case .all: request.state = .all; case .actual: request.state = .actual }
            switch arguments.operation {
            case .summary: request.operation = .summary
            case .progress: request.purpose = .incomeProgress; request.state = .all
            case .transactions(let order, let offset): request.operation = .transactions; request.sort = sort(order); request.offset = offset
            case .groups(let dimension, let offset): request.operation = .ranking; request.grouping = grouping(dimension); request.offset = offset
            case .periodTotals(let unit, let offset): request.operation = .trend; request.periodUnit = periodUnit(unit); request.offset = offset
            case .compareIncome(let source, let cardID, let dates):
                request.operation = .comparison
                request.comparisonFilter = .init(cardID: cardID, search: source)
                applyComparisonDates(dates, to: &request)
            }
            request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaBudgetOperation {
    case overview
    case pace
    case savingsTrend(unit: MarinaPeriodUnit, offset: Int)
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaBudgetTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readBudgetSummary"
    let description = "Calculate budget room, pace, category limits, income coverage and savings forecasts."
    typealias Arguments = BudgetQueryArguments
    @Generable struct BudgetQueryArguments {
        @Guide(description: "Resolved card ID only for an explicitly card-filtered pace question. Omit otherwise.")
        var cardID: String? = nil
        @Guide(description: "pace checks spending against the plan. overview gives remaining room and savings. savingsTrend is only a savings time series. Select the date range separately with dates.")
        var operation: MarinaBudgetOperation
        @Guide(description: "Set true only when the person explicitly asks to see the visual again. Otherwise omit; the app avoids repeating unchanged visuals.")
        var showVisual: Bool? = nil
        var dates: MarinaDateSelection?
        var budgetID: String?
        var categoryID: String?
        @Guide(description: "Optional hypothetical extra spending amount; never income or savings replacement.") var hypotheticalSpending: Double?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .budgetSummary)
            request.forcePresentation = arguments.showVisual
            applyDates(arguments.dates, to: &request)
            request.budgetID = arguments.budgetID; request.categoryID = arguments.categoryID
            request.cardID = arguments.cardID
            switch arguments.operation {
            case .overview: break
            case .pace: request.purpose = .budgetPace
            case .savingsTrend(let unit, let offset): request.periodUnit = periodUnit(unit); request.offset = offset
            }
            request.hypotheticalSpending = arguments.hypotheticalSpending
            request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaAccountsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readAccounts"
    let description = "Read savings or reconciliation balances and activity; preserves who owes whom."
    typealias Arguments = AccountQueryArguments
    @Generable struct AccountQueryArguments {
        @Guide(description: "Set true only when the person explicitly asks to see the visual again. Otherwise omit; the app avoids repeating unchanged visuals.")
        var showVisual: Bool? = nil
        var scope: MarinaAccountScope?
        var accountID: String?
        var dates: MarinaDateSelection?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .accounts)
            request.forcePresentation = arguments.showVisual
            switch arguments.scope { case .savings: request.scope = .savings; case .reconciliation: request.scope = .reconciliation; default: break }
            request.accountID = arguments.accountID
            applyDates(arguments.dates, to: &request)
            request.offset = arguments.offset ?? 0; request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func applyExpenseSelection(_ selection: MarinaExpenseSelection, to request: inout MarinaDataRequest) throws {
    switch selection {
    case .expenseWorkspace: break
    case .expenseMatching(let filters):
        guard !filters.isEmpty else { throw EmptyExpenseSelection() }
        try applyExpenseFilters(filters, to: &request)
    }
}

private struct EmptyExpenseSelection: LocalizedError {
    var errorDescription: String? { "A matching expense selection requires at least one resolved filter. Use expenseWorkspace for the whole workspace." }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func applyExpenseFilters(_ filters: [MarinaExpenseFilter], to request: inout MarinaDataRequest) throws {
    var kinds: Set<String> = []
    for filter in filters {
        let kind: String
        switch filter {
        case .expenseCard: kind = "card"
        case .expenseCategory: kind = "category"
        case .expenseBudget: kind = "budget"
        case .expensePreset: kind = "preset"
        case .expenseMerchant: kind = "merchant"
        }
        guard kinds.insert(kind).inserted else { throw DuplicateExpenseFilter(kind: kind) }
        switch filter {
        case .expenseCard(let id): request.cardID = id
        case .expenseCategory(let id): request.categoryID = id
        case .expenseBudget(let id): request.budgetID = id
        case .expensePreset(let id): request.presetID = id
        case .expenseMerchant(let name): request.search = name
        }
    }
}

private struct DuplicateExpenseFilter: LocalizedError {
    let kind: String
    var errorDescription: String? { "Use at most one \(kind) filter in an expense selection." }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func grouping(_ value: MarinaDataGrouping?) -> MarinaDataRequest.Grouping {
    switch value { case .card: .card; case .category: .category; case .merchant: .merchant; case .source: .source; default: .none }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func sort(_ value: MarinaDataSort?) -> MarinaDataRequest.Sort {
    switch value { case .oldest: .oldest; case .largest: .largest; case .smallest: .smallest; default: .newest }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func periodUnit(_ value: MarinaPeriodUnit?) -> MarinaDataRequest.PeriodUnit? {
    switch value { case .day: .day; case .week: .week; case .month: .month; case .quarter: .quarter; case .year: .year; case nil: nil }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func applyDates(_ value: MarinaDateSelection?, to request: inout MarinaDataRequest) {
    switch value {
    case .selectedPeriod: request.relativePeriod = .selectedPeriod
    case .previousPeriod: request.relativePeriod = .previousPeriod
    case .currentMonth: request.relativePeriod = .currentMonth
    case .previousMonth: request.relativePeriod = .previousMonth
    case .yearToDate: request.relativePeriod = .yearToDate
    case .nextSevenDays: request.relativePeriod = .nextSevenDays
    case .allTime: request.allTime = true
    case .dates(let start, let end): request.startDate = start; request.endDate = end
    case nil: break
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func applyComparisonDates(_ value: MarinaDateSelection?, to request: inout MarinaDataRequest) {
    var dates = MarinaDataRequest(tool: request.tool)
    applyDates(value, to: &dates)
    request.comparisonStartDate = dates.startDate
    request.comparisonEndDate = dates.endDate
    request.comparisonPeriod = dates.relativePeriod
    request.comparisonAllTime = dates.allTime
}
#endif
