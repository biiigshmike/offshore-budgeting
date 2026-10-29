import SwiftUI
import SwiftData

struct UncategorizedExpenseReviewPresenter: ViewModifier {
    let workspace: Workspace
    let session: UncategorizedExpenseReviewSession
    let activity: AppPresentationActivity
    let onSave: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("general_hideFutureVariableExpenses") private var hideFuture = false
    @AppStorage("releaseLogs_seenReleaseIDs") private var seenReleaseIDs = ""
    @Query private var expenses: [VariableExpense]
    @Query private var categories: [Category]
    @State private var reviewWorkspace: Workspace?
    @State private var presentationID = UUID()

    init(workspace: Workspace, session: UncategorizedExpenseReviewSession,
         activity: AppPresentationActivity, onSave: @escaping () -> Void) {
        self.workspace = workspace
        self.session = session
        self.activity = activity
        self.onSave = onSave
        let workspaceID = workspace.id
        _expenses = Query(filter: #Predicate<VariableExpense> {
            $0.workspace?.id == workspaceID && $0.category == nil
        })
        _categories = Query(filter: #Predicate<Category> {
            $0.workspace?.id == workspaceID && !$0.isArchived
        })
    }

    private var hasPendingRelease: Bool {
        guard let release = SettingsReleaseLogsView.currentReleaseSection else { return false }
        return !seenReleaseIDs.split(separator: ",").contains(Substring(release.id))
    }

    private var eligibility: [String] {
        [String(session.generation), String(session.isPending), workspace.id.uuidString,
         String(activity.isBusy), String(scenePhase == .active), seenReleaseIDs,
         String(expenses.count), String(categories.count), String(hideFuture)]
    }

    func body(content: Content) -> some View {
        content
            .appSheet(item: $reviewWorkspace) { selectedWorkspace in
                NavigationStack {
                    UncategorizedExpenseReviewView(workspace: selectedWorkspace, onSave: onSave)
                }
                .id(presentationID)
            }
            .task(id: eligibility) {
                // Let existing onAppear/deferred tip requests reserve their sheets.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                guard !Task.isCancelled else { return }
                session.selectWorkspace(workspace.id)
                if reviewWorkspace != nil {
                    session.consume()
                    return
                }
                guard session.isPending, scenePhase == .active,
                      !activity.isBusy, !hasPendingRelease, reviewWorkspace == nil else { return }
                let eligible = UncategorizedExpenseReviewService.expenses(
                    in: expenses, workspaceID: workspace.id, hideFuture: hideFuture
                )
                let available = UncategorizedExpenseReviewService.categories(in: categories, workspaceID: workspace.id)
                session.consume()
                guard !eligible.isEmpty, !available.isEmpty else { return }
                // SwiftUI can retain sheet state after an interactive dismissal.
                // Every new review gets a fresh staging area, even for the same workspace.
                presentationID = UUID()
                reviewWorkspace = workspace
            }
            .onChange(of: workspace.id) { _, id in
                reviewWorkspace = nil
                session.selectWorkspace(id)
            }
    }
}
