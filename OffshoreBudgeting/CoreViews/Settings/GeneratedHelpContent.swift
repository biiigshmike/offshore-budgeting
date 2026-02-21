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

struct GeneratedHelpSectionMediaItem: Identifiable, Hashable {
    let id: String
    let assetName: String
    let bodyText: String
}

struct GeneratedHelpSection: Identifiable, Hashable {
    let id: String
    let header: String?
    let bodyText: String
    let mediaItems: [GeneratedHelpSectionMediaItem]
}

struct GeneratedHelpLeafTopic: Identifiable, Hashable {
    let id: String
    let destinationID: String
    let title: String
    let sections: [GeneratedHelpSection]

    var searchableText: String {
        var parts: [String] = [title]

        for section in sections {
            if let header = section.header {
                parts.append(header)
            }

            parts.append(section.bodyText)
            parts.append(contentsOf: section.mediaItems.map(\.bodyText))
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func mediaItems(for section: GeneratedHelpSection) -> [GeneratedHelpSectionMediaItem] {
        section.mediaItems
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
                "home-customization",
                "home-marina",
                "home-widgets"
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
                "budgets-budget-details",
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
                "settings-general",
                "settings-privacy",
                "settings-notifications",
                "settings-icloud",
                "settings-quick-actions",
                "settings-categories",
                "settings-presets",
                "settings-workspaces"
            ]
        )
    ]

    // MARK: - Leaf Topics

