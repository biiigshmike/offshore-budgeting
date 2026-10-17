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

    var modelFactsJSON: String {
        // UI snapshots and pagination are not model context. Include exact formatted money facts.
        struct Facts: Encodable {
            struct MetricFact: Encodable { let label: String; let value: Double; let formatted: String; let unit: Metric.Unit }
            struct SelectionFact: Encodable { let type = "expenseMatching"; let filters: [[String: String]] }
            struct RecordFact: Encodable { let id: String; let kind: String; let title: String; let date: String?; let amount: Double?; let detail: String?; let formattedAmount: String?; let filter: [String: String]?; let selection: SelectionFact? }
            let status: String; let scope: String; let metrics: [MetricFact]; let records: [RecordFact]?
            let totalCount: Int; let nextOffset: Int?; let explanation: String?; let appliedFilters: String?
        }
        let isSummary = presentation?.operation == .summary
        func resolvedFilter(_ record: Record) -> [String: String]? {
            guard presentation?.operation == .inventory else { return nil }
            switch record.kind {
            case "savingsAccount", "reconciliationAccount": return ["accountID": record.id]
            case "incomeSource": return ["source": record.title]
            default: return nil
            }
        }
        func expenseFilters(_ record: Record) -> [[String: String]]? {
            guard presentation?.operation == .inventory else { return nil }
            switch record.kind {
            case "card": return [["type": "expenseCard", "id": record.id]]
            case "category": return [["type": "expenseCategory", "id": record.id]]
            case "budget": return [["type": "expenseBudget", "id": record.id]]
            case "preset": return [["type": "expensePreset", "id": record.id]]
            case "merchant": return [["type": "expenseMerchant", "name": record.title]]
            default: return nil
            }
        }
        let facts = Facts(status: status, scope: scope,
                          metrics: metrics.map { .init(label: $0.label, value: $0.value, formatted: $0.formatted, unit: $0.unit) },
                          records: isSummary ? nil : records.map { .init(id: $0.id, kind: $0.kind, title: $0.title, date: $0.date, amount: $0.amount, detail: $0.detail, formattedAmount: $0.amount.map { CurrencyFormatter.string(from: $0) }, filter: resolvedFilter($0), selection: expenseFilters($0).map { .init(filters: $0) }) },
                          totalCount: totalCount, nextOffset: isSummary ? nil : nextOffset, explanation: explanation, appliedFilters: appliedFilters)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(facts), let text = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\",\"explanation\":\"Result encoding failed\"}"
        }
        return text
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
