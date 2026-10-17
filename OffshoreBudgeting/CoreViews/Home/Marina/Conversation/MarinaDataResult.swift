import Foundation

struct MarinaDataResult: Codable, Sendable {
    struct Metric: Codable, Sendable {
        enum Unit: String, Codable, Sendable { case money, number, percent }
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
    struct Record: Codable, Sendable {
        let id: String
        let kind: String
        let title: String
        var date: String? = nil
        var amount: Double? = nil
        var detail: String? = nil
    }
    var status: String = "success"
    var scope: String
    var metrics: [Metric] = []
    var records: [Record] = []
    var totalCount: Int = 0
    var nextOffset: Int? = nil
    var explanation: String? = nil
    var appliedFilters: String? = nil

    var modelFactsJSON: String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"error\",\"explanation\":\"Result encoding failed\"}"
        }
        return text
    }

    var homeAnswer: HomeAnswer {
        HomeAnswer(queryID: UUID(), kind: records.isEmpty ? .metric : .list,
                   title: "Verified budget data", subtitle: scope,
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
