import SwiftUI
import SwiftData

struct CategoryGoalAutoConfigurationSettingsView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @State private var settings: CategoryGoalAutoConfigurationSettings
    @State private var showingSaveError = false

    init(workspace: Workspace) {
        self.workspace = workspace
        _settings = State(initialValue: workspace.categoryGoalAutoConfiguration)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Suggest Maximums", isOn: $settings.suggestMaximums)
                    .tint(Color("AccentColor"))
                    .accessibilityIdentifier("categoryGoals.settings.suggestMaximums")
                Stepper(value: $settings.historyCount, in: 1...12) {
                    LabeledContent("Past Budgets", value: settings.historyCount.formatted())
                }
                .accessibilityIdentifier("categoryGoals.settings.historyCount")
                .disabled(!settings.suggestMaximums)
                Stepper(value: $settings.cushionPercent, in: 0...100, step: 5) {
                    LabeledContent("Extra Cushion") {
                        Text(settings.cushionPercent / 100, format: .percent.precision(.fractionLength(0)))
                    }
                }
                .accessibilityIdentifier("categoryGoals.settings.cushionPercent")
                .disabled(!settings.suggestMaximums)
            } footer: {
                Text("When you enable Auto-Configure while creating a budget, minimums come from attached planned expenses. Maximums use average category spending from past budgets of comparable length, plus your cushion. Every amount remains editable.")
            }
            Section {
                Text("Only completed, non-overlapping budgets in this workspace are compared. Fewer budgets are used when history is limited. Without category history, the maximum stays blank.")
                Text("Extra Cushion adds your chosen percentage to the historical average before suggesting a maximum. Set it to zero to add no cushion.")
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Auto-Configure Goals")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings) { _, updated in
            let previous = workspace.categoryGoalAutoConfiguration
            guard updated != previous else { return }
            workspace.categoryGoalAutoConfiguration = updated
            do {
                try modelContext.save()
            } catch {
                workspace.categoryGoalAutoConfiguration = previous
                settings = previous
                showingSaveError = true
            }
        }
        .onChange(of: workspace.categoryGoalAutoConfiguration) { _, updated in
            settings = updated
        }
        .alert("Couldn’t Save Settings", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your previous Auto-Configure settings were restored. Please try again.")
        }
    }
}
