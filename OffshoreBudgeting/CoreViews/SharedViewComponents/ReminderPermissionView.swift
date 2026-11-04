import SwiftUI

struct ReminderPermissionView: View {
    @ObservedObject var notificationService: LocalNotificationService
    let remindersEnabled: Bool
    let hasSelectedReminders: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.bold())
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if notificationService.authorizationState == .denied {
            return String(localized: "Reminders are blocked")
        }
        if remindersEnabled && hasSelectedReminders && notificationService.isAuthorized {
            return String(localized: "Reminders are on")
        }
        return String(localized: "Reminders are off")
    }

    private var summary: String {
        if notificationService.authorizationState == .denied {
            return String(localized: "To receive reminders, allow notifications in your device’s Settings.")
        }
        if !hasSelectedReminders {
            return String(localized: "Choose which reminders you’d like to receive.")
        }
        if !remindersEnabled {
            return String(localized: "Turn on Send Scheduled Reminders to receive your reminders.")
        }
        if notificationService.isAuthorized {
            return notificationService.deliveryDescription
        }
        return String(localized: "Allow notifications to receive your reminders.")
    }
}
