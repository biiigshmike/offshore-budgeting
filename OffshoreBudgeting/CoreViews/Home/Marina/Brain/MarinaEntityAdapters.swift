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
