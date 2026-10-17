import Foundation

enum PresetScheduleFormatter {

    static func humanReadableSchedule(for preset: Preset) -> String {
        let freq = preset.frequency
        let interval = max(1, preset.interval)

        switch freq {
        case .none:
            return "None"

        case .daily:
            if interval == 1 { return "Daily" }
            return "Every \(localizedInt(interval)) days"

        case .weekly:
            let weekday = weekdayName(for: preset.weeklyWeekday)
            if interval == 1 { return "Weekly • \(weekday)" }
            return "Every \(localizedInt(interval)) weeks • \(weekday)"

        case .monthly:
            let anchor: String
            if preset.monthlyIsLastDay {
                anchor = "Last day"
            } else {
                anchor = ordinalDay(preset.monthlyDayOfMonth)
            }

            if interval == 1 { return "Monthly • \(anchor)" }
            return "Every \(localizedInt(interval)) months • \(anchor)"

        case .yearly:
            let month = monthAbbreviation(for: preset.yearlyMonth)
            let day = ordinalDay(preset.yearlyDayOfMonth)
            let anchor = "\(month) \(day)"

            if interval == 1 { return "Yearly • \(anchor)" }
            return "Every \(localizedInt(interval)) years • \(anchor)"
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
        if Locale.current.identifier.hasPrefix("es") {
            return localizedInt(d)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: d)) ?? localizedInt(d)
    }

    private static func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}
