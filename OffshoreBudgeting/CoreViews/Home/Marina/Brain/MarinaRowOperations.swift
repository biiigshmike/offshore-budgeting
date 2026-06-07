import Foundation

nonisolated struct MarinaRowSearchClause: Equatable, Sendable {
    let fields: Set<MarinaFieldKey>
    let query: String
}

nonisolated enum MarinaRowFilterOperator: Equatable, Sendable {
    case equals
    case contains
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case between
}

nonisolated enum MarinaRowFilterTarget: Equatable, Sendable {
    case field(MarinaFieldKey)
    case relationship(MarinaRelationshipKey)
}

nonisolated struct MarinaRowFilter: Equatable, Sendable {
    let target: MarinaRowFilterTarget
    let operation: MarinaRowFilterOperator
    let value: MarinaValue
    let upperValue: MarinaValue?

    init(
        target: MarinaRowFilterTarget,
        operation: MarinaRowFilterOperator,
        value: MarinaValue,
        upperValue: MarinaValue? = nil
    ) {
        self.target = target
        self.operation = operation
        self.value = value
        self.upperValue = upperValue
    }
}

nonisolated enum MarinaRowSortDirection: Equatable, Sendable {
    case ascending
    case descending
}

nonisolated enum MarinaRowSortTarget: Equatable, Sendable {
    case field(MarinaFieldKey)
    case relationship(MarinaRelationshipKey)
}

nonisolated struct MarinaRowSort: Equatable, Sendable {
    let target: MarinaRowSortTarget
    let direction: MarinaRowSortDirection
}

nonisolated enum MarinaRowGroupTarget: Equatable, Sendable {
    case field(MarinaFieldKey)
    case relationship(MarinaRelationshipKey)
}

nonisolated struct MarinaGroupedRows: Equatable, Sendable {
    let key: String
    let displayName: String
    let rows: [MarinaQueryableRow]
}

struct MarinaRowOperationEngine: Sendable {
    func search(
        _ rows: [MarinaQueryableRow],
        clause: MarinaRowSearchClause,
        catalog: MarinaEntityCatalog
    ) -> [MarinaQueryableRow] {
        let query = normalizedText(clause.query)
        guard query.isEmpty == false else {
            return rows
        }

        return rows.filter { row in
            guard let descriptor = catalog.descriptor(for: row.entity) else {
                return false
            }
            let searchableFields = Set(
                descriptor.fields
                    .filter { $0.isSearchable && $0.valueType == .text }
                    .map(\.key)
            )
            let fields = clause.fields.intersection(searchableFields)

            return fields.contains { field in
                guard case let .text(value) = row.fields[field] else {
                    return false
                }
                return normalizedText(value).contains(query)
            }
        }
    }

