//
//  PillDatePickerField.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct PillDatePickerField: View {

    let title: String
    @Binding var date: Date

    var minimumDate: Date?
    var maximumDate: Date?

    @State private var isPresented = false

    init(
        title: String,
        date: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil
    ) {
        self.title = title
        self._date = date
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
    }

    var body: some View {
        let dateText = formattedDate(date)

        Button {
            isPresented = true
        } label: {
            Text(dateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(dateText)")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    picker
                }
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let range = optionalClosedRange(minimumDate: minimumDate, maximumDate: maximumDate) {
            DatePicker("", selection: $date, in: range, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
        } else if let min = minimumDate {
            DatePicker("", selection: $date, in: min..., displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
        } else if let max = maximumDate {
            DatePicker("", selection: $date, in: ...max, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
        } else {
            DatePicker("", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
    }

    private func optionalClosedRange(minimumDate: Date?, maximumDate: Date?) -> ClosedRange<Date>? {
        guard let min = minimumDate, let max = maximumDate else { return nil }
        if max < min { return nil }
        return min...max
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }
}

struct PillTimePickerField: View {

    let title: String
    @Binding var time: Date

    @State private var isPresented = false

    init(title: String, time: Binding<Date>) {
        self.title = title
        self._time = time
    }

    var body: some View {
        let timeText = formattedTime(time)

        Button {
            isPresented = true
        } label: {
            Text(timeText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(timeText)")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
    }
}
