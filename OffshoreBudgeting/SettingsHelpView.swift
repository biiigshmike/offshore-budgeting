import SwiftUI

struct SettingsHelpView: View {

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = true
    @State private var showOnboardingAlert: Bool = false

    var body: some View {
        List {
            Section("Getting Started") {
                NavigationLink {
                    IntroductionHelpView()
                } label: {
                    HelpRowLabel(
                        iconSystemName: "exclamationmark.bubble",
                        title: "Introduction",
                        iconStyle: .blue
                    )
                }
            }

            Section {
                repeatOnboardingButton
            }

            Section("Core Screens") {
                NavigationLink {
                    HomeHelpView()
                } label: {
                    HelpRowLabel(iconSystemName: "house.fill", title: "Home", iconStyle: .purple)
                }

                NavigationLink {
                    BudgetsHelpView()
                } label: {
                    HelpRowLabel(iconSystemName: "chart.pie.fill", title: "Budgets", iconStyle: .blue)
                }

                NavigationLink {
                    IncomeHelpView()
                } label: {
                    HelpRowLabel(iconSystemName: "calendar", title: "Income", iconStyle: .red)
                }

                NavigationLink {
                    CardsHelpView()
                } label: {
                    HelpRowLabel(iconSystemName: "creditcard.fill", title: "Cards", iconStyle: .green)
                }

                NavigationLink {
                    PresetsHelpView()
                } label: {
                    HelpRowLabel(iconSystemName: "list.bullet.rectangle", title: "Presets", iconStyle: .orange)
                }

                NavigationLink {
                    SettingsHelpDetailsView()
                } label: {
                    HelpRowLabel(iconSystemName: "gear", title: "Settings", iconStyle: .gray)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Help")
        .alert("Repeat Onboarding?", isPresented: $showOnboardingAlert) {
            Button("Go", role: .destructive) { didCompleteOnboarding = false }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can restart onboarding at any time.")
        }
    }

    // MARK: - Repeat Onboarding Button

    private var repeatOnboardingButton: some View {
        Button {
            showOnboardingAlert = true
        } label: {
            Text("Repeat Onboarding")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(.blue)
        .listRowInsets(EdgeInsets())
    }
}

// MARK: - Help Detail Screens

private struct IntroductionHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Offshore Budgeting: a privacy-first budgeting app. All data is processed on your device, and you’ll never be asked to connect a bank account. This guide introduces the core building blocks and explains exactly how totals are calculated across the app.")

                sectionHeader("The Building Blocks")
                Text("Cards, Income, Expense Categories, Presets, and Budgets are the foundation:")
                bullet("Cards hold your expenses and let you analyze spending by card.")
                bullet("Income is tracked via planned or actual income. Use planned income to help gauge savings and actual income for income you actually received to get your actual savings.")
                bullet("Expense Categories describe what the expense was for (groceries, rent, fuel).")
                bullet("Presets are reusable planned expenses for recurring bills.")
                bullet("Variable expenses are one-off or unpredictable expenses tied to a card.")
                bullet("Budgets group a date range so the app can summarize income, expenses, and savings for that period, such as Daily, Monthly, Quarterly, or Yearly. Budget in a way that makes sense to you.")

                sectionHeader("Planned Expenses")
                Text("Expected or recurring costs for a budget period (rent, subscriptions).")
                bullet("Plannd Amount: The amount you expect to debit from your account.")
                bullet("Actual Amount: Sometimes, a planned expense may cost more or less than expected. Edit the Planned Expense from your budget and enter the actual amount debited to keep your totals accurate.")
                Text("Pro Tip: If you notice a planned expense consistently costs more or less than expected, update the planned amount to reflect reality.")
                
                sectionHeader("Variable Expenses")
                Text("Unpredictable, one-off costs during a budget period (fuel, dining). These are always treated as actual spending and are tracked by card and category.")

                sectionHeader("Planned Income")
                Text("Income you expect to receive (salary, deposits). Planned income is used for forecasts and potential savings.")
                bullet("Use Planned Income to help plan your budget. If your income is consistent, consider creating a recurring Actual Income entry instead.")

                sectionHeader("Actual Income")
                Text("Income you actually receive. Actual income drives real totals, real savings, and the amount you can still spend safely.")
                bullet("Income can be logged as Actual when received, or you can create a recurring Actual Income entry for consistent paychecks.")

                sectionHeader("Budgets")
                Text("Budgets are a lens for viewing your income and expenses over a specific date range. Create budgets that align with your financial goals and pay cycles. Budget in a way that makes sense to you.")

                sectionHeader("How Totals Are Calculated")
                Text("Everything in Offshore is basic math, and here's how it breaks down:")
                bullet("Planned expenses total = sum of the planned amounts for planned expenses in the budget period.")
                bullet("Actual planned expenses total = sum of the actual amounts for those planned expenses.")
                bullet("Variable expenses total = sum of unplanned or variable expenses in the budget period.")
                bullet("Planned income total = sum of income entries marked Planned in the period.")
                bullet("Actual income total = sum of income entries marked Actual in the period.")
                bullet("Potential savings = planned income total - planned expenses planned total.")
                bullet("Actual savings = actual income total - (planned expenses actual total + variable expenses total).")
            }
            .padding()
        }
        .navigationTitle("Introduction")
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Divider()
        }
        .padding(.top, 10)
    }

    private func bullet(_ text: String) -> Text {
        Text("• \(text)")
    }
}

