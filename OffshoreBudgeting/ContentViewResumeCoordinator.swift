//
//  ContentViewResumeCoordinator.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/13/26.
//

import Foundation
import Combine

enum ContentViewResumeTrigger: String, Equatable {
    case initialAppear
    case sceneBecameActive
    case workspaceSelectionChanged
    case workspaceCountChanged
    case settingsChanged
}

struct ContentViewDeferredRefreshPlan: Equatable {
    let widgetSignature: ContentViewWidgetRefreshSignature?
    let savingsSignature: ContentViewSavingsRefreshSignature?
    let notificationSignature: ContentViewNotificationRefreshSignature?
    let forceWidgetRefresh: Bool
    let forceSavingsRefresh: Bool
    let forceNotificationRefresh: Bool
}

enum ContentViewDeferredRefreshPlanner {
    static func plan(
        trigger: ContentViewResumeTrigger,
        widgetSignature: ContentViewWidgetRefreshSignature?,
        savingsSignature: ContentViewSavingsRefreshSignature?,
        notificationSignature: ContentViewNotificationRefreshSignature?,
        shouldRefreshWidgetsOnForeground: Bool,
        shouldRefreshSavingsOnForeground: Bool
    ) -> ContentViewDeferredRefreshPlan {
        switch trigger {
        case .sceneBecameActive:
            let resolvedWidgetSignature = shouldRefreshWidgetsOnForeground ? widgetSignature : nil
            let resolvedSavingsSignature = shouldRefreshSavingsOnForeground ? savingsSignature : nil
            return ContentViewDeferredRefreshPlan(
                widgetSignature: resolvedWidgetSignature,
                savingsSignature: resolvedSavingsSignature,
                notificationSignature: notificationSignature,
                forceWidgetRefresh: resolvedWidgetSignature != nil,
                forceSavingsRefresh: resolvedSavingsSignature != nil,
                forceNotificationRefresh: false
            )
        case .workspaceCountChanged:
            return ContentViewDeferredRefreshPlan(
                widgetSignature: widgetSignature,
                savingsSignature: savingsSignature,
                notificationSignature: notificationSignature,
                forceWidgetRefresh: widgetSignature != nil,
                forceSavingsRefresh: savingsSignature != nil,
                forceNotificationRefresh: notificationSignature != nil
            )
        case .initialAppear, .workspaceSelectionChanged, .settingsChanged:
            return ContentViewDeferredRefreshPlan(
                widgetSignature: widgetSignature,
                savingsSignature: savingsSignature,
                notificationSignature: notificationSignature,
                forceWidgetRefresh: false,
                forceSavingsRefresh: false,
                forceNotificationRefresh: false
            )
        }
    }
}

struct ContentViewWidgetRefreshSignature: Equatable {
    let workspaceID: UUID
    let defaultBudgetingPeriodRaw: String
    let excludeFuturePlannedExpensesFromCalculations: Bool
    let excludeFutureVariableExpensesFromCalculations: Bool
}

struct ContentViewSavingsRefreshSignature: Equatable {
    let workspaceID: UUID
    let defaultBudgetingPeriodRaw: String
}

struct ContentViewNotificationRefreshSignature: Equatable {
    let workspaceID: UUID
    let notificationsEnabled: Bool
    let dailyExpenseReminderEnabled: Bool
    let plannedIncomeReminderEnabled: Bool
    let presetDueReminderEnabled: Bool
    let reminderHour: Int
    let reminderMinute: Int
}

struct ContentViewDeferredRefreshRequest: Equatable {
    let generation: Int
    let widgetSignature: ContentViewWidgetRefreshSignature?
    let savingsSignature: ContentViewSavingsRefreshSignature?
    let notificationSignature: ContentViewNotificationRefreshSignature?

    var hasWork: Bool {
        widgetSignature != nil || savingsSignature != nil || notificationSignature != nil
    }

    func equivalentWork(to other: ContentViewDeferredRefreshRequest) -> Bool {
        widgetSignature == other.widgetSignature
            && savingsSignature == other.savingsSignature
            && notificationSignature == other.notificationSignature
    }
}

@MainActor
final class ContentViewResumeState: ObservableObject {
    var coordinator = ContentViewResumeCoordinator()
    var deferredResumeTask: Task<Void, Never>? = nil
    var lastWidgetRefreshDayStart: Date? = nil
    private(set) var lastUserInteractionUptimeNs: UInt64? = nil

    func schedule(
        plan: ContentViewDeferredRefreshPlan
    ) -> ContentViewDeferredRefreshRequest? {
        coordinator.schedule(
            widgetSignature: plan.widgetSignature,
            savingsSignature: plan.savingsSignature,
            notificationSignature: plan.notificationSignature,
            forceWidgetRefresh: plan.forceWidgetRefresh,
            forceSavingsRefresh: plan.forceSavingsRefresh,
            forceNotificationRefresh: plan.forceNotificationRefresh
        )
    }

    func replaceDeferredResumeTask(_ task: Task<Void, Never>) {
        deferredResumeTask?.cancel()
        deferredResumeTask = task
    }

    func recordUserInteraction(nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lastUserInteractionUptimeNs = nowUptimeNs
    }

