//
//  ContentViewResumeCoordinator.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/13/26.
//

import Foundation

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

struct ContentViewResumeCoordinator {
    private(set) var latestGeneration: Int = 0
    private(set) var pendingRequest: ContentViewDeferredRefreshRequest? = nil

    private(set) var lastCompletedWidgetSignature: ContentViewWidgetRefreshSignature? = nil
    private(set) var lastCompletedSavingsSignature: ContentViewSavingsRefreshSignature? = nil
    private(set) var lastCompletedNotificationSignature: ContentViewNotificationRefreshSignature? = nil

    mutating func schedule(
        widgetSignature: ContentViewWidgetRefreshSignature?,
        savingsSignature: ContentViewSavingsRefreshSignature?,
        notificationSignature: ContentViewNotificationRefreshSignature?
    ) -> ContentViewDeferredRefreshRequest? {
        let candidate = ContentViewDeferredRefreshRequest(
            generation: latestGeneration + 1,
            widgetSignature: normalized(widgetSignature, lastCompleted: lastCompletedWidgetSignature),
            savingsSignature: normalized(savingsSignature, lastCompleted: lastCompletedSavingsSignature),
            notificationSignature: normalized(notificationSignature, lastCompleted: lastCompletedNotificationSignature)
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

    private func normalized<T: Equatable>(_ signature: T?, lastCompleted: T?) -> T? {
        guard let signature else { return nil }
        return signature == lastCompleted ? nil : signature
    }

    private mutating func clearPendingIfFinished() {
        guard let pendingRequest else { return }
        if pendingRequest.hasWork == false {
            self.pendingRequest = nil
        }
    }
}
