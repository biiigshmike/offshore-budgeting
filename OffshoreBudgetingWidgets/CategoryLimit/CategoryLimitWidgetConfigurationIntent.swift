import AppIntents
import Foundation
import WidgetKit

struct CategoryLimitWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Category Limit"
    static let description = IntentDescription("Track one category’s spending against its current budget limit.")

    @Parameter(title: "Category")
    var category: CategoryLimitWidgetCategory?

    init() {
        category = .unconfigured
    }

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$category
        }
    }
}

struct CategoryLimitWidgetCategory: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Budget Category"
    static let defaultQuery = CategoryLimitWidgetCategoryQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var unconfigured: Self {
        Self(id: "__choose_category__", name: widgetLocalized("Choose a Category"))
    }

    static var noLimits: Self {
        Self(id: "__no_limits__", name: widgetLocalized("No limits in current budget"))
    }

    static var openOffshore: Self {
        Self(id: "__open_offshore__", name: widgetLocalized("Open Offshore to refresh"))
    }
}

struct CategoryLimitWidgetCategoryQuery: EntityQuery {
    func suggestedEntities() async throws -> [CategoryLimitWidgetCategory] {
        guard let options = CategoryLimitWidgetSnapshotStore.loadSelectedPickerOptions() else {
            return [.openOffshore]
        }

        let categories = Self.eligibleCategories(in: options, asOf: .now)
        return categories.isEmpty ? [.noLimits] : categories
    }

    static func eligibleCategories(
        in options: CategoryLimitWidgetPickerOptions,
        asOf date: Date
    ) -> [CategoryLimitWidgetCategory] {
        options.eligibleCategoryIDs(asOf: date).compactMap { id -> CategoryLimitWidgetCategory? in
            guard let name = options.categoryNames[id] else { return nil }
            return CategoryLimitWidgetCategory(id: id.uuidString, name: name)
        }.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    func entities(for identifiers: [String]) async throws -> [CategoryLimitWidgetCategory] {
        let categoryNames = CategoryLimitWidgetSnapshotStore.loadSelectedPickerOptions()?.categoryNames ?? [:]
        return identifiers.compactMap { identifier in
            switch identifier {
            case CategoryLimitWidgetCategory.unconfigured.id:
                return .unconfigured
            case CategoryLimitWidgetCategory.noLimits.id:
                return .noLimits
            case CategoryLimitWidgetCategory.openOffshore.id:
                return .openOffshore
            default:
                guard let id = UUID(uuidString: identifier), let name = categoryNames[id] else { return nil }
                return CategoryLimitWidgetCategory(id: identifier, name: name)
            }
        }
    }
}
