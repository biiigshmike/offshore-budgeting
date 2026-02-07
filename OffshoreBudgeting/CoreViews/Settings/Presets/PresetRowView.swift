//
//  PresetRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI

struct PresetRowView: View {

    let preset: Preset
    let assignedBudgetsCount: Int

    private var scheduleText: String {
        PresetScheduleFormatter.humanReadableSchedule(for: preset)
    }

    private var plannedText: String {
        preset.plannedAmount.formatted(CurrencyFormatter.currencyStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline) {
                Text(preset.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Text("Assigned Budgets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(localizedInt(assignedBudgetsCount))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .accessibilityHidden(true)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLANNED")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(plannedText)
                        .font(.body.weight(.semibold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("SCHEDULE")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(scheduleText)
                        .font(.body.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let budgetPhrase = assignedBudgetsCount == 1 ? "one budget" : "\(localizedInt(assignedBudgetsCount)) budgets"
        return "\(preset.title) preset. Planned \(plannedText). Runs \(scheduleText). Assigned to \(budgetPhrase)."
    }

    private func localizedInt(_ value: Int) -> String {
        value.formatted(.number)
    }
}

// MARK: - Schedule Formatting

private enum PresetScheduleFormatter {

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
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: d)) ?? localizedInt(d)
    }

    private static func localizedInt(_ value: Int) -> String {
        value.formatted(.number)
    }
}
