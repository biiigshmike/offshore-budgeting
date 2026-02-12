//
//  NotificationsAppDelegate.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import Foundation
import UserNotifications

#if canImport(UIKit)
import UIKit

final class NotificationsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Ensures banners/sounds can present while the app is foregrounded
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.notificationCategories)
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let actionRaw = userInfo[LocalNotificationService.UserInfoKey.action] as? String,
              actionRaw == LocalNotificationService.NotificationAction.openQuickAddExpenseFromShoppingMode.rawValue else {
            completionHandler()
            return
        }

        Self.routeToQuickAdd(userInfo: userInfo)
        completionHandler()
    }

    // MARK: - Notification Actions

    private static var notificationCategories: Set<UNNotificationCategory> {
        let openAction = UNNotificationAction(
            identifier: LocalNotificationService.NotificationAction.openQuickAddExpenseFromShoppingMode.rawValue,
            title: "Add Expense",
            options: [.foreground]
        )

        let shoppingSuggestionCategory = UNNotificationCategory(
            identifier: LocalNotificationService.NotificationCategory.shoppingModeSuggestion,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        return [shoppingSuggestionCategory]
    }

    // MARK: - Routing

    private static func routeToQuickAdd(userInfo: [AnyHashable: Any]) {
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

}
#endif
