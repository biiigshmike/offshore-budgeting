import Foundation

struct MarinaDataResult: Codable, Equatable, Sendable {
    struct Metric: Codable, Equatable, Sendable {
        enum Unit: String, Codable, Equatable, Sendable { case money, number, percent }
        let label: String
        let value: Double
        var unit: Unit = .money
        var formatted: String {
            switch unit {
            case .money: CurrencyFormatter.string(from: value)
            case .number: value.formatted(.number.precision(.fractionLength(0...2)))
            case .percent: (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
            }
        }
    }
    struct Record: Codable, Equatable, Sendable {
        let id: String
        let kind: String
        let title: String
        var date: String? = nil
        var amount: Double? = nil
        var detail: String? = nil
    }
    var presentation: MarinaPresentation? = nil
    var status: String = "success"
    var scope: String
    var metrics: [Metric] = []
    var records: [Record] = []
    var totalCount: Int = 0
    var nextOffset: Int? = nil
    var explanation: String? = nil
    var appliedFilters: String? = nil
    /// Validated targets and resolved dates for reference memory, never a cached financial answer.
    var resolvedRequest: MarinaDataRequest? = nil

    var modelFactsJSON: String { modelFactsJSON(for: nil) }

    /// A bounded narration payload. The original result and saved UI snapshots stay complete.
    func modelFactsJSON(for request: MarinaDataRequest?, reference: ((String, String) -> String?)? = nil) -> String {
        struct Facts: Encodable {
            struct MetricFact: Encodable { let label: String; let formatted: String; let unit: Metric.Unit }
            struct RecordFact: Encodable {
                let selection: String?
                let kind: String
                let title: String
                let date: String?
                let detail: String?
                let formattedAmount: String?
            }
            let status: String
            let scope: String
            let comparisonScope: String?
            let metrics: [MetricFact]
            let records: [RecordFact]?
            let totalCount: Int
            let nextOffset: Int?
            let explanation: String?
            let appliedFilters: String?
            let qualifier: String?
        }
        let tool = request?.tool ?? presentation?.topicKey?.split(separator: ":").first.flatMap { MarinaDataRequest.Tool(rawValue: String($0)) }
        let operation = presentation?.operation ?? request?.operation
        let purpose = presentation?.purpose ?? request?.purpose
        let isInventory = operation == .inventory || tool == .findRecords
        let isAccountList = tool == .accounts && (request.map { $0.accountID == nil }
            ?? !metrics.contains { $0.label == "Selected period activity count" })
        // Account balance metrics repeat the account rows and can grow without a page limit.
        // Keep the paged rows instead. Selected-account activity still retains its balance.
        let selectedMetrics = modelMetrics(tool: tool, operation: operation, purpose: purpose,
                                           hypothetical: request?.hypotheticalSpending != nil,
                                           accountList: isAccountList)
        let includesRecords = isInventory || tool == .accounts
            || (tool == .budgetSummary && purpose != .budgetPace && request?.hypotheticalSpending == nil)
            || (operation != .summary && operation != .comparison)
        let modelRecords = includesRecords ? Array(records.prefix(5)) : []
        let recordFacts = modelRecords.map { record in
            Facts.RecordFact(
                selection: isInventory || isAccountList ? reference?(record.kind, record.id) : nil,
                kind: record.kind, title: record.title, date: record.date, detail: record.detail,
                formattedAmount: record.amount.map { CurrencyFormatter.string(from: $0) })
        }
        let offset = request?.offset ?? presentation?.pagination?.request.offset ?? nextOffset.map { max(0, $0 - records.count) } ?? 0
        let modelNextOffset = includesRecords
            ? (modelRecords.count < records.count ? offset + modelRecords.count : nextOffset)
            : nil
        let facts = Facts(status: status, scope: scope,
                          comparisonScope: operation == .comparison ? presentation?.chartPoints.last?.label : nil,
                          metrics: selectedMetrics.map { .init(label: $0.label, formatted: $0.formatted, unit: $0.unit) },
                          records: includesRecords ? recordFacts : nil,
                          totalCount: totalCount, nextOffset: modelNextOffset, explanation: explanation,
                          appliedFilters: appliedFilters, qualifier: presentation?.qualifier)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(facts), let text = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\",\"explanation\":\"Result encoding failed\"}"
        }
        return text
    }

    private func modelMetrics(tool: MarinaDataRequest.Tool?, operation: MarinaDataRequest.Operation?,
                              purpose: MarinaDataRequest.Purpose?, hypothetical: Bool,
                              accountList: Bool) -> [Metric] {
        if accountList { return [] }
        if operation == .comparison {
            return metrics.filter { ["Total", "Comparison total", "Difference", "Change percent"].contains($0.label) }
        }
        if purpose == .incomeProgress {
            return metrics.filter { ["Actual income", "Planned income", "Income progress percent"].contains($0.label) }
        }
        if tool == .income && operation == .summary {
            // State and full-result scope remain in the explanation. Unrequested counterpart
            // totals can be mistaken for fresh evidence in a later actual/planned follow-up.
            return metrics.filter { ["Total", "Count"].contains($0.label) || $0.label.hasPrefix("Average per ") }
        }
        guard tool == .budgetSummary else { return metrics }
        let paceLabels: Set<String> = ["Planned spending", "Pace actual spending", "Elapsed period percent",
            "Expected spending by now", "Spending pace difference", "Spending per elapsed day", "Projected spending at current pace"]
        if purpose == .budgetPace { return metrics.filter { paceLabels.contains($0.label) } }
        if operation == .trend {
            return metrics.filter { ["Actual savings", "Projected savings"].contains($0.label)
                || $0.label.hasPrefix("Average actual savings per ") || $0.label.hasPrefix("Average projected savings per ") }
        }
        if hypothetical {
            return metrics.filter { ["Projected savings", "Remaining room", "Hypothetical additional spending",
                                      "Projected savings after hypothetical spending"].contains($0.label) }
        }
        // These details remain available through the dedicated pace operation.
        return metrics.filter { !paceLabels.subtracting(["Planned spending"]).contains($0.label) }
    }

    var homeAnswer: HomeAnswer {
        HomeAnswer(queryID: UUID(), kind: records.isEmpty ? .metric : .list,
                   title: presentation?.title ?? "", subtitle: scope,
                   primaryValue: nil,
                   rows: metrics.map { HomeAnswerRow(title: $0.label, value: $0.formatted, amount: $0.value) }
                   + records.map { record in
                       HomeAnswerRow(title: record.title + (record.date.map { " · \($0)" } ?? ""),
                                     value: record.amount.map { CurrencyFormatter.string(from: $0) } ?? record.detail ?? record.kind,
                                     sourceID: UUID(uuidString: record.id),
                                     objectType: lookupType(record.kind), amount: record.amount, date: record.date.flatMap(parseDate))
                   }, explanation: explanation)
    }

    private func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private func lookupType(_ kind: String) -> MarinaLookupObjectType? {
        switch kind {
        case "variableExpense": return .variableExpense
        case "plannedExpense": return .plannedExpense
        case "income": return .income
        case "card": return .card
        case "budget": return .budget
        case "category", "categoryLimit": return .category
        case "preset": return .preset
        case "savingsAccount": return .savingsAccount
        case "savingsLedgerEntry": return .savingsLedgerEntry
        case "reconciliationAccount": return .reconciliationAccount
        case "expenseAllocation": return .expenseAllocation
        case "reconciliationItem": return .reconciliationItem
        default: return nil
        }
    }
}
