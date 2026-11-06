//
//  PresetFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct PresetFormView: View {
    
    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]
    
    @Binding var title: String
    @Binding var plannedAmountText: String
    
    @Binding var frequency: RecurrenceFrequency
    @Binding var interval: Int
    
    @Binding var weeklyWeekday: Int
    @Binding var monthlyDayOfMonth: Int
    @Binding var monthlyIsLastDay: Bool
    @Binding var yearlyMonth: Int
    @Binding var yearlyDayOfMonth: Int
    
    @Binding var selectedCardID: UUID?
    @Binding var selectedCategoryID: UUID?
    
    // MARK: - Validation (shared by Add + Edit)
    
    static func trimmedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func parsePlannedAmount(_ text: String) -> Double? {
        CurrencyFormatter.parseAmount(text)
    }
    
    static func canSave(
        title: String,
        plannedAmountText: String,
        selectedCardID: UUID?,
        hasAtLeastOneCard: Bool
    ) -> Bool {
        let t = trimmedTitle(title)
        guard !t.isEmpty else { return false }
        guard let amt = parsePlannedAmount(plannedAmountText), amt > 0 else { return false }
        guard hasAtLeastOneCard else { return false }
        guard selectedCardID != nil else { return false }
        return true
    }
    
    var body: some View {
        Form {
            
            Section("Details") {
                if cards.isEmpty {
                    Text("No cards yet. Create a card first to set a default.")
                        .foregroundStyle(.secondary)
                } else {
                    EntityMenuPicker(title: "Card", items: cards, selection: $selectedCardID, allowsEmptySelection: false, showsTitle: false) { card in
                        CardMenuLabel(card: card)
                    }
                }

                TextField("Expense Name", text: $title)
                TextField("Planned Amount", text: $plannedAmountText)
                    .keyboardType(.decimalPad)

                EntityMenuPicker(title: "Category", items: categories, selection: $selectedCategoryID, showsTitle: false) { category in
                    CategoryMenuLabel(category: category)
                }
            }

            Section("Schedule") {
                
                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                
                Stepper(value: $interval, in: 1...365) {
                    Text(interval == 1 ? "Interval: \(localizedInt(1))" : "Interval: \(localizedInt(interval))")
                }
                .disabled(frequency == .none)
                
                scheduleAnchorSection
                
                Text(scheduleHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var scheduleAnchorSection: some View {
        switch frequency {
        case .none:
            EmptyView()
            
        case .daily:
            EmptyView()
            
        case .weekly:
            Picker("Weekday", selection: $weeklyWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(weekdayName(day)).tag(day)
                }
            }
            
        case .monthly:
            Toggle("Last Day of Month", isOn: $monthlyIsLastDay)
                .tint(Color("AccentColor"))
            
            if !monthlyIsLastDay {
                Picker("Day of Month", selection: $monthlyDayOfMonth) {
                    ForEach(1...31, id: \.self) { day in
                        Text(localizedInt(day)).tag(day)
                    }
                }
            }
            
        case .yearly:
            Picker("Month", selection: $yearlyMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(monthName(m)).tag(m)
                }
            }
            
            Picker("Day", selection: $yearlyDayOfMonth) {
                ForEach(1...31, id: \.self) { day in
                    Text(localizedInt(day)).tag(day)
                }
            }
        }
    }
    
    // MARK: - Ordinal helper (1st, 2nd, 3rd, 4th...)
    
    private func ordinal(_ number: Int) -> String {
        let n = abs(number)
        if Locale.current.identifier.hasPrefix("es") {
            return localizedInt(n)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: n)) ?? localizedInt(n)
    }
    
    
    private var scheduleHelpText: String {
        switch frequency {
        case .none:
            return "This expense does not repeat."
            
        case .daily:
            return interval == 1
            ? "An expense that repeats daily."
            : "An expense that repeats every \(localizedInt(interval)) days."
            
        case .weekly:
            let day = weekdayName(weeklyWeekday)
            return interval == 1
            ? "An expense that repeats weekly on \(day)."
            : "An expense that repeats every \(localizedInt(interval)) weeks on \(day)."
            
        case .monthly:
            if monthlyIsLastDay {
                return interval == 1
                ? "An expense that repeats on the last day of every month."
                : "An expense that repeats on the last day of every \(localizedInt(interval)) months."
            } else {
                let day = ordinal(monthlyDayOfMonth)
                return interval == 1
                ? "An expense that repeats on the \(day) of every month."
                : "An expense that repeats on the \(day) of every \(localizedInt(interval)) months."
            }
            
        case .yearly:
            let month = monthName(yearlyMonth)
            let day = ordinal(yearlyDayOfMonth)
            return interval == 1
            ? "An expense that repeats yearly on \(month) \(day)."
            : "An expense that repeats every \(localizedInt(interval)) years on \(month) \(day)."
        }
    }
    
    private func weekdayName(_ weekday: Int) -> String {
        let clamped = min(7, max(1, weekday))
        let symbols = Calendar.current.weekdaySymbols
        let index = clamped - 1
        return index < symbols.count ? symbols[index] : "Sunday"
    }
    
    private func monthName(_ month: Int) -> String {
        let clamped = min(12, max(1, month))
        let symbols = Calendar.current.monthSymbols
        let index = clamped - 1
        return index < symbols.count ? symbols[index] : "January"
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}
