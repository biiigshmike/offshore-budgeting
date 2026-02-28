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
        var headerTitle: String { "What’s New • \(version) (Build \(localizedBuild))" }

        private var localizedBuild: String {
            guard let value = Int(build) else { return build }
            return value.formatted(.number)
        }
    }

    struct ReleaseItem: Identifiable {
        let systemImage: String
        let title: String
        let description: String

        var id: String { "\(systemImage)|\(title)" }
    }

    // MARK: - App Version

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var currentReleaseSection: ReleaseSection? {
        releaseSections.first {
            $0.version == appVersion && $0.build == appBuild
        }
    }

    // MARK: - Sections

    static let releaseSections: [ReleaseSection] = [
        ReleaseSection(
            version: "2.3.2",
            build: "14",
            items: [
                ReleaseItem(
                    systemImage: "wand.and.sparkles.inverse",
                    title: "Quality of Life Improvements",
                    description: "Swipe gestures enabled on the budgets list while on the Budgets tab."
                ),
                ReleaseItem(
                    systemImage: "pencil.and.list.clipboard",
                    title: "Enhancements to Onboarding",
                    description: "Onboarding now has additional steps included to walk new users through how use the swipe  and long-press gestures for editing and deleting. The onboarding process now allows for the capture of Income and creation of Budgets."
                )
            ]
        ),
        ReleaseSection(
            version: "2.3.1",
            build: "13",
            items: [
                ReleaseItem(
                    systemImage: "wand.and.sparkles.inverse",
                    title: "Quality of Life Improvements",
                    description: "2.3.1 includes quality of life improvements."
                ),
                ReleaseItem(
                    systemImage: "ladybug.slash",
                    title: "Squashed Bugs",
                    description: "Fixed a bug on Accounts where pressing the plus button did not render the Add Card or Add Reconcilation form."
                ),
                ReleaseItem(
                    systemImage: "banknote.fill",
                    title: "Enhancements to Savings Account",
                    description: "The in-app, workspace-scoped Savings Account now supports adding negative manual entries to transfer any amount of the running balance 'out' of the savings account to reflect when funds are moved to your actual bank's savings account."
                ),
                ReleaseItem(
                    systemImage: "slider.horizontal.below.rectangle",
                    title: "Splitting Transactions",
                    description: "Splitting transactions now supports splitting by percentage using a slider. This makes it so that the split amount value can be calculated easily."
                )
            ]
        ),
        ReleaseSection(
            version: "2.3",
            build: "9",
            items: [
                ReleaseItem(
                    systemImage: "figure.wave",
                    title: "Welcome Aboard, Marina!",
                    description: "Marina is Offshore’s new on-device financial assistant, available on the Home tab. She’s just getting her sea legs, so please be patient as she learns her way around. Marina runs entirely on your device and will improve with time. Try chatting with her to add income or expenses, explore savings goals, or gain quick insights into your finances."
                ),
                ReleaseItem(
                    systemImage: "sailboat.fill",
                    title: "Excursion Mode",
                    description: "Heading out to explore? Activate Excursion Mode to receive gentle reminders to log expenses when you’re near relevant points of interest. All processing happens on-device and can be turned on or off anytime."
                ),
                ReleaseItem(
                    systemImage: "creditcard.fill",
                    title: "Reconciliations and Savings: Now on the Accounts Tab",
                    description: "Accounts is now your place for Cards, Reconciliations, and a workspace-scoped Savings Account! You can now split expenses and track reconciliations. When adding or editing an expense, choose to split or offset it against a Reconciliation. View the running total and full expense history in Cards > Reconciliation. At the end of your budget periods, your Savings Account will keep a running total. This feature is designed to help offset future expenses with any surplus savings."
                ),
                ReleaseItem(
                    systemImage: "square.2.layers.3d.top.filled",
                    title: "Quick Actions",
                    description: "Optional Quick Actions are now available through Shortcuts and Automations. You’ll see them during Onboarding and in Settings > Install Quick Actions.\n\nThese are completely optional and can help automate adding income from SMS or email notifications, as well as logging expenses from Apple Wallet taps. Offshore works perfectly without them."
                ),
                ReleaseItem(
                    systemImage: "filemenu.and.selection",
                    title: "Screen-Aware Keyboard Shortcuts",
                    description: "The iPad and Mac menu bar has been refined with screen-aware keyboard shortcuts. Shortcuts now appear only where relevant and are organized into the appropriate menu sections."
                ),
                ReleaseItem(
                    systemImage: "eye",
                    title: "Expense Display",
                    description: "In Settings > General > Expense Display, it is now possible to hide future expenses from view, as well as excluding future expenses from being calculated. To toggle this temporarily, look for the eye button on Budget Details and Card Details."
                ),
                ReleaseItem(
                    systemImage: "widget.large.badge.plus",
                    title: "Two New Home Screen Widgets",
                    description: "Next Planned Expense and Spend Trends widgets are now available for the Home Screen. The Large and XXL Spend Trends widgets also incorporate Category Spotlight elements, showing spending by category as a percentage."
                )
            ]
        ),
        ReleaseSection(
            version: "2.2.1",
            build: "8",
            items: [
                ReleaseItem(
                    systemImage: "ladybug.slash",
                    title: "Swept for Bugs",
                    description: "Cleaned around the vault and managed to squash a few bugs and improve some UI glitches in the process."
                )
            ]
        ),
        ReleaseSection(
            version: "2.2",
            build: "7",
            items: [
                ReleaseItem(
                    systemImage: "server.rack",
                    title: "Database Migration",
                    description: "Upgraded Offshore’s underlying data storage for a faster, more reliable experience. If you were part of the beta, you’ll need to delete the previous version before installing 2.2. This change sets Offshore up for smoother sailing long-term."
                ),
                ReleaseItem(
                    systemImage: "wand.and.sparkles.inverse",
                    title: "App-Wide Sparkle and Polish",
                    description: "Small but noticeable app-wide improvements. The app will still feel instantly familiar, just with a more refined and timeless look."
                )
            ]
        ),
        ReleaseSection(
            version: "2.1.1",
            build: "1",
            items: [
                ReleaseItem(
                    systemImage: "building.columns.fill",
                    title: "Behind the Vault Improvements",
                    description: "Reinforced the vault for Offshore’s future, and cleared out a few barnacles so everything runs a bit faster."
                ),
                ReleaseItem(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Improvements to Importing Expenses",
                    description: "Incoming entries now come in with cleaner names instead of long strings of bank text. You can store preferred names locally so future imports recognize them automatically with the press of a toggle."
                )
            ]
        ),
        ReleaseSection(
            version: "2.1",
            build: "4",
            items: [
                ReleaseItem(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Import Entries",
                    description: "Import entries and income (.csv only) directly into a card from its detail view. Select what you want, then attach them instantly."
                ),
                ReleaseItem(
                    systemImage: "creditcard.fill",
                    title: "Customizable Card Appearances and Effects",
                    description: "Updated the Card creation form with a new Effects feature. Find the perfect effect to pair with your Card’s theme."
                ),
                ReleaseItem(
                    systemImage: "accessibility",
                    title: "Accessibility Improvements",
                    description: "App-wide accessibility updates, including Dynamic Type support and improved contrast. The Home grid was simplified to ensure full compliance."
                )
            ]
        ),
        ReleaseSection(
            version: "2.0",
            build: "1",
            items: [
                ReleaseItem(
                    systemImage: "building.columns.fill",
                    title: "Offshore Released to the Public",
                    description: "The vault is officially ready for its first Offshore account!"
                ),
                ReleaseItem(
                    systemImage: "widget.large.badge.plus",
                    title: "Widgets In and Out of the App",
                    description: "Track the metrics you care about most. Home is your dedicated budget dashboard, pin and reorder widgets to your liking. You can also pin select metrics on your iOS/macOS Home Screen."
                ),
                ReleaseItem(
                    systemImage: "sparkles",
                    title: "Polished the Vault Inside and Out",
                    description: "From the early days of landing on this deserted island to now, the app has been refined and polished throughout. Identity and brand have been set to sustain."
                )
            ]
        ),
        ReleaseSection(
            version: "1.0",
            build: "1",
            items: [
                ReleaseItem(
                    systemImage: "sailboat.fill",
                    title: "Set Sail to Find Better Waters",
                    description: "Embarked on a journey to create a budgeting app that values privacy, simplicity, and creative solutions. Dreamed day and night of an app that helps track and plan income, log expenses and understand spending, and build better habits to increase savings."
                )
            ]
        )
    ]

    var body: some View {
        List {
            ForEach(Self.releaseSections) { section in
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
                .foregroundStyle(Color("AccentColor"))
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
