import UserNotifications

struct NotificationSettingsSnapshot {
    let authorization: UNAuthorizationStatus
    let alerts: UNNotificationSetting
    let sounds: UNNotificationSetting
}
