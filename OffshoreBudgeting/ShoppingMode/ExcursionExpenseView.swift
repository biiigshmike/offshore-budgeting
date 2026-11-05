import SwiftUI
import SwiftData

struct ExcursionExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID = ""
    @Query private var workspaces: [Workspace]
    @State private var choice: ExpenseChoice?

    let suggestion: ExcursionSuggestion

    private struct ExpenseChoice: Hashable {
        let name: String?
    }

    private var originatingWorkspace: Workspace? {
        workspaces.first { $0.id == suggestion.workspaceID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workspace = originatingWorkspace {
                    if selectedWorkspaceID != workspace.id.uuidString {
                        ContentUnavailableView {
                            Label("Switch Workspace", systemImage: "square.stack")
                        } description: {
                            Text("This reminder belongs to \(workspace.name). Switch there before recording an expense.")
                        } actions: {
                            Button("Switch to \(workspace.name)") { switchWorkspace() }
                        }
                    } else if suggestion.candidates.count == 1 {
                        AddExpenseView(workspace: workspace, prefilledDescription: suggestion.candidates.first?.name)
                    } else if let choice {
                        AddExpenseView(workspace: workspace, prefilledDescription: choice.name)
                    } else {
                        List {
                            Section {
                                ForEach(suggestion.candidates) { candidate in
                                    Button(candidate.name) { choice = ExpenseChoice(name: candidate.name) }
                                }
                                Button("Other") { choice = ExpenseChoice(name: nil) }
                            } header: {
                                Text("Where did you spend?")
                            } footer: {
                                Text("These places were nearby. Choose a place only if you made a purchase.")
                            }
                        }
                        .navigationTitle("Nearby Places")

                    }
                } else {
                    ContentUnavailableView("Workspace Unavailable", systemImage: "square.stack",
                        description: Text("The workspace for this reminder no longer exists. No expense has been created."))
                }
            }
            .toolbar {
                if originatingWorkspace == nil || selectedWorkspaceID != suggestion.workspaceID.uuidString || (suggestion.candidates.count > 1 && choice == nil) {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private func switchWorkspace() {
        guard originatingWorkspace != nil else { return }
        // Replay the route in the newly selected workspace instead of opening a
        // financial form against a workspace different from the app selection.
        dismiss()
        selectedWorkspaceID = suggestion.workspaceID.uuidString
        UserDefaults.standard.set(suggestion.encoded, forKey: AppShortcutNavigationStore.pendingExcursionSuggestionKey)
        UserDefaults.standard.set(AppShortcutNavigationStore.PendingAction.openQuickAddExpenseFromShoppingMode.rawValue,
                                  forKey: AppShortcutNavigationStore.pendingActionKey)
    }
}
