import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Serializes SwiftData access on the main actor, even when the model calls tools concurrently.
@available(iOS 26.0, macCatalyst 26.0, *)
@MainActor
final class MarinaToolBridge {
    private var service: MarinaReadOnlyDataService?
    private var onResult: (() -> Void)?
    private var results: [MarinaDataResult] = []
    private var evidence: [(tool: MarinaDataRequest.Tool, verified: Bool, answer: HomeAnswer)] = []
    private var calls = 0
    private var requiresClarification = false
    private(set) var requests: [MarinaDataRequest] = []
    var hasResults: Bool { !results.isEmpty }

    func begin(service: MarinaReadOnlyDataService, onResult: @escaping () -> Void) {
        self.service = service
        self.onResult = onResult
        results = []
        evidence = []
        requests = []
        calls = 0
        requiresClarification = false
    }

    func end() { service = nil; onResult = nil }

    func call(_ request: MarinaDataRequest) throws -> String {
        try Task.checkCancellation()
        guard let service else { throw CancellationError() }
        calls += 1
        guard calls <= 8 else { throw ToolLimitError() }
        if requiresClarification && request.tool != .findRecords {
            return "{\"status\":\"needsClarification\",\"explanation\":\"A lookup found competing records. Ask the person which candidate they mean before reading financial data.\"}"
        }
        requests.append(request)
        let result = try service.execute(request)
        results.append(result)
        if result.status == "candidates" { requiresClarification = true }
        let card = result.homeAnswer
        let verified = result.status == "success"
        let notice = !verified ? result.explanation.map { [HomeAnswerRow(title: $0, value: "", role: .assumption)] } ?? [] : []
        evidence.append((request.tool, verified, HomeAnswer(queryID: card.queryID, kind: card.kind,
            title: card.title, subtitle: card.subtitle,
            rows: [HomeAnswerRow(title: result.scope, value: "", role: .assumption)] + notice + card.rows,
            explanation: card.explanation)))
        onResult?()
        return result.modelFactsJSON
    }

