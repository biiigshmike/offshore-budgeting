//
//  GeneratedHelpContent.swift
//  OffshoreBudgeting
//
//  In-app help content source for Offshore.
//  Maintained directly in this file.
//

import Foundation

enum GeneratedHelpTopicGroup: String {
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

struct GeneratedHelpSection: Identifiable, Hashable {
    let id: String
    let header: String?
    let lines: [GeneratedHelpLine]
}

struct GeneratedHelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let group: GeneratedHelpTopicGroup
    let iconSystemName: String
    let iconStyle: GeneratedHelpIconStyle
    let sections: [GeneratedHelpSection]
    let searchableText: String
}

enum GeneratedHelpContent {
    static let bookTitle: String = "Offshore Help"
    static let bookIdentifier: String = "com.mb.offshore.help"

    static let topics: [GeneratedHelpTopic] = [
        GeneratedHelpTopic(
            id: "introduction",
            title: "Introduction",
            group: .gettingStarted,
            iconSystemName: "exclamationmark.bubble",
            iconStyle: .blue,
            sections: [
                GeneratedHelpSection(
                    id: "introduction-1",
                    header: nil,
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Welcome to Offshore Budgeting, a privacy-first budgeting app. All data is processed on your device, and you will never be asked to connect a bank account. This guide introduces the core building blocks and explains exactly how totals are calculated across the app."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-2",
                    header: "The Building Blocks",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Cards, Income, Expense Categories, Presets, and Budgets are the foundation:"),
                        GeneratedHelpLine(kind: .bullet, value: "Cards hold your expenses and let you analyze spending by card."),
                        GeneratedHelpLine(kind: .bullet, value: "Income is tracked as planned or actual. Planned income helps you forecast savings, while actual income powers real savings calculations."),
                        GeneratedHelpLine(kind: .bullet, value: "Expense Categories describe what an expense was for, like groceries, rent, or fuel."),
                        GeneratedHelpLine(kind: .bullet, value: "Presets are reusable planned expenses for recurring bills."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable expenses are one-off or unpredictable expenses tied to a card."),
                        GeneratedHelpLine(kind: .bullet, value: "Budgets group a date range so the app can summarize income, expenses, and savings for that period."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-3",
                    header: "Planned Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Expected or recurring costs for a budget period, like rent or subscriptions."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned Amount: the amount you expect to debit from your account."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Amount: if a planned expense costs more or less than expected, edit the planned expense and enter the actual amount."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-4",
                    header: "Variable Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Unpredictable, one-off costs during a budget period, like fuel or dining. These are always treated as actual spending and are tracked by card and category."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-5",
                    header: "Planned Income",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Income you expect to receive, like salary or deposits. Planned income is used for forecasts and potential savings."),
                        GeneratedHelpLine(kind: .bullet, value: "Use planned income to help plan your budget. If income is very consistent, consider recurring actual income instead."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-6",
                    header: "Actual Income",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Income you actually receive. Actual income drives real totals, real savings, and the amount you can still spend safely."),
                        GeneratedHelpLine(kind: .bullet, value: "Income can be logged as actual when received, or set as recurring actual income for consistent paychecks."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-7",
                    header: "Budgets",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Budgets are a lens for viewing your income and expenses over a specific date range. Create budgets that align with your financial goals and pay cycles."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "introduction-8",
                    header: "How Totals Are Calculated",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Everything in Offshore is basic math:"),
                        GeneratedHelpLine(kind: .bullet, value: "Planned expenses total = sum of planned amounts for planned expenses in the budget period."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual planned expenses total = sum of actual amounts for those planned expenses."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable expenses total = sum of variable expenses in the budget period."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned income total = sum of income entries marked Planned in the period."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual income total = sum of income entries marked Actual in the period."),
                        GeneratedHelpLine(kind: .bullet, value: "Potential savings = planned income total - planned expenses planned total."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual savings = actual income total - (planned expenses actual total + variable expenses total)."),
                    ]
                )
            ],
            searchableText: "Introduction Welcome to Offshore Budgeting, a privacy-first budgeting app. All data is processed on your device, and you will never be asked to connect a bank account. This guide introduces the core building blocks and explains exactly how totals are calculated across the app. The Building Blocks Cards, Income, Expense Categories, Presets, and Budgets are the foundation: Cards hold your expenses and let you analyze spending by card. Income is tracked as planned or actual. Planned income helps you forecast savings, while actual income powers real savings calculations. Expense Categories describe what an expense was for, like groceries, rent, or fuel. Presets are reusable planned expenses for recurring bills. Variable expenses are one-off or unpredictable expenses tied to a card. Budgets group a date range so the app can summarize income, expenses, and savings for that period. Planned Expenses Expected or recurring costs for a budget period, like rent or subscriptions. Planned Amount: the amount you expect to debit from your account. Actual Amount: if a planned expense costs more or less than expected, edit the planned expense and enter the actual amount. Variable Expenses Unpredictable, one-off costs during a budget period, like fuel or dining. These are always treated as actual spending and are tracked by card and category. Planned Income Income you expect to receive, like salary or deposits. Planned income is used for forecasts and potential savings. Use planned income to help plan your budget. If income is very consistent, consider recurring actual income instead. Actual Income Income you actually receive. Actual income drives real totals, real savings, and the amount you can still spend safely. Income can be logged as actual when received, or set as recurring actual income for consistent paychecks. Budgets Budgets are a lens for viewing your income and expenses over a specific date range. Create budgets that align with your financial goals and pay cycles. How Totals Are Calculated Everything in Offshore is basic math: Planned expenses total = sum of planned amounts for planned expenses in the budget period. Actual planned expenses total = sum of actual amounts for those planned expenses. Variable expenses total = sum of variable expenses in the budget period. Planned income total = sum of income entries marked Planned in the period. Actual income total = sum of income entries marked Actual in the period. Potential savings = planned income total - planned expenses planned total. Actual savings = actual income total - (planned expenses actual total + variable expenses total)."
        ),
        GeneratedHelpTopic(
            id: "home",
            title: "Home",
            group: .coreScreens,
            iconSystemName: "house.fill",
            iconStyle: .purple,
            sections: [
                GeneratedHelpSection(
                    id: "home-1",
                    header: "Home: Welcome to Your Dashboard",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "You can pick your own custom start and end date, or use predefined ranges in the period menu. Widgets respond to the date range you select."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "home-2",
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
                        GeneratedHelpLine(kind: .bullet, value: "What If?: interactive scenario planner for budget outcomes."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "home-3",
                    header: "HomeView & Customization",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Use Edit on Home to choose what appears on your dashboard."),
                        GeneratedHelpLine(kind: .bullet, value: "Pin widgets and cards you care about most."),
                        GeneratedHelpLine(kind: .bullet, value: "Reorder pinned items to put key metrics first."),
                        GeneratedHelpLine(kind: .bullet, value: "Remove items you do not need right now."),
                        GeneratedHelpLine(kind: .bullet, value: "Keep Home focused on the date range and metrics you actually use."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "home-4",
                    header: "Home Calculations",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Home calculations mirror budget math."),
                        GeneratedHelpLine(kind: .bullet, value: "Actual Savings = actual income - (planned expenses effective amount + variable expenses total)."),
                        GeneratedHelpLine(kind: .bullet, value: "Remaining Income = actual income - expenses."),
                    ]
                )
            ],
            searchableText: "Home Home: Welcome to Your Dashboard 1 You can pick your own custom start and end date, or use predefined ranges in the period menu. Widgets respond to the date range you select. Widgets Overview 2 Home is made of widgets. Tap any widget to open its detail page. Income: shows actual income versus planned income. Savings Outlook: projected savings based on planned income and planned expenses. Next Planned Expense: displays the next upcoming planned expense. Category Spotlight: top categories by spend in the current range. Spend Trends: spend totals by day, week, or month depending on range. Category Availability: category caps and remaining amounts for the period. What If?: interactive scenario planner for budget outcomes. HomeView & Customization 3 Use Edit on Home to choose what appears on your dashboard. Pin widgets and cards you care about most. Reorder pinned items to put key metrics first. Remove items you do not need right now. Keep Home focused on the date range and metrics you actually use. Home Calculations Home calculations mirror budget math. Actual Savings = actual income - (planned expenses effective amount + variable expenses total). Remaining Income = actual income - expenses."
        ),
        GeneratedHelpTopic(
            id: "budgets",
            title: "Budgets",
            group: .coreScreens,
            iconSystemName: "chart.pie.fill",
            iconStyle: .blue,
            sections: [
                GeneratedHelpSection(
                    id: "budgets-1",
                    header: "Budgets: Where the Actual Budgeting Work Happens",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "This screen lists past, active, and upcoming budgets. Tap any budget to open details and add expenses, assign cards, and monitor budget metrics."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "budgets-2",
                    header: "Budget Details: Build the Budget",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Inside a budget, you track expenses in two lanes:"),
                        GeneratedHelpLine(kind: .bullet, value: "Planned: recurring or expected costs."),
                        GeneratedHelpLine(kind: .bullet, value: "Variable: one-off spending from your cards."),
                        GeneratedHelpLine(kind: .bullet, value: "Categories: long-press a category and assign a spending cap for this budgeting period."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "budgets-3",
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
                        GeneratedHelpLine(kind: .bullet, value: "Actual Savings = actual income - (planned expenses effective total + variable expenses total)."),
                    ]
                )
            ],
            searchableText: "Budgets Budgets: Where the Actual Budgeting Work Happens 1 This screen lists past, active, and upcoming budgets. Tap any budget to open details and add expenses, assign cards, and monitor budget metrics. Budget Details: Build the Budget 2 Inside a budget, you track expenses in two lanes: Planned: recurring or expected costs. Variable: one-off spending from your cards. Categories: long-press a category and assign a spending cap for this budgeting period. How Budget Totals Are Calculated 3 These totals are shown in the budget header. Planned Income = planned income total in this period. Actual Income = actual income total in this period. Planned Total = sum of planned expense planned amounts. Variable Total = sum of variable expenses in the period. Unified Total = planned effective total + variable total. Max Savings = planned income - planned expenses effective total. Projected Savings = planned income - planned expenses planned total. Actual Savings = actual income - (planned expenses effective total + variable expenses total)."
        ),
        GeneratedHelpTopic(
            id: "income",
            title: "Income",
            group: .coreScreens,
            iconSystemName: "calendar",
            iconStyle: .red,
            sections: [
                GeneratedHelpSection(
                    id: "income-1",
                    header: "Income: Calendar-Based Tracking",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "The calendar shows planned and actual income totals per day. Tap a day to see entries and weekly totals."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "income-2",
                    header: "Planned Income vs Actual Income",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "If your paycheck is consistent, create recurring actual income. If it varies, use planned income to estimate and log actual income when it arrives."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "income-3",
                    header: "How Income Feeds the App",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Income entries contribute to Home and Budget calculations. Actual income drives real totals and savings, while planned income supports forecasts."),
                    ]
                )
            ],
            searchableText: "Income Income: Calendar-Based Tracking 1 The calendar shows planned and actual income totals per day. Tap a day to see entries and weekly totals. Planned Income vs Actual Income 2 If your paycheck is consistent, create recurring actual income. If it varies, use planned income to estimate and log actual income when it arrives. How Income Feeds the App 3 Income entries contribute to Home and Budget calculations. Actual income drives real totals and savings, while planned income supports forecasts."
        ),
        GeneratedHelpTopic(
            id: "cards",
            title: "Cards",
            group: .coreScreens,
            iconSystemName: "creditcard.fill",
            iconStyle: .green,
            sections: [
                GeneratedHelpSection(
                    id: "cards-1",
                    header: "Cards: Spending Account Gallery",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Tap + to add a card. Tap a card to open detail view."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "cards-2",
                    header: "Card Detail: Deep Dive",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Card detail is a focused spending console with filters, scope controls, sorting, and search."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "cards-3",
                    header: "Card Calculations",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Totals reflect the current filters. Variable expenses are always actual. Planned expenses use actual amount when provided, otherwise planned amount."),
                    ]
                )
            ],
            searchableText: "Cards Cards: Spending Account Gallery 1 Tap + to add a card. Tap a card to open detail view. Card Detail: Deep Dive 2 Card detail is a focused spending console with filters, scope controls, sorting, and search. Card Calculations 3 Totals reflect the current filters. Variable expenses are always actual. Planned expenses use actual amount when provided, otherwise planned amount."
        ),
        GeneratedHelpTopic(
            id: "shared-balances",
            title: "Reconciliations",
            group: .coreScreens,
            iconSystemName: "person.2.fill",
            iconStyle: .purple,
            sections: [
                GeneratedHelpSection(
                    id: "shared-balances-1",
                    header: "Reconciliations: Track Shared Spending in One Place",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Reconciliations help you track money you fronted, split, or need to settle with someone else."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "shared-balances-2",
                    header: "Create and Manage Reconciliations",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "From Accounts > Reconciliations, tap + to add a reconciliation."),
                        GeneratedHelpLine(kind: .bullet, value: "Name each balance clearly (for example: Roommate, Trip Fund, Work Lunches)."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap a balance to open details."),
                        GeneratedHelpLine(kind: .bullet, value: "Edit from the context menu."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "shared-balances-3",
                    header: "Settlements and History",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Reconciliations keep a running ledger from allocations and settlements."),
                        GeneratedHelpLine(kind: .bullet, value: "Settlements move the balance toward zero."),
                        GeneratedHelpLine(kind: .bullet, value: "Balances with history are archived instead of hard deleted."),
                        GeneratedHelpLine(kind: .bullet, value: "Archived balances stay in history but are hidden from new choices."),
                    ]
                )
            ],
            searchableText: "Reconciliations Reconciliations: Track Shared Spending in One Place 1 Reconciliations help you track money you fronted, split, or need to settle with someone else. Create and Manage Reconciliations 2 From Accounts > Reconciliations, tap + to add a reconciliation. Name each balance clearly (for example: Roommate, Trip Fund, Work Lunches). Tap a balance to open details. Edit from the context menu. Settlements and History 3 Reconciliations keep a running ledger from allocations and settlements. Settlements move the balance toward zero. Balances with history are archived instead of hard deleted. Archived balances stay in history but are hidden from new choices."
        ),
        GeneratedHelpTopic(
            id: "savings-account",
            title: "Savings Account",
            group: .coreScreens,
            iconSystemName: "chart.line.uptrend.xyaxis",
            iconStyle: .green,
            sections: [
                GeneratedHelpSection(
                    id: "savings-account-1",
                    header: "Savings Account: Your Savings Ledger",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Savings gives you a dedicated ledger and running total for money you are setting aside."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "savings-account-2",
                    header: "Add and Manage Savings Entries",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "From Accounts > Savings, tap + to add a ledger entry."),
                        GeneratedHelpLine(kind: .bullet, value: "Add positive entries for contributions."),
                        GeneratedHelpLine(kind: .bullet, value: "Add negative entries for withdrawals."),
                        GeneratedHelpLine(kind: .bullet, value: "Swipe to edit or delete an entry."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "savings-account-3",
                    header: "Savings Trend and Date Range",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Savings includes a trend chart and date range filter."),
                        GeneratedHelpLine(kind: .bullet, value: "Use date range controls to review a period."),
                        GeneratedHelpLine(kind: .bullet, value: "Running Total reflects your full ledger balance."),
                        GeneratedHelpLine(kind: .bullet, value: "The chart helps you see momentum over time."),
                    ]
                )
            ],
            searchableText: "Savings Account Savings Account: Your Savings Ledger 1 Savings gives you a dedicated ledger and running total for money you are setting aside. Add and Manage Savings Entries 2 From Accounts > Savings, tap + to add a ledger entry. Add positive entries for contributions. Add negative entries for withdrawals. Swipe to edit or delete an entry. Savings Trend and Date Range 3 Savings includes a trend chart and date range filter. Use date range controls to review a period. Running Total reflects your full ledger balance. The chart helps you see momentum over time."
        ),
        GeneratedHelpTopic(
            id: "marina",
            title: "Marina",
            group: .coreScreens,
            iconSystemName: "message.badge.fill",
            iconStyle: .blue,
            sections: [
                GeneratedHelpSection(
                    id: "marina-1",
                    header: "Marina: Built-In Home Assistant",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Marina is your in-app budget assistant on Home. She answers from your Offshore data."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "marina-2",
                    header: "What You Can Ask",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Marina supports practical spending and savings questions."),
                        GeneratedHelpLine(kind: .bullet, value: "\"How am I doing this month?\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Top categories this month\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Largest recent expenses\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"How is my savings status?\""),
                        GeneratedHelpLine(kind: .bullet, value: "\"Do I have presets due soon?\""),
                    ]
                ),
                GeneratedHelpSection(
                    id: "marina-3",
                    header: "Clarifications and Follow-Ups",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "If a request is unclear, Marina asks quick clarifying questions."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap a follow-up suggestion to refine results."),
                        GeneratedHelpLine(kind: .bullet, value: "Use specific dates, categories, or cards for tighter answers."),
                        GeneratedHelpLine(kind: .bullet, value: "Treat responses as decision support based on your current data."),
                    ]
                )
            ],
            searchableText: "Marina Marina: Built-In Home Assistant 1 Marina is your in-app budget assistant on Home. She answers from your Offshore data. What You Can Ask 2 Marina supports practical spending and savings questions. \"How am I doing this month?\" \"Top categories this month\" \"Largest recent expenses\" \"How is my savings status?\" \"Do I have presets due soon?\" Clarifications and Follow-Ups 3 If a request is unclear, Marina asks quick clarifying questions. Tap a follow-up suggestion to refine results. Use specific dates, categories, or cards for tighter answers. Treat responses as decision support based on your current data."
        ),
        GeneratedHelpTopic(
            id: "import-workflow",
            title: "Import Workflow",
            group: .coreScreens,
            iconSystemName: "tray.and.arrow.down.fill",
            iconStyle: .orange,
            sections: [
                GeneratedHelpSection(
                    id: "import-workflow-1",
                    header: "Import Workflow for Income and Expenses",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Offshore can parse files, photos, and clipboard text to speed up entry."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "import-workflow-2",
                    header: "Supported Import Sources",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "You can import from:"),
                        GeneratedHelpLine(kind: .bullet, value: "Files (CSV, PDF, image)"),
                        GeneratedHelpLine(kind: .bullet, value: "Photos"),
                        GeneratedHelpLine(kind: .bullet, value: "Clipboard text"),
                        GeneratedHelpLine(kind: .bullet, value: "Shortcut screenshot or clipboard preview flows"),
                    ]
                ),
                GeneratedHelpSection(
                    id: "import-workflow-3",
                    header: "Review Before You Commit",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Imports open a review screen before anything is saved."),
                        GeneratedHelpLine(kind: .bullet, value: "Ready to Import"),
                        GeneratedHelpLine(kind: .bullet, value: "Possible Matches"),
                        GeneratedHelpLine(kind: .bullet, value: "Possible Duplicates"),
                        GeneratedHelpLine(kind: .bullet, value: "Needs More Data / Skipped rows"),
                    ]
                ),
                GeneratedHelpSection(
                    id: "import-workflow-4",
                    header: "Commit and Learning",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "After review, tap Import to save selected rows."),
                        GeneratedHelpLine(kind: .bullet, value: "Offshore stores merchant/category matching signals to improve future imports."),
                        GeneratedHelpLine(kind: .bullet, value: "Expense imports route to a selected card."),
                        GeneratedHelpLine(kind: .bullet, value: "Income imports route to income entries."),
                    ]
                )
            ],
            searchableText: "Import Workflow Import Workflow for Income and Expenses 1 Offshore can parse files, photos, and clipboard text to speed up entry. Supported Import Sources 2 You can import from: Files (CSV, PDF, image) Photos Clipboard text Shortcut screenshot or clipboard preview flows Review Before You Commit 3 Imports open a review screen before anything is saved. Ready to Import Possible Matches Possible Duplicates Needs More Data / Skipped rows Commit and Learning After review, tap Import to save selected rows. Offshore stores merchant/category matching signals to improve future imports. Expense imports route to a selected card. Income imports route to income entries."
        ),
        GeneratedHelpTopic(
            id: "excursion-mode",
            title: "Excursion Mode",
            group: .coreScreens,
            iconSystemName: "cart.fill",
            iconStyle: .red,
            sections: [
                GeneratedHelpSection(
                    id: "excursion-mode-1",
                    header: "Excursion Mode: Temporary Spending Session",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Excursion Mode is a timed session for in-the-moment spending."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "excursion-mode-2",
                    header: "Start, Stop, and Extend",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "You can start Excursion Mode from Notifications, Shortcuts, or in-app controls."),
                        GeneratedHelpLine(kind: .bullet, value: "Start for 1, 2, or 4 hours."),
                        GeneratedHelpLine(kind: .bullet, value: "Stop anytime."),
                        GeneratedHelpLine(kind: .bullet, value: "Extend active sessions by 30 minutes."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "excursion-mode-3",
                    header: "Session Signals",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "While active, Offshore can surface session status and nudges."),
                        GeneratedHelpLine(kind: .bullet, value: "Live Activity support on iPhone."),
                        GeneratedHelpLine(kind: .bullet, value: "Optional location-aware reminders."),
                        GeneratedHelpLine(kind: .bullet, value: "Session status appears in relevant controls until expiration."),
                    ]
                )
            ],
            searchableText: "Excursion Mode Excursion Mode: Temporary Spending Session 1 Excursion Mode is a timed session for in-the-moment spending. Start, Stop, and Extend 2 You can start Excursion Mode from Notifications, Shortcuts, or in-app controls. Start for 1, 2, or 4 hours. Stop anytime. Extend active sessions by 30 minutes. Session Signals 3 While active, Offshore can surface session status and nudges. Live Activity support on iPhone. Optional location-aware reminders. Session status appears in relevant controls until expiration."
        ),
        GeneratedHelpTopic(
            id: "presets",
            title: "Presets",
            group: .coreScreens,
            iconSystemName: "list.bullet.rectangle",
            iconStyle: .orange,
            sections: [
                GeneratedHelpSection(
                    id: "presets-1",
                    header: "Presets: Reusable Fixed Expense Templates",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Use presets for fixed bills like rent or subscriptions. Tap + to create one. Swipe right to edit or left to delete."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "presets-2",
                    header: "How Presets Affect Totals",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "When assigned to a budget, presets become planned expenses in that budget."),
                        GeneratedHelpLine(kind: .bullet, value: "Presets act as templates for planned expenses."),
                        GeneratedHelpLine(kind: .bullet, value: "Planned expenses generated from presets use planned amount unless you edit actual amount later."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "presets-3",
                    header: "Tip",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Use presets to make budget setup fast and consistent month to month."),
                    ]
                )
            ],
            searchableText: "Presets Presets: Reusable Fixed Expense Templates 1 Use presets for fixed bills like rent or subscriptions. Tap + to create one. Swipe right to edit or left to delete. How Presets Affect Totals 2 When assigned to a budget, presets become planned expenses in that budget. Presets act as templates for planned expenses. Planned expenses generated from presets use planned amount unless you edit actual amount later. Tip 3 Use presets to make budget setup fast and consistent month to month."
        ),
        GeneratedHelpTopic(
            id: "settings",
            title: "Settings",
            group: .coreScreens,
            iconSystemName: "gear",
            iconStyle: .gray,
            sections: [
                GeneratedHelpSection(
                    id: "settings-1",
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
                        GeneratedHelpLine(kind: .bullet, value: "Presets: manage expense presets."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "settings-2",
                    header: "Settings Toggles for Expense Display",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "In General > Expense Display, you can control future expenses in two different ways."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide future planned expenses: hides planned items from lists."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude future planned expenses from calculations: removes future planned items from totals."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide future variable expenses: hides variable items dated in the future."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude future variable expenses from calculations: keeps those future variable items out of totals."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "settings-3",
                    header: "Why Hide vs Exclude Matters",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Hide and Exclude are not the same setting."),
                        GeneratedHelpLine(kind: .bullet, value: "Hide changes what you see on screen."),
                        GeneratedHelpLine(kind: .bullet, value: "Exclude changes calculation results."),
                        GeneratedHelpLine(kind: .bullet, value: "You can combine them if you want cleaner views and tighter totals."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "settings-4",
                    header: "Workspaces",
                    lines: [
                        GeneratedHelpLine(kind: .text, value: "Offshore supports multiple workspaces to separate budgeting contexts like Personal and Work. Each workspace has its own cards, income, presets, categories, and budgets."),
                    ]
                )
            ],
            searchableText: "Settings Settings: Configure Offshore 1 Every row is a separate area to manage your Offshore experience. About: version info, contact support, release logs. Help: this guide and Repeat Onboarding. Install Quick Actions: shortcut install links and trigger setup guidance. General: currency, budget period, tips reset, erase content. Privacy: biometrics app lock. Notifications: reminders for daily spending, income comparisons, and due presets. iCloud: sync across devices and sync status. Categories: manage expense categories. Presets: manage expense presets. Settings Toggles for Expense Display 2 In General > Expense Display, you can control future expenses in two different ways. Hide future planned expenses: hides planned items from lists. Exclude future planned expenses from calculations: removes future planned items from totals. Hide future variable expenses: hides variable items dated in the future. Exclude future variable expenses from calculations: keeps those future variable items out of totals. Why Hide vs Exclude Matters 3 Hide and Exclude are not the same setting. Hide changes what you see on screen. Exclude changes calculation results. You can combine them if you want cleaner views and tighter totals. Workspaces Offshore supports multiple workspaces to separate budgeting contexts like Personal and Work. Each workspace has its own cards, income, presets, categories, and budgets."
        ),
        GeneratedHelpTopic(
            id: "quick-actions",
            title: "Quick Actions",
            group: .coreScreens,
            iconSystemName: "bolt.fill",
            iconStyle: .orange,
            sections: [
                GeneratedHelpSection(
                    id: "quick-actions-1",
                    header: "Quick Actions: Shortcut Entry Points",
                    lines: [
                        GeneratedHelpLine(kind: .heroScreenshot, value: "1"),
                        GeneratedHelpLine(kind: .text, value: "Quick Actions are optional. Install the shared shortcuts first, then set up the matching automations in Shortcuts."),
                        GeneratedHelpLine(kind: .bullet, value: "Add Expense to Offshore"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income to Offshore"),
                        GeneratedHelpLine(kind: .bullet, value: "Start Excursion Mode"),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-2",
                    header: "Shortcuts & Automations",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "2"),
                        GeneratedHelpLine(kind: .text, value: "Trigger automations can feed Offshore from Wallet, Messages, and Email."),
                        GeneratedHelpLine(kind: .bullet, value: "Add Expense From Tap To Pay"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income From An SMS Message"),
                        GeneratedHelpLine(kind: .bullet, value: "Add Income From An Email"),
                        GeneratedHelpLine(kind: .bullet, value: "Use Run Immediately for the smoothest experience."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-3",
                    header: "App Shortcuts You Can Run Anytime",
                    lines: [
                        GeneratedHelpLine(kind: .miniScreenshot, value: "3"),
                        GeneratedHelpLine(kind: .text, value: "Offshore also exposes direct shortcuts for common actions."),
                        GeneratedHelpLine(kind: .bullet, value: "Log Expense"),
                        GeneratedHelpLine(kind: .bullet, value: "Log Income"),
                        GeneratedHelpLine(kind: .bullet, value: "Review Today's Spending"),
                        GeneratedHelpLine(kind: .bullet, value: "Forecast Savings"),
                        GeneratedHelpLine(kind: .bullet, value: "What Can I Spend Today?"),
                        GeneratedHelpLine(kind: .bullet, value: "Open Quick Add flows"),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-4",
                    header: "Before You Start",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "Open Offshore > Settings > Quick Actions."),
                        GeneratedHelpLine(kind: .bullet, value: "Tap each shortcut link and import it in Shortcuts."),
                        GeneratedHelpLine(kind: .bullet, value: "Confirm the imported shortcut names are correct."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-5",
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
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-6",
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
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-7",
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
                        GeneratedHelpLine(kind: .bullet, value: "Save the automation."),
                    ]
                ),
                GeneratedHelpSection(
                    id: "quick-actions-8",
                    header: "Troubleshooting",
                    lines: [
                        GeneratedHelpLine(kind: .bullet, value: "If a shared item imports with a long autogenerated name, rename the shortcut after import."),
                        GeneratedHelpLine(kind: .bullet, value: "If you do not see the expected trigger type, make sure your device and iOS version support that trigger."),
                        GeneratedHelpLine(kind: .bullet, value: "If the last Offshore action appears missing, confirm Offshore is installed on that device, then edit the shortcut and add Offshore Add Income or Add Expense as the last action again."),
                        GeneratedHelpLine(kind: .bullet, value: "If an automation does not fire, open it in Shortcuts and verify trigger condition text, selected Run Shortcut action, and run behavior settings."),
                    ]
                )
            ],
            searchableText: "Quick Actions Quick Actions: Shortcut Entry Points 1 Quick Actions are optional. Install the shared shortcuts first, then set up the matching automations in Shortcuts. Add Expense to Offshore Add Income to Offshore Start Excursion Mode Shortcuts & Automations 2 Trigger automations can feed Offshore from Wallet, Messages, and Email. Add Expense From Tap To Pay Add Income From An SMS Message Add Income From An Email Use Run Immediately for the smoothest experience. App Shortcuts You Can Run Anytime 3 Offshore also exposes direct shortcuts for common actions. Log Expense Log Income Review Today's Spending Forecast Savings What Can I Spend Today? Open Quick Add flows Before You Start Open Offshore > Settings > Quick Actions. Tap each shortcut link and import it in Shortcuts. Confirm the imported shortcut names are correct. Add Expense From Tap To Pay Open Shortcuts > Automation. Tap New Automation. Scroll down and select Wallet. Configure this screen to your liking. You can choose which card or cards should trigger the automation. It is recommended to leave all categories selected. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience. On the next screen, tap Create New Shortcut. Add action: Get Text from Shortcut Input. In this action, tap the blue Input field and choose Shortcut Input. Add action: Run Shortcut. In Run Shortcut, tap the blue Shortcut field and select Add Expense From Tap To Pay. Save the automation. Add Income From An SMS Message Open Shortcuts > Automation. Tap New Automation. Scroll down and select Message. Configure this screen to your liking. For example, use Message Contains and type the exact phrasing your bank uses in deposit notifications. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience. On the next screen, tap Create New Shortcut. Add action: Get Text from Shortcut Input. In this action, tap the blue Input field and choose Shortcut Input. Add action: Run Shortcut. In Run Shortcut, tap the blue Shortcut field and select Add Income From An SMS Message. Save the automation. Add Income From An Email Open Shortcuts > Automation. Tap New Automation. Scroll down and select Email. Configure this screen to your liking. For example, use Subject Contains and type the exact phrasing your bank uses in deposit email subject lines. Instead of Run After Confirmation, choose Run Immediately for an uninterrupted experience. On the next screen, tap Create New Shortcut. Add action: Get Text from Shortcut Input. In this action, tap the blue Input field and choose Shortcut Input. Add action: Run Shortcut. In Run Shortcut, tap the blue Shortcut field and select Add Income From An Email. Save the automation. Troubleshooting If a shared item imports with a long autogenerated name, rename the shortcut after import. If you do not see the expected trigger type, make sure your device and iOS version support that trigger. If the last Offshore action appears missing, confirm Offshore is installed on that device, then edit the shortcut and add Offshore Add Income or Add Expense as the last action again. If an automation does not fire, open it in Shortcuts and verify trigger condition text, selected Run Shortcut action, and run behavior settings."
        )
    ]

    static var gettingStartedTopics: [GeneratedHelpTopic] {
        topics.filter { $0.group == .gettingStarted }
    }

    static var coreScreenTopics: [GeneratedHelpTopic] {
        topics.filter { $0.group == .coreScreens }
    }
}
