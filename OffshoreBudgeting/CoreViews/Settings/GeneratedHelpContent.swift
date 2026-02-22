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
    let fullscreenCaptionText: String?
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
            parts.append(contentsOf: section.mediaItems.compactMap(\.fullscreenCaptionText))
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
                    header: "What This Includes",
                    body: "Offshore is organized into a few core parts that work together: Accounts (cards and reconciliations), Income, Budgets, and Settings tools like Categories and Presets. Each part has a focused job so you can understand where money came from, where it went, and how that compares to your plan. Learning these building blocks first makes every other screen easier to use."
                ),
                textSection(
                    id: "introduction-building-blocks-2",
                    header: "Where To Find Everything",
                    body: "Use the main navigation to open Home, Budgets, Income, Accounts, and Settings. Home gives you a summary, while the other screens are where entries are created and managed. If you are unsure where to edit something, start from the screen that owns that type of record."
                ),
                textSection(
                    id: "introduction-building-blocks-3",
                    header: "Basic Workflow",
                    body: "Create or open a budget period first, then add planned items and track actual activity as it happens. Use Income for pay and inflows, Accounts for card-linked spending context, and Categories for clean reporting. This pattern gives you a predictable routine each period."
                ),
                textSection(
                    id: "introduction-building-blocks-4",
                    header: "Verify Your Setup",
                    body: "After entering data, check Home and the relevant detail screen to confirm totals moved the way you expected. If the change is visible in both places, your records are aligned. This quick check prevents confusion later when comparing planned versus actual."
                ),
                textSection(
                    id: "introduction-building-blocks-5",
                    header: "Building Block Pitfalls",
                    body: "The most common issue is mixing concepts, like treating planned values as already-spent money or creating categories that overlap too much. Keep names clear and consistent, and use each screen for its intended purpose. A little structure early will keep reports readable as your history grows."
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
                    header: "What Planned Expenses Mean",
                    body: "Planned expenses are expected costs you want in the budget before money is actually spent. They help you forecast recurring obligations like rent, subscriptions, utilities, and known bills. Think of them as your financial intention for the period."
                ),
                textSection(
                    id: "introduction-planned-expenses-2",
                    header: "Where To Add Them",
                    body: "Open the budget period you are working in and use the expense add flow to create planned entries. You can also rely on presets for recurring items so setup is faster and more consistent. Staying inside the correct budget period keeps planned totals scoped correctly."
                ),
                textSection(
                    id: "introduction-planned-expenses-3",
                    header: "How To Use Them Day To Day",
                    body: "Add planned expenses early in the period, then review them as real charges happen. If the final charge differs, record the actual outcome so planned versus actual stays meaningful. This turns your budget into a live plan instead of a static list."
                ),
                textSection(
                    id: "introduction-planned-expenses-4",
                    header: "Verify They Are Working",
                    body: "Check that the budget reflects planned totals before you begin logging variable or actual spending. As actuals are recorded, confirm comparisons still make sense and highlight real differences. This gives you a clear signal when you are drifting from plan."
                ),
                textSection(
                    id: "introduction-planned-expenses-5",
                    header: "Planned Expense Pitfalls",
                    body: "Avoid duplicating the same recurring bill across presets and manual entries, which can overstate your plan. Keep naming and category mapping consistent so reviews are easy to interpret. If a planned amount changes often, update the source template so future periods stay accurate."
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
                    header: "What Variable Expenses Mean",
                    body: "Variable expenses are unplanned or flexible purchases that happen as real spending in the period. They usually include categories like dining, fuel, shopping, and one-off costs. These entries reflect what already happened, not what you expected to happen."
                ),
                textSection(
                    id: "introduction-variable-expenses-2",
                    header: "Where To Record Them",
                    body: "Log variable expenses from the appropriate expense entry flow in your active budget context. Assign category and related account details carefully so later filtering is useful. Clean inputs here directly improve every downstream summary."
                ),
                textSection(
                    id: "introduction-variable-expenses-3",
                    header: "How To Use Them In Workflow",
                    body: "Record variable spending as soon as possible after purchase so your budget stays current. Use short, consistent naming and accurate amounts so trend views remain trustworthy. Frequent small entries are better than waiting and batch-entering from memory."
                ),
                textSection(
                    id: "introduction-variable-expenses-4",
                    header: "Verify Your Tracking",
                    body: "After saving, confirm the entry appears in the expected budget and updates relevant totals. Then check category-level views to make sure the expense landed in the right bucket. Quick verification catches miscategorized spending before it compounds."
                ),
                textSection(
                    id: "introduction-variable-expenses-5",
                    header: "Variable Expense Pitfalls",
                    body: "Avoid broad category labels that hide useful detail, especially for frequent variable spending. Also avoid delaying entry for too long, which can make end-of-period totals feel surprising. Capture consistently and your spending patterns become much easier to manage."
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
                    header: "What Planned Income Means",
                    body: "Planned income is the amount you expect to receive during a period before deposits arrive. It powers forecasts, including whether your budgeted plan appears sustainable. This gives you early visibility before real cash flow is finalized."
                ),
                textSection(
                    id: "introduction-planned-income-2",
                    header: "Where To Enter It",
                    body: "Open Income and create planned entries for each expected inflow in the active timeframe. Keep names clear enough to distinguish paycheck-like entries from irregular income. Clear labeling makes planned versus actual review much easier later."
                ),
                textSection(
                    id: "introduction-planned-income-3",
                    header: "How To Use It In Workflow",
                    body: "Start each period by entering expected income so savings outlook and budget pressure are realistic. As dates pass, compare the plan against what was actually received. This gives you time to adjust spending if income arrives lower or later than expected."
                ),
                textSection(
                    id: "introduction-planned-income-4",
                    header: "Verify Forecast Quality",
                    body: "Check Home and Income views to confirm planned totals match your expected period cash flow. If numbers look off, review duplicate entries and date alignment first. Accurate planned income improves every forward-looking metric."
                ),
                textSection(
                    id: "introduction-planned-income-5",
                    header: "Planned Income Pitfalls",
                    body: "Do not treat planned income as guaranteed money in daily decision-making. Keep uncertain income clearly separated and update plans when expectations change. A realistic plan is more valuable than an optimistic one."
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
                    header: "What Actual Income Means",
                    body: "Actual income is money that has already been received and is available in real cash flow totals. It is the grounding layer for what truly happened this period. Use it as the source of truth when comparing against planned income."
                ),
                textSection(
                    id: "introduction-actual-income-2",
                    header: "Where To Record It",
                    body: "Record actual income in the Income area using the add flow that matches how you track deposits. Include accurate amount and date so period comparisons remain trustworthy. Good entry timing keeps your dashboard aligned with reality."
                ),
                textSection(
                    id: "introduction-actual-income-3",
                    header: "How To Use It In Workflow",
                    body: "Log income soon after a deposit clears, then review planned versus actual differences. Use those differences to decide whether spending should be tightened or if you can safely allocate extra. This closes the loop between expectation and outcome."
                ),
                textSection(
                    id: "introduction-actual-income-4",
                    header: "Verify Totals",
                    body: "After saving, check Income totals and Home summary cards to confirm values updated as expected. If a number seems inflated, inspect duplicate entries or wrong-period dates first. Consistent validation prevents small data issues from snowballing."
                ),
                textSection(
                    id: "introduction-actual-income-5",
                    header: "Actual Income Pitfalls",
                    body: "Avoid entering expected deposits as actual before they land, since that can overstate available funds. Also avoid merging unrelated income sources under one vague label. Clear, timely entries make your trend history much more useful."
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
                    header: "What A Budget Is",
                    body: "A budget is the time window Offshore uses to group income, expenses, and savings progress. It defines the period you are measuring, such as monthly or custom ranges. Everything in that range can then be reviewed as one cohesive cycle."
                ),
                textSection(
                    id: "introduction-budgets-2",
                    header: "Where To Create It",
                    body: "Open Budgets and create a new period with a clear name and start/end dates. Choose a range that matches how you naturally review finances. Consistent cadence makes cross-period comparisons easier."
                ),
                textSection(
                    id: "introduction-budgets-3",
                    header: "How To Use It In Workflow",
                    body: "After creating a budget, add planned entries, record variable spending, and track income for the same window. Return frequently during the period to adjust as new information arrives. A budget works best as an active tool, not a one-time setup."
                ),
                textSection(
                    id: "introduction-budgets-4",
                    header: "Verify It Is Healthy",
                    body: "Review planned versus actual inside the budget and cross-check with Home summaries. If totals do not match expectations, check for missing entries or dates outside the range. This keeps your period review reliable from start to finish."
                ),
                textSection(
                    id: "introduction-budgets-5",
                    header: "Budget Pitfalls",
                    body: "Avoid overlapping periods unless you intentionally want parallel contexts. Also avoid changing date ranges mid-cycle without reviewing affected totals. Stable ranges produce cleaner history and better trend clarity."
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
                    header: "How Calculations Work",
                    body: "Most totals in Offshore are grouped sums filtered by period, record type, and visibility context. Planned values support forecasting, while actual values represent real outcomes. Reading each total in the right context prevents most confusion."
                ),
                textSection(
                    id: "introduction-calculations-2",
                    header: "Where Calculations Appear",
                    body: "You will see calculated totals across Home, Budgets, Income, and related detail views. The same underlying records can surface in different summaries depending on the screen purpose. Use labels on each screen to confirm whether you are viewing planned or actual numbers."
                ),
                textSection(
                    id: "introduction-calculations-3",
                    header: "How To Read Them In Workflow",
                    body: "Start with period-level totals, then drill into categories or entry lists when a number looks unexpected. Compare planned and actual side by side instead of in isolation. This approach helps you move from signal to root cause quickly."
                ),
                textSection(
                    id: "introduction-calculations-4",
                    header: "Verify A Number",
                    body: "When validating a total, confirm date range first, then confirm the included entries in detail views. Check for duplicates, missing records, and wrong classification between planned and actual. This short audit process usually resolves mismatches fast."
                ),
                textSection(
                    id: "introduction-calculations-5",
                    header: "Calculation Pitfalls",
                    body: "Avoid comparing numbers from different periods or different data types without realizing it. Also avoid assuming every summary includes the same filters by default. Always anchor comparisons to the same timeframe and context."
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
                    header: "What Import Is For",
                    body: "Import is designed to speed up entry by bringing in batches of expense or income records, then letting you review them before saving. It reduces repetitive typing while preserving control over final data quality. Use it when manual entry would be slow or error-prone."
                ),
                textSection(
                    id: "introduction-import-2",
                    header: "Where To Start Import",
                    body: "Open the relevant import flow from the area where you want records to land, then choose your source and proceed to review. Keep the target period in mind before you begin so imported records are scoped correctly. This prevents cleanup after the fact."
                ),
                textSection(
                    id: "introduction-import-3",
                    header: "How To Review Records",
                    body: "During review, check names, amounts, categories, and dates before committing. Resolve possible duplicates and fill any missing required details while still in the review step. Taking an extra minute here prevents long correction sessions later."
                ),
                textSection(
                    id: "introduction-import-4",
                    header: "Verify The Result",
                    body: "After import, open list and summary views to confirm totals and entry counts changed as expected. Spot-check a few imported rows for classification accuracy. Verification right away makes rollback or edits much simpler."
                ),
                textSection(
                    id: "introduction-import-5",
                    header: "Import Pitfalls",
                    body: "Avoid importing the same source repeatedly without duplicate review, which can inflate totals quickly. Also avoid skipping category cleanup during review, since low-quality labels weaken every report. Clean imports save time in every future period."
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
                    header: "What Quick Actions Are",
                    body: "Quick Actions are optional shortcuts that speed up common entry tasks like capturing expenses or income. They are meant to reduce taps, not replace standard screens. Offshore works fully without them, so treat them as an efficiency layer."
                ),
                textSection(
                    id: "introduction-quick-actions-2",
                    header: "Where To Set Them Up",
                    body: "Go to Settings and open the Quick Actions area to install and review available shortcuts. If you use Apple Shortcuts, you can connect these actions into your own automation routines. Start simple first, then add automation after basic flows feel stable."
                ),
                textSection(
                    id: "introduction-quick-actions-3",
                    header: "How To Use Them Safely",
                    body: "Run a quick action and immediately verify the created record in the destination screen. Confirm amount, category, and date so the shortcut behavior matches your expectations. This one-time validation protects you from repeated automation mistakes."
                ),
                textSection(
                    id: "introduction-quick-actions-4",
                    header: "Verify Reliability",
                    body: "Test your most-used action a few times with realistic examples before relying on it daily. Keep shortcut naming clear so future edits are easier to manage. Reliable quick actions should feel boring and predictable."
                ),
                textSection(
                    id: "introduction-quick-actions-5",
                    header: "Quick Action Pitfalls",
                    body: "Avoid building complex automations before validating simple manual-trigger behavior. Also avoid using ambiguous default values that can create wrong categories or amounts. Start small, prove accuracy, then expand."
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
                    header: "What Excursion Mode Is",
                    body: "Excursion Mode is a focused tracking state for moments when spending activity is high and fast. It prioritizes quick capture so you can log activity with minimal interruption. Use it when you want tighter real-time awareness."
                ),
                textSection(
                    id: "introduction-excursion-mode-2",
                    header: "When To Use It",
                    body: "Turn to Excursion Mode during outings, travel, event days, or any period with many small transactions. It is especially useful when waiting until later would cause missed details. Short bursts of disciplined capture can dramatically improve data quality."
                ),
                textSection(
                    id: "introduction-excursion-mode-3",
                    header: "How To Work In It",
                    body: "Capture each transaction quickly, then return later for any deeper cleanup such as notes or fine category adjustments. Keep the process simple so you maintain momentum instead of delaying entry. The goal is completeness first, refinement second."
                ),
                textSection(
                    id: "introduction-excursion-mode-4",
                    header: "Verify After A Session",
                    body: "When the high-activity window ends, review what was captured and confirm totals align with what you expected to spend. Fix obvious mislabels while context is still fresh. This quick closeout step keeps excursion sessions trustworthy."
                ),
                textSection(
                    id: "introduction-excursion-mode-5",
                    header: "Excursion Mode Pitfalls",
                    body: "Avoid over-editing each entry in the moment, which usually leads to skipped captures. Also avoid forgetting a short post-session review, since fast entry can include minor classification errors. Use the mode for speed, then verify for accuracy."
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
                    body: "Home is the fastest way to understand where the current period stands before opening detailed screens. It brings spending, income, and savings signals into one place so you can decide what needs attention first. Start here at the beginning of each check-in, then drill into Budgets, Income, or Accounts for corrections.\n\nUse the widgets as directional signals, not isolated verdicts. When a tile looks unusual, validate the cause in the destination screen that owns that data. This keeps day-to-day decisions tied to real entries instead of quick assumptions.\n\nA good Home workflow is simple: scan, identify one priority, investigate, then return. Repeating that loop keeps your budgeting process focused and consistent. Over time, Home becomes your control panel for staying proactive rather than reactive.",
                    media: [
                        mediaItem(
                            id: "home-overview-1-image-1",
                            assetName: "Help/CoreScreens/Home/Overview/overview",
                            bodyText: "This overview image shows the Home dashboard acting as a starting point for daily review. Read top-level totals first, then look for any widget that suggests a shift in spending, income, or savings direction. When something needs clarification, open the matching core screen and validate the underlying entries. Returning to Home after each adjustment helps you confirm whether the correction improved the period outlook.",
                            fullscreenCaptionText: "Use Home as your first scan, then open the matching screen to verify any number that looks off."
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
                    body: "Home customization lets you decide which insights appear first so your most important decisions require fewer taps. A strong layout reduces scrolling and keeps critical widgets visible when you are moving quickly. This is especially useful if your priorities change during different parts of the month.\n\nTreat customization as a workflow tool, not just a visual preference. Put frequently checked widgets near the top and move low-priority items lower. Revisit your layout after a few cycles to ensure it still matches how you actually review the app.\n\nAfter reordering, run one normal daily check-in to validate that the sequence feels natural. Small changes in order can significantly improve consistency. A layout that matches your routine helps you catch problems earlier.",
                    media: [
                        mediaItem(
                            id: "home-customization-edit-home-1",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-1",
                            bodyText: "This first step shows entering edit mode from Home customization. Use this point to decide which tiles belong in your top view versus lower priority positions. If you are unsure, place your most decision-driving widgets first, such as income reliability or savings trend signals. Starting with intention makes later ordering changes simpler.",
                            fullscreenCaptionText: "Enter edit mode to begin arranging the Home widgets around your priorities."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-2",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-2",
                            bodyText: "This step shows reordering widgets into the sequence you want for quick daily checks. Drag high-impact tiles toward the top so important shifts are visible immediately. Keep related widgets near each other when possible so context is easier to read. A practical order reduces friction and improves follow-through.",
                            fullscreenCaptionText: "Drag widgets into the order that supports your fastest daily review."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-3",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-3",
                            bodyText: "This final step confirms and saves your updated Home layout. After saving, perform a quick scan to verify the new order feels right in real use. If a tile is still out of place, adjust it now while the workflow is fresh. Regular small refinements keep the Home experience aligned with your budgeting habits.",
                            fullscreenCaptionText: "Save and test the new layout, then make small tweaks until the flow feels natural."
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
                    body: "Marina is your conversational helper for translating raw budget data into practical next steps. It is most useful when you want a quick interpretation before diving into individual screens. Ask focused questions tied to a period, category, or concern so the response stays actionable.\n\nUse Marina as a planning companion, then verify key points in the underlying destination views. This pattern combines speed with confidence because you get guidance and confirmation. Specific prompts usually produce the most useful recommendations.\n\nA strong habit is to ask one question, act on one recommendation, then re-check your summary state. This keeps interaction purposeful and avoids information overload. Marina works best when used as a decision accelerator.",
                    media: [
                        mediaItem(
                            id: "home-marina-1-image-1",
                            assetName: "Help/CoreScreens/Home/Marina/marina",
                            bodyText: "This image shows opening Marina from Home for a conversational review flow. Use concise prompts about spending trends, income variance, or savings direction to get targeted guidance. After receiving a suggestion, jump to the relevant screen and confirm the supporting records. This keeps Marina responses grounded in your live data workflow.",
                            fullscreenCaptionText: "Ask Marina targeted questions, then confirm recommendations in the related core screen."
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
                    body: "Home widgets are designed to answer distinct budgeting questions quickly without opening every screen. Each tile provides a focused signal, and together they form a reliable daily scan pattern. Use them in sequence so you can detect pressure, prioritize action, and decide where to drill in next.\n\nTreat widgets as an early-warning system. They help you catch shifts while there is still time to correct course. When one tile changes sharply, verify the cause in Budgets, Income, or Accounts before making decisions.\n\nConsistency matters more than speed here. A short repeatable scan each day usually produces better outcomes than occasional deep dives. Use the same order to build confidence and reduce missed signals.",
                    media: [
                        mediaItem(
                            id: "home-widgets-income",
                            assetName: "Help/CoreScreens/Home/Widgets/income",
                            bodyText: "The income widget helps you compare expected versus received inflows at a glance. Use it early in the period to detect timing delays or lower-than-planned deposits. If a gap appears, adjust planned spending priorities before pressure builds. This widget is your first check for cash-flow reliability.",
                            fullscreenCaptionText: "Compare planned and actual income quickly to spot shortfalls early."
                        ),
                        mediaItem(
                            id: "home-widgets-savings-outlook",
                            assetName: "Help/CoreScreens/Home/Widgets/savings-outlook",
                            bodyText: "Savings Outlook projects where the period may end based on current entries and assumptions. Review it after adding meaningful expenses or income updates so direction changes are visible immediately. Use this signal to decide whether you need to slow discretionary spending. Frequent checks keep surprises smaller at period close.",
                            fullscreenCaptionText: "Use Savings Outlook to forecast direction and course-correct before period close."
                        ),
                        mediaItem(
                            id: "home-widgets-spend-trends",
                            assetName: "Help/CoreScreens/Home/Widgets/spend-trends",
                            bodyText: "Spend Trends emphasizes movement over time, not just a single total. Watch for acceleration patterns that indicate a category or habit is drifting upward. When trend slope changes, inspect recent entries to identify what triggered the shift. Early trend awareness makes interventions more effective.",
                            fullscreenCaptionText: "Watch trend direction, not just totals, to catch acceleration early."
                        ),
                        mediaItem(
                            id: "home-widgets-category-spotlight",
                            assetName: "Help/CoreScreens/Home/Widgets/category-spotlight",
                            bodyText: "Category Spotlight highlights which categories currently have the most budget pressure. Use it to find the best place for small behavior changes that can create meaningful impact. After identifying a heavy category, open details and verify the entries driving that weight. This supports targeted adjustments instead of broad guesswork.",
                            fullscreenCaptionText: "Use Category Spotlight to find the categories creating the most pressure."
                        ),
                        mediaItem(
                            id: "home-widgets-what-if",
                            assetName: "Help/CoreScreens/Home/Widgets/what-if",
                            bodyText: "What If lets you test potential spending adjustments before committing to them in your real plan. Use it when you are deciding between competing choices or trying to recover from an unfavorable trend. Simulating outcomes helps you choose options with clearer tradeoffs. It is a safe planning step before making real entries.",
                            fullscreenCaptionText: "Run What If scenarios to compare tradeoffs before committing real changes."
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
                    body: "Budgets is the command center for period-based planning and review. It organizes active, upcoming, and past cycles so you can stay clear on what you are managing now versus what is historical. Start each cycle here to confirm the correct period is open before adding or editing entries.\n\nUse this screen to decide where to focus first: setup, ongoing tracking, or end-of-period validation. Keeping period boundaries clear prevents accidental edits in the wrong cycle. That one habit alone improves reporting accuracy across the app.\n\nWhen something looks unusual on Home, Budgets is usually the fastest place to confirm the cause in context. It ties planned and actual behavior together in a single timeline. This makes decision-making much easier during busy weeks.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/overview",
                            bodyText: "This overview image shows the list of budget periods and their current status. Use it to quickly locate the active period, then open it for daily updates and review. If multiple periods exist, confirm dates before editing so entries stay in the correct cycle. A fast period check prevents confusing totals later.",
                            fullscreenCaptionText: "Start in Budgets to open the correct period before making any updates."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-overview-create-budget",
                    header: "Create a Budget",
                    body: "Creating a budget establishes the date window used for all totals, comparisons, and savings outcomes in that cycle. This step defines the frame that every entry depends on, so clarity here matters. Choose a period cadence that matches how you naturally review finances.\n\nA clean setup flow includes naming, date selection, and quick review before save. Keep names recognizable so you can find the right period quickly later. Consistent naming and date boundaries make trend analysis cleaner over time.\n\nAfter creation, move directly into assigning structure and adding initial planned entries. That keeps momentum and reduces setup debt. Early setup quality improves every downstream decision.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-create-budget-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-1",
                            bodyText: "This first step shows starting a new budget period from the add flow. Enter a clear name and choose a date range that matches your review rhythm, such as monthly or custom cycles. Make sure the window aligns with planned income and recurring expenses you expect to track. Accurate dates are the foundation for trustworthy budget math.",
                            fullscreenCaptionText: "Create a budget with a clear name and date range that matches your cycle."
                        ),
                        mediaItem(
                            id: "budgets-overview-create-budget-2",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-2",
                            bodyText: "This step shows reviewing and confirming budget setup details before saving. Verify the period boundaries and core settings now so you do not need cleanup edits after entries are added. Once saved, continue directly into cards, planned expenses, and other setup tasks. A short confirmation pass here saves significant correction time later.",
                            fullscreenCaptionText: "Review setup details before save so the period starts with clean boundaries."
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
                    body: "Budget Details is where period execution happens day by day. This is where you add, edit, and monitor expenses while keeping planned and variable behavior in sync. Treat this view as your working ledger for the active cycle.\n\nUse planned entries for expected obligations and variable entries for real-time spending. Keeping both updated in one place helps comparisons stay meaningful. Frequent updates here reduce end-of-period surprises.\n\nAfter each meaningful change, quickly scan summary signals to confirm direction. Small, consistent updates make budget control much easier than large delayed corrections. This section is the core of active budget maintenance.",
                    media: [
                        mediaItem(
                            id: "budgets-details-add-expense-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-1",
                            bodyText: "This step shows opening the add expense flow from Budget Details. Choose the correct expense type first so the entry contributes to calculations in the right way. Planned and variable entries serve different purposes, so classification is important. Starting with the right type prevents avoidable reporting confusion.",
                            fullscreenCaptionText: "Start add expense from Budget Details and choose the correct expense type first."
                        ),
                        mediaItem(
                            id: "budgets-details-add-expense-2",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-2",
                            bodyText: "This step completes the entry fields such as amount, date, card, and category. Fill these carefully so filters, category reports, and trend views remain useful later. If something is uncertain, add the best available values now and refine shortly after. High-quality entry details make every later review faster.",
                            fullscreenCaptionText: "Finish amount, date, card, and category fields before saving the expense."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "Filtering lets you isolate the exact slice of spending you need to evaluate before making changes. Use it to narrow by category, card, or other scope controls when totals need explanation. Focused views reduce noise and shorten investigation time.\n\nA good sequence is filter first, inspect entries second, then decide action. This keeps decisions tied to evidence instead of intuition. Clear filtered views are especially useful when spending accelerates unexpectedly.\n\nReset filters after analysis so future reviews begin from full context. That habit avoids accidental conclusions from stale scopes. Filtering is most powerful when used intentionally and reset consistently.",
                    media: [
                        mediaItem(
                            id: "budgets-details-filter-expenses-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/filter-expenses",
                            bodyText: "This image shows applying filters to narrow the visible expense set. Use this when troubleshooting one category, one card, or one timeframe instead of scanning the full ledger. A focused result set makes it easier to identify the entries driving pressure. Confirm conclusions, then reset filters before moving on.",
                            fullscreenCaptionText: "Apply filters to isolate the exact expense slice you want to diagnose."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-spending-limits",
                    header: "Spending Limits",
                    body: "Spending limits create practical guardrails for categories that tend to drift beyond comfort. They are not just constraints, they are early alerts that help you respond before overspending compounds. Use limits on high-variance categories first for the biggest impact.\n\nReview limit status alongside trend and category views so decisions stay contextual. Limits work best when adjusted as behavior patterns change rather than left static forever. Recalibrating periodically keeps them realistic and useful.\n\nIf a limit is repeatedly exceeded, investigate root causes before simply raising it. Sometimes the better fix is reclassification or behavior adjustment. Thoughtful limit usage improves long-term control.",
                    media: [
                        mediaItem(
                            id: "budgets-details-spending-limits-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/spending-limits",
                            bodyText: "This step shows setting or adjusting category spending limits inside Budget Details. Use limits to keep high-variance categories visible and actionable throughout the cycle. When alerts or pressure appear, review recent entries before changing the threshold. This keeps limits tied to real behavior rather than guesswork.",
                            fullscreenCaptionText: "Set category limits to surface budget pressure before it compounds."
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
                    body: "Budget calculations summarize how income and expenses combine into period outcomes. The overview helps you read relationships between planned values, actual values, and resulting savings direction. Start here when a top-line number changes and you need context.\n\nRemember that filters and policy toggles can change what appears included. Always confirm scope before comparing numbers across screens. Consistent scope checks prevent most calculation misunderstandings.\n\nUse this summary as a navigation map: identify the metric that moved, then inspect the contributing entries. This creates a reliable path from signal to cause.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/overview",
                            bodyText: "This overview image shows the top-level budget math components in one place. Use it to see how planned and actual values combine into savings outcomes for the active period. When totals shift unexpectedly, start here to identify which component moved first. Then inspect that component in detail before making adjustments.",
                            fullscreenCaptionText: "Use the overview to identify which calculation component moved first."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-calculations-details",
                    header: "Calculation Details",
                    body: "Calculation Details explains why specific totals changed, not just that they changed. Use it when projected and actual outcomes diverge or when period momentum feels unclear. This is where tradeoffs become visible enough to act on.\n\nCompare projected versus actual savings with current expense behavior to decide next steps. If variance is growing, investigate the entries driving that spread. Detailed math review helps you prioritize corrective action.\n\nA quick detail check after major edits can prevent end-of-period surprises. It is a practical verification step, not just a diagnostic tool. Use it proactively when stakes are high.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-details-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/calculations",
                            bodyText: "This detail image shows the deeper math breakdown behind budget outcomes. Use it to verify which totals are driving movement across projected and actual savings. When a value looks wrong, trace it back to entry type, timing, and recent edits. Clear math tracing makes fixes faster and more reliable.",
                            fullscreenCaptionText: "Open details to trace projected and actual savings changes to their source."
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
                    body: "Income uses a calendar-centered workflow so you can track inflows by date and context. This makes it easier to match expected deposits with what actually arrived. Start here when validating cash flow reliability for the active cycle.\n\nMove through days intentionally instead of scanning only totals. Date-level review helps you catch timing shifts that can affect spending decisions. Even when totals look fine, timing issues can still create pressure.\n\nA strong routine is to review the selected date, confirm planned versus actual, then update records immediately. That habit keeps all downstream calculations aligned. Income accuracy is critical for trustworthy savings projections.",
                    media: [
                        mediaItem(
                            id: "income-overview-1-image-1",
                            assetName: "Help/CoreScreens/Income/Overview/overview",
                            bodyText: "This overview image shows the calendar-driven Income workspace for daily verification. Use it to move between dates and confirm what was planned versus what was received. If a deposit is missing or delayed, update records so budget pressure reflects reality. Daily validation here keeps Home and Budget signals honest.",
                            fullscreenCaptionText: "Use the Income calendar to verify planned and actual inflows by day."
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
                    body: "Planned versus actual income is one of the most important comparisons in the app because it determines whether your budget assumptions are holding. Planned values give forward visibility, while actual values confirm reality. The difference between them is where decisions happen.\n\nReview this comparison regularly, especially after each expected payday or major inflow event. A small variance caught early is much easier to manage than a large surprise near period close. This comparison supports both stability and responsiveness.\n\nWhen variance appears, decide quickly whether to adjust discretionary spending, update planned values, or both. Keep the comparison current so guidance across Home and Budgets stays relevant. Reliable income comparisons improve confidence everywhere else.",
                    media: [
                        mediaItem(
                            id: "income-planned-vs-actual-1-image-1",
                            assetName: "Help/CoreScreens/Income/Planned vs Actual/planned-vs-actual",
                            bodyText: "This image highlights the side-by-side planned and actual income comparison view. Use it to identify gaps, timing delays, or overestimation patterns quickly. When a source varies, adjust plans to realistic expectations and continue logging actuals as they arrive. This keeps savings forecasting practical instead of optimistic.",
                            fullscreenCaptionText: "Compare planned and actual income side by side to identify variance quickly."
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
                    body: "Income calculations power both Home indicators and Budget outcomes, so quality here has broad impact. Planned income contributes to forecasting, while actual income determines what is truly available. Understanding this split prevents many interpretation errors.\n\nWhen a number looks unexpected, verify three things first: period dates, entry type, and duplicates. Most mismatches come from one of those sources. Correcting those quickly restores trust in the summary views.\n\nUse Income calculations as a checkpoint after each meaningful update cycle. Confirm totals moved in the direction you expected before continuing. Frequent lightweight verification keeps the entire app experience coherent."
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
                    body: "Accounts is the hub for card activity, shared-balance reconciliation, and savings tracking. It helps you separate normal spending workflows from settlement and reserve workflows so your data stays organized. Start here when the task is account-specific rather than period-planning specific.\n\nUse this screen to choose the right container before editing entries. Card details are best for transaction-level spending maintenance, while reconciliations and savings serve different financial intents. Choosing the right area first reduces accidental misclassification.\n\nA quick review pass in Accounts each cycle keeps card-level accuracy strong. This improves every related report and trend in the app. Think of Accounts as structure and integrity for spending records.",
                    media: [
                        mediaItem(
                            id: "accounts-overview-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Overview/overview",
                            bodyText: "This overview image shows Accounts as the launch point for cards, reconciliations, and savings workflows. Use it to jump into the specific container that matches the task you need to complete. Opening the correct container first keeps edits contextual and easier to validate. It is the best starting point for non-budget transaction maintenance.",
                            fullscreenCaptionText: "Use Accounts to jump into cards, reconciliations, or savings with the right context."
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
                    body: "Card Detail is the focused workspace for transaction-level spending management on one card. It is where you verify, clean up, and investigate entries with full context. Use it whenever a card total, statement check, or category assignment needs precision.\n\nThis view combines scoped totals, search, and filtering so you can move from summary to exact row quickly. It is much more efficient than broad list scanning when diagnosing a specific problem. Keep this as your primary card-maintenance screen.\n\nAfter edits, recheck scoped totals to confirm expected movement. This immediate feedback loop helps prevent drift over time. Card-level discipline improves budget quality overall.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/overview",
                            bodyText: "This image shows the Card Detail overview where transactions can be reviewed with focused controls. Use category and date scopes here when reconciling statements or cleaning inconsistent tagging. Start with broad context, then narrow to the exact rows driving the issue. This keeps card cleanup accurate and efficient.",
                            fullscreenCaptionText: "Open Card Detail to review transactions with focused filters and scoped totals."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-add-expense",
                    header: "Add Expense",
                    body: "Adding expenses directly in Card Detail keeps card history current without leaving context. This is useful when you are already investigating a card and need to capture missing activity immediately. Staying in one screen reduces switching friction.\n\nAlways complete essential fields during entry so the record is analysis-ready from the start. Correct amount, date, and category choices make later reviews easier. High-quality inputs here improve filters, trends, and reconciliation confidence.\n\nAfter save, verify that totals changed as expected in the current scope. Quick confirmation catches wrong-card or wrong-date issues early. This keeps card ledgers reliable.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-add-expense-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/add-expense",
                            bodyText: "This step shows adding a new expense directly from Card Detail under the selected card. Enter amount, date, and category carefully so the entry lands correctly in summaries and filters. If unsure, capture the best known values now and refine promptly after save. Immediate capture plus quick verification keeps card records trustworthy.",
                            fullscreenCaptionText: "Add expenses directly in Card Detail to keep the selected card ledger current."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "Card filters let you isolate the exact transaction slice you need for investigation. This reduces noise when checking unusual totals or preparing cleanup edits. Focused scopes are essential for fast, confident diagnosis.\n\nApply filter criteria before reviewing totals so what you see matches the question you are asking. A filtered scope can reveal patterns that are hidden in full-card views. This is especially useful for recurring or category-specific drift.\n\nReset filters after completing each investigation. That keeps future reviews from inheriting stale context. Clear filter discipline avoids misleading conclusions.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-filter-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/filter-expenses",
                            bodyText: "This image shows applying card-level filters to narrow transaction review. Use filtered scopes to isolate the exact rows tied to a discrepancy or cleanup goal. Once identified, update entries and recheck scoped totals for confirmation. Focused filtering can cut investigation time dramatically.",
                            fullscreenCaptionText: "Filter card transactions to isolate the rows tied to your current review goal."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-import-expenses",
                    header: "Import Expenses",
                    body: "Card import helps you add multiple transactions quickly when manual entry would be slow. Starting import from Card Detail keeps the destination context clear and reduces mapping mistakes. This is ideal for catch-up sessions after travel or statement review.\n\nUse the review stage to confirm amount, date, and category quality before commit. Duplicate checks are especially important during repeated imports. Better review quality now means less cleanup later.\n\nAfter import, validate sample rows and scoped totals to ensure the batch landed correctly. Immediate verification prevents hidden drift. Bulk speed should still include quality control.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-import-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/import-expenses",
                            bodyText: "This step shows starting a card-scoped import flow for bulk transaction capture. Review each parsed row for duplicates and category accuracy before saving the batch. When records commit, check a few entries and totals to verify correct placement. Strong review habits make imports both fast and reliable.",
                            fullscreenCaptionText: "Use card import for bulk capture, then review rows carefully before saving."
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
                    body: "Account calculations explain how card totals are assembled under current scope and record type rules. Use this when a card number looks unexpected and you need a reliable breakdown. It is a practical bridge between summary totals and raw rows.\n\nRemember that filters and entry types change what contributes to the final value. Planned records with actual outcomes can influence totals differently than pure variable spend. Confirm scope before drawing conclusions.\n\nUse this panel after meaningful edits or imports to verify expected movement. A short check here prevents unresolved mismatches from spreading into other screens. Calculation clarity improves confidence in card health.",
                    media: [
                        mediaItem(
                            id: "accounts-calculations-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Calculations/calculations",
                            bodyText: "This image shows the card calculation view used to validate scoped totals. Use it to confirm how current filters and entry composition produce the number you are seeing. If totals changed, trace contributing groups before editing additional data. Clear tracing helps you fix the right issue the first time.",
                            fullscreenCaptionText: "Use card calculations to trace filtered totals back to contributing transaction groups."
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
                    body: "Reconciliations track shared balances separately from normal card spending so settle-up workflows remain clear. Use them when money is fronted, split, or owed between people. This keeps peer-to-peer tracking structured and auditable.\n\nEach reconciliation maintains a running ledger of allocations and settlements. Over time, that timeline gives clear context for why a balance changed. Good naming and notes make this history much easier to interpret later.\n\nReview reconciliation ledgers periodically even when balances seem stable. Early verification prevents stale misunderstandings with shared expenses. Consistent maintenance keeps settle-up conversations simple.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/overview",
                            bodyText: "This overview image shows the Reconciliations list for managing shared balances. Use it to create and monitor person-specific or context-specific ledgers without mixing them with card expenses. Keep names explicit so balances are easy to recognize during review. Separate ledgers make settlement progress easier to communicate.",
                            fullscreenCaptionText: "Use Reconciliations to track shared balances separately from normal card spending."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-reconciliations-add-settlement",
                    header: "Add a Settlement",
                    body: "Settlements are the entries that reduce or clear shared balances over time. Use this flow any time money is paid back, collected, or otherwise resolves a reconciliation amount. Recording settlements promptly keeps the ledger honest and current.\n\nDirection and amount accuracy matter because they determine whether balances move toward zero correctly. Include brief notes so future you can understand why each movement occurred. Clear settlement records prevent timeline confusion later.\n\nAfter saving, verify updated balance direction in detail view. This quick check catches sign mistakes immediately. Reliable settlement entry is key to trustworthy shared-balance tracking.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-1",
                            bodyText: "This first step shows opening reconciliation detail and initiating a settlement entry. Choose the settlement direction carefully so the balance moves as intended. Direction mistakes can invert progress and create confusion in later review. Confirm the sign before continuing.",
                            fullscreenCaptionText: "Start a settlement from reconciliation detail and confirm the balance direction."
                        ),
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-2",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-2",
                            bodyText: "This step confirms settlement amount and notes before committing the entry. Add a concise reason so future reviews clearly explain the balance change. Good notes are especially valuable when multiple people or events affect one ledger. Save only after amount, direction, and context are all clear.",
                            fullscreenCaptionText: "Confirm amount and add a short note so settlement history stays clear."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-reconciliations-detail-view",
                    header: "Detail View",
                    body: "Reconciliation Detail is the full timeline view for one shared-balance ledger. It shows allocations, settlements, and resulting balance movement in sequence. Use it whenever you need complete context before making adjustments.\n\nThis view is also the best place to verify whether archived or older activity still explains current balances. Historical continuity matters for trust when reconciling with others. A clear timeline reduces disputes and rework.\n\nBefore closing a settlement cycle, perform one final detail review. Confirm that sequence, notes, and ending balance all match expectation. End-of-cycle verification keeps the ledger dependable.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-detail-view-image-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/detail-view",
                            bodyText: "This image shows the reconciliation detail timeline used for full ledger audit. Review entries in order to confirm how the current balance was produced. Use it before final settle-up discussions so you can explain each movement clearly. A complete timeline review reduces ambiguity and mistakes.",
                            fullscreenCaptionText: "Use detail view to audit the full reconciliation timeline before final settlement."
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
                    body: "Savings Account provides a dedicated ledger and trend view for money set aside outside normal card spending. Use it to track contributions, withdrawals, and adjustments with clear historical context. Separating savings from spending records improves clarity during review.\n\nThe trend view helps you evaluate momentum instead of relying on a single balance snapshot. Regularly checking movement direction can reveal whether habits are supporting goals. Small trend shifts matter when repeated across cycles.\n\nAfter each savings update, verify the entry and resulting movement quickly. This keeps your reserve history trustworthy. A clean savings ledger supports better planning decisions.",
                    media: [
                        mediaItem(
                            id: "accounts-savings-account-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Savings Account/overview",
                            bodyText: "This image shows the Savings Account ledger with trend context for recent movement. Use it to confirm each contribution or withdrawal updates the timeline as expected. Review trend direction periodically to catch early signs of momentum loss. Dedicated savings tracking makes reserve progress much easier to manage.",
                            fullscreenCaptionText: "Track contributions and withdrawals here, then monitor trend direction over time."
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
                    body: "Settings is the control center for app behavior, privacy, notifications, sync, and data management tools. Use it whenever you want to change defaults or improve workflow consistency across cycles. Most long-term app preferences are configured here rather than in day-to-day transaction screens.\n\nA strong approach is to review Settings at onboarding, then revisit when your process changes. Small adjustments here can reduce repetitive work later in Budgets, Income, and Accounts. Settings choices directly influence how data is displayed and interpreted.\n\nTreat Settings as preventive maintenance, not just troubleshooting. Keeping it aligned with your habits improves reliability and confidence. This screen supports long-term stability in the app experience.",
                    media: [
                        mediaItem(
                            id: "settings-overview-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Overview/overview",
                            bodyText: "This overview image shows the main Settings list with all management areas in one place. Use it to choose whether you are adjusting behavior, security, sync, or organizational data. Starting from this index helps you enter the correct section quickly. A clear route through Settings reduces accidental changes in unrelated areas.",
                            fullscreenCaptionText: "Start in Settings Overview to jump directly to the management area you need."
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
                    body: "General contains app-wide behavior and display rules that influence how information appears across the app. Changes here can affect interpretation of planned and variable expense views. Use this section when you want predictable defaults that match your budgeting style.\n\nBecause General settings can alter display logic, review this area first when numbers appear different than expected. Many apparent mismatches are preference-based rather than data-based. Confirming defaults saves unnecessary troubleshooting.\n\nAfter changing a toggle, check a known budget or card view to verify expected effect. Small verification steps prevent silent confusion. General is best managed intentionally, not casually.",
                    media: [
                        mediaItem(
                            id: "settings-general-1-image-1",
                            assetName: "Help/CoreScreens/Settings/General/overview",
                            bodyText: "This image shows General settings used to tune core display and calculation behavior. Use it to control how planned and variable items are surfaced and interpreted in summaries. After updates, validate one familiar screen to ensure the result matches your intent. Purposeful configuration here keeps totals predictable.",
                            fullscreenCaptionText: "Adjust General preferences to control global display and calculation behavior."
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
                    body: "Privacy settings control access protections and sensitive workflow behavior across the app. Use this section to align security posture with your device usage and personal comfort level. It is the first place to visit when hardening access.\n\nChoose a privacy setup that balances safety with daily usability. Too little friction can reduce protection, while too much can reduce consistency. Pick the level you will actually maintain.\n\nAfter changing privacy controls, test one normal flow to confirm behavior feels right. Practical verification ensures protection works without breaking routine. Security settings are most effective when they remain usable.",
                    media: [
                        mediaItem(
                            id: "settings-privacy-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Privacy/overview",
                            bodyText: "This image shows the Privacy controls used to protect access and sensitive workflows. Use these options to set the right balance between security and convenience for your routine. After updates, run a quick unlock and entry check to confirm expected behavior. A verified setup is safer than assumptions.",
                            fullscreenCaptionText: "Configure Privacy controls to match your preferred security and access friction."
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
                    body: "Notifications help you build consistency by prompting review and capture habits at the right times. Use this section to configure reminders that support your budgeting cadence without creating alert fatigue. Fewer focused reminders usually perform better than broad noisy setups.\n\nMatch reminder timing to moments when you can actually act, not just when it is convenient to schedule. Actionable timing increases follow-through. This makes notifications supportive instead of distracting.\n\nReview notification performance after a week and adjust quickly. If you ignore a reminder repeatedly, change or disable it. Useful reminders should earn their place.",
                    media: [
                        mediaItem(
                            id: "settings-notifications-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Notifications/overview",
                            bodyText: "This image shows Notification settings for selecting reminder types and schedule timing. Enable only the reminders that directly improve your daily workflow. Then validate delivery timing against when you can actually review or log data. Focused reminder design increases consistency and lowers noise.",
                            fullscreenCaptionText: "Enable only high-value reminders and schedule them when you can act."
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
                    body: "iCloud settings provide sync visibility and cross-device status for your workspace data. Use this section when validating setup on a new device or troubleshooting stale records. It is the authoritative place to check sync health first.\n\nWhen data appears inconsistent, confirm status here before editing entries. Many issues are temporary sync delays rather than true data problems. Early verification avoids unnecessary manual corrections.\n\nAfter major setup changes or device migrations, perform a quick sync check. Confirm recent edits appear where expected. Reliable sync confidence helps you trust multi-device workflows.",
                    media: [
                        mediaItem(
                            id: "settings-icloud-1-image-1",
                            assetName: "Help/CoreScreens/Settings/iCloud/overview",
                            bodyText: "This image shows iCloud sync status and related controls for cross-device data behavior. Use it to confirm that recent edits are propagating correctly across your devices. If something appears stale, verify sync health here before changing records elsewhere. Sync-first troubleshooting prevents avoidable data confusion.",
                            fullscreenCaptionText: "Check iCloud status first when data looks stale across devices."
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
                    body: "Quick Actions in Settings provide optional shortcut install and setup paths for faster capture workflows. They are useful when you repeat the same entry actions often and want fewer manual taps. Offshore works fully without them, so treat this as an efficiency layer.\n\nStart with one or two high-value actions and verify created records before scaling automation. Reliable small flows are better than complex fragile ones. Use clear shortcut naming so future edits stay manageable.\n\nIf an automation behaves unexpectedly, simplify first and retest with manual triggers. Stability should come before complexity. This keeps speed gains from turning into cleanup work."
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
                    body: "Categories define the language your spending data uses across Budgets, Accounts, and Home insights. Clean category structure improves filters, trend interpretation, and assistant guidance quality. This is one of the highest-leverage maintenance areas in Settings.\n\nReview category naming periodically to reduce overlap and ambiguity. Broad or duplicate labels make analysis harder and decisions slower. Clear taxonomy leads to clearer action.\n\nWhen spending patterns evolve, update categories deliberately rather than forcing everything into old buckets. Maintenance here protects long-term report quality. Category hygiene compounds over time.",
                    media: [
                        mediaItem(
                            id: "settings-categories-overview-image-1",
                            assetName: "Help/CoreScreens/Settings/Categories/overview",
                            bodyText: "This image shows the category management list used to organize your spending taxonomy. Use it to review naming consistency and remove ambiguity before it spreads into reports. Well-maintained categories make every filter and trend easier to trust. Small cleanup sessions here pay off across the entire app.",
                            fullscreenCaptionText: "Review category structure here to keep spending analysis clean and consistent."
                        )
                    ]
                ),
                mediaSection(
                    id: "settings-categories-add-category",
                    header: "Add Category",
                    body: "Add a category when existing labels are too broad to support useful decisions. New categories should represent distinct behavior you want to track and act on. Clear category boundaries improve both visibility and accountability.\n\nChoose names that are short, specific, and unlikely to overlap with existing labels. This reduces confusion during entry and later analysis. A clean name is easier to apply consistently.\n\nAfter creating a category, use it consistently in new entries and review old mapping as needed. Consistency is what creates insight quality. Category growth should stay intentional.",
                    media: [
                        mediaItem(
                            id: "settings-categories-add-category-image-1",
                            assetName: "Help/CoreScreens/Settings/Categories/add-category",
                            bodyText: "This step shows creating a new category to separate spending behavior currently grouped too broadly. Add categories when you need clearer tracking and better targeted adjustments. Keep names distinct so users can classify entries quickly and consistently. Focused categories improve decision quality downstream.",
                            fullscreenCaptionText: "Create a category when existing labels are too broad for useful decisions."
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
                    body: "Presets are reusable templates for recurring planned expenses that appear in many budget cycles. They reduce repetitive entry work and improve consistency in planned-data setup. Use them for stable obligations such as rent, subscriptions, and utilities.\n\nWell-maintained presets accelerate period setup and reduce manual errors. Keep amounts and category mapping current so reuse stays reliable. Presets should be reviewed periodically, not created and forgotten.\n\nWhen budget setup starts feeling repetitive, presets are usually the fastest optimization. They turn repeated work into one controlled template. Good presets save time every cycle.",
                    media: [
                        mediaItem(
                            id: "settings-presets-overview-image-1",
                            assetName: "Help/CoreScreens/Settings/Presets/overview",
                            bodyText: "This image shows the Presets management list for reviewing and organizing recurring templates. Use it to keep template values and categories accurate before each cycle begins. Clean presets improve speed and reduce setup mistakes in new budgets. This is your maintenance home for recurring planned expense logic.",
                            fullscreenCaptionText: "Use Presets management to keep recurring templates accurate and ready."
                        )
                    ]
                ),
                mediaSection(
                    id: "settings-presets-add-preset",
                    header: "Add Preset",
                    body: "Adding a preset converts a recurring planned expense into a reusable template for future cycles. This improves setup speed while preserving consistency in naming and category assignment. Create presets for items that repeat with similar structure.\n\nDuring creation, prioritize accurate default values and practical names. Better defaults mean fewer edits each cycle. Template quality directly determines reuse quality.\n\nBefore final save, run a quick review of amount, category, and label clarity. A clean preset now avoids repeated correction later. Strong preset creation compounds over time.",
                    media: [
                        mediaItem(
                            id: "settings-presets-add-preset-1",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-1",
                            bodyText: "This first step shows entering core preset fields such as name, amount, and category. Choose defaults that match normal recurring behavior so reuse requires minimal edits. Clear naming helps you select the right preset quickly during budget setup. Strong defaults create repeatable efficiency.",
                            fullscreenCaptionText: "Define clear preset defaults so recurring setup needs minimal editing later."
                        ),
                        mediaItem(
                            id: "settings-presets-add-preset-2",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-2",
                            bodyText: "This step shows reviewing preset details before saving the template. Confirm amount and category mapping now so future budgets inherit reliable defaults. A careful review here prevents repeated cycle-by-cycle fixes. Save only after template intent is clear.",
                            fullscreenCaptionText: "Review and confirm preset details before save to prevent recurring setup errors."
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
                    body: "Workspaces let you separate independent budgeting contexts so data does not mix across domains. Each workspace has its own cards, categories, presets, budgets, and history. Use this when you need clear boundaries between financial contexts.\n\nSwitch intentionally and confirm active workspace before major edits. Most cross-context confusion comes from making changes in the wrong workspace. A quick active-context check prevents that.\n\nUse workspace separation to simplify analysis and reduce accidental overlap. Clean boundaries improve trust in totals and trends. Workspaces are a structural tool for clarity at scale.",
                    media: [
                        mediaItem(
                            id: "settings-workspaces-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Workspaces/overview",
                            bodyText: "This image shows the Workspaces area used to manage and switch independent budgeting contexts. Use it when you want separate histories and totals that do not overlap. Verify the active workspace before edits so records land where intended. Proper workspace use protects data boundaries and reporting clarity.",
                            fullscreenCaptionText: "Use Workspaces to keep contexts separate and prevent cross-domain data mixing."
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

private func mediaItem(
    id: String,
    assetName: String,
    bodyText: String,
    fullscreenCaptionText: String? = nil
) -> GeneratedHelpSectionMediaItem {
    GeneratedHelpSectionMediaItem(
        id: id,
        assetName: assetName,
        bodyText: bodyText,
        fullscreenCaptionText: fullscreenCaptionText
    )
}