    func answer(id: UUID, prompt: String, narration: String) -> HomeAnswer {
        let financial = evidence.filter { $0.tool != .findRecords && $0.verified }
        let visible = financial.isEmpty ? Array(evidence.suffix(1)) : financial
        let rows = visible.flatMap { $0.answer.rows }
        let title = !financial.isEmpty ? "Verified budget data"
            : (visible.last?.tool == .findRecords ? "Workspace records" : "Query needs attention")
        return HomeAnswer(id: id, queryID: id, kind: rows.isEmpty ? .message : .list,
                          userPrompt: prompt, title: rows.isEmpty ? "" : title,
                          rows: rows, explanation: narration)
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
@Generable enum MarinaExpenseTarget {
    case workspace
    case card(id: String)
    case category(id: String)
    case merchant(text: String)
    case preset(id: String)
    case budget(id: String)
    case cardCategory(cardID: String, categoryID: String)
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
struct MarinaFindRecordsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "findRecords"
    let description = "Find workspace records and name candidates before applying named filters."
    @Generable struct Arguments {
        @Guide(description: "Name to find; omit to list workspace inventory.") var search: String?
        @Guide(description: "Kind for listing inventory. Named searches return all competing kinds.") var recordKind: MarinaRecordKind?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        var request = MarinaDataRequest(tool: .findRecords)
        request.search = arguments.search
        request.recordKind = arguments.recordKind?.rawValue
        request.limit = 8
        request.offset = arguments.offset ?? 0
        return try await bridge.call(request)
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseOperation {
    case summary
    case transactions(order: MarinaDataSort, offset: Int)
    case groups(by: MarinaDataGrouping, offset: Int)
    case periodTotals(unit: MarinaPeriodUnit, offset: Int)
    case compare(other: MarinaExpenseTarget, dates: MarinaDateSelection)
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeOperation {
    case summary
    case transactions(order: MarinaDataSort, offset: Int)
    case groups(by: MarinaDataGrouping, offset: Int)
    case periodTotals(unit: MarinaPeriodUnit, offset: Int)
    case compare(source: String?, cardID: String?, dates: MarinaDateSelection)
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaExpensesTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readExpenses"
    let description = "Read spending totals, averages, comparisons, grouped shares and transaction details."
    @Generable struct Arguments {
        @Guide(description: "Card/category/preset/budget use an ID from findRecords. Merchant is expense text, never a card name.")
        var target: MarinaExpenseTarget
        var dates: MarinaDateSelection
        @Guide(description: "Summary for totals; transactions for individual purchases including biggest/next; groups for category/card shares; periodTotals only for time series; compare for differences.")
        var operation: MarinaExpenseOperation
        var scope: MarinaExpenseScope?
        @Guide(description: "Normally budgetImpact. Only use ledger/spending/planned/actual when explicitly requesting that measure.")
        var measure: MarinaExpenseMeasure?
        @Guide(description: "True to inspect upcoming costs despite calculation exclusions.") var includeFuture: Bool?
    }
    func call(arguments: Arguments) async throws -> String {
        var request = MarinaDataRequest(tool: .expenses)
        applyTarget(arguments.target, to: &request)
        applyDates(arguments.dates, to: &request)
        switch arguments.operation {
        case .summary: break
        case .transactions(let order, let offset): request.sort = sort(order); request.offset = offset
        case .groups(let dimension, let offset): request.grouping = grouping(dimension); request.offset = offset
        case .periodTotals(let unit, let offset): request.periodUnit = periodUnit(unit); request.offset = offset
        case .compare(let target, let dates):
            var other = MarinaDataRequest(tool: .expenses)
            applyTarget(target, to: &other)
            request.comparisonFilter = .init(cardID: other.cardID, categoryID: other.categoryID,
                                             budgetID: other.budgetID, presetID: other.presetID, search: other.search)
            applyComparisonDates(dates, to: &request)
        }
        switch arguments.scope { case .variable: request.scope = .variable; case .planned: request.scope = .planned; default: break }
        request.includeFuture = arguments.includeFuture ?? false
        switch arguments.measure { case .ledger: request.expenseMeasure = .ledger; case .spending: request.expenseMeasure = .spending; case .planned: request.expenseMeasure = .planned; case .actual: request.expenseMeasure = .actual; default: break }
        request.limit = 5
        return try await bridge.call(request)
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaIncomeTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readIncome"
    let description = "Read expected or received income, source shares and period comparisons."
    @Generable struct Arguments {
        @Guide(description: "Only a specific income source name requested by the person. Omit for all income in the workspace.")
        var source: String?
        @Guide(description: "Only a card UUID returned by findRecords when explicitly filtering income by card. Omit for workspace income.")
        var cardID: String?
        var dates: MarinaDateSelection
        var state: MarinaIncomeState
        var operation: MarinaIncomeOperation
    }
    func call(arguments: Arguments) async throws -> String {
        var request = MarinaDataRequest(tool: .income)
        request.search = arguments.source
        request.cardID = arguments.cardID
        applyDates(arguments.dates, to: &request)
        switch arguments.state { case .planned: request.state = .planned; case .all: request.state = .all; case .actual: request.state = .actual }
        switch arguments.operation {
        case .summary: break
        case .transactions(let order, let offset): request.sort = sort(order); request.offset = offset
        case .groups(let dimension, let offset): request.grouping = grouping(dimension); request.offset = offset
        case .periodTotals(let unit, let offset): request.periodUnit = periodUnit(unit); request.offset = offset
        case .compare(let source, let cardID, let dates):
            request.comparisonFilter = .init(cardID: cardID, search: source)
            applyComparisonDates(dates, to: &request)
        }
        request.limit = 5
        return try await bridge.call(request)
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaBudgetTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readBudgetSummary"
    let description = "Calculate budget room, pace, category limits, income coverage and savings forecasts."
    @Generable struct Arguments {
        var dates: MarinaDateSelection?
        var budgetID: String?
        var categoryID: String?
        @Guide(description: "Optional hypothetical extra spending amount; never income or savings replacement.") var hypotheticalSpending: Double?
        @Guide(description: "Only for averages per period or a time series, not selecting dates.") var periodUnit: MarinaPeriodUnit?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        var request = MarinaDataRequest(tool: .budgetSummary)
        applyDates(arguments.dates, to: &request)
        request.budgetID = arguments.budgetID; request.categoryID = arguments.categoryID
        request.hypotheticalSpending = arguments.hypotheticalSpending
        request.periodUnit = periodUnit(arguments.periodUnit)
        request.offset = arguments.offset ?? 0
        request.limit = 5
        return try await bridge.call(request)
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaAccountsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readAccounts"
    let description = "Read savings or reconciliation balances and activity; preserves who owes whom."
    @Generable struct Arguments {
        var scope: MarinaAccountScope?
        var accountID: String?
        var dates: MarinaDateSelection?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
        var request = MarinaDataRequest(tool: .accounts)
        switch arguments.scope { case .savings: request.scope = .savings; case .reconciliation: request.scope = .reconciliation; default: break }
        request.accountID = arguments.accountID
        applyDates(arguments.dates, to: &request)
        request.offset = arguments.offset ?? 0; request.limit = 5
        return try await bridge.call(request)
    }
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
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func applyTarget(_ target: MarinaExpenseTarget, to request: inout MarinaDataRequest) {
    switch target {
    case .workspace: break
    case .card(let id): request.cardID = id
    case .category(let id): request.categoryID = id
    case .merchant(let text): request.search = text
    case .preset(let id): request.presetID = id
    case .budget(let id): request.budgetID = id
    case .cardCategory(let card, let category): request.cardID = card; request.categoryID = category
    }
}
#endif
