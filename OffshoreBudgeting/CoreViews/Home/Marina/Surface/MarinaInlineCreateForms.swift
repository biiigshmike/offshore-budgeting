import SwiftUI

struct MarinaInlineCreateFormCard: View {
    @Binding var form: MarinaInlineCreateForm
    let cards: [Card]
    let categories: [Category]
    let presets: [Preset]
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = form.summary, summary.isEmpty == false {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch form.entity {
            case .expense:
                expenseFields
            case .income:
                incomeFields
            case .budget:
                budgetFields
            case .card:
                cardFields
            case .preset:
                presetFields
            case .category:
                categoryFields
            case .plannedExpense:
                unsupportedFields
            }

            if form.showsValidation, let validation = validationMessage {
                Text(validation)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text(MarinaL10n.string("common.cancel", defaultValue: "Cancel", comment: "Cancel action label."))
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.bordered)

                Button(action: onSubmit) {
                    Text(submitLabel)
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.top, 2)
    }

    private var submitLabel: String {
        MarinaL10n.format("marina.inlineCreate.submit", defaultValue: "Create %@", comment: "Button title for creating an entity from Marina.", form.entity.displayTitle)
    }

    private var expenseFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField(MarinaL10n.common("description", defaultValue: "Description", comment: "Common label for a description field."), text: $form.notesText)
            roundedAmountField(MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), text: $form.amountText)
            inlineDatePicker(MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field."), selection: $form.date)
            cardPicker(selection: $form.selectedCardID)
            categoryPicker(selection: $form.selectedCategoryID, pickerTitle: MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category."))
        }
    }

    private var incomeFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(MarinaL10n.common("type", defaultValue: "Type", comment: "Common label for a type picker."), selection: $form.isPlannedIncome) {
                Text(MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values.")).tag(true)
                Text(MarinaL10n.common("actual", defaultValue: "Actual", comment: "Common label for actual values.")).tag(false)
            }
            .pickerStyle(.segmented)

            roundedTextField(MarinaL10n.common("source", defaultValue: "Source", comment: "Common label for source."), text: $form.sourceText)
            roundedAmountField(MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), text: $form.amountText)
            inlineDatePicker(MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field."), selection: $form.date)
            recurrenceSection

            if form.recurrenceFrequencyRaw != RecurrenceFrequency.none.rawValue {
                inlineDatePicker(MarinaL10n.common("endDate", defaultValue: "End Date", comment: "Common label for end date."), selection: $form.secondaryDate)
            }
        }
    }

    private var budgetFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("January 2026", text: $form.nameText)
            inlineDatePicker(MarinaL10n.common("startDate", defaultValue: "Start Date", comment: "Common label for start date."), selection: $form.date)
            inlineDatePicker(MarinaL10n.common("endDate", defaultValue: "End Date", comment: "Common label for end date."), selection: $form.secondaryDate)

            multiSelectSection(
                title: MarinaL10n.string("marina.inlineCreate.cardsToTrack", defaultValue: "Cards to Track", comment: "Multi-select label for cards tracked by a budget created from Marina."),
                items: cards.map { ($0.id, $0.name) },
                selection: $form.selectedCardIDs,
                emptyMessage: MarinaL10n.string("marina.inlineCreate.noCardsCreateFirst", defaultValue: "No cards yet. Create a card first.", comment: "Empty state for card picker in Marina inline create forms.")
            )

            multiSelectSection(
                title: MarinaL10n.string("marina.inlineCreate.presetPlannedExpenses", defaultValue: "Preset Planned Expenses", comment: "Multi-select label for preset planned expenses in a Marina budget form."),
                items: presets.map { ($0.id, $0.title) },
                selection: $form.selectedPresetIDs,
                emptyMessage: MarinaL10n.string("marina.inlineCreate.noPresetsCreateFirst", defaultValue: "No presets yet. Create a preset first.", comment: "Empty state for preset picker in Marina inline create forms.")
            )
        }
    }

    private var cardFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("Apple Card", text: $form.nameText)

            CardVisualView(
                title: CardFormView.trimmedName(form.nameText).isEmpty ? MarinaL10n.string("marina.inlineCreate.newCardPreview", defaultValue: "New Card", comment: "Fallback title for a new card preview in Marina.") : CardFormView.trimmedName(form.nameText),
                theme: CardThemeOption(rawValue: form.cardThemeRaw) ?? .ruby,
                effect: CardEffectOption(rawValue: form.cardEffectRaw) ?? .plastic
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(MarinaL10n.common("effect", defaultValue: "Effect", comment: "Common label for card visual effect."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                EffectCapsuleGrid(
                    selection: Binding(
                        get: { CardEffectOption(rawValue: form.cardEffectRaw) ?? .plastic },
                        set: { form.cardEffectRaw = $0.rawValue }
                    ),
                    currentTheme: CardThemeOption(rawValue: form.cardThemeRaw) ?? .ruby
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(MarinaL10n.common("theme", defaultValue: "Theme", comment: "Common label for card theme."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ThemeCapsuleGrid(
                    selection: Binding(
                        get: { CardThemeOption(rawValue: form.cardThemeRaw) ?? .ruby },
                        set: { form.cardThemeRaw = $0.rawValue }
                    )
                )
            }
        }
    }

    private var presetFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField(MarinaL10n.string("marina.inlineCreate.expenseName", defaultValue: "Expense Name", comment: "Placeholder for preset expense name in Marina inline create."), text: $form.nameText)
            roundedAmountField(MarinaL10n.string("marina.inlineCreate.plannedAmount", defaultValue: "Planned Amount", comment: "Label for planned amount in Marina inline create."), text: $form.amountText)
            cardPicker(selection: $form.selectedCardID)
            categoryPicker(selection: $form.selectedCategoryID, pickerTitle: MarinaL10n.string("marina.inlineCreate.defaultCategory", defaultValue: "Default Category", comment: "Picker title for a preset default category."))
            recurrenceSection
        }
    }

    private var categoryFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField(MarinaL10n.common("name", defaultValue: "Name", comment: "Common label for name."), text: $form.nameText)

            ColorPicker(
                MarinaL10n.common("color", defaultValue: "Color", comment: "Common label for color."),
                selection: Binding(
                    get: { CategoryFormView.color(fromHex: form.categoryColorHex) },
                    set: { form.categoryColorHex = CategoryFormView.hexString(from: $0) }
                ),
                supportsOpacity: false
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var unsupportedFields: some View {
        Text(MarinaL10n.string("marina.inlineCreate.plannedExpenseUnsupported", defaultValue: "Planned expenses are created from presets.", comment: "Inline create helper explaining planned expenses are created from presets."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(MarinaL10n.common("repeat", defaultValue: "Repeat", comment: "Common label for repeat or recurrence."))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Picker(MarinaL10n.common("repeat", defaultValue: "Repeat", comment: "Common label for repeat or recurrence."), selection: $form.recurrenceFrequencyRaw) {
                    ForEach(RecurrenceFrequency.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Stepper(MarinaL10n.format("marina.inlineCreate.intervalFormat", defaultValue: "Interval: %@", comment: "Stepper label for recurrence interval.", AppNumberFormat.integer(max(1, form.recurrenceInterval))), value: $form.recurrenceInterval, in: 1...365)
                .disabled(form.recurrenceFrequencyRaw == RecurrenceFrequency.none.rawValue)

            switch RecurrenceFrequency(rawValue: form.recurrenceFrequencyRaw) ?? .monthly {
            case .daily, .none:
                EmptyView()
            case .weekly:
                Picker(MarinaL10n.common("weekday", defaultValue: "Weekday", comment: "Common label for weekday."), selection: $form.weeklyWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                .pickerStyle(.menu)
            case .monthly:
                Toggle(MarinaL10n.string("marina.inlineCreate.lastDayOfMonth", defaultValue: "Last Day of Month", comment: "Toggle label for recurring on the last day of the month."), isOn: $form.monthlyIsLastDay)
                    .tint(Color("AccentColor"))

                if form.monthlyIsLastDay == false {
                    Picker(MarinaL10n.string("marina.inlineCreate.dayOfMonth", defaultValue: "Day of Month", comment: "Picker label for day of month."), selection: $form.monthlyDayOfMonth) {
                        ForEach(1...31, id: \.self) { day in
                            Text(AppNumberFormat.integer(day)).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                }
            case .yearly:
                Picker(MarinaL10n.common("month", defaultValue: "Month", comment: "Common label for month."), selection: $form.yearlyMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                    }
                }
                .pickerStyle(.menu)

                Picker(MarinaL10n.common("day", defaultValue: "Day", comment: "Common label for day."), selection: $form.yearlyDayOfMonth) {
                    ForEach(1...31, id: \.self) { day in
                        Text(AppNumberFormat.integer(day)).tag(day)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func roundedTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
    }

    private func roundedAmountField(_ title: String, text: Binding<String>) -> some View {
        roundedTextField(title, text: text)
            .keyboardType(.decimalPad)
    }

    private func inlineDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            PillDatePickerField(title: title, date: selection)
        }
    }

    private func cardPicker(selection: Binding<UUID?>, allowNone: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if cards.isEmpty == false {
                    Picker(MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."), selection: selection) {
                        if allowNone {
                            Text(MarinaL10n.common("none", defaultValue: "None", comment: "Common option for no selection.")).tag(UUID?.none)
                        } else {
                            Text(MarinaL10n.common("select", defaultValue: "Select", comment: "Common option prompting a selection.")).tag(UUID?.none)
                        }
                        ForEach(cards) { card in
                            Text(card.name).tag(UUID?.some(card.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if cards.isEmpty {
                Text(MarinaL10n.string("marina.inlineCreate.noCardsCreateFirst", defaultValue: "No cards yet. Create a card first.", comment: "Empty state for card picker in Marina inline create forms."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryPicker(selection: Binding<UUID?>, pickerTitle: String) -> some View {
        HStack(spacing: 12) {
            Text(MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category."))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Picker(pickerTitle, selection: selection) {
                Text(MarinaL10n.common("none", defaultValue: "None", comment: "Common option for no selection.")).tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func multiSelectSection(
        title: String,
        items: [(UUID, String)],
        selection: Binding<[UUID]>,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.0) { id, label in
                    Toggle(
                        label,
                        isOn: Binding(
                            get: { selection.wrappedValue.contains(id) },
                            set: { isSelected in
                                var ids = selection.wrappedValue
                                if isSelected {
                                    ids.append(id)
                                } else {
                                    ids.removeAll { $0 == id }
                                }
                                selection.wrappedValue = Array(Set(ids))
                            }
                        )
                    )
                    .tint(Color("AccentColor"))
                }
            }
        }
    }

    private var validationMessage: String? {
        switch form.entity {
        case .expense:
            if form.notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addDescription", defaultValue: "Add a description to continue.", comment: "Validation message for missing expense description in Marina inline create.")
            }
            if CurrencyFormatter.parseAmount(form.amountText) ?? 0 <= 0 {
                return MarinaL10n.string("marina.inlineCreate.validation.amountGreaterThanZero", defaultValue: "Enter an amount greater than 0.", comment: "Validation message for invalid money amount.")
            }
            if cards.isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addCardFirst", defaultValue: "Add a card first.", comment: "Validation message when no cards exist.")
            }
            if form.selectedCardID == nil {
                return MarinaL10n.string("marina.inlineCreate.validation.selectCard", defaultValue: "Select a card to continue.", comment: "Validation message for missing card selection.")
            }
            return nil
        case .income:
            if form.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addIncomeSource", defaultValue: "Add an income source to continue.", comment: "Validation message for missing income source.")
            }
            if CurrencyFormatter.parseAmount(form.amountText) ?? 0 <= 0 {
                return MarinaL10n.string("marina.inlineCreate.validation.amountGreaterThanZero", defaultValue: "Enter an amount greater than 0.", comment: "Validation message for invalid money amount.")
            }
            if form.recurrenceFrequencyRaw != RecurrenceFrequency.none.rawValue,
               form.secondaryDate < form.date {
                return MarinaL10n.string("marina.inlineCreate.validation.endAfterStart", defaultValue: "End date must be on or after the start date.", comment: "Validation message when an end date is before a start date.")
            }
            return nil
        case .budget:
            if form.nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addBudgetName", defaultValue: "Add a budget name to continue.", comment: "Validation message for missing budget name.")
            }
            if form.date > form.secondaryDate {
                return MarinaL10n.string("marina.inlineCreate.validation.endAfterStart", defaultValue: "End date must be on or after the start date.", comment: "Validation message when an end date is before a start date.")
            }
            return nil
        case .card:
            return CardFormView.canSave(name: form.nameText) ? nil : MarinaL10n.string("marina.inlineCreate.validation.addCardName", defaultValue: "Add a card name to continue.", comment: "Validation message for missing card name.")
        case .preset:
            if PresetFormView.trimmedTitle(form.nameText).isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addPresetName", defaultValue: "Add a preset name to continue.", comment: "Validation message for missing preset name.")
            }
            if PresetFormView.parsePlannedAmount(form.amountText) ?? 0 <= 0 {
                return MarinaL10n.string("marina.inlineCreate.validation.plannedAmountGreaterThanZero", defaultValue: "Enter a planned amount greater than 0.", comment: "Validation message for invalid planned amount.")
            }
            if cards.isEmpty {
                return MarinaL10n.string("marina.inlineCreate.validation.addCardFirst", defaultValue: "Add a card first.", comment: "Validation message when no cards exist.")
            }
            if form.selectedCardID == nil {
                return MarinaL10n.string("marina.inlineCreate.validation.selectDefaultCard", defaultValue: "Select a default card to continue.", comment: "Validation message for missing default card.")
            }
            return nil
        case .category:
            return form.nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MarinaL10n.string("marina.inlineCreate.validation.addCategoryName", defaultValue: "Add a category name to continue.", comment: "Validation message for missing category name.") : nil
        case .plannedExpense:
            return MarinaL10n.string("marina.inlineCreate.validation.plannedExpensesFromPresets", defaultValue: "Planned expenses are created from presets.", comment: "Validation message explaining planned expenses are created from presets.")
        }
    }
}
