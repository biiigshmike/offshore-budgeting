//
//  GeneratedHelpContent.swift
//  OffshoreBudgeting
//
//  In-app help content source for Offshore.
//  Maintained directly in this file.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum GeneratedHelpAudience {
    case phone
    case nonPhone

    static var current: GeneratedHelpAudience {
        #if targetEnvironment(macCatalyst)
        return .nonPhone
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone ? .phone : .nonPhone
        #else
        return .nonPhone
        #endif
    }
}

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
    let displayTitle: String?
    let bodyText: String
    let fullscreenCaptionText: String?

    init(
        id: String,
        assetName: String,
        displayTitle: LocalizedStringResource?,
        bodyText: LocalizedStringResource,
        fullscreenCaptionText: LocalizedStringResource?
    ) {
        self.id = id
        self.assetName = assetName
        self.displayTitle = displayTitle.map(String.init(localized:))
        self.bodyText = String(localized: bodyText)
        self.fullscreenCaptionText = fullscreenCaptionText.map(String.init(localized:))
    }

    init(
        id: String,
        assetName: String,
        resolvedDisplayTitle: String?,
        resolvedBodyText: String,
        resolvedFullscreenCaptionText: String?
    ) {
        self.id = id
        self.assetName = assetName
        self.displayTitle = resolvedDisplayTitle
        self.bodyText = resolvedBodyText
        self.fullscreenCaptionText = resolvedFullscreenCaptionText
    }
}

struct GeneratedHelpSectionLinkItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImageName: String
    let url: URL
    let accessoryText: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImageName: String,
        url: URL,
        accessoryText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.url = url
        self.accessoryText = accessoryText
    }
}

struct GeneratedHelpSection: Identifiable, Hashable {
    let id: String
    let header: String?
    let bodyText: String
    let mediaItems: [GeneratedHelpSectionMediaItem]
    let linkItems: [GeneratedHelpSectionLinkItem]

    init(
        id: String,
        header: LocalizedStringResource?,
        bodyText: LocalizedStringResource,
        mediaItems: [GeneratedHelpSectionMediaItem],
        linkItems: [GeneratedHelpSectionLinkItem] = []
    ) {
        self.id = id
        self.header = header.map(String.init(localized:))
        self.bodyText = String(localized: bodyText)
        self.mediaItems = mediaItems
        self.linkItems = linkItems
    }

    init(
        id: String,
        resolvedHeader: String?,
        resolvedBodyText: String,
        mediaItems: [GeneratedHelpSectionMediaItem] = [],
        linkItems: [GeneratedHelpSectionLinkItem] = []
    ) {
        self.id = id
        self.header = resolvedHeader
        self.bodyText = resolvedBodyText
        self.mediaItems = mediaItems
        self.linkItems = linkItems
    }
}

struct GeneratedHelpLeafTopic: Identifiable, Hashable {
    let id: String
    let destinationID: String
    let title: String
    let sections: [GeneratedHelpSection]

    init(id: String, destinationID: String, title: LocalizedStringResource, sections: [GeneratedHelpSection]) {
        self.id = id
        self.destinationID = destinationID
        self.title = String(localized: title)
        self.sections = sections
    }

    init(id: String, destinationID: String, resolvedTitle: String, sections: [GeneratedHelpSection]) {
        self.id = id
        self.destinationID = destinationID
        self.title = resolvedTitle
        self.sections = sections
    }

    var searchableText: String {
        faqSearchText
    }

