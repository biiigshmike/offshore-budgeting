//
//  HomeDateRangeBar.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeDateRangeBar: View {

    enum QuickRange: String, CaseIterable, Identifiable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case last30Days = "Last 30 Days"
        case thisYear = "This Year"

        var id: String { rawValue }
    }

    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    /// Parent decides this (draft differs from applied, or whatever your logic is).
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
                    ForEach(QuickRange.allCases) { range in
                        Button(range.rawValue) {
                            applyQuickRange(range)
                        }
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
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private func applyQuickRange(_ range: QuickRange) {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            draftStartDate = start
            draftEndDate = end

        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            let lastMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: lastMonthStart) ?? now
            draftStartDate = lastMonthStart
            draftEndDate = lastMonthEnd

        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
            draftStartDate = start
            draftEndDate = now

        case .thisYear:
            let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1)) ?? now
            let end = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 12, day: 31)) ?? now
            draftStartDate = start
            draftEndDate = end
        }

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
