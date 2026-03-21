//
//  ContentViewResumeCoordinatorTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Testing
@testable import Offshore

struct ContentViewResumeCoordinatorTests {

    private let widgetSignature = ContentViewWidgetRefreshSignature(
        workspaceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
        excludeFuturePlannedExpensesFromCalculations: false,
        excludeFutureVariableExpensesFromCalculations: false
    )

    private let savingsSignature = ContentViewSavingsRefreshSignature(
        workspaceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
        dataSignature: ContentViewSavingsDataSignature(
            incomeCount: 1,
            incomeLatestUpdateStamp: 100,
            incomeTotalCents: 250_000,
            plannedExpenseCount: 2,
            plannedExpenseLatestUpdateStamp: 200,
            plannedExpenseTotalCents: 175_000,
            variableExpenseCount: 3,
            variableExpenseLatestUpdateStamp: 300,
            variableExpenseTotalCents: 95_000
        )
    )

    private let notificationSignature = ContentViewNotificationRefreshSignature(
        workspaceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        notificationsEnabled: true,
        dailyExpenseReminderEnabled: true,
        plannedIncomeReminderEnabled: false,
        presetDueReminderEnabled: false,
        reminderHour: 20,
        reminderMinute: 0
    )

    private func expectWidgetSignature(
        _ actual: ContentViewWidgetRefreshSignature?,
        equals expected: ContentViewWidgetRefreshSignature?
    ) {
        #expect(actual?.workspaceID == expected?.workspaceID)
        #expect(actual?.defaultBudgetingPeriodRaw == expected?.defaultBudgetingPeriodRaw)
        #expect(
            actual?.excludeFuturePlannedExpensesFromCalculations
                == expected?.excludeFuturePlannedExpensesFromCalculations
        )
        #expect(
            actual?.excludeFutureVariableExpensesFromCalculations
                == expected?.excludeFutureVariableExpensesFromCalculations
        )
    }

    private func expectSavingsSignature(
        _ actual: ContentViewSavingsRefreshSignature?,
        equals expected: ContentViewSavingsRefreshSignature?
    ) {
        #expect(actual?.workspaceID == expected?.workspaceID)
        #expect(actual?.defaultBudgetingPeriodRaw == expected?.defaultBudgetingPeriodRaw)
        #expect(actual?.dataSignature == expected?.dataSignature)
    }

    private func expectNotificationSignature(
        _ actual: ContentViewNotificationRefreshSignature?,
        equals expected: ContentViewNotificationRefreshSignature?
    ) {
        #expect(actual?.workspaceID == expected?.workspaceID)
        #expect(actual?.notificationsEnabled == expected?.notificationsEnabled)
        #expect(actual?.dailyExpenseReminderEnabled == expected?.dailyExpenseReminderEnabled)
        #expect(actual?.plannedIncomeReminderEnabled == expected?.plannedIncomeReminderEnabled)
        #expect(actual?.presetDueReminderEnabled == expected?.presetDueReminderEnabled)
        #expect(actual?.reminderHour == expected?.reminderHour)
        #expect(actual?.reminderMinute == expected?.reminderMinute)
    }

    @Test func schedule_collapsesIdenticalPendingRequest() {
        var coordinator = ContentViewResumeCoordinator()

        let first = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature
        )
        let second = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature
        )

        #expect(first != nil)
        #expect(second == nil)
        #expect(coordinator.pendingRequest?.generation == first?.generation)
    }

    @Test func schedule_supersedesOlderPendingRequestWhenInputsChange() {
        var coordinator = ContentViewResumeCoordinator()

        let first = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature
        )
        let changedWidgetSignature = ContentViewWidgetRefreshSignature(
            workspaceID: widgetSignature.workspaceID,
            defaultBudgetingPeriodRaw: BudgetingPeriod.yearly.rawValue,
            excludeFuturePlannedExpensesFromCalculations: false,
            excludeFutureVariableExpensesFromCalculations: false
        )
        let second = coordinator.schedule(
            widgetSignature: changedWidgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature
        )

        #expect(first != nil)
        #expect(second != nil)
        #expect(second?.generation == ((first?.generation ?? 0) + 1))
        #expect(coordinator.isCurrent(first!) == false)
        #expect(coordinator.isCurrent(second!) == true)
    }

    @Test func schedule_skipsCompletedWidgetInputs() {
        var coordinator = ContentViewResumeCoordinator()

        let first = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: nil,
            notificationSignature: nil
        )!
        coordinator.markWidgetRefreshCompleted(first)

        let second = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: nil,
            notificationSignature: nil
        )

        #expect(second == nil)
    }

    @Test func phaseCompletionLeavesOnlyRemainingWorkPending() {
        var coordinator = ContentViewResumeCoordinator()

        let request = coordinator.schedule(
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature
        )!

        coordinator.markWidgetRefreshCompleted(request)
        #expect(coordinator.pendingRequest?.widgetSignature == nil)
        expectSavingsSignature(coordinator.pendingRequest?.savingsSignature, equals: savingsSignature)
        expectNotificationSignature(
            coordinator.pendingRequest?.notificationSignature,
            equals: notificationSignature
        )

        coordinator.markNotificationRefreshCompleted(request)
        #expect(coordinator.pendingRequest?.widgetSignature == nil)
        #expect(coordinator.pendingRequest?.notificationSignature == nil)
        expectSavingsSignature(coordinator.pendingRequest?.savingsSignature, equals: savingsSignature)

        coordinator.markSavingsRefreshCompleted(request)
        #expect(coordinator.pendingRequest == nil)
    }

    @Test func planner_sceneBecameActive_sameDaySkipsWidgetAndSavingsWork() {
        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: .sceneBecameActive,
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature,
            shouldRefreshWidgetsOnForeground: false,
            shouldRefreshSavingsOnForeground: false
        )

        #expect(plan.widgetSignature == nil)
        #expect(plan.savingsSignature == nil)
        expectNotificationSignature(plan.notificationSignature, equals: notificationSignature)
        #expect(plan.forceWidgetRefresh == false)
        #expect(plan.forceSavingsRefresh == false)
    }

    @Test func planner_workspaceSelectionChangedKeepsRequestedWorkWithoutForcing() {
        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: .workspaceSelectionChanged,
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature,
            shouldRefreshWidgetsOnForeground: false,
            shouldRefreshSavingsOnForeground: false
        )

        expectWidgetSignature(plan.widgetSignature, equals: widgetSignature)
        expectSavingsSignature(plan.savingsSignature, equals: savingsSignature)
        expectNotificationSignature(plan.notificationSignature, equals: notificationSignature)
        #expect(plan.forceWidgetRefresh == false)
        #expect(plan.forceSavingsRefresh == false)
        #expect(plan.forceNotificationRefresh == false)
    }

    @Test func planner_sceneBecameActive_dayRolloverForcesWidgetRefresh() {
        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: .sceneBecameActive,
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: nil,
            shouldRefreshWidgetsOnForeground: true,
            shouldRefreshSavingsOnForeground: false
        )

        expectWidgetSignature(plan.widgetSignature, equals: widgetSignature)
        #expect(plan.savingsSignature == nil)
        #expect(plan.forceWidgetRefresh)
        #expect(plan.forceSavingsRefresh == false)
    }

    @Test func planner_sceneBecameActive_periodBoundaryForcesSavingsRefresh() {
        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: .sceneBecameActive,
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: nil,
            shouldRefreshWidgetsOnForeground: false,
            shouldRefreshSavingsOnForeground: true
        )

        #expect(plan.widgetSignature == nil)
        expectSavingsSignature(plan.savingsSignature, equals: savingsSignature)
        #expect(plan.forceWidgetRefresh == false)
        #expect(plan.forceSavingsRefresh)
    }

    @Test func workspaceCountChanged_forcesRefreshButCollapsesIdenticalPendingWork() {
        var coordinator = ContentViewResumeCoordinator()
        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: .workspaceCountChanged,
            widgetSignature: widgetSignature,
            savingsSignature: savingsSignature,
            notificationSignature: notificationSignature,
            shouldRefreshWidgetsOnForeground: false,
            shouldRefreshSavingsOnForeground: false
        )

        let first = coordinator.schedule(
            widgetSignature: plan.widgetSignature,
            savingsSignature: plan.savingsSignature,
            notificationSignature: plan.notificationSignature,
            forceWidgetRefresh: plan.forceWidgetRefresh,
            forceSavingsRefresh: plan.forceSavingsRefresh,
            forceNotificationRefresh: plan.forceNotificationRefresh
        )
        let second = coordinator.schedule(
            widgetSignature: plan.widgetSignature,
            savingsSignature: plan.savingsSignature,
            notificationSignature: plan.notificationSignature,
            forceWidgetRefresh: plan.forceWidgetRefresh,
            forceSavingsRefresh: plan.forceSavingsRefresh,
            forceNotificationRefresh: plan.forceNotificationRefresh
        )

        #expect(first != nil)
        #expect(second == nil)

        coordinator.markWidgetRefreshCompleted(first!)
        coordinator.markNotificationRefreshCompleted(first!)
        coordinator.markSavingsRefreshCompleted(first!)

        let third = coordinator.schedule(
            widgetSignature: plan.widgetSignature,
            savingsSignature: plan.savingsSignature,
            notificationSignature: plan.notificationSignature,
            forceWidgetRefresh: plan.forceWidgetRefresh,
            forceSavingsRefresh: plan.forceSavingsRefresh,
            forceNotificationRefresh: plan.forceNotificationRefresh
        )

        #expect(third != nil)
    }

    @MainActor
    @Test func sceneScopedResumeState_preservesCompletedWorkAcrossReconstruction() {
        let resumeState = ContentViewResumeState()
        let plan = ContentViewDeferredRefreshPlan(
            widgetSignature: widgetSignature,
            savingsSignature: nil,
            notificationSignature: nil,
            forceWidgetRefresh: false,
            forceSavingsRefresh: false,
            forceNotificationRefresh: false
        )

        let first = resumeState.schedule(plan: plan)!
        resumeState.markWidgetRefreshCompleted(first, now: Date(timeIntervalSince1970: 0))

        let reconstructedContentViewState = resumeState
        let second = reconstructedContentViewState.schedule(plan: plan)
        let expectedDayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))

        #expect(second == nil)
        #expect(reconstructedContentViewState.lastWidgetRefreshDayStart == expectedDayStart)
    }
}
