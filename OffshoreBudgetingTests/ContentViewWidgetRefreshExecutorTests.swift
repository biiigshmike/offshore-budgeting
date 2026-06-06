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
            MarinaChatSession.self,
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
            theme: "periwinkle",
            effect: "glass",
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
            expenseDate: now,
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
        let cardWidgetSnapshot = try #require(
            CardWidgetSnapshotStore.load(
                workspaceID: workspaceIDString,
                cardID: cardIDString,
                periodToken: CardWidgetPeriod.period.rawValue
            )
        )
        let cardWidgetOption = try #require(
            CardWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceIDString).first {
                $0.id == cardIDString
            }
        )
        #expect(cardWidgetSnapshot.themeToken == "periwinkle")
        #expect(cardWidgetSnapshot.effectToken == "glass")
        #expect(cardWidgetOption.themeToken == "periwinkle")
        #expect(cardWidgetOption.effectToken == "glass")
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

    @Test func widgetTimelineSchedule_rollsToNextBoundaryStarts() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)))

        let dailyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 59, second: 59)))
        let weeklyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 23, minute: 59, second: 59)))
        let monthlyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 23, minute: 59, second: 59)))
        let quarterlyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 23, minute: 59, second: 59)))
        let yearlyEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)))

        #expect(calendar.component(.day, from: WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: dailyEnd, now: now)) == 2)
        #expect(calendar.component(.day, from: WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: weeklyEnd, now: now)) == 8)
        #expect(calendar.component(.month, from: WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: monthlyEnd, now: now)) == 7)
        #expect(calendar.component(.month, from: WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: quarterlyEnd, now: now)) == 7)
        #expect(calendar.component(.year, from: WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: yearlyEnd, now: now)) == 2027)
    }

    @Test func refreshAll_precomputesMonthlyTimelineRolloverWithoutAppReopen() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current
        let defaults = UserDefaults(suiteName: IncomeWidgetSnapshotStore.appGroupID)
        defaults?.set(BudgetingPeriod.monthly.rawValue, forKey: "general_defaultBudgetingPeriod")

        let workspaceID = UUID(uuidString: "ABABABAB-CDCD-EFEF-1212-343434343434")!
        let cardID = UUID(uuidString: "45454545-5656-6767-7878-898989898989")!
        let may31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12)))
        let june1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))

        let workspace = Workspace(id: workspaceID, name: "Personal Timeline", hexColor: "#3B82F6")
        let card = Card(
            id: cardID,
            name: "Timeline Card",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )
        context.insert(workspace)
        context.insert(card)
        try context.save()

        let executor = ContentViewWidgetRefreshExecutor(modelContainer: container)
        _ = await executor.refreshAll(workspaceID: workspaceID, now: may31)

        let incomeSnapshot = try #require(
            IncomeWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                periodToken: IncomeWidgetPeriod.period.rawValue,
                asOf: june1
            )
        )
        let cardSnapshot = try #require(
            CardWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: cardID.uuidString,
                periodToken: CardWidgetPeriod.period.rawValue,
                asOf: june1
            )
        )
        let nextPlannedSnapshot = try #require(
            NextPlannedExpenseWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: nil,
                periodToken: NextPlannedExpenseWidgetPeriod.period.rawValue,
                asOf: june1
            )
        )
        let spendTrendsSnapshot = try #require(
            SpendTrendsWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: nil,
                periodToken: SpendTrendsWidgetPeriod.period.rawValue,
                asOf: june1
            )
        )

        for rangeStart in [
            incomeSnapshot.rangeStart,
            cardSnapshot.rangeStart,
            nextPlannedSnapshot.rangeStart,
            spendTrendsSnapshot.rangeStart
        ] {
            #expect(calendar.component(.month, from: rangeStart) == 6)
            #expect(calendar.component(.day, from: rangeStart) == 1)
        }

        for rangeEnd in [
            incomeSnapshot.rangeEnd,
            cardSnapshot.rangeEnd,
            nextPlannedSnapshot.rangeEnd,
            spendTrendsSnapshot.rangeEnd
        ] {
            #expect(calendar.component(.month, from: rangeEnd) == 6)
            #expect(calendar.component(.day, from: rangeEnd) == 30)
        }

        #expect(nextPlannedSnapshot.items.isEmpty)
        #expect(spendTrendsSnapshot.totalSpent == 0)
    }

    @Test func currentQuarterWidgetRanges_useCalendarQuarters() throws {
        let cases: [(date: DateComponents, start: DateComponents, end: DateComponents)] = [
            (
                DateComponents(year: 2026, month: 1, day: 15, hour: 12),
                DateComponents(year: 2026, month: 1, day: 1),
                DateComponents(year: 2026, month: 3, day: 31)
            ),
            (
                DateComponents(year: 2026, month: 6, day: 2, hour: 12),
                DateComponents(year: 2026, month: 4, day: 1),
                DateComponents(year: 2026, month: 6, day: 30)
            ),
            (
                DateComponents(year: 2026, month: 7, day: 4, hour: 12),
                DateComponents(year: 2026, month: 7, day: 1),
                DateComponents(year: 2026, month: 9, day: 30)
            ),
            (
                DateComponents(year: 2026, month: 12, day: 12, hour: 12),
                DateComponents(year: 2026, month: 10, day: 1),
                DateComponents(year: 2026, month: 12, day: 31)
            )
        ]

        for item in cases {
            let container = try makeContainer()
            let context = ModelContext(container)
            let calendar = Calendar.current
            let workspaceID = UUID()
            let cardID = UUID()
            let now = try #require(calendar.date(from: item.date))
            let expectedStart = try #require(calendar.date(from: item.start))
            let expectedEndDay = try #require(calendar.date(from: item.end))

            let workspace = Workspace(id: workspaceID, name: "Quarter", hexColor: "#3B82F6")
            let card = Card(id: cardID, name: "Quarter Card", theme: "ruby", effect: "plastic", workspace: workspace)
            context.insert(workspace)
            context.insert(card)
            try context.save()

            IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: context,
                workspaceID: workspaceID,
                now: now,
                shouldReloadTimelines: false
            )
            CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: context,
                workspaceID: workspaceID,
                now: now,
                shouldReloadTimelines: false
            )
            NextPlannedExpenseWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: context,
                workspaceID: workspaceID,
                now: now,
                shouldReloadTimelines: false
            )
            SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: context,
                workspaceID: workspaceID,
                now: now,
                shouldReloadTimelines: false
            )

            let snapshots: [(Date, Date)] = [
                try #require(
                    IncomeWidgetSnapshotStore.load(
                        workspaceID: workspaceID.uuidString,
                        periodToken: IncomeWidgetPeriod.q.rawValue
                    )
                ).rangeTuple,
                try #require(
                    CardWidgetSnapshotStore.load(
                        workspaceID: workspaceID.uuidString,
                        cardID: cardID.uuidString,
                        periodToken: CardWidgetPeriod.q.rawValue
                    )
                ).rangeTuple,
                try #require(
                    NextPlannedExpenseWidgetSnapshotStore.load(
                        workspaceID: workspaceID.uuidString,
                        cardID: nil,
                        periodToken: NextPlannedExpenseWidgetPeriod.q.rawValue
                    )
                ).rangeTuple,
                try #require(
                    SpendTrendsWidgetSnapshotStore.load(
                        workspaceID: workspaceID.uuidString,
                        cardID: nil,
                        periodToken: SpendTrendsWidgetPeriod.q.rawValue
                    )
                ).rangeTuple
            ]

            for (start, end) in snapshots {
                #expect(calendar.startOfDay(for: start) == expectedStart)
                #expect(calendar.startOfDay(for: end) == expectedEndDay)
            }
        }
    }

    @Test func currentQuarterTimeline_rollsFromQ2ToQ3() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current

        let workspaceID = UUID(uuidString: "EEEEEEEE-FFFF-0000-1111-222222222222")!
        let cardID = UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!
        let june30 = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let july1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12)))

        let workspace = Workspace(id: workspaceID, name: "Quarter Rollover", hexColor: "#3B82F6")
        let card = Card(id: cardID, name: "Quarter Card", theme: "ruby", effect: "plastic", workspace: workspace)
        context.insert(workspace)
        context.insert(card)
        try context.save()

        let executor = ContentViewWidgetRefreshExecutor(modelContainer: container)
        _ = await executor.refreshAll(workspaceID: workspaceID, now: june30)

        let incomeSnapshot = try #require(
            IncomeWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                periodToken: IncomeWidgetPeriod.q.rawValue,
                asOf: july1
            )
        )
        let cardSnapshot = try #require(
            CardWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: cardID.uuidString,
                periodToken: CardWidgetPeriod.q.rawValue,
                asOf: july1
            )
        )
        let nextPlannedSnapshot = try #require(
            NextPlannedExpenseWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: nil,
                periodToken: NextPlannedExpenseWidgetPeriod.q.rawValue,
                asOf: july1
            )
        )
        let spendTrendsSnapshot = try #require(
            SpendTrendsWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID.uuidString,
                cardID: nil,
                periodToken: SpendTrendsWidgetPeriod.q.rawValue,
                asOf: july1
            )
        )

        for (start, end) in [
            incomeSnapshot.rangeTuple,
            cardSnapshot.rangeTuple,
            nextPlannedSnapshot.rangeTuple,
            spendTrendsSnapshot.rangeTuple
        ] {
            #expect(calendar.component(.month, from: start) == 7)
            #expect(calendar.component(.day, from: start) == 1)
            #expect(calendar.component(.month, from: end) == 9)
            #expect(calendar.component(.day, from: end) == 30)
        }
    }

    @Test func incomeWidgetSnapshotCapsRecentItemsToSixNewest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let calendar = Calendar.current

        let workspaceID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12)))
        let workspace = Workspace(id: workspaceID, name: "Recent Income Cap", hexColor: "#3B82F6")
        let card = Card(
            id: UUID(uuidString: "ABABABAB-1212-3434-5656-787878787878")!,
            name: "Payroll",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )

        context.insert(workspace)
        context.insert(card)

        for day in 1...8 {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 12)))
            context.insert(
                Income(
                    source: "Income \(day)",
                    amount: Double(day * 100),
                    date: date,
                    isPlanned: false,
                    workspace: workspace,
                    card: card
                )
            )
        }

        try context.save()

        IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            now: now,
            shouldReloadTimelines: false
        )

        let snapshot = try #require(
            IncomeWidgetSnapshotStore.load(
                workspaceID: workspaceID.uuidString,
                periodToken: IncomeWidgetPeriod.oneMonth.rawValue
            )
        )
        let recentItems = try #require(snapshot.recentItems)

        #expect(recentItems.count == 6)
        #expect(recentItems.map(\.source) == ["Income 8", "Income 7", "Income 6", "Income 5", "Income 4", "Income 3"])
    }

    @Test func spendTrendsWidgetSnapshot_usesOwnedBudgetImpactForSplitExpenses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workspaceID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let workspace = Workspace(id: workspaceID, name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
            name: "Visa",
            theme: "aqua",
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

    @Test func widgetCardVisualResolver_recognizesCurrentAppTokensAndLegacyAliases() {
        for theme in CardThemeOption.allCases {
            #expect(WidgetCardVisualTheme.resolve(theme.rawValue).rawValue == theme.rawValue)
        }

        for effect in CardEffectOption.allCases {
            #expect(WidgetCardVisualEffect.resolve(effect.rawValue).rawValue == effect.rawValue)
        }

        #expect(WidgetCardVisualTheme.resolve("ocean") == .aqua)
        #expect(WidgetCardVisualTheme.resolve("graphite") == .charcoal)
        #expect(WidgetCardVisualTheme.resolve("nebula") == .aster)
        #expect(WidgetCardVisualEffect.resolve("none") == .plastic)
    }

    @Test func widgetPlaceholders_useCurrentCardVisualTokens() {
        #expect(CardThemeOption(rawValue: CardWidgetSnapshot.placeholder.themeToken) != nil)
        #expect(CardEffectOption(rawValue: CardWidgetSnapshot.placeholder.effectToken) != nil)

        for item in NextPlannedExpenseWidgetSnapshot.placeholder.items {
            #expect(CardThemeOption(rawValue: item.cardThemeToken) != nil)
            #expect(CardEffectOption(rawValue: item.cardEffectToken) != nil)
        }

        for item in NextPlannedExpenseWidgetSnapshot.truncationPreview.items {
            #expect(CardThemeOption(rawValue: item.cardThemeToken) != nil)
            #expect(CardEffectOption(rawValue: item.cardEffectToken) != nil)
        }
    }

    @Test func cardWidgetSnapshotRefresh_overwritesStyleAndOptionsWhenCardChanges() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workspaceID = UUID(uuidString: "CCCCCCCC-DDDD-EEEE-FFFF-000000000001")!
        let cardID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
        let workspace = Workspace(id: workspaceID, name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            id: cardID,
            name: "Everyday",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )
        context.insert(workspace)
        context.insert(card)
        try context.save()

        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            shouldReloadTimelines: false
        )

        card.name = "Travel"
        card.theme = "aster"
        card.effect = "holographic"
        try context.save()

        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            shouldReloadTimelines: false
        )

        let snapshot = try #require(
            CardWidgetSnapshotStore.load(
                workspaceID: workspaceID.uuidString,
                cardID: cardID.uuidString,
                periodToken: CardWidgetPeriod.period.rawValue
            )
        )
        let option = try #require(
            CardWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID.uuidString).first {
                $0.id == cardID.uuidString
            }
        )

        #expect(snapshot.title == "Travel")
        #expect(snapshot.themeToken == "aster")
        #expect(snapshot.effectToken == "holographic")
        #expect(option.name == "Travel")
        #expect(option.themeToken == "aster")
        #expect(option.effectToken == "holographic")
    }

    @Test func cardWidgetSnapshotRefresh_prunesDeletedCardSnapshots() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workspaceID = UUID(uuidString: "DDDDDDDD-EEEE-FFFF-0000-111111111111")!
        let cardID = UUID(uuidString: "44444444-5555-6666-7777-888888888888")!
        let workspace = Workspace(id: workspaceID, name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            id: cardID,
            name: "Everyday",
            theme: "seafoam",
            effect: "metal",
            workspace: workspace
        )
        context.insert(workspace)
        context.insert(card)
        try context.save()

        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            shouldReloadTimelines: false
        )
        #expect(
            CardWidgetSnapshotStore.load(
                workspaceID: workspaceID.uuidString,
                cardID: cardID.uuidString,
                periodToken: CardWidgetPeriod.period.rawValue
            ) != nil
        )

        context.delete(card)
        try context.save()

        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: context,
            workspaceID: workspaceID,
            shouldReloadTimelines: false
        )

        #expect(
            CardWidgetSnapshotStore.load(
                workspaceID: workspaceID.uuidString,
                cardID: cardID.uuidString,
                periodToken: CardWidgetPeriod.period.rawValue
            ) == nil
        )
        #expect(
            CardWidgetSnapshotStore
                .loadCardOptions(workspaceID: workspaceID.uuidString)
                .contains(where: { $0.id == cardID.uuidString }) == false
        )
    }
}

private extension IncomeWidgetSnapshot {
    var rangeTuple: (Date, Date) {
        (rangeStart, rangeEnd)
    }
}

private extension CardWidgetSnapshot {
    var rangeTuple: (Date, Date) {
        (rangeStart, rangeEnd)
    }
}

private extension NextPlannedExpenseWidgetSnapshot {
    var rangeTuple: (Date, Date) {
        (rangeStart, rangeEnd)
    }
}

private extension SpendTrendsWidgetSnapshot {
    var rangeTuple: (Date, Date) {
        (rangeStart, rangeEnd)
    }
}
