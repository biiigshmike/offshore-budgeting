import Foundation

/// A presentation-local copy: editing or dismissing it never changes the applied filter.
struct DateRangeEditorDraft: Identifiable {
    let id = UUID()
    var startDate: Date
    var endDate: Date

    func isValid(calendar: Calendar = .current) -> Bool {
        calendar.compare(startDate, to: endDate, toGranularity: .day) != .orderedDescending
    }
}
