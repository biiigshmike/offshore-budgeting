import Foundation

enum MarinaInlineCreateEntity: String, Codable, Equatable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case budget
    case card
    case preset
    case category
    case plannedExpense

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        case .budget:
            return "Budget"
        case .card:
            return "Card"
        case .preset:
            return "Preset"
        case .category:
            return "Category"
        case .plannedExpense:
            return "Planned Expense"
        }
    }
}

struct MarinaInlineCreateForm: Codable, Equatable, Sendable {
    let entity: MarinaInlineCreateEntity
    var summary: String?
    var nameText: String
    var amountText: String
    var date: Date
    var secondaryDate: Date
    var sourceText: String
    var notesText: String
    var isPlannedIncome: Bool
    var selectedCardID: UUID?
    var selectedCategoryID: UUID?
    var selectedCardIDs: [UUID]
    var selectedPresetIDs: [UUID]
    var cardThemeRaw: String
    var cardEffectRaw: String
    var categoryColorHex: String
    var recurrenceFrequencyRaw: String
    var recurrenceInterval: Int
    var weeklyWeekday: Int
    var monthlyDayOfMonth: Int
    var monthlyIsLastDay: Bool
    var yearlyMonth: Int
    var yearlyDayOfMonth: Int
    var showsValidation: Bool

    init(
        entity: MarinaInlineCreateEntity,
        summary: String? = nil,
        nameText: String = "",
        amountText: String = "",
        date: Date = .now,
        secondaryDate: Date = .now,
        sourceText: String = "",
        notesText: String = "",
        isPlannedIncome: Bool = false,
        selectedCardID: UUID? = nil,
        selectedCategoryID: UUID? = nil,
        selectedCardIDs: [UUID] = [],
        selectedPresetIDs: [UUID] = [],
        cardThemeRaw: String = CardThemeOption.ruby.rawValue,
        cardEffectRaw: String = CardEffectOption.plastic.rawValue,
        categoryColorHex: String = "#3B82F6",
        recurrenceFrequencyRaw: String = RecurrenceFrequency.monthly.rawValue,
        recurrenceInterval: Int = 1,
        weeklyWeekday: Int = 6,
        monthlyDayOfMonth: Int = 15,
        monthlyIsLastDay: Bool = false,
        yearlyMonth: Int = 1,
        yearlyDayOfMonth: Int = 15,
        showsValidation: Bool = false
    ) {
        self.entity = entity
        self.summary = summary
        self.nameText = nameText
        self.amountText = amountText
        self.date = date
        self.secondaryDate = secondaryDate
        self.sourceText = sourceText
        self.notesText = notesText
        self.isPlannedIncome = isPlannedIncome
        self.selectedCardID = selectedCardID
        self.selectedCategoryID = selectedCategoryID
        self.selectedCardIDs = selectedCardIDs
        self.selectedPresetIDs = selectedPresetIDs
        self.cardThemeRaw = cardThemeRaw
        self.cardEffectRaw = cardEffectRaw
        self.categoryColorHex = categoryColorHex
        self.recurrenceFrequencyRaw = recurrenceFrequencyRaw
        self.recurrenceInterval = recurrenceInterval
        self.weeklyWeekday = weeklyWeekday
        self.monthlyDayOfMonth = monthlyDayOfMonth
        self.monthlyIsLastDay = monthlyIsLastDay
        self.yearlyMonth = yearlyMonth
        self.yearlyDayOfMonth = yearlyDayOfMonth
        self.showsValidation = showsValidation
    }
}

struct MarinaMutationResult {
    let title: String
    let subtitle: String?
    let rows: [HomeAnswerRow]
}
