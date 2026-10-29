import SwiftData
import SwiftUI

struct MarinaPeakDrilldownView: View {
    let drilldown: MarinaPeakDrilldown
    let workspace: Workspace
    let homeContext: MarinaPanelHomeContext?
    let defaultBudgetingPeriod: BudgetingPeriod
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var result: MarinaDataResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("These are current records for the peak period. Your saved spending report stays unchanged.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    }
                    if let result, let presentation = result.presentation {
                        if let previous = drilldown.presentation.report?.peak?.amount,
                           let total = result.metrics.first(where: { $0.label == "Total" })?.value,
                           abs(previous - total) > 0.005 {
                            Text("This period now totals \(CurrencyFormatter.string(from: total)). The saved report showed \(CurrencyFormatter.string(from: previous)).")
                                .font(.subheadline)
                        }
                        MarinaPresentationView(presentation: presentation, onShowMore: loadMore)
                    } else if errorMessage == nil {
                        ProgressView("Reading current expenses")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Peak period transactions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: drilldown.id) { load() }
    }

    private func load() {
        do {
            accept(try drilldown.read(workspace: workspace, modelContext: modelContext,
                                     homeContext: homeContext, defaultBudgetingPeriod: defaultBudgetingPeriod))
        } catch {
            errorMessage = "Marina couldn’t read these expenses. Please close this view and try again."
        }
    }

    private func loadMore() {
        guard drilldown.workspaceID == workspace.id, let presentation = result?.presentation else { return }
        do {
            // loadMore restores the first read's calculation date and independent
            // future-expense policies from its pagination snapshot.
            let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: modelContext,
                homeContext: homeContext, defaultBudgetingPeriod: defaultBudgetingPeriod)
            accept(try service.loadMore(presentation: presentation))
        } catch {
            errorMessage = "Marina couldn’t load more expenses. Please try again."
        }
    }

    private func accept(_ fresh: MarinaDataResult) {
        guard ["success", "empty"].contains(fresh.status), fresh.presentation != nil else {
            errorMessage = fresh.explanation ?? "The saved card, category, or budget may no longer be available. Please ask Marina for a new report."
            return
        }
        result = fresh
        errorMessage = nil
    }
}
