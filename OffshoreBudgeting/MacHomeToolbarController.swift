#if targetEnvironment(macCatalyst)
import UIKit

/// Owns the window toolbar for the native Mac Home split container.
@MainActor
final class MacHomeToolbarController: NSObject, NSToolbarDelegate {
    private static let sidebarID = NSToolbarItem.Identifier("home.sidebar")
    private static let actionsID = NSToolbarItem.Identifier("home.actions")
    private static let assistantID = NSToolbarItem.Identifier("home.assistant.openButton")

    private static let chatActionsID = NSToolbarItem.Identifier("marina.chatActionsMenu")
    private static let closeAssistantID = NSToolbarItem.Identifier("marina.closeButton")

    private weak var scene: UIWindowScene?
    private var previousToolbar: NSToolbar?
    private var restoreToolbarStyle: (() -> Void)?
    private var toolbar: NSToolbar?
    private var actionsItem: NSMenuToolbarItem?
    private var chatActionsItem: NSMenuToolbarItem?
    private var chatMenu = UIMenu(children: [])
    private var closeAssistant: () -> Void = {}
    private var menu = UIMenu(children: [])
    private var isMarinaPresented = false
    var toggleSidebar: () -> Void = {}
    var openAssistant: () -> Void = {}

    func attach(to scene: UIWindowScene) {
        guard let titlebar = scene.titlebar, self.scene !== scene else { return }
        if self.scene != nil { detach() }
        self.scene = scene
        previousToolbar = titlebar.toolbar
        let previousStyle = titlebar.toolbarStyle
        restoreToolbarStyle = { [weak scene] in
            scene?.titlebar?.toolbarStyle = previousStyle
        }
        let toolbar = NSToolbar(identifier: "Offshore.Home")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        self.toolbar = toolbar
        titlebar.toolbarStyle = .unified
        titlebar.toolbar = toolbar
    }

    func detach() {
        if let titlebar = scene?.titlebar, titlebar.toolbar === toolbar {
            titlebar.toolbar = previousToolbar
            restoreToolbarStyle?()
        }
        scene = nil
        previousToolbar = nil
        restoreToolbarStyle = nil
        toolbar = nil
        actionsItem = nil
        chatActionsItem = nil
        chatMenu = UIMenu(children: [])
        closeAssistant = {}
        menu = UIMenu(children: [])
        openAssistant = {}
        toggleSidebar = {}
    }

    func update(menu: UIMenu, isMarinaPresented: Bool, openAssistant: @escaping () -> Void) {
        self.menu = menu
        self.openAssistant = openAssistant
        actionsItem?.itemMenu = menu
        guard self.isMarinaPresented != isMarinaPresented else { return }
        self.isMarinaPresented = isMarinaPresented
        guard let toolbar else { return }
        // The system separators follow the native split columns as they resize.
        while !toolbar.items.isEmpty { toolbar.removeItem(at: 0) }
        for (index, identifier) in identifiers.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    func updateMarina(menu: UIMenu, onDismiss: @escaping () -> Void) {
        chatMenu = menu
        closeAssistant = onDismiss
        chatActionsItem?.itemMenu = menu
    }

    private var identifiers: [NSToolbarItem.Identifier] {
        var items: [NSToolbarItem.Identifier] = [
            .flexibleSpace, Self.sidebarID, .primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace, Self.actionsID
        ]
        if isMarinaPresented {
            items += [.supplementarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace, Self.chatActionsID, .space, Self.closeAssistantID]
        } else {
            items.append(Self.assistantID)
        }
        return items
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.actionsID:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "home.actions", defaultValue: "Home Actions")
            item.image = UIImage(systemName: "eye")
            item.itemMenu = menu
            item.showsIndicator = true
            actionsItem = item
            return item
        case Self.chatActionsID:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "marina.chat.actions", defaultValue: "Chat Actions", comment: "Accessibility label for Marina chat actions menu.")
            item.image = UIImage(systemName: "ellipsis")
            item.itemMenu = chatMenu
            item.showsIndicator = false
            chatActionsItem = item
            return item
        case Self.closeAssistantID:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = String(localized: "assistant.close", defaultValue: "Close Assistant", comment: "Accessibility label for closing assistant.")
            item.image = UIImage(systemName: "xmark")
            item.target = self
            item.action = #selector(didCloseAssistant)
            return item
        case Self.sidebarID, Self.assistantID:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self
            if identifier == Self.sidebarID {
                item.label = String(localized: "Sidebar")
                item.image = UIImage(systemName: "sidebar.left")
                item.action = #selector(didToggleSidebar)
            } else {
                item.label = String(localized: "assistant.open", defaultValue: "Open Assistant")
                item.image = UIImage(systemName: "figure.wave")
                item.action = #selector(didOpenAssistant)
                if #available(macCatalyst 26.0, *) {
                    item.style = .prominent
                    item.backgroundTintColor = UIColor(named: "AccentColor")
                }
            }
            return item
        default:
            return nil
        }
    }

    @objc private func didToggleSidebar() { toggleSidebar() }
    @objc private func didCloseAssistant() { closeAssistant() }
    @objc private func didOpenAssistant() { openAssistant() }
}
#endif
