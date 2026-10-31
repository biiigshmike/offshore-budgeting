import SwiftUI

/// Shows the signed contributions used by the originating screen's calculation.
struct FinancialCalculationHelpView: View {
    let sections: [FinancialCalculationSection]
    var dateRange: String? = nil
    var helpTopicID: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let dateRange {
                    Section("Dates Included") {
                        Text(dateRange)
                    }
                }

                ForEach(sections) { section in
                    Section {
                        Text(LocalizedStringKey(section.explanation))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ForEach(section.rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                if row.titleIsVerbatim {
                                    Text(verbatim: row.title)
                                } else {
                                    Text(LocalizedStringKey(row.title))
                                }
                                Spacer(minLength: 12)
                                Text(row.amount, format: CurrencyFormatter.currencyStyle())
                                    .monospacedDigit()
                            }
                            .fontWeight(row.isTotal ? .semibold : .regular)
                        }

                        ForEach(section.notes, id: \.self) { note in
                            Text(LocalizedStringKey(note))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(LocalizedStringKey(section.title))
                    }
                }

                if let helpTopicID {
                    Section {
                        HelpTopicLink(topicID: helpTopicID, title: "Learn more in Help")
                    }
                }
            }
            .navigationTitle("How is this calculated?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
