#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// An owned Catalyst split shell. SwiftUI content and its navigation state stay
/// in the same hosting controllers when Marina adds or removes a column.
struct MacSplitContainer<Content: View, Marina: View>: UIViewControllerRepresentable {
    var isMarinaPresented: Bool
    @Binding var isSidebarVisible: Bool
    var onWindowScene: ((UIWindowScene) -> Void)?
    var onController: ((MacSplitController) -> Void)?
    var selectedSection: AppSection
    var onSelectSection: (AppSection) -> Void
    var onAddExpense: () -> Void
    var onAddIncome: () -> Void
    private let content: Content
    private let marina: Marina

    init(
        isMarinaPresented: Bool,
        isSidebarVisible: Binding<Bool>,
        onWindowScene: ((UIWindowScene) -> Void)? = nil,
        onController: ((MacSplitController) -> Void)? = nil,
        selectedSection: AppSection,
        onSelectSection: @escaping (AppSection) -> Void,
        onAddExpense: @escaping () -> Void,
        onAddIncome: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder marina: () -> Marina
    ) {
        self.isMarinaPresented = isMarinaPresented
        _isSidebarVisible = isSidebarVisible
        self.onWindowScene = onWindowScene
        self.onController = onController
        self.selectedSection = selectedSection
        self.onSelectSection = onSelectSection
        self.onAddExpense = onAddExpense
        self.onAddIncome = onAddIncome
        self.content = content()
        self.marina = marina()
    }

    func makeUIViewController(context: Context) -> MacSplitController {
        let controller = MacSplitController()
        updateUIViewController(controller, context: context)
        return controller
    }

    func updateUIViewController(_ controller: MacSplitController, context: Context) {
        controller.onWindowScene = onWindowScene
        controller.onSidebarVisibilityChange = { isSidebarVisible = $0 }
        controller.update(
            selectedSection: selectedSection,
            onSelectSection: onSelectSection,
            onAddExpense: onAddExpense,
            onAddIncome: onAddIncome,
            content: AnyView(content.environment(\.self, context.environment)),
            marina: AnyView(marina.environment(\.self, context.environment)),
            isMarinaPresented: isMarinaPresented,
            isSidebarVisible: isSidebarVisible
        )
        onController?(controller)
    }
}

@MainActor
final class MacSplitController: UIViewController, UISplitViewControllerDelegate {
    var onWindowScene: ((UIWindowScene) -> Void)?
    var onSidebarVisibilityChange: ((Bool) -> Void)?
    private(set) var isSidebarVisible = true
    private(set) var isMarinaPresented = false
    private(set) var splitController: UISplitViewController?