private struct HomeHelpView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Home",
            sections: [
                .init(screenshotSlot: 1, header: "Home is your dashboard for the selected date range.", body: [
                    "By default, Home loads using your default budgeting preference from Settings. You can pick your own custom start and end date, or use the pre-defined ranges in the period menu by pressing on the calendar icon. The widgets respond with the date range you select."
                ]),
                .init(screenshotSlot: 2, header: "Widgets Overview", body: [
                    "Home is made of widgets. Tap any widget to open its detail page.",
                    "• Income: shows Actual Income versus Planned Income. Tapping the widget takes you to a detailed metric overview to view income trends over time.",
                    "• Savings Outlook: Use Savings Outlook to view your projected savings based on your planned income and expenses. The projected savings is calculated by taking your Actual Savings + Planned Income and subtracting remaining Planned Expenses.",
                    "• Next Planned Expense: Displays the next upcoming Planned Expense. Tapping it opens the Presets management page where you will see this expense pinned at the top, as well as being able to quickly manage the rest of your presets here.",
                    "• Category Spotlight: Shows the top categories by spend in the current range. The total is derived by summing the Planned Expenses and Variable together for each category.",
                    "• Spend Trends: Spend totals segmented by day, week, or month, depending upon which period is being viewed. Tapping the widget opens a detailed trends view.",
                    "• Category Availability: Caps and remaining amounts for categories with limits set. Planned and Variable expenses are summed to show total spend against the cap for the period.",
                    "• What If?: An interactive scenario planner to project if you will be over or under your available income threshold. Use it to plan different scenarios. You can even pin scenarios you're closely monitoring on Home (maximum of 3 scenarios can be pinned)."
                ]),
                .init(screenshotSlot: 3, header: "Home Calculations", body: [
                    "Home calculations mirror your budget math:",
                    "• Actual Savings = actual income - (planned expenses actual amount + variable expenses total amount).",
                    "• Remaining Income = actual income - expenses."
                ])
            ]
        )
    }
}

private struct BudgetsHelpView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Budgets",
            sections: [
                .init(screenshotSlot: 1, header: "Budgets: the place where the actual budgeting magic happens.", body: [
                    "This screen lists Past, Active, and Upcoming budgets. Tap any budget to open its details and do the real work: add expenses, assign cards, and monitor totals."
                ]),
                .init(screenshotSlot: 2, header: "Budget Details: Build the Budget", body: [
                    "Inside a budget, you plan and track expenses in two lanes:",
                    "• Planned: recurring or expected costs.",
                    "• Variable: one-off spending from your cards."
                ]),
                .init(screenshotSlot: 3, header: "How Budget Totals Are Calculated", body: [
                    "These totals are shown in the budget header and summary cards:",
                    "• Income (Expected) = planned income total in this period.",
                    "• Income (Received) = actual income total in this period.",
                    "• Planned expenses (Planned) = sum of planned amounts.",
                    "• Planned expenses (Actual) = sum of actual amounts entered on planned expenses.",
                    "• Variable expenses = sum of unplanned expenses on cards for this budget."
                ])
            ]
        )
    }
}

private struct IncomeHelpView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Income",
            sections: [
                .init(screenshotSlot: 1, header: "Income is your calendar-based income tracker.", body: [
                    "The calendar shows planned and actual income totals per day. Tap a day to see its income entries and weekly totals."
                ]),
                .init(screenshotSlot: 2, header: "Planned vs Actual Income", body: [
                    "If your paycheck is consistent, create a recurring Actual Income entry. If it varies, use Planned Income to estimate, then log Actual Income when it arrives."
                ]),
                .init(screenshotSlot: 3, header: "How Income Feeds the App", body: [
                    "Income totals feed Home and Budgets, especially Savings and pacing widgets."
                ])
            ]
        )
    }
}

