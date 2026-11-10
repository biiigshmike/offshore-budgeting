import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - QuickActionsInstallView

struct QuickActionsInstallView: View {

    let isOnboarding: Bool

    private var quickActionsHelpTopic: GeneratedHelpLeafTopic? {
        GeneratedHelpContent.visibleLeafTopic(for: "introduction-quick-actions")
    }

    init(isOnboarding: Bool = false) {
        self.isOnboarding = isOnboarding
    }

    private var isPhone: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #elseif canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        let base = VStack(alignment: .leading, spacing: 14) {
            if isOnboarding {
                header
            }

            List {
                ForEach(ShortcutLinkCatalog.installGroups) { group in
                    ShortcutDownloadSection(group: group)
                }
                if !isOnboarding {
                    helpSection
                }
            }
            .listStyle(.insetGrouped)
            .frame(minHeight: 300)

        }

        if isOnboarding {
            base
        } else {
            base
                .navigationTitle("Quick Actions")
        }
    }

    // MARK: - Sections

    private var helpSection: some View {
        Section {
            if let quickActionsHelpTopic {
                NavigationLink {
                    HelpTopicDetailView(topic: quickActionsHelpTopic)
                } label: {
                    Label("Setup Guide", systemImage: "book")
                }
            }
        } footer: {
            if isPhone {
                Text("Tap to Pay is configured directly in the Shortcuts app using Offshore’s built-in Add Expense action.\n\nThere is no Tap to Pay shortcut download. Use the Setup Guide for the manual automation steps.")
            }
        }
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Actions")
                .font(.title2.weight(.bold))
            Text("Download any shortcut links you want to use with Offshore. Everything here is optional, and you can install these later from Settings.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutDownloadSection: View {
    let group: ShortcutLinkGroup

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedVariantID: String

    init(group: ShortcutLinkGroup) {
        self.group = group
        _selectedVariantID = State(initialValue: group.variants.first?.id ?? "")
    }

    private var selectedVariant: ShortcutLinkVariant? {
        group.variants.first { $0.id == selectedVariantID }
    }

    var body: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize {
                versionPicker.pickerStyle(.inline)
            } else {
                versionPicker.pickerStyle(.segmented)
            }

            if let variant = selectedVariant {
                let title: LocalizedStringKey = variant.requiresAppleIntelligence ? "Download Apple Intelligence" : "Download Standard"
                Link(destination: variant.url) {
                    Label(title, systemImage: variant.systemImageName)
                }
                .accessibilityLabel(Text("Download \(group.title) - \(variant.title)"))
            }
        } header: {
            Text(group.title)
        } footer: {
            if selectedVariant?.requiresAppleIntelligence == true {
                Text("Requires Apple Intelligence")
            }
        }
    }

    private var versionPicker: some View {
        Picker("Version for \(group.title)", selection: $selectedVariantID) {
            ForEach(group.variants) { variant in
                Text(variant.title).tag(variant.id)
            }
        }
    }
}

#Preview("Quick Actions") {
    NavigationStack {
        QuickActionsInstallView()
    }
}
