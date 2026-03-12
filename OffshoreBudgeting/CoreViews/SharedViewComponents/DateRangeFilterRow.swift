import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private enum DateRangePillMetrics {
    static let horizontalPadding: CGFloat = 12
    static let minimumScaleFactor: CGFloat = 0.75
}

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
        GeometryReader { proxy in
            let pillWidth = datePillWidth(for: proxy.size.width)
            let synchronizedScale = synchronizedDateScale(for: pillWidth)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    PillDatePickerField(
                        title: startDateTitle,
                        date: $draftStartDate,
                        synchronizedTextScale: synchronizedScale
                    )
                    .frame(width: pillWidth)

                    PillDatePickerField(
                        title: endDateTitle,
                        date: $draftEndDate,
                        synchronizedTextScale: synchronizedScale
                    )
                    .frame(width: pillWidth)

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
        .frame(height: 44)
    }

    private func datePillWidth(for totalWidth: CGFloat) -> CGFloat {
        let iconButtonWidth: CGFloat = 44
        let spacingWidth: CGFloat = 10 * 3
        let availableWidth = totalWidth - (iconButtonWidth * 2) - spacingWidth
        return max(0, availableWidth / 2)
    }

    private func synchronizedDateScale(for pillWidth: CGFloat) -> CGFloat {
        let availableTextWidth = max(0, pillWidth - (DateRangePillMetrics.horizontalPadding * 2))
        let longestDateWidth = max(
            measuredDateWidth(for: draftStartDate),
            measuredDateWidth(for: draftEndDate)
        )

        guard availableTextWidth > 0, longestDateWidth > 0 else { return 1 }

        let requiredScale = availableTextWidth / longestDateWidth
        return min(1, max(DateRangePillMetrics.minimumScaleFactor, requiredScale))
    }

    private func measuredDateWidth(for date: Date) -> CGFloat {
        let text = AppDateFormat.abbreviatedDate(date)

        #if canImport(UIKit)
        let descriptor = UIFont.preferredFont(forTextStyle: .subheadline).fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        ])
        let font = UIFont(descriptor: descriptor, size: 0)
        return (text as NSString).size(withAttributes: [.font: font]).width
        #else
        return 0
        #endif
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
