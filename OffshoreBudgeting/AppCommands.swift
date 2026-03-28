//
//  AppCommands.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/13/26.
//

import SwiftUI
import Combine

// MARK: - Command IDs

enum AppCommandID {
    enum Window {
        static let newWindow = "window.new_window"
    }

    enum Help {
        static let openHelp = "help.open_help"
    }

    enum Budgets {
        static let newBudget = "budgets.new_budget"
        static let sortAZ = "budgets.sort.az"
        static let sortZA = "budgets.sort.za"
        static let sortDateAsc = "budgets.sort.date_asc"
        static let sortDateDesc = "budgets.sort.date_desc"
    }

    enum Presets {
        static let sortAZ = "presets.sort.az"
        static let sortZA = "presets.sort.za"
        static let sortDateAsc = "presets.sort.date_asc"
        static let sortDateDesc = "presets.sort.date_desc"
        static let sortAmountAsc = "presets.sort.amount_asc"
        static let sortAmountDesc = "presets.sort.amount_desc"
    }

    enum Categories {
        static let sortAZ = "categories.sort.az"
        static let sortZA = "categories.sort.za"
    }

    enum BudgetDetail {
        static let newTransaction = "budget_detail.new_transaction"
        static let editBudget = "budget_detail.edit_budget"
        static let deleteBudget = "budget_detail.delete_budget"
        static let sortAZ = "budget_detail.sort.az"
        static let sortZA = "budget_detail.sort.za"
        static let sortAmountAsc = "budget_detail.sort.amount_asc"
        static let sortAmountDesc = "budget_detail.sort.amount_desc"
        static let sortDateAsc = "budget_detail.sort.date_asc"
        static let sortDateDesc = "budget_detail.sort.date_desc"
    }

    enum Income {
        static let newActual = "income.new_actual"
        static let newPlanned = "income.new_planned"
        static let deleteActual = "income.delete_actual"
        static let deletePlanned = "income.delete_planned"
    }

    enum Cards {
        static let newCard = "cards.new_card"
        static let sortAZ = "cards.sort.az"
        static let sortZA = "cards.sort.za"
    }

    enum SharedBalances {
        static let sortAZ = "shared_balances.sort.az"
        static let sortZA = "shared_balances.sort.za"
        static let sortAmountAsc = "shared_balances.sort.amount_asc"
        static let sortAmountDesc = "shared_balances.sort.amount_desc"
    }

    enum Savings {
        static let newEntry = "savings.new_entry"
        static let sortAZ = "savings.sort.az"
        static let sortZA = "savings.sort.za"
        static let sortAmountAsc = "savings.sort.amount_asc"
        static let sortAmountDesc = "savings.sort.amount_desc"
        static let sortDateAsc = "savings.sort.date_asc"
        static let sortDateDesc = "savings.sort.date_desc"
    }

    enum CardDetail {
        static let newTransaction = "card_detail.new_transaction"
        static let editCard = "card_detail.edit_card"
        static let deleteCard = "card_detail.delete_card"
        static let sortAZ = "card_detail.sort.az"
        static let sortZA = "card_detail.sort.za"
        static let sortAmountAsc = "card_detail.sort.amount_asc"
        static let sortAmountDesc = "card_detail.sort.amount_desc"
        static let sortDateAsc = "card_detail.sort.date_asc"
        static let sortDateDesc = "card_detail.sort.date_desc"
    }

    enum ExpenseDisplay {
        static let toggleHideFuturePlanned = "expense_display.toggle_hide_future_planned"
        static let toggleExcludeFuturePlanned = "expense_display.toggle_exclude_future_planned"
        static let toggleHideFutureVariable = "expense_display.toggle_hide_future_variable"
        static let toggleExcludeFutureVariable = "expense_display.toggle_exclude_future_variable"
    }
}

// MARK: - Surface

enum AppCommandSurface: Equatable {
    case none
    case home
    case budgets
    case presets
    case categories
    case budgetDetail
    case income
    case cards
    case savings
    case cardDetail
}

enum AppCardsSortCommandContext: String, Equatable {
    case cards
    case sharedBalances
}

// MARK: - Availability

struct AppCommandAvailability: Equatable {
    var budgetDetailCanCreateTransaction: Bool = false
    var incomeCanDeleteActual: Bool = false
    var incomeCanDeletePlanned: Bool = false
    var cardsSortContext: AppCardsSortCommandContext = .cards
}