private struct CardsHelpView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Cards",
            sections: [
                .init(screenshotSlot: 1, header: "Cards is your full gallery of saved cards.", body: [
                    "Tap + to add a card. Tap a card to open its detail view."
                ]),
                .init(screenshotSlot: 2, header: "Card Detail: Deep Dive", body: [
                    "The detail view is a focused spending console with filters, segmented scope, sorting, and search."
                ]),
                .init(screenshotSlot: 3, header: "Card Calculations", body: [
                    "Totals reflect the current filters. Variable is always actual, planned depends on actual amounts entered."
                ])
            ]
        )
    }
}

private struct PresetsHelpView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Presets",
            sections: [
                .init(screenshotSlot: 1, header: "Presets are reusable planned expense templates.", body: [
                    "Use presets for fixed bills (rent, subscriptions). Tap + to create a new preset. Swipe to edit or delete."
                ]),
                .init(screenshotSlot: 2, header: "How Presets Affect Totals", body: [
                    "When assigned to a budget, presets become planned expenses in that budget."
                ]),
                .init(screenshotSlot: 3, header: "Tip", body: [
                    "Use presets to make budget setup fast and consistent month to month."
                ])
            ]
        )
    }
}

private struct SettingsHelpDetailsView: View {
    var body: some View {
        HelpDetailScreen(
            title: "Settings",
            sections: [
                .init(screenshotSlot: 1, header: "Settings is where you configure the app.", body: [
                    "Every row here is a separate area to manage the app, including About, Help, General, Privacy, Notifications, iCloud, Categories, and Presets."
                ]),
                .init(screenshotSlot: 2, header: "How Settings Affect Calculations", body: [
                    "Your default budget period influences Home and budgeting screens, and Categories drive grouping and filtering."
                ]),
                .init(screenshotSlot: 3, header: "Workspace Tip", body: [
                    "If you use multiple workspaces (Personal, Work), Settings is usually where you decide what defaults each workspace should follow."
                ])
            ]
        )
    }
}

// MARK: - Shared Detail Screen Components

private struct HelpScreenSection: Identifiable {
    let id = UUID()
    let screenshotSlot: Int
    let header: String?
    let body: [String]
}

private struct HelpDetailScreen: View {
    let title: String
    let sections: [HelpScreenSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections) { section in
                    HelpScreenshotPlaceholder(
                        sectionTitle: title,
                        slot: section.screenshotSlot
                    )
                    .padding(.vertical, 4)

                    if let header = section.header {
                        Text(header)
                            .font(.title3.weight(.semibold))
                        Divider()
                    }

                    ForEach(section.body, id: \.self) { line in
                        Text(line)
                    }

                    if section.id != sections.last?.id {
                        Spacer().frame(height: 8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
    }
}

// MARK: - Row UI

private enum HelpIconStyle {
    case gray, blue, purple, red, green, orange

    var background: Color {
        switch self {
        case .gray: return Color(.systemGray)
        case .blue: return Color(.systemBlue)
        case .purple: return Color(.systemPurple)
        case .red: return Color(.systemRed)
        case .green: return Color(.systemGreen)
        case .orange: return Color(.systemOrange)
        }
    }
}

private struct HelpRowLabel: View {
    let iconSystemName: String
    let title: String
    let iconStyle: HelpIconStyle

    var body: some View {
        HStack(spacing: 16) {
            HelpIconTile(systemName: iconSystemName, style: iconStyle)
            Text(title)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
    }
}

private struct HelpIconTile: View {
    let systemName: String
    let style: HelpIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(style.background)

            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: - Screenshot Loader

private struct HelpScreenshotPlaceholder: View {
    let sectionTitle: String
    let slot: Int

    private var assetName: String {
        let sanitizedSection = sectionTitle.replacingOccurrences(of: " ", with: "")
        return "Help-\(sanitizedSection)-\(slot)"
    }

    var body: some View {
        if let image = platformImage(named: assetName) {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)

                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .regular))
                    Text("\(sectionTitle) Screenshot \(slot)")
                        .font(.subheadline.weight(.semibold))
                    Text("Add asset: \(assetName)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 18)
            }
        }
    }

    #if canImport(UIKit)
    private func platformImage(named name: String) -> UIImage? { UIImage(named: name) }
    #elseif canImport(AppKit)
    private func platformImage(named name: String) -> NSImage? { NSImage(named: name) }
    #else
    private func platformImage(named name: String) -> Any? { nil }
    #endif
}

#if canImport(UIKit)
private extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
private extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

#Preview("Help") {
    NavigationStack {
        SettingsHelpView()
    }
}
