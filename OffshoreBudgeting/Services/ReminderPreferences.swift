import Foundation

/// Device-local reminder choices. Reading preferences never opts an existing user in.
struct ReminderPreferences: Equatable {
    enum Key {
        static let enabled = "notifications_enabled"
        static let hour = "notifications_reminderHour"
        static let minute = "notifications_reminderMinute"
        static let daily = "notifications_dailyExpenseReminderEnabled"
        static let income = "notifications_plannedIncomeReminderEnabled"
        static let preset = "notifications_presetDueReminderEnabled"
        static let configured = "notifications_remindersConfigured"
    }

    var enabled = false
    var daily = false
    var income = false
    var preset = false
    var hour = 20
    var minute = 0

    var hasSelectedReminders: Bool { daily || income || preset }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(
            enabled: defaults.bool(forKey: Key.enabled),
            daily: defaults.bool(forKey: Key.daily),
            income: defaults.bool(forKey: Key.income),
            preset: defaults.bool(forKey: Key.preset),
            hour: defaults.object(forKey: Key.hour) as? Int ?? 20,
            minute: defaults.object(forKey: Key.minute) as? Int ?? 0
        )
    }

    /// Defaults apply only to an unsaved setup draft, never to live scheduling.
    static func setupDraft(from defaults: UserDefaults = .standard) -> Self {
        var preferences = load(from: defaults)
        let hasSavedChoices = defaults.bool(forKey: Key.configured)
            || [Key.daily, Key.income, Key.preset].contains { defaults.object(forKey: $0) != nil }
        if !hasSavedChoices {
            preferences.daily = true
            preferences.income = true
            preferences.preset = true
        }
        return preferences
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(daily, forKey: Key.daily)
        defaults.set(income, forKey: Key.income)
        defaults.set(preset, forKey: Key.preset)
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(true, forKey: Key.configured)
    }

    var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    mutating func setTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? hour
        minute = parts.minute ?? minute
    }
}
