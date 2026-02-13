import Foundation

// MARK: - ShortcutLinkKind

enum ShortcutLinkKind {
    case shortcut
    case automationTemplate
}

// MARK: - ShortcutLinkItem

struct ShortcutLinkItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImageName: String
    let url: URL
    let kind: ShortcutLinkKind
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
            kind: .shortcut
        ),
        ShortcutLinkItem(
            id: "start-excursion-mode",
            title: "Start Excursion Mode",
            subtitle: "Start your spending session with one tap.",
            systemImageName: "cart.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/c20b32cc454345558fb828e679aec1f7")!,
            kind: .shortcut
        ),
        ShortcutLinkItem(
            id: "add-income",
            title: "Add Income to Offshore",
            subtitle: "Quickly log an income entry.",
            systemImageName: "dollarsign",
            url: URL(string: "https://www.icloud.com/shortcuts/aab8aa44d1294828bf966b79c0178b44")!,
            kind: .shortcut
        )
    ]

    static let automationTemplates: [ShortcutLinkItem] = [
        ShortcutLinkItem(
            id: "tap-apple-card",
            title: "When I Tap My Apple Card",
            subtitle: "Template for logging transactions from a card tap trigger.",
            systemImageName: "wallet.sensor.tag.radiowaves.left.and.right.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/27ae7fa07f9f46ceb579553a0953c3cc")!,
            kind: .automationTemplate
        ),
        ShortcutLinkItem(
            id: "sms-credited",
            title: "When SMS Contains \"credited to your account\"",
            subtitle: "Template for income-from-message automation.",
            systemImageName: "message.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/613d0e270dbd41599f24e8aad851d9df")!,
            kind: .automationTemplate
        ),
        ShortcutLinkItem(
            id: "email-credited",
            title: "When Email Subject Contains \"credited to your account\"",
            subtitle: "Template for income-from-email automation.",
            systemImageName: "envelope.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/a8b5fbe82b33485db4959b0b21918d6f")!,
            kind: .automationTemplate
        )
    ]
}
