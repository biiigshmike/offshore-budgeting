import SwiftUI

/// Shared ordering and glass styling for the tab accessory and wider Home layouts.
@available(iOS 26.0, macCatalyst 26.0, *)
struct HomeDateRangeControls: View {
    let startDate: Date
    let endDate: Date
    var presentsSheet = false
    let onApply: (Date, Date) -> Void
    @State private var selectedQuickRange: CalendarQuickRangePreset?

    var body: some View {
        HStack(spacing: 12) {
            DateRangeButton(startDate: startDate, endDate: endDate,
                            presentsSheet: presentsSheet, onApply: onApply)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)

            Menu {
                CalendarQuickRangeMenuItems { preset in
                    selectedQuickRange = preset
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityLabel(String(localized: "home.dateRange.quickRanges", defaultValue: "Quick ranges"))
            .accessibilityIdentifier("home.quickRanges")
            .popover(item: $selectedQuickRange) { preset in
                DateRangeEditor(startDate: startDate, endDate: endDate,
                                initialPreset: preset, onApply: onApply)
                    .frame(idealWidth: 380, idealHeight: 360)
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .foregroundStyle(.primary)
        .tint(.primary)
        .frame(maxWidth: 600)
    }
}
