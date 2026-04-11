import SwiftUI

struct HomeAssistantInlineCreateFormCard: View {
    @Binding var form: HomeAssistantInlineCreateForm
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
                    Text("Cancel")
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
        "Create \(form.entity.displayTitle)"
    }

    private var expenseFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("Description", text: $form.notesText)
            roundedAmountField("Amount", text: $form.amountText)
            inlineDatePicker("Date", selection: $form.date)
            cardPicker(selection: $form.selectedCardID)
            categoryPicker(selection: $form.selectedCategoryID, pickerTitle: "Category")
        }
    }

    private var incomeFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $form.isPlannedIncome) {
                Text("Planned").tag(true)
                Text("Actual").tag(false)
            }
            .pickerStyle(.segmented)

            roundedTextField("Source", text: $form.sourceText)
            roundedAmountField("Amount", text: $form.amountText)
            inlineDatePicker("Date", selection: $form.date)
            recurrenceSection

            if form.recurrenceFrequencyRaw != RecurrenceFrequency.none.rawValue {
                inlineDatePicker("End Date", selection: $form.secondaryDate)
            }
        }
    }

    private var budgetFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("January 2026", text: $form.nameText)
            inlineDatePicker("Start Date", selection: $form.date)
            inlineDatePicker("End Date", selection: $form.secondaryDate)

            multiSelectSection(
                title: "Cards to Track",
                items: cards.map { ($0.id, $0.name) },
                selection: $form.selectedCardIDs,
                emptyMessage: "No cards yet. Create a card first."
            )

            multiSelectSection(
                title: "Preset Planned Expenses",
                items: presets.map { ($0.id, $0.title) },
                selection: $form.selectedPresetIDs,
                emptyMessage: "No presets yet. Create a preset first."
            )
        }
    }

    private var cardFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("Apple Card", text: $form.nameText)

            CardVisualView(
                title: CardFormView.trimmedName(form.nameText).isEmpty ? "New Card" : CardFormView.trimmedName(form.nameText),
                theme: CardThemeOption(rawValue: form.cardThemeRaw) ?? .ruby,
                effect: CardEffectOption(rawValue: form.cardEffectRaw) ?? .plastic
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Effect")
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
                Text("Theme")
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
            roundedTextField("Expense Name", text: $form.nameText)
            roundedAmountField("Planned Amount", text: $form.amountText)
            cardPicker(selection: $form.selectedCardID)
            categoryPicker(selection: $form.selectedCategoryID, pickerTitle: "Default Category")
            recurrenceSection
        }
    }

    private var categoryFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            roundedTextField("Name", text: $form.nameText)

            ColorPicker(
                "Color",
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
        Text("Planned expenses are created from presets.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Repeat")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Picker("Repeat", selection: $form.recurrenceFrequencyRaw) {
                    ForEach(RecurrenceFrequency.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Stepper("Interval: \(AppNumberFormat.integer(max(1, form.recurrenceInterval)))", value: $form.recurrenceInterval, in: 1...365)
                .disabled(form.recurrenceFrequencyRaw == RecurrenceFrequency.none.rawValue)

            switch RecurrenceFrequency(rawValue: form.recurrenceFrequencyRaw) ?? .monthly {
            case .daily, .none:
                EmptyView()
            case .weekly:
                Picker("Weekday", selection: $form.weeklyWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                .pickerStyle(.menu)
            case .monthly:
                Toggle("Last Day of Month", isOn: $form.monthlyIsLastDay)
                    .tint(Color("AccentColor"))

                if form.monthlyIsLastDay == false {
                    Picker("Day of Month", selection: $form.monthlyDayOfMonth) {
                        ForEach(1...31, id: \.self) { day in
                            Text(AppNumberFormat.integer(day)).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                }
            case .yearly:
                Picker("Month", selection: $form.yearlyMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                    }
                }
                .pickerStyle(.menu)

                Picker("Day", selection: $form.yearlyDayOfMonth) {
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
                Text("Card")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if cards.isEmpty == false {
                    Picker("Card", selection: selection) {
                        if allowNone {
                            Text("None").tag(UUID?.none)
                        } else {
                            Text("Select").tag(UUID?.none)
                        }
                        ForEach(cards) { card in
                            Text(card.name).tag(UUID?.some(card.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if cards.isEmpty {
                Text("No cards yet. Create a card first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryPicker(selection: Binding<UUID?>, pickerTitle: String) -> some View {
        HStack(spacing: 12) {
            Text("Category")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Picker(pickerTitle, selection: selection) {
                Text("None").tag(UUID?.none)
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
                return "Add a description to continue."
            }
            if CurrencyFormatter.parseAmount(form.amountText) ?? 0 <= 0 {
                return "Enter an amount greater than 0."
            }
            if cards.isEmpty {
                return "Add a card first."
            }
            if form.selectedCardID == nil {
                return "Select a card to continue."
            }
            return nil
        case .income:
            if form.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Add an income source to continue."
            }
            if CurrencyFormatter.parseAmount(form.amountText) ?? 0 <= 0 {
                return "Enter an amount greater than 0."
            }
            if form.recurrenceFrequencyRaw != RecurrenceFrequency.none.rawValue,
               form.secondaryDate < form.date {
                return "End date must be on or after the start date."
            }
            return nil
        case .budget:
            if form.nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Add a budget name to continue."
            }
            if form.date > form.secondaryDate {
                return "End date must be on or after the start date."
            }
            return nil
        case .card:
            return CardFormView.canSave(name: form.nameText) ? nil : "Add a card name to continue."
        case .preset:
            if PresetFormView.trimmedTitle(form.nameText).isEmpty {
                return "Add a preset name to continue."
            }
            if PresetFormView.parsePlannedAmount(form.amountText) ?? 0 <= 0 {
                return "Enter a planned amount greater than 0."
            }
            if cards.isEmpty {
                return "Add a card first."
            }
            if form.selectedCardID == nil {
                return "Select a default card to continue."
            }
            return nil
        case .category:
            return form.nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add a category name to continue." : nil
        case .plannedExpense:
            return "Planned expenses are created from presets."
        }
    }
}
