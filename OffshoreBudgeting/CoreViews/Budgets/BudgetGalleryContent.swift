import SwiftUI

struct BudgetGalleryContent: View {
    let budget: Budget

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    private var dateRange: String {
        let currentYear = calendar.component(.year, from: .now)
        let includesYear = calendar.component(.year, from: budget.startDate) != currentYear
            || calendar.component(.year, from: budget.endDate) != currentYear
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateTemplate = includesYear ? "yMMMd" : "MMMd"
        return formatter.string(from: budget.startDate, to: budget.endDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(budget.name)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .accessibilityLabel(Text(budget.name))
            Text(dateRange)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}
