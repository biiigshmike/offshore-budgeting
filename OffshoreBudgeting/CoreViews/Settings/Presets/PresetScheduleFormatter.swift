import Foundation

enum PresetScheduleFormatter {

    static func humanReadableSchedule(for preset: Preset) -> String {
        let interval = max(1, preset.interval)
        let count = AppNumberFormat.integer(interval)

        switch preset.frequency {
        case .none:
            return String(localized: "preset.schedule.none", defaultValue: "Does not repeat")

        case .daily:
            if interval == 1 { return preset.frequency.displayName }
            return String(localized: "Every \(count) days")

        case .weekly:
            let weekday = weekdayName(for: preset.weeklyWeekday)
            if interval == 1 {
                return String(localized: "preset.schedule.weekly", defaultValue: "Every \(weekday)")
            }
            return String(localized: "preset.schedule.weeklyInterval", defaultValue: "Every \(count) weeks on \(weekday)")

        case .monthly:
            if preset.monthlyIsLastDay {
                if interval == 1 {
                    return String(localized: "preset.schedule.monthlyLastDay", defaultValue: "On the last day of each month")
                }
                return String(localized: "preset.schedule.monthlyLastDayInterval", defaultValue: "Every \(count) months on the last day")
            }
            let day = ordinalDay(preset.monthlyDayOfMonth)
            if interval == 1 {
                return String(localized: "preset.schedule.monthly", defaultValue: "On the \(day) of each month")
            }
            return String(localized: "preset.schedule.monthlyInterval", defaultValue: "Every \(count) months on the \(day)")

        case .yearly:
            let month = monthAbbreviation(for: preset.yearlyMonth)
            let day = AppNumberFormat.integer(max(1, min(31, preset.yearlyDayOfMonth)))
            if interval == 1 {
                return String(localized: "preset.schedule.yearly", defaultValue: "Every year on \(month) \(day)")
            }
            return String(localized: "preset.schedule.yearlyInterval", defaultValue: "Every \(count) years on \(month) \(day)")
        }
    }

    private static func weekdayName(for weekday: Int) -> String {
        let clamped = min(7, max(1, weekday))
        let symbols = Calendar.current.weekdaySymbols
        let index = clamped - 1
        return index < symbols.count ? symbols[index] : "Sunday"
    }

    private static func monthAbbreviation(for month: Int) -> String {
        let clamped = min(12, max(1, month))
        let symbols = Calendar.current.shortMonthSymbols
        let index = clamped - 1
        return index < symbols.count ? symbols[index] : "Jan"
    }

    private static func ordinalDay(_ day: Int) -> String {
        let d = max(1, min(31, day))
        if Locale.current.language.languageCode?.identifier == "es" {
            return AppNumberFormat.integer(d)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: d)) ?? AppNumberFormat.integer(d)
    }
}
