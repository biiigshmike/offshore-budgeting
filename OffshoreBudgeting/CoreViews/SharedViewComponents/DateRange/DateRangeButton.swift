import SwiftUI

/// Keeps the editing session in the presentation, so dismissal never saves a draft.
struct DateRangeButton: View {
    let startDate: Date
    let endDate: Date
    var presentsSheet = false
    let onApply: (Date, Date) -> Void
    @State private var isPresented = false

    private var fullRange: String {
        "\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))"
    }

    var body: some View {
        Button { isPresented = true } label: {
            ViewThatFits(in: .horizontal) {
                rangeLabel(fullRange)
                rangeLabel("\(startDate.formatted(date: .numeric, time: .omitted)) – \(endDate.formatted(date: .numeric, time: .omitted))")
                Image(systemName: "calendar")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .accessibilityLabel(Text(String(localized: "home.tip.dateRange.title", defaultValue: "Date Range")))
        .accessibilityValue(fullRange)
        .accessibilityHint(Text(String(localized: "home.dateRange.changeHint", defaultValue: "Change the dates shown on Home.")))
        .sheet(isPresented: sheetPresentation) {
            editor
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .popover(isPresented: popoverPresentation) {
            editor
                .frame(idealWidth: 380, idealHeight: 360)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
        }
    }

    private var sheetPresentation: Binding<Bool> {
        Binding(get: { presentsSheet && isPresented }, set: { isPresented = $0 })
    }

    private var popoverPresentation: Binding<Bool> {
        Binding(get: { !presentsSheet && isPresented }, set: { isPresented = $0 })
    }

    private var editor: some View {
        DateRangeEditor(startDate: startDate, endDate: endDate, onApply: onApply)
    }

    private func rangeLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Label(text, systemImage: "calendar")
            Image(systemName: "chevron.down")
                .imageScale(.small)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44)
    }
}
