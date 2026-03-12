import SwiftUI

struct DateRangeFilterRow: View {
    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    let isGoEnabled: Bool
    let onTapGo: () -> Void
    let onSelectQuickRange: (CalendarQuickRangePreset) -> Void

    private var startDateTitle: String {
        String(localized: "dateRange.short.start", defaultValue: "Start", comment: "Short title for the start date picker pill.")
    }

    private var endDateTitle: String {
        String(localized: "dateRange.short.end", defaultValue: "End", comment: "Short title for the end date picker pill.")
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillDatePickerField(title: startDateTitle, date: $draftStartDate)
                    .layoutPriority(1)

                PillDatePickerField(title: endDateTitle, date: $draftEndDate)
                    .layoutPriority(1)

                DateRangeIconCircleButton(systemName: "arrow.right", isEnabled: isGoEnabled, action: onTapGo)
                    .accessibilityLabel(String(localized: "Apply Date Range", defaultValue: "Apply Date Range", comment: "Accessibility label for applying the selected date range."))

                Menu {
                    CalendarQuickRangeMenuItems { preset in
                        onSelectQuickRange(preset)
                    }
                } label: {
                    DateRangeIconCircleLabel(systemName: "calendar")
                }
                .accessibilityLabel(String(localized: "Quick Date Ranges", defaultValue: "Quick Date Ranges", comment: "Accessibility label for quick date range presets."))
            }

            Spacer(minLength: 0)
        }
    }
}

private struct DateRangeIconCircleButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct DateRangeIconCircleLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .tint(.primary)
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Circle())
    }
}
