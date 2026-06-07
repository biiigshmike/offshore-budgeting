import Foundation

struct MarinaVariableExpenseAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .variableExpense

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.variableExpenses.map { expense in
            MarinaQueryableRow(
                id: expense.id,
                entity: entity,
                displayName: displayName(expense.descriptionText, fallbackID: expense.id),
                fields: [
                    .id: .text(expense.id.uuidString),
                    .descriptionText: .text(expense.descriptionText),
                    .merchantText: .text(expense.descriptionText),
                    .amount: .money(expense.amount),
                    .budgetImpact: .money(SavingsMathService.variableBudgetImpactAmount(for: expense)),
                    .date: .date(expense.transactionDate),
                    .transactionDate: .date(expense.transactionDate)
                ],
                relationships: expenseRelationships(
                    workspace: expense.workspace,
                    card: expense.card,
                    category: expense.category,
                    allocationAccount: expense.allocation?.account,
                    savingsAccount: expense.savingsLedgerEntry?.account
                )
            )
        }
    }
}

struct MarinaPlannedExpenseAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .plannedExpense

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.plannedExpenses.map { expense in
            var relationships = expenseRelationships(
                workspace: expense.workspace,
                card: expense.card,
                category: expense.category,
                allocationAccount: expense.allocation?.account,
                savingsAccount: expense.savingsLedgerEntry?.account
            )

            if let sourcePresetID = expense.sourcePresetID,
               let preset = snapshot.presets.first(where: { $0.id == sourcePresetID }) {
                relationships[.preset] = relationship(.preset, targetEntity: .preset, id: preset.id, displayName: preset.title)
            }

            if let sourceBudgetID = expense.sourceBudgetID,
               let budget = snapshot.budgets.first(where: { $0.id == sourceBudgetID }) {
                relationships[.budget] = relationship(.budget, targetEntity: .budget, id: budget.id, displayName: budget.name)
            }

            return MarinaQueryableRow(
                id: expense.id,
                entity: entity,
                displayName: displayName(expense.title, fallbackID: expense.id),
                fields: [
                    .id: .text(expense.id.uuidString),
                    .title: .text(expense.title),
                    .merchantText: .text(expense.title),
                    .plannedAmount: .money(expense.plannedAmount),
                    .actualAmount: .money(expense.actualAmount),
                    .effectiveAmount: .money(expense.effectiveAmount()),
                    .budgetImpact: .money(SavingsMathService.plannedBudgetImpactAmount(for: expense)),
                    .date: .date(expense.expenseDate),
                    .expenseDate: .date(expense.expenseDate)
                ],
                relationships: relationships
            )
        }
    }
}

struct MarinaUnifiedExpenseAdapter {
    let variableAdapter: any MarinaEntityAdapter
    let plannedAdapter: any MarinaEntityAdapter

    init(
        variableAdapter: any MarinaEntityAdapter = MarinaVariableExpenseAdapter(),
        plannedAdapter: any MarinaEntityAdapter = MarinaPlannedExpenseAdapter()
    ) {
        self.variableAdapter = variableAdapter
        self.plannedAdapter = plannedAdapter
    }

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        variableAdapter.rows(from: snapshot) + plannedAdapter.rows(from: snapshot)
    }
}

struct MarinaSavingsAccountAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .savingsAccount

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.savingsAccounts.map { account in
            MarinaQueryableRow(
                id: account.id,
                entity: entity,
                displayName: displayName(account.name, fallbackID: account.id),
                fields: [
                    .id: .text(account.id.uuidString),
                    .name: .text(account.name),
                    .date: .date(account.createdAt),
                    .createdAt: .date(account.createdAt),
                    .updatedAt: .date(account.updatedAt)
                ],
                relationships: baseRelationships(workspace: account.workspace)
            )
        }
    }
}

struct MarinaSavingsLedgerEntryAdapter {
    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.savingsEntries.map { entry in
            let kind = entry.kind.rawValue
            var fields: [MarinaFieldKey: MarinaValue] = [
                .id: .text(entry.id.uuidString),
                .amount: .money(entry.amount),
                .date: .date(entry.date),
                .note: .text(entry.note),
                .kind: .text(kind),
                .createdAt: .date(entry.createdAt),
                .updatedAt: .date(entry.updatedAt)
            ]

            if let periodStartDate = entry.periodStartDate {
                fields[.startDate] = .date(periodStartDate)
            }
            if let periodEndDate = entry.periodEndDate {
                fields[.endDate] = .date(periodEndDate)
            }

            return MarinaQueryableRow(
                id: entry.id,
                entity: .savingsAccount,
                displayName: displayName(entry.note.isEmpty ? kind : entry.note, fallbackID: entry.id),
                fields: fields,
                relationships: savingsLedgerRelationships(
                    workspace: entry.workspace,
                    account: entry.account,
                    variableExpense: entry.variableExpense,
                    plannedExpense: entry.plannedExpense
                )
            )
        }
    }
}

struct MarinaReconciliationAccountAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .reconciliationAccount

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.reconciliationAccounts.map { account in
            MarinaQueryableRow(
                id: account.id,
                entity: entity,
                displayName: displayName(account.name, fallbackID: account.id),
                fields: [
                    .id: .text(account.id.uuidString),
                    .name: .text(account.name),
                    .color: .colorHex(account.hexColor),
                    .archivedState: .boolean(account.isArchived)
                ],
                relationships: baseRelationships(workspace: account.workspace)
            )
        }
    }
}

struct MarinaReconciliationLedgerEntryAdapter {
    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let allocationRows = snapshot.expenseAllocations.map { allocation in
            let date = allocation.expense?.transactionDate
                ?? allocation.plannedExpense?.expenseDate
                ?? allocation.createdAt
            let note = allocation.expense?.descriptionText
                ?? allocation.plannedExpense?.title
                ?? "Allocation"
            return MarinaQueryableRow(
                id: allocation.id,
                entity: .reconciliationAccount,
                displayName: displayName(note, fallbackID: allocation.id),
                fields: [
                    .id: .text(allocation.id.uuidString),
                    .amount: .money(allocation.allocatedAmount),
                    .date: .date(date),
                    .note: .text(note),
                    .kind: .text("allocation"),
                    .createdAt: .date(allocation.createdAt),
                    .updatedAt: .date(allocation.updatedAt)
                ],
                relationships: reconciliationLedgerRelationships(
                    workspace: allocation.workspace,
                    account: allocation.account,
                    variableExpense: allocation.expense,
                    plannedExpense: allocation.plannedExpense
                )
            )
        }

        let settlementRows = snapshot.allocationSettlements.map { settlement in
            let note = settlement.note.isEmpty ? "Settlement" : settlement.note
            return MarinaQueryableRow(
                id: settlement.id,
                entity: .reconciliationAccount,
                displayName: displayName(note, fallbackID: settlement.id),
                fields: [
                    .id: .text(settlement.id.uuidString),
                    .amount: .money(settlement.amount),
                    .date: .date(settlement.date),
                    .note: .text(note),
                    .kind: .text("settlement")
                ],
                relationships: reconciliationLedgerRelationships(
                    workspace: settlement.workspace,
                    account: settlement.account,
                    variableExpense: settlement.expense,
                    plannedExpense: settlement.plannedExpense
                )
            )
        }

        return (allocationRows + settlementRows).sorted { left, right in
            switch (left.fields[.date], right.fields[.date]) {
            case let (.date(leftDate)?, .date(rightDate)?):
                if leftDate != rightDate {
                    return leftDate < rightDate
                }
            default:
                break
            }
            return left.displayName < right.displayName
        }
    }
}

struct MarinaIncomeAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .income

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.incomes.map { income in
            var relationships = baseRelationships(workspace: income.workspace)
            if let card = income.card {
                relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
            }
            relationships[.incomeSource] = relationship(.incomeSource, targetEntity: nil, id: nil, displayName: income.source)

            return MarinaQueryableRow(
                id: income.id,
                entity: entity,
                displayName: displayName(income.source, fallbackID: income.id),
                fields: [
                    .id: .text(income.id.uuidString),
                    .source: .text(income.source),
                    .amount: .money(income.amount),
                    .incomeAmount: .money(income.amount),
                    .date: .date(income.date),
                    .isPlanned: .boolean(income.isPlanned)
                ],
                relationships: relationships
            )
        }
    }
}

struct MarinaCategoryAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .category

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.categories.map { category in
            MarinaQueryableRow(
                id: category.id,
                entity: entity,
                displayName: displayName(category.name, fallbackID: category.id),
                fields: [
                    .id: .text(category.id.uuidString),
                    .name: .text(category.name),
                    .color: .colorHex(category.hexColor),
                    .archivedState: .boolean(category.isArchived)
                ],
                relationships: baseRelationships(workspace: category.workspace)
            )
        }
    }
}

struct MarinaCardAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .card

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.cards.map { card in
            MarinaQueryableRow(
                id: card.id,
                entity: entity,
                displayName: displayName(card.name, fallbackID: card.id),
                fields: [
                    .id: .text(card.id.uuidString),
                    .name: .text(card.name)
                ],
                relationships: baseRelationships(workspace: card.workspace)
            )
        }
    }
}

