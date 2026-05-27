import Foundation
import SwiftData

@MainActor
final class MarinaCreateService {
    private let transactionEntryService = TransactionEntryService()

    func addBudget(
        name: String,
        dateRange: HomeQueryDateRange,
        cards: [Card],
        presets: [Preset],
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let budget = Budget(
            name: trimmed,
            startDate: Calendar.current.startOfDay(for: dateRange.startDate),
            endDate: Calendar.current.startOfDay(for: dateRange.endDate),
            workspace: workspace
        )
        modelContext.insert(budget)

        for card in cards {
            modelContext.insert(BudgetCardLink(budget: budget, card: card))
        }
        for preset in presets {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
        }

        materializePlannedExpenses(
            for: budget,
            selectedPresets: presets,
            selectedCardIDs: Set(cards.map(\.id)),
            workspace: workspace,
            modelContext: modelContext
        )

        try modelContext.save()
        syncNotifications(modelContext: modelContext, workspaceID: workspace.id)

        return MarinaCreateResult(
            title: "Budget created",
            subtitle: "Saved budget \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Start", value: AppDateFormat.abbreviatedDate(dateRange.startDate)),
                HomeAnswerRow(title: "End", value: AppDateFormat.abbreviatedDate(dateRange.endDate)),
                HomeAnswerRow(title: "Cards", value: "\(cards.count) linked"),
                HomeAnswerRow(title: "Presets", value: "\(presets.count) linked")
            ]
        )
    }

    func addCard(
        name: String,
        themeRaw: String?,
        effectRaw: String?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let theme = CardThemeOption(rawValue: themeRaw ?? "")?.rawValue ?? CardThemeOption.ruby.rawValue
        let effect = CardEffectOption(rawValue: effectRaw ?? "")?.rawValue ?? CardEffectOption.plastic.rawValue
        modelContext.insert(Card(name: trimmed, theme: theme, effect: effect, workspace: workspace))
        try modelContext.save()

        return MarinaCreateResult(
            title: "Card created",
            subtitle: "Saved card \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: effect)?.displayName ?? "Plastic")
            ]
        )
    }

    func addCategory(
        name: String,
        colorHex: String?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let resolvedHex = (colorHex ?? "#3B82F6").trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Category(name: trimmed, hexColor: resolvedHex, workspace: workspace))
        try modelContext.save()

        return MarinaCreateResult(
            title: "Category created",
            subtitle: "Saved category \(trimmed).",
            rows: [HomeAnswerRow(title: "Color", value: resolvedHex)]
        )
    }

    func addPreset(
        title: String,
        plannedAmount: Double,
        frequencyRaw: String,
        interval: Int,
        weeklyWeekday: Int,
        monthlyDayOfMonth: Int,
        monthlyIsLastDay: Bool,
        yearlyMonth: Int,
        yearlyDayOfMonth: Int,
        card: Card,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        guard plannedAmount > 0 else {
            throw TransactionEntryService.ValidationError.invalidAmount
        }

        let preset = Preset(
            title: trimmed,
            plannedAmount: plannedAmount,
            frequencyRaw: frequencyRaw,
            interval: interval,
            weeklyWeekday: weeklyWeekday,
            monthlyDayOfMonth: monthlyDayOfMonth,
            monthlyIsLastDay: monthlyIsLastDay,
            yearlyMonth: yearlyMonth,
            yearlyDayOfMonth: yearlyDayOfMonth,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        modelContext.insert(preset)
        try modelContext.save()

        return MarinaCreateResult(
            title: "Preset created",
            subtitle: "Saved preset \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: plannedAmount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Frequency", value: RecurrenceFrequency(rawValue: frequencyRaw)?.displayName ?? "Monthly")
            ]
        )
    }

    func addExpense(
        amount: Double,
        notes: String,
        date: Date,
        card: Card,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        _ = try transactionEntryService.addExpense(
            notes: notes,
            amount: amount,
            date: date,
            workspace: workspace,
            card: card,
            category: category,
            modelContext: modelContext
        )

        return MarinaCreateResult(
            title: "Expense logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) on \(card.name).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(date))
            ]
        )
    }

    func addIncome(
        amount: Double,
        source: String,
        date: Date,
        isPlanned: Bool,
        recurrenceFrequencyRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        weeklyWeekday: Int? = nil,
        monthlyDayOfMonth: Int? = nil,
        monthlyIsLastDay: Bool? = nil,
        yearlyMonth: Int? = nil,
        yearlyDayOfMonth: Int? = nil,
        recurrenceEndDate: Date? = nil,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaCreateResult {
        let resolvedFrequency = RecurrenceFrequency(rawValue: recurrenceFrequencyRaw ?? RecurrenceFrequency.none.rawValue) ?? .none

        if resolvedFrequency != .none {
            guard let recurrenceEndDate else {
                throw NSError(
                    domain: "MarinaCreateService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income needs an end date."]
                )
            }

            let startDay = Calendar.current.startOfDay(for: date)
            let endDay = Calendar.current.startOfDay(for: recurrenceEndDate)
            guard endDay >= startDay else {
                throw NSError(
                    domain: "MarinaCreateService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income end date must be on or after the start date."]
                )
            }

            let series = IncomeSeries(
                source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                isPlanned: isPlanned,
                frequencyRaw: resolvedFrequency.rawValue,
                interval: max(1, recurrenceInterval ?? 1),
                weeklyWeekday: weeklyWeekday ?? 6,
                monthlyDayOfMonth: monthlyDayOfMonth ?? 15,
                monthlyIsLastDay: monthlyIsLastDay ?? false,
                yearlyMonth: yearlyMonth ?? 1,
                yearlyDayOfMonth: yearlyDayOfMonth ?? 15,
                startDate: startDay,
                endDate: endDay,
                workspace: workspace
            )
            modelContext.insert(series)

            for occurrenceDay in IncomeScheduleEngine.occurrences(for: series) {
                modelContext.insert(
                    Income(
                        source: series.source,
                        amount: series.amount,
                        date: Calendar.current.startOfDay(for: occurrenceDay),
                        isPlanned: series.isPlanned,
                        isException: false,
                        workspace: workspace,
                        series: series
                    )
                )
            }

            try modelContext.save()

            return MarinaCreateResult(
                title: "Income logged",
                subtitle: "Saved recurring \(isPlanned ? "planned" : "actual") income for \(source).",
                rows: [
                    HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                    HomeAnswerRow(title: "Source", value: source),
                    HomeAnswerRow(title: "Frequency", value: resolvedFrequency.displayName)
                ]
            )
        }

        _ = try transactionEntryService.addIncome(
            source: source,
            amount: amount,
            date: date,
            isPlanned: isPlanned,
            workspace: workspace,
            modelContext: modelContext
        )

        return MarinaCreateResult(
            title: "Income logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) as \(isPlanned ? "planned" : "actual") income.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Source", value: source),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(date))
            ]
        )
    }

    private func materializePlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        for preset in selectedPresets {
            let occurrences = PresetScheduleEngine.occurrences(for: preset, in: budget)
            for occurrence in occurrences {
                guard plannedExpenseExists(
                    budgetID: budget.id,
                    presetID: preset.id,
                    date: occurrence,
                    modelContext: modelContext
                ) == false else {
                    continue
                }

                let resolvedCard: Card?
                if let defaultCard = preset.defaultCard, selectedCardIDs.contains(defaultCard.id) {
                    resolvedCard = defaultCard
                } else {
                    resolvedCard = nil
                }

                modelContext.insert(
                    PlannedExpense(
                        title: preset.title,
                        plannedAmount: preset.plannedAmount,
                        actualAmount: 0,
                        expenseDate: Calendar.current.startOfDay(for: occurrence),
                        workspace: workspace,
                        card: resolvedCard,
                        category: preset.defaultCategory,
                        sourcePresetID: preset.id,
                        sourceBudgetID: budget.id
                    )
                )
            }
        }
    }

    private func plannedExpenseExists(
        budgetID: UUID,
        presetID: UUID,
        date: Date,
        modelContext: ModelContext
    ) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID &&
                    expense.sourcePresetID == presetID &&
                    expense.expenseDate == day
            }
        )
        return (try? modelContext.fetch(descriptor).isEmpty == false) ?? false
    }

    private func syncNotifications(modelContext: ModelContext, workspaceID: UUID) {
        Task {
            await LocalNotificationService.syncFromUserDefaultsIfPossible(
                modelContext: modelContext,
                workspaceID: workspaceID
            )
        }
    }
}
