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
        let canSave = PresetFormView.canSave(
            title: title,
            plannedAmountText: plannedAmountText,
            selectedCardID: selectedCardID,
            hasAtLeastOneCard: !cards.isEmpty
        )

        Form {

            Section("Card") {
                if cards.isEmpty {
                    Text("No cards yet. Create a card first to set a default.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cards) { card in
                                CardTile(
                                    title: card.name,
                                    themeRaw: card.theme,
                                    effectRaw: card.effect,
                                    isSelected: selectedCardID == card.id
                                ) {
                                    selectedCardID = card.id
                                }
                                .accessibilityLabel(selectedCardID == card.id ? "\(card.name), selected" : "\(card.name)")
                                .accessibilityHint("Double tap to set as default card.")
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    if selectedCardID == nil {
                        Text("Select a default card to continue.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Category") {
                Picker("Default Category", selection: $selectedCategoryID) {
                    Text("None").tag(UUID?.none)

                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }

            Section("Details") {
                TextField("Expense Name", text: $title)

                TextField("Planned Amount", text: $plannedAmountText)
                    .keyboardType(.decimalPad)
            }

            Section("Schedule") {

                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }

                Stepper(value: $interval, in: 1...365) {
                    Text(interval == 1 ? "Interval: 1" : "Interval: \(interval)")
                }
                .disabled(frequency == .none)

                scheduleAnchorSection

                Text(scheduleHelpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !canSave {
//                Section {
//                    VStack(alignment: .leading, spacing: 6) {
//                        if PresetFormView.trimmedTitle(title).isEmpty {
//                            Text("Enter an expense name.")
//                        }
//
//                        let planned = PresetFormView.parsePlannedAmount(plannedAmountText) ?? 0
//                        if planned <= 0 {
//                            Text("Enter a planned amount greater than 0.")
//                        }
//
//                        if cards.isEmpty {
//                            Text("Create a card first.")
//                        } else if selectedCardID == nil {
//                            Text("Select a default card.")
//                        }
//                    }
//                    .foregroundStyle(.secondary)
//                }
            }

//            Section {
//                Text("This preset will be created inside “\(workspace.name)”.")
//                    .foregroundStyle(.secondary)
//            }
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
            Toggle("Last day of month", isOn: $monthlyIsLastDay)

            if !monthlyIsLastDay {
                Picker("Day of month", selection: $monthlyDayOfMonth) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
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
                    Text("\(day)").tag(day)
                }
            }
        }
    }
    
    // MARK: - Ordinal helper (1st, 2nd, 3rd, 4th...)

    private func ordinal(_ number: Int) -> String {
        let n = abs(number)

        // 11, 12, 13 are always "th"
        let lastTwo = n % 100
        if (11...13).contains(lastTwo) {
            return "\(n)th"
        }

        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }


    private var scheduleHelpText: String {
        switch frequency {
        case .none:
            return "This expense does not repeat."

        case .daily:
            return interval == 1
                ? "An expense that repeats daily."
                : "An expense that repeats every \(interval) days."

        case .weekly:
            let day = weekdayName(weeklyWeekday)
            return interval == 1
                ? "An expense that repeats weekly on \(day)."
                : "An expense that repeats every \(interval) weeks on \(day)."

        case .monthly:
            if monthlyIsLastDay {
                return interval == 1
                    ? "An expense that repeats on the last day of every month."
                    : "An expense that repeats on the last day of every \(interval) months."
            } else {
                let day = ordinal(monthlyDayOfMonth)
                return interval == 1
                    ? "An expense that repeats on the \(day) of every month."
                    : "An expense that repeats on the \(day) of every \(interval) months."
            }

        case .yearly:
            let month = monthName(yearlyMonth)
            let day = ordinal(yearlyDayOfMonth)
            return interval == 1
                ? "An expense that repeats yearly on \(month) \(day)."
                : "An expense that repeats every \(interval) years on \(month) \(day)."
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
}

// MARK: - Reused tile (now uses CardVisualView)

private struct CardTile: View {

    let title: String
    let themeRaw: String
    let effectRaw: String
    let isSelected: Bool
    let onTap: () -> Void

    private let tileWidth: CGFloat = 160

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {

                CardVisualView(
                    title: title,
                    theme: themeOption(from: themeRaw),
                    effect: effectOption(from: effectRaw),
                    minHeight: nil,
                    showsShadow: false,
                    titleFont: .headline,
                    titlePadding: 12,
                    titleOpacity: 0.82
                )
                .frame(width: tileWidth)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func themeOption(from raw: String) -> CardThemeOption {
        CardThemeOption(rawValue: raw) ?? .graphite
    }

    private func effectOption(from raw: String) -> CardEffectOption {
        CardEffectOption(rawValue: raw) ?? .plastic
    }
}
