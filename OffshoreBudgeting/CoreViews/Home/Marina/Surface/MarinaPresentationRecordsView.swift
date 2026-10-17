import SwiftUI

struct MarinaPresentationRecordsView: View {
    let records: [MarinaPresentation.Record]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(records) { record in
                if let preset = record.preset {
                    PresetRowContent(title: preset.title, plannedAmount: preset.plannedAmount,
                        scheduleText: preset.schedule, assignedBudgetsCount: preset.assignedBudgetCount,
                        dueDate: record.date.flatMap(parseDate), occurrenceAmount: record.date == nil ? nil : record.amount)
                } else {
                SharedExpenseRowContent(
                    title: record.title,
                    subtitle: subtitle(for: record),
                    amount: record.amount.map { CurrencyFormatter.string(from: $0) } ?? "",
                    categoryColorHex: record.categoryColorHex
                )
                }
                if record.id != records.last?.id {
                    Divider()
                }
            }
        }
    }

    private func parseDate(_ date: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    private func subtitle(for record: MarinaPresentation.Record) -> String {
        var parts: [String] = []
        if let date = record.date {
            if let parsed = parseDate(date) {
                parts.append(parsed.formatted(date: .abbreviated, time: .omitted))
            }
        }
        if record.kind == "plannedExpense" {
            parts.append((record.actualAmount ?? 0) > 0 ? "Recorded planned expense" : "Planned expense")
        }
        if let category = record.categoryName { parts.append(category) }
        if let card = record.cardName { parts.append(card) }
        if parts.isEmpty, let detail = record.detail { parts.append(detail) }
        return parts.joined(separator: " • ")
    }
}