struct MarinaBudgetAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .budget

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.budgets.map { budget in
            MarinaQueryableRow(
                id: budget.id,
                entity: entity,
                displayName: displayName(budget.name, fallbackID: budget.id),
                fields: [
                    .id: .text(budget.id.uuidString),
                    .name: .text(budget.name),
                    .startDate: .date(budget.startDate),
                    .endDate: .date(budget.endDate)
                ],
                relationships: baseRelationships(workspace: budget.workspace)
            )
        }
    }
}

struct MarinaPresetAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .preset

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        snapshot.presets.map { preset in
            var relationships = baseRelationships(workspace: preset.workspace)
            if let card = preset.defaultCard {
                relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
            }
            if let category = preset.defaultCategory {
                relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
            }

            return MarinaQueryableRow(
                id: preset.id,
                entity: entity,
                displayName: displayName(preset.title, fallbackID: preset.id),
                fields: [
                    .id: .text(preset.id.uuidString),
                    .title: .text(preset.title),
                    .plannedAmount: .money(preset.plannedAmount),
                    .archivedState: .boolean(preset.isArchived)
                ],
                relationships: relationships
            )
        }
    }
}

private func displayName(_ value: String, fallbackID: UUID) -> String {
    value.isEmpty ? fallbackID.uuidString : value
}

private func baseRelationships(workspace: Workspace?) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    guard let workspace else {
        return [:]
    }

    return [
        .workspace: relationship(.workspace, targetEntity: .workspace, id: workspace.id, displayName: workspace.name)
    ]
}

private func expenseRelationships(
    workspace: Workspace?,
    card: Card?,
    category: Category?,
    allocationAccount: AllocationAccount?,
    savingsAccount: SavingsAccount?
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(workspace: workspace)

    if let card {
        relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
    }

    if let category {
        relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
    }

    if let allocationAccount {
        relationships[.reconciliationAccount] = relationship(
            .reconciliationAccount,
            targetEntity: .reconciliationAccount,
            id: allocationAccount.id,
            displayName: allocationAccount.name
        )
    }

    if let savingsAccount {
        relationships[.savingsAccount] = relationship(
            .savingsAccount,
            targetEntity: .savingsAccount,
            id: savingsAccount.id,
            displayName: savingsAccount.name
        )
    }

    return relationships
}

private func savingsLedgerRelationships(
    workspace: Workspace?,
    account: SavingsAccount?,
    variableExpense: VariableExpense?,
    plannedExpense: PlannedExpense?
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(workspace: workspace)

    if let account {
        relationships[.savingsAccount] = relationship(
            .savingsAccount,
            targetEntity: .savingsAccount,
            id: account.id,
            displayName: account.name
        )
    }

    if let variableExpense {
        relationships[.variableExpense] = relationship(
            .variableExpense,
            targetEntity: .variableExpense,
            id: variableExpense.id,
            displayName: variableExpense.descriptionText
        )
    }

    if let plannedExpense {
        relationships[.plannedExpense] = relationship(
            .plannedExpense,
            targetEntity: .plannedExpense,
            id: plannedExpense.id,
            displayName: plannedExpense.title
        )
    }

    return relationships
}

private func reconciliationLedgerRelationships(
    workspace: Workspace?,
    account: AllocationAccount?,
    variableExpense: VariableExpense?,
    plannedExpense: PlannedExpense?
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(workspace: workspace)

    if let account {
        relationships[.reconciliationAccount] = relationship(
            .reconciliationAccount,
            targetEntity: .reconciliationAccount,
            id: account.id,
            displayName: account.name
        )
    }

    if let variableExpense {
        relationships[.variableExpense] = relationship(
            .variableExpense,
            targetEntity: .variableExpense,
            id: variableExpense.id,
            displayName: variableExpense.descriptionText
        )
        addExpenseRelationships(card: variableExpense.card, category: variableExpense.category, to: &relationships)
    }

    if let plannedExpense {
        relationships[.plannedExpense] = relationship(
            .plannedExpense,
            targetEntity: .plannedExpense,
            id: plannedExpense.id,
            displayName: plannedExpense.title
        )
        addExpenseRelationships(card: plannedExpense.card, category: plannedExpense.category, to: &relationships)
    }

    return relationships
}

private func addExpenseRelationships(
    card: Card?,
    category: Category?,
    to relationships: inout [MarinaRelationshipKey: MarinaResolvedRelationship]
) {
    if let card {
        relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
    }

    if let category {
        relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
    }
}

private func relationship(
    _ key: MarinaRelationshipKey,
    targetEntity: MarinaSemanticEntity?,
    id: UUID?,
    displayName: String?
) -> MarinaResolvedRelationship {
    MarinaResolvedRelationship(
        key: key,
        targetEntity: targetEntity,
        targetID: id,
        displayName: displayName
    )
}