enum AppCommandHubPolicy: Equatable {
    case enabled
    case disabled
}

// MARK: - Hub

@MainActor
final class AppCommandHub: ObservableObject {
    private let policy: AppCommandHubPolicy

    @Published private(set) var surface: AppCommandSurface = .none
    @Published private(set) var availability: AppCommandAvailability = .init()
    @Published private(set) var activeSectionRaw: String = AppSection.home.rawValue
    @Published private(set) var sequence: Int = 0
    private(set) var latestCommandID: String = ""

    init(policy: AppCommandHubPolicy = .enabled) {
        self.policy = policy
    }

    func activate(_ surface: AppCommandSurface) {
        guard policy == .enabled else { return }
        guard self.surface != surface else { return }
        self.surface = surface
    }

    func deactivate(_ surface: AppCommandSurface) {
        guard policy == .enabled else { return }
        guard self.surface == surface else { return }
        self.surface = .none
    }

    func setBudgetDetailCanCreateTransaction(_ canCreate: Bool) {
        guard policy == .enabled else { return }
        guard availability.budgetDetailCanCreateTransaction != canCreate else { return }
        availability.budgetDetailCanCreateTransaction = canCreate
    }

    func setIncomeDeletionAvailability(canDeleteActual: Bool, canDeletePlanned: Bool) {
        guard policy == .enabled else { return }
        guard availability.incomeCanDeleteActual != canDeleteActual
                || availability.incomeCanDeletePlanned != canDeletePlanned else { return }

        availability.incomeCanDeleteActual = canDeleteActual
        availability.incomeCanDeletePlanned = canDeletePlanned
    }

    func setCardsSortContext(_ context: AppCardsSortCommandContext) {
        guard policy == .enabled else { return }
        guard availability.cardsSortContext != context else { return }
        availability.cardsSortContext = context
    }

    func dispatch(_ commandID: String) {
        latestCommandID = commandID
        sequence += 1
    }

    func setActiveSectionRaw(_ sectionRaw: String) {
        guard policy == .enabled else { return }
        guard activeSectionRaw != sectionRaw else { return }
        activeSectionRaw = sectionRaw
    }
}

// MARK: - Environment

private struct AppCommandHubKey: EnvironmentKey {
    static let defaultValue: AppCommandHub = AppCommandHub()
}

extension EnvironmentValues {
    var appCommandHub: AppCommandHub {
        get { self[AppCommandHubKey.self] }
        set { self[AppCommandHubKey.self] = newValue }
    }
}

// MARK: - Command Item

private struct AppMenuCommandItem: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let shortcut: KeyboardShortcut?
    let isEnabled: Bool
    let role: ButtonRole?

    init(
        id: String,
        title: LocalizedStringResource,
        shortcut: KeyboardShortcut? = nil,
        isEnabled: Bool = true,
        role: ButtonRole? = nil
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.role = role
    }
}

private extension LocalizedStringResource {
    static var localizedSortAZ: LocalizedStringResource {
        "Sort A-Z"
    }

    static var localizedSortZA: LocalizedStringResource {
        "Sort Z-A"
    }

    static var localizedSortDateAsc: LocalizedStringResource {
        "Sort Date ↑"
    }

    static var localizedSortDateDesc: LocalizedStringResource {
        "Sort Date ↓"
    }

    static var localizedSortAmountAsc: LocalizedStringResource {
        "Sort $↑"
    }

    static var localizedSortAmountDesc: LocalizedStringResource {
        "Sort $↓"
    }
}

// MARK: - Commands

