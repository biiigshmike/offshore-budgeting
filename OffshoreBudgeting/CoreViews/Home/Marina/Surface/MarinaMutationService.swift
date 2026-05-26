import Foundation
import SwiftData

@MainActor
final class MarinaMutationService {
    private let transactionEntryService = TransactionEntryService()

    func addBudget(
        name: String,
        dateRange: HomeQueryDateRange,
        cards: [Card],
        presets: [Preset],
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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

        return MarinaMutationResult(
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
    ) throws -> MarinaMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let theme = CardThemeOption(rawValue: themeRaw ?? "")?.rawValue ?? CardThemeOption.ruby.rawValue
        let effect = CardEffectOption(rawValue: effectRaw ?? "")?.rawValue ?? CardEffectOption.plastic.rawValue
        modelContext.insert(Card(name: trimmed, theme: theme, effect: effect, workspace: workspace))
        try modelContext.save()

        return MarinaMutationResult(
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
    ) throws -> MarinaMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let resolvedHex = (colorHex ?? "#3B82F6").trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Category(name: trimmed, hexColor: resolvedHex, workspace: workspace))
        try modelContext.save()

        return MarinaMutationResult(
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
    ) throws -> MarinaMutationResult {
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

        return MarinaMutationResult(
            title: "Preset created",
            subtitle: "Saved preset \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: plannedAmount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Frequency", value: RecurrenceFrequency(rawValue: frequencyRaw)?.displayName ?? "Monthly")
            ]
        )
    }

    func addPlannedExpense(
        title: String,
        amount: Double,
        date: Date,
        card: Card?,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        guard amount > 0 else {
            throw TransactionEntryService.ValidationError.invalidAmount
        }

        let expense = PlannedExpense(
            title: trimmed,
            plannedAmount: amount,
            actualAmount: 0,
            expenseDate: Calendar.current.startOfDay(for: date),
            workspace: workspace,
            card: card,
            category: category
        )
        modelContext.insert(expense)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense created",
            subtitle: "Saved planned expense \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.expenseDate)),
                HomeAnswerRow(title: "Card", value: card?.name ?? "None")
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
    ) throws -> MarinaMutationResult {
        _ = try transactionEntryService.addExpense(
            notes: notes,
            amount: amount,
            date: date,
            workspace: workspace,
            card: card,
            category: category,
            modelContext: modelContext
        )

        return MarinaMutationResult(
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
    ) throws -> MarinaMutationResult {
        let resolvedFrequency = RecurrenceFrequency(rawValue: recurrenceFrequencyRaw ?? RecurrenceFrequency.none.rawValue) ?? .none

        if resolvedFrequency != .none {
            guard let recurrenceEndDate else {
                throw NSError(
                    domain: "MarinaMutationService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income needs an end date."]
                )
            }

            let startDay = Calendar.current.startOfDay(for: date)
            let endDay = Calendar.current.startOfDay(for: recurrenceEndDate)
            guard endDay >= startDay else {
                throw NSError(
                    domain: "MarinaMutationService",
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

            return MarinaMutationResult(
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

        return MarinaMutationResult(
            title: "Income logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) as \(isPlanned ? "planned" : "actual") income.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Source", value: source),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(date))
            ]
        )
    }

    func editExpense(
        _ expense: VariableExpense,
        amount: Double? = nil,
        notes: String? = nil,
        date: Date? = nil,
        card: Card? = nil,
        category: Category? = nil,
        updateCategory: Bool = false,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let amount, amount > 0 {
            expense.amount = amount
        }
        if let notes {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                expense.descriptionText = trimmed
            }
        }
        if let date {
            expense.transactionDate = Calendar.current.startOfDay(for: date)
        }
        if let card {
            expense.card = card
        }
        if updateCategory {
            expense.category = category
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Expense updated",
            subtitle: "Updated \(expense.descriptionText).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: expense.amount)),
                HomeAnswerRow(title: "Card", value: expense.card?.name ?? "None")
            ]
        )
    }

    func moveExpenseCategory(
        expense: VariableExpense,
        category: Category,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        expense.category = category
        try modelContext.save()

        return MarinaMutationResult(
            title: "Expense category updated",
            subtitle: "Moved \(expense.descriptionText) to \(category.name).",
            rows: [HomeAnswerRow(title: "Category", value: category.name)]
        )
    }

    func editIncome(
        _ income: Income,
        amount: Double? = nil,
        source: String? = nil,
        date: Date? = nil,
        isPlanned: Bool? = nil,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let amount, amount > 0 {
            income.amount = amount
        }
        if let source {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                income.source = trimmed
            }
        }
        if let date {
            income.date = Calendar.current.startOfDay(for: date)
        }
        if let isPlanned {
            income.isPlanned = isPlanned
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Income updated",
            subtitle: "Updated \(income.source).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: income.amount)),
                HomeAnswerRow(title: "Type", value: income.isPlanned ? "Planned" : "Actual")
            ]
        )
    }

    func editCard(
        card: Card,
        newName: String? = nil,
        themeRaw: String? = nil,
        effectRaw: String? = nil,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                card.name = trimmed
            }
        }
        if let themeRaw, let theme = CardThemeOption(rawValue: themeRaw) {
            card.theme = theme.rawValue
        }
        if let effectRaw, let effect = CardEffectOption(rawValue: effectRaw) {
            card.effect = effect.rawValue
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Card updated",
            subtitle: "Updated \(card.name).",
            rows: [
                HomeAnswerRow(title: "Name", value: card.name),
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic")
            ]
        )
    }

    func editCategory(
        _ category: Category,
        newName: String? = nil,
        colorHex: String? = nil,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                category.name = trimmed
            }
        }
        if let colorHex, colorHex.isEmpty == false {
            category.hexColor = colorHex
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Category updated",
            subtitle: "Updated \(category.name).",
            rows: [
                HomeAnswerRow(title: "Name", value: category.name),
                HomeAnswerRow(title: "Color", value: category.hexColor)
            ]
        )
    }

    func editPreset(
        _ preset: Preset,
        title: String? = nil,
        plannedAmount: Double? = nil,
        frequencyRaw: String? = nil,
        interval: Int? = nil,
        weeklyWeekday: Int? = nil,
        monthlyDayOfMonth: Int? = nil,
        monthlyIsLastDay: Bool? = nil,
        yearlyMonth: Int? = nil,
        yearlyDayOfMonth: Int? = nil,
        card: Card? = nil,
        category: Category? = nil,
        updateCategory: Bool = false,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                preset.title = trimmed
            }
        }
        if let plannedAmount, plannedAmount > 0 {
            preset.plannedAmount = plannedAmount
        }
        if let card {
            preset.defaultCard = card
        }
        if updateCategory {
            preset.defaultCategory = category
        }
        if let frequencyRaw, RecurrenceFrequency(rawValue: frequencyRaw) != nil {
            preset.frequencyRaw = frequencyRaw
            preset.interval = max(1, interval ?? preset.interval)
            if let weeklyWeekday {
                preset.weeklyWeekday = weeklyWeekday
            }
            if let monthlyDayOfMonth {
                preset.monthlyDayOfMonth = monthlyDayOfMonth
            }
            if let monthlyIsLastDay {
                preset.monthlyIsLastDay = monthlyIsLastDay
            }
            if let yearlyMonth {
                preset.yearlyMonth = yearlyMonth
            }
            if let yearlyDayOfMonth {
                preset.yearlyDayOfMonth = yearlyDayOfMonth
            }
        }

        syncGeneratedPlannedExpenses(for: preset, workspace: workspace, modelContext: modelContext)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Preset updated",
            subtitle: "Updated \(preset.title).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: preset.plannedAmount)),
                HomeAnswerRow(title: "Card", value: preset.defaultCard?.name ?? "None"),
                HomeAnswerRow(title: "Frequency", value: preset.frequency.displayName)
            ]
        )
    }

    func editBudget(
        _ budget: Budget,
        name: String? = nil,
        dateRange: HomeQueryDateRange? = nil,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                budget.name = trimmed
            }
        }
        if let dateRange {
            budget.startDate = Calendar.current.startOfDay(for: dateRange.startDate)
            budget.endDate = Calendar.current.startOfDay(for: dateRange.endDate)
            syncGeneratedPlannedExpenses(for: budget, workspace: workspace, modelContext: modelContext)
        }

        try modelContext.save()
        syncNotifications(modelContext: modelContext, workspaceID: workspace.id)

        return MarinaMutationResult(
            title: "Budget updated",
            subtitle: "Updated \(budget.name).",
            rows: [
                HomeAnswerRow(title: "Start", value: AppDateFormat.abbreviatedDate(budget.startDate)),
                HomeAnswerRow(title: "End", value: AppDateFormat.abbreviatedDate(budget.endDate))
            ]
        )
    }

    func editPlannedExpense(
        _ expense: PlannedExpense,
        title: String? = nil,
        plannedAmount: Double? = nil,
        actualAmount: Double? = nil,
        date: Date? = nil,
        card: Card? = nil,
        category: Category? = nil,
        updateCategory: Bool = false,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                expense.title = trimmed
            }
        }
        if let plannedAmount, plannedAmount > 0 {
            expense.plannedAmount = plannedAmount
        }
        if let actualAmount, actualAmount >= 0 {
            expense.actualAmount = actualAmount
        }
        if let date {
            expense.expenseDate = Calendar.current.startOfDay(for: date)
        }
        if let card {
            expense.card = card
        }
        if updateCategory {
            expense.category = category
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense updated",
            subtitle: "Updated \(expense.title).",
            rows: [
                HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: expense.plannedAmount)),
                HomeAnswerRow(title: "Actual", value: CurrencyFormatter.string(from: expense.actualAmount)),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.expenseDate))
            ]
        )
    }

    func updatePlannedExpenseAmount(
        _ expense: PlannedExpense,
        amount: Double,
        target: MarinaPlannedExpenseAmountTarget,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        guard amount > 0 else {
            throw TransactionEntryService.ValidationError.invalidAmount
        }

        switch target {
        case .planned:
            expense.plannedAmount = amount
        case .actual:
            expense.actualAmount = amount
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense amount updated",
            subtitle: "Updated \(expense.title).",
            rows: [
                HomeAnswerRow(title: target == .planned ? "Planned" : "Actual", value: CurrencyFormatter.string(from: amount))
            ]
        )
    }

    func deleteExpense(_ expense: VariableExpense, modelContext: ModelContext) throws -> MarinaMutationResult {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
        try modelContext.save()
        return MarinaMutationResult(title: "Expense deleted", subtitle: "The expense was removed.", rows: [])
    }

    func deleteIncome(_ income: Income, modelContext: ModelContext) throws -> MarinaMutationResult {
        modelContext.delete(income)
        try modelContext.save()
        return MarinaMutationResult(title: "Income deleted", subtitle: "The income entry was removed.", rows: [])
    }

    func deleteCard(_ card: Card, workspace: Workspace, modelContext: ModelContext) throws -> MarinaMutationResult {
        let workspaceID = workspace.id
        let cardID = card.id

        HomePinnedItemsStore(workspaceID: workspaceID).removePinnedCard(id: cardID)
        HomePinnedCardsStore(workspaceID: workspaceID).removePinnedCardID(cardID)

        if let planned = card.plannedExpenses {
            for expense in planned {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
        if let variable = card.variableExpenses {
            for expense in variable {
                VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
        if let incomes = card.incomes {
            for income in incomes {
                modelContext.delete(income)
            }
        }
        if let links = card.budgetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }

        modelContext.delete(card)
        try modelContext.save()

        return MarinaMutationResult(title: "Card deleted", subtitle: "Removed \(card.name) and its linked entries.", rows: [])
    }

    func deleteCategory(_ category: Category, modelContext: ModelContext) throws -> MarinaMutationResult {
        if let variableExpenses = category.variableExpenses {
            for expense in variableExpenses {
                expense.category = nil
            }
        }
        if let plannedExpenses = category.plannedExpenses {
            for expense in plannedExpenses {
                expense.category = nil
            }
        }
        if let presets = category.defaultForPresets {
            for preset in presets {
                preset.defaultCategory = nil
            }
        }
        if let limits = category.budgetCategoryLimits {
            for limit in limits {
                modelContext.delete(limit)
            }
        }

        modelContext.delete(category)
        try modelContext.save()

        return MarinaMutationResult(title: "Category deleted", subtitle: "Removed \(category.name).", rows: [])
    }

    func deletePreset(_ preset: Preset, modelContext: ModelContext) throws -> MarinaMutationResult {
        if let links = preset.budgetPresetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }
        modelContext.delete(preset)
        try modelContext.save()

        return MarinaMutationResult(title: "Preset deleted", subtitle: "Removed \(preset.title).", rows: [])
    }

    func deleteBudget(_ budget: Budget, modelContext: ModelContext) throws -> MarinaMutationResult {
        try BudgetDeletionService.deleteBudgetAndGeneratedPlannedExpenses(budget, modelContext: modelContext)
        return MarinaMutationResult(title: "Budget deleted", subtitle: "Removed \(budget.name).", rows: [])
    }

    func deletePlannedExpense(_ expense: PlannedExpense, modelContext: ModelContext) throws -> MarinaMutationResult {
        PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        try modelContext.save()
        return MarinaMutationResult(title: "Planned expense deleted", subtitle: "The planned expense was removed.", rows: [])
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

    private func syncGeneratedPlannedExpenses(for preset: Preset, workspace: Workspace, modelContext: ModelContext) {
        let linkedBudgets = (preset.budgetPresetLinks ?? []).compactMap(\.budget)
        for budget in linkedBudgets {
            deleteGeneratedPlannedExpenses(
                budgetID: budget.id,
                presetID: preset.id,
                modelContext: modelContext
            )
            let selectedPresets = (budget.presetLinks ?? []).compactMap(\.preset)
            let selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
            materializePlannedExpenses(
                for: budget,
                selectedPresets: selectedPresets,
                selectedCardIDs: selectedCardIDs,
                workspace: workspace,
                modelContext: modelContext
            )
        }

        applyPresetAttributesToGeneratedExpenses(preset: preset, modelContext: modelContext)
    }

    private func syncGeneratedPlannedExpenses(for budget: Budget, workspace: Workspace, modelContext: ModelContext) {
        let selectedPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
        let selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })

        deleteGeneratedPlannedExpensesNotMatchingSelection(
            budgetID: budget.id,
            selectedPresetIDs: selectedPresetIDs,
            windowStart: Calendar.current.startOfDay(for: budget.startDate),
            windowEnd: Calendar.current.startOfDay(for: budget.endDate),
            selectedCardIDs: selectedCardIDs,
            modelContext: modelContext
        )

        materializePlannedExpenses(
            for: budget,
            selectedPresets: (budget.presetLinks ?? []).compactMap(\.preset),
            selectedCardIDs: selectedCardIDs,
            workspace: workspace,
            modelContext: modelContext
        )
    }

    private func deleteGeneratedPlannedExpensesNotMatchingSelection(
        budgetID: UUID,
        selectedPresetIDs: Set<UUID>,
        windowStart: Date,
        windowEnd: Date,
        selectedCardIDs: Set<UUID>,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        guard let matches = try? modelContext.fetch(descriptor) else { return }
        for expense in matches {
            let presetID = expense.sourcePresetID
            let inSelectedPresets = presetID.map { selectedPresetIDs.contains($0) } ?? false
            let day = Calendar.current.startOfDay(for: expense.expenseDate)
            let inWindow = (day >= windowStart && day <= windowEnd)
            let cardID = expense.card?.id
            let cardStillLinked = cardID.map { selectedCardIDs.contains($0) } ?? true

            if !inSelectedPresets || !inWindow || !cardStillLinked {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
    }

    private func deleteGeneratedPlannedExpenses(budgetID: UUID, presetID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID &&
                    expense.sourcePresetID == presetID
            }
        )

        guard let matches = try? modelContext.fetch(descriptor) else { return }
        for expense in matches {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }
    }

    private func applyPresetAttributesToGeneratedExpenses(preset: Preset, modelContext: ModelContext) {
        let presetID = preset.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourcePresetID == presetID
            }
        )

        guard let matches = try? modelContext.fetch(descriptor) else { return }
        for expense in matches {
            expense.title = preset.title
            expense.plannedAmount = preset.plannedAmount
            expense.category = preset.defaultCategory

            if let budgetID = expense.sourceBudgetID,
               let budgetCardIDs = budgetCardIDs(for: budgetID, modelContext: modelContext),
               let defaultCard = preset.defaultCard,
               budgetCardIDs.contains(defaultCard.id) {
                expense.card = defaultCard
            } else if expense.sourceBudgetID == nil {
                expense.card = preset.defaultCard
            } else {
                expense.card = nil
            }
        }
    }

    private func budgetCardIDs(for budgetID: UUID, modelContext: ModelContext) -> Set<UUID>? {
        let descriptor = FetchDescriptor<BudgetCardLink>(
            predicate: #Predicate { link in
                link.budget?.id == budgetID
            }
        )

        return try? Set(modelContext.fetch(descriptor).compactMap { $0.card?.id })
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

enum MarinaPlannedExpenseAmountTarget: String, Equatable {
    case planned
    case actual
}
