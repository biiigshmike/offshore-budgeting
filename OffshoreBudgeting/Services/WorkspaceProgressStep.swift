import Foundation

enum WorkspaceProgressStep: String, CaseIterable, Identifiable, Codable {
    case card, category, preset, income, budget

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: String(localized: "Card")
        case .category: String(localized: "Category")
        case .preset: String(localized: "Preset")
        case .income: String(localized: "Income")
        case .budget: String(localized: "Budget")
        }
    }

    var explanation: String {
        switch self {
        case .card: String(localized: "Add a card to track your spending.")
        case .category: String(localized: "Create a category to organize expenses.")
        case .preset: String(localized: "Create a preset for an expected recurring expense.")
        case .income: String(localized: "Add money you expect to receive or have received.")
        case .budget: String(localized: "Create a budget for a date range that works for you.")
        }
    }

    var actionTitle: String {
        switch self {
        case .card: String(localized: "Add Card")
        case .category: String(localized: "Add Category")
        case .preset: String(localized: "Add Preset")
        case .income: String(localized: "Add Income")
        case .budget: String(localized: "Add Budget")
        }
    }

    var systemImage: String {
        switch self {
        case .card: "creditcard"
        case .category: "tag"
        case .preset: "list.bullet.rectangle"
        case .income: "arrow.down.circle"
        case .budget: "chart.pie"
        }
    }

    var milestoneKeyPath: ReferenceWritableKeyPath<Workspace, Bool> {
        switch self {
        case .card: \.setupHasCreatedCard
        case .category: \.setupHasCreatedCategory
        case .preset: \.setupHasCreatedPreset
        case .income: \.setupHasCreatedIncome
        case .budget: \.setupHasCreatedBudget
        }
    }
}
