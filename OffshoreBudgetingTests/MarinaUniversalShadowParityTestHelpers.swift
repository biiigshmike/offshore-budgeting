import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaShadowParityHarness {
    let snapshot: MarinaWorkspaceSnapshot
    let planner: MarinaQueryPlanner
    let legacyExecutor: MarinaQueryExecutor
    let bridge: MarinaSemanticUniversalPlanBridge
    let universalRunner: MarinaUniversalQueryRunner

    init(snapshot: MarinaWorkspaceSnapshot, context: MarinaUniversalPlanningContext) {
        let formulaRegistry = MarinaFormulaRegistry(now: context.now, calendar: context.calendar)
        self.snapshot = snapshot
        self.planner = MarinaQueryPlanner(calendar: context.calendar)
        self.legacyExecutor = MarinaQueryExecutor(calendar: context.calendar)
        self.bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        self.universalRunner = MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry)
    }

    func runLegacy(
        request: MarinaSemanticRequest,
        context: MarinaUniversalPlanningContext
    ) -> MarinaExecutionResult {
        let plan = planner.plan(
            request: request,
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now
        )
        return legacyExecutor.execute(plan: plan, snapshot: snapshot)
    }

    func runUniversal(
        request: MarinaSemanticRequest,
        context: MarinaUniversalPlanningContext
    ) -> MarinaUniversalQueryResult {
        switch bridge.makePlan(from: request, planningContext: context) {
        case let .plan(plan):
            return universalRunner.runFormulaAware(plan: plan, snapshot: snapshot)
        case let .unsupported(reason):
            return .unsupported(reason)
        }
    }
}

enum MarinaLegacyAmountSelection {
    case first
    case last
    case index(Int)
}

enum MarinaComparableFact: Equatable {
    case money(Double)
    case integer(Int)
    case text(String)
    case date(Date)
    case rows([MarinaComparableRow])
    case groups([MarinaComparableGroup])
    case unsupported(MarinaCapabilityFailureReason)
}

struct MarinaComparableRow: Equatable {
    let entity: MarinaSemanticEntity
    let id: UUID?
    let displayName: String
    let amount: Double?
    let date: Date?
    let categoryName: String?
    let cardName: String?
}

struct MarinaComparableGroup: Equatable {
    let displayName: String
    let amount: Double?
    let count: Int?
}

extension MarinaShadowParityHarness {
    func legacyMoneyFact(
        from result: MarinaExecutionResult,
        selection: MarinaLegacyAmountSelection = .first
    ) -> MarinaComparableFact? {
        let amounts = result.rows.compactMap(\.amount)
        let amount: Double?
        switch selection {
        case .first:
            amount = amounts.first
        case .last:
            amount = amounts.last
        case let .index(index):
            amount = amounts.indices.contains(index) ? amounts[index] : nil
        }

        guard let amount else {
            Issue.record("Expected a typed legacy amount in rows for \(result.title).")
            return nil
        }
        return .money(amount)
    }

    func universalMoneyFact(from result: MarinaUniversalQueryResult) -> MarinaComparableFact? {
        guard case let .metric(metric) = result,
              let amount = moneyValue(metric.value) else {
            Issue.record("Expected a universal metric money result, got \(result).")
            return nil
        }
        return .money(amount)
    }

    func legacyRowsFact(from result: MarinaExecutionResult) -> MarinaComparableFact {
        let rows = result.rows.compactMap { row -> MarinaComparableRow? in
            guard row.sourceID != nil || row.objectType != nil else {
                return nil
            }
            return MarinaComparableRow(
                entity: semanticEntity(for: row.objectType),
                id: row.sourceID,
                displayName: legacyDisplayName(for: row),
                amount: row.amount,
                date: row.date,
                categoryName: nil,
                cardName: nil
            )
        }
        return .rows(rows)
    }

