import SwiftUI

struct SharedExpenseRowContent: View {
    let title: String
    let date: Date
    let amount: String
    let category: Category?
    var card: Card?
    var isCredit = false
    var typeLabel: String?
    var typeLabelShowsCheckmark = false
    var accessibilityOnlyTypeLabel: String?
    var secondaryAmountSummary: String?

    private var accessibilitySummary: String {
        let categoryName = category?.name ?? String(localized: "Uncategorized")
        return [
            title,
            AppDateFormat.abbreviatedDate(date),
            amount,
            typeLabel ?? accessibilityOnlyTypeLabel,
            secondaryAmountSummary,
            String(localized: "Category: \(categoryName)"),
            card.map { String(localized: "Card: \($0.name)") }
        ].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        DatedAmountRowLayout(
            title: title,
            titleFont: .body,
            date: date,
            dateFont: .footnote,
            category: category,
            showsCategory: true,
            card: card
        ) {
            Text(amount)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isCredit ? .green : .primary)
                .fixedSize(horizontal: false, vertical: true)
        } details: { alignment in
            VStack(alignment: alignment, spacing: 2) {
                if let typeLabel {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if typeLabelShowsCheckmark {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                        Text(typeLabel)
                    }
                }
                if let secondaryAmountSummary {
                    Text(secondaryAmountSummary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}
