import Foundation

struct MarinaWorkspaceAggregationCard: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let answerKind: HomeAnswerKind
    let rows: [Row]
    let items: [Item]
    let traceSummary: String

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        answerKind: HomeAnswerKind = .list,
        rows: [Row] = [],
        items: [Item] = [],
        traceSummary: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.answerKind = answerKind
        self.rows = rows
        self.items = items
        self.traceSummary = traceSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case primaryValue
        case answerKind
        case rows
        case items
        case traceSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        primaryValue = try container.decodeIfPresent(String.self, forKey: .primaryValue)
        answerKind = try container.decodeIfPresent(HomeAnswerKind.self, forKey: .answerKind) ?? .list
        rows = try container.decode([Row].self, forKey: .rows)
        items = try container.decode([Item].self, forKey: .items)
        traceSummary = try container.decode(String.self, forKey: .traceSummary)
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
