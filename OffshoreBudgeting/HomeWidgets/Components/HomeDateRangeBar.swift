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

    @State private var actionDiameter: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillDatePickerField(title: String(localized: "home.dateRange.startDate", defaultValue: "Start Date", comment: "Label for start date picker on Home date range bar."), date: $draftStartDate)
                    .layoutPriority(1)
                PillDatePickerField(title: String(localized: "home.dateRange.endDate", defaultValue: "End Date", comment: "Label for end date picker on Home date range bar."), date: $draftEndDate)
                    .layoutPriority(1)

                Button(action: onApply) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: actionDiameter, height: actionDiameter)
                        .background(
                            Circle()
                                .fill(isApplyEnabled
                                      ? Color.accentColor.opacity(0.85)
                                      : Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isApplyEnabled)
                .accessibilityLabel(String(localized: "home.dateRange.apply", defaultValue: "Apply date range", comment: "Accessibility label for applying home date range filter."))

                Menu {
                    CalendarQuickRangeMenuItems { preset in
                        applyQuickRange(preset)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: actionDiameter, height: actionDiameter)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "home.dateRange.quickRanges", defaultValue: "Quick ranges", comment: "Accessibility label for quick date ranges menu on Home."))
            }

            Spacer(minLength: 0)
        }
        .onPreferenceChange(DateRangePillHeightKey.self) { height in
            if height > 0 { actionDiameter = height }
        }
        .padding(.horizontal, 12)
        #if targetEnvironment(macCatalyst)
        .padding(.vertical, 6)
        #else
        .padding(.vertical, 12)
        #endif
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
