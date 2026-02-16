import Foundation

// MARK: - ShortcutLinkItem

struct ShortcutLinkItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImageName: String
    let url: URL
    let platformNote: String?
    let setupInstructions: String?
}

// MARK: - ShortcutLinkCatalog

enum ShortcutLinkCatalog {
    static let shortcuts: [ShortcutLinkItem] = [
        ShortcutLinkItem(
            id: "add-expense",
            title: "Add Expense to Offshore",
            subtitle: "Quickly log a new expense from Control Center or Lock Screen.",
            systemImageName: "creditcard.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/5284c3fd6597408d9db06ad74371dc98")!,
            platformNote: nil,
            setupInstructions: nil
        ),
        ShortcutLinkItem(
            id: "start-excursion-mode",
            title: "Start Excursion Mode",
            subtitle: "Start your spending session with one tap.",
            systemImageName: "cart.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/c20b32cc454345558fb828e679aec1f7")!,
            platformNote: nil,
            setupInstructions: nil
        ),
        ShortcutLinkItem(
            id: "add-income",
            title: "Add Income to Offshore",
            subtitle: "Quickly log an income entry.",
            systemImageName: "dollarsign",
            url: URL(string: "https://www.icloud.com/shortcuts/aab8aa44d1294828bf966b79c0178b44")!,
            platformNote: nil,
            setupInstructions: nil
        )
    ]

    static let triggerShortcuts: [ShortcutLinkItem] = [
        ShortcutLinkItem(
            id: "tap-apple-card",
            title: "Add Expense From Tap To Pay",
            subtitle: "Install this shortcut, then run it from your Wallet tap automation.",
            systemImageName: "wallet.bifold",
            url: URL(string: "https://www.icloud.com/shortcuts/e6b198dbd3794e6988cb93bd87eba0b6")!,
            platformNote: "Supported on: iPhone",
            setupInstructions: "Create your trigger automation, then add Get Text from Shortcut Input and Run Shortcut."
        ),
        ShortcutLinkItem(
            id: "sms-credited",
            title: "Add Income From An SMS Message",
            subtitle: "Install this shortcut, then run it from your message automation.",
            systemImageName: "message.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/a8490bc9431c40c3aae04d4050cdf690")!,
            platformNote: "Supported on: iPhone, iPad, and Mac",
            setupInstructions: "Create your trigger automation, then add Get Text from Shortcut Input and Run Shortcut."
        ),
        ShortcutLinkItem(
            id: "email-credited",
            title: "Add Income From An Email",
            subtitle: "Install this shortcut, then run it from your email automation.",
            systemImageName: "envelope.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/dfdb203b9b7a48439319009e9c0e364b")!,
            platformNote: "Supported on: iPhone, iPad, and Mac",
            setupInstructions: "Create your trigger automation, then add Get Text from Shortcut Input and Run Shortcut."
        )
    ]
}
