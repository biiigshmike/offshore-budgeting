import Foundation

enum MarinaLookupObjectType: String, Codable, Sendable, Equatable, CaseIterable {
    case budget
    case income
    case incomeSeries
    case variableExpense
    case plannedExpense
    case category
    case preset
    case card
    case savingsAccount
    case savingsLedgerEntry
    case reconciliationAccount
    case reconciliationItem
    case expenseAllocation
    case importMerchantRule
    case assistantAliasRule
    case workspace
    case unknown

    static let safeDefaultSearchTypes: [MarinaLookupObjectType] = allCases.filter { $0 != .unknown }
}

enum MarinaLookupMode: String, Codable, Sendable, Equatable {
    case entityDetail
    case relatedRows
    case relationship
    case broadSearch
}

struct MarinaDatabaseLookupRequest: Codable, Sendable, Equatable {
    var rawPrompt: String
    var searchText: String
    var objectTypes: [MarinaLookupObjectType]
    var dateRange: HomeQueryDateRange?
    var limit: Int
    var requestedDetail: RequestedDetail
    var lookupMode: MarinaLookupMode

    enum RequestedDetail: String, Codable, Sendable, Equatable {
        case general
        case date
        case amount
        case card
        case category
        case status
        case schedule
        case recurrence
        case account
        case balance
        case linkedObjects
    }

    init(
        rawPrompt: String,
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        dateRange: HomeQueryDateRange?,
        limit: Int,
        requestedDetail: RequestedDetail,
        lookupMode: MarinaLookupMode = .broadSearch
    ) {
        self.rawPrompt = rawPrompt
        self.searchText = searchText
        self.objectTypes = objectTypes
        self.dateRange = dateRange
        self.limit = limit
        self.requestedDetail = requestedDetail
        self.lookupMode = lookupMode
    }

    var clamped: MarinaDatabaseLookupRequest {
        var copy = self
        copy.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.limit = min(10, max(1, limit))
        copy.objectTypes = objectTypes.isEmpty ? [.unknown] : objectTypes
        return copy
    }
}

extension MarinaDatabaseLookupRequest {
    private enum CodingKeys: String, CodingKey {
        case rawPrompt
        case searchText
        case objectTypes
        case dateRange
        case limit
        case requestedDetail
        case lookupMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rawPrompt: try container.decode(String.self, forKey: .rawPrompt),
            searchText: try container.decode(String.self, forKey: .searchText),
            objectTypes: try container.decode([MarinaLookupObjectType].self, forKey: .objectTypes),
            dateRange: try container.decodeIfPresent(HomeQueryDateRange.self, forKey: .dateRange),
            limit: try container.decode(Int.self, forKey: .limit),
            requestedDetail: try container.decode(RequestedDetail.self, forKey: .requestedDetail),
            lookupMode: try container.decodeIfPresent(MarinaLookupMode.self, forKey: .lookupMode) ?? .broadSearch
        )
    }
}

struct MarinaDatabaseLookupResult: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var objectType: MarinaLookupObjectType
    var title: String
    var subtitle: String?
    var date: Date?
    var amount: Double?
    var cardName: String?
    var categoryName: String?
    var accountName: String?
    var workspaceName: String?
    var detailRows: [DetailRow]

    struct DetailRow: Codable, Sendable, Equatable {
        var label: String
        var value: String
    }
}

struct MarinaDatabaseLookupResponse: Codable, Sendable, Equatable {
    var request: MarinaDatabaseLookupRequest
    var results: [MarinaDatabaseLookupResult]
    var ambiguityChoices: [MarinaDatabaseLookupResult] = []

    var needsClarification: Bool {
        ambiguityChoices.isEmpty == false
    }

    var traceSummary: String {
        let objectTypes = request.objectTypes.map(\.rawValue).joined(separator: ",")
        let selectedTypes = (results.isEmpty ? ambiguityChoices : results)
            .map(\.objectType.rawValue)
            .joined(separator: ",")
        return [
            "requestFamily=\(MarinaRequestFamily.databaseLookup.rawValue)",
            "lookupMode=\(request.lookupMode.rawValue)",
            "objectTypes=\(objectTypes)",
            "searchText=\"\(request.searchText)\"",
            "requestedDetail=\(request.requestedDetail.rawValue)",
            "selectedResultTypes=\(selectedTypes)",
            "resultCount=\(results.count)",
            "ambiguityCount=\(ambiguityChoices.count)"
        ].joined(separator: ",")
    }
}
