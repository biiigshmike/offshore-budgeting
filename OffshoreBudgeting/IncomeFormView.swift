//
//  IncomeFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI

struct IncomeFormView: View {

    let detailsTitle: String

    @Binding var source: String
    @Binding var amountText: String
    @Binding var date: Date
    @Binding var isPlanned: Bool

    // Series / recurrence fields
    @Binding var frequencyRaw: String
    @Binding var interval: Int
    @Binding var weeklyWeekday: Int
    @Binding var monthlyDayOfMonth: Int
    @Binding var monthlyIsLastDay: Bool
    @Binding var yearlyMonth: Int
    @Binding var yearlyDayOfMonth: Int
    @Binding var endDate: Date?

    private var frequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequencyRaw) ?? .none
    }

    var body: some View {
        Form {

            // MARK: - Type

            Section("Type") {
                Picker("Type", selection: $isPlanned) {
                    Text("Planned").tag(true)
                    Text("Actual").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // MARK: - Details

            Section(detailsTitle) {
                TextField("Source", text: $source)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $date)
                }
            }

            // MARK: - Repeat

            Section("Repeat") {
                Picker("Repeat", selection: $frequencyRaw) {
                    ForEach(RecurrenceFrequency.allCases) { f in
                        Text(f.displayName).tag(f.rawValue)
                    }
                }

                if frequency != .none {
                    Stepper("Every \(max(1, interval))", value: $interval, in: 1...52)

                    switch frequency {
                    case .daily:
                        EmptyView()

                    case .weekly:
                        Picker("Weekday", selection: $weeklyWeekday) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(Self.weekdayName(for: weekday)).tag(weekday)
                            }
                        }

                    case .monthly:
                        Toggle("Last day of month", isOn: $monthlyIsLastDay)

                        if !monthlyIsLastDay {
                            Stepper("Day \(monthlyDayOfMonth)", value: $monthlyDayOfMonth, in: 1...31)
                        }

                    case .yearly:
                        Picker("Month", selection: $yearlyMonth) {
                            ForEach(1...12, id: \.self) { m in
                                Text(Self.monthName(for: m)).tag(m)
                            }
                        }
                        Stepper("Day \(yearlyDayOfMonth)", value: $yearlyDayOfMonth, in: 1...31)

                    case .none:
                        EmptyView()
                    }

                    HStack {
                        Text("End Date")
                        Spacer()
                        PillDatePickerField(
                            title: "End Date",
                            date: Binding(
                                get: { endDate ?? date },
                                set: { endDate = $0 }
                            ),
                            minimumDate: date
                        )
                    }
                }
            }
        }
    }

    private static func weekdayName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols // Sunday first in US locale, but weekday index is Calendar weekday
        let index = max(1, min(7, weekday)) - 1
        return symbols[index]
    }

    private static func monthName(for month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        let index = max(1, min(12, month)) - 1
        return symbols[index]
    }
}
