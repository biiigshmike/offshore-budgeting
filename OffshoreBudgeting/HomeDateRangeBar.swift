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

    var onApply: () -> Void

    @State private var presentedPicker: PresentedPicker?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                datePill(
                    title: draftStartDate,
                    accessibilityPrefix: "Start date"
                ) {
                    presentedPicker = .start
                }

                datePill(
                    title: draftEndDate,
                    accessibilityPrefix: "End date"
                ) {
                    presentedPicker = .end
                }

                Button(action: onApply) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
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
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick ranges")
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .sheet(item: $presentedPicker) { picker in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    DatePicker(
                        "",
                        selection: picker.binding(start: $draftStartDate, end: $draftEndDate),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
                .padding()
                .navigationTitle(picker.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            presentedPicker = nil
                        }
                    }
                }
            }
        }
    }

    private func datePill(
        title: Date,
        accessibilityPrefix: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(formattedDate(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix) \(formattedDate(title))")
    }

    private enum PresentedPicker: String, Identifiable {
        case start
        case end

        var id: String { rawValue }

        var title: String {
            switch self {
            case .start:
                return "Start Date"
            case .end:
                return "End Date"
            }
        }

        func binding(start: Binding<Date>, end: Binding<Date>) -> Binding<Date> {
            switch self {
            case .start:
                return start
            case .end:
                return end
            }
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
    }
}
