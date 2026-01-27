//
//  NotificationsAppDelegate.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//


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

        // Ensures banners/sounds can present while the app is foregrounded (great for testing).
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
}
#endif
