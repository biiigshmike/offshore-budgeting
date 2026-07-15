import Foundation

struct MarinaWorkspaceAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .workspace

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspace = snapshot.workspace
        return [
            MarinaQueryableRow(
                id: workspace.id,
                entity: entity,
                displayName: displayName(workspace.name, fallbackID: workspace.id),
                fields: [
                    .id: .text(workspace.id.uuidString),
                    .name: .text(workspace.name),
                    .color: .colorHex(workspace.hexColor)
                ],
                relationships: [:]
            )
        ]
    }
}

struct MarinaVariableExpenseAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .variableExpense

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        rows(for: snapshot.variableExpenses, from: snapshot)
    }

    func calculationRows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        rows(for: snapshot.homeCalculationVariableExpenses, from: snapshot)
    }

    private func rows(
        for expenses: [VariableExpense],
        from snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return expenses.compactMap { expense in
            guard isInWorkspace(expense.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: expense.id,
                entity: entity,
                displayName: displayName(expense.descriptionText, fallbackID: expense.id),
                fields: [
                    .id: .text(expense.id.uuidString),
                    .descriptionText: .text(expense.descriptionText),
                    .merchantText: .text(expense.descriptionText),
                    .amount: .money(expense.amount),
                    .budgetImpact: .money(SavingsMathService.variableBudgetImpactAmount(for: expense)),
                    .ledgerSignedAmount: .money(expense.ledgerSignedAmount()),
                    .kind: .text(expense.kind.rawValue),
                    .date: .date(expense.transactionDate),
                    .transactionDate: .date(expense.transactionDate)
                ],
                relationships: expenseRelationships(
                    selectedWorkspace: snapshot.workspace,
                    card: expense.card,
                    category: expense.category,
                    allocationAccount: expense.allocation?.account,
                    savingsAccount: expense.savingsLedgerEntry?.account,
                    workspaceID: workspaceID
                )
            )
        }
    }
}

struct MarinaPlannedExpenseAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .plannedExpense

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        rows(for: snapshot.plannedExpenses, from: snapshot)
    }

    func calculationRows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        rows(for: snapshot.homeCalculationPlannedExpenses, from: snapshot)
    }

    private func rows(
        for expenses: [PlannedExpense],
        from snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return expenses.compactMap { expense in
            guard isInWorkspace(expense.workspace, workspaceID: workspaceID) else { return nil }
            var relationships = expenseRelationships(
                selectedWorkspace: snapshot.workspace,
                card: expense.card,
                category: expense.category,
                allocationAccount: expense.allocation?.account,
                savingsAccount: expense.savingsLedgerEntry?.account,
                workspaceID: workspaceID
            )

            if let sourcePresetID = expense.sourcePresetID,
               let preset = snapshot.presets.first(where: {
                   $0.id == sourcePresetID && isInWorkspace($0.workspace, workspaceID: workspaceID)
               }) {
                relationships[.preset] = relationship(.preset, targetEntity: .preset, id: preset.id, displayName: preset.title)
            }

            if let sourceBudgetID = expense.sourceBudgetID,
               let budget = snapshot.budgets.first(where: {
                   $0.id == sourceBudgetID && isInWorkspace($0.workspace, workspaceID: workspaceID)
               }) {
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
                    .projectedBudgetImpact: .money(SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense)),
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
        variableAdapter.calculationRows(from: snapshot) + plannedAdapter.calculationRows(from: snapshot)
    }
}

struct MarinaSavingsAccountAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .savingsAccount

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.savingsAccounts.compactMap { account in
            guard isInWorkspace(account.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
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
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaSavingsLedgerEntryAdapter {
    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.savingsEntries.compactMap { entry in
            guard isInWorkspace(entry.workspace, workspaceID: workspaceID) else { return nil }
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
                    selectedWorkspace: snapshot.workspace,
                    account: entry.account,
                    variableExpense: entry.variableExpense,
                    plannedExpense: entry.plannedExpense,
                    workspaceID: workspaceID
                )
            )
        }
    }
}

struct MarinaReconciliationAccountAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .reconciliationAccount

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.reconciliationAccounts.compactMap { account in
            guard isInWorkspace(account.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: account.id,
                entity: entity,
                displayName: displayName(account.name, fallbackID: account.id),
                fields: [
                    .id: .text(account.id.uuidString),
                    .name: .text(account.name),
                    .color: .colorHex(account.hexColor),
                    .archivedState: .boolean(account.isArchived)
                ],
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaReconciliationLedgerEntryAdapter {
    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        let allocationRows = snapshot.expenseAllocations.compactMap { allocation -> MarinaQueryableRow? in
            guard isInWorkspace(allocation.workspace, workspaceID: workspaceID) else { return nil }
            let variableExpense = selectedWorkspaceObject(allocation.expense, workspaceID: workspaceID)
            let plannedExpense = selectedWorkspaceObject(allocation.plannedExpense, workspaceID: workspaceID)
            let date = variableExpense?.transactionDate
                ?? plannedExpense?.expenseDate
                ?? allocation.createdAt
            let note = variableExpense?.descriptionText
                ?? plannedExpense?.title
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
                    selectedWorkspace: snapshot.workspace,
                    account: allocation.account,
                    variableExpense: variableExpense,
                    plannedExpense: plannedExpense,
                    workspaceID: workspaceID
                )
            )
        }

        let settlementRows = snapshot.allocationSettlements.compactMap { settlement -> MarinaQueryableRow? in
            guard isInWorkspace(settlement.workspace, workspaceID: workspaceID) else { return nil }
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
                    selectedWorkspace: snapshot.workspace,
                    account: settlement.account,
                    variableExpense: settlement.expense,
                    plannedExpense: settlement.plannedExpense,
                    workspaceID: workspaceID
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
        let workspaceID = snapshot.workspace.id
        return snapshot.incomes.compactMap { income in
            guard isInWorkspace(income.workspace, workspaceID: workspaceID) else { return nil }
            var relationships = baseRelationships(selectedWorkspace: snapshot.workspace)
            if let card = selectedWorkspaceObject(income.card, workspaceID: workspaceID) {
                relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
            }
            if let series = selectedWorkspaceObject(income.series, workspaceID: workspaceID) {
                relationships[.incomeSeries] = relationship(
                    .incomeSeries,
                    targetEntity: .incomeSeries,
                    id: series.id,
                    displayName: series.source
                )
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
                    .isPlanned: .boolean(income.isPlanned),
                    .isException: .boolean(income.isException)
                ],
                relationships: relationships
            )
        }
    }
}

struct MarinaIncomeSeriesAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .incomeSeries

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.incomeSeries.compactMap { series in
            guard isInWorkspace(series.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: series.id,
                entity: entity,
                displayName: displayName(series.source, fallbackID: series.id),
                fields: [
                    .id: .text(series.id.uuidString),
                    .source: .text(series.source),
                    .amount: .money(series.amount),
                    .incomeAmount: .money(series.amount),
                    .isPlanned: .boolean(series.isPlanned),
                    .frequency: .text(series.frequencyRaw),
                    .interval: .integer(series.interval),
                    .weeklyWeekday: .integer(series.weeklyWeekday),
                    .monthlyDayOfMonth: .integer(series.monthlyDayOfMonth),
                    .monthlyIsLastDay: .boolean(series.monthlyIsLastDay),
                    .yearlyMonth: .integer(series.yearlyMonth),
                    .yearlyDayOfMonth: .integer(series.yearlyDayOfMonth),
                    .startDate: .date(series.startDate),
                    .endDate: .date(series.endDate)
                ],
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaCategoryAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .category

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.categories.compactMap { category in
            guard isInWorkspace(category.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: category.id,
                entity: entity,
                displayName: displayName(category.name, fallbackID: category.id),
                fields: [
                    .id: .text(category.id.uuidString),
                    .name: .text(category.name),
                    .color: .colorHex(category.hexColor),
                    .archivedState: .boolean(category.isArchived)
                ],
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaCardAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .card

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.cards.compactMap { card in
            guard isInWorkspace(card.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: card.id,
                entity: entity,
                displayName: displayName(card.name, fallbackID: card.id),
                fields: [
                    .id: .text(card.id.uuidString),
                    .name: .text(card.name)
                ],
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaBudgetAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .budget

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        return snapshot.budgets.compactMap { budget in
            guard isInWorkspace(budget.workspace, workspaceID: workspaceID) else { return nil }
            return MarinaQueryableRow(
                id: budget.id,
                entity: entity,
                displayName: displayName(budget.name, fallbackID: budget.id),
                fields: [
                    .id: .text(budget.id.uuidString),
                    .name: .text(budget.name),
                    .startDate: .date(budget.startDate),
                    .endDate: .date(budget.endDate)
                ],
                relationships: baseRelationships(selectedWorkspace: snapshot.workspace)
            )
        }
    }
}

struct MarinaPresetAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .preset

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        let workspaceID = snapshot.workspace.id
        let availableBudgetIDs = Set(snapshot.budgets.compactMap { budget in
            isInWorkspace(budget.workspace, workspaceID: workspaceID) ? budget.id : nil
        })
        return snapshot.presets.compactMap { preset in
            guard isInWorkspace(preset.workspace, workspaceID: workspaceID) else { return nil }
            var relationships = baseRelationships(selectedWorkspace: snapshot.workspace)
            if let card = selectedWorkspaceObject(preset.defaultCard, workspaceID: workspaceID) {
                relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
            }
            if let category = selectedWorkspaceObject(preset.defaultCategory, workspaceID: workspaceID) {
                relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
            }

            var seenBudgetIDs = Set<UUID>()
            let linkedBudgets = (preset.budgetPresetLinks ?? []).compactMap { link -> MarinaResolvedRelationship? in
                guard link.preset?.id == preset.id,
                      isInWorkspace(link.preset?.workspace, workspaceID: workspaceID),
                      let budget = link.budget,
                      isInWorkspace(budget.workspace, workspaceID: workspaceID),
                      availableBudgetIDs.contains(budget.id),
                      seenBudgetIDs.insert(budget.id).inserted else {
                    return nil
                }
                return relationship(.budget, targetEntity: .budget, id: budget.id, displayName: budget.name)
            }

            return MarinaQueryableRow(
                id: preset.id,
                entity: entity,
                displayName: displayName(preset.title, fallbackID: preset.id),
                fields: [
                    .id: .text(preset.id.uuidString),
                    .title: .text(preset.title),
                    .plannedAmount: .money(preset.plannedAmount),
                    .frequency: .text(preset.frequencyRaw),
                    .interval: .integer(preset.interval),
                    .weeklyWeekday: .integer(preset.weeklyWeekday),
                    .monthlyDayOfMonth: .integer(preset.monthlyDayOfMonth),
                    .monthlyIsLastDay: .boolean(preset.monthlyIsLastDay),
                    .yearlyMonth: .integer(preset.yearlyMonth),
                    .yearlyDayOfMonth: .integer(preset.yearlyDayOfMonth),
                    .archivedState: .boolean(preset.isArchived)
                ],
                relationships: relationships,
                relationshipCollections: [.budget: linkedBudgets]
            )
        }
    }
}

private func displayName(_ value: String, fallbackID: UUID) -> String {
    value.isEmpty ? fallbackID.uuidString : value
}

private func baseRelationships(selectedWorkspace workspace: Workspace) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    return [
        .workspace: relationship(.workspace, targetEntity: .workspace, id: workspace.id, displayName: workspace.name)
    ]
}

private func expenseRelationships(
    selectedWorkspace: Workspace,
    card: Card?,
    category: Category?,
    allocationAccount: AllocationAccount?,
    savingsAccount: SavingsAccount?,
    workspaceID: UUID
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(selectedWorkspace: selectedWorkspace)

    if let card = selectedWorkspaceObject(card, workspaceID: workspaceID) {
        relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
    }

    if let category = selectedWorkspaceObject(category, workspaceID: workspaceID) {
        relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
    }

    if let allocationAccount = selectedWorkspaceObject(allocationAccount, workspaceID: workspaceID) {
        relationships[.reconciliationAccount] = relationship(
            .reconciliationAccount,
            targetEntity: .reconciliationAccount,
            id: allocationAccount.id,
            displayName: allocationAccount.name
        )
    }

    if let savingsAccount = selectedWorkspaceObject(savingsAccount, workspaceID: workspaceID) {
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
    selectedWorkspace: Workspace,
    account: SavingsAccount?,
    variableExpense: VariableExpense?,
    plannedExpense: PlannedExpense?,
    workspaceID: UUID
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(selectedWorkspace: selectedWorkspace)

    if let account = selectedWorkspaceObject(account, workspaceID: workspaceID) {
        relationships[.savingsAccount] = relationship(
            .savingsAccount,
            targetEntity: .savingsAccount,
            id: account.id,
            displayName: account.name
        )
    }

    if let variableExpense = selectedWorkspaceObject(variableExpense, workspaceID: workspaceID) {
        relationships[.variableExpense] = relationship(
            .variableExpense,
            targetEntity: .variableExpense,
            id: variableExpense.id,
            displayName: variableExpense.descriptionText
        )
    }

    if let plannedExpense = selectedWorkspaceObject(plannedExpense, workspaceID: workspaceID) {
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
    selectedWorkspace: Workspace,
    account: AllocationAccount?,
    variableExpense: VariableExpense?,
    plannedExpense: PlannedExpense?,
    workspaceID: UUID
) -> [MarinaRelationshipKey: MarinaResolvedRelationship] {
    var relationships = baseRelationships(selectedWorkspace: selectedWorkspace)

    if let account = selectedWorkspaceObject(account, workspaceID: workspaceID) {
        relationships[.reconciliationAccount] = relationship(
            .reconciliationAccount,
            targetEntity: .reconciliationAccount,
            id: account.id,
            displayName: account.name
        )
    }

    if let variableExpense = selectedWorkspaceObject(variableExpense, workspaceID: workspaceID) {
        relationships[.variableExpense] = relationship(
            .variableExpense,
            targetEntity: .variableExpense,
            id: variableExpense.id,
            displayName: variableExpense.descriptionText
        )
        addExpenseRelationships(
            card: variableExpense.card,
            category: variableExpense.category,
            workspaceID: workspaceID,
            to: &relationships
        )
    }

    if let plannedExpense = selectedWorkspaceObject(plannedExpense, workspaceID: workspaceID) {
        relationships[.plannedExpense] = relationship(
            .plannedExpense,
            targetEntity: .plannedExpense,
            id: plannedExpense.id,
            displayName: plannedExpense.title
        )
        addExpenseRelationships(
            card: plannedExpense.card,
            category: plannedExpense.category,
            workspaceID: workspaceID,
            to: &relationships
        )
    }

    return relationships
}

private func addExpenseRelationships(
    card: Card?,
    category: Category?,
    workspaceID: UUID,
    to relationships: inout [MarinaRelationshipKey: MarinaResolvedRelationship]
) {
    if let card = selectedWorkspaceObject(card, workspaceID: workspaceID) {
        relationships[.card] = relationship(.card, targetEntity: .card, id: card.id, displayName: card.name)
    }

    if let category = selectedWorkspaceObject(category, workspaceID: workspaceID) {
        relationships[.category] = relationship(.category, targetEntity: .category, id: category.id, displayName: category.name)
    }
}

private protocol MarinaWorkspaceOwned {
    var workspace: Workspace? { get }
}

extension Card: MarinaWorkspaceOwned {}
extension Category: MarinaWorkspaceOwned {}
extension Preset: MarinaWorkspaceOwned {}
extension Budget: MarinaWorkspaceOwned {}
extension VariableExpense: MarinaWorkspaceOwned {}
extension PlannedExpense: MarinaWorkspaceOwned {}
extension AllocationAccount: MarinaWorkspaceOwned {}
extension SavingsAccount: MarinaWorkspaceOwned {}
extension IncomeSeries: MarinaWorkspaceOwned {}

private func selectedWorkspaceObject<Object: MarinaWorkspaceOwned>(
    _ object: Object?,
    workspaceID: UUID
) -> Object? {
    guard let object, isInWorkspace(object.workspace, workspaceID: workspaceID) else {
        return nil
    }
    return object
}

private func isInWorkspace(_ workspace: Workspace?, workspaceID: UUID) -> Bool {
    workspace?.id == workspaceID
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
