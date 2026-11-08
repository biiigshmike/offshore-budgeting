import SwiftUI

/// Shows the signed contributions used by the originating screen's calculation.
struct FinancialCalculationHelpView: View {
    let sections: [FinancialCalculationSection]
    var dateRange: String? = nil
    var helpTopicID: String? = nil
    var expandableGroups: [FinancialCalculationDisclosure] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        sectionContent(section)
                    } header: {
                        Text(LocalizedStringKey(section.title))
                    }
                }

                if let firstGroup = expandableGroups.first {
                    Section {
                        ForEach(expandableGroups) { group in
                            DisclosureGroup {
                                ForEach(group.sections) { section in
                                    if group.sections.count > 1 {
                                        Text(LocalizedStringKey(section.title))
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    sectionContent(section)
                                }
                            } label: {
                                calculationRow(group.summary)
                            }
                            .accessibilityIdentifier("calculation.disclosure.\(group.id)")
                        }
                    } header: {
                        Text(LocalizedStringKey(firstGroup.sectionTitle))
                    }
                }

                if let helpTopicID {
                    Section {
                        HelpTopicLink(topicID: helpTopicID, title: "Learn more in Help", font: .body)
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

    private func sectionContent(_ section: FinancialCalculationSection) -> some View {
        Group {
            Text(LocalizedStringKey(section.explanation))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(section.rows) { row in
                calculationRow(row)
            }

            ForEach(section.notes, id: \.self) { note in
                Text(LocalizedStringKey(note))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calculationRow(_ row: FinancialCalculationRow) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    rowTitle(row)
                    rowAmount(row)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    rowTitle(row)
                    Spacer(minLength: 12)
                    rowAmount(row)
                }
            }
        }
        .fontWeight(row.isTotal ? .semibold : .regular)
    }

    @ViewBuilder
    private func rowTitle(_ row: FinancialCalculationRow) -> some View {
        if row.titleIsVerbatim {
            Text(verbatim: row.title)
        } else {
            Text(LocalizedStringKey(row.title))
        }
    }

    private func rowAmount(_ row: FinancialCalculationRow) -> some View {
        Text(row.amount, format: CurrencyFormatter.currencyStyle())
    }
}