    var faqSearchText: String {
        var parts: [String] = [title]

        for section in sections {
            if let header = section.header {
                parts.append(header)
            }

            parts.append(section.bodyText)
            parts.append(contentsOf: section.linkItems.map(\.title))
            parts.append(contentsOf: section.linkItems.compactMap(\.subtitle))
            parts.append(contentsOf: section.linkItems.compactMap(\.accessoryText))
            parts.append(contentsOf: section.mediaItems.compactMap(\.displayTitle))
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

    func linkItems(for section: GeneratedHelpSection) -> [GeneratedHelpSectionLinkItem] {
        section.linkItems
    }
}

struct GeneratedHelpDestination: Identifiable, Hashable {
    let id: String
    let title: String
    let group: GeneratedHelpDestinationGroup
    let iconSystemName: String
    let iconStyle: GeneratedHelpIconStyle
    let leafTopicIDs: [String]

    init(
        id: String,
        title: LocalizedStringResource,
        group: GeneratedHelpDestinationGroup,
        iconSystemName: String,
        iconStyle: GeneratedHelpIconStyle,
        leafTopicIDs: [String]
    ) {
        self.id = id
        self.title = String(localized: title)
        self.group = group
        self.iconSystemName = iconSystemName
        self.iconStyle = iconStyle
        self.leafTopicIDs = leafTopicIDs
    }
}

enum GeneratedHelpContent {
    static let bookTitle: String = String(localized: "Offshore Help", defaultValue: "Offshore Help", comment: "Title for the in-app help book.")
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
                "home-system-widgets",
                "home-review-today",
                "home-customization",
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
                "budgets-category-goals",
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
            iconSystemName: "wallet.bifold.fill",
            iconStyle: .green,
            leafTopicIDs: [
                "accounts-overview",
                "accounts-card-details",
                "accounts-transaction-types",
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
                    header: "Budget Your Way",
                    body: "Budget your way. Choose any date range and the cards you want to include. Add presets for predictable expenses, record variable expenses as they happen, and set category goals wherever they help. You can start small and add more later.\n\nA workspace keeps a complete set of finances separate, such as Personal and Work. Within a workspace, a budget gives you a date range for reviewing income and selected cards. You can budget daily, weekly, by payday, monthly, or for custom dates.\n\nA preset is a reusable expense template. Including it in a budget creates its dated planned expenses. Variable expenses record individual transactions. Categories organize both kinds of expense; category goals are optional and belong to each budget."
                ),
                textSection(
                    id: "introduction-building-blocks-2",
                    header: "Where To Find Everything",
                    body: "Use the main navigation to open Home, Budgets, Income, Accounts, and Settings. Home is your one-screen summary of what needs attention, while the other screens are where records are created, edited, and verified.\n\nIf you are ever unsure where to make a change, start from the screen that owns that record type. Budgets owns budget cycles and expense planning, Income owns inflows, Accounts owns card and reconciliation workflows, and Settings owns long-term configuration. That one rule will save you a lot of backtracking."
                ),
                textSection(
                    id: "introduction-building-blocks-3",
                    header: "Basic Workflow",
                    body: "Start by creating or opening the budget period you are working in. During setup, decide which cards and presets belong to that cycle, then add planned items that make the period realistic from day one.\n\nAs the period unfolds, log variable spending and track income in Income as deposits arrive. If your income is predictable, recurring entries can reduce repetitive work. Keep categories clear and meaningful so your trends stay readable as history grows."
                ),
                textSection(
                    id: "introduction-building-blocks-4",
                    header: "Verify Your Setup",
                    body: "After you enter data, do a quick verification pass before moving on. Check Home first, then check the destination screen that owns the records you just changed.\n\nIf both views moved in the way you expected, your setup is aligned and you can continue with confidence. This short habit prevents most of the confusion that appears later during planned-versus-actual reviews."
                ),
                textSection(
                    id: "introduction-building-blocks-5",
                    header: "Building Block Pitfalls",
                    body: "The most common issue is mixing concepts, especially treating planned values like money that has already moved. Planned values still represent intent, so read savings metrics with that context in mind.\n\nAnother common issue is category overlap or unclear naming. Keep names consistent, use each screen for its intended purpose, and keep your workspace structure simple early on. A little structure now goes a long way as your history grows."
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
                    body: "Planned expenses are expected costs you want visible before money is actually spent. They represent your intention for the period and give your budget structure early, before real transactions start rolling in.\n\nUse planned expenses for recurring or predictable obligations such as rent, subscriptions, utilities, and similar fixed commitments. When planned values are clear, your savings outlook becomes much easier to trust."
                ),
                textSection(
                    id: "introduction-planned-expenses-2",
                    header: "Schedule a Planned Bill",
                    body: "Open Settings › Manage Presets and create a preset with a card, planned amount, and schedule. In Add Budget or Budget Details › Manage Presets, attach the preset to a budget that includes its default card and the scheduled date. Offshore generates the dated planned expense on that card."
                ),
                textSection(
                    id: "introduction-planned-expenses-3",
                    header: "Recording a Paid Bill",
                    body: "Open the existing planned expense in Budget Details or Card Details. In Edit Planned Expense, enter Actual Amount (optional) and choose Save. If the bill matched the estimate, use As Planned from the row actions to record the planned amount as paid.\n\nFor example, a planned electricity bill of $80 counts as $80 while the actual amount is blank or zero. Entering $72 changes its effective amount to $72. Creating a separate variable expense for the same payment would count it twice."
                ),
                textSection(
                    id: "introduction-planned-expenses-4",
                    header: "Verify They Are Working",
                    body: "Before heavy day-to-day tracking begins, confirm your planned totals look right in the active budget. This gives you a stable reference point for the rest of the period.\n\nAs actual entries come in, verify that comparisons still make sense and are highlighting true differences. Good verification here gives you early warning when spending starts drifting from your original plan."
                ),
                textSection(
                    id: "introduction-planned-expenses-5",
                    header: "Planned Expense Pitfalls",
                    body: "Before adding a preset or a separate transaction, check whether the bill already appears in Planned Expenses. If the expected cost changes for future periods, update the preset. See Delete a Budget or Change Its Links in Help › Budgets › Budget Details before removing a preset from an existing budget."
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
                    body: "Variable expenses record card activity, including purchases, refunds, and positive ledger corrections. In Add Expense, choose Debit, Credit, or Adjustment to match the transaction. See Purchases, Refunds, and Adjustments for examples of how each type affects totals."
                ),
                textSection(
                    id: "introduction-variable-expenses-2",
                    header: "Where To Record Them",
                    body: "Use Add Expense from Budget Details or Card Details and choose the card and transaction date. A variable transaction can appear in every budget in the workspace that links that card and includes the date. Set its description and amount, and choose a category if you want it grouped in spending reports."
                ),
                textSection(
                    id: "introduction-variable-expenses-3",
                    header: "How To Use Them In Workflow",
                    body: "Try to log variable spending close to when it happens so your budget stays current and useful. Small, consistent updates are easier to trust than delayed batch entry from memory.\n\nUse clear naming and accurate amounts so trend views stay reliable over time. Fast capture with clean details gives you both speed and quality."
                ),
                textSection(
                    id: "introduction-variable-expenses-4",
                    header: "Verify Your Tracking",
                    body: "After each save, confirm the expense appears in the expected budget and moves totals in the direction you anticipated. A quick check immediately after entry catches mistakes while context is still fresh.\n\nThen verify category placement so spending is landing in the right bucket. This keeps category trends clean and prevents misclassification from compounding over time."
                ),
                textSection(
                    id: "introduction-variable-expenses-5",
                    header: "Variable Expense Pitfalls",
                    body: "Avoid broad category labels that hide useful detail, especially in high-frequency variable spending areas. Clear categories make it easier to understand what is actually driving pressure.\n\nAlso avoid delaying entries too long. Delayed capture usually turns into surprise totals at period close, while steady capture keeps you in control all cycle long."
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
                    body: "Planned income is what you expect to receive before deposits actually land. It gives your budget a forward-looking baseline and helps you decide whether the period plan is realistic.\n\nThis is one of the most important setup inputs because it shapes early savings expectations. Strong planned income data gives you better decisions before the month gets busy."
                ),
                textSection(
                    id: "introduction-planned-income-2",
                    header: "Where To Enter It",
                    body: "In Income, choose + › Add Income and set Type to Planned. Enter the source, amount, and expected date, then save. See Add Planned or Actual Income in Help › Income › Planned vs Actual for the full workflow and recurring options."
                ),
                textSection(
                    id: "introduction-planned-income-3",
                    header: "How To Use It In Workflow",
                    body: "At the beginning of each cycle, enter expected income so your savings outlook starts from realistic assumptions. Then, as dates pass, compare plan versus actual and update as needed.\n\nIf inflow timing shifts or amounts come in lower, adjust spending priorities early instead of waiting for period close. Early adjustments are almost always easier than late corrections."
                ),
                textSection(
                    id: "introduction-planned-income-4",
                    header: "Verify Forecast Quality",
                    body: "Review Home and Income together to make sure planned totals reflect your true expected cash flow. If a number looks off, first check period dates and duplicate entries.\n\nWhen planned income is clean, every forecast in the app becomes more trustworthy. This is a small verification step with a big downstream payoff."
                ),
                textSection(
                    id: "introduction-planned-income-5",
                    header: "Planned Income Pitfalls",
                    body: "Do not treat planned income like guaranteed cash that is already available. Keep uncertain sources clearly separated and update expectations when reality changes.\n\nA realistic plan is always more helpful than an optimistic one. Accuracy gives you control, while optimism without verification can create avoidable pressure."
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
                    body: "Actual income is money that has already landed and is available in real cash flow. It is your source of truth for what happened in this period, not what you hoped would happen.\n\nWhen planned and actual diverge, actual income should guide decisions first. It keeps budgeting grounded in reality."
                ),
                textSection(
                    id: "introduction-actual-income-2",
                    header: "Where To Record It",
                    body: "In Income, choose + › Add Income. Use Actual under Type, then enter the source, amount, and date received. See Add Planned or Actual Income in Help › Income › Planned vs Actual for the full workflow and recurring options."
                ),
                textSection(
                    id: "introduction-actual-income-3",
                    header: "How To Use It In Workflow",
                    body: "Log deposits shortly after they clear, then compare planned versus actual while the context is still fresh. This keeps your cycle grounded in current reality.\n\nUse the variance to decide next actions: tighten spending, hold steady, or reallocate surplus. That closes the loop between expectation and outcome in a practical way."
                ),
                textSection(
                    id: "introduction-actual-income-4",
                    header: "Verify Totals",
                    body: "After saving, check Income totals and Home summary cards to confirm values moved as expected. If numbers seem inflated, check for duplicates and wrong-period dates first.\n\nThis lightweight validation keeps small entry issues from snowballing into confusing period summaries."
                ),
                textSection(
                    id: "introduction-actual-income-5",
                    header: "Actual Income Pitfalls",
                    body: "Avoid entering expected deposits as actual before money lands. Doing that can overstate available funds and make your period look healthier than it really is.\n\nAlso avoid lumping unrelated inflows under vague labels. Clear source naming and timely entry are what make income history truly useful."
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
                    body: "A budget is the period container Offshore uses to group income, expenses, and savings outcomes. It gives you a clear time window so every number is measured in the same context.\n\nWhether you run monthly or custom ranges, the budget period is the frame that keeps analysis clean and decisions consistent."
                ),
                textSection(
                    id: "introduction-budgets-2",
                    header: "Where To Create It",
                    body: "Create budgets in Budgets with clear names and deliberate start and end dates. Choose a cadence that matches how you naturally review money, so staying consistent feels practical.\n\nConsistent periods make cross-cycle comparison much easier. Irregular ranges can still work, but they require more intentional review."
                ),
                textSection(
                    id: "introduction-budgets-3",
                    header: "How To Use It In Workflow",
                    body: "After creating a budget, load planned items first, then track variable expenses and income inside the same window. Revisit the period frequently so adjustments happen while they can still help.\n\nA budget works best as an active workflow, not a one-time setup task. Short frequent check-ins beat occasional deep corrections."
                ),
                textSection(
                    id: "introduction-budgets-4",
                    header: "Verify It Is Healthy",
                    body: "Review planned versus actual directly in Budgets, then cross-check with Home to confirm alignment. If totals feel off, inspect missing entries and out-of-range dates first.\n\nThis quick health check keeps period math trustworthy from setup through closeout."
                ),
                textSection(
                    id: "introduction-budgets-5",
                    header: "Budget Pitfalls",
                    body: "When you change an existing budget’s dates, cards, or presets, check which generated planned expenses may be removed. For the effects of each action, see Delete a Budget or Change Its Links in Help › Budgets › Budget Details. Overlapping budgets can show the same variable expense when they both include its card and date."
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
                    body: "Most totals in Offshore are grouped sums filtered by period, record type, and view context. That means a number can change based on scope, even when the underlying records did not.\n\nPlanned values support forecasting, while actual values represent what really happened. Reading both in the correct context prevents most interpretation mistakes."
                ),
                textSection(
                    id: "introduction-calculations-2",
                    header: "Where Calculations Appear",
                    body: "You will see calculations throughout Home, Budgets, Income, Accounts, and detail screens. The same records may appear in different summaries depending on the purpose of that view.\n\nWhen reading any total, use labels and context clues to confirm whether you are looking at planned or actual values. That quick check keeps comparisons meaningful."
                ),
                textSection(
                    id: "introduction-calculations-3",
                    header: "How To Read Them In Workflow",
                    body: "Start with period-level totals to identify whether a meaningful shift happened. If something looks off, drill into category or entry-level detail to find the root cause.\n\nCompare planned and actual side by side whenever possible. Looking at one without the other can hide the reason a value moved."
                ),
                textSection(
                    id: "introduction-calculations-4",
                    header: "Verify A Number",
                    body: "When verifying any number, check period range first. Then confirm included entries in detail views so you can see exactly what contributed.\n\nLook for duplicates, missing records, and planned-versus-actual misclassification. This short audit process resolves most mismatches quickly."
                ),
                textSection(
                    id: "introduction-calculations-5",
                    header: "Calculation Pitfalls",
                    body: "Avoid comparing values from different periods or different data types without realizing it. The numbers may both be correct while still answering different questions.\n\nAlso avoid assuming every summary uses the same filters by default. Anchor comparisons to one timeframe and one context whenever possible."
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
                    body: "Import helps you capture batches of expense or income records faster than manual entry. It is built for speed, but still gives you a review step so quality stays in your control.\n\nUse import when repetitive typing would slow you down or increase mistakes. A clean import workflow saves time without sacrificing data trust."
                ),
                textSection(
                    id: "introduction-import-2",
                    header: "Import a Statement or Income Records",
                    body: "1. For card transactions, open Accounts › Cards, select the card, then choose + › Import Expenses. For income, open Income and choose + › Import Income.\n2. Choose Source, then Import from Files for a CSV, PDF, or image, or Import from Photos for an image.\n3. Review the parsed dates, amounts, and transaction types. A row’s date determines which budget periods can include it. Imported income is saved as Actual. Income import skips expense, credit, and adjustment rows.\n4. Review which rows are selected and choose Import when the summary is correct."
                ),
                textSection(
                    id: "introduction-import-3",
                    header: "Review Duplicates and Missing Import Data",
                    body: "Review Possible Matches, Possible Duplicates, and Needs More Data before saving. Open a row to correct its details and set a category when required. Check the inclusion circle for each entry you want to save. Leave duplicates and unwanted payment or transfer rows unselected.\n\nSave for Future Imports is a per-row switch for reusing a recognized merchant or source name and, for expenses, its category in this workspace. Review the final count before choosing Import."
                ),
                textSection(
                    id: "introduction-import-4",
                    header: "Verify The Result",
                    body: "After import, verify totals and entry counts in both list and summary views. Spot-check a few rows to confirm category and date accuracy.\n\nImmediate verification makes follow-up edits simple and catches problems before they spread into period analysis."
                ),
                textSection(
                    id: "introduction-import-5",
                    header: "Import Pitfalls",
                    body: "Avoid importing the same source repeatedly without duplicate review. Repeated batches can inflate totals quickly and create hard-to-trace variance.\n\nAlso avoid skipping category cleanup during review. Weak labels in imported data reduce report quality everywhere else."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-quick-actions",
            destinationID: "introduction",
            title: "Quick Actions",
            sections: quickActionsGuideSections(prefix: "introduction-quick-actions", isSettingsVariant: false)
        ),
        GeneratedHelpLeafTopic(
            id: "introduction-excursion-mode",
            destinationID: "introduction",
            title: "Excursion Mode",
            sections: [
                textSection(
                    id: "introduction-excursion-mode-1",
                    header: "What Excursion Mode Is",
                    body: "Excursion Mode is a focused tracking mode for high-activity windows when transactions are happening quickly. It prioritizes fast capture so you can stay present while still logging spending accurately.\n\nUse it when real-time awareness matters more than deep entry detail in the moment."
                ),
                textSection(
                    id: "introduction-excursion-mode-2",
                    header: "Start or Stop Excursion Mode",
                    body: "On a supported device, open Settings › Excursion Mode. Choose Duration, then Start Excursion Mode. To end a session early, return here and choose Stop Excursion Mode. On supported devices, use the Offshore control or Shortcut to get to Excursion Mode."
                ),
                textSection(
                    id: "introduction-excursion-mode-3",
                    header: "Configure Nearby Spending Reminders",
                    body: "In Settings › Excursion Mode, open Preferences. Choose which Categories can trigger reminders, whether to include uncategorized places, and how long to wait under Remind After. These preferences apply to this device across workspaces.\n\nFor background reminders, allow location while using the app first, then choose Change to Always Allow when prompted. Allow Once supports reminders while Offshore is open."
                ),
                textSection(
                    id: "introduction-excursion-mode-4",
                    header: "Review Expenses After an Excursion",
                    body: "Open Review Today from Home to check what was recorded during the day. Review dates, cards, and categories on any expense you want to correct."
                ),
                textSection(
                    id: "introduction-excursion-mode-5",
                    header: "If Excursion Reminders Are Missing",
                    body: "Check that the session is still active and review Offshore’s location and notification permissions in Settings. Also check the selected place categories and Remind After delay in Excursion Mode preferences. Excursion Mode is unavailable on Mac."
                )
            ]
        ),

        // MARK: Home

        GeneratedHelpLeafTopic(
            id: "home-review-today",
            destinationID: "home",
            title: "Review Today",
            sections: [
                textSection(
                    id: "home-review-today-activity",
                    header: "Review Today’s Spending and Planned Bills",
                    body: "On Home, choose Review Today. Check Today’s Activity for recorded entries and Still Planned for bills that have no recorded actual amount. In Spending Breakdown, choose By Category or By Card. In By Card, expand a card to inspect its entries. When Period Review appears, open it to review completed savings periods and see how many are waiting."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "home-system-widgets",
            destinationID: "home",
            title: "Device Widgets and Controls",
            sections: [
                textSection(
                    id: "home-system-widgets-desktop",
                    header: "Home Screen and Mac Desktop Widgets",
                    body: "Search for Offshore in the widget gallery on the iPhone or iPad Home Screen or the Mac desktop. Look for Income, Card, Spend Trends, Next Planned Expense, Safe Spend Today, and Forecast Savings. The gallery shows the sizes available for your device and placement."
                ),
                textSection(
                    id: "home-system-widgets-gallery",
                    header: "Lock Screen Widgets",
                    body: "On supported Lock Screens, search for Offshore in the widget gallery. The Lock Screen collection includes Next Planned Expense, Safe Spend Today, Forecast Savings, Category Limit, and Next Income. Category Limit can be configured to show the top-spending category among those with a budget limit."
                ),
                textSection(
                    id: "home-system-widgets-controls",
                    header: "Controls and Excursion Live Activity",
                    body: "On supported iPhone and iPad setups, search for Offshore in the controls gallery to add Add Expense, Add Income, Review Today, or Excursion Mode. Excursion Mode can also display a Live Activity on supported devices. See Help › Introduction › Excursion Mode for setup and location permissions."
                )
            ]
        ),
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
                            bodyText: "The Home dashboard acts as a starting point for daily review. Read top-level totals first, then look for any widget that suggests a shift in spending, income, or savings direction. When something needs clarification, open the matching core screen and validate the underlying entries. Returning to Home after each adjustment helps you confirm whether the correction improved the period outlook.",
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
                    body: "On Home, choose Edit to open the editor. Under Pinned on Dashboard, choose Edit to reorder your tiles. Drag them into place, then choose Done. On Mac, the editor opens beside the dashboard.",
                    media: [
                        mediaItem(
                            id: "home-customization-edit-home-1",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-1",
                            bodyText: "Choose Edit on Home to open the dashboard editor.",
                            fullscreenCaptionText: "Open the Home editor."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-2",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-2",
                            bodyText: "Under Pinned on Dashboard, choose Edit and drag items to arrange them.",
                            fullscreenCaptionText: "Drag pinned items into your preferred order."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-3",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-3",
                            bodyText: "Choose Done after rearranging your widgets, then check their order on Home.",
                            fullscreenCaptionText: "Finish editing with Done."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "home-widgets",
            destinationID: "home",
            title: "Home Dashboard Widgets",
            sections: [
                textSection(
                    id: "home-widgets-category-goals",
                    header: "Category Goals",
                    body: "Category Goals compares spending during Home’s selected dates with maximums from the budget named in the widget subtitle. The marker on each category’s chart is its maximum; spending can extend beyond it. Each row uses its own scale. Categories without a maximum show unlimited availability.\n\nTap a category to edit its minimum and maximum for that budget. The editor uses the full budget’s dates and linked cards, so its spending totals can differ from Home. Save to apply changes, or Cancel to keep the goals unchanged. Use the page controls to review more categories."
                ),
                mediaSection(
                    id: "home-widgets-overview",
                    header: "Choose Widgets for Your Dashboard",
                    body: "Home widgets are designed to answer distinct budgeting questions quickly without opening every screen. Each tile provides a focused signal, and together they form a reliable daily scan pattern. Use them in sequence so you can detect pressure, prioritize action, and decide where to drill in next.\n\nTreat widgets as an early-warning system. They help you catch shifts while there is still time to correct course. When one tile changes sharply, verify the cause in Budgets, Income, or Accounts before making decisions.\n\nConsistency matters more than speed here. A short repeatable scan each day usually produces better outcomes than occasional deep dives. Use the same order to build confidence and reduce missed signals.",
                    media: [
                        mediaItem(
                            id: "home-widgets-income",
                            assetName: "Help/CoreScreens/Home/Widgets/income",
                            displayTitle: "Income",
                            bodyText: "The income widget helps you compare expected versus received inflows at a glance. Use it early in the period to detect timing delays or lower-than-planned deposits. If a gap appears, adjust planned spending priorities before pressure builds. This widget is your first check for cash-flow reliability.",
                            fullscreenCaptionText: "Compare planned and actual income quickly to spot shortfalls early."
                        ),
                        mediaItem(
                            id: "home-widgets-savings-outlook",
                            assetName: "Help/CoreScreens/Home/Widgets/savings-outlook",
                            displayTitle: "Savings Outlook",
                            bodyText: "Savings Outlook projects where the period may end based on current entries and assumptions. Review it after adding meaningful expenses or income updates so direction changes are visible immediately. Use this signal to decide whether you need to slow discretionary spending. Frequent checks keep surprises smaller at period close.",
                            fullscreenCaptionText: "Use Savings Outlook to forecast direction and course-correct before period close."
                        ),
                        mediaItem(
                            id: "home-widgets-spend-trends",
                            assetName: "Help/CoreScreens/Home/Widgets/spend-trends",
                            displayTitle: "Spend Trends",
                            bodyText: "Spend Trends emphasizes movement over time, not just a single total. Watch for acceleration patterns that indicate a category or habit is drifting upward. When trend slope changes, inspect recent entries to identify what triggered the shift. Early trend awareness makes interventions more effective.",
                            fullscreenCaptionText: "Watch trend direction, not just totals, to catch acceleration early."
                        ),
                        mediaItem(
                            id: "home-widgets-category-spotlight",
                            assetName: "Help/CoreScreens/Home/Widgets/category-spotlight",
                            displayTitle: "Category Spotlight",
                            bodyText: "Category Spotlight highlights which categories currently have the most budget pressure. Use this to find the best place for small behavior changes that can create meaningful impact. After identifying a heavy category, open details and verify the entries driving that weight. This supports targeted adjustments instead of broad guesswork.",
                            fullscreenCaptionText: "Use Category Spotlight to find the categories creating the most pressure."
                        ),
                        mediaItem(
                            id: "home-widgets-what-if",
                            assetName: "Help/CoreScreens/Home/Widgets/what-if",
                            displayTitle: "What If",
                            bodyText: "What If lets you test potential spending adjustments before committing to them in your real plan. Use it when you are deciding between competing choices or trying to recover from an unfavorable trend. Simulating outcomes helps you choose options with clearer tradeoffs. It is a safe planning step before making real entries.",
                            fullscreenCaptionText: "Run What If scenarios to compare tradeoffs before committing real changes."
                        )
                    ]
                ),
                textSection(
                    id: "home-widgets-next-planned",
                    header: "Next Planned Expense on Home",
                    body: "Pin Next Planned Expense from the Home editor to see the upcoming planned bill in Home’s selected range. If nothing qualifies, the tile says No planned expenses coming up in this range."
                ),
                textSection(
                    id: "home-widgets-what-if-scenarios",
                    header: "Save, Pin, or Export a What If Scenario",
                    body: "Open What If? on Home. Use the scenario menu to create, duplicate, or rename a scenario. Choose Pin to Home to show it on your dashboard, or Unpin from Home to remove it from the dashboard. Use Export to share the scenario as CSV, PDF, or text. Simulated adjustments stay in the scenario."
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
                            bodyText: "The list of budget periods shows current status at a glance. Use it to quickly locate the active period, then open it for daily updates and review. If multiple periods exist, confirm dates before editing so entries stay in the correct cycle. A fast period check prevents confusing totals later.",
                            fullscreenCaptionText: "Start in Budgets to open the correct period before making any updates."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-overview-create-budget",
                    header: "Create a Budget",
                    body: "1. Open Budgets and choose + (Add Budget).\n2. Enter a Name or keep the suggested one. Set the Start Date and End Date. Both dates are included.\n3. Under Cards, select the cards to include. If the workspace has none, use Add Card. A budget with no linked cards cannot add expenses from Budget Details.\n4. Under Presets, choose any recurring bills to include. An eligible preset generates dated planned expenses when you save.\n5. Choose Save, then open the new budget and check its dates, cards, and planned expenses.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-create-budget-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-1",
                            bodyText: "Choose the budget dates and review the suggested name, or enter your own.",
                            fullscreenCaptionText: "Set the name, start date, and end date."
                        ),
                        mediaItem(
                            id: "budgets-overview-create-budget-2",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-2",
                            bodyText: "Select the cards and any presets before saving. Check the generated planned expenses in Budget Details afterward.",
                            fullscreenCaptionText: "Review the selected cards and presets before saving."
                        )
                    ]
                ),
                textSection(
                    id: "budgets-overview-repeat",
                    header: "Create Recurring Budgets",
                    body: "In Add Budget, use Repeat to choose the cadence, then set Every and Number of budgets. The count includes the first budget. Choose Preview to review the dates before creating the batch. Each budget is independent, so editing one later affects that budget alone."
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
                    body: "Use Add Expense for a separate variable transaction. If a bill already has a planned expense, open that existing row and record its actual amount instead of creating a second expense.\n\nChoose Debit for a purchase, Credit for a refund, or Adjustment for a positive ledger correction. The help article Purchases, Refunds, and Adjustments explains why gross spending, signed ledger totals, and budget impact can differ.\n\nSplit assigns part of a purchase to a reconciliation balance. Offset records a settlement against that balance. Pay From Savings uses available leftover money to reduce a purchase’s budget impact. Choose the action that matches what happened; reconciliation actions and Pay From Savings cannot be combined on one expense.",
                    media: [
                        mediaItem(
                            id: "budgets-details-add-expense-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-1",
                            bodyText: "Add Expense opens a variable transaction. Under Transaction Type, choose Debit for a purchase, Credit for a refund, or Adjustment for a positive ledger correction. To record payment for a planned bill, open its existing row.",
                            fullscreenCaptionText: "Choose Debit, Credit, or Adjustment in the Add Expense form."
                        ),
                        mediaItem(
                            id: "budgets-details-add-expense-2",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-2",
                            bodyText: "Enter the Description and amount, then confirm the date and card. Category is optional. When available, use Split, Offset, or Pay From Savings to reflect how the transaction was handled.",
                            fullscreenCaptionText: "Enter the transaction details and review the selected action before saving."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "In Budget Details, use Categories, the expense type picker, and Search to find records within the budget’s existing dates and linked cards. Use Sort to change their order. Clear filters when you want the full list again.",
                    media: [
                        mediaItem(
                            id: "budgets-details-filter-expenses-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/filter-expenses",
                            bodyText: "Use Categories or the expense type picker to narrow the budget list. Search can match the name, category, card, date, or amount.",
                            fullscreenCaptionText: "Filter or search within the budget’s existing scope."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-spending-limits",
                    header: "Category Goals",
                    body: "Set optional minimum and maximum spending goals for each category. In Budget Details, open Budget Actions (…) › Category Goals to edit them. A minimum is a target you want to reach; a maximum is a ceiling. Goals guide your review without blocking expense entry.\n\nCategory Goals belong to this budget. You can set them while creating a budget or edit them later. The Goals list includes categories with no spending yet, so you can plan ahead. Leave either amount blank when you do not need that goal.",
                    media: [
                        mediaItem(
                            id: "budgets-details-spending-limits-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/spending-limits",
                            bodyText: "In Budget Details, open Budget Actions (…) › Category Goals to set its minimum and maximum spending goals for this budget. Review recent spending before changing a goal. Minimums are targets; maximums are ceilings; either can be left blank.",
                            fullscreenCaptionText: "Set category goals to surface budget pressure before it compounds."
                        )
                    ]
                ),
                textSection(
                    id: "budgets-details-delete-budget",
                    header: "Delete a Budget or Change Its Links",
                    body: "Open Budget Actions › Delete Budget. If the budget generated planned expenses, Keep All Expenses removes the budget and keeps its expenses on their cards. Delete Budget-Planned Expenses removes unrecorded generated rows first. If there are recorded rows, Offshore opens Review Recorded Expenses so you can choose which of those rows to delete.\n\nSaving Edit Budget with a narrower date range, different linked cards, or a deselected preset can remove generated expenses, including rows with an actual amount. Removing a preset in Manage Presets deletes its generated rows for this budget, including recorded ones. When removing a card through Manage Cards, review the choices shown. Use Keep All Expenses when offered to preserve its existing expense history."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "budgets-category-goals",
            destinationID: "budgets",
            title: "Category Goals",
            sections: [
                textSection(
                    id: "budgets-category-goals-savings",
                    header: "Savings at Goal Maximums",
                    body: "Maximums also power Savings at Goal Maximums in Budget Detail and Category Goals on Home.\n\nThe savings estimate starts with planned income, subtracts current expense impact, then reserves the unused allowance under each category maximum. Planned expenses use recorded amounts when available and planned amounts otherwise. Shared splits, payments from savings, and refunds follow the usual budget-impact rules. Expenses are counted once, and spending already above a maximum stays included.\n\nThe estimate uses the full budget’s linked cards and dates, regardless of search, category filters, or expense-list type. Future-expense calculation settings still apply. Categories without a maximum, including minimum-only goals and Uncategorized, receive no extra allowance. Manual savings adjustments are not included.\n\nThis scenario appears when at least one maximum is set, including zero. Projected Savings keeps its existing meaning. Category Goals on Home uses goals from the budget named in its subtitle and spending during Home’s selected dates, so its amounts can differ from Budget Detail."
                ),
                textSection(
                    id: "budgets-category-goals-editing",
                    header: "Set Minimum and Maximum Goals",
                    body: "Set optional minimum and maximum spending goals for each category. In Budget Details, open Budget Actions (…) › Category Goals to edit them. A minimum is a spending target you want to reach; a maximum is a ceiling you want to stay within. Either can be left blank.\n\nGoals belong to one budget, so Groceries can have a different maximum in a weekly budget and a monthly budget. They guide your review without preventing you from recording expenses. All categories in the workspace are available, including ones with no spending yet."
                ),
                textSection(
                    id: "budgets-category-goals-creation",
                    header: "Goals During Budget Creation",
                    body: "Open the optional Category Goals section while creating a budget. Enter only the goals you need. These values remain a draft until you save the budget; canceling budget creation discards them.\n\nChoose which presets to include. Offshore creates their planned expenses within this budget’s dates. Select the cards you want this budget to track so their expenses can contribute to its totals."
                ),
                textSection(
                    id: "budgets-category-goals-auto-configure",
                    header: "Auto-Configure Goals",
                    body: "While creating a budget, enable Auto-Configure to fill minimums from attached presets assigned to selected cards. If no positive preset minimum applies, an eligible blank minimum can use the lowest comparable spending amount, with a floor of zero. Blank maximums can be suggested from average category spending in previous comparable budgets. Open a category to see the budgets behind its suggestion. You can edit every amount. Turning Auto-Configure off restores the previous values where suggestions are unchanged and keeps your manual edits.\n\nSet workspace defaults in Settings > Manage Categories > Auto-Configure Goals. Start with 3 past budgets and no extra cushion, or choose 1–12 budgets and a cushion from zero to 100 percent. Only budgets ending before today and before the new budget are used. Overlapping history windows are skipped. Durations match exactly, except 28–31 days, 90–92 days, and 365–366 days are treated as comparable groups.\n\nHistory follows Budget Detail totals: recorded actual amounts where available, planned amounts otherwise, with splits, refunds, and savings offsets included. Empty periods count as zero after the category first appears in expenses or goals. Limited history uses fewer samples; no history leaves the maximum blank. Suggestions are at least the planned or entered minimum. They are a starting point, not an assessment of affordability. Defaults sync with the workspace when using iCloud and are included in workspace backups. Changing defaults does not change saved goals."
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
                    body: "If a future expense is missing from the list or a total, open Expense Display from the eye button. Hide Future Planned Expenses and Hide Future Variable Expenses remove rows from the list. Exclude Future Planned Expenses from Totals and Exclude Future Variable Expenses from Totals change the calculations. Check each setting separately.\n\nSet your defaults in Settings › General › Expense Display.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/overview",
                            bodyText: "Open Expense Display to check the list and calculation controls for each expense type.",
                            fullscreenCaptionText: "Check both the Hide and Exclude from Totals settings."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-calculations-details",
                    header: "How Is This Calculated?",
                    body: "In the budget Overview, choose How is this calculated? to see the inputs behind the totals. If an amount is unexpected, check the budget dates, linked cards, expense type, and Exclude from Totals settings. Then check the underlying transactions for changes such as refunds, splits, payments from savings, or newly recorded actual amounts.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-details-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/calculations",
                            bodyText: "Use the breakdown to trace a budget total to the income and expense amounts included in it.",
                            fullscreenCaptionText: "Open How is this calculated? to see the inputs for the current budget."
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
                    body: "Income uses a calendar-centered workflow so you can track inflows by date and context. This makes it easier to match expected deposits with what actually arrived. Start here whenever validating cash flow reliability for the active cycle.\n\nMove through days intentionally instead of scanning only totals. Date-level review helps you catch timing shifts that can affect spending decisions. Even when totals look fine, timing issues can still create pressure.\n\nA strong routine is to review the selected date, confirm planned versus actual, then update records immediately. That habit keeps all downstream calculations aligned. Income accuracy is critical for trustworthy savings projections.",
                    media: [
                        mediaItem(
                            id: "income-overview-1-image-1",
                            assetName: "Help/CoreScreens/Income/Overview/overview",
                            bodyText: "The calendar-driven Income workspace supports daily verification. Use this to move between dates and confirm what was planned versus what was received. If a deposit is missing or delayed, update records so budget pressure reflects reality. Daily validation here keeps Home and Budget signals honest.",
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
                            bodyText: "This image shows adding Actual Income received and setting it up as a recurring series. If an income source varies, consider using the Planned segment and logging income when actually received.",
                            fullscreenCaptionText: "Adding an Actual income recurring series, repeats every 2 weeks on Fridays, ending 1 year from now."
                        )
                    ]
                ),
                textSection(
                    id: "income-add-planned-or-actual",
                    header: "Add Planned or Actual Income",
                    body: "1. Open Income, select a day, then choose + › Add Income. The form starts with Actual selected.\n2. Under Type, select Planned for money you expect or Actual for money you have received.\n3. Enter Source, Amount, and Date. Choose a card if you want to associate the entry with one.\n4. Choose Save. Check the entry and its type in Income."
                ),
                textSection(
                    id: "income-repeat",
                    header: "Set Up or Edit Recurring Income",
                    body: "To repeat an income entry, choose a schedule under Repeat, set an End Date, and save.\n\nWhen editing a repeating entry, Just This Income changes a single occurrence. Use it when one paycheck differs. This and Future applies the change from the selected occurrence forward. All in Series applies the change across the series while keeping individual exceptions. Review the scope before saving."
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
                    body: "Accounts is the hub for card activity, shared-balance reconciliation, and savings tracking. It helps you separate normal spending workflows from settlement and reserve workflows so your data stays organized.\n\nOpen Accounts to see Cards, Reconciliations, and Offshore Savings together. Choose a destination row to open it. On iPad and Mac, you can also choose its child destination in the sidebar. Use Accounts in the destination toolbar to return to the overview, or the Section menu to switch directly.\n\nA quick review pass in Accounts each cycle keeps card-level accuracy strong and improves related reports across the app.",
                    media: [
                        mediaItem(
                            id: "accounts-overview-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Overview/overview",
                            bodyText: "Accounts is the launch point for Cards, Reconciliations, and Offshore Savings workflows. Use the Section menu in the toolbar to choose the right area for the job. Container-first navigation keeps edits easier to validate and reduces accidental cross-workflow changes.",
                            fullscreenCaptionText: "Use the Section menu to switch between Cards, Reconciliations, and Offshore Savings."
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
                            bodyText: "Card Detail is where transactions are reviewed with focused controls. Use category and date scopes when reconciling statements or cleaning inconsistent tagging. Start with broad context, then narrow to the exact rows driving the issue. This keeps card cleanup accurate and efficient.",
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
                            bodyText: "Card-level filters narrow transaction review. Use filtered scopes to isolate the exact rows tied to a discrepancy or cleanup goal. Once identified, update entries and recheck scoped totals for confirmation. Focused filtering can cut investigation time dramatically.",
                            fullscreenCaptionText: "Filter card transactions to isolate the rows tied to your current review goal."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-card-details-import-expenses",
                    header: "Import Expenses",
                    body: "Open a card, choose + › Import Expenses, then Choose Source to import a CSV, PDF, or image. Check that the file belongs to this card. Review the row dates and transaction types, resolve possible duplicates, and confirm the selected rows before choosing Import.\n\nUse Save for Future Imports on individual rows to remember a recognized merchant’s name or category in this workspace. See Help › Introduction › Import for the full walkthrough and the separate income path.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-import-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/import-expenses",
                            bodyText: "Review the parsed transactions for the selected card. Check row details and selection before using Import.",
                            fullscreenCaptionText: "Check the card, dates, and included rows before importing."
                        )
                    ]
                ),
                textSection(
                    id: "accounts-card-details-delete",
                    header: "Delete a Card",
                    body: "Open the card, then choose Card Actions › Delete Card. Deleting a card also deletes its planned expenses, variable expenses, and linked income, and removes the card from budgets. Review the card’s history before confirming. To remove the card from just one budget, use Manage Cards in that budget and review the choices for its existing expenses."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-transaction-types",
            destinationID: "accounts",
            title: "Purchases, Refunds, and Adjustments",
            sections: [
                textSection(
                    id: "accounts-transaction-types-debit",
                    header: "Debit: Purchases and Charges",
                    body: "Choose Debit for a purchase or charge, including a purchase paid with a credit card. Debit describes the transaction’s effect, not the type of card.\n\nA $40 debit adds $40 to the signed card ledger and gross spending totals. It normally adds $40 of budget impact too. A reconciliation split or Pay From Savings can reduce your budget impact while the full purchase remains in card history."
                ),
                textSection(
                    id: "accounts-transaction-types-credit",
                    header: "Record a Refund or Credit",
                    body: "1. Open Accounts › Cards and select the card that received the refund.\n2. Choose + › Add Expense. Set Transaction Type to Credit.\n3. Enter a description, the refund as a positive amount, and the date the refund was posted. Choose Save and check card history.\n\nA $10 credit subtracts $10 from the signed card ledger and budget impact. After a $40 purchase, the net ledger amount is $30. The purchase still contributes $40 to gross spending. If the refund arrives in a later budget period, it can affect that period when the budget includes its date and card."
                ),
                textSection(
                    id: "accounts-transaction-types-adjustment",
                    header: "Adjustment: Positive Ledger Corrections",
                    body: "Choose Adjustment for a positive correction to the card ledger that should not count as a purchase.\n\nA $5 adjustment adds $5 to the signed card ledger. It contributes zero to gross spending totals and has zero budget impact in savings calculations. To record money returned from a purchase, use Credit instead."
                ),
                textSection(
                    id: "accounts-transaction-types-totals",
                    header: "Why Totals Can Differ",
                    body: "The signed card ledger counts debits and adjustments as positive and credits as negative. In the Variable view, Total Spent counts debit purchases before refunds. The Planned view uses each expense’s actual amount when greater than zero and its planned amount otherwise. The combined view includes both.\n\nBudget impact accounts for credits, your share after reconciliation splits, and Pay From Savings. Adjustments have zero budget impact. Date ranges, filters, and future-expense calculation settings determine which amounts are included."
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
                            bodyText: "The card calculation view validates scoped totals. Use it to confirm how current filters and entry composition produce the number you are seeing. If totals changed, trace contributing groups before editing additional data. Clear tracing helps you fix the right issue the first time.",
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
                textSection(
                    id: "accounts-reconciliations-actions",
                    header: "Split and Offset",
                    body: "Split assigns part of a purchase to a reconciliation balance. For example, a $100 purchase with a $40 split keeps the full $100 in card history, adds $40 to that reconciliation balance, and leaves $60 as your budget impact.\n\nOffset records a negative settlement against the chosen reconciliation balance. A $40 offset reduces that shared balance by $40. It does not use Offshore Savings or reduce the expense’s budget impact.\n\nTo cover an expense with leftover money from earlier periods, choose Pay From Savings instead. A reconciliation action and Pay From Savings cannot be applied to the same expense. For credits and adjustments, splits and payments from savings do not change their normal budget impact: credits retain their full negative amount and adjustments contribute zero."
                ),
                mediaSection(
                    id: "accounts-reconciliations-overview",
                    header: "Reconciliations Overview",
                    body: "Reconciliations track shared balances separately from normal card spending so settle-up workflows remain clear. Use them when money is fronted, split, or owed between people. This keeps peer-to-peer tracking structured and auditable.\n\nEach reconciliation maintains a running ledger of allocations and settlements. Over time, that timeline gives clear context for why a balance changed. Good naming and notes make this history much easier to interpret later.\n\nReview reconciliation ledgers periodically even when balances seem stable. Early verification prevents stale misunderstandings with shared expenses. Consistent maintenance keeps settle-up conversations simple.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/overview",
                            bodyText: "The Reconciliations list manages shared balances. Use it to create and monitor person-specific or context-specific ledgers without mixing them with card expenses. Keep names explicit so balances are easy to recognize during review. Separate ledgers make settlement progress easier to communicate.",
                            fullscreenCaptionText: "Use Reconciliations to track shared balances separately from normal card spending."
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
                            bodyText: "The reconciliation detail timeline supports full ledger audit. Review entries in order to confirm how the current balance was produced. Use it before settle-up conversations so you can explain each movement clearly. A complete timeline review reduces ambiguity and mistakes.",
                            fullscreenCaptionText: "Use detail view to audit the full reconciliation timeline before final settlement."
                        )
                    ]
                ),
                mediaSection(
                    id: "accounts-reconciliations-add-settlement",
                    header: "Add a Settlement",
                    body: "Open the reconciliation account and choose Add Settlement. Enter a positive Amount. Under Direction, They Owe Me adds it to the balance and I Owe Them subtracts it. For example, if someone owes you $60 and repays $20, choose I Owe Them to subtract $20 and leave $40 owed. Check the resulting balance in the account timeline.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-1",
                            bodyText: "Choose a direction based on the change you want to make to the current balance.",
                            fullscreenCaptionText: "They Owe Me adds to the balance. I Owe Them subtracts from it."
                        ),
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-2",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-2",
                            bodyText: "Enter the amount and review the direction before saving. Check the settlement and resulting balance in the account timeline.",
                            fullscreenCaptionText: "Verify the signed settlement in the reconciliation timeline."
                        )
                    ]
                ),
                textSection(
                    id: "accounts-reconciliations-archive",
                    header: "Archive a Reconciliation",
                    body: "Open Accounts › Reconciliations and choose Archive from the account’s actions when it has history. Existing allocations and settlements stay in history, and the account is hidden from new allocation choices. Accounts without allocations or settlements can be deleted."
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "accounts-savings-account",
            destinationID: "accounts",
            title: "Offshore Savings",
            sections: [
                textSection(
                    id: "accounts-savings-account-calculations",
                    header: "Outlook Versus Available Balance",
                    body: "Projected Savings is planned income minus planned expenses at their original planned amounts, after splits. Max Savings is planned income minus the effective budget impact of planned expenses. Neither includes variable transactions.\n\nActual Savings starts with actual income, subtracts effective planned-expense and variable-expense budget impacts, then includes manual savings adjustments in the selected dates. A planned expense uses its actual amount when greater than zero, otherwise its planned amount. Actual Savings therefore still allows for bills you have not recorded as paid.\n\nThe available Offshore Savings running total is the sum of period closes, manual adjustments, and payments from savings across all dates. It is different from Actual Savings for a selected period. Legacy reconciliation mirrors are excluded. Tap How is this calculated? to inspect the amounts used by the current screen."
                ),
                mediaSection(
                    id: "accounts-savings-account-overview",
                    header: "Money Available for Future Expenses",
                    body: "Offshore Savings tracks money left over from completed default budgeting periods that remains available for future expenses. Running Total includes your full savings ledger across all dates. Current Period shows ledger activity for the selected date range.\n\nPeriod closes follow your Default Budgeting Period and its calendar boundaries. They do not make a separate deposit whenever a custom budget ends. Daily, weekly, monthly, and other custom Budget records are views of your finances, not separate savings accounts.\n\nPay From Savings reduces an expense’s budget impact while keeping the full transaction in card history. Set Aside as Savings removes money from this available balance when you reserve it elsewhere. Offshore records these changes; it does not move money between bank accounts.",
                    media: [
                        mediaItem(
                            id: "accounts-savings-account-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Savings Account/overview",
                            bodyText: "The Offshore Savings ledger shows period-close amounts, manual adjustments, and expense offsets. Use Running Total for the full ledger balance or Current Period to review activity in the selected date range.",
                            fullscreenCaptionText: "Review your available Offshore Savings balance and its ledger history."
                        )
                    ]
                ),
                textSection(
                    id: "accounts-savings-account-period-review",
                    header: "Review Before Posting",
                    body: "Open Period Review in Offshore Savings to check completed periods. Review Today also links to this dedicated screen and shows how many periods are waiting. Each review shows overlapping budgets, income, expenses, the calculated closing amount, and the change it would make to your available Savings balance.\n\nTap an income or expense to edit it. Press and hold for all row actions, or swipe to reveal them. Planned expenses still use their planned amounts until you record an actual amount. If the records don’t tell the whole story, turn on Use a Different Amount. Zero and negative amounts are fine. Add a note if you like; leaving it blank uses the usual period-close text. When you’re ready, turn on Update Savings, then tap Save at the top to confirm. Your transactions and existing manual adjustments stay as they are.\n\nChanges after confirmation appear under Needs Review. The posted amount stays in Savings until you confirm again. Posted History also lets you deliberately review older closes; existing closes are not automatically queued when you first use this feature.\n\nReview Before Posting Savings is enabled by default and saved with your workspace in Settings > General. Turning it off enables automatic posting only for periods ending afterward. Older pending periods still need review, and corrected closes remain protected from automatic recalculation."
                ),
                textSection(
                    id: "accounts-savings-account-set-aside",
                    header: "Set Aside as Savings",
                    body: "In Accounts > Offshore Savings, add a savings entry, enter the amount, and enable Set Aside as Savings. Record money you have moved into savings and no longer want available for future expenses. This subtracts it from Offshore Savings; Offshore does not transfer money between bank accounts or create a second savings balance.\n\nFor example, with $500 available, covering $40 of a $100 purchase leaves $460 available and gives that purchase a $60 budget impact. Setting aside another $200 leaves $260 available. The full $100 purchase remains in card history and gross spending totals.\n\nSet Aside reduces the available Offshore Savings running total and leaves Actual Savings unchanged. The ledger keeps a record of the change."
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
                            bodyText: "The main Settings list keeps all management areas in one place. Use it to choose whether you are adjusting behavior, security, sync, or organizational data. Starting from this index helps you enter the correct section quickly. A clear route through Settings reduces accidental changes in unrelated areas.",
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
                            bodyText: "General settings tune core display and calculation behavior. Use this to control how planned and variable items are surfaced and interpreted in summaries. After updates, validate one familiar screen to ensure the result matches your intent. Purposeful configuration here keeps totals predictable.",
                            fullscreenCaptionText: "Adjust General preferences to control global display and calculation behavior."
                        )
                    ]
                ),
                textSection(
                    id: "settings-general-expense-display",
                    header: "Expense Display and Future Expense Totals",
                    body: "In Settings › General › Expense Display, use the Hide Future switches to control whether expenses dated after today appear in lists. The separate Exclude from Totals switches affect totals and savings calculations. Planned and variable expenses each have their own pair of switches."
                ),
                textSection(
                    id: "settings-general-maintenance",
                    header: "Reset Tips, Repeat Onboarding, or Erase Content",
                    body: "Open Settings › General › Maintenance. Reset Tips & Hints makes tips eligible to appear again. Repeat Onboarding repeats setup while keeping your data and data source. Reset & Erase Content erases on-device app data. In iCloud mode, switch to On Device and relaunch to access the erase action. To keep a copy first, see Back Up or Import a Workspace in Help › Settings › Workspaces."
                ),
                textSection(
                    id: "settings-general-uncategorized-review",
                    header: "Review Uncategorized Expenses on App Open",
                    body: "In Settings › General › Behavior, enable Review Uncategorized Expenses on App Open. Offshore offers to review uncategorized expenses in the selected workspace when you open or return to the app. Assign categories as needed, or choose Skip to defer the review."
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
                    body: "Use Settings › Privacy to see which permissions Offshore has. On iPhone and iPad, use Open App Settings to manage system permissions. On Mac, the system photo picker can select an image without full library access. Use Open Photos Settings when it appears for denied or restricted access. The core budgeting features work offline.",
                    media: [
                        mediaItem(
                            id: "settings-privacy-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Privacy/overview",
                            bodyText: "Review Offshore’s permission status and use the available settings action for your device.",
                            fullscreenCaptionText: "Review privacy permissions and app lock in Settings."
                        )
                    ]
                ),
                textSection(
                    id: "settings-privacy-app-lock",
                    header: "Lock Offshore with Face ID or Touch ID",
                    body: "Open Settings › Privacy. Under Security, turn on Use Face ID or Use Touch ID when it is available on your device. Use your device settings to set up biometrics first if needed."
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
                    header: "Set Up Scheduled Reminders",
                    body: "Open Settings › Notifications and turn on Send Scheduled Reminders. Set the shared Time, then choose Daily Expense Reminder, Planned Income Reminder, or Preset Expense Due Reminder. You may see Set Up Reminders when none are selected. If the system has denied notifications, use Open Settings and allow notifications for Offshore. Excursion Mode reminders are controlled separately.",
                    media: [
                        mediaItem(
                            id: "settings-notifications-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Notifications/overview",
                            bodyText: "Choose a time and turn on the scheduled reminders you want. Excursion Mode has its own reminder settings.",
                            fullscreenCaptionText: "Set the shared reminder time and choose individual reminders."
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
                    header: "Switch Between iCloud and On Device",
                    body: "In Settings › iCloud, use Use iCloud to Sync Data, then quit and relaunch Offshore. iCloud and On Device use separate data stores. Switching to iCloud opens your iCloud data and leaves the on-device data available when you switch back. To move a workspace between the two stores, export it first, switch and relaunch, then import the archive.\n\nThe status shows whether syncing is enabled and whether iCloud is available. To confirm a particular change has arrived, check the record on the other device. Once iCloud is active, Sync Options separately controls Home Layout and What-if Scenarios.",
                    media: [
                        mediaItem(
                            id: "settings-icloud-1-image-1",
                            assetName: "Help/CoreScreens/Settings/iCloud/overview",
                            bodyText: "Use this screen to check the active storage mode and change the optional Home Layout and What-if Scenarios sync settings.",
                            fullscreenCaptionText: "Relaunch Offshore after changing the data source."
                        )
                    ]
                )
            ]
        ),
        GeneratedHelpLeafTopic(
            id: "settings-quick-actions",
            destinationID: "settings",
            title: "Quick Actions",
            sections: quickActionsGuideSections(prefix: "settings-quick-actions", isSettingsVariant: true)
        ),
        GeneratedHelpLeafTopic(
            id: "settings-categories",
            destinationID: "settings",
            title: "Categories",
            sections: [
                mediaSection(
                    id: "settings-categories-overview",
                    header: "Categories Overview",
                    body: "Categories define the language your spending data uses across Budgets, Accounts, and Home insights. Clean category structure improves filters and trend interpretation. This is one of the highest-leverage maintenance areas in Settings.\n\nReview category naming periodically to reduce overlap and ambiguity. Broad or duplicate labels make analysis harder and decisions slower. Clear taxonomy leads to clearer action.\n\nWhen spending patterns evolve, update categories deliberately rather than forcing everything into old buckets. Maintenance here protects long-term report quality. Category hygiene compounds over time.",
                    media: [
                        mediaItem(
                            id: "settings-categories-overview-image-1",
                            assetName: "Help/CoreScreens/Settings/Categories/overview",
                            bodyText: "The category management list organizes your spending taxonomy. Use this to review naming consistency and remove ambiguity before it spreads into reports. Well-maintained categories make every filter and trend easier to trust. Small cleanup sessions here pay off across the entire app.",
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
                            bodyText: "This step creates a new category to separate spending behavior that is currently grouped too broadly. Add categories when you need clearer tracking and better targeted adjustments. Keep names distinct so that you can classify entries quickly and consistently.",
                            fullscreenCaptionText: "Create a category when existing labels are too broad for useful decisions."
                        )
                    ]
                ),
                textSection(
                    id: "settings-categories-archive",
                    header: "Archive or Unarchive a Category",
                    body: "In Settings › Manage Categories, use a category’s actions and choose Archive. Existing expenses keep their category. To use the category again, open the Archived section and choose Unarchive."
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
                            bodyText: "The Presets management list is for reviewing and organizing recurring templates. Use this to keep template values and categories accurate before each cycle begins. Clean presets improve speed and reduce setup mistakes in new budgets. This is your maintenance home for recurring planned expense logic.",
                            fullscreenCaptionText: "Use Presets management to keep recurring templates accurate and ready."
                        )
                    ]
                ),
                mediaSection(
                    id: "settings-presets-add-preset",
                    header: "Add Preset",
                    body: "Open Settings › Manage Presets and choose + (Add Preset). Pick a Card, enter the name and planned amount, and set the Schedule. Category is optional. After saving, select eligible budgets in Preset Saved and choose Add to Budget or Add to Budgets. Choose Not Now to apply the preset later. If no budget is eligible, choose Done. An eligible budget links the default card and includes a scheduled occurrence.",
                    media: [
                        mediaItem(
                            id: "settings-presets-add-preset-1",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-1",
                            bodyText: "Choose the default card, add a name and amount, and optionally pick a category.",
                            fullscreenCaptionText: "Choose the card and enter the preset details."
                        ),
                        mediaItem(
                            id: "settings-presets-add-preset-2",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-2",
                            bodyText: "Review Schedule and save. Apply the preset to eligible budgets now or attach it to a budget later.",
                            fullscreenCaptionText: "Set the schedule before saving the preset."
                        )
                    ]
                ),
                textSection(
                    id: "settings-presets-apply-or-archive",
                    header: "Apply or Archive a Preset",
                    body: "Apply a preset when you save it or from a budget’s Manage Presets screen. Offshore generates planned expenses for occurrences inside that budget’s dates when its default card is linked. Archive a preset in Manage Presets to keep it out of new selections while retaining generated history. Unlinking it from a budget has a separate effect: it removes that budget’s generated rows for the preset, including any with recorded actual amounts."
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
                            bodyText: "The Workspaces area is used to manage and switch independent budgeting contexts. Use it when you want separate histories and totals that do not overlap. Verify the active workspace before edits so records land where intended. Proper workspace use protects data boundaries and reporting clarity.",
                            fullscreenCaptionText: "Use Workspaces to keep contexts separate and prevent cross-domain data mixing."
                        )
                    ]
                ),
                textSection(
                    id: "settings-workspaces-transfer",
                    header: "Back Up or Import a Workspace",
                    body: "1. Open the workspace menu and choose Manage Workspaces. Select the workspace you want to back up.\n2. Choose Export Workspace, select the sections to include, and save the archive file.\n3. To restore or move it, open Manage Workspaces and choose + › Import Workspace. Pick the file, review Included Data and the record counts, then choose Import.\n\nThe archive opens as a new workspace with its own name. Your existing workspace stays available. For a transfer between On Device and iCloud, switch the data source and relaunch between exporting and importing."
                ),
                textSection(
                    id: "settings-workspaces-progress",
                    header: "Check or Hide Workspace Progress",
                    body: "Open Workspace Progress from Settings to see setup milestones for the current workspace, including cards, categories, presets, income, and budgets. After setup is complete, go to Settings › General › Maintenance and turn on Hide Workspace Progress to hide that row for the workspace."
                ),
                textSection(
                    id: "settings-workspaces-delete",
                    header: "Delete a Workspace",
                    body: "Open the workspace menu and choose Manage Workspaces. Deleting a workspace removes its budgets, cards, transactions, income, savings, and other workspace records. Export the workspace first if you want a copy. Offshore requires at least one workspace."
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
    private static let iPhoneOnlyQuickActionsSectionIDs: Set<String> = [
        "introduction-quick-actions-12-tap-to-pay",
        "introduction-quick-actions-13-tap-to-pay",
        "settings-quick-actions-12-tap-to-pay",
        "settings-quick-actions-13-tap-to-pay"
    ]
    private static let introductionQuickActionsNoteSectionID: String = "introduction-quick-actions-nonphone-note"
    private static let settingsQuickActionsNoteSectionID: String = "settings-quick-actions-nonphone-note"

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

    static func visibleLeafTopics(for audience: GeneratedHelpAudience = .current) -> [GeneratedHelpLeafTopic] {
        allLeafTopics.map { filteredTopic($0, for: audience) }
    }

    static func visibleLeafTopic(
        for id: String,
        audience: GeneratedHelpAudience = .current
    ) -> GeneratedHelpLeafTopic? {
        guard let topic = leafTopicsByID[id] else { return nil }
        return filteredTopic(topic, for: audience)
    }

    static func visibleLeafTopics(
        for destination: GeneratedHelpDestination,
        audience: GeneratedHelpAudience = .current
    ) -> [GeneratedHelpLeafTopic] {
        destination.leafTopicIDs.compactMap { visibleLeafTopic(for: $0, audience: audience) }
    }

    private static func filteredTopic(
        _ topic: GeneratedHelpLeafTopic,
        for audience: GeneratedHelpAudience
    ) -> GeneratedHelpLeafTopic {
        guard audience == .nonPhone else { return topic }

        var filteredSections = topic.sections.filter {
            iPhoneOnlyQuickActionsSectionIDs.contains($0.id) == false
        }

        if topic.id == "introduction-quick-actions" {
            filteredSections = insertingNonPhoneQuickActionsNote(
                into: filteredSections,
                noteSectionID: introductionQuickActionsNoteSectionID
            )
        } else if topic.id == "settings-quick-actions" {
            filteredSections = insertingNonPhoneQuickActionsNote(
                into: filteredSections,
                noteSectionID: settingsQuickActionsNoteSectionID
            )
        }

        return GeneratedHelpLeafTopic(
            id: topic.id,
            destinationID: topic.destinationID,
            resolvedTitle: topic.title,
            sections: filteredSections
        )
    }

    private static func insertingNonPhoneQuickActionsNote(
        into sections: [GeneratedHelpSection],
        noteSectionID: String
    ) -> [GeneratedHelpSection] {
        guard sections.contains(where: { $0.id == noteSectionID }) == false else { return sections }

        let noteSection = textSection(
            id: noteSectionID,
            header: "Tap To Pay Automation Availability",
            body: "Tap To Pay automation setup steps are currently available on iPhone only.\n\nOpen this help topic on iPhone to view the full step-by-step setup walkthrough."
        )

        var updatedSections = sections
        let insertIndex = min(1, updatedSections.count)
        updatedSections.insert(noteSection, at: insertIndex)
        return updatedSections
    }
}

// MARK: - Builders

private func quickActionsGuideSections(prefix: String, isSettingsVariant: Bool) -> [GeneratedHelpSection] {
    let introHeader: LocalizedStringResource = isSettingsVariant ? "Install and Use Quick Actions" : "What Quick Actions Are"
    let introBody: LocalizedStringResource
    if isSettingsVariant {
        introBody = "Quick Actions is the install hub for Offshore shortcut links and setup guidance. Use it to configure repeat tasks like income and expense capture from email or SMS, and Tap to Pay logging.\n\nShortcuts are optional. Offshore works without them, so treat automations as a convenience layer you build gradually."
    } else {
        introBody = "Quick Actions are optional Apple Shortcuts that make repeat tasks faster. Offshore works fully without them, so treat automations as a convenience layer.\n\nSome workflows can use Apple Intelligence for better names or labels, but every flow should still have a non-AI fallback so setup works on more devices."
    }

    let setupPatternBody: LocalizedStringResource = isSettingsVariant
        ? "Start with one automation for one trusted source, test it with a real message or transaction, then expand only after it behaves reliably. Keep card mapping, amount parsing, and source naming as simple as possible on the first pass.\n\nChoose Standard for broader device support. The Apple Intelligence version requires Apple Intelligence and uses it to suggest a source or merchant name."
        : "Start with one automation for one source, confirm the right variables are being passed into Offshore, then expand only after real-world testing. This keeps troubleshooting small and prevents duplicate or misparsed entries.\n\nFor shared shortcut links, assume people who already installed an older copy may need to reinstall to get later improvements."

    let deviceSetupBody: LocalizedStringResource = """
    Set up and enable the automation on the device that will receive the alert. On iPhone and iPad, open Automation in Shortcuts and tap +. On a Mac with macOS 26 or later, open the shortcut in Shortcuts and add a trigger from the Edit menu. Choose Email or Message if that trigger is available on your device.

    Set sender and subject or message filters on that device. Enable automatic running if offered. If the automation uses Run Shortcut, set its Input to Shortcut Input so the alert reaches the installed shortcut.

    Use one device per alert source. Test a matching alert and check Offshore for one entry before setting up another source.
    """

    let tapToPayHeader: LocalizedStringResource = "Add Expense via Tap to Pay"
    let tapToPayGuideHeader: LocalizedStringResource = "Add Expense via Tap to Pay Setup Guide"
    let tapToPayBody: LocalizedStringResource = "Use this workflow for Apple Wallet transaction automations. Setup is per device and works best with one automation per card. In Offshore’s Add Expense action, choose a category to apply it to each transaction. If you leave Category unset, Offshore checks the selected workspace for a learned merchant category and uses Uncategorized when there is no match.\n\nTap to Pay is configured manually in Shortcuts using Offshore’s built-in Add Expense action, so no shortcut download is required."
    let reliabilityBody: LocalizedStringResource = "Test after each automation is created. If parsing fails, recheck that the intended variables are mapped to the correct Shortcut Input details and that the installed shortcut version matches the instructions you are following.\n\nAvoid creating many near-duplicate automations up front. Start with one, verify it runs from a real message or transaction, then expand only if needed."
    let shortcutDownloadsBody: LocalizedStringResource = "Choose the version you want to install before following the setup guide."
    let incomeSetup: LocalizedStringResource = """
    1. Under Add Income, choose Standard or Apple Intelligence, then download the shortcut.
    2. Follow Set Up on Your Device above. Choose Email for deposit emails and filter by sender and subject. For SMS, choose Message and filter by sender and text such as “direct deposit.”
    3. If you are setting up the trigger in a separate shortcut, add Run Shortcut and select your Add Income download. Expand the action, set Input to Shortcut Input, and save.
    4. Test one alert, such as “Direct deposit of $250.00 was credited to your account,” and check the amount and source in Offshore. Use the comments inside the shortcut to adapt the matching pattern to your bank’s wording.
    """
    let expenseSetup: LocalizedStringResource = """
    1. Under Add Expense, choose Standard or Apple Intelligence, then download the shortcut. Open it and choose your Offshore Card in both Add Expense actions. Set a category if you want one.
    2. Follow Set Up on Your Device above. Choose Email for receipts and filter by sender and subject. For SMS, choose Message and filter by sender and text such as “Card purchase of.”
    3. If you are setting up the trigger in a separate shortcut, add Run Shortcut and select your Add Expense download. Expand the action, set Input to Shortcut Input, and save.
    4. Test a receipt or an SMS such as “Card purchase of $18.42 at Corner Market.” Check the amount and card in Offshore. Use the comments inside the shortcut to adapt the matching pattern. Receipts with multiple matching totals can create multiple expenses.
    """
    let replaceShortcutBody: LocalizedStringResource = "When replacing a downloaded shortcut, open your existing automation and change the shortcut selected in Run Shortcut. Keep Input set to Shortcut Input. Test the updated automation before removing the old shortcut."

    let tapToPaySteps: [LocalizedStringResource] = [
        "Open the Shortcuts app and go to the Automations tab. Tap the plus button to create a new automation.",
        "On this screen, choose the Wallet trigger.",
        "For best results, set up one automation per Apple Wallet card. By default, all cards are selected, so deselect every card except the one you want to use for this automation. It is also recommended to leave all categories selected. You can filter merchants if you want, but the safest default is to leave them unchanged. Make sure Run Immediately is selected instead of Run After Confirmation.",
        "On the next screen, under Get Started, tap Create New Shortcut.",
        "Search the Actions list for Add Expense. This action is built into Offshore, so there is nothing to download first. To extract the Amount, Wallet Card, Merchant, and Date, you will need to configure the form.",
        "Tap the Amount field, choose Select Variable, then choose Shortcut Input. Once Shortcut Input appears in the field, tap it so the data is passed into the Amount field. Then change the Type from Transaction to Amount and tap Return.",
        "Choose the Offshore card these Tap to Pay expenses should be attached to.",
        "Repeat the same setup for the Wallet Card field. Tap the field, choose Select Variable, then choose Shortcut Input. Once Shortcut Input appears in the field, tap it and change the Type from Transaction to Card or Pass. Then tap Return.",
        "Repeat the same setup for Merchant. Tap the field, choose Select Variable, then choose Shortcut Input. Once Shortcut Input appears in the field, tap it and change the Type from Transaction to Merchant. Then tap Return.",
        "To use the current date, tap the Date field and scroll until you find Current Date. For best results, set Date Format to Medium and Time Format to None. Once Current Date looks correct, tap Return.",
        "Choose a category to apply every time, or leave Category unset to use a learned merchant category when available. Turn off Show When Run, then tap Save."
    ]

    return [
        textSection(
            id: "\(prefix)-1",
            header: introHeader,
            body: introBody
        ),
        textSection(
            id: "\(prefix)-2",
            header: "Recommended Setup Pattern",
            body: setupPatternBody
        ),
        textSection(
            id: "\(prefix)-device-setup",
            header: "Set Up on Your Device",
            body: deviceSetupBody
        ),
        textSection(
            id: "\(prefix)-3-income",
            header: "Add Income from Email or SMS",
            body: incomeSetup
        ),
        quickActionsWorkflowLinksSection(
            prefix: prefix,
            sectionNumber: 4,
            workflowSlug: "income",
            header: "Download Add Income",
            body: shortcutDownloadsBody,
            workflowID: "income"
        ),
        textSection(
            id: "\(prefix)-9-expense",
            header: "Add Expense from Email or SMS",
            body: expenseSetup
        ),
        quickActionsWorkflowLinksSection(
            prefix: prefix,
            sectionNumber: 10,
            workflowSlug: "expense",
            header: "Download Add Expense",
            body: shortcutDownloadsBody,
            workflowID: "expense"
        ),
        textSection(
            id: "\(prefix)-11-replace-shortcut",
            header: "Replace an Installed Shortcut",
            body: replaceShortcutBody
        ),
        quickActionsWorkflowTextSection(
            prefix: prefix,
            sectionNumber: 12,
            workflowSlug: "tap-to-pay",
            header: tapToPayHeader,
            body: tapToPayBody
        ),
        quickActionsWorkflowMediaSection(
            prefix: prefix,
            sectionNumber: 13,
            workflowSlug: "tap-to-pay",
            header: tapToPayGuideHeader,
            assetPrefix: "tap-to-pay",
            steps: tapToPaySteps
        ),
        textSection(
            id: "\(prefix)-built-in-actions",
            header: "Built-in Offshore Shortcut Actions",
            body: "In Apple Shortcuts, search for Offshore to find Add Expense, Add Income, Review Today, Safe Spend Today, Forecast Savings, and, on supported devices, Excursion Mode. Add Expense and Add Income use Offshore’s selected workspace. Offshore also offers Import Screenshot and Import From Clipboard to review what was recognized before saving."
        ),
        textSection(
            id: "\(prefix)-14",
            header: "Reliability Tips",
            body: reliabilityBody
        )
    ]
}

private func quickActionsWorkflowTextSection(
    prefix: String,
    sectionNumber: Int,
    workflowSlug: String,
    header: LocalizedStringResource,
    body: LocalizedStringResource
) -> GeneratedHelpSection {
    textSection(
        id: "\(prefix)-\(sectionNumber)-\(workflowSlug)",
        header: header,
        body: body
    )
}

private func quickActionsWorkflowMediaSection(
    prefix: String,
    sectionNumber: Int,
    workflowSlug: String,
    header: LocalizedStringResource,
    assetPrefix: String,
    steps: [LocalizedStringResource]
) -> GeneratedHelpSection {
    let body: LocalizedStringResource = "Follow each step in order, then compare it to the matching screenshot in this guide."
    return mediaSection(
        id: "\(prefix)-\(sectionNumber)-\(workflowSlug)",
        header: header,
        body: body,
        media: quickActionsMediaItems(
            prefix: "\(prefix)-\(sectionNumber)-\(workflowSlug)",
            assetPrefix: assetPrefix,
            steps: steps
        )
    )
}

private func quickActionsWorkflowLinksSection(
    prefix: String,
    sectionNumber: Int,
    workflowSlug: String,
    header: LocalizedStringResource,
    body: LocalizedStringResource,
    workflowID: String
) -> GeneratedHelpSection {
    let group = ShortcutLinkCatalog.installGroups.first(where: { $0.id == workflowID })

    return linkSection(
        id: "\(prefix)-\(sectionNumber)-\(workflowSlug)",
        header: header,
        body: body,
        links: group.map(helpLinkItems(for:)) ?? []
    )
}

private func quickActionsMediaItems(
    prefix: String,
    assetPrefix: String,
    steps: [LocalizedStringResource]
) -> [GeneratedHelpSectionMediaItem] {
    steps.enumerated().map { index, step in
        let stepNumber = index + 1
        let assetName = "Help/CoreScreens/Settings/Quick Actions/\(assetPrefix)-\(stepNumber)"
        let resolvedStep = String(localized: step)
        let caption = String(
            format: String(localized: "Step %@: %@", defaultValue: "Step %@: %@", comment: "Fullscreen caption for quick-actions help screenshots."),
            locale: Locale.current,
            stepNumber.formatted(.number),
            resolvedStep
        )

        return mediaItem(
            id: "\(prefix)-image-\(stepNumber)",
            assetName: assetName,
            resolvedBodyText: resolvedStep,
            resolvedFullscreenCaptionText: caption
        )
    }
}

private func textSection(id: String, header: LocalizedStringResource?, body: LocalizedStringResource) -> GeneratedHelpSection {
    GeneratedHelpSection(
        id: id,
        header: header,
        bodyText: body,
        mediaItems: [],
        linkItems: []
    )
}

private func mediaSection(
    id: String,
    header: LocalizedStringResource?,
    body: LocalizedStringResource,
    media: [GeneratedHelpSectionMediaItem]
) -> GeneratedHelpSection {
    GeneratedHelpSection(
        id: id,
        header: header,
        bodyText: body,
        mediaItems: media,
        linkItems: []
    )
}

private func linkSection(
    id: String,
    header: LocalizedStringResource?,
    body: LocalizedStringResource,
    links: [GeneratedHelpSectionLinkItem]
) -> GeneratedHelpSection {
    GeneratedHelpSection(
        id: id,
        header: header,
        bodyText: body,
        mediaItems: [],
        linkItems: links
    )
}

private func mediaItem(
    id: String,
    assetName: String,
    displayTitle: LocalizedStringResource? = nil,
    bodyText: LocalizedStringResource,
    fullscreenCaptionText: LocalizedStringResource? = nil
) -> GeneratedHelpSectionMediaItem {
    GeneratedHelpSectionMediaItem(
        id: id,
        assetName: assetName,
        displayTitle: displayTitle,
        bodyText: bodyText,
        fullscreenCaptionText: fullscreenCaptionText
    )
}

private func mediaItem(
    id: String,
    assetName: String,
    resolvedDisplayTitle: String? = nil,
    resolvedBodyText: String,
    resolvedFullscreenCaptionText: String? = nil
) -> GeneratedHelpSectionMediaItem {
    GeneratedHelpSectionMediaItem(
        id: id,
        assetName: assetName,
        resolvedDisplayTitle: resolvedDisplayTitle,
        resolvedBodyText: resolvedBodyText,
        resolvedFullscreenCaptionText: resolvedFullscreenCaptionText
    )
}

private func helpLinkItems(for group: ShortcutLinkGroup) -> [GeneratedHelpSectionLinkItem] {
    group.variants.map { variant in
        GeneratedHelpSectionLinkItem(
            id: "\(group.id)-\(variant.id)",
            title: variant.title,
            subtitle: variant.subtitle,
            systemImageName: "square.and.arrow.down",
            url: variant.url,
            accessoryText: variant.requirementLabel
        )
    }
}
