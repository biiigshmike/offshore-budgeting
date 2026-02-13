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
    enum Help {
        static let openHelp = "help.open_help"
    }

    enum Budgets {
        static let newBudget = "budgets.new_budget"
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
}

// MARK: - Surface

enum AppCommandSurface: Equatable {
    case none
    case budgets
    case budgetDetail
    case income
    case cards
    case cardDetail
}

// MARK: - Availability

struct AppCommandAvailability: Equatable {
    var budgetDetailCanCreateTransaction: Bool = false
    var incomeCanDeleteActual: Bool = false
    var incomeCanDeletePlanned: Bool = false
}

// MARK: - Hub

@MainActor
final class AppCommandHub: ObservableObject {
    @Published private(set) var surface: AppCommandSurface = .none
    @Published private(set) var availability: AppCommandAvailability = .init()
    @Published private(set) var sequence: Int = 0
    private(set) var latestCommandID: String = ""

    func activate(_ surface: AppCommandSurface) {
        guard self.surface != surface else { return }
        self.surface = surface
    }

    func deactivate(_ surface: AppCommandSurface) {
        guard self.surface == surface else { return }
        self.surface = .none
    }

    func setBudgetDetailCanCreateTransaction(_ canCreate: Bool) {
        guard availability.budgetDetailCanCreateTransaction != canCreate else { return }
        availability.budgetDetailCanCreateTransaction = canCreate
    }

    func setIncomeDeletionAvailability(canDeleteActual: Bool, canDeletePlanned: Bool) {
        guard availability.incomeCanDeleteActual != canDeleteActual
                || availability.incomeCanDeletePlanned != canDeletePlanned else { return }

        availability.incomeCanDeleteActual = canDeleteActual
        availability.incomeCanDeletePlanned = canDeletePlanned
    }

    func dispatch(_ commandID: String) {
        latestCommandID = commandID
        sequence += 1
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
    let title: String
    let shortcut: KeyboardShortcut?
    let isEnabled: Bool
    let role: ButtonRole?

    init(
        id: String,
        title: String,
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

// MARK: - Commands

struct OffshoreAppCommands: Commands {
    @ObservedObject var commandHub: AppCommandHub
    let showsCustomHelpCommand: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            if fileItems.isEmpty {
                Button("New") { }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(true)
            } else {
                ForEach(fileItems) { item in
                    commandButton(for: item)
                }
            }
        }

        if showsCustomHelpCommand {
            CommandGroup(after: .help) {
                ForEach(helpItems) { item in
                    commandButton(for: item)
                }
            }
        }

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
        switch commandHub.surface {
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
                    title: "New Transaction",
                    shortcut: KeyboardShortcut("n", modifiers: [.command]),
                    isEnabled: commandHub.availability.budgetDetailCanCreateTransaction
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
        case .cardDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.newTransaction,
                    title: "New Transaction",
                    shortcut: KeyboardShortcut("n", modifiers: [.command])
                )
            ]
        case .none:
            return []
        }
    }

    private var editItems: [AppMenuCommandItem] {
        switch commandHub.surface {
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
                    isEnabled: commandHub.availability.incomeCanDeleteActual,
                    role: .destructive
                ),
                AppMenuCommandItem(
                    id: AppCommandID.Income.deletePlanned,
                    title: "Delete Planned Income",
                    shortcut: KeyboardShortcut(.delete, modifiers: [.command, .shift]),
                    isEnabled: commandHub.availability.incomeCanDeletePlanned,
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
        case .none, .budgets, .cards:
            return []
        }
    }

    private var viewItems: [AppMenuCommandItem] {
        switch commandHub.surface {
        case .budgetDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortAZ,
                    title: "Sort A-Z",
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortZA,
                    title: "Sort Z-A",
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortAmountAsc,
                    title: "Sort $↑",
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortAmountDesc,
                    title: "Sort $↓",
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortDateAsc,
                    title: "Sort Date ↑",
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.BudgetDetail.sortDateDesc,
                    title: "Sort Date ↓",
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                )
            ]
        case .cardDetail:
            return [
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortAZ,
                    title: "Sort A-Z",
                    shortcut: KeyboardShortcut("1", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortZA,
                    title: "Sort Z-A",
                    shortcut: KeyboardShortcut("2", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortAmountAsc,
                    title: "Sort $↑",
                    shortcut: KeyboardShortcut("3", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortAmountDesc,
                    title: "Sort $↓",
                    shortcut: KeyboardShortcut("4", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortDateAsc,
                    title: "Sort Date ↑",
                    shortcut: KeyboardShortcut("5", modifiers: [.command, .option])
                ),
                AppMenuCommandItem(
                    id: AppCommandID.CardDetail.sortDateDesc,
                    title: "Sort Date ↓",
                    shortcut: KeyboardShortcut("6", modifiers: [.command, .option])
                )
            ]
        case .none, .budgets, .income, .cards:
            return []
        }
    }

    @ViewBuilder
    private func commandButton(for item: AppMenuCommandItem) -> some View {
        if let role = item.role {
            Button(item.title, role: role) {
                commandHub.dispatch(item.id)
            }
            .keyboardShortcut(item.shortcut)
            .disabled(!item.isEnabled)
        } else {
            Button(item.title) {
                commandHub.dispatch(item.id)
            }
            .keyboardShortcut(item.shortcut)
            .disabled(!item.isEnabled)
        }
    }
}
