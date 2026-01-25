//
//  SettingsReleaseLogsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//


import SwiftUI

struct SettingsReleaseLogsView: View {

    struct ReleaseSection: Identifiable {
        let version: String
        let build: String
        let items: [ReleaseItem]

        var id: String { "\(version)-\(build)" }
        var headerTitle: String { "What’s New • \(version) (Build \(build))" }
    }

    struct ReleaseItem: Identifiable {
        let systemImage: String
        let title: String
        let description: String

        var id: String { "\(systemImage)|\(title)" }
    }

    // MARK: - Placeholder data (we’ll swap to AppUpdateLogs next)

    private let sections: [ReleaseSection] = [
        ReleaseSection(
            version: "2.1.1",
            build: "2",
            items: [
                ReleaseItem(
                    systemImage: "building.columns",
                    title: "Behind the Vault Improvements",
                    description: "Reinforced the vault for Offshore’s future. Cleared out a few barnacles to help everything run faster."
                ),
                ReleaseItem(
                    systemImage: "creditcard",
                    title: "Improvements to Importing Expenses",
                    description: "Incoming transactions now come pre-loaded with cleaner names instead of long strings of bank text. You can store preferred names locally so future imports recognize the preferred name automatically."
                )
            ]
        ),
        ReleaseSection(
            version: "2.1",
            build: "4",
            items: [
                ReleaseItem(
                    systemImage: "square.and.arrow.down",
                    title: "Import Transactions & Card Themes",
                    description: "Import .csv transactions directly into a card from its detail view. Select what you want and attach them instantly. Updated Card creation form with new Effects feature. Find the perfect effect to pair with your Card’s theme."
                ),
                ReleaseItem(
                    systemImage: "figure.walk",
                    title: "Accessibility Improvements",
                    description: "App-wide accessibility updates, including Dynamic Type and improved contrast. The Home grid was simplified to ensure full compliance."
                ),
                ReleaseItem(
                    systemImage: "hand.raised",
                    title: "Privacy & Security",
                    description: "Biometric prompts now appear only on enrolled devices. You can also lock the app using your device passcode, if enabled."
                ),
                ReleaseItem(
                    systemImage: "lightbulb",
                    title: "Tips & Hints",
                    description: "Tips now appear only once per screen, or when manually reset in Settings. What’s New alerts appear only for significant updates."
                )
            ]
        )
    ]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.headerTitle) {
                    ForEach(section.items) { item in
                        ReleaseRow(item: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Release Logs")
    }
}

// MARK: - Row

private struct ReleaseRow: View {

    let item: SettingsReleaseLogsView.ReleaseItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview("Release Logs") {
    NavigationStack {
        SettingsReleaseLogsView()
    }
}
