import SwiftUI

// MARK: - QuickActionsInstallView

struct QuickActionsInstallView: View {

    let isOnboarding: Bool

    @Environment(\.openURL) private var openURL

    private var quickActionsHelpTopic: GeneratedHelpLeafTopic? {
        GeneratedHelpContent.visibleLeafTopic(for: "introduction-quick-actions")
    }

    init(isOnboarding: Bool = false) {
        self.isOnboarding = isOnboarding
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
                shortcutsSection
                if !isOnboarding {
                    builtInActionsSection
                    helpSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
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

    private var builtInActionsSection: some View {
        Section("Built-In Offshore Actions") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Expense, Add Income, Excursion Mode, Review Today, Safe Spend Today, and Forecast Savings are built into Offshore as native App Shortcuts.")
                    .font(.footnote)
                    .foregroundStyle(.primary)

                Text("Users can access them from the Shortcuts app, Siri, Spotlight, and the Action button on supported devices without downloading an iCloud shortcut link.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Control Center is best for quick actions like Add Expense, Add Income, Review Today, and Excursion Mode. Safe Spend Today and Forecast Savings are better surfaced as widgets.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var shortcutsSection: some View {
        Section("Shortcuts") {
            ForEach(ShortcutLinkCatalog.installGroups) { group in
                ShortcutLinkGroupCard(
                    group: group,
                    openURL: openURL
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
            }
            
            if !isOnboarding {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap to Pay is configured directly in the Shortcuts app using Offshore’s built-in Add Expense action.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("There is no Tap to Pay shortcut download. Use the Setup Guide for the manual automation steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var helpSection: some View {
        Section("Automation Setup Help") {
            if let quickActionsHelpTopic {
                NavigationLink {
                    HelpTopicDetailView(topic: quickActionsHelpTopic)
                } label: {
                    Text("Setup Guide for Installing Automation Shortcuts")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color("AccentColor"))
                }
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

private struct ShortcutLinkGroupCard: View {
    let group: ShortcutLinkGroup
    let openURL: OpenURLAction

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: max(1, min(2, group.variants.count)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(group.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(group.variants) { variant in
                    ShortcutLinkVariantCard(
                        variant: variant,
                        openURL: openURL
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private struct ShortcutLinkVariantCard: View {
    let variant: ShortcutLinkVariant
    let openURL: OpenURLAction

    var body: some View {
        Button {
            openURL(variant.url)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: variant.systemImageName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color("AccentColor"))
                }

                Text(variant.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(variant.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if let platformNote = variant.platformNote {
                    Text(platformNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Quick Actions") {
    NavigationStack {
        QuickActionsInstallView()
    }
}