struct OffshoreAppCommands: Commands {
    @FocusedObject private var commandHub: AppCommandHub?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "appCommands.newWindow", defaultValue: "New Window", comment: "Command menu item for opening a new app window.")) {
                openNewWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(supportsMultipleWindows == false)

            if !fileItems.isEmpty {
                Divider()
                ForEach(fileItems) { item in
                    commandButton(for: item)
                }
            }
        }

        #if targetEnvironment(macCatalyst)
        CommandGroup(replacing: .help) {
            ForEach(helpItems) { item in
                commandButton(for: item)
            }
        }
        #elseif canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .pad && ProcessInfo.processInfo.isiOSAppOnMac == false {
            CommandGroup(after: .help) {
                ForEach(helpItems) { item in
                    commandButton(for: item)
                }
            }
        }
        #endif

        CommandGroup(after: .pasteboard) {
            if !editItems.isEmpty {
                Divider()
                ForEach(editItems) { item in
                    commandButton(for: item)
                }
            }
        }

        CommandGroup(after: .toolbar) {
            if !viewItems.isEmpty {
                Divider()
                ForEach(viewItems) { item in
                    commandButton(for: item)
                }
            }
        }
    }

    private var helpItems: [AppMenuCommandItem] {
        [
            AppMenuCommandItem(
                id: AppCommandID.Help.openHelp,
                title: "Offshore Help"
            )
        ]
    }

    private var fileItems: [AppMenuCommandItem] {
        switch currentSurface {
        case .home:
            return []
        case .budgets:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.Budgets.newBudget,
                    title: "New Budget",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                )
            ]
        case .budgetDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.newTransaction,
                    title: "New Expense",
                    shortcut: KeyboardShortcut("n", modifiers: [.command]),
                    isEnabled: currentAvailability.budgetDetailCanCreateTransaction
                )
            ]
        case .income:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.Income.newActual,
                    title: "New Actual Income",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.Income.newPlanned,
                    title: "New Planned Income",
                    shortcut: KeyboardShortcut("n", modifiers: [.command, .shift])
                )
            ]
        case .cards:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.Cards.newCard,
                    title: "New Card",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                )
            ]
        case .savings:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.Savings.newEntry,
                    title: "New Savings Entry",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                )
            ]
        case .cardDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.newTransaction,
                    title: "New Expense",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                )
            ]
        case .none, .presets, .categories:
            return []
        }
    }

    private var editItems: [AppMenuCommandItem] {
        switch currentSurface {
        case .home:
            return []
        case .budgetDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.editBudget,
                    title: "Edit Budget",
                    shortcut: KeyboardShortcut("e", modifiers: [.command])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.deleteBudget,
                    title: "Delete Budget",
                    shortcut: KeyboardShortcut(.delete, modifiers: [.command]),
                    role: .destructive
                )
            ]
        case .income:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.Income.deleteActual,
                    title: "Delete Actual Income",
                    shortcut: KeyboardShortcut(.delete, modifiers: [.command]),
                    isEnabled: currentAvailability.incomeCanDeleteActual,
                    role: .destructive
                ),
                AppMenuCommandItem(
                    id: AppCommandID.Income.deletePlanned,
                    title: "Delete Planned Income",
                    shortcut: KeyboardShortcut(.delete, modifiers: [.command, .shift]),
                    isEnabled: currentAvailability.incomeCanDeletePlanned,
                    role: .destructive
                )
            ]
        case .cardDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.editCard,
                    title: "Edit Card",
                    shortcut: KeyboardShortcut("e", modifiers: [.command])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.deleteCard,
                    title: "Delete Card",
                    shortcut: KeyboardShortcut(.delete, modifiers: [.command]),
                    role: .destructive
                )
            ]
        case .none, .budgets, .presets, .categories, .cards, .savings:
            return []
        }
    }

    private var viewItems: [AppMenuCommandItem] {
        switch currentSurface {
        case .home:
            return expenseDisplayItems
        case .budgets:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.Budgets.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Budgets.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Budgets.sortDateAsc,
                        title: .localizedSortDateAsc,
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Budgets.sortDateDesc,
                        title: .localizedSortDateDesc,
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                )
            ]
        case .presets:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortDateAsc,
                        title: .localizedSortDateAsc,
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortDateDesc,
                        title: .localizedSortDateDesc,
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortAmountAsc,
                        title: .localizedSortAmountAsc,
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Presets.sortAmountDesc,
                        title: .localizedSortAmountDesc,
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                )
            ]
        case .categories:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.Categories.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Categories.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                )
            ]
        case .cards:
            switch currentAvailability.cardsSortContext {
            case .cards:
                return [
                    AppMenuCommandItem(
                        id: AppCommandID.Cards.sortAZ,
                        title: .localizedSortAZ,
                        shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                    ),
                    AppMenuCommandItem(
                        id: AppCommandID.Cards.sortZA,
                        title: .localizedSortZA,
                        shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                    )
                ]
            case .sharedBalances:
                return [
                    AppMenuCommandItem(
                        id: AppCommandID.SharedBalances.sortAZ,
                        title: .localizedSortAZ,
                        shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                    ),
                    AppMenuCommandItem(
                        id: AppCommandID.SharedBalances.sortZA,
                        title: .localizedSortZA,
                        shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                    ),
                    AppMenuCommandItem(
                        id: AppCommandID.SharedBalances.sortAmountAsc,
                        title: .localizedSortAmountAsc,
                        shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                    ),
                    AppMenuCommandItem(
                        id: AppCommandID.SharedBalances.sortAmountDesc,
                        title: .localizedSortAmountDesc,
                        shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                    )
                ]
            }
        case .savings:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortAmountAsc,
                        title: .localizedSortAmountAsc,
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortAmountDesc,
                        title: .localizedSortAmountDesc,
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortDateAsc,
                        title: .localizedSortDateAsc,
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.Savings.sortDateDesc,
                        title: .localizedSortDateDesc,
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                )
            ]
        case .budgetDetail:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortAmountAsc,
                        title: .localizedSortAmountAsc,
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortAmountDesc,
                        title: .localizedSortAmountDesc,
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortDateAsc,
                        title: .localizedSortDateAsc,
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.BudgetDetail.sortDateDesc,
                        title: .localizedSortDateDesc,
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                ),
            ] + expenseDisplayItems
        case .cardDetail:
            return [
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortAZ,
                        title: .localizedSortAZ,
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortZA,
                        title: .localizedSortZA,
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortAmountAsc,
                        title: .localizedSortAmountAsc,
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortAmountDesc,
                        title: .localizedSortAmountDesc,
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortDateAsc,
                        title: .localizedSortDateAsc,
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                    AppMenuCommandItem(
                        id: AppCommandID.CardDetail.sortDateDesc,
                        title: .localizedSortDateDesc,
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                ),
            ] + expenseDisplayItems
        case .none, .income:
            return []
        }
    }

    private var expenseDisplayItems: [AppMenuCommandItem] {
        [
            AppMenuCommandItem(
                id: AppCommandID.ExpenseDisplay.toggleHideFuturePlanned,
                title: "Toggle Hide Future Planned Expenses",
                shortcut: KeyboardShortcut("1", modifiers: [.control, .shift])
            ),
            AppMenuCommandItem(
                id: AppCommandID.ExpenseDisplay.toggleExcludeFuturePlanned,
                title: "Toggle Exclude Future Planned Expenses from Totals",
                shortcut: KeyboardShortcut("2", modifiers: [.control, .shift])
            ),
            AppMenuCommandItem(
                id: AppCommandID.ExpenseDisplay.toggleHideFutureVariable,
                title: "Toggle Hide Future Variable Expenses",
                shortcut: KeyboardShortcut("3", modifiers: [.control, .shift])
            ),
            AppMenuCommandItem(
                id: AppCommandID.ExpenseDisplay.toggleExcludeFutureVariable,
                title: "Toggle Exclude Future Variable Expenses from Totals",
                shortcut: KeyboardShortcut("4", modifiers: [.control, .shift])
            ),
        ]
    }

    @ViewBuilder
    private func commandButton(for item: AppMenuCommandItem) -> some View {
        if let role = item.role {
            Button(role: role) {
                dispatch(item.id)
            } label: {
                Text(item.title)
            }
            .keyboardShortcut(item.shortcut)
            .disabled(!item.isEnabled)
        } else {
            Button {
                dispatch(item.id)
            } label: {
                Text(item.title)
            }
            .keyboardShortcut(item.shortcut)
            .disabled(!item.isEnabled)
        }
    }

    private var currentSurface: AppCommandSurface {
        commandHub?.surface ?? .none
    }

    private var currentAvailability: AppCommandAvailability {
        commandHub?.availability ?? .init()
    }

    private func dispatch(_ commandID: String) {
        commandHub?.dispatch(commandID)
    }

    private func openNewWindow() {
        let sectionRaw = commandHub?.activeSectionRaw ?? AppSection.home.rawValue
        openWindow(value: AppWindowContext(sectionRawValue: sectionRaw))
    }
}
