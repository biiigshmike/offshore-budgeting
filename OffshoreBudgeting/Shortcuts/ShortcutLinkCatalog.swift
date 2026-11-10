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
            id: "income",
            title: "Add Income",
            subtitle: "Choose a version to use with an Email or Message automation.",
            variants: [
                ShortcutLinkVariant(
                    id: "income-standard",
                    title: "Standard",
                    subtitle: "Recommended default for broader device support.",
                    systemImageName: "square.2.layers.3d.top.filled",
                    url: URL(string: "https://www.icloud.com/shortcuts/53b01ca8d1e140e2aa94b55e7e4a15ec")!,
                    platformNote: "Supported on: iPhone, iPad, and Mac"
                ),
                ShortcutLinkVariant(
                    id: "income-ai",
                    title: "Apple Intelligence",
                    subtitle: "Uses Apple Intelligence for richer source naming when available.",
                    systemImageName: "square.2.layers.3d.top.filled",
                    url: URL(string: "https://www.icloud.com/shortcuts/8262c2e3b8a642d9a096ba05757ff545")!,
                    platformNote: "Requires Apple Intelligence support on the device.",
                    requiresAppleIntelligence: true
                )
            ]
        ),
        ShortcutLinkGroup(
            id: "expense",
            title: "Add Expense",
            subtitle: "Choose a version to use with an Email or Message automation.",
            variants: [
                ShortcutLinkVariant(
                    id: "expense-standard",
                    title: "Standard",
                    subtitle: "Recommended default for broader device support.",
                    systemImageName: "square.2.layers.3d.top.filled",
                    url: URL(string: "https://www.icloud.com/shortcuts/96f0316605544c8db7d7427eae2da568")!,
                    platformNote: "Supported on: iPhone, iPad, and Mac"
                ),
                ShortcutLinkVariant(
                    id: "expense-ai",
                    title: "Apple Intelligence",
                    subtitle: "Uses Apple Intelligence for richer merchant naming when available.",
                    systemImageName: "square.2.layers.3d.top.filled",
                    url: URL(string: "https://www.icloud.com/shortcuts/07af55bcac2246809332079a7d7218ac")!,
                    platformNote: "Requires Apple Intelligence support on the device.",
                    requiresAppleIntelligence: true
                )
            ]
        )
    ]
}
