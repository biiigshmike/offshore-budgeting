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
        defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue
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
        #expect(coordinator.pendingRequest?.savingsSignature == savingsSignature)
        #expect(coordinator.pendingRequest?.notificationSignature == notificationSignature)

        coordinator.markNotificationRefreshCompleted(request)
        #expect(coordinator.pendingRequest?.widgetSignature == nil)
        #expect(coordinator.pendingRequest?.notificationSignature == nil)
        #expect(coordinator.pendingRequest?.savingsSignature == savingsSignature)

        coordinator.markSavingsRefreshCompleted(request)
        #expect(coordinator.pendingRequest == nil)
    }
}
