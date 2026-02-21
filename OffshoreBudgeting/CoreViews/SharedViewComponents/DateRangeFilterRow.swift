import SwiftUI

struct DateRangeFilterRow: View {
    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    let isGoEnabled: Bool
    let onTapGo: () -> Void
    let onSelectQuickRange: (CalendarQuickRangePreset) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillDatePickerField(title: "Start Date", date: $draftStartDate)
                    .layoutPriority(1)

                PillDatePickerField(title: "End Date", date: $draftEndDate)
                    .layoutPriority(1)

                DateRangeIconCircleButton(systemName: "arrow.right", isEnabled: isGoEnabled, action: onTapGo)
                    .accessibilityLabel("Apply Date Range")

                Menu {
                    CalendarQuickRangeMenuItems { preset in
                        onSelectQuickRange(preset)
                    }
                } label: {
                    DateRangeIconCircleLabel(systemName: "calendar")
                }
                .accessibilityLabel("Quick Date Ranges")
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
