import Foundation

struct MarinaWorkspaceAggregationCard: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [Row]
    let items: [Item]
    let traceSummary: String

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [Row] = [],
        items: [Item] = [],
        traceSummary: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.items = items
        self.traceSummary = traceSummary
    }

    struct Row: Codable, Equatable, Identifiable {
        let id: UUID
        let label: String
        let value: String
        let amount: Double?
        let date: Date?
        let objectType: MarinaLookupObjectType?
        let sourceID: UUID?
        let sortValue: Double?
        let role: HomeAnswerRowRole

        init(
            id: UUID = UUID(),
            label: String,
            value: String,
            amount: Double? = nil,
            date: Date? = nil,
            objectType: MarinaLookupObjectType? = nil,
            sourceID: UUID? = nil,
            sortValue: Double? = nil,
            role: HomeAnswerRowRole = .result
        ) {
            self.id = id
            self.label = label
            self.value = value
            self.amount = amount
            self.date = date
            self.objectType = objectType
            self.sourceID = sourceID
            self.sortValue = sortValue
            self.role = role
        }
    }

    struct Item: Codable, Equatable, Identifiable {
        let id: UUID
        let label: String
        let value: String
        let subtitle: String?
        let amount: Double?
        let date: Date?
        let objectType: MarinaLookupObjectType?
        let sourceID: UUID?
        let sortValue: Double?
        let role: HomeAnswerRowRole

        init(
            id: UUID = UUID(),
            label: String,
            value: String,
            subtitle: String? = nil,
            amount: Double? = nil,
            date: Date? = nil,
            objectType: MarinaLookupObjectType? = nil,
            sourceID: UUID? = nil,
            sortValue: Double? = nil,
            role: HomeAnswerRowRole = .result
        ) {
            self.id = id
            self.label = label
            self.value = value
            self.subtitle = subtitle
            self.amount = amount
            self.date = date
            self.objectType = objectType
            self.sourceID = sourceID
            self.sortValue = sortValue
            self.role = role
        }
    }
}

enum MarinaWorkspaceAggregationExecutionResult: Equatable {
    case handled(MarinaWorkspaceAggregationCard)
    case unsupported
}
