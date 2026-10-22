import SwiftUI

struct DateRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DateRangeDraft
    let onApply: (Date, Date) -> Void

    init(startDate: Date, endDate: Date, initialPreset: CalendarQuickRangePreset? = nil,
         onApply: @escaping (Date, Date) -> Void) {
        var initialDraft = DateRangeDraft(start: startDate, end: endDate)
        if let initialPreset { initialDraft.select(initialPreset) }
        _draft = State(initialValue: initialDraft)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        PillDatePickerField(
                            title: String(localized: "home.dateRange.startDate", defaultValue: "Start Date"),
                            date: $draft.start
                        )
                    } label: {
                        Text(String(localized: "home.dateRange.startDate", defaultValue: "Start Date"))
                    }
                    LabeledContent {
                        PillDatePickerField(
                            title: String(localized: "home.dateRange.endDate", defaultValue: "End Date"),
                            date: $draft.end
                        )
                    } label: {
                        Text(String(localized: "home.dateRange.endDate", defaultValue: "End Date"))
                    }
                } footer: {
                    if !draft.isValid {
                        Text(String(localized: "home.dateRange.invalidOrder", defaultValue: "End date must be on or after start date."))
                            .foregroundStyle(.red)
                    }
                }

            }
            .navigationTitle(Text(String(localized: "home.tip.dateRange.title", defaultValue: "Date Range")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text(String(localized: "common.cancel", defaultValue: "Cancel"))
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard draft.canApply else { return }
                        onApply(draft.start, draft.end)
                        dismiss()
                    } label: {
                        Text(String(localized: "home.dateRange.applyButton", defaultValue: "Apply"))
                    }
                    .disabled(!draft.canApply)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
