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
        UNUserNotificationCenter.current().delegate = self
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
        if let actionRaw = userInfo[LocalNotificationService.UserInfoKey.action] as? String,
           actionRaw == LocalNotificationService.NotificationAction.openQuickAddExpenseFromShoppingMode.rawValue {
            UserDefaults.standard.set(
                AppSection.cards.rawValue,
                forKey: AppShortcutNavigationStore.pendingSectionKey
            )
            UserDefaults.standard.set(
                AppShortcutNavigationStore.PendingAction.openQuickAddExpenseFromShoppingMode.rawValue,
                forKey: AppShortcutNavigationStore.pendingActionKey
            )
        }

        completionHandler()
    }
}
#endif