    func universalRowsFact(
        from result: MarinaUniversalQueryResult,
        request: MarinaSemanticRequest
    ) -> MarinaComparableFact? {
        let rows: [MarinaQueryableRow]
        switch result {
        case let .rows(resultRows):
            rows = resultRows
        case let .rowsPage(page):
            rows = page.rows
        case .metric, .groups, .unsupported:
            Issue.record("Expected universal rows, got \(result).")
            return nil
        }

        return .rows(rows.map { row in
            MarinaComparableRow(
                entity: row.entity,
                id: row.id,
                displayName: row.displayName,
                amount: amount(for: row, request: request),
                date: date(for: row),
                categoryName: row.relationships[.category]?.displayName,
                cardName: row.relationships[.card]?.displayName
            )
        })
    }

    func legacyGroupsFact(from result: MarinaExecutionResult) -> MarinaComparableFact {
        let groups = result.rows.compactMap { row -> MarinaComparableGroup? in
            guard let amount = row.amount else {
                return nil
            }
            return MarinaComparableGroup(displayName: row.title, amount: amount, count: nil)
        }
        return .groups(groups)
    }

    func universalGroupsFact(from result: MarinaUniversalQueryResult) -> MarinaComparableFact? {
        guard case let .groups(groups) = result else {
            Issue.record("Expected universal groups, got \(result).")
            return nil
        }

        return .groups(groups.map { group in
            MarinaComparableGroup(
                displayName: group.group.displayName,
                amount: group.aggregate.flatMap(moneyValue),
                count: group.group.rows.count
            )
        })
    }

    private func semanticEntity(for objectType: MarinaLookupObjectType?) -> MarinaSemanticEntity {
        switch objectType {
        case .budget:
            return .budget
        case .plannedExpense:
            return .plannedExpense
        case .variableExpense:
            return .variableExpense
        case .income, .incomeSeries:
            return .income
        case .category:
            return .category
        case .preset:
            return .preset
        case .card:
            return .card
        case .savingsAccount, .savingsLedgerEntry:
            return .savingsAccount
        case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
            return .reconciliationAccount
        case .workspace:
            return .workspace
        case .importMerchantRule, .assistantAliasRule, .unknown, nil:
            return .variableExpense
        }
    }

    private func legacyDisplayName(for row: HomeAnswerRow) -> String {
        if row.objectType == .plannedExpense,
           row.sourceID != nil,
           row.amount != nil,
           row.date != nil,
           row.title.caseInsensitiveCompare("Expense") == .orderedSame {
            return row.value
        }
        return row.title
    }

    private func amount(for row: MarinaQueryableRow, request: MarinaSemanticRequest) -> Double? {
        let preferredFields: [MarinaFieldKey]
        switch request.measure {
        case .budgetImpact:
            preferredFields = [.budgetImpact]
        case .effectiveAmount:
            preferredFields = [.effectiveAmount]
        case .incomeAmount:
            preferredFields = [.incomeAmount]
        case .amount:
            preferredFields = [.amount]
        case .plannedAmount:
            preferredFields = [.plannedAmount]
        case .actualAmount:
            preferredFields = [.actualAmount]
        case .savingsTotal,
             .reconciliationBalance,
             .categoryAvailability,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .concentration,
             .color,
             .name,
             nil:
            preferredFields = []
        }

        for field in preferredFields + [.budgetImpact, .effectiveAmount, .incomeAmount, .amount, .plannedAmount, .actualAmount] {
            if let amount = moneyValue(row.fields[field]) {
                return amount
            }
        }
        return nil
    }

    private func date(for row: MarinaQueryableRow) -> Date? {
        for field in [MarinaFieldKey.date, .transactionDate, .expenseDate] {
            if case let .date(date)? = row.fields[field] {
                return date
            }
        }
        return nil
    }
}

func expectMoneyParity(
    _ legacy: MarinaComparableFact?,
    _ universal: MarinaComparableFact?,
    scenario: String,
    accuracy: Double = 0.01
) {
    guard case let .money(legacyAmount)? = legacy,
          case let .money(universalAmount)? = universal else {
        Issue.record("Expected money facts for \(scenario), got legacy \(String(describing: legacy)) and universal \(String(describing: universal)).")
        return
    }

    #expect(abs(legacyAmount - universalAmount) <= accuracy, "\(scenario) money mismatch: legacy \(legacyAmount), universal \(universalAmount)")
}