    func search(
        _ rows: [MarinaQueryableRow],
        clause: MarinaRowSearchClause,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> [MarinaQueryableRow] {
        let query = normalizedText(clause.query)
        guard query.isEmpty == false else {
            return rows
        }

        let searchableFields = Set(
            descriptor.fields
                .filter { $0.isSearchable && $0.valueType == .text }
                .map(\.key)
        )
        let fields = clause.fields.intersection(searchableFields)

        return rows.filter { row in
            fields.contains { field in
                guard case let .text(value) = row.fields[field] else {
                    return false
                }
                return normalizedText(value).contains(query)
            }
        }
    }

    func filter(
        _ rows: [MarinaQueryableRow],
        filters: [MarinaRowFilter]
    ) -> [MarinaQueryableRow] {
        guard filters.isEmpty == false else {
            return rows
        }

        return rows.filter { row in
            filters.allSatisfy { filter in
                matches(row: row, filter: filter)
            }
        }
    }

    func sort(
        _ rows: [MarinaQueryableRow],
        sorts: [MarinaRowSort]
    ) -> [MarinaQueryableRow] {
        guard sorts.isEmpty == false else {
            return rows
        }

        return rows.enumerated()
            .sorted { left, right in
                for sort in sorts {
                    let comparison = compare(left.element, right.element, target: sort.target)
                    if comparison != .orderedSame {
                        return sort.direction == .ascending
                            ? comparison == .orderedAscending
                            : comparison == .orderedDescending
                    }
                }

                let tieBreak = compareTieBreakers(left.element, right.element)
                if tieBreak != .orderedSame {
                    return tieBreak == .orderedAscending
                }

                return left.offset < right.offset
            }
            .map(\.element)
    }

    func group(
        _ rows: [MarinaQueryableRow],
        by target: MarinaRowGroupTarget
    ) -> [MarinaGroupedRows] {
        let grouped = Dictionary(grouping: rows) { row in
            groupKey(for: row, target: target)
        }

        return grouped.map { key, rows in
            MarinaGroupedRows(key: key.key, displayName: key.displayName, rows: rows)
        }
        .sorted { left, right in
            let nameComparison = compareText(left.displayName, right.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return compareText(left.key, right.key) == .orderedAscending
        }
    }

    func count(_ rows: [MarinaQueryableRow]) -> Int {
        rows.count
    }

    func sum(
        _ rows: [MarinaQueryableRow],
        field: MarinaFieldKey
    ) -> Double {
        numericValues(rows, field: field).reduce(0, +)
    }

    func average(
        _ rows: [MarinaQueryableRow],
        field: MarinaFieldKey
    ) -> Double? {
        let values = numericValues(rows, field: field)
        guard values.isEmpty == false else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    func limit(
        _ rows: [MarinaQueryableRow],
        to count: Int?
    ) -> [MarinaQueryableRow] {
        guard let count else {
            return rows
        }
        guard count > 0 else {
            return []
        }
        return Array(rows.prefix(count))
    }

    private func matches(row: MarinaQueryableRow, filter: MarinaRowFilter) -> Bool {
        switch filter.target {
        case let .field(field):
            return matches(
                value: row.fields[field] ?? .empty,
                operation: filter.operation,
                filterValue: filter.value,
                upperValue: filter.upperValue
            )
        case let .relationship(key):
            return matches(
                relationship: row.relationships[key],
                operation: filter.operation,
                filterValue: filter.value
            )
        }
    }

    private func matches(
        value: MarinaValue,
        operation: MarinaRowFilterOperator,
        filterValue: MarinaValue,
        upperValue: MarinaValue?
    ) -> Bool {
        switch operation {
        case .equals:
            return equals(value, filterValue)
        case .contains:
            guard case let .text(left) = value,
                  case let .text(right) = filterValue else {
                return false
            }
            return normalizedText(left).contains(normalizedText(right))
        case .greaterThan:
            return compare(value, filterValue) == .orderedDescending
        case .greaterThanOrEqual:
            let comparison = compare(value, filterValue)
            return comparison == .orderedDescending || comparison == .orderedSame
        case .lessThan:
            return compare(value, filterValue) == .orderedAscending
        case .lessThanOrEqual:
            let comparison = compare(value, filterValue)
            return comparison == .orderedAscending || comparison == .orderedSame
        case .between:
            guard let upperValue else {
                return false
            }
            let lowerComparison = compare(value, filterValue)
            let upperComparison = compare(value, upperValue)
            return (lowerComparison == .orderedDescending || lowerComparison == .orderedSame)
                && (upperComparison == .orderedAscending || upperComparison == .orderedSame)
        }
    }

    private func matches(
        relationship: MarinaResolvedRelationship?,
        operation: MarinaRowFilterOperator,
        filterValue: MarinaValue
    ) -> Bool {
        if relationshipIsEmpty(relationship) {
            return operation == .equals && filterValue == .empty
        }

        guard let relationship else {
            return false
        }

        switch operation {
        case .equals:
            if case let .text(value) = filterValue {
                let normalizedValue = normalizedText(value)
                let displayNameMatches = relationship.displayName.map { normalizedText($0) == normalizedValue } ?? false
                let idMatches = relationship.targetID?.uuidString.lowercased() == value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return displayNameMatches || idMatches
            }
            return filterValue == .empty && relationshipIsEmpty(relationship)
        case .contains:
            guard case let .text(value) = filterValue,
                  let displayName = relationship.displayName else {
                return false
            }
            return normalizedText(displayName).contains(normalizedText(value))
        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between:
            return false
        }
    }

    private func equals(_ left: MarinaValue, _ right: MarinaValue) -> Bool {
        switch (left, right) {
        case let (.text(left), .text(right)):
            return normalizedText(left) == normalizedText(right)
        case let (.colorHex(left), .colorHex(right)):
            return normalizedText(left) == normalizedText(right)
        case let (.money(left), .money(right)):
            return left == right
        case let (.number(left), .number(right)):
            return left == right
        case let (.integer(left), .integer(right)):
            return left == right
        case let (.date(left), .date(right)):
            return left == right
        case let (.boolean(left), .boolean(right)):
            return left == right
        case (.empty, .empty):
            return true
        default:
            if let leftNumber = numericValue(left), let rightNumber = numericValue(right) {
                return leftNumber == rightNumber
            }
            return false
        }
    }

    private func compare(_ left: MarinaValue, _ right: MarinaValue) -> ComparisonResult {
        switch (left, right) {
        case let (.text(left), .text(right)):
            return compareText(left, right)
        case let (.colorHex(left), .colorHex(right)):
            return compareText(left, right)
        case let (.date(left), .date(right)):
            return compareComparable(left, right)
        case let (.boolean(left), .boolean(right)):
            return compareComparable(left ? 1 : 0, right ? 1 : 0)
        default:
            if let leftNumber = numericValue(left), let rightNumber = numericValue(right) {
                return compareComparable(leftNumber, rightNumber)
            }
            return .orderedSame
        }
    }

    private func compare(
        _ left: MarinaQueryableRow,
        _ right: MarinaQueryableRow,
        target: MarinaRowSortTarget
    ) -> ComparisonResult {
        switch target {
        case let .field(field):
            return compare(left.fields[field] ?? .empty, right.fields[field] ?? .empty)
        case let .relationship(key):
            let leftName = relationshipDisplayName(left.relationships[key], key: key)
            let rightName = relationshipDisplayName(right.relationships[key], key: key)
            return compareText(leftName, rightName)
        }
    }

    private func compareTieBreakers(
        _ left: MarinaQueryableRow,
        _ right: MarinaQueryableRow
    ) -> ComparisonResult {
        let displayNameComparison = compareText(left.displayName, right.displayName)
        if displayNameComparison != .orderedSame {
            return displayNameComparison
        }
        return compareText(left.id.uuidString, right.id.uuidString)
    }

    private func numericValues(
        _ rows: [MarinaQueryableRow],
        field: MarinaFieldKey
    ) -> [Double] {
        rows.compactMap { row in
            numericValue(row.fields[field] ?? .empty)
        }
    }

    private func numericValue(_ value: MarinaValue) -> Double? {
        switch value {
        case let .money(value), let .number(value):
            return value
        case let .integer(value):
            return Double(value)
        case .text, .date, .boolean, .colorHex, .empty:
            return nil
        }
    }

    private func groupKey(
        for row: MarinaQueryableRow,
        target: MarinaRowGroupTarget
    ) -> GroupKey {
        switch target {
        case let .field(field):
            let displayValue = displayValue(for: row.fields[field] ?? .empty)
            return GroupKey(key: displayValue, displayName: displayValue)
        case let .relationship(key):
            let displayName = relationshipDisplayName(row.relationships[key], key: key)
            return GroupKey(key: displayName, displayName: displayName)
        }
    }

    private func displayValue(for value: MarinaValue) -> String {
        switch value {
        case let .text(value):
            return value
        case let .money(value), let .number(value):
            return String(value)
        case let .integer(value):
            return String(value)
        case let .date(value):
            return String(value.timeIntervalSince1970)
        case let .boolean(value):
            return value ? "true" : "false"
        case let .colorHex(value):
            return value
        case .empty:
            return "Unassigned"
        }
    }

    private func relationshipDisplayName(
        _ relationship: MarinaResolvedRelationship?,
        key: MarinaRelationshipKey
    ) -> String {
        guard let displayName = relationship?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              displayName.isEmpty == false else {
            return key == .category ? "Uncategorized" : "Unassigned"
        }
        return displayName
    }

    private func relationshipIsEmpty(_ relationship: MarinaResolvedRelationship?) -> Bool {
        guard let relationship else {
            return true
        }
        let displayName = relationship.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return displayName.isEmpty && relationship.targetID == nil
    }

    private func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func compareText(_ left: String, _ right: String) -> ComparisonResult {
        let left = normalizedText(left)
        let right = normalizedText(right)

        if left < right {
            return .orderedAscending
        }
        if left > right {
            return .orderedDescending
        }
        return .orderedSame
    }

    private func compareComparable<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right {
            return .orderedAscending
        }
        if left > right {
            return .orderedDescending
        }
        return .orderedSame
    }
}

private struct GroupKey: Hashable {
    let key: String
    let displayName: String
}