    private let sidebarController = MacSidebarController()
    private let contentHost = UIHostingController(rootView: AnyView(EmptyView()))
    private let marinaHost = UIHostingController(rootView: AnyView(EmptyView()))
    private lazy var sidebarNavigation = navigationController(for: sidebarController)
    private lazy var contentNavigation = navigationController(for: contentHost)
    private lazy var marinaNavigation = navigationController(for: marinaHost)
    private var isApplyingState = false
    private weak var reportedWindowScene: UIWindowScene?
    private var preferredSidebarWidth: CGFloat = 280
    private var preferredMarinaWidth: CGFloat = 420

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportWindowSceneIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reportWindowSceneIfNeeded()
    }

    func update(
        selectedSection: AppSection,
        onSelectSection: @escaping (AppSection) -> Void,
        onAddExpense: @escaping () -> Void,
        onAddIncome: @escaping () -> Void,
        content: AnyView,
        marina: AnyView,
        isMarinaPresented: Bool,
        isSidebarVisible: Bool
    ) {
        isApplyingState = true
        defer { isApplyingState = false }
        sidebarController.update(
            selectedSection: selectedSection,
            onSelectSection: onSelectSection,
            onAddExpense: onAddExpense,
            onAddIncome: onAddIncome
        )
        contentHost.rootView = content
        marinaHost.rootView = marina
        let needsNewSplit = splitController == nil || self.isMarinaPresented != isMarinaPresented
        let sidebarChanged = self.isSidebarVisible != isSidebarVisible
        self.isMarinaPresented = isMarinaPresented
        self.isSidebarVisible = isSidebarVisible
        if needsNewSplit {
            replaceSplitController()
        } else if sidebarChanged {
            setSidebarVisible(isSidebarVisible)
        }
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
        setSidebarVisible(isSidebarVisible)
        onSidebarVisibilityChange?(isSidebarVisible)
    }

    private func navigationController(for host: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: host)
        navigation.setNavigationBarHidden(true, animated: false)
        return navigation
    }

    private func replaceSplitController() {
        loadViewIfNeeded()
        if let oldSplit = splitController {
            // Snapshot native divider positions only when changing column
            // structure. Reapplying widths during layout would fight dragging.
            let sidebarWidth = oldSplit.primaryColumnWidth
            if sidebarWidth.isFinite, sidebarWidth > 0 {
                preferredSidebarWidth = min(max(sidebarWidth, 220), 420)
            }
            if oldSplit.style == .tripleColumn,
               let marinaWidth = marinaNavigation.viewIfLoaded?.bounds.width,
               marinaWidth.isFinite, marinaWidth > 0 {
                preferredMarinaWidth = max(marinaWidth, 340)
            }
            oldSplit.delegate = nil
            oldSplit.willMove(toParent: nil)
            oldSplit.setViewController(nil, for: .primary)
            if oldSplit.style == .tripleColumn {
                oldSplit.setViewController(nil, for: .supplementary)
            }
            oldSplit.setViewController(nil, for: .secondary)
            oldSplit.view.removeFromSuperview()
            oldSplit.removeFromParent()
        }

        let split = UISplitViewController(style: isMarinaPresented ? .tripleColumn : .doubleColumn)
        split.preferredSplitBehavior = .tile
        split.primaryBackgroundStyle = .sidebar
        split.preferredPrimaryColumnWidth = preferredSidebarWidth
        split.minimumPrimaryColumnWidth = 220
        split.maximumPrimaryColumnWidth = 420
        split.showsSecondaryOnlyButton = false
        split.setViewController(sidebarNavigation, for: .primary)
        if isMarinaPresented {
            split.minimumSupplementaryColumnWidth = 400
            // Home is the flexible workspace, not a second narrow sidebar.
            // Leave divider resizing to UIKit while allowing this column to
            // consume space released when the primary sidebar is hidden.
            split.maximumSupplementaryColumnWidth = .greatestFiniteMagnitude
            split.preferredSupplementaryColumnWidthFraction = 1
            split.setViewController(contentNavigation, for: .supplementary)
            split.setViewController(marinaNavigation, for: .secondary)
            if #available(macCatalyst 26.0, *) {
                split.preferredSecondaryColumnWidth = preferredMarinaWidth
                split.minimumSecondaryColumnWidth = 340
            }
        } else {
            split.setViewController(contentNavigation, for: .secondary)
        }
        split.preferredDisplayMode = preferredDisplayMode
        split.delegate = self
        splitController = split
        addChild(split)
        split.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(split.view)
        NSLayoutConstraint.activate([
            split.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.view.topAnchor.constraint(equalTo: view.topAnchor),
            split.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        split.didMove(toParent: self)
    }

    private var preferredDisplayMode: UISplitViewController.DisplayMode {
        if isMarinaPresented {
            return isSidebarVisible ? .twoBesideSecondary : .oneBesideSecondary
        }
        return isSidebarVisible ? .oneBesideSecondary : .secondaryOnly
    }

    private func setSidebarVisible(_ visible: Bool) {
        splitController?.preferredDisplayMode = preferredDisplayMode
        if visible {
            splitController?.show(.primary)
        } else {
            splitController?.hide(.primary)
        }
    }

    func splitViewController(
        _ svc: UISplitViewController,
        willChangeTo displayMode: UISplitViewController.DisplayMode
    ) {
        guard !isApplyingState else { return }
        let visible: Bool
        switch displayMode {
        case .twoBesideSecondary, .twoOverSecondary, .twoDisplaceSecondary:
            visible = true
        case .oneBesideSecondary, .oneOverSecondary:
            visible = svc.style == .doubleColumn
        case .secondaryOnly:
            visible = false
        default:
            return
        }
        guard visible != isSidebarVisible else { return }
        isSidebarVisible = visible
        onSidebarVisibilityChange?(visible)
    }

    private func reportWindowSceneIfNeeded() {
        guard let scene = view.window?.windowScene, scene !== reportedWindowScene else { return }
        reportedWindowScene = scene
        onWindowScene?(scene)
    }
}
#endif
