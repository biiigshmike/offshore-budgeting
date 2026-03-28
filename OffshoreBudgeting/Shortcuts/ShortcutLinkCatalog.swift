import Foundation

// MARK: - ShortcutLinkVariant

struct ShortcutLinkVariant: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImageName: String
    let url: URL
    let platformNote: String?
    let requiresAppleIntelligence: Bool

    init(
        id: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        systemImageName: String,
        url: URL,
        platformNote: LocalizedStringResource? = nil,
        requiresAppleIntelligence: Bool = false
    ) {
        self.id = id
        self.title = String(localized: title)
        self.subtitle = String(localized: subtitle)
        self.systemImageName = systemImageName
        self.url = url
        self.platformNote = platformNote.map(String.init(localized:))
        self.requiresAppleIntelligence = requiresAppleIntelligence
    }

    var requirementLabel: String? {
        guard requiresAppleIntelligence else { return nil }
        return String(localized: "Apple Intelligence", defaultValue: "Apple Intelligence", comment: "Requirement label for shortcut variants that need Apple Intelligence.")
    }
}

// MARK: - ShortcutLinkGroup

struct ShortcutLinkGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let variants: [ShortcutLinkVariant]

    init(
        id: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        variants: [ShortcutLinkVariant]
    ) {
        self.id = id
        self.title = String(localized: title)
        self.subtitle = String(localized: subtitle)
        self.variants = variants
    }
}

// MARK: - ShortcutLinkCatalog

enum ShortcutLinkCatalog {
    static let installGroups: [ShortcutLinkGroup] = [
        ShortcutLinkGroup(
            id: "income-email",
            title: "Add Income From An Email",
            subtitle: "Install the version you want, then use the setup guide to connect it to your email automation.",
            variants: [
                ShortcutLinkVariant(
                    id: "income-email-non-ai",
                    title: "Non-Apple Intelligence",
                    subtitle: "Recommended default for broader device support.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/bdb4cf4e1f38431c9e6cc4353d1c9d71")!,
                    platformNote: "Supported on: iPhone, iPad, and Mac"
                ),
                ShortcutLinkVariant(
                    id: "income-email-ai",
                    title: "Apple Intelligence",
                    subtitle: "Uses Apple Intelligence for richer source naming when available.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/3dbbd2b0f2334e679be0b4b1e903f019")!,
                    platformNote: "Requires Apple Intelligence support on the device.",
                    requiresAppleIntelligence: true
                )
            ]
        ),
        ShortcutLinkGroup(
            id: "income-sms",
            title: "Add Income From An SMS Message",
            subtitle: "Install the version you want, then use the setup guide to connect it to your message automation.",
            variants: [
                ShortcutLinkVariant(
                    id: "income-sms-non-ai",
                    title: "Non-Apple Intelligence",
                    subtitle: "Recommended default for broader device support.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/ba5e0593ce9c4708b25930cdbaf683af")!,
                    platformNote: "Supported on: iPhone, iPad, and Mac"
                ),
                ShortcutLinkVariant(
                    id: "income-sms-ai",
                    title: "Apple Intelligence",
                    subtitle: "Uses Apple Intelligence for richer source naming when available.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/c97015724fdc433391d1afad6d928b88")!,
                    platformNote: "Requires Apple Intelligence support on the device.",
                    requiresAppleIntelligence: true
                )
            ]
        ),
        ShortcutLinkGroup(
            id: "expense-email",
            title: "Add Expense From Email",
            subtitle: "Install the version you want, then use the setup guide to connect it to your email automation.",
            variants: [
                ShortcutLinkVariant(
                    id: "expense-email-non-ai",
                    title: "Non-Apple Intelligence",
                    subtitle: "Recommended default for broader device support.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/bd258ccf9ccc47f18efba68c71913504")!,
                    platformNote: "Supported on: iPhone, iPad, and Mac"
                ),
                ShortcutLinkVariant(
                    id: "expense-email-ai",
                    title: "Apple Intelligence",
                    subtitle: "Uses Apple Intelligence for richer merchant naming when available.",
                    systemImageName: "square.and.arrow.down",
                    url: URL(string: "https://www.icloud.com/shortcuts/b6e256f053ba4ec79faffcd32477daf8")!,
                    platformNote: "Requires Apple Intelligence support on the device.",
                    requiresAppleIntelligence: true
                )
            ]
        )
    ]
}
