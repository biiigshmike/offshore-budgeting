import UserNotifications

/// The system boundary is injectable so permission and scheduling can be tested without prompts.
@MainActor
protocol LocalNotificationCenter {
    func settings() async -> NotificationSettingsSnapshot
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func remove(identifiers: [String])
    func removeAll()
}
