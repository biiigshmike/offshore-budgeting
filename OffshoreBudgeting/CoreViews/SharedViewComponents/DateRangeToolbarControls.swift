import SwiftUI
import UIKit

struct DateRangeToolbarControls: View {
    let startDate: Date
    let endDate: Date
    var isEnabled: Bool = true
    var usesNeutralMacEditor = false
    let onApply: (Date, Date) -> Void
    let onSelectQuickRange: (CalendarQuickRangePreset) -> Void

    @Environment(\.appearanceTheme) private var theme
    @State private var editorDraft: DateRangeEditorDraft?

    var body: some View {
        let editorButton = Button {
            editorDraft = DateRangeEditorDraft(startDate: startDate, endDate: endDate)
        } label: {
            let label = Label("Date Range", systemImage: "calendar.badge.clock")
            #if targetEnvironment(macCatalyst)
            if usesNeutralMacEditor {
                label.foregroundStyle(theme.accent)
            } else {
                label
            }
            #else
            label
            #endif
        }
        .accessibilityLabel("Date Range")
        .accessibilityValue("\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))")
        .accessibilityIdentifier("dateRange.editor")
        .help("Edit Date Range")
        .disabled(!isEnabled)

        #if targetEnvironment(macCatalyst)
        let styledEditorButton = usesNeutralMacEditor ? AnyView(editorButton.tint(nil)) : AnyView(editorButton)
        #else
        let styledEditorButton = editorButton
        #endif

        if UIDevice.current.userInterfaceIdiom == .phone {
            styledEditorButton.appSheet(item: $editorDraft) { draft in
                DateRangeEditorView(draft: draft, onApply: onApply)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        } else {
            styledEditorButton
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
