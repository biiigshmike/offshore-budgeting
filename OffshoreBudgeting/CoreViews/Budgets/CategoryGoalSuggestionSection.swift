import SwiftUI

struct CategoryGoalSuggestionSection: View {
    let suggestion: CategoryGoalSuggestion?

    var body: some View {
        Section {
            if let suggestion {
                DisclosureGroup {
                    ForEach(suggestion.samples) { sample in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sample.name)
                            Text("\(sample.startDate, format: .dateTime.month(.abbreviated).day().year()) – \(sample.endDate, format: .dateTime.month(.abbreviated).day().year())")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(sample.amount, format: CurrencyFormatter.currencyStyle())
                        }
                    }
                    LabeledContent("Average Category Spending") {
                        Text(suggestion.averageAmount, format: CurrencyFormatter.currencyStyle())
                    }
                } label: {
                    if suggestion.samples.count == 1 {
                        Text("Based on 1 past budget · \(suggestion.cushionPercent / 100, format: .percent.precision(.fractionLength(0))) cushion")
                    } else {
                        Text("Based on \(suggestion.samples.count) past budgets · \(suggestion.cushionPercent / 100, format: .percent.precision(.fractionLength(0))) cushion")
                    }
                }
                .accessibilityIdentifier("categoryGoals.historyDisclosure")
            } else {
                Text("No comparable category history. Enter a maximum if you want one.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("History Reference")
        } footer: {
            Text("Includes planned amounts when no actual amount was recorded. Auto-Configure adds your cushion and respects the minimum when applied. Your edited goals may differ. This is a starting point, not an assessment of affordability.")
        }
    }
}