    func hasRecentUserInteraction(
        within nanoseconds: UInt64,
        nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        guard let lastUserInteractionUptimeNs else { return false }
        return nowUptimeNs - lastUserInteractionUptimeNs < nanoseconds
    }

    func cancelPending() {
        deferredResumeTask?.cancel()
        deferredResumeTask = nil
        coordinator.cancelPending()
    }

    func markWidgetRefreshCompleted(
        _ request: ContentViewDeferredRefreshRequest,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        lastWidgetRefreshDayStart = calendar.startOfDay(for: now)
        coordinator.markWidgetRefreshCompleted(request)
    }

    func markSavingsRefreshCompleted(_ request: ContentViewDeferredRefreshRequest) {
        coordinator.markSavingsRefreshCompleted(request)
    }

    func markNotificationRefreshCompleted(_ request: ContentViewDeferredRefreshRequest) {
        coordinator.markNotificationRefreshCompleted(request)
    }
}

struct ContentViewResumeCoordinator {
    private(set) var latestGeneration: Int = 0
    private(set) var pendingRequest: ContentViewDeferredRefreshRequest? = nil

    private(set) var lastCompletedWidgetSignature: ContentViewWidgetRefreshSignature? = nil
    private(set) var lastCompletedSavingsSignature: ContentViewSavingsRefreshSignature? = nil
    private(set) var lastCompletedNotificationSignature: ContentViewNotificationRefreshSignature? = nil

    mutating func schedule(
        widgetSignature: ContentViewWidgetRefreshSignature?,
        savingsSignature: ContentViewSavingsRefreshSignature?,
        notificationSignature: ContentViewNotificationRefreshSignature?,
        forceWidgetRefresh: Bool = false,
        forceSavingsRefresh: Bool = false,
        forceNotificationRefresh: Bool = false
    ) -> ContentViewDeferredRefreshRequest? {
        let candidate = ContentViewDeferredRefreshRequest(
            generation: latestGeneration + 1,
            widgetSignature: normalized(
                widgetSignature,
                lastCompleted: lastCompletedWidgetSignature,
                forceRefresh: forceWidgetRefresh
            ),
            savingsSignature: normalized(
                savingsSignature,
                lastCompleted: lastCompletedSavingsSignature,
                forceRefresh: forceSavingsRefresh
            ),
            notificationSignature: normalized(
                notificationSignature,
                lastCompleted: lastCompletedNotificationSignature,
                forceRefresh: forceNotificationRefresh
            )
        )

        guard candidate.hasWork else { return nil }

        if let pendingRequest, pendingRequest.equivalentWork(to: candidate) {
            return nil
        }

        latestGeneration += 1
        let request = ContentViewDeferredRefreshRequest(
            generation: latestGeneration,
            widgetSignature: candidate.widgetSignature,
            savingsSignature: candidate.savingsSignature,
            notificationSignature: candidate.notificationSignature
        )
        pendingRequest = request
        return request
    }

    mutating func cancelPending() {
        pendingRequest = nil
    }

    func isCurrent(_ request: ContentViewDeferredRefreshRequest) -> Bool {
        pendingRequest?.generation == request.generation
    }

    mutating func markWidgetRefreshCompleted(_ request: ContentViewDeferredRefreshRequest) {
        guard isCurrent(request), let signature = request.widgetSignature else { return }
        lastCompletedWidgetSignature = signature
        pendingRequest = pendingRequest.map {
            ContentViewDeferredRefreshRequest(
                generation: $0.generation,
                widgetSignature: nil,
                savingsSignature: $0.savingsSignature,
                notificationSignature: $0.notificationSignature
            )
        }
        clearPendingIfFinished()
    }

    mutating func markSavingsRefreshCompleted(_ request: ContentViewDeferredRefreshRequest) {
        guard isCurrent(request), let signature = request.savingsSignature else { return }
        lastCompletedSavingsSignature = signature
        pendingRequest = pendingRequest.map {
            ContentViewDeferredRefreshRequest(
                generation: $0.generation,
                widgetSignature: $0.widgetSignature,
                savingsSignature: nil,
                notificationSignature: $0.notificationSignature
            )
        }
        clearPendingIfFinished()
    }

    mutating func markNotificationRefreshCompleted(_ request: ContentViewDeferredRefreshRequest) {
        guard isCurrent(request), let signature = request.notificationSignature else { return }
        lastCompletedNotificationSignature = signature
        pendingRequest = pendingRequest.map {
            ContentViewDeferredRefreshRequest(
                generation: $0.generation,
                widgetSignature: $0.widgetSignature,
                savingsSignature: $0.savingsSignature,
                notificationSignature: nil
            )
        }
        clearPendingIfFinished()
    }

    private func normalized<T: Equatable>(
        _ signature: T?,
        lastCompleted: T?,
        forceRefresh: Bool
    ) -> T? {
        guard let signature else { return nil }
        if forceRefresh {
            return signature
        }
        return signature == lastCompleted ? nil : signature
    }

    private mutating func clearPendingIfFinished() {
        guard let pendingRequest else { return }
        if pendingRequest.hasWork == false {
            self.pendingRequest = nil
        }
    }
}
