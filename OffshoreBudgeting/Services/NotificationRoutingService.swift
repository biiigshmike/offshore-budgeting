//
//  NotificationRoutingService.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/22/26.
//

import Foundation
import UserNotifications

// MARK: - NotificationRoutingService

final class NotificationRoutingService {
    static let shared = NotificationRoutingService()

    private init() {}

    // MARK: - Configuration

    func configure(delegate: UNUserNotificationCenterDelegate?) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories(notificationCategories)
    }

    // MARK: - Presentation

    func presentationOptions(for _: UNNotification) -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // MARK: - Routing

    func handleResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        if let explicitAction = LocalNotificationService.NotificationAction(rawValue: actionIdentifier) {
            route(for: explicitAction, userInfo: userInfo)
            return
        }

        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        if let userInfoAction = userInfo[LocalNotificationService.UserInfoKey.action] as? String,
           let explicitAction = LocalNotificationService.NotificationAction(rawValue: userInfoAction) {
            route(for: explicitAction, userInfo: userInfo)
            return
        }

        guard let kindRaw = userInfo[LocalNotificationService.UserInfoKey.notificationKind] as? String,
              let kind = LocalNotificationService.NotificationKind(rawValue: kindRaw) else {
            return
        }

        switch kind {
        case .dailyExpenseReminder:
            routeToCards()
        case .plannedIncomeReminder:
            routeToQuickAddIncome()
        case .presetDueReminder:
            routeToBudgets()
        case .shoppingModeSuggestion:
            routeToQuickAddExpense(userInfo: userInfo)
        }
    }

    private func route(for action: LocalNotificationService.NotificationAction, userInfo: [AnyHashable: Any]) {
        switch action {
        case .openCards:
            routeToCards()
        case .openBudgets:
            routeToBudgets()
        case .openQuickAddIncome:
            routeToQuickAddIncome()
        case .openQuickAddExpenseFromShoppingMode:
            routeToQuickAddExpense(userInfo: userInfo)
        }
    }

    private func routeToCards() {
        UserDefaults.standard.set(
            AppSection.cards.rawValue,
            forKey: AppShortcutNavigationStore.pendingSectionKey
        )
        UserDefaults.standard.set("", forKey: AppShortcutNavigationStore.pendingActionKey)
        UserDefaults.standard.removeObject(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
    }

    private func routeToBudgets() {
        UserDefaults.standard.set(
            AppSection.budgets.rawValue,
            forKey: AppShortcutNavigationStore.pendingSectionKey
        )
        UserDefaults.standard.set("", forKey: AppShortcutNavigationStore.pendingActionKey)
        UserDefaults.standard.removeObject(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
    }

    private func routeToQuickAddIncome() {
        UserDefaults.standard.set(
            AppSection.income.rawValue,
            forKey: AppShortcutNavigationStore.pendingSectionKey
        )
        UserDefaults.standard.set(
            AppShortcutNavigationStore.PendingAction.openQuickAddIncome.rawValue,
            forKey: AppShortcutNavigationStore.pendingActionKey
        )
        UserDefaults.standard.removeObject(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
    }

    private func routeToQuickAddExpense(userInfo: [AnyHashable: Any]) {
        let merchantName = (userInfo[LocalNotificationService.UserInfoKey.merchantName] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        UserDefaults.standard.set(
            AppSection.cards.rawValue,
            forKey: AppShortcutNavigationStore.pendingSectionKey
        )
        UserDefaults.standard.set(
            AppShortcutNavigationStore.PendingAction.openQuickAddExpenseFromShoppingMode.rawValue,
            forKey: AppShortcutNavigationStore.pendingActionKey
        )

        if let merchantName, !merchantName.isEmpty {
            UserDefaults.standard.set(
                merchantName,
                forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
        }
    }

    // MARK: - Notification Categories

    private var notificationCategories: Set<UNNotificationCategory> {
        let openCardsAction = UNNotificationAction(
            identifier: LocalNotificationService.NotificationAction.openCards.rawValue,
            title: "Open Cards",
            options: [.foreground]
        )

        let openBudgetsAction = UNNotificationAction(
            identifier: LocalNotificationService.NotificationAction.openBudgets.rawValue,
            title: "Open Budgets",
            options: [.foreground]
        )

        let openQuickAddIncomeAction = UNNotificationAction(
            identifier: LocalNotificationService.NotificationAction.openQuickAddIncome.rawValue,
            title: "Add Income",
            options: [.foreground]
        )

        let openAction = UNNotificationAction(
            identifier: LocalNotificationService.NotificationAction.openQuickAddExpenseFromShoppingMode.rawValue,
            title: "Add Expense",
            options: [.foreground]
        )

        let dailyExpenseCategory = UNNotificationCategory(
            identifier: LocalNotificationService.NotificationCategory.dailyExpenseReminder,
            actions: [openCardsAction],
            intentIdentifiers: [],
            options: []
        )

        let plannedIncomeCategory = UNNotificationCategory(
            identifier: LocalNotificationService.NotificationCategory.plannedIncomeReminder,
            actions: [openQuickAddIncomeAction],
            intentIdentifiers: [],
            options: []
        )

        let presetDueCategory = UNNotificationCategory(
            identifier: LocalNotificationService.NotificationCategory.presetDueReminder,
            actions: [openBudgetsAction],
            intentIdentifiers: [],
            options: []
        )

        let shoppingSuggestionCategory = UNNotificationCategory(
            identifier: LocalNotificationService.NotificationCategory.shoppingModeSuggestion,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        return [
            dailyExpenseCategory,
            plannedIncomeCategory,
            presetDueCategory,
            shoppingSuggestionCategory
        ]
    }
}
