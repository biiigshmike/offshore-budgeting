//
//  HomeDateRangeBar.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeDateRangeBar: View {

    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    /// Parent decides this
    let isApplyEnabled: Bool
    var onApply: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillDatePickerField(title: "Start Date", date: $draftStartDate)
                PillDatePickerField(title: "End Date", date: $draftEndDate)

                Button(action: onApply) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(isApplyEnabled
                                      ? Color.accentColor.opacity(0.85)
                                      : Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isApplyEnabled)
                .accessibilityLabel("Apply date range")

                Menu {
                    CalendarQuickRangeMenuItems { preset in
                        applyQuickRange(preset)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick ranges")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            Color("HomeTileColor"),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func applyQuickRange(_ preset: CalendarQuickRangePreset) {
        let range = preset.makeRange(now: Date(), calendar: .current)
        draftStartDate = range.start
        draftEndDate = range.end

        // Keep it sane if the user has end < start
        if draftEndDate < draftStartDate {
            draftEndDate = draftStartDate
        }

        // Match CardDetailView behavior: quick range selection auto-applies the range.
        // Defer to the next run loop so the menu can dismiss cleanly.
        let apply = onApply
        DispatchQueue.main.async {
            apply()
        }
    }
}
