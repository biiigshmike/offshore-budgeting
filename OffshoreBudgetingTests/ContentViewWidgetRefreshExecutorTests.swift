//
//  ContentViewWidgetRefreshExecutorTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 3/14/26.
//

import Foundation
import SwiftData
import Testing
@testable import Offshore

struct ContentViewWidgetRefreshExecutorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            IncomeSeries.self,
            Income.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func refreshAll_buildsSnapshotsForCurrentWorkspace() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workspaceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let workspace = Workspace(id: workspaceID, name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Visa",
            theme: "ocean",
            effect: "plastic",
            workspace: workspace
        )
        let category = Category(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            name: "Dining",
            hexColor: "#FF6600",
            workspace: workspace
        )

        let now = Date.now
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now

        let income = Income(
            source: "Salary",
            amount: 3200,
            date: startOfMonth,
            isPlanned: false,
            workspace: workspace,
            card: card
        )
        let plannedExpense = PlannedExpense(
            title: "Dinner Reservation",
            plannedAmount: 72,
            expenseDate: Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now,
            workspace: workspace,
            card: card,
            category: category,
            sourceBudgetID: UUID()
        )
        let variableExpense = VariableExpense(
            descriptionText: "Coffee",
            amount: 8.5,
            transactionDate: now,
            workspace: workspace,
            card: card,
            category: category
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(income)
        context.insert(plannedExpense)
        context.insert(variableExpense)
        try context.save()

        let executor = ContentViewWidgetRefreshExecutor(modelContainer: container)
        let report = await executor.refreshAll(workspaceID: workspaceID)

        let workspaceIDString = workspaceID.uuidString
        let cardIDString = card.id.uuidString

        #expect(report.totalDurationMillis >= 0)
        #expect(
            IncomeWidgetSnapshotStore.load(
                workspaceID: workspaceIDString,
                periodToken: IncomeWidgetPeriod.period.rawValue
            ) != nil
        )
        #expect(
            CardWidgetSnapshotStore.load(
                workspaceID: workspaceIDString,
                cardID: cardIDString,
                periodToken: CardWidgetPeriod.period.rawValue
            ) != nil
        )
        #expect(
            NextPlannedExpenseWidgetSnapshotStore.load(
                workspaceID: workspaceIDString,
                cardID: nil,
                periodToken: NextPlannedExpenseWidgetPeriod.period.rawValue
            ) != nil
        )
        #expect(
            SpendTrendsWidgetSnapshotStore.load(
                workspaceID: workspaceIDString,
                cardID: nil,
                periodToken: SpendTrendsWidgetPeriod.period.rawValue
            ) != nil
        )
    }

    @Test func spendTrendsWidgetSnapshot_usesOwnedBudgetImpactForSplitExpenses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workspaceID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let workspace = Workspace(id: workspaceID, name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            name: "Visa",
            theme: "ocean",
            effect: "plastic",
            workspace: workspace
        )
        let category = Category(
            id: UUID(uuidString: "AAAAAAAA-9999-8888-7777-666666666666")!,
            name: "Dining",
            hexColor: "#FF6600",
            workspace: workspace
        )
        let account = AllocationAccount(name: "Shared", workspace: workspace)
        let now = Date.now
        let plannedExpense = PlannedExpense(
            title: "Reservation",
            plannedAmount: 100,
            actualAmount: 80,
            expenseDate: now,
            workspace: workspace,
            card: card,
            category: category
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 30,
            preservesGrossAmount: true,
            workspace: workspace,
            account: account,
            plannedExpense: plannedExpense
        )
        plannedExpense.allocation = plannedAllocation

        let variableExpense = VariableExpense(
            descriptionText: "Dinner",
            amount: 100,
            transactionDate: now,
            workspace: workspace,
            card: card,
            category: category
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            workspace: workspace,
            account: account,
            expense: variableExpense
        )
        variableExpense.allocation = variableAllocation

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        context.insert(plannedExpense)
        context.insert(plannedAllocation)
        context.insert(variableExpense)
        context.insert(variableAllocation)
        try context.save()

        SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            shouldReloadTimelines: false
        )

        let snapshot = try #require(
            SpendTrendsWidgetSnapshotStore.load(
                workspaceID: workspaceID.uuidString,
                cardID: nil,
                periodToken: SpendTrendsWidgetPeriod.oneMonth.rawValue
            )
        )
        let nonZeroBucket = try #require(snapshot.buckets.first { $0.total > 0 })
        let topCategory = try #require(snapshot.topCategories.first)

        #expect(abs(snapshot.totalSpent - 110) < 0.001)
        #expect(abs(nonZeroBucket.total - 110) < 0.001)
        #expect(topCategory.name == "Dining")
        #expect(abs(topCategory.amount - 110) < 0.001)
    }
}
