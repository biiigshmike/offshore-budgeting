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
    let displayTitle: String?
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
        faqSearchText
    }

    var faqSearchText: String {
        var parts: [String] = [title]

        for section in sections {
            if let header = section.header {
                parts.append(header)
            }

            parts.append(section.bodyText)
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
                    body: "Offshore is organized into core functions that work together instead of competing for your attention. Accounts includes Cards, Reconciliations, and a dedicated workspace Savings Account. Income is split into planned and actual inflows, while Budgets gives you the lens that compares what you expected against what really happened.\n\nEach area has one clear job so you always know where to go, where money is being spent, what income is expected, what income has landed, and what your savings direction looks like in the current period. Settings supports all of this with defaults and tools like Categories, Presets, and workspace-level behavior. Once these building blocks click, every other screen feels much more natural."
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
                    header: "Where To Add Them",
                    body: "Add planned expenses from the budget period you are actively managing so totals remain scoped to the right cycle. Staying inside the correct period avoids silent crossover issues that can make math look wrong later.\n\nFor recurring items, use presets whenever possible. Presets speed up setup, reduce manual mistakes, and keep naming and category behavior consistent from one period to the next."
                ),
                textSection(
                    id: "introduction-planned-expenses-3",
                    header: "How To Use Them Day To Day",
                    body: "Add planned expenses early in the period so your numbers start from a realistic baseline. As real charges happen, compare those charges to the plan and keep records updated.\n\nIf the final amount changes, record the actual outcome and let planned-versus-actual do its job. That keeps your budget alive and useful instead of turning into a static list that no longer reflects reality."
                ),
                textSection(
                    id: "introduction-planned-expenses-4",
                    header: "Verify They Are Working",
                    body: "Before heavy day-to-day tracking begins, confirm your planned totals look right in the active budget. This gives you a stable reference point for the rest of the period.\n\nAs actual entries come in, verify that comparisons still make sense and are highlighting true differences. Good verification here gives you early warning when spending starts drifting from your original plan."
                ),
                textSection(
                    id: "introduction-planned-expenses-5",
                    header: "Planned Expense Pitfalls",
                    body: "Avoid duplicating recurring bills across presets and manual entries, because duplicates can quietly overstate your period. If a planned amount changes often, update the preset source so future cycles stay accurate.\n\nKeep category mapping and naming consistent. When labels drift, reviews get noisy and it becomes harder to spot real behavior changes."
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
                    body: "Variable expenses are flexible or less predictable purchases that happen in real time during the period. These are usually your day-to-day categories, like dining, fuel, shopping, entertainment, and one-off needs.\n\nUnlike planned expenses, variable entries describe what already happened. They are your lived spending behavior, and they give the most honest signal about where your budget pressure is building."
                ),
                textSection(
                    id: "introduction-variable-expenses-2",
                    header: "Where To Record Them",
                    body: "Record variable expenses in the active budget context so entries land in the correct period and comparisons stay meaningful. Keeping the right context from the start prevents avoidable cleanup work.\n\nAssign category, amount, date, and account details with care. Clean entry data now directly improves every filter, report, and trend you rely on later."
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
                    body: "Enter planned income in Income for the same timeframe as your active budget period. Keep each source clearly labeled so you can quickly distinguish predictable pay from irregular inflows.\n\nClear naming now makes planned-versus-actual review much easier later. It also helps you identify which income source changed when a variance appears."
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
                    body: "Record actual income in Income using the flow that matches how you track deposits. Capture accurate amount and date so the entry lands in the right period and comparisons stay trustworthy.\n\nTimely recording matters. The faster you log landed income, the more reliable Home and budget guidance becomes."
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
                    body: "Avoid overlapping periods unless you intentionally want separate parallel contexts. Overlap can make it harder to explain which cycle owns a given result.\n\nAlso avoid changing date ranges mid-cycle without reviewing impacted totals. Stable ranges produce cleaner history and clearer trend comparisons."
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
                    header: "Where To Start Import",
                    body: "Start import from the screen that owns the records you want to create. This keeps destination context clear and reduces mapping confusion.\n\nBefore importing, confirm the target period so records land in the correct cycle. That one check prevents a lot of cleanup later."
                ),
                textSection(
                    id: "introduction-import-3",
                    header: "How To Review Records",
                    body: "During review, check names, amounts, dates, and categories before committing. Resolve likely duplicates and fill missing required details while you are still in the review step.\n\nTaking an extra minute here is usually faster than fixing a full batch after save. Clean imports protect every report that depends on them."
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
            sections: [
                textSection(
                    id: "introduction-quick-actions-1",
                    header: "What Quick Actions Are",
                    body: "Quick Actions are optional Apple Shortcuts that speed up repeat workflows like logging income or expenses from triggers you already see every day. They reduce taps, improve consistency, and make capture feel less manual.\n\nOffshore still works fully without automations, so this is an efficiency layer, not a requirement. If you want to scale your setup over time, start with one or two automations and add the rest after they are working reliably."
                ),
                textSection(
                    id: "introduction-quick-actions-2",
                    header: "Where To Set Them Up",
                    body: "Open Quick Actions in Settings to install each Offshore shortcut first. Then open Apple Shortcuts and create a personal automation that runs the matching Offshore shortcut.\n\nFor each automation, the core mapping step is the same after you choose \"Run Shortcut\": press the Down Arrow, set Input to Choose Variable, then choose Shortcut Input. This makes sure trigger text gets passed into the Offshore shortcut correctly."
                ),
                textSection(
                    id: "introduction-quick-actions-3",
                    header: "How To Use Them Safely",
                    body: "Use these literal trigger setups once the matching shortcuts are installed:\n\nExpense automations:\n\n1. Add Expense From Tap To Pay\nTrigger: When I tap any Wallet pass or payment card.\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Expense From Tap To Pay\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\n2. Add Amazon Expense From Amazon.com\nTrigger: When I get an email with subject containing \"Ordered:\" from auto-confirm@amazon.com.\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Amazon Expense From Amazon.com\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\nIncome automations:\n\n3. Add Income From An Email\nTrigger: When I get an email with subject containing \"credited to your account\".\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Income From An Email\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\n4. Add Income From An SMS Message\nTrigger: When message contains \"credited to your account ending in x1234\".\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Income From An SMS Message\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save."
                ),
                textSection(
                    id: "introduction-quick-actions-4",
                    header: "Verify Reliability",
                    body: "After setup, test each automation once with realistic input and verify the created record in Offshore immediately. Confirm destination, amount parsing, and category behavior before you trust daily usage.\n\nIf one automation fails, simplify and retest that single flow before changing others. Reliable automation should feel boring and predictable once it is configured correctly."
                ),
                textSection(
                    id: "introduction-quick-actions-5",
                    header: "Quick Action Pitfalls",
                    body: "Avoid changing multiple trigger rules at the same time before each one is proven. Most issues come from input mapping or trigger text mismatch, not from Offshore itself.\n\nYou can customize trigger phrases later, but keep the text format consistent with what your shortcut expects so parsing stays stable. Make one change at a time, retest, and then continue.\n\nIf you are using iCloud Sync, only enable automations on one of your devices to avoid automating adding duplicate entries."
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
                    body: "Excursion Mode is a focused tracking mode for high-activity windows when transactions are happening quickly. It prioritizes fast capture so you can stay present while still logging spending accurately.\n\nUse it when real-time awareness matters more than deep entry detail in the moment."
                ),
                textSection(
                    id: "introduction-excursion-mode-2",
                    header: "When To Use It",
                    body: "Use Excursion Mode during travel, outings, event days, or any period with many small transactions. It is especially helpful when waiting until later would cause details to be forgotten.\n\nShort bursts of consistent capture can dramatically improve data quality and reduce end-of-day guesswork."
                ),
                textSection(
                    id: "introduction-excursion-mode-3",
                    header: "How To Work In It",
                    body: "Capture each transaction quickly, then return later for deeper cleanup if needed, such as notes or category refinement. Keep the process simple so you keep momentum.\n\nThe goal in this mode is completeness first, refinement second. A complete draft record is better than a missing one."
                ),
                textSection(
                    id: "introduction-excursion-mode-4",
                    header: "Verify After A Session",
                    body: "When the high-activity window ends, do a short closeout review. Confirm totals align with what you expected and fix obvious mislabels while memory is still fresh.\n\nThis quick wrap-up step keeps excursion sessions accurate and prevents cleanup from piling up later."
                ),
                textSection(
                    id: "introduction-excursion-mode-5",
                    header: "Excursion Mode Pitfalls",
                    body: "Avoid over-editing entries in the moment, because that usually leads to skipped capture. Focus on fast capture first.\n\nAlso avoid skipping the post-session review. Fast entry is great for speed, but the short cleanup pass is what locks in long-term accuracy."
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
                    body: "Home customization lets you decide which insights appear first so your most important decisions require fewer taps. A strong layout reduces scrolling and keeps critical widgets visible when you are moving quickly. This is especially useful if your priorities change during different parts of the month.\n\nTreat customization as a workflow tool, not just a visual preference. Put frequently checked widgets near the top and move low-priority items lower. Revisit your layout after a few cycles to ensure it still matches how you actually review the app.\n\nAfter reordering, run one normal daily check-in to validate that the sequence feels natural. Small changes in order can significantly improve consistency. A layout that matches your routine helps you catch problems earlier.",
                    media: [
                        mediaItem(
                            id: "home-customization-edit-home-1",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-1",
                            bodyText: "This first step walks you into edit mode from Home customization. Use this point to decide which tiles belong in your top view versus lower priority positions. If you are unsure, place your most decision-driving widgets first, such as income reliability or savings trend signals. Starting with intention makes later ordering changes simpler.",
                            fullscreenCaptionText: "Enter edit mode to begin arranging the Home widgets around your priorities."
                        ),
                        mediaItem(
                            id: "home-customization-edit-home-2",
                            assetName: "Help/CoreScreens/Home/Customization/edit-home-2",
                            bodyText: "This step shows you how to reorder widgets into the sequence you want for quick daily checks. Drag high-impact tiles toward the top so important shifts are visible immediately. Keep related widgets near each other when possible so context is easier to read. A practical order reduces friction and improves follow-through.",
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
                    body: "Marina is your conversational helper for turning raw numbers into clear next steps. Ask focused questions about a period, category, card, or savings direction to get practical guidance quickly.\n\nMarina also pairs well with your create, update, and cleanup workflow. Use the + button on the owning screen when you need to add a new record, then use edit or delete actions in that same screen to finish cleanup. Marina helps you decide what to do, and the destination screens help you do it accurately.\n\nA strong routine is simple: ask one question, take one action, then verify the result. This keeps guidance actionable and prevents overload.",
                    media: [
                        mediaItem(
                            id: "home-marina-1-image-1",
                            assetName: "Help/CoreScreens/Home/Marina/marina",
                            bodyText: "Marina is opened from Home for a conversational review flow. Ask concise prompts about trends, savings direction, or variance, then open the related screen to take action. When you need to add something new, use the + button in that screen. For changes later, use edit and delete there as well so your records stay clean and traceable.",
                            fullscreenCaptionText: "Ask Marina for guidance, then use +, edit, or delete in the owning screen to complete the workflow."
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
                    header: "Widgets",
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
                    body: "Creating a budget establishes the date window used for totals, comparisons, and savings outcomes in that cycle. This step defines the frame every entry depends on, so clarity here matters.\n\nThe title field is dynamic and can self-generate based on your period setup. You can keep that generated title or enter your own custom title if you want tighter naming control.\n\nAfter creation, move directly into assigning structure and adding initial planned entries. Early setup quality improves every downstream decision.",
                    media: [
                        mediaItem(
                            id: "budgets-overview-create-budget-1",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-1",
                            bodyText: "Start a new budget period from the add flow. The title can auto-fill based on your period details, and you can override it with your own name at any time before saving. Choose a date range that matches your review rhythm so planned income and recurring expenses align cleanly.",
                            fullscreenCaptionText: "Start the budget, keep the generated title or enter your own, then confirm dates."
                        ),
                        mediaItem(
                            id: "budgets-overview-create-budget-2",
                            assetName: "Help/CoreScreens/Budgets/Overview/create-budget-2",
                            bodyText: "This step walks through reviewing and confirming budget setup details before saving. Verify the period boundaries and core settings now so you do not need cleanup edits after entries are added. Once saved, continue directly into cards, planned expenses, and other setup tasks. A short confirmation pass here saves significant correction time later.",
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
                    body: "Budget Details is where period execution happens day by day. This is where you add, edit, and monitor expenses while keeping planned and variable behavior in sync.\n\nWhen adding an expense, you can also use split and offset controls when one purchase needs more than one treatment. Split helps you break a single charge into multiple tracked parts, while offset helps you intentionally reduce the balance impact when another source is covering all or part of that cost.\n\nAfter each meaningful change, scan summary signals to confirm direction. Small, consistent updates make budget control much easier than large delayed corrections.",
                    media: [
                        mediaItem(
                            id: "budgets-details-add-expense-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-1",
                            bodyText: "This step opens the add expense flow from Budget Details. Choose the correct expense type first so the entry contributes to calculations in the right way. Planned and variable entries serve different purposes, so classification is important. Starting with the right type prevents avoidable reporting confusion.",
                            fullscreenCaptionText: "Start add expense from Budget Details and choose the correct expense type first."
                        ),
                        mediaItem(
                            id: "budgets-details-add-expense-2",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/add-expense-2",
                            bodyText: "This step completes amount, date, card, and category, and it is where split and offset are applied when needed. Use split when one transaction should be tracked across multiple purposes, and use offset when another source should reduce part of the balance impact. Verify totals right after save so you can confirm the split or offset behaved the way you expected.",
                            fullscreenCaptionText: "Complete fields, apply split or offset if needed, then verify totals after save."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-details-filter-expenses",
                    header: "Filter Expenses",
                    body: "Filtering lets you isolate the exact slice of spending you need to evaluate before making changes. Use this to narrow by category, card, or other scope controls when totals need explanation. Focused views reduce noise and shorten investigation time.\n\nA good sequence is filter first, inspect entries second, then decide action. This keeps decisions tied to evidence instead of intuition. Clear filtered views are especially useful when spending accelerates unexpectedly.\n\nReset filters after analysis so future reviews begin from full context. That habit avoids accidental conclusions from stale scopes. Filtering is most powerful when used intentionally and reset consistently.",
                    media: [
                        mediaItem(
                            id: "budgets-details-filter-expenses-1",
                            assetName: "Help/CoreScreens/Budgets/Budget Details/filter-expenses",
                            bodyText: "Filters are applied to narrow the visible expense set. Use this when troubleshooting one category, one card, or one timeframe instead of scanning the full ledger. A focused result set makes it easier to identify the entries driving pressure. Confirm conclusions, then reset filters before moving on.",
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
                    body: "Calculations summarize how income and expenses combine into period outcomes. When a number looks off, first check whether values are hidden or excluded before assuming the math is wrong.\n\nThe eye control changes visibility and can make totals look different from what you expected if some values are currently hidden. Always confirm visibility state before comparing screens.\n\nYou can set default visibility behavior in Settings > General > Expense Display, then use the eye control for quick per-view adjustments.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-overview-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/overview",
                            bodyText: "The overview shows top-level budget math in one place, including controls that affect what is visible. If totals look unusual, check the eye state first to confirm no values are hidden or excluded. This quick check prevents unnecessary troubleshooting.",
                            fullscreenCaptionText: "Check eye visibility first when totals look off."
                        )
                    ]
                ),
                mediaSection(
                    id: "budgets-calculations-details",
                    header: "Calculation Details",
                    body: "Calculation Details is where you confirm why a total changed. Use it after checking visibility controls so you know whether the value changed because of data or because items are hidden.\n\nIf numbers still look wrong, trace by entry type and recent edits. This is usually enough to find the exact source quickly.\n\nFor consistent behavior across sessions, review Settings > General > Expense Display and choose defaults that match how you like to review expense math.",
                    media: [
                        mediaItem(
                            id: "budgets-calculations-details-image-1",
                            assetName: "Help/CoreScreens/Budgets/Calculations/calculations",
                            bodyText: "The detail view breaks down the numbers behind budget outcomes. If something seems inconsistent, verify hidden or excluded values first, then trace the remaining difference to entry type, timing, and recent edits. This keeps debugging focused and fast.",
                            fullscreenCaptionText: "Use details after visibility checks to trace the exact source of a mismatch."
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
                    body: "Accounts is the hub for card activity, shared-balance reconciliation, and savings tracking. It helps you separate normal spending workflows from settlement and reserve workflows so your data stays organized.\n\nUse the three colored toggle buttons at the top to move between Cards, Reconciliations, and Savings quickly. Think of them as fast container switches so you can jump directly to the area that owns the task.\n\nA quick review pass in Accounts each cycle keeps card-level accuracy strong and improves related reports across the app.",
                    media: [
                        mediaItem(
                            id: "accounts-overview-1-image-1",
                            assetName: "Help/CoreScreens/Accounts/Overview/overview",
                            bodyText: "Accounts is the launch point for Cards, Reconciliations, and Savings workflows. Use the card, person, and cash toggle buttons to switch containers and start in the right place for the job. Container-first navigation keeps edits easier to validate and reduces accidental cross-workflow changes.",
                            fullscreenCaptionText: "Use the top toggles to switch between Cards, Reconciliations, and Savings."
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
                    body: "Card import helps you add multiple transactions quickly when manual entry would be slow. Offshore supports CSV, PDF, and image imports from this flow.\n\nIf you use the mapping memory toggle, Offshore can reuse similar import structure later so repeat imports are faster. It is a good option when your source format is consistent.\n\nFriendly warning: avoid importing card payment transfers as expenses. Offshore is built to help you understand spending and savings direction, and importing payments as expenses can create confusing or inflated math. Keep imports focused on true spending or income activity.",
                    media: [
                        mediaItem(
                            id: "accounts-card-details-import-expenses-image-1",
                            assetName: "Help/CoreScreens/Accounts/Card Details/import-expenses",
                            bodyText: "This step starts a card-scoped import flow for bulk transaction capture from CSV, PDF, or images. Review parsed rows for duplicates and category accuracy, and use the mapping memory toggle when you want faster repeat imports from similar files. Skip payment-transfer rows that are not true expenses so totals stay clean.",
                            fullscreenCaptionText: "Import CSV/PDF/image records, use mapping memory for repeats, and avoid payment-transfer expense rows."
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
                    body: "Settlements are the entries that reduce or clear shared balances over time. Use this flow any time money is paid back, collected, or otherwise resolves a reconciliation amount. Recording settlements promptly keeps the ledger honest and current.\n\nDirection and amount accuracy matter because they determine whether balances move toward zero correctly. Include brief notes so future you can understand why each movement occurred. Clear settlement records prevent timeline confusion later.\n\nAfter saving, verify updated balance direction in detail view. This quick check catches sign mistakes immediately. Reliable settlement entry is key to trustworthy shared-balance tracking.",
                    media: [
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-1",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-1",
                            bodyText: "This first step opens reconciliation detail and starts a settlement entry. Choose settlement direction carefully so the balance moves as intended. Direction mistakes can invert progress and create confusion in later review. Confirm the sign before continuing.",
                            fullscreenCaptionText: "Start a settlement from reconciliation detail and confirm the balance direction."
                        ),
                        mediaItem(
                            id: "accounts-reconciliations-add-settlement-2",
                            assetName: "Help/CoreScreens/Accounts/Reconciliations/add-settlement-2",
                            bodyText: "This step confirms settlement amount and notes before committing the entry. Add a concise reason so future reviews clearly explain the balance change. Good notes are especially valuable when multiple people or events affect one ledger. Save only after amount, direction, and context are all clear.",
                            fullscreenCaptionText: "Confirm amount and add a short note so settlement history stays clear."
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
                    body: "Savings Account provides a dedicated ledger and trend view for money set aside outside normal card spending. It is especially useful when you want saved funds to offset future purchases without losing expense ownership on the card that made the purchase.\n\nA practical pattern is: save money during one period, keep a later purchase on the correct card, then use Savings activity to offset the balance impact intentionally. This keeps card history accurate while showing how savings supported the purchase.\n\nAfter each savings update, verify both ledgers moved as expected. This keeps your reserve history trustworthy and your card math clean.",
                    media: [
                        mediaItem(
                            id: "accounts-savings-account-overview-image-1",
                            assetName: "Help/CoreScreens/Accounts/Savings Account/overview",
                            bodyText: "The Savings Account ledger shows contributions, withdrawals, and trend context in one view. Use it when you are offsetting a future card purchase with saved funds so the card still owns the expense while savings absorbs part of the impact. After posting, verify the card and savings records both reflect your intent.",
                            fullscreenCaptionText: "Use Savings to offset future card purchases while keeping expense ownership on the card."
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
                    body: "Privacy in Offshore is primarily a visibility and status view for permissions the system controls. Use it to review what Offshore currently has access to, then open iOS App Settings if you want to change those permissions.\n\nA good workflow is: review status here, open App Settings for permission changes, then return and verify expected behavior. This keeps permission changes intentional and easy to confirm.\n\nCore Offshore budgeting functions work fully offline. Network-dependent features are optional, so your core workflow remains available even without connectivity.",
                    media: [
                        mediaItem(
                            id: "settings-privacy-1-image-1",
                            assetName: "Help/CoreScreens/Settings/Privacy/overview",
                            bodyText: "This screen shows Offshore permission status and privacy-related controls. Use it as your checkpoint, then open App Settings to modify permissions when needed. After changes, run a quick verification pass to confirm expected behavior. Core budgeting features continue to work offline.",
                            fullscreenCaptionText: "Review permission status here, manage changes in App Settings, and keep in mind core features work offline."
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
                            bodyText: "Notification settings control reminder types and schedule timing. Enable only the reminders that directly improve your daily workflow. Then validate delivery timing against when you can actually review or log data. Focused reminder design increases consistency and lowers noise.",
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
                            bodyText: "iCloud sync status and related controls are shown here for cross-device behavior. Use this to confirm that recent edits are propagating correctly across your devices. If something appears stale, verify sync health here before changing records elsewhere. Sync-first troubleshooting prevents avoidable data confusion.",
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
                    body: "Quick Actions is your install hub for all Offshore shortcuts and automation links. Install the shortcuts first, then build automations in Apple Shortcuts using the steps below.\n\nExpense automations:\n\n1. Add Expense From Tap To Pay\nTrigger: When I tap any Wallet pass or payment card.\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Expense From Tap To Pay\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\n2. Add Amazon Expense From Amazon.com\nTrigger: When I get an email with subject containing \"Ordered:\" from auto-confirm@amazon.com.\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Amazon Expense From Amazon.com\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\nIncome automations:\n\n3. Add Income From An Email\nTrigger: When I get an email with subject containing \"credited to your account\".\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Income From An Email\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\n4. Add Income From An SMS Message\nTrigger: When message contains \"credited to your account ending in x1234\".\nSetup:\n- Run Immediately.\n- Create New Shortcut.\n- Search for \"Run Shortcut\".\n- Choose \"Add Income From An SMS Message\".\n- Press the Down Arrow.\n- Set Input to Choose Variable.\n- Choose \"Shortcut Input\".\n- Save.\n\nFriendly note: You can customize trigger phrases later, but keep the input format consistent with what each shortcut expects and retest after every change."
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
                    body: "Adding a preset converts a recurring planned expense into a reusable template for future cycles. This improves setup speed while preserving consistency in naming and category assignment. Create presets for items that repeat with similar structure.\n\nDuring creation, prioritize accurate default values and practical names. Better defaults mean fewer edits each cycle. Template quality directly determines reuse quality.\n\nBefore final save, run a quick review of amount, category, and label clarity. A clean preset now avoids repeated correction later. Strong preset creation compounds over time.",
                    media: [
                        mediaItem(
                            id: "settings-presets-add-preset-1",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-1",
                            bodyText: "This first step fills in core preset fields such as name, amount, and category. Choose defaults that match normal recurring behavior so reuse requires minimal edits. Clear naming helps you select the right preset quickly during budget setup. Strong defaults create repeatable efficiency.",
                            fullscreenCaptionText: "Define clear preset defaults so recurring setup needs minimal editing later."
                        ),
                        mediaItem(
                            id: "settings-presets-add-preset-2",
                            assetName: "Help/CoreScreens/Settings/Presets/add-preset-2",
                            bodyText: "This step reviews preset details before saving the template. Confirm amount and category mapping now so future budgets inherit reliable defaults. A careful review here prevents repeated cycle-by-cycle fixes. Save only after template intent is clear.",
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
                            bodyText: "The Workspaces area is used to manage and switch independent budgeting contexts. Use it when you want separate histories and totals that do not overlap. Verify the active workspace before edits so records land where intended. Proper workspace use protects data boundaries and reporting clarity.",
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
    displayTitle: String? = nil,
    bodyText: String,
    fullscreenCaptionText: String? = nil
) -> GeneratedHelpSectionMediaItem {
    GeneratedHelpSectionMediaItem(
        id: id,
        assetName: assetName,
        displayTitle: displayTitle,
        bodyText: bodyText,
        fullscreenCaptionText: fullscreenCaptionText
    )
}
