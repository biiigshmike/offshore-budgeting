import SwiftUI

struct PresetRowView: View {
    let preset: Preset
    let assignedBudgetsCount: Int

    var body: some View {
        PresetRowContent(
            title: preset.title,
            plannedAmount: preset.plannedAmount,
            scheduleText: PresetScheduleFormatter.humanReadableSchedule(for: preset),
            assignedBudgetsCount: assignedBudgetsCount
        )
    }
}
