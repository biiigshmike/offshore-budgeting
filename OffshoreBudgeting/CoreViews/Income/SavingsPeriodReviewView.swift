import SwiftData
import SwiftUI

struct SavingsPeriodReviewView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw = BudgetingPeriod.monthly.rawValue
    @State private var periods: [SavingsPeriodReviewSummary] = []
    @State private var loadError: String?
    @State private var hasLoaded = false

    private var pending: [SavingsPeriodReviewSummary] {
        periods.filter(\.isPending).sorted { $0.start < $1.start }
    }

    private var changed: [SavingsPeriodReviewSummary] {
        periods.filter { !$0.isPending && $0.needsReview }.sorted { $0.start < $1.start }
    }

    private var history: [SavingsPeriodReviewSummary] {
        periods.filter { !$0.isPending && !$0.needsReview }.sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            Section {
                Text("Take a look at each period’s budgets, income, and expenses, then update Savings when you’re ready.")
                    .foregroundStyle(.secondary)
            } header: {
                Text(workspace.name)
                    .textCase(nil)
            } footer: {
                Text("Copied or imported periods keep their posted amounts and may need confirmation again in this workspace.")
            }

            if let loadError {
                Section {
                    Label("Couldn’t Load Periods", systemImage: "exclamationmark.circle")
                    Text(loadError).foregroundStyle(.secondary)
                    Button("Try Again", action: reload)
                }
            } else if !hasLoaded {
                ProgressView()
            } else if periods.isEmpty {
                ContentUnavailableView(
                    "No Completed Periods",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Periods with income or expenses will show up here once they end.")
                )
            } else {
                if pending.isEmpty && changed.isEmpty {
                    Section {
                        Label("No Periods Awaiting Review", systemImage: "checkmark.circle")
                    }
                }
                if !changed.isEmpty {
                    Section("Needs Review") {
                        ForEach(changed, content: periodRow)
                    }
                }
                if !pending.isEmpty {
                    Section("Awaiting Confirmation") {
                        ForEach(pending, content: periodRow)
                    }
                }
                if !history.isEmpty {
                    Section {
                        ForEach(history, content: periodRow)
                    } header: {
                        Text("Posted History")
                    } footer: {
                        Text("Want to check an older period? Open it here to take another look.")
                    }
                }
            }
        }
        .navigationTitle("Period Review")
        .accessibilityIdentifier("savings.periodReview")
        .onAppear(perform: reload)
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .refreshable { reload() }
    }

    private func periodRow(_ period: SavingsPeriodReviewSummary) -> some View {
        NavigationLink {
            SavingsPeriodReviewDetailView(workspace: workspace, summary: period)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(AppDateFormat.abbreviatedDate(period.start)) – \(AppDateFormat.abbreviatedDate(period.end))")
                    .font(.headline)
                LabeledContent(period.isPending ? "Calculated Savings" : "Posted Savings") {
                    Text(period.isPending ? period.calculatedAmount : period.postedAmount, format: CurrencyFormatter.currencyStyle())
                }
                .font(.subheadline)
                if period.hasOverlapConflict {
                    Label("Overlaps a posted period", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                } else if period.existingEntry?.correctedCloseAmount != nil {
                    Label("Corrected closing amount", systemImage: "pencil.circle")
                        .font(.caption)
                }
            }
        }
    }

    private func reload() {
        do {
            periods = try SavingsPeriodReviewService.summaries(
                workspaceID: workspace.id,
                defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
                modelContext: modelContext
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }
}