func expectRowParity(
    _ legacy: MarinaComparableFact,
    _ universal: MarinaComparableFact?,
    scenario: String,
    accuracy: Double = 0.01
) {
    guard case let .rows(legacyRows) = legacy,
          case let .rows(universalRows)? = universal else {
        Issue.record("Expected row facts for \(scenario), got legacy \(legacy) and universal \(String(describing: universal)).")
        return
    }

    #expect(legacyRows.count == universalRows.count, "\(scenario) row count mismatch.")
    for (legacyRow, universalRow) in zip(legacyRows, universalRows) {
        #expect(legacyRow.id == universalRow.id, "\(scenario) row id mismatch for \(legacyRow.displayName).")
        #expect(legacyRow.entity == universalRow.entity, "\(scenario) row entity mismatch for \(legacyRow.displayName).")
        #expect(legacyRow.displayName == universalRow.displayName, "\(scenario) row display name mismatch.")
        expectOptionalMoney(legacyRow.amount, universalRow.amount, scenario: "\(scenario) row \(legacyRow.displayName)", accuracy: accuracy)
        #expect(legacyRow.date == universalRow.date, "\(scenario) row date mismatch for \(legacyRow.displayName).")

        if let legacyCategory = legacyRow.categoryName, let universalCategory = universalRow.categoryName {
            #expect(legacyCategory == universalCategory, "\(scenario) row category mismatch for \(legacyRow.displayName).")
        }
        if let legacyCard = legacyRow.cardName, let universalCard = universalRow.cardName {
            #expect(legacyCard == universalCard, "\(scenario) row card mismatch for \(legacyRow.displayName).")
        }
    }
}

func expectUnorderedGroupParity(
    _ legacy: MarinaComparableFact,
    _ universal: MarinaComparableFact?,
    scenario: String,
    accuracy: Double = 0.01
) {
    guard case let .groups(legacyGroups) = legacy,
          case let .groups(universalGroups)? = universal else {
        Issue.record("Expected group facts for \(scenario), got legacy \(legacy) and universal \(String(describing: universal)).")
        return
    }

    let sortedLegacy = legacyGroups.sorted { $0.displayName < $1.displayName }
    let sortedUniversal = universalGroups.sorted { $0.displayName < $1.displayName }

    #expect(sortedLegacy.count == sortedUniversal.count, "\(scenario) group count mismatch.")
    for (legacyGroup, universalGroup) in zip(sortedLegacy, sortedUniversal) {
        #expect(legacyGroup.displayName == universalGroup.displayName, "\(scenario) group label mismatch.")
        expectOptionalMoney(legacyGroup.amount, universalGroup.amount, scenario: "\(scenario) group \(legacyGroup.displayName)", accuracy: accuracy)
        if let legacyCount = legacyGroup.count, let universalCount = universalGroup.count {
            #expect(legacyCount == universalCount, "\(scenario) group count mismatch for \(legacyGroup.displayName).")
        }
    }
}

private func expectOptionalMoney(
    _ legacy: Double?,
    _ universal: Double?,
    scenario: String,
    accuracy: Double
) {
    switch (legacy, universal) {
    case let (legacy?, universal?):
        #expect(abs(legacy - universal) <= accuracy, "\(scenario) amount mismatch: legacy \(legacy), universal \(universal)")
    case (nil, nil):
        break
    case let (legacy, universal):
        Issue.record("\(scenario) optional amount mismatch: legacy \(String(describing: legacy)), universal \(String(describing: universal)).")
    }
}

private func moneyValue(_ value: MarinaValue?) -> Double? {
    switch value {
    case let .money(value)?:
        return value
    case let .number(value)?:
        return value
    case let .integer(value)?:
        return Double(value)
    case .text, .date, .boolean, .colorHex, .empty, nil:
        return nil
    }
}
