import Foundation
import Testing
@testable import Offshore

struct MarinaSavingsReconciliationQueryRunnerTests {
    private let runner = MarinaUniversalQueryRunner()

    @Test func savingsAccountRowsListCountSearchAndSort() {
        let fixture = makeFixture()

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .list),
            snapshot: fixture.snapshot
        ))) == ["Emergency Fund", "Travel Savings"])

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .count),
            snapshot: fixture.snapshot
        )).value == .integer(2))

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .list,
                search: MarinaRowSearchClause(fields: [.name], query: "Emergency")
            ),
            snapshot: fixture.snapshot
        ))) == ["Emergency Fund"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.name), direction: .descending)]
            ),
            snapshot: fixture.snapshot
        ))) == ["Travel Savings", "Emergency Fund"])
    }

    @Test func savingsFormulaMeasuresReturnTypedUnsupported() {
        let fixture = makeFixture()

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .list, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .savingsLedgerEntries, operation: .sum, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))
    }

    @Test func savingsLedgerRowsSupportSearchFilterSortSumAverageAndGroup() {
        let fixture = makeFixture()

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .savingsLedgerEntries, operation: .list),
            snapshot: fixture.snapshot
        ))) == ["May reserve", "Emergency deposit", "Expense offset", "Travel deposit"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .list,
                search: MarinaRowSearchClause(fields: [.note, .kind], query: "offset")
            ),
            snapshot: fixture.snapshot
        ))) == ["Expense offset"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .list,
                filters: [
                    MarinaRowFilter(target: .relationship(.savingsAccount), operation: .equals, value: .text("Emergency Fund"))
                ]
            ),
            snapshot: fixture.snapshot
        ))) == ["May reserve", "Emergency deposit", "Expense offset"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .list,
                filters: juneDateFilters()
            ),
            snapshot: fixture.snapshot
        ))) == ["Emergency deposit", "Expense offset", "Travel deposit"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.amount), direction: .descending)]
            ),
            snapshot: fixture.snapshot
        ))) == ["Travel deposit", "Emergency deposit", "May reserve", "Expense offset"])

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .savingsLedgerEntries, operation: .sum, measure: .amount),
            snapshot: fixture.snapshot
        )).value == .money(350))

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .savingsLedgerEntries, operation: .average, measure: .amount),
            snapshot: fixture.snapshot
        )).value == .money(87.5))

        #expect(groupSummaries(requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .group,
                measure: .amount,
                groupBy: .relationship(.savingsAccount)
            ),
            snapshot: fixture.snapshot
        ))) == [
            GroupSummary(name: "Emergency Fund", aggregate: .money(150)),
            GroupSummary(name: "Travel Savings", aggregate: .money(200))
        ])
    }

    @Test func reconciliationAccountRowsListCountSearchAndSort() {
        let fixture = makeFixture()

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .reconciliationAccount, operation: .list),
            snapshot: fixture.snapshot
        ))) == ["Roommate", "Travel Kitty"])

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .reconciliationAccount, operation: .count),
            snapshot: fixture.snapshot
        )).value == .integer(2))

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .reconciliationAccount,
                operation: .list,
                search: MarinaRowSearchClause(fields: [.name], query: "room")
            ),
            snapshot: fixture.snapshot
        ))) == ["Roommate"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .reconciliationAccount,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.name), direction: .descending)]
            ),
            snapshot: fixture.snapshot
        ))) == ["Travel Kitty", "Roommate"])
    }

    @Test func reconciliationFormulaMeasuresReturnTypedUnsupported() {
        let fixture = makeFixture()

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .reconciliationAccount, operation: .list, measure: .reconciliationBalance),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .reconciliationLedgerEntries, operation: .sum, measure: .reconciliationBalance),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))
    }

    @Test func reconciliationLedgerRowsSupportSearchFilterSortSumAverageAndGroup() {
        let fixture = makeFixture()

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .reconciliationLedgerEntries, operation: .list),
            snapshot: fixture.snapshot
        ))) == ["May true-up", "Apple Store", "Paid back", "Hotel"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .list,
                search: MarinaRowSearchClause(fields: [.note, .kind], query: "paid")
            ),
            snapshot: fixture.snapshot
        ))) == ["Paid back"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .list,
                filters: [
                    MarinaRowFilter(target: .relationship(.reconciliationAccount), operation: .equals, value: .text("Roommate"))
                ]
            ),
            snapshot: fixture.snapshot
        ))) == ["May true-up", "Apple Store", "Paid back"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .list,
                filters: juneDateFilters()
            ),
            snapshot: fixture.snapshot
        ))) == ["Apple Store", "Paid back", "Hotel"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.amount), direction: .descending)]
            ),
            snapshot: fixture.snapshot
        ))) == ["Apple Store", "Hotel", "May true-up", "Paid back"])

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .reconciliationLedgerEntries, operation: .sum, measure: .amount),
            snapshot: fixture.snapshot
        )).value == .money(55))

        #expect(requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .reconciliationLedgerEntries, operation: .average, measure: .amount),
            snapshot: fixture.snapshot
        )).value == .money(13.75))

        #expect(groupSummaries(requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .group,
                measure: .amount,
                groupBy: .relationship(.reconciliationAccount)
            ),
            snapshot: fixture.snapshot
        ))) == [
            GroupSummary(name: "Roommate", aggregate: .money(35)),
            GroupSummary(name: "Travel Kitty", aggregate: .money(20))
        ])
    }

    @Test func shadowPlansCoverAccountsAndLedgerActivity() {
        let fixture = makeFixture()

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .semantic(.savingsAccount), operation: .list),
            snapshot: fixture.snapshot
        ))) == ["Emergency Fund", "Travel Savings"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .savingsLedgerEntries,
                operation: .list,
                filters: [
                    MarinaRowFilter(target: .relationship(.savingsAccount), operation: .equals, value: .text("Emergency Fund"))
                ]
            ),
            snapshot: fixture.snapshot
        ))) == ["May reserve", "Emergency deposit", "Expense offset"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .semantic(.reconciliationAccount), operation: .list),
            snapshot: fixture.snapshot
        ))) == ["Roommate", "Travel Kitty"])

        #expect(rowNames(requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .reconciliationLedgerEntries,
                operation: .list,
                filters: [
                    MarinaRowFilter(target: .relationship(.reconciliationAccount), operation: .equals, value: .text("Roommate"))
                ]
            ),
            snapshot: fixture.snapshot
        ))) == ["May true-up", "Apple Store", "Paid back"])
    }

    @Test func accountActivityUsesStableNonduplicatingPagesAndFullSetAggregates() {
        let fixture = makeFixture(longActivity: true)
        let bridge = MarinaSemanticUniversalPlanBridge()

        func page(
            entity: MarinaSemanticEntity,
            targetID: UUID,
            targetName: String,
            offset: Int
        ) -> MarinaUniversalRowsPage {
            let request = MarinaSemanticRequest(
                entity: entity,
                operation: .list,
                projection: .activity,
                dateRangeToken: .allTime,
                dateRangeSource: .explicit,
                targetName: targetName,
                resolvedTarget: MarinaResolvedEntityReference(
                    entity: entity,
                    id: targetID,
                    displayName: targetName,
                    provenance: .explicitIdentifier
                ),
                resolvedScope: .workspace(fixture.snapshot.workspace.id),
                resultLimit: 20,
                resultOffset: offset,
                expectedAnswerShape: .list
            )
            guard case let .plan(plan) = bridge.makePlan(from: request) else {
                Issue.record("Expected public account activity request to bridge.")
                return MarinaUniversalRowsPage(rows: [], totalRowCount: 0, displayLimit: 20)
            }
            let result = runner.run(
                plan: plan,
                snapshot: fixture.snapshot
            )
            guard case let .rowsPage(page) = result else {
                Issue.record("Expected paged activity rows, got \(result).")
                return MarinaUniversalRowsPage(rows: [], totalRowCount: 0, displayLimit: 20)
            }
            return page
        }

        let cases: [(MarinaSemanticEntity, UUID, String, MarinaUniversalEntitySurface)] = [
            (
                .savingsAccount,
                fixture.snapshot.savingsAccounts[0].id,
                fixture.snapshot.savingsAccounts[0].name,
                .savingsLedgerEntries
            ),
            (
                .reconciliationAccount,
                fixture.snapshot.reconciliationAccounts[0].id,
                fixture.snapshot.reconciliationAccounts[0].name,
                .reconciliationLedgerEntries
            )
        ]

        for (entity, targetID, targetName, internalSurface) in cases {
            let first = page(entity: entity, targetID: targetID, targetName: targetName, offset: 0)
            let second = page(entity: entity, targetID: targetID, targetName: targetName, offset: 20)

            #expect(first.rows.count == 20)
            #expect(first.totalRowCount == 25)
            #expect(first.fullTotalAmount == 325)
            #expect(first.hasMore)
            #expect(first.nextOffset == 20)
            #expect(second.rows.count == 5)
            #expect(second.totalRowCount == 25)
            #expect(second.fullTotalAmount == 325)
            #expect(second.hasMore == false)
            #expect(second.nextOffset == nil)
            #expect(Set(first.rows.map(\.id)).isDisjoint(with: Set(second.rows.map(\.id))))

            #expect(requireMetric(runner.run(
                plan: MarinaUniversalQueryPlan(surface: internalSurface, operation: .sum, measure: .amount),
                snapshot: fixture.snapshot
            )).value == .money(325))
        }
    }

    private func makeFixture(longActivity: Bool = false) -> SavingsReconciliationRunnerFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let travelCard = Card(name: "Travel Card", theme: "ocean", effect: "matte", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#22C55E", workspace: workspace)
        let travel = Offshore.Category(name: "Travel", hexColor: "#0EA5E9", workspace: workspace)

        let emergency = SavingsAccount(name: "Emergency Fund", createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let travelSavings = SavingsAccount(name: "Travel Savings", createdAt: date(2026, 2, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let roommate = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)
        let travelKitty = AllocationAccount(name: "Travel Kitty", hexColor: "#8B5CF6", workspace: workspace)

        let appleExpense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 90,
            transactionDate: date(2026, 6, 5),
            workspace: workspace,
            card: appleCard,
            category: electronics
        )
        let offsetExpense = VariableExpense(
            descriptionText: "Emergency Offset",
            amount: 25,
            transactionDate: date(2026, 6, 7),
            workspace: workspace,
            card: appleCard,
            category: electronics
        )
        let hotel = PlannedExpense(
            title: "Hotel",
            plannedAmount: 200,
            actualAmount: 180,
            expenseDate: date(2026, 6, 9),
            workspace: workspace,
            card: travelCard,
            category: travel
        )

        let savingsEntries: [SavingsLedgerEntry]
        let allocations: [ExpenseAllocation]
        let settlements: [AllocationSettlement]
        if longActivity {
            savingsEntries = (0..<25).map { index in
                SavingsLedgerEntry(
                    date: date(2026, 6, 1).addingTimeInterval(Double(index) * 86_400),
                    amount: Double(index + 1),
                    note: "Savings activity \(index + 1)",
                    kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                    workspace: workspace,
                    account: emergency
                )
            }
            allocations = []
            settlements = (0..<25).map { index in
                AllocationSettlement(
                    date: date(2026, 6, 1).addingTimeInterval(Double(index) * 86_400),
                    note: "Reconciliation activity \(index + 1)",
                    amount: Double(index + 1),
                    workspace: workspace,
                    account: roommate
                )
            }
        } else {
            savingsEntries = [
                SavingsLedgerEntry(date: date(2026, 5, 20), amount: 50, note: "May reserve", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: emergency),
                SavingsLedgerEntry(date: date(2026, 6, 3), amount: 125, note: "Emergency deposit", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: emergency),
                SavingsLedgerEntry(date: date(2026, 6, 7), amount: -25, note: "Expense offset", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, workspace: workspace, account: emergency, variableExpense: offsetExpense),
                SavingsLedgerEntry(date: date(2026, 6, 10), amount: 200, note: "Travel deposit", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: travelSavings)
            ]
            allocations = [
                ExpenseAllocation(allocatedAmount: 40, createdAt: date(2026, 6, 6), updatedAt: date(2026, 6, 6), workspace: workspace, account: roommate, expense: appleExpense),
                ExpenseAllocation(allocatedAmount: 20, createdAt: date(2026, 6, 9), updatedAt: date(2026, 6, 9), workspace: workspace, account: travelKitty, plannedExpense: hotel)
            ]
            settlements = [
                AllocationSettlement(date: date(2026, 5, 18), note: "May true-up", amount: 10, workspace: workspace, account: roommate),
                AllocationSettlement(date: date(2026, 6, 8), note: "Paid back", amount: -15, workspace: workspace, account: roommate)
            ]
        }

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [],
            cards: [appleCard, travelCard],
            categories: [electronics, travel],
            presets: [],
            plannedExpenses: [hotel],
            variableExpenses: [appleExpense, offsetExpense],
            homePlannedExpenses: [hotel],
            homeCalculationPlannedExpenses: [hotel],
            homeCalculationVariableExpenses: [appleExpense, offsetExpense],
            reconciliationAccounts: [roommate, travelKitty],
            expenseAllocations: allocations,
            allocationSettlements: settlements,
            savingsAccounts: [emergency, travelSavings],
            savingsEntries: savingsEntries,
            incomes: []
        )

        return SavingsReconciliationRunnerFixture(snapshot: snapshot)
    }

    private func juneDateFilters() -> [MarinaRowFilter] {
        [
            MarinaRowFilter(target: .field(.date), operation: .greaterThanOrEqual, value: .date(date(2026, 6, 1))),
            MarinaRowFilter(target: .field(.date), operation: .lessThanOrEqual, value: .date(date(2026, 6, 30)))
        ]
    }

    private func requireRows(_ result: MarinaUniversalQueryResult) -> [MarinaQueryableRow] {
        switch result {
        case let .rows(rows):
            return rows
        case let .rowsPage(page):
            return page.rows
        default:
            Issue.record("Expected row result, got \(result).")
            return []
        }
    }

    private func requireMetric(_ result: MarinaUniversalQueryResult) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected metric result, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
    }

    private func requireGroups(_ result: MarinaUniversalQueryResult) -> [MarinaUniversalGroupResult] {
        guard case let .groups(groups) = result else {
            Issue.record("Expected grouped result, got \(result).")
            return []
        }
        return groups
    }

    private func rowNames(_ rows: [MarinaQueryableRow]) -> [String] {
        rows.map(\.displayName)
    }

    private func groupSummaries(_ groups: [MarinaUniversalGroupResult]) -> [GroupSummary] {
        groups.map { group in
            GroupSummary(name: group.group.displayName, aggregate: group.aggregate)
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

private struct SavingsReconciliationRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
}

private struct GroupSummary: Equatable {
    let name: String
    let aggregate: MarinaValue?
}