    static let allLeafTopics: [GeneratedHelpLeafTopic] = [
        // MARK: Introduction

        GeneratedHelpLeafTopic(
            id: "introduction-building-blocks",
            destinationID: "introduction",
            title: "The Building Blocks",
            sections: [
                textSection(
                    id: "introduction-building-blocks-1",
                    header: "The Building Blocks",
                    body: "Offshore is built around cards, income, categories, presets, and budgets. Cards store where expenses were charged, while income tracks what you planned and what you actually received. Categories and presets organize recurring behavior, and budgets tie everything together into a date range you can measure."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-planned-expenses",
            destinationID: "introduction",
            title: "Planned Expenses",
            sections: [
                textSection(
                    id: "introduction-planned-expenses-1",
                    header: "Planned Expenses",
                    body: "Planned expenses are expected costs such as rent, subscriptions, or recurring bills. You can set a planned amount up front, then record an actual amount later if the charge changed. This gives you a forecast and a reality check in the same workflow."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-variable-expenses",
            destinationID: "introduction",
            title: "Variable Expenses",
            sections: [
                textSection(
                    id: "introduction-variable-expenses-1",
                    header: "Variable Expenses",
                    body: "Variable expenses cover one-off or unpredictable spending such as fuel, dining, or quick purchases. They are treated as actual spending and roll into budget and card totals immediately. Use categories to keep this spending easy to filter and review later."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-planned-income",
            destinationID: "introduction",
            title: "Planned Income",
            sections: [
                textSection(
                    id: "introduction-planned-income-1",
                    header: "Planned Income",
                    body: "Planned income is the amount you expect to receive in a period. It powers forward-looking savings projections before deposits arrive. Once income is received, log actual entries to confirm what really happened."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-actual-income",
            destinationID: "introduction",
            title: "Actual Income",
            sections: [
                textSection(
                    id: "introduction-actual-income-1",
                    header: "Actual Income",
                    body: "Actual income is money already received, so it drives real totals and real savings. Use recurring actual income for consistent paychecks, or manual entries when deposits vary. This keeps Home and Budget metrics grounded in real cash flow."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-budgets",
            destinationID: "introduction",
            title: "Budgets",
            sections: [
                textSection(
                    id: "introduction-budgets-1",
                    header: "Budgets",
                    body: "Budgets define a start and end date so Offshore can summarize spending, income, and savings for a clear window. You can compare planned versus actual behavior in the same period and adjust quickly. This is the main lens for measuring progress over time."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-calculations",
            destinationID: "introduction",
            title: "Calculations",
            sections: [
                textSection(
                    id: "introduction-calculations-1",
                    header: "Calculation Basics",
                    body: "Most totals in Offshore are straightforward sums grouped by date range, category, type, and visibility settings. Planned values support forecasting, while actual values represent real outcomes. Savings views combine income and expense totals so you can see direction quickly."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-import",
            destinationID: "introduction",
            title: "Import",
            sections: [
                textSection(
                    id: "introduction-import-1",
                    header: "Import Flow",
                    body: "Import helps you bring in expense or income data from supported sources, then review matches before saving. The review step lets you catch duplicates and fill missing fields before anything is committed. This keeps imports fast without losing control over data quality."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-quick-actions",
            destinationID: "introduction",
            title: "Quick Actions",
            sections: [
                textSection(
                    id: "introduction-quick-actions-1",
                    header: "Quick Actions",
                    body: "Quick Actions are optional shortcuts that help you log expenses or income faster. Install them from Settings, then pair them with Shortcuts automations if you want background-style capture flows. Offshore works fully without them, but they can reduce repeated manual entry."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-excursion-mode",
            destinationID: "introduction",
            title: "Excursion Mode",
            sections: [
                textSection(
                    id: "introduction-excursion-mode-1",
                    header: "Excursion Mode",
                    body: "Excursion Mode is designed for focused tracking while you are out and spending. It keeps quick entry front and center so you can capture transactions with less friction. Use it when you want tighter day-of-spend awareness."
                )
            ]
        ),

        // MARK: Home

        GeneratedHelpLeafTopic(
            id: "home-overview",
            destinationID: "home",
            title: "Overview",
            sections: [
                mediaSection(
                    id: "home-overview-1",
                    header: "Home Overview",
                    body: "Home is your dashboard for current spending, income, and savings direction. Use the visible widgets to spot changes quickly and drill into detail where needed. You can keep this screen lightweight or data-dense depending on what you pin.",
                    media: [
                        mediaItem(
                            id: "home-overview-1-image-1",
                            assetName: "Help/CoreScreens/Home/Overview/overview",
                            bodyText: "Home gives you a quick read of your current financial position without opening each screen. Use the top-level summaries to decide where to drill in next. If something looks off, tap through to Budgets, Income, or Accounts for detail."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "home-customization",
            destinationID: "home",
            title: "Customization",
            sections: [
                mediaSection(
                    id: "home-customization-edit-home",
                    header: "Customize Home",
                    body: "You can tailor Home so the most important insights show first. Reordering or pinning widgets helps you build a workflow that matches your routine. This makes daily check-ins faster and more consistent.",
                    media: [
                        mediaItem(
                            id: "home-customization-edit-home-1",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-1",
                            bodyText: "Open Home customization and enter edit mode to start arranging cards and widgets. This is the setup step where you decide what matters most for your default dashboard view."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-2",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-2",
                            bodyText: "Drag widgets into the order you want so high-priority insights stay at the top. Keep frequently used sections near the top to reduce scrolling during quick reviews."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-3",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-3",
                            bodyText: "Save your layout to apply the updated Home sequence. You can return anytime and adjust as your priorities change across weeks or months."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "home-marina",
            destinationID: "home",
            title: "Marina",
            sections: [
                mediaSection(
                    id: "home-marina-1",
                    header: "Marina Assistant",
                    body: "Marina is your in-app budgeting assistant on Home. Use prompts to ask for quick insights, trend checks, and practical next actions based on your existing data. Keep prompts specific to get the most relevant guidance.",
                    media: [
                        mediaItem(
                            id: "home-marina-1-image-1",
                            assetName: "Help/CoreScreens/Home/Marina/marina",
                            bodyText: "Open Marina from Home when you want a conversational summary instead of manual digging. Ask targeted questions about spending, income, or savings to get practical, on-device guidance."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "home-widgets",
            destinationID: "home",
            title: "Widgets",
            sections: [
                mediaSection(
                    id: "home-widgets-overview",
                    header: "Widget Highlights",
                    body: "Home widgets surface focused metrics so you can scan key patterns quickly. Each tile answers a different question, from category pressure to savings momentum. Use them together for a fast daily check-in.",
                    media: [
                        mediaItem(
                            id: "home-widgets-income",
                            assetName: "Help/CoreScreens/Home/Widgets/income",
                            bodyText: "The income widget helps you compare what was planned versus what was actually received. Use this to spot shortfalls early and decide whether spending needs to be adjusted this period."
                        ),
                        mediaItem(
                            id: "home-widgets-savings-outlook",
                            assetName: "Help/CoreScreens/Home/Widgets/savings-outlook",
                            bodyText: "Savings Outlook estimates how your period may finish based on current inputs. Check this regularly when adding expenses so you can course-correct before the period closes."
                        ),
                        mediaItem(
                            id: "home-widgets-spend-trends",
                            assetName: "Help/CoreScreens/Home/Widgets/spend-trends",
                            bodyText: "Spend Trends shows how your spending is moving over time instead of just the current total. Use it to catch acceleration patterns before they become budget problems."
                        ),
                        mediaItem(
                            id: "home-widgets-category-spotlight",
                            assetName: "Help/CoreScreens/Home/Widgets/category-spotlight",
                            bodyText: "Category Spotlight surfaces categories that are taking the largest share of spending. This is useful for finding where a small adjustment could make the biggest difference."
                        ),
                        mediaItem(
                            id: "home-widgets-what-if",
                            assetName: "Help/CoreScreens/Home/Widgets/what-if",
                            bodyText: "What If lets you test spending scenarios before making changes. Try adjustments here to understand impact on savings and remaining budget before committing to decisions."
                        )
                    ]
                )
            ]
        ),

        // MARK: Budgets

        GeneratedHelpLeafTopic(
            id: "budgets-overview",
            destinationID: "budgets",
            title: "Overview",
            sections: [
                mediaSection(
                    id: "budgets-overview-overview",
                    header: "Budgets Overview",
                    body: "The Budgets screen is the index of active, upcoming, and past periods. Open a budget to manage planned and variable spending in one place. This is your main control center for period-by-period tracking.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/overview",
                            bodyText: "Use Budgets to scan current periods quickly and jump into details with one tap. Active budgets are where day-to-day planning and tracking happen."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-overview-create-budget",
                    header: "Create a Budget",
                    body: "Creating a budget sets the date window and planning context for expenses and income. This gives you a clean frame for totals and savings metrics. Start here when beginning a new cycle.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-create-budget-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-1",
                            bodyText: "Tap add from the Budgets screen to create a new period. Enter a clear name and set a start/end range that matches your planning cadence."
                        ),
                        mediaItem(
                            id: "budgets-overview-create-budget-2",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-2",
                            bodyText: "Review your budget details before saving so totals line up with the period you expect. Once saved, you can assign cards and begin adding expenses immediately."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "budgets-budget-details",
            destinationID: "budgets",
            title: "Budget Details",
            sections: [
                mediaSection(
                    id: "budgets-details-add-expense",
                    header: "Add Expense",
                    body: "Budget Details is where you log and monitor spending for the selected period. Planned entries capture expected costs and variable entries capture live spending. Use this screen to keep the period accurate as it unfolds.",
                    media: [
                        mediaItem(
                            id: "budgets-details-add-expense-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-1",
                            bodyText: "Use the add flow inside Budget Details to create a new expense in the current budget. Choose the correct expense type so calculations reflect planned versus variable behavior correctly."
                        ),
                        mediaItem(
                            id: "budgets-details-add-expense-2",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-2",
                            bodyText: "Complete amount, date, card, and category fields before saving. Accurate categorization now makes filters and spending insights much more useful later."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "Filters let you narrow budget expenses by category and other scope controls. This helps isolate exactly where pressure is coming from in a period. Use filters before making spending decisions.",
                    media: [
                        mediaItem(
                            id: "budgets-details-filter-expenses-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/filter-expenses",
                            bodyText: "Apply filters to reduce noise and review only the expenses relevant to your current question. This is ideal when you are troubleshooting one category or one card at a time."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-spending-limits",
                    header: "Spending Limits",
                    body: "Category spending limits help you set soft guardrails inside a budget. They are useful for categories that tend to drift upward over time. Track these limits as part of your regular budget review.",
                    media: [
                        mediaItem(
                            id: "budgets-details-spending-limits-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/spending-limits",
                            bodyText: "Set or adjust category limits from Budget Details so high-variance categories stay visible. This makes it easier to react before overspending compounds."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "budgets-calculations",
            destinationID: "budgets",
            title: "Calculations",
            sections: [
                mediaSection(
                    id: "budgets-calculations-overview",
                    header: "Calculations Overview",
                    body: "Budget totals combine planned income, actual income, planned expenses, and variable expenses for the selected period. These values react to your current filters and policy toggles. Use the header metrics as your source of truth for progress.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/overview",
                            bodyText: "Start with the calculations overview to understand how the budget summary is assembled. This view shows the relationship between income, expense totals, and resulting savings metrics."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-calculations-details",
                    header: "Calculation Details",
                    body: "Use this section to verify how each total changes when planned entries get actual amounts or when variable spending rises. It is designed to make tradeoffs visible early. Compare projected and actual savings to judge period performance.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-details-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/calculations",
                            bodyText: "Review the detailed math breakdown when totals do not match expectations. It clarifies which components are driving movement in max, projected, and actual savings."
                        )
                    ]
                )
            ]
        ),

        // MARK: Income

        GeneratedHelpLeafTopic(
            id: "income-overview",
            destinationID: "income",
            title: "Overview",
            sections: [
                mediaSection(
                    id: "income-overview-1",
                    header: "Income Overview",
                    body: "Income uses a calendar-first view so you can track planned and actual income by day. Select a date to inspect entries and see weekly totals in context. This helps you validate incoming cash flow against expectations.",
                    media: [
                        mediaItem(
                            id: "income-overview-1-image-1",
                            assetName: "Help/CoreScreens/Income/Overview/overview",
                            bodyText: "Use the Income screen to move between days and confirm what has landed versus what was planned. The calendar makes patterns easy to spot across the month."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "income-planned-vs-actual",
            destinationID: "income",
            title: "Planned vs Actual",
            sections: [
                mediaSection(
                    id: "income-planned-vs-actual-1",
                    header: "Planned vs Actual Income",
                    body: "Planned income helps forecast upcoming periods, while actual income confirms what you really received. Use both together to monitor reliability of income sources. This keeps your savings projections honest and actionable.",
                    media: [
                        mediaItem(
                            id: "income-planned-vs-actual-1-image-1",
                            assetName: "Help/CoreScreens/Income/Planned vs Actual/planned-vs-actual",
                            bodyText: "Compare planned and actual entries side by side to find gaps quickly. If a source varies, keep planned entries realistic and update actuals as deposits arrive."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "income-calculations",
            destinationID: "income",
            title: "Calculations",
            sections: [
                textSection(
                    id: "income-calculations-1",
                    header: "Income Calculation Notes",
                    body: "Income totals feed both Home and Budget summaries. Planned income supports forecasting, while actual income drives real savings and remaining capacity. If numbers look off, verify date range and entry type first."
                )
            ]
        ),

        // MARK: Accounts

        GeneratedHelpLeafTopic(
            id: "accounts-overview",
            destinationID: "accounts",
            title: "Overview",
            sections: [
                mediaSection(
                    id: "accounts-overview-1",
                    header: "Accounts Overview",
                    body: "Accounts is where you manage cards, reconciliations, and savings in one area. Open a card for transaction-level detail, or switch to reconciliation and savings workflows as needed. This screen helps separate daily spending from settlement tracking.",
                    media: [
                        mediaItem(
                            id: "accounts-overview-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Overview/overview",
                            bodyText: "Use Accounts to access each financial container quickly, including card-level detail and shared-balance tracking. This is the launch point for most spending operations outside Budgets."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-card-details",
            destinationID: "accounts",
            title: "Card Details",
            sections: [
                mediaSection(
                    id: "accounts-card-details-overview",
                    header: "Card Detail Overview",
                    body: "Card Detail is the focused workspace for reviewing and editing expenses on a specific card. It includes search, filters, and scoped totals so you can diagnose spending quickly. Use this when you need transaction-level control.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/overview",
                            bodyText: "Open a card to inspect its expenses with full context, including category and date filtering. This view is ideal when reconciling statements or cleaning up tagged spending."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-add-expense",
                    header: "Add Expense",
                    body: "You can add expenses directly from card detail when capturing new activity. This keeps card history up to date without switching screens. Enter complete metadata so downstream insights stay accurate.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-add-expense-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/add-expense",
                            bodyText: "Use the add button in card detail to log a new expense immediately under that card. Fill amount, date, and category fields before saving to preserve reporting quality."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "Filters let you focus on a subset of card expenses, such as one category or date range. This is useful when investigating unusual totals or preparing edits. Apply filters first, then review the scoped totals.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-filter-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/filter-expenses",
                            bodyText: "Use card-level filters to isolate transactions that match your current review goal. This reduces noise and makes manual cleanup much faster."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-import-expenses",
                    header: "Import Expenses",
                    body: "Import from card detail routes parsed expense rows into the selected card workflow. Review entries before saving to avoid duplicates or misclassified rows. This is useful for bulk capture sessions.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-import-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/import-expenses",
                            bodyText: "Start an import from card detail when you need to add multiple transactions quickly. Confirm matches and categories in review so imported data lands correctly."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-calculations",
            destinationID: "accounts",
            title: "Calculations",
            sections: [
                mediaSection(
                    id: "accounts-calculations-1",
                    header: "Account Calculation Notes",
                    body: "Card totals respond to your current filters and expense type selections. Planned entries can use actual amounts when available, and variable entries always contribute as actual spend. Check this view when card totals need validation.",
                    media: [
                        mediaItem(
                            id: "accounts-calculations-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Calculations/calculations",
                            bodyText: "Use the calculations panel to verify how scoped totals are built from the current transaction set. This makes it easier to explain why a filtered total changed."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-reconciliations",
            destinationID: "accounts",
            title: "Reconciliations",
            sections: [
                mediaSection(
                    id: "accounts-reconciliations-overview",
                    header: "Reconciliations Overview",
                    body: "Reconciliations track shared balances like money fronted, split, or owed between people. Each reconciliation maintains a running ledger so you can settle over time instead of losing context. Use clear names for each balance to keep history readable.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/overview",
                            bodyText: "Create and monitor shared balances from the Reconciliations area in Accounts. This keeps peer-to-peer tracking separate from normal card spending."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-reconciliations-add-settlement",
                    header: "Add a Settlement",
                    body: "Settlements move a reconciliation balance toward zero and document progress. Use this flow whenever money is paid back or collected. Over time, the ledger gives a clean audit trail.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-1",
                            bodyText: "Open the reconciliation detail and choose to add a settlement entry. Select the correct direction so the balance moves the way you expect."
                        ),
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-2",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-2",
                            bodyText: "Confirm amount and note before saving so future reviews show exactly why the balance changed. Good notes make shared-balance history much easier to interpret."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-reconciliations-detail-view",
                    header: "Detail View",
                    body: "The detail view shows all ledger activity for one reconciliation, including allocations and settlements. Archived items remain in history so past context is preserved. Use this view for complete timeline review.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-detail-view-image-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/detail-view",
                            bodyText: "Use reconciliation detail to inspect each ledger event in order and confirm current balance. This is the best place to audit old entries or prepare a clean settle-up summary."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-savings-account",
            destinationID: "accounts",
            title: "Savings Account",
            sections: [
                mediaSection(
                    id: "accounts-savings-account-overview",
                    header: "Savings Account",
                    body: "Savings Account keeps a running ledger and trend chart for money set aside. Add entries for contributions, withdrawals, or adjustments and review movement by date range. This gives a dedicated history separate from card spending.",
                    media: [
                        mediaItem(
                            id: "accounts-savings-account-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Savings Account/overview",
                            bodyText: "Use the savings ledger to track how your saved balance changes across the period. The trend chart helps you confirm whether momentum is improving or slipping."
                        )
                    ]
                )
            ]
        ),

        // MARK: Settings

        GeneratedHelpLeafTopic(
            id: "settings-overview",
            destinationID: "settings",
            title: "Overview",
            sections: [
                mediaSection(
                    id: "settings-overview-1",
                    header: "Settings Overview",
                    body: "Settings is where you configure app behavior, privacy, notifications, sync, shortcuts, and management tools. Use it as your control panel for defaults and maintenance tasks. Most long-term preferences live here.",
                    media: [
                        mediaItem(
                            id: "settings-overview-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Overview/overview",
                            bodyText: "Start in Settings Overview to see all management areas in one list, from General and Privacy to Categories and Presets. This helps you quickly choose whether you are configuring behavior or managing data."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-general",
            destinationID: "settings",
            title: "General",
            sections: [
                mediaSection(
                    id: "settings-general-1",
                    header: "General",
                    body: "General contains app-wide behavior settings such as display and calculation preferences. Changes here can affect how future expenses are shown and how totals are computed. Review these toggles if numbers look different than expected.",
                    media: [
                        mediaItem(
                            id: "settings-general-1-image-1",
                            assetName: "Help/CoreScreens/Settings/General/overview",
                            bodyText: "Use General to tune how Offshore displays and calculates future planned and variable expenses. This is where you control visibility versus inclusion in totals."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-privacy",
            destinationID: "settings",
            title: "Privacy",
            sections: [
                mediaSection(
                    id: "settings-privacy-1",
                    header: "Privacy",
                    body: "Privacy settings control protections such as app lock and sensitive workflow permissions. Use this area to align security behavior with your device habits. It is the first stop when tightening access rules.",
                    media: [
                        mediaItem(
                            id: "settings-privacy-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Privacy/overview",
                            bodyText: "Open Privacy to configure how the app protects access and handles sensitive entry flows. Keep these settings aligned with your preferred level of friction and safety."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-notifications",
            destinationID: "settings",
            title: "Notifications",
            sections: [
                mediaSection(
                    id: "settings-notifications-1",
                    header: "Notifications",
                    body: "Notifications help you stay on top of daily spending checks, income reminders, and due items. Configure timing and behavior so reminders support your routine without becoming noise. This is useful for consistency during busy periods.",
                    media: [
                        mediaItem(
                            id: "settings-notifications-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Notifications/overview",
                            bodyText: "Use Notifications to choose which reminders Offshore sends and when they should appear. A small set of focused reminders usually works better than enabling everything."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-icloud",
            destinationID: "settings",
            title: "iCloud",
            sections: [
                mediaSection(
                    id: "settings-icloud-1",
                    header: "iCloud",
                    body: "iCloud settings show sync status and cross-device behavior for your data. Use this area to confirm your workspace changes are propagating as expected. It is helpful when validating setup on a new device.",
                    media: [
                        mediaItem(
                            id: "settings-icloud-1-image-1",
                            assetName: "Help/CoreScreens/Settings/iCloud/overview",
                            bodyText: "Open iCloud settings to verify sync health and ensure your data is available across devices. If something looks stale, check this area first before troubleshooting elsewhere."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-quick-actions",
            destinationID: "settings",
            title: "Quick Actions",
            sections: [
                textSection(
                    id: "settings-quick-actions-1",
                    header: "Install and Use Quick Actions",
                    body: "Quick Actions in Settings provide install links and setup guidance for optional shortcuts. After installing, you can run them manually or pair them with Shortcuts automations for faster capture flows. Keep shortcut names consistent so automations stay reliable."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-categories",
            destinationID: "settings",
            title: "Categories",
            sections: [
                mediaSection(
                    id: "settings-categories-overview",
                    header: "Categories Overview",
                    body: "Manage Categories lets you create and organize spending labels used across budgets and cards. Clean categories improve filters, trends, and guidance quality throughout the app. Review this list occasionally to keep naming consistent.",
                    media: [
                        mediaItem(
                            id: "settings-categories-overview-image-1",
                            assetName: "Help/CoreScreens/Settings/Categories/overview",
                            bodyText: "Use Manage Categories to keep your spending taxonomy clean and practical. Good category hygiene makes every downstream report easier to trust."
                        )
                    ]
                ),
                mediaSection(
                    id: "settings-categories-add-category",
                    header: "Add Category",
                    body: "Add categories when you notice spending patterns that need their own label. Specific categories improve both tracking clarity and targeted adjustments. Keep names short and distinct.",
                    media: [
                        mediaItem(
                            id: "settings-categories-add-category-image-1",
                            assetName: "Help/CoreScreens/Settings/Categories/add-category",
                            bodyText: "Create a new category from this screen when existing labels are too broad. This helps you separate meaningful spending behavior instead of lumping it together."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-presets",
            destinationID: "settings",
            title: "Presets",
            sections: [
                mediaSection(
                    id: "settings-presets-overview",
                    header: "Presets Overview",
                    body: "Presets are reusable templates for recurring planned expenses. They speed up budget setup and keep repeated bills consistent across periods. Use presets for stable costs such as rent, subscriptions, and utilities.",
                    media: [
                        mediaItem(
                            id: "settings-presets-overview-image-1",
                            assetName: "Help/CoreScreens/Settings/Presets/overview",
                            bodyText: "Manage Presets is where you review, edit, and organize your recurring planned-expense templates. Well-maintained presets make new budget creation much faster."
                        )
                    ]
                ),
                mediaSection(
                    id: "settings-presets-add-preset",
                    header: "Add Preset",
                    body: "Create a preset once, then reuse it in future budgets instead of retyping the same planned expense. This improves consistency and reduces setup time. Keep amounts and category mappings accurate so template reuse stays reliable.",
                    media: [
                        mediaItem(
                            id: "settings-presets-add-preset-1",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-1",
                            bodyText: "Start the add preset flow and define the core fields such as name, amount, and category. Choose values that reflect how the recurring expense normally behaves."
                        ),
                        mediaItem(
                            id: "settings-presets-add-preset-2",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-2",
                            bodyText: "Review the preset before saving so future budgets inherit correct defaults. A clean preset today prevents repeated edits later in each budget cycle."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-workspaces",
            destinationID: "settings",
            title: "Workspaces",
            sections: [
                mediaSection(
                    id: "settings-workspaces-1",
                    header: "Workspaces",
                    body: "Workspaces separate budgeting contexts so personal and other domains can stay independent. Each workspace has its own cards, categories, presets, and budgets. Switch or manage workspaces from the Settings toolbar menu.",
                    media: [
                        mediaItem(
                            id: "settings-workspaces-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Workspaces/overview",
                            bodyText: "Use Workspaces when you want separate financial contexts without mixing records. This keeps totals and history scoped to the context you are actively managing."
                        )
                    ]
                )
            ]
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

// MARK: - Builders

private func textSection(id: String, header: String?, body: String) -> GeneratedHelpSection {
    GeneratedHelpSection(
        id: id,
        header: header,
        bodyText: body,
        mediaItems: []
    )
}

private func mediaSection(
    id: String,
    header: String?,
    body: String,
    media: [GeneratedHelpSectionMediaItem]
) -> GeneratedHelpSection {
    GeneratedHelpSection(
        id: id,
        header: header,
        bodyText: body,
        mediaItems: media
    )
}

private func mediaItem(id: String, assetName: String, bodyText: String) -> GeneratedHelpSectionMediaItem {
    GeneratedHelpSectionMediaItem(
        id: id,
        assetName: assetName,
        bodyText: bodyText
    )
}
