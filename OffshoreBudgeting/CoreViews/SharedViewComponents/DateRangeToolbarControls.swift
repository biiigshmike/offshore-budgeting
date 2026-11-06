import SwiftUI
import UIKit

struct DateRangeToolbarControls: View {
    let startDate: Date
    let endDate: Date
    var isEnabled: Bool = true
    let onApply: (Date, Date) -> Void
    let onSelectQuickRange: (CalendarQuickRangePreset) -> Void

    @State private var editorDraft: DateRangeEditorDraft?

    var body: some View {
        let editorButton = Button {
            editorDraft = DateRangeEditorDraft(startDate: startDate, endDate: endDate)
        } label: {
            Label("Date Range", systemImage: "calendar.badge.clock")
        }
        .accessibilityLabel("Date Range")
        .accessibilityValue("\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))")
        .accessibilityIdentifier("dateRange.editor")
        .help("Edit Date Range")
        .disabled(!isEnabled)

        if UIDevice.current.userInterfaceIdiom == .phone {
            editorButton.appSheet(item: $editorDraft) { draft in
                DateRangeEditorView(draft: draft, onApply: onApply)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        } else {
            editorButton
                .blocksAutomaticExpenseReview(while: editorDraft != nil)
                .popover(item: $editorDraft, arrowEdge: .top) { draft in
                    DateRangeEditorView(draft: draft, onApply: onApply)
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440,
                               minHeight: 200, idealHeight: 260, maxHeight: 400)
                        .presentationCompactAdaptation(.popover)
                }
        }

        Menu {
            CalendarQuickRangeMenuItems(onSelect: onSelectQuickRange)
        } label: {
            Label("Date Ranges", systemImage: "calendar")
        }
        .accessibilityLabel("Quick Date Ranges")
        .accessibilityIdentifier("dateRange.quickRanges")
        .help("Quick Date Ranges")
        .disabled(!isEnabled)
    }
}
