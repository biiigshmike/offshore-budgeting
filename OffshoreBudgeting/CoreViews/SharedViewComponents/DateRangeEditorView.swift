import SwiftUI

struct DateRangeEditorView: View {
    let onApply: (Date, Date) -> Void

    @State private var draft: DateRangeEditorDraft
    @Environment(\.dismiss) private var dismiss

    init(draft: DateRangeEditorDraft, onApply: @escaping (Date, Date) -> Void) {
        _draft = State(initialValue: draft)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    #if targetEnvironment(macCatalyst)
                    HStack {
                        Text("Start Date")
                        Spacer()
                        PillDatePickerField(title: "Start Date", date: $draft.startDate)
                            .accessibilityIdentifier("dateRange.start")
                    }

                    HStack {
                        Text("End Date")
                        Spacer()
                        PillDatePickerField(title: "End Date", date: $draft.endDate)
                            .accessibilityIdentifier("dateRange.end")
                    }
                    #else
                    DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("dateRange.start")

                    DatePicker("End Date", selection: $draft.endDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("dateRange.end")
                    #endif

                    if !draft.isValid() {
                        Text("End date must be on or after start date.")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("dateRange.validation")
                    }
                }
                .padding()
            }
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: applyAndDismiss)
                        .disabled(!draft.isValid())
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("dateRange.done")
                }
            }
        }
    }

    private func applyAndDismiss() {
        guard draft.isValid() else { return }
        onApply(draft.startDate, draft.endDate)
        dismiss()
    }
}
