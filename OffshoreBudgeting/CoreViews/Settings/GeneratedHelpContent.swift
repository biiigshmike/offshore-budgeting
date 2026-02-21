//
//  GeneratedHelpContent.swift
//  OffshoreBudgeting
//
//  In-app help content source for Offshore.
//  Maintained directly in this file.
//

import Foundation

enum GeneratedHelpDestinationGroup: String {
    case gettingStarted
    case coreScreens
}

enum GeneratedHelpIconStyle: String {
    case gray
    case blue
    case purple
    case red
    case green
    case orange
}

struct GeneratedHelpLine: Hashable {
    enum Kind: String {
        case text
        case bullet
        case heroScreenshot
        case miniScreenshot
    }

    let kind: Kind
    let value: String
}

struct GeneratedHelpSectionMediaItem: Identifiable, Hashable {
    let id: String
    let assetName: String
    let bodyText: String
}

struct GeneratedHelpSection: Identifiable, Hashable {
    let id: String
    let header: String?
    let lines: [GeneratedHelpLine]
}

struct GeneratedHelpLeafTopic: Identifiable, Hashable {
    let id: String
    let destinationID: String
    let title: String
    let sections: [GeneratedHelpSection]
    let assetPrefix: String?

    var searchableText: String {
        var parts: [String] = [title]

        for section in sections {
            if let header = section.header {
                parts.append(header)
            }

            for mediaItem in mediaItems(for: section) {
                parts.append(mediaItem.bodyText)
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Section Media

    // I keep two media slots per section so I can swap screenshots in Assets.xcassets later.
    func mediaItems(for section: GeneratedHelpSection) -> [GeneratedHelpSectionMediaItem] {
        let sectionBodyText = section.condensedBodyText
        var items: [GeneratedHelpSectionMediaItem] = []

        for slot in section.screenshotSlots.prefix(2) {
            items.append(
                GeneratedHelpSectionMediaItem(
                    id: "\(section.id)-media-\(items.count + 1)",
                    assetName: screenshotAssetName(slot: slot),
                    bodyText: sectionBodyText
                )
            )
        }

        while items.count < 2 {
            let placeholderSlot = items.count + 1
            items.append(
                GeneratedHelpSectionMediaItem(
                    id: "\(section.id)-media-\(placeholderSlot)",
                    assetName: section.placeholderAssetName(slot: placeholderSlot),
                    bodyText: sectionBodyText
                )
            )
        }

        return items
    }

    // MARK: - Screenshot Import Guide

    // I name section placeholders as Help-<section-id>-1 and Help-<section-id>-2 in Assets.xcassets.
    var sectionImportAssetNames: [String: [String]] {
        var mapping: [String: [String]] = [:]

        for section in sections {
            mapping[section.id] = mediaItems(for: section).map(\.assetName)
        }

        return mapping
    }

    private func screenshotAssetName(slot: Int) -> String {
        if let assetPrefix = assetPrefix {
            return "\(assetPrefix)-\(slot)"
        }

        let fallbackTitle = title.replacingOccurrences(of: " ", with: "")
        return "Help-\(fallbackTitle)-\(slot)"
    }
}

struct GeneratedHelpDestination: Identifiable, Hashable {
    let id: String
    let title: String
    let group: GeneratedHelpDestinationGroup
    let iconSystemName: String
    let iconStyle: GeneratedHelpIconStyle
    let leafTopicIDs: [String]
}

enum GeneratedHelpContent {
    static let bookTitle: String = "Offshore Help"
    static let bookIdentifier: String = "com.mb.offshore.help"

    // MARK: - Destinations

    static let destinations: [GeneratedHelpDestination] = [
        GeneratedHelpDestination(
            id: "introduction",
            title: "Introduction",
            group: .gettingStarted,
            iconSystemName: "exclamationmark.bubble",
            iconStyle: .blue,
            leafTopicIDs: [
                "introduction-building-blocks",
                "introduction-planned-expenses",
                "introduction-variable-expenses",
                "introduction-planned-income",
                "introduction-actual-income",
                "introduction-budgets",
                "introduction-calculations",
                "introduction-import",
                "introduction-quick-actions",
                "introduction-excursion-mode"
            ]
        ),
        GeneratedHelpDestination(
            id: "home",
            title: "Home",
            group: .coreScreens,
            iconSystemName: "house.fill",
            iconStyle: .purple,
            leafTopicIDs: [
                "home-overview",
                "home-widgets",
                "home-customization",
                "home-calculations",
                "home-marina"
            ]
        ),
        GeneratedHelpDestination(
            id: "budgets",
            title: "Budgets",
            group: .coreScreens,
            iconSystemName: "chart.pie.fill",
            iconStyle: .blue,
            leafTopicIDs: [
                "budgets-overview",
                "budgets-details",
                "budgets-calculations"
            ]
        ),
        GeneratedHelpDestination(
            id: "income",
            title: "Income",
            group: .coreScreens,
            iconSystemName: "calendar",
            iconStyle: .red,
            leafTopicIDs: [
                "income-overview",
                "income-planned-vs-actual",
                "income-calculations"
            ]
        ),
        GeneratedHelpDestination(
            id: "accounts",
            title: "Accounts",
            group: .coreScreens,
            iconSystemName: "creditcard.fill",
            iconStyle: .green,
            leafTopicIDs: [
                "accounts-overview",
                "accounts-card-details",
                "accounts-calculations",
                "accounts-reconciliations",
                "accounts-savings-account"
            ]
        ),
        GeneratedHelpDestination(
            id: "settings",
            title: "Settings",
            group: .coreScreens,
            iconSystemName: "gear",
            iconStyle: .gray,
            leafTopicIDs: [
                "settings-overview",
                "settings-expense-display-toggles",
                "settings-hide-vs-exclude",
                "settings-workspaces",
                "settings-presets"
            ]
        )
    ]

    // MARK: - Leaf Topics

    static let allLeafTopics: [GeneratedHelpLeafTopic] = [
        GeneratedHelpLeafTopic(
            id: "introduction-building-blocks",
            destinationID: "introduction",
            title: "The Building Blocks",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-building-blocks-1",
                    header: "The Building Blocks",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Welcome to Offshore Budgeting, a privacy-first budgeting app. All data is processed on your device, and you will never be asked to connect a bank account."),
                        GeneratedHelpLine(kind: .text, value: "Cards, Income, Expense Categories, Presets, and Budgets are the foundation:"),
                        GeneratedHelpLine(kind: .bullet, value: "Cards hold your expenses and let you analyze spending by card."),
                        GeneratedHelpLine(kind: .bullet, value: "Income is tracked as planned or actual. Planned income helps you forecast savings, while actual income powers real savings calculations."),
                        GeneratedHelpLine(kind: .bullet, value: "Expense Categories describe what an expense was for, like groceries, rent, or fuel."),
                        GeneratedHelpLine(kind: .bullet, value: "Presets are reusable planned expenses for recurring bills."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable expenses are one-off or unpredictable expenses tied to a card."),
                        GeneratedHelpLine(kind: .bullet, value: "Budgets group a date range so the app can summarize income, expenses, and savings for that period.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-planned-expenses",
            destinationID: "introduction",
            title: "Planned Expenses",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-planned-expenses-1",
                    header: "Planned Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Expected or recurring costs for a budget period, like rent or subscriptions."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned Amount: the amount you expect to debit from your account."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Amount: if a planned expense costs more or less than expected, edit the planned expense and enter the actual amount.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-variable-expenses",
            destinationID: "introduction",
            title: "Variable Expenses",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-variable-expenses-1",
                    header: "Variable Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Unpredictable, one-off costs during a budget period, like fuel or dining. These are always treated as actual spending and are tracked by card and category.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-planned-income",
            destinationID: "introduction",
            title: "Planned Income",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-planned-income-1",
                    header: "Planned Income",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Income you expect to receive, like salary or deposits. Planned income is used for forecasts and potential savings."),
                        GeneratedHelpLine(kind: .bullet, value: "Use planned income to help plan your budget. If income is very consistent, consider recurring actual income instead.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-actual-income",
            destinationID: "introduction",
            title: "Actual Income",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-actual-income-1",
                    header: "Actual Income",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Income you actually receive. Actual income drives real totals, real savings, and the amount you can still spend safely."),
                        GeneratedHelpLine(kind: .bullet, value: "Income can be logged as actual when received, or set as recurring actual income for consistent paychecks.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-budgets",
            destinationID: "introduction",
            title: "Budgets",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-budgets-1",
                    header: "Budgets",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Budgets are a lens for viewing your income and expenses over a specific date range. Create budgets that align with your financial goals and pay cycles.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-calculations",
            destinationID: "introduction",
            title: "Calculations",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-calculations-1",
                    header: "How Totals Are Calculated",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Everything in Offshore is basic math:"),
                        GeneratedHelpLine(kind: .bullet, value: "Planned expenses total = sum of planned amounts for planned expenses in the budget period."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual planned expenses total = sum of actual amounts for those planned expenses."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable expenses total = sum of variable expenses in the budget period."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned income total = sum of income entries marked Planned in the period."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual income total = sum of income entries marked Actual in the period."),
                        GeneratedHelpLine(kind: .bullet, value: "Potential savings = planned income total - planned expenses planned total."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual savings = actual income total - (planned expenses actual total + variable expenses total).")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-import",
            destinationID: "introduction",
            title: "Import",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-import-1",
                    header: "Import Workflow for Income and Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Offshore can parse files, photos, and clipboard text to speed up entry.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-import-2",
                    header: "Supported Import Sources",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "You can import from:"),
                        GeneratedHelpLine(kind: .bullet, value: "Files (CSV, PDF, image)"),
                        GeneratedHelpLine(kind: .bullet, value: "Photos"),
                        GeneratedHelpLine(kind: .bullet, value: "Clipboard text"),
                        GeneratedHelpLine(kind: .bullet, value: "Shortcut screenshot or clipboard preview flows")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-import-3",
                    header: "Review Before You Commit",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Imports open a review screen before anything is saved."),
                        GeneratedHelpLine(kind: .bullet, value: "Ready to Import"),
                        GeneratedHelpLine(kind: .bullet, value: "Possible Matches"),
                        GeneratedHelpLine(kind: .bullet, value: "Possible Duplicates"),
                        GeneratedHelpLine(kind: .bullet, value: "Needs More Data / Skipped rows")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-import-4",
                    header: "Commit and Learning",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "After review, tap Import to save selected rows."),
                        GeneratedHelpLine(kind: .bullet, value: "Offshore stores merchant/category matching signals to improve future imports."),
                        GeneratedHelpLine(kind: .bullet, value: "Expense imports route to a selected card."),
                        GeneratedHelpLine(kind: .bullet, value: "Income imports route to income entries.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-quick-actions",
            destinationID: "introduction",
            title: "Quick Actions",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-quick-actions-1",
                    header: "Quick Actions: Shortcut Entry Points",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Quick Actions are optional. Install the shared shortcuts first, then set up the matching automations in Shortcuts."),
                        GeneratedHelpLine(kind: .bullet, value: "Add Expense to Offshore"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income to Offshore"),
                        GeneratedHelpLine(kind: .bullet, value: "Start Excursion Mode")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-2",
                    header: "Shortcuts & Automations",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Trigger automations can feed Offshore from Wallet, Messages, and Email."),
                        GeneratedHelpLine(kind: .bullet, value: "Add Expense From Tap To Pay"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income From An SMS Message"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income From An Email"),
                        GeneratedHelpLine(kind: .bullet, value: "Use Run Immediately for the smoothest experience.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-3",
                    header: "App Shortcuts You Can Run Anytime",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Offshore also exposes direct shortcuts for common actions."),
                        GeneratedHelpLine(kind: .bullet, value: "Log Expense"),
                        GeneratedHelpLine(kind: .bullet, value: "Log Income"),
                        GeneratedHelpLine(kind: .bullet, value: "Review Today's Spending"),
                        GeneratedHelpLine(kind: .bullet, value: "Forecast Savings"),
                        GeneratedHelpLine(kind: .bullet, value: "What Can I Spend Today?"),
                        GeneratedHelpLine(kind: .bullet, value: "Open Quick Add flows")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-4",
                    header: "Before You Start",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "Open Offshore > Settings > Quick Actions."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap each shortcut link and import it in Shortcuts."),
                        GeneratedHelpLine(kind: .bullet, value: "Confirm the imported shortcut names are correct.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-5",
                    header: "Add Expense From Tap To Pay",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "Open Shortcuts > Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap New Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Scroll down and select Wallet."),
                        GeneratedHelpLine(kind: .bullet, value: "Configure this screen to your liking. You can choose which card or cards should trigger the automation. It is recommended to leave all categories selected. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience."),
                        GeneratedHelpLine(kind: .bullet, value: "On the next screen, tap Create New Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Get Text from Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "In this action, tap the blue Input field and choose Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Run Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "In Run Shortcut, tap the blue Shortcut field and select Add Expense From Tap To Pay."),
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-6",
                    header: "Add Income From An SMS Message",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "Open Shortcuts > Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap New Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Scroll down and select Message."),
                        GeneratedHelpLine(kind: .bullet, value: "Configure this screen to your liking. For example, use Message Contains and type the exact phrasing your bank uses in deposit notifications. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience."),
                        GeneratedHelpLine(kind: .bullet, value: "On the next screen, tap Create New Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Get Text from Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "In this action, tap the blue Input field and choose Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Run Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "In Run Shortcut, tap the blue Shortcut field and select Add Income From An SMS Message."),
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-7",
                    header: "Add Income From An Email",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "Open Shortcuts > Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap New Automation."),
                        GeneratedHelpLine(kind: .bullet, value: "Scroll down and select Email."),
                        GeneratedHelpLine(kind: .bullet, value: "Configure this screen to your liking. For example, use Subject Contains and type the exact phrasing your bank uses in deposit email subject lines. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience."),
                        GeneratedHelpLine(kind: .bullet, value: "On the next screen, tap Create New Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Get Text from Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "In this action, tap the blue Input field and choose Shortcut Input."),
                        GeneratedHelpLine(kind: .bullet, value: "Add action: Run Shortcut."),
                        GeneratedHelpLine(kind: .bullet, value: "In Run Shortcut, tap the blue Shortcut field and select Add Income From An Email."),
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-quick-actions-8",
                    header: "Troubleshooting",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "If a shared item imports with a long autogenerated name, rename the shortcut after import."),
                        GeneratedHelpLine(kind: .bullet, value: "If you do not see the expected trigger type, make sure your device and iOS version support that trigger."),
                        GeneratedHelpLine(kind: .bullet, value: "If the last Offshore action appears missing, confirm Offshore is installed on that device, then edit the shortcut and add Offshore Add Income or Add Expense as the last action again."),
                        GeneratedHelpLine(kind: .bullet, value: "If an automation does not fire, open it in Shortcuts and verify trigger condition text, selected Run Shortcut action, and run behavior settings.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-excursion-mode",
            destinationID: "introduction",
            title: "Excursion Mode",
            sections: [
                GeneratedHelpSection(
                    id: "introduction-excursion-mode-1",
                    header: "Excursion Mode: Temporary Spending Session",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Excursion Mode is a timed session for in-the-moment spending.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-excursion-mode-2",
                    header: "Start, Stop, and Extend",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "You can start Excursion Mode from Notifications, Shortcuts, or in-app controls."),
                        GeneratedHelpLine(kind: .bullet, value: "Start for 1, 2, or 4 hours."),
                        GeneratedHelpLine(kind: .bullet, value: "Stop anytime."),
                        GeneratedHelpLine(kind: .bullet, value: "Extend active sessions by 30 minutes.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-excursion-mode-3",
                    header: "Session Signals",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "While active, Offshore can surface session status and nudges."),
                        GeneratedHelpLine(kind: .bullet, value: "Live Activity support on iPhone."),
                        GeneratedHelpLine(kind: .bullet, value: "Optional location-aware reminders."),
                        GeneratedHelpLine(kind: .bullet, value: "Session status appears in relevant controls until expiration.")
                    ]
                )
            ],
            assetPrefix: nil
        ),

        GeneratedHelpLeafTopic(
            id: "home-overview",
            destinationID: "home",
            title: "Overview",
            sections: [
                GeneratedHelpSection(
                    id: "home-overview-1",
                    header: "Home: Welcome to Your Dashboard",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "You can pick your own custom start and end date, or use predefined ranges in the period menu. Widgets respond to the date range you select.")
                    ]
                )
            ],
            assetPrefix: "Help-Home"
        ),
        GeneratedHelpLeafTopic(
            id: "home-widgets",
            destinationID: "home",
            title: "Widgets",
            sections: [
                GeneratedHelpSection(
                    id: "home-widgets-1",
                    header: "Widgets Overview",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Home is made of widgets. Tap any widget to open its detail page."),
                        GeneratedHelpLine(kind: .bullet, value: "Income: shows actual income versus planned income."),
                        GeneratedHelpLine(kind: .bullet, value: "Savings Outlook: projected savings based on planned income and planned expenses."),
                        GeneratedHelpLine(kind: .bullet, value: "Next Planned Expense: displays the next upcoming planned expense."),
                        GeneratedHelpLine(kind: .bullet, value: "Category Spotlight: top categories by spend in the current range."),
                        GeneratedHelpLine(kind: .bullet, value: "Spend Trends: spend totals by day, week, or month depending on range."),
                        GeneratedHelpLine(kind: .bullet, value: "Category Availability: category caps and remaining amounts for the period."),
                        GeneratedHelpLine(kind: .bullet, value: "What If?: interactive scenario planner for budget outcomes.")
                    ]
                )
            ],
            assetPrefix: "Help-Home"
        ),
        GeneratedHelpLeafTopic(
            id: "home-customization",
            destinationID: "home",
            title: "Customization",
            sections: [
                GeneratedHelpSection(
                    id: "home-customization-1",
                    header: "HomeView & Customization",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Use Edit on Home to choose what appears on your dashboard."),
                        GeneratedHelpLine(kind: .bullet, value: "Pin widgets and cards you care about most."),
                        GeneratedHelpLine(kind: .bullet, value: "Reorder pinned items to put key metrics first."),
                        GeneratedHelpLine(kind: .bullet, value: "Remove items you do not need right now."),
                        GeneratedHelpLine(kind: .bullet, value: "Keep Home focused on the date range and metrics you actually use.")
                    ]
                )
            ],
            assetPrefix: "Help-Home"
        ),
        GeneratedHelpLeafTopic(
            id: "home-calculations",
            destinationID: "home",
            title: "Calculations",
            sections: [
                GeneratedHelpSection(
                    id: "home-calculations-1",
                    header: "Home Calculations",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Home calculations mirror budget math."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Savings = actual income - (planned expenses effective amount + variable expenses total)."),
                        GeneratedHelpLine(kind: .bullet, value: "Remaining Income = actual income - expenses.")
                    ]
                )
            ],
            assetPrefix: "Help-Home"
        ),
        GeneratedHelpLeafTopic(
            id: "home-marina",
            destinationID: "home",
            title: "Marina",
            sections: [
                GeneratedHelpSection(
                    id: "home-marina-1",
                    header: "Marina: Built-In Home Assistant",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Marina is your in-app budget assistant on Home. She answers from your Offshore data.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "home-marina-2",
                    header: "What You Can Ask",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Marina supports practical spending and savings questions."),
                        GeneratedHelpLine(kind: .bullet, value: "\"How am I doing this month?\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Top categories this month\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Largest recent expenses\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"How is my savings status?\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Do I have presets due soon?\"")
                    ]
                ),
                GeneratedHelpSection(
                    id: "home-marina-3",
                    header: "Clarifications and Follow-Ups",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "If a request is unclear, Marina asks quick clarifying questions."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap a follow-up suggestion to refine results."),
                        GeneratedHelpLine(kind: .bullet, value: "Use specific dates, categories, or cards for tighter answers."),
                        GeneratedHelpLine(kind: .bullet, value: "Treat responses as decision support based on your current data.")
                    ]
                )
            ],
            assetPrefix: nil
        ),

        GeneratedHelpLeafTopic(
            id: "budgets-overview",
            destinationID: "budgets",
            title: "Overview",
            sections: [
                GeneratedHelpSection(
                    id: "budgets-overview-1",
                    header: "Budgets: Where the Actual Budgeting Work Happens",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "This screen lists past, active, and upcoming budgets. Tap any budget to open details and add expenses, assign cards, and monitor budget metrics.")
                    ]
                )
            ],
            assetPrefix: "Help-Budgets"
        ),
        GeneratedHelpLeafTopic(
            id: "budgets-details",
            destinationID: "budgets",
            title: "Budget Details",
            sections: [
                GeneratedHelpSection(
                    id: "budgets-details-1",
                    header: "Budget Details: Build the Budget",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Inside a budget, you track expenses in two lanes:"),
                        GeneratedHelpLine(kind: .bullet, value: "Planned: recurring or expected costs."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable: one-off spending from your cards."),
                        GeneratedHelpLine(kind: .bullet, value: "Categories: long-press a category and assign a spending cap for this budgeting period.")
                    ]
                )
            ],
            assetPrefix: "Help-Budgets"
        ),
        GeneratedHelpLeafTopic(
            id: "budgets-calculations",
            destinationID: "budgets",
            title: "Calculations",
            sections: [
                GeneratedHelpSection(
                    id: "budgets-calculations-1",
                    header: "How Budget Totals Are Calculated",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "These totals are shown in the budget header."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned Income = planned income total in this period."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Income = actual income total in this period."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned Total = sum of planned expense planned amounts."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable Total = sum of variable expenses in the period."),
                        GeneratedHelpLine(kind: .bullet, value: "Unified Total = planned effective total + variable total."),
                        GeneratedHelpLine(kind: .bullet, value: "Max Savings = planned income - planned expenses effective total."),
                        GeneratedHelpLine(kind: .bullet, value: "Projected Savings = planned income - planned expenses planned total."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Savings = actual income - (planned expenses effective total + variable expenses total).")
                    ]
                )
            ],
            assetPrefix: "Help-Budgets"
        ),

        GeneratedHelpLeafTopic(
            id: "income-overview",
            destinationID: "income",
            title: "Overview",
            sections: [
                GeneratedHelpSection(
                    id: "income-overview-1",
                    header: "Income: Calendar-Based Tracking",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "The calendar shows planned and actual income totals per day. Tap a day to see entries and weekly totals.")
                    ]
                )
            ],
            assetPrefix: "Help-Income"
        ),
        GeneratedHelpLeafTopic(
            id: "income-planned-vs-actual",
            destinationID: "income",
            title: "Planned vs Actual",
            sections: [
                GeneratedHelpSection(
                    id: "income-planned-vs-actual-1",
                    header: "Planned Income vs Actual Income",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "If your paycheck is consistent, create recurring actual income. If it varies, use planned income to estimate and log actual income when it arrives.")
                    ]
                )
            ],
            assetPrefix: "Help-Income"
        ),
        GeneratedHelpLeafTopic(
            id: "income-calculations",
            destinationID: "income",
            title: "Calculations",
            sections: [
                GeneratedHelpSection(
                    id: "income-calculations-1",
                    header: "How Income Feeds the App",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Income entries contribute to Home and Budget calculations. Actual income drives real totals and savings, while planned income supports forecasts.")
                    ]
                )
            ],
            assetPrefix: "Help-Income"
        ),

        GeneratedHelpLeafTopic(
            id: "accounts-overview",
            destinationID: "accounts",
            title: "Overview",
            sections: [
                GeneratedHelpSection(
                    id: "accounts-overview-1",
                    header: "Accounts: Spending Account Gallery",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Tap + to add an account card. Tap a card to open detail view.")
                    ]
                )
            ],
            assetPrefix: "Help-Accounts"
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-card-details",
            destinationID: "accounts",
            title: "Card Details",
            sections: [
                GeneratedHelpSection(
                    id: "accounts-card-details-1",
                    header: "Card Detail: Deep Dive",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Card detail is a focused spending console with filters, scope controls, sorting, and search.")
                    ]
                )
            ],
            assetPrefix: "Help-Accounts"
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-calculations",
            destinationID: "accounts",
            title: "Calculations",
            sections: [
                GeneratedHelpSection(
                    id: "accounts-calculations-1",
                    header: "Card Calculations",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Totals reflect the current filters. Variable expenses are always actual. Planned expenses use actual amount when provided, otherwise planned amount.")
                    ]
                )
            ],
            assetPrefix: "Help-Accounts"
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-reconciliations",
            destinationID: "accounts",
            title: "Reconciliations",
            sections: [
                GeneratedHelpSection(
                    id: "accounts-reconciliations-1",
                    header: "Reconciliations: Track Shared Spending in One Place",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Reconciliations help you track money you fronted, split, or need to settle with someone else.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "accounts-reconciliations-2",
                    header: "Create and Manage Reconciliations",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "From Accounts > Reconciliations, tap + to add a reconciliation."),
                        GeneratedHelpLine(kind: .bullet, value: "Name each balance clearly (for example: Roommate, Trip Fund, Work Lunches)."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap a balance to open details."),
                        GeneratedHelpLine(kind: .bullet, value: "Edit from the context menu.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "accounts-reconciliations-3",
                    header: "Settlements and History",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Reconciliations keep a running ledger from allocations and settlements."),
                        GeneratedHelpLine(kind: .bullet, value: "Settlements move the balance toward zero."),
                        GeneratedHelpLine(kind: .bullet, value: "Balances with history are archived instead of hard deleted."),
                        GeneratedHelpLine(kind: .bullet, value: "Archived balances stay in history but are hidden from new choices.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-savings-account",
            destinationID: "accounts",
            title: "Savings Account",
            sections: [
                GeneratedHelpSection(
                    id: "accounts-savings-account-1",
                    header: "Savings Account: Your Savings Ledger",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Savings gives you a dedicated ledger and running total for money you are setting aside.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "accounts-savings-account-2",
                    header: "Add and Manage Savings Entries",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "From Accounts > Savings, tap + to add a ledger entry."),
                        GeneratedHelpLine(kind: .bullet, value: "Add positive entries for contributions."),
                        GeneratedHelpLine(kind: .bullet, value: "Add negative entries for withdrawals."),
                        GeneratedHelpLine(kind: .bullet, value: "Swipe to edit or delete an entry.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "accounts-savings-account-3",
                    header: "Savings Trend and Date Range",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Savings includes a trend chart and date range filter."),
                        GeneratedHelpLine(kind: .bullet, value: "Use date range controls to review a period."),
                        GeneratedHelpLine(kind: .bullet, value: "Running Total reflects your full ledger balance."),
                        GeneratedHelpLine(kind: .bullet, value: "The chart helps you see momentum over time.")
                    ]
                )
            ],
            assetPrefix: nil
        ),

        GeneratedHelpLeafTopic(
            id: "settings-overview",
            destinationID: "settings",
            title: "Overview",
            sections: [
                GeneratedHelpSection(
                    id: "settings-overview-1",
                    header: "Settings: Configure Offshore",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Every row is a separate area to manage your Offshore experience."),
                        GeneratedHelpLine(kind: .bullet, value: "About: version info, contact support, release logs."),
                        GeneratedHelpLine(kind: .bullet, value: "Help: this guide and Repeat Onboarding."),
                        GeneratedHelpLine(kind: .bullet, value: "Install Quick Actions: shortcut install links and trigger setup guidance."),
                        GeneratedHelpLine(kind: .bullet, value: "General: currency, budget period, tips reset, erase content."),
                        GeneratedHelpLine(kind: .bullet, value: "Privacy: biometrics app lock."),
                        GeneratedHelpLine(kind: .bullet, value: "Notifications: reminders for daily spending, income comparisons, and due presets."),
                        GeneratedHelpLine(kind: .bullet, value: "iCloud: sync across devices and sync status."),
                        GeneratedHelpLine(kind: .bullet, value: "Categories: manage expense categories."),
                        GeneratedHelpLine(kind: .bullet, value: "Presets: manage expense presets.")
                    ]
                )
            ],
            assetPrefix: "Help-Settings"
        ),
        GeneratedHelpLeafTopic(
            id: "settings-expense-display-toggles",
            destinationID: "settings",
            title: "Expense Display Toggles",
            sections: [
                GeneratedHelpSection(
                    id: "settings-expense-display-toggles-1",
                    header: "Settings Toggles for Expense Display",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "In General > Expense Display, you can control future expenses in two different ways."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide future planned expenses: hides planned items from lists."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude future planned expenses from calculations: removes future planned items from totals."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide future variable expenses: hides variable items dated in the future."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude future variable expenses from calculations: keeps those future variable items out of totals.")
                    ]
                )
            ],
            assetPrefix: "Help-Settings"
        ),
        GeneratedHelpLeafTopic(
            id: "settings-hide-vs-exclude",
            destinationID: "settings",
            title: "Hide vs Exclude",
            sections: [
                GeneratedHelpSection(
                    id: "settings-hide-vs-exclude-1",
                    header: "Why Hide vs Exclude Matters",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Hide and Exclude are not the same setting."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide changes what you see on screen."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude changes calculation results."),
                        GeneratedHelpLine(kind: .bullet, value: "You can combine them if you want cleaner views and tighter totals.")
                    ]
                )
            ],
            assetPrefix: "Help-Settings"
        ),
        GeneratedHelpLeafTopic(
            id: "settings-workspaces",
            destinationID: "settings",
            title: "Workspaces",
            sections: [
                GeneratedHelpSection(
                    id: "settings-workspaces-1",
                    header: "Workspaces",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Offshore supports multiple workspaces to separate budgeting contexts like Personal and Work. Each workspace has its own cards, income, presets, categories, and budgets.")
                    ]
                )
            ],
            assetPrefix: nil
        ),
        GeneratedHelpLeafTopic(
            id: "settings-presets",
            destinationID: "settings",
            title: "Presets",
            sections: [
                GeneratedHelpSection(
                    id: "settings-presets-1",
                    header: "Presets: Reusable Fixed Expense Templates",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Use presets for fixed bills like rent or subscriptions. Tap + to create one. Swipe right to edit or left to delete.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "settings-presets-2",
                    header: "How Presets Affect Totals",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "When assigned to a budget, presets become planned expenses in that budget."),
                        GeneratedHelpLine(kind: .bullet, value: "Presets act as templates for planned expenses."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned expenses generated from presets use planned amount unless you edit actual amount later.")
                    ]
                ),
                GeneratedHelpSection(
                    id: "settings-presets-3",
                    header: "Tip",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Use presets to make budget setup fast and consistent month to month.")
                    ]
                )
            ],
            assetPrefix: "Help-Presets"
        )
    ]

    // MARK: - Lookup

    private static let leafTopicsByID: [String: GeneratedHelpLeafTopic] = {
        var lookup: [String: GeneratedHelpLeafTopic] = [:]

        for topic in allLeafTopics {
            lookup[topic.id] = topic
        }

        return lookup
    }()

    static var gettingStartedDestinations: [GeneratedHelpDestination] {
        destinations.filter { $0.group == .gettingStarted }
    }

    static var coreScreenDestinations: [GeneratedHelpDestination] {
        destinations.filter { $0.group == .coreScreens }
    }

    static func destination(for id: String) -> GeneratedHelpDestination? {
        destinations.first { $0.id == id }
    }

    static func leafTopic(for id: String) -> GeneratedHelpLeafTopic? {
        leafTopicsByID[id]
    }

    static func leafTopics(for destination: GeneratedHelpDestination) -> [GeneratedHelpLeafTopic] {
        destination.leafTopicIDs.compactMap { leafTopicsByID[$0] }
    }
}

private extension GeneratedHelpSection {
    var screenshotSlots: [Int] {
        lines.compactMap { line in
            switch line.kind {
            case .heroScreenshot, .miniScreenshot:
                return Int(line.value)
            case .text, .bullet:
                return nil
            }
        }
    }

    var condensedBodyText: String {
        let content = lines.compactMap { line -> String? in
            switch line.kind {
            case .text, .bullet:
                return line.value.trimmingCharacters(in: .whitespacesAndNewlines)
            case .heroScreenshot, .miniScreenshot:
                return nil
            }
        }
        .filter { $0.isEmpty == false }

        if content.isEmpty {
            return "Replace this placeholder with concise help text for this section."
        }

        return content.joined(separator: " ")
    }

    func placeholderAssetName(slot: Int) -> String {
        "Help-\(id)-\(slot)"
    }
}
