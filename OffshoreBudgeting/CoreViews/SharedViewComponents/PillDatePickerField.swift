//
//  PillDatePickerField.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Presentation Metrics

private enum PillPickerSheetMetrics {
    static let sheetHeight: CGFloat = 520
    static let datePickerContentHeight: CGFloat = 340
    static let timePickerContentHeight: CGFloat = 240
}

private enum PillPickerPopoverMetrics {
    static let datePickerWidth: CGFloat = 320
    static let datePickerHeight: CGFloat = 320
    static let timePickerWidth: CGFloat = 280
    static let timePickerHeight: CGFloat = 200
}

private enum PillPickerPlatform {
    static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
}

private extension View {
    @ViewBuilder
    func platformCalendarDatePickerStyle(useWheelOnPhoneLandscape: Bool) -> some View {
        if useWheelOnPhoneLandscape {
            self.datePickerStyle(.wheel)
        } else {
            self.datePickerStyle(.graphical)
        }
    }

    @ViewBuilder
    func platformTimePickerStyle(useWheel: Bool) -> some View {
        if useWheel {
            self.datePickerStyle(.wheel)
        } else {
            self.datePickerStyle(.compact)
        }
    }
}

struct PillDatePickerField: View {

    @Environment(\.verticalSizeClass) private var verticalSizeClass

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

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var useWheelOnPhoneLandscape: Bool {
        isPhone && verticalSizeClass == .compact
    }

    var body: some View {
        let dateText = formattedDate(date)

        if PillPickerPlatform.isMacCatalyst {
            triggerButton(text: dateText, accessibilityText: "\(title) \(dateText)")
                .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    macPopoverContent
                        .presentationCompactAdaptation(.popover)
                }
        } else {
            triggerButton(text: dateText, accessibilityText: "\(title) \(dateText)")
                .sheet(isPresented: $isPresented) {
                    mobileSheetContent
                }
        }
    }

    private func triggerButton(text: String, accessibilityText: String) -> some View {
        Button {
            isPresented = true
        } label: {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var mobileSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                pickerContainer
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.automatic)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .modifier(PillPickerSheetPresentationModifier())
    }

    private var macPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            picker
                .frame(height: PillPickerPopoverMetrics.datePickerHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: PillPickerPopoverMetrics.datePickerWidth, alignment: .topLeading)
        .transaction { txn in
            txn.animation = nil
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let range = optionalClosedRange(minimumDate: minimumDate, maximumDate: maximumDate) {
            datePickerContent(selection: $date, range: .bounded(range))
        } else if let minimumDate {
            datePickerContent(selection: $date, range: .minimum(minimumDate))
        } else if let maximumDate {
            datePickerContent(selection: $date, range: .maximum(maximumDate))
        } else {
            datePickerContent(selection: $date, range: .unbounded)
        }
    }

    @ViewBuilder
    private func datePickerContent(selection: Binding<Date>, range: DatePickerRange) -> some View {
        switch range {
        case .bounded(let bounded):
            DatePicker("", selection: selection, in: bounded, displayedComponents: [.date])
                .platformCalendarDatePickerStyle(useWheelOnPhoneLandscape: useWheelOnPhoneLandscape)
                .labelsHidden()
        case .minimum(let minimum):
            DatePicker("", selection: selection, in: minimum..., displayedComponents: [.date])
                .platformCalendarDatePickerStyle(useWheelOnPhoneLandscape: useWheelOnPhoneLandscape)
                .labelsHidden()
        case .maximum(let maximum):
            DatePicker("", selection: selection, in: ...maximum, displayedComponents: [.date])
                .platformCalendarDatePickerStyle(useWheelOnPhoneLandscape: useWheelOnPhoneLandscape)
                .labelsHidden()
        case .unbounded:
            DatePicker("", selection: selection, displayedComponents: [.date])
                .platformCalendarDatePickerStyle(useWheelOnPhoneLandscape: useWheelOnPhoneLandscape)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var pickerContainer: some View {
        ScrollView(.vertical) {
            picker
                .frame(height: PillPickerSheetMetrics.datePickerContentHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .transaction { txn in
            txn.animation = nil
        }
    }

    private enum DatePickerRange {
        case bounded(ClosedRange<Date>)
        case minimum(Date)
        case maximum(Date)
        case unbounded
    }

    private func optionalClosedRange(minimumDate: Date?, maximumDate: Date?) -> ClosedRange<Date>? {
        guard let min = minimumDate, let max = maximumDate else { return nil }
        if max < min { return nil }
        return min...max
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
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

        if PillPickerPlatform.isMacCatalyst {
            triggerButton(text: timeText, accessibilityText: "\(title) \(timeText)")
                .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    macPopoverContent
                        .presentationCompactAdaptation(.popover)
                }
        } else {
            triggerButton(text: timeText, accessibilityText: "\(title) \(timeText)")
                .sheet(isPresented: $isPresented) {
                    mobileSheetContent
                }
        }
    }

    private func triggerButton(text: String, accessibilityText: String) -> some View {
        Button {
            isPresented = true
        } label: {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var mobileSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.vertical) {
                    DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                        .platformTimePickerStyle(useWheel: true)
                        .labelsHidden()
                        .frame(height: PillPickerSheetMetrics.timePickerContentHeight, alignment: .top)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transaction { txn in
                    txn.animation = nil
                }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.automatic)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .modifier(PillPickerSheetPresentationModifier())
    }

    private var macPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                .platformTimePickerStyle(useWheel: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(
            width: PillPickerPopoverMetrics.timePickerWidth,
            height: PillPickerPopoverMetrics.timePickerHeight,
            alignment: .topLeading
        )
        .transaction { txn in
            txn.animation = nil
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened))
    }
}

// MARK: - Sheet presentation (platform-tuned)

private struct PillPickerSheetPresentationModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .presentationDetents([.height(PillPickerSheetMetrics.sheetHeight)])
            .presentationDragIndicator(.visible)
    }
}
