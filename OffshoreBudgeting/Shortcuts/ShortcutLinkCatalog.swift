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
            id: "start-excursion-mode",
            title: "Start Excursion Mode",
            subtitle: "Start your spending session with one tap.",
            systemImageName: "cart.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/c20b32cc454345558fb828e679aec1f7")!,
            platformNote: nil,
            setupInstructions: nil
        )
    ]

    static let triggerShortcuts: [ShortcutLinkItem] = [
        ShortcutLinkItem(
            id: "amazon-ordered",
            title: "Add Amazon Expense From Amazon.com",
            subtitle: "Install this shortcut, then run it from your Amazon confirmation email automation.",
            systemImageName: "cart.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/dfdc98c5724b4c13ac021f55134882ef")!,
            platformNote: "Supported on: iPhone, iPad, and Mac",
            setupInstructions: "When I get an email subject contains \"Ordered:\" from auto-confirm@amazon.com -> Run Immediately -> Create New Shortcut -> Search for \"Run Shortcut\" -> Add Amazon Expense From Amazon.com -> Down Arrow -> Input: Choose Variable -> Shortcut Input -> Save."
        ),
        ShortcutLinkItem(
            id: "email-credited",
            title: "Add Income From An Email",
            subtitle: "Install this shortcut, then run it from your email automation.",
            systemImageName: "envelope.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/791f1d8f99634215a7fdb71f5a606fe6")!,
            platformNote: "Supported on: iPhone, iPad, and Mac",
            setupInstructions: "When I get an email subject contains \"credited to your account\" -> Run Immediately -> Create New Shortcut -> Search for \"Run Shortcut\" -> Add Income From An Email -> Down Arrow -> Input: Choose Variable -> Shortcut Input -> Save."
        ),
        ShortcutLinkItem(
            id: "sms-credited",
            title: "Add Income From An SMS Message",
            subtitle: "Install this shortcut, then run it from your message automation.",
            systemImageName: "message.fill",
            url: URL(string: "https://www.icloud.com/shortcuts/6ebb3d15fa444f9e9b880907cbb5978a")!,
            platformNote: "Supported on: iPhone, iPad, and Mac",
            setupInstructions: "When message contains \"credited to your account ending in x1234\" -> Run Immediately -> Create New Shortcut -> Search for \"Run Shortcut\" -> Add Income From An SMS Message -> Down Arrow -> Input: Choose Variable -> Shortcut Input -> Save."
        )
    ]
}
