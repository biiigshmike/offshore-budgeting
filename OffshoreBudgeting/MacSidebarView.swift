#if targetEnvironment(macCatalyst)
import SwiftUI

/// Shares the native sidebar with sections whose navigation remains in SwiftUI.
struct MacSidebarView: UIViewControllerRepresentable {
    var selectedSection: AppSection
    var onSelectSection: (AppSection) -> Void
    var onAddExpense: () -> Void
    var onAddIncome: () -> Void

    func makeUIViewController(context: Context) -> MacSidebarController {
        let controller = MacSidebarController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: MacSidebarController, context: Context) {
        controller.update(
            selectedSection: selectedSection,
            onSelectSection: onSelectSection,
            onAddExpense: onAddExpense,
            onAddIncome: onAddIncome
        )
    }
}
#endif
