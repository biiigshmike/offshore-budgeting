import Foundation

enum MarinaLookupObjectType: String, Codable, Sendable, Equatable, CaseIterable {
    case budget
    case income
    case variableExpense
    case plannedExpense
    case category
    case preset
    case card
    case savingsAccount
    case savingsLedgerEntry
    case reconciliationAccount
    case reconciliationItem
    case workspace
    case unknown
}

struct MarinaDatabaseLookupRequest: Codable, Sendable, Equatable {
    var rawPrompt: String
    var searchText: String
    var objectTypes: [MarinaLookupObjectType]
    var dateRange: HomeQueryDateRange?
    var limit: Int
    var requestedDetail: RequestedDetail

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

    var clamped: MarinaDatabaseLookupRequest {
        var copy = self
        copy.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.limit = min(10, max(1, limit))
        copy.objectTypes = objectTypes.isEmpty ? [.unknown] : objectTypes
        return copy
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

    var traceSummary: String {
        let objectTypes = request.objectTypes.map(\.rawValue).joined(separator: ",")
        return [
            "requestFamily=\(MarinaRequestFamily.databaseLookup.rawValue)",
            "objectTypes=\(objectTypes)",
            "searchText=\"\(request.searchText)\"",
            "requestedDetail=\(request.requestedDetail.rawValue)",
            "resultCount=\(results.count)"
        ].joined(separator: ",")
    }
}
