#if DEBUG
import SwiftData
import SwiftUI

struct MarinaFoundationReadinessView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @AppStorage(MarinaRuntimeSettings.aiOptInKey)
    private var marinaAIOptInEnabled: Bool = MarinaRuntimeSettings.defaultAIOptInEnabled
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @State private var report: MarinaFoundationReadinessReport?
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Button {
                    runCheck()
                } label: {
                    Label(
                        isRunning ? "Running Check" : "Run Readiness Check",
                        systemImage: "apple.intelligence"
                    )
                }
                .disabled(isRunning)

                if let report {
                    statusRow(report)
                }
            }

            if let report {
                Section("Steps") {
                    ForEach(report.steps) { step in
                        stepRow(step)
                    }
                }
            }
        }
        .navigationTitle("Marina Diagnostics")
    }

    private var defaultPeriodUnit: HomeQueryPeriodUnit {
        (BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly).queryPeriodUnit
    }

    private func runCheck() {
        isRunning = true
        Task {
            let now = Date()
            let context = MarinaTurnContext(
                provider: MarinaDataProvider(modelContext: modelContext, workspaceID: workspace.id),
                routerContext: MarinaInterpretationContext(
                    workspaceName: workspace.name,
                    defaultPeriodUnit: defaultPeriodUnit,
                    sessionContext: MarinaSessionContext(),
                    priorQueryContext: .empty,
                    cardNames: [],
                    categoryNames: [],
                    incomeSourceNames: [],
                    presetTitles: [],
                    budgetNames: [],
                    aliasSummaries: [],
                    now: now
                ),
                defaultPeriodUnit: defaultPeriodUnit,
                aiEnabled: marinaAIOptInEnabled,
                now: now,
                turnClassification: .freshQuestion
            )
            report = await MarinaFoundationReadinessCheck().run(context: context)
            isRunning = false
        }
    }

    private func statusRow(_ report: MarinaFoundationReadinessReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(report.passed ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 4) {
                Text(report.passed ? "Ready" : "Not Ready")
                    .font(.headline)
                Text(report.failedStep?.detail ?? report.generatedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepRow(_ step: MarinaFoundationReadinessStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage(for: step.status))
                .foregroundStyle(color(for: step.status))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.body.weight(.medium))
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func systemImage(for status: MarinaFoundationReadinessStep.Status) -> String {
        switch status {
        case .passed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .skipped:
            return "minus.circle.fill"
        }
    }

    private func color(for status: MarinaFoundationReadinessStep.Status) -> Color {
        switch status {
        case .passed:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .secondary
        }
    }
}
#endif
