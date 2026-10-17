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
        let activePresets = presets.filter { $0.isArchived == false }

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
        for preset in activePresets {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
        }

        materializePlannedExpenses(
            for: budget,
            selectedPresets: activePresets,
            selectedCardIDs: Set(cards.map(\.id)),
            workspace: workspace,
            modelContext: modelContext
        )

        try modelContext.save()
        syncNotifications(modelContext: modelContext, workspaceID: workspace.id)

        return MarinaCreateResult(
            title: MarinaL10n.string("marina.create.budgetCreated", defaultValue: "Budget created", comment: "Confirmation title after Marina creates a budget."),
            subtitle: MarinaL10n.format("marina.create.savedBudgetFormat", defaultValue: "Saved budget %@.", comment: "Confirmation subtitle after Marina saves a budget.", trimmed),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("start", defaultValue: "Start", comment: "Common label for a start value."), value: AppDateFormat.abbreviatedDate(dateRange.startDate)),
                HomeAnswerRow(title: MarinaL10n.common("end", defaultValue: "End", comment: "Common label for an end value."), value: AppDateFormat.abbreviatedDate(dateRange.endDate)),
                HomeAnswerRow(title: MarinaL10n.common("cards", defaultValue: "Cards", comment: "Common label for cards."), value: MarinaL10n.format("marina.create.linkedCount", defaultValue: "%@ linked", comment: "Value showing how many records were linked.", AppNumberFormat.integer(cards.count))),
                HomeAnswerRow(title: MarinaL10n.common("presets", defaultValue: "Presets", comment: "Common label for presets."), value: MarinaL10n.format("marina.create.linkedCount", defaultValue: "%@ linked", comment: "Value showing how many records were linked.", AppNumberFormat.integer(activePresets.count)))
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
            title: MarinaL10n.string("marina.create.cardCreated", defaultValue: "Card created", comment: "Confirmation title after Marina creates a card."),
            subtitle: MarinaL10n.format("marina.create.savedCardFormat", defaultValue: "Saved card %@.", comment: "Confirmation subtitle after Marina saves a card.", trimmed),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("theme", defaultValue: "Theme", comment: "Common label for card theme."), value: CardThemeOption(rawValue: theme)?.displayName ?? CardThemeOption.ruby.displayName),
                HomeAnswerRow(title: MarinaL10n.common("effect", defaultValue: "Effect", comment: "Common label for card visual effect."), value: CardEffectOption(rawValue: effect)?.displayName ?? CardEffectOption.plastic.displayName)
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
            title: MarinaL10n.string("marina.create.categoryCreated", defaultValue: "Category created", comment: "Confirmation title after Marina creates a category."),
            subtitle: MarinaL10n.format("marina.create.savedCategoryFormat", defaultValue: "Saved category %@.", comment: "Confirmation subtitle after Marina saves a category.", trimmed),
            rows: [HomeAnswerRow(title: MarinaL10n.common("color", defaultValue: "Color", comment: "Common label for color."), value: resolvedHex)]
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

        let selectedCategory = category?.isArchived == false ? category : nil

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
            defaultCategory: selectedCategory
        )
        modelContext.insert(preset)
        try modelContext.save()

        return MarinaCreateResult(
            title: MarinaL10n.string("marina.create.presetCreated", defaultValue: "Preset created", comment: "Confirmation title after Marina creates a preset."),
            subtitle: MarinaL10n.format("marina.create.savedPresetFormat", defaultValue: "Saved preset %@.", comment: "Confirmation subtitle after Marina saves a preset.", trimmed),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), value: CurrencyFormatter.string(from: plannedAmount)),
                HomeAnswerRow(title: MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."), value: card.name),
                HomeAnswerRow(title: MarinaL10n.common("frequency", defaultValue: "Frequency", comment: "Common label for recurrence frequency."), value: RecurrenceFrequency(rawValue: frequencyRaw)?.displayName ?? RecurrenceFrequency.monthly.displayName)
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
            title: MarinaL10n.string("marina.create.expenseLogged", defaultValue: "Expense logged", comment: "Confirmation title after Marina logs an expense."),
            subtitle: MarinaL10n.format("marina.create.savedExpenseFormat", defaultValue: "Saved %@ on %@.", comment: "Confirmation subtitle after Marina saves an expense with amount and card name.", CurrencyFormatter.string(from: amount), card.name),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."), value: card.name),
                HomeAnswerRow(title: MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field."), value: AppDateFormat.abbreviatedDate(date))
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
                    userInfo: [NSLocalizedDescriptionKey: MarinaL10n.string("marina.inlineCreate.validation.repeatIncomeNeedsEndDate", defaultValue: "Repeat income needs an end date.", comment: "Validation message for recurring income without an end date.")]
                )
            }

            let startDay = Calendar.current.startOfDay(for: date)
            let endDay = Calendar.current.startOfDay(for: recurrenceEndDate)
            guard endDay >= startDay else {
                throw NSError(
                    domain: "MarinaCreateService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: MarinaL10n.string("marina.inlineCreate.validation.repeatIncomeEndAfterStart", defaultValue: "Repeat income end date must be on or after the start date.", comment: "Validation message for recurring income whose end date is before start date.")]
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
                title: MarinaL10n.string("marina.create.incomeLogged", defaultValue: "Income logged", comment: "Confirmation title after Marina logs income."),
                subtitle: MarinaL10n.format("marina.create.savedRecurringIncomeFormat", defaultValue: "Saved recurring %@ income for %@.", comment: "Confirmation subtitle after Marina saves recurring income with state and source.", isPlanned ? MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values.").localizedLowercase : MarinaL10n.common("actual", defaultValue: "Actual", comment: "Common label for actual values.").localizedLowercase, source),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), value: CurrencyFormatter.string(from: amount)),
                    HomeAnswerRow(title: MarinaL10n.common("source", defaultValue: "Source", comment: "Common label for source."), value: source),
                    HomeAnswerRow(title: MarinaL10n.common("frequency", defaultValue: "Frequency", comment: "Common label for recurrence frequency."), value: resolvedFrequency.displayName)
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
            title: MarinaL10n.string("marina.create.incomeLogged", defaultValue: "Income logged", comment: "Confirmation title after Marina logs income."),
            subtitle: MarinaL10n.format("marina.create.savedIncomeFormat", defaultValue: "Saved %@ as %@ income.", comment: "Confirmation subtitle after Marina saves income with amount and state.", CurrencyFormatter.string(from: amount), isPlanned ? MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values.").localizedLowercase : MarinaL10n.common("actual", defaultValue: "Actual", comment: "Common label for actual values.").localizedLowercase),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: MarinaL10n.common("source", defaultValue: "Source", comment: "Common label for source."), value: source),
                HomeAnswerRow(title: MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field."), value: AppDateFormat.abbreviatedDate(date))
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
