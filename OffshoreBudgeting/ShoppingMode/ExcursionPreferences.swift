import Foundation

/// Device-wide reminder preferences, independent of financial workspaces.
nonisolated struct ExcursionPreferences: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable {
        case all
        case custom
    }

    var includeUncategorized: Bool
    var mode: Mode {
        includeUncategorized && ExcursionPOICategoryCatalog.supportedIDs.isSubset(of: categoryIDs) ? .all : .custom
    }

    init(mode: Mode = .custom, categoryIDs: Set<String>, dwellSeconds: Int, includeUncategorized: Bool = false) {
        self.categoryIDs = categoryIDs
        self.dwellSeconds = dwellSeconds
        self.includeUncategorized = includeUncategorized
        if mode == .all {
            self.categoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs)
            self.includeUncategorized = true
        }
    }

    private enum CodingKeys: String, CodingKey { case mode, categoryIDs, dwellSeconds, includeUncategorized }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mode: try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .custom,
                  categoryIDs: try container.decode(Set<String>.self, forKey: .categoryIDs),
                  dwellSeconds: try container.decode(Int.self, forKey: .dwellSeconds),
                  includeUncategorized: try container.decodeIfPresent(Bool.self, forKey: .includeUncategorized) ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categoryIDs, forKey: .categoryIDs)
        try container.encode(dwellSeconds, forKey: .dwellSeconds)
        try container.encode(includeUncategorized, forKey: .includeUncategorized)
    }
    var categoryIDs: Set<String>
    var dwellSeconds: Int

    static let dwellOptions = [45, 60, 120]

    static var `default`: Self {
        Self(mode: .custom, categoryIDs: ExcursionPOICategoryCatalog.recommendedIDs, dwellSeconds: 45)
    }

    func allows(categoryID: String?) -> Bool {
        guard let categoryID, ExcursionPOICategoryCatalog.supportedIDs.contains(categoryID) else { return includeUncategorized }
        return categoryIDs.contains(categoryID)
    }

    /// Preserve unrecognized IDs so a downgrade doesn't erase saved choices,
    /// but never treat them as supported categories on the running OS.
    func validated() -> Self? {
        guard Self.dwellOptions.contains(dwellSeconds) else { return nil }
        guard includeUncategorized || !categoryIDs.isDisjoint(with: ExcursionPOICategoryCatalog.supportedIDs) else { return nil }
        return self
    }

    var selectedSupportedCategoryIDs: Set<String> {
        categoryIDs.intersection(ExcursionPOICategoryCatalog.supportedIDs)
    }

    mutating func setMode(_ mode: Mode) {
        includeUncategorized = mode == .all
        if mode == .all { categoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs) }
        if mode == .custom && selectedSupportedCategoryIDs.isEmpty {
            categoryIDs.formUnion(ExcursionPOICategoryCatalog.recommendedIDs)
        }
    }

    /// Keep at least one selected category or uncategorized places enabled.
    @discardableResult
    mutating func toggleCategories(_ ids: Set<String>) -> Bool {
        let supported = ids.intersection(ExcursionPOICategoryCatalog.supportedIDs)
        var next = self
        if supported.isSubset(of: categoryIDs) {
            next.categoryIDs.subtract(supported)
        } else {
            next.categoryIDs.formUnion(supported)
        }
        guard next.validated() != nil else { return false }
        self = next
        return true
    }
}
