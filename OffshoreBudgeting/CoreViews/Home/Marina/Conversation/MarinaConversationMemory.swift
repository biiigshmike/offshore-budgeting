import Foundation

/// Bounded, non-executable references for follow-ups. Financial values always require a fresh tool call.
nonisolated struct MarinaConversationMemory: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maxStoredBytes = 12_288
    static let maxEntities = 12
    static let maxQueries = 6
    static let maxReferences = 24

    struct Entity: Codable, Equatable, Sendable {
        let kind: String
        let id: String
        let name: String
    }

    struct Selection: Codable, Equatable, Sendable {
        var cardID: String?
        var categoryID: String?
        var budgetID: String?
        var presetID: String?
        var accountID: String?
        var search: String?

        var isEmpty: Bool {
            cardID == nil && categoryID == nil && budgetID == nil && presetID == nil && accountID == nil && search == nil
        }
    }

    struct Period: Codable, Equatable, Sendable {
        let allTime: Bool?
        let relative: MarinaDataRequest.RelativePeriod?
        let startDate: String?
        let endDate: String?
    }

    struct Query: Codable, Equatable, Sendable {
        let tool: MarinaDataRequest.Tool
        let operation: MarinaDataRequest.Operation
        let purpose: MarinaDataRequest.Purpose?
        let selection: Selection?
        let period: Period
        let measure: MarinaDataRequest.ExpenseMeasure?
        let scope: MarinaDataRequest.Scope?
        let state: MarinaDataRequest.State?
        let grouping: MarinaDataRequest.Grouping?
        let periodUnit: MarinaDataRequest.PeriodUnit?
        let includeFuture: Bool?
        let recordKind: String?
        let sort: MarinaDataRequest.Sort?
        let offset: Int?
        let limit: Int?
        let nextOffset: Int?
        let comparisonSelection: Selection?
        let comparisonPeriod: Period?
        let answerID: UUID
        let resultID: String?
    }

    struct Clarification: Codable, Equatable, Sendable {
        let search: String?
        let recordKind: String?
        let candidates: [Entity]
        let totalCount: Int
        let nextOffset: Int?
        let answerID: UUID
        var originatingPrompt: String? = nil
        var period: Period? = nil
    }

    private struct EntityReference: Codable, Equatable, Sendable {
        let reference: String
        let entity: Entity
    }

    let version: Int
    let workspaceID: UUID
    let chatID: UUID
    private(set) var confirmedEntities: [Entity]
    private(set) var recentQueries: [Query]
    private(set) var pendingClarification: Clarification?
    private var entityReferences: [EntityReference]
    private var nextReferenceNumber: Int

    var latestFinancialQuery: Query? { recentQueries.last { $0.tool != .findRecords } }

    init(workspaceID: UUID, chatID: UUID) {
        version = Self.currentVersion
        self.workspaceID = workspaceID
        self.chatID = chatID
        confirmedEntities = []
        recentQueries = []
        entityReferences = []
        nextReferenceNumber = 1
    }

    /// The reference is usable only in this memory's workspace and chat. Evicted names are never reused.
    /// Invalid oversized entities cannot receive a reference.
    mutating func reference(for entity: Entity) -> String {
        guard Self.bounded(entity.kind) != nil, Self.bounded(entity.id) != nil,
              Self.bounded(entity.name) != nil else { return "" }
        if let index = entityReferences.firstIndex(where: { $0.entity.kind == entity.kind && $0.entity.id == entity.id }) {
            let reference = entityReferences[index].reference
            entityReferences.remove(at: index)
            entityReferences.append(EntityReference(reference: reference, entity: entity))
            trim(to: Self.maxStoredBytes)
            return reference
        }
        guard nextReferenceNumber < Int.max else { return "" }
        let reference = "r\(nextReferenceNumber)"
        nextReferenceNumber += 1
        entityReferences.append(EntityReference(reference: reference, entity: entity))
        while entityReferences.count > Self.maxReferences { discardOldestReference() }
        trim(to: Self.maxStoredBytes)
        return reference
    }

    func entity(forReference reference: String) -> Entity? {
        entityReferences.first { $0.reference == reference }?.entity
    }

    func reference(forKind kind: String, id: String) -> String? {
        entityReferences.first { $0.entity.kind == kind && $0.entity.id == id }?.reference
    }

    /// Call only with the result of the workspace-bound, validating data service.
    mutating func record(request: MarinaDataRequest, result: MarinaDataResult, answerID: UUID, prompt: String? = nil) {
        guard ["success", "empty", "candidates"].contains(result.status),
              result.presentation?.pagination.map({ $0.workspaceID == workspaceID }) ?? true else { return }
        if let returnedWorkspace = result.records.first(where: { $0.kind == "workspace" }),
           returnedWorkspace.id != workspaceID.uuidString { return }

        let entities = result.records.compactMap(Self.entity)
        if request.tool == .findRecords && result.status == "candidates" {
            // Candidates are deliberately separate from confirmed entities. Never guess a selection.
            let retainedCandidates = Array(entities.prefix(Self.maxEntities))
            for entity in retainedCandidates { _ = reference(for: entity) }
            let previous = pendingClarification.flatMap { pending in
                pending.search?.compare(request.search ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    ? pending : nil
            }
            let period = Self.clarificationPeriod(request: request, result: result, prompt: prompt, previous: previous?.period)
            pendingClarification = Clarification(
                search: Self.bounded(request.search), recordKind: Self.bounded(request.recordKind),
                candidates: retainedCandidates, totalCount: result.totalCount,
                nextOffset: result.nextOffset, answerID: answerID,
                originatingPrompt: previous?.originatingPrompt ?? Self.boundedPrompt(prompt), period: period
            )
        } else {
            if request.tool == .findRecords || request.tool == .accounts {
                for entity in entities { remember(entity) }
            }
            if let card = result.presentation?.card,
               let name = Self.bounded(card.name), let id = Self.bounded(card.id) {
                remember(Entity(kind: "card", id: id, name: name))
            }
            let selectedCandidates = resolvedCandidates(request)
            for entity in selectedCandidates { remember(entity) }
            let matchingCandidateLookup = request.tool == .findRecords && result.status == "success"
                && request.search?.isEmpty == false && entities.count == 1
                && pendingClarification?.candidates.contains(where: { candidate in
                    candidate.kind == entities[0].kind && candidate.id == entities[0].id
                }) == true
            if matchingCandidateLookup, var pending = pendingClarification {
                // Resolving a name is not yet the financial answer. Keep its intent across a
                // cancellation or failure between lookup and the validated financial read.
                pending.period = Self.clarificationPeriod(request: request, result: result, prompt: prompt, previous: pending.period)
                pendingClarification = pending
            } else if result.status == "success" || result.status == "empty" {
                // A completed financial read or unrelated lookup ends the pending question.
                pendingClarification = nil
            }
        }

        let effective = result.resolvedRequest ?? result.presentation?.pagination?.request ?? request
        // Never turn an overlong named filter into an unfiltered workspace query in memory.
        guard Self.canRememberQuery(effective) else {
            // An older query must not appear to be the latest successful request after renewal.
            recentQueries.removeAll()
            trim(to: Self.maxStoredBytes)
            return
        }
        let selection = Self.selection(effective)
        let comparison = effective.comparisonFilter.map {
            Selection(cardID: Self.bounded($0.cardID), categoryID: Self.bounded($0.categoryID),
                      budgetID: Self.bounded($0.budgetID), presetID: Self.bounded($0.presetID),
                      search: Self.bounded($0.search))
        }
        let hasComparison = effective.comparisonAllTime || effective.comparisonPeriod != nil
            || effective.comparisonStartDate != nil || effective.comparisonEndDate != nil || comparison != nil
        let operation = result.presentation?.operation ?? effective.operation
        registerSelection(selection, tool: effective.tool, scope: effective.scope)
        if let comparison { registerSelection(comparison, tool: effective.tool, scope: effective.scope) }
        let isList = effective.tool == .findRecords || effective.tool == .accounts
            || [.transactions, .inventory, .ranking, .share, .trend].contains(operation)
        recentQueries.append(Query(
            tool: effective.tool, operation: operation,
            purpose: effective.purpose, selection: selection.isEmpty ? nil : selection,
            period: Period(allTime: effective.allTime ? true : nil, relative: effective.relativePeriod,
                           startDate: Self.bounded(effective.startDate), endDate: Self.bounded(effective.endDate)),
            measure: effective.tool == .expenses ? effective.expenseMeasure : nil,
            scope: effective.scope == .all ? nil : effective.scope,
            state: effective.state == .all ? nil : effective.state,
            grouping: effective.grouping == .none ? nil : effective.grouping,
            periodUnit: effective.periodUnit, includeFuture: effective.includeFuture ? true : nil,
            recordKind: Self.bounded(effective.recordKind),
            sort: isList ? effective.sort : nil, offset: isList ? effective.offset : nil,
            limit: isList ? effective.limit : nil, nextOffset: isList ? result.nextOffset : nil,
            comparisonSelection: comparison,
            comparisonPeriod: hasComparison ? Period(allTime: effective.comparisonAllTime ? true : nil,
                relative: effective.comparisonPeriod, startDate: Self.bounded(effective.comparisonStartDate),
                endDate: Self.bounded(effective.comparisonEndDate)) : nil,
            answerID: answerID, resultID: Self.bounded(result.presentation?.id)
        ))
        while recentQueries.count > Self.maxQueries {
            // Repeated resolution attempts must not erase the last complete financial context.
            let latestFinancialIndex = recentQueries.lastIndex { $0.tool != .findRecords }
            recentQueries.remove(at: latestFinancialIndex == 0 ? 1 : 0)
        }
        trim(to: Self.maxStoredBytes)
    }

    /// JSON values are data, including names supplied by users. Do not splice them into instructions.
    /// Drop complete old units rather than truncating JSON, names, or a query's comparison context.
    func contextText(maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var copy = self
        copy.trim(to: min(maxBytes, Self.maxStoredBytes), forModel: true)
        guard let data = copy.encoded(forModel: true), data.count <= maxBytes,
              !copy.recentQueries.isEmpty || !copy.confirmedEntities.isEmpty || copy.pendingClarification != nil else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private mutating func remember(_ entity: Entity) {
        _ = reference(for: entity)
        confirmedEntities.removeAll { $0.kind == entity.kind && $0.id == entity.id }
        confirmedEntities.append(entity)
        confirmedEntities = Array(confirmedEntities.suffix(Self.maxEntities))
    }

    private func resolvedCandidates(_ request: MarinaDataRequest) -> [Entity] {
        guard let pendingClarification else { return [] }
        let selection = Self.selection(request)
        return pendingClarification.candidates.filter { candidate in
            switch candidate.kind {
            case "card": return selection.cardID == candidate.id
            case "category": return selection.categoryID == candidate.id
            case "budget": return selection.budgetID == candidate.id
            case "preset": return selection.presetID == candidate.id
            case "savingsAccount", "reconciliationAccount": return selection.accountID == candidate.id
            case "merchant": return request.tool == .expenses && selection.search == candidate.name
            case "incomeSource": return request.tool == .income && selection.search == candidate.name
            default: return false
            }
        }
    }

    private static func canRememberQuery(_ request: MarinaDataRequest) -> Bool {
        let text = [request.cardID, request.categoryID, request.budgetID, request.presetID,
                    request.accountID, request.search, request.startDate, request.endDate, request.recordKind,
                    request.comparisonStartDate, request.comparisonEndDate, request.comparisonFilter?.cardID,
                    request.comparisonFilter?.categoryID, request.comparisonFilter?.budgetID,
                    request.comparisonFilter?.presetID, request.comparisonFilter?.search]
        return text.compactMap { $0 }.allSatisfy { bounded($0) != nil }
    }

    private static func selection(_ request: MarinaDataRequest) -> Selection {
        Selection(cardID: bounded(request.cardID), categoryID: bounded(request.categoryID),
                  budgetID: bounded(request.budgetID), presetID: bounded(request.presetID),
                  accountID: bounded(request.accountID), search: bounded(request.search))
    }

    private static func entity(_ record: MarinaDataResult.Record) -> Entity? {
        guard ["workspace", "card", "category", "budget", "preset", "savingsAccount", "reconciliationAccount", "merchant", "incomeSource"].contains(record.kind),
              let id = bounded(record.id), let name = bounded(record.title) else { return nil }
        return Entity(kind: record.kind, id: id, name: name)
    }

    private static func bounded(_ text: String?) -> String? {
        guard let text, !text.isEmpty, text.utf8.count <= 256 else { return nil }
        return text
    }

    private static func boundedPrompt(_ text: String?) -> String? {
        guard let text, !text.isEmpty, text.utf8.count <= 768 else { return nil }
        return text
    }

    private static func clarificationPeriod(request: MarinaDataRequest, result: MarinaDataResult,
                                            prompt: String?, previous: Period?) -> Period? {
        switch MarinaTurnPolicy(prompt: prompt ?? "").periodCue {
        case .none: return previous
        case .other: return nil
        case .relative(let expected):
            guard request.relativePeriod == expected, let resolved = result.resolvedRequest,
                  let start = bounded(resolved.startDate), let end = bounded(resolved.endDate) else { return nil }
            return Period(allTime: nil, relative: nil, startDate: start, endDate: end)
        }
    }

    private mutating func registerSelection(_ selection: Selection, tool: MarinaDataRequest.Tool,
                                            scope: MarinaDataRequest.Scope) {
        let namedIDs: [(String, String?)] = [("card", selection.cardID), ("category", selection.categoryID),
            ("budget", selection.budgetID), ("preset", selection.presetID)]
        for (kind, id) in namedIDs {
            if let id, reference(forKind: kind, id: id) == nil {
                _ = reference(for: Entity(kind: kind, id: id, name: kind))
            }
        }
        if let name = selection.search, tool == .expenses || tool == .income {
            let kind = tool == .expenses ? "merchant" : "incomeSource"
            _ = reference(for: Entity(kind: kind, id: name, name: name))
        }
        if let id = selection.accountID,
           !entityReferences.contains(where: { $0.entity.id == id && ["savingsAccount", "reconciliationAccount"].contains($0.entity.kind) }) {
            let kind = scope == .savings ? "savingsAccount" : scope == .reconciliation ? "reconciliationAccount" : nil
            if let kind { _ = reference(for: Entity(kind: kind, id: id, name: kind)) }
        }
    }

    private func selectionReferences(_ selection: Selection?, tool: MarinaDataRequest.Tool) -> [String]? {
        guard let selection, !selection.isEmpty else { return [] }
        var references: [String] = []
        let namedIDs: [(String, String?)] = [("card", selection.cardID), ("category", selection.categoryID),
            ("budget", selection.budgetID), ("preset", selection.presetID),
            (tool == .income ? "incomeSource" : "merchant", selection.search)]
        for (kind, id) in namedIDs {
            guard let id else { continue }
            guard let reference = reference(forKind: kind, id: id) else { return nil }
            references.append(reference)
        }
        if let id = selection.accountID {
            guard let reference = entityReferences.first(where: {
                $0.entity.id == id && ["savingsAccount", "reconciliationAccount"].contains($0.entity.kind)
            })?.reference else { return nil }
            references.append(reference)
        }
        return references
    }

    private mutating func discardOldestReference() {
        var protected: Set<String> = []
        if let latest = latestFinancialQuery {
            protected.formUnion(selectionReferences(latest.selection, tool: latest.tool) ?? [])
            if let selection = latest.comparisonSelection {
                protected.formUnion(selectionReferences(selection, tool: latest.tool) ?? [])
            }
        }
        guard !entityReferences.isEmpty else { return }
        let index = entityReferences.firstIndex { !protected.contains($0.reference) } ?? 0
        entityReferences.remove(at: index)
    }

    private mutating func trim(to bytes: Int, forModel: Bool = false) {
        while (encoded(forModel: forModel)?.count ?? Int.max) > bytes {
            if recentQueries.count > 1 {
                let latestFinancialIndex = recentQueries.lastIndex { $0.tool != .findRecords }
                recentQueries.remove(at: latestFinancialIndex == 0 ? 1 : 0)
            }
            else if !confirmedEntities.isEmpty { confirmedEntities.removeFirst() }
            else if let pending = pendingClarification, pending.candidates.count > 1 {
                pendingClarification = Clarification(search: pending.search, recordKind: pending.recordKind,
                    candidates: Array(pending.candidates.dropLast()), totalCount: pending.totalCount,
                    nextOffset: pending.nextOffset, answerID: pending.answerID, originatingPrompt: pending.originatingPrompt, period: pending.period)
            }
            else if let pending = pendingClarification, pending.originatingPrompt != nil {
                var compact = pending
                compact.originatingPrompt = nil
                pendingClarification = compact
            }
            else if let pending = pendingClarification, !pending.candidates.isEmpty {
                // Keep the unresolved choice, its full match count and the latest query even
                // when long names cannot all fit. Every retained candidate remains complete.
                pendingClarification = Clarification(search: pending.search, recordKind: pending.recordKind,
                    candidates: Array(pending.candidates.dropLast()), totalCount: pending.totalCount,
                    nextOffset: pending.nextOffset, answerID: pending.answerID, originatingPrompt: pending.originatingPrompt, period: pending.period)
            }
            else if !forModel && !entityReferences.isEmpty { discardOldestReference() }
            else if !recentQueries.isEmpty { recentQueries.removeFirst() }
            else if pendingClarification != nil { pendingClarification = nil }
            else { break }
        }
    }

    private func encoded(forModel: Bool = false) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return forModel ? try? encoder.encode(ModelContext(self)) : try? encoder.encode(self)
    }

    /// Persistence IDs are useful to the app, but cannot select financial data in a tool call.
    private struct ModelContext: Encodable {
        struct ModelEntity: Encodable {
            let kind: String
            let selection: String?
            let name: String
            init(_ entity: Entity, memory: MarinaConversationMemory) {
                kind = entity.kind
                selection = entity.kind == "workspace" ? "workspace" : memory.reference(forKind: entity.kind, id: entity.id)
                name = entity.name
            }
        }
        struct ModelClarification: Encodable {
            let search: String?
            let recordKind: String?
            let candidates: [ModelEntity]
            let totalCount: Int
            let nextOffset: Int?
            let originatingPrompt: String?
            let dates: ModelDates?
            init(_ clarification: Clarification, memory: MarinaConversationMemory) {
                search = clarification.search
                recordKind = clarification.recordKind
                candidates = clarification.candidates.map { ModelEntity($0, memory: memory) }
                totalCount = clarification.totalCount
                nextOffset = clarification.nextOffset
                originatingPrompt = clarification.originatingPrompt
                dates = clarification.period.flatMap(ModelDates.init)
            }
        }
        struct ModelQuery: Encodable {
            let query: Query
            let selection: ModelSelection?
            let comparisonSelection: ModelSelection?
            init?(_ query: Query, memory: MarinaConversationMemory, isLatest: Bool) {
                self.query = query
                if query.tool == .findRecords {
                    selection = nil
                    comparisonSelection = nil
                    return
                }
                func modelSelection(_ selection: Selection?, allowPrevious: Bool) -> ModelSelection? {
                    if let refs = memory.selectionReferences(selection, tool: query.tool) {
                        return refs.isEmpty ? .workspace : .references(refs)
                    }
                    return allowPrevious ? .previous : nil
                }
                guard let selected = modelSelection(query.selection, allowPrevious: isLatest) else { return nil }
                selection = selected
                if query.comparisonSelection != nil || query.comparisonPeriod != nil {
                    let sameSelection = query.comparisonSelection == nil || query.comparisonSelection == query.selection
                    guard let compared = modelSelection(query.comparisonSelection ?? query.selection,
                                                        allowPrevious: isLatest && sameSelection) else { return nil }
                    comparisonSelection = compared
                } else { comparisonSelection = nil }
            }
            enum CodingKeys: String, CodingKey {
                case tool, operation, purpose, selection, period, measure, scope, state, grouping, periodUnit
                case includeFuture, recordKind, sort, offset, limit, nextOffset, comparisonSelection
                case dates, comparison, cardID, categoryID, budgetID, presetID, accountID, source, search
            }
            func encode(to encoder: Encoder) throws {
                var values = encoder.container(keyedBy: CodingKeys.self)
                let toolName: String
                switch query.tool {
                case .expenses: toolName = "readExpenses"
                case .income: toolName = "readIncome"
                case .budgetSummary: toolName = "readBudgetSummary"
                case .accounts: toolName = "readAccounts"
                case .findRecords: toolName = "findRecords"
                }
                try values.encode(toolName, forKey: .tool)
                try values.encodeIfPresent(selection, forKey: .selection)
                if (query.tool == .expenses || query.tool == .income), query.operation == .comparison {
                    let operation = query.tool == .expenses ? "compare" : "compareIncome"
                    try values.encode(operation, forKey: .operation)
                    try values.encode(ModelComparison(
                        selection: comparisonSelection ?? selection ?? .previous,
                        dates: query.comparisonPeriod.flatMap(ModelDates.init)), forKey: .comparison)
                } else if query.tool == .expenses {
                    try values.encode(expenseOperation, forKey: .operation)
                } else {
                    let operation = query.purpose == .incomeProgress ? "progress"
                        : query.purpose == .budgetPace ? "pace"
                        : query.tool == .budgetSummary && query.periodUnit == nil ? "overview" : query.operation.rawValue
                    try values.encode(operation, forKey: .operation)
                    if query.purpose != .incomeProgress && query.purpose != .budgetPace {
                        try values.encodeIfPresent(query.purpose, forKey: .purpose)
                    }
                    if query.tool == .findRecords { try values.encodeIfPresent(query.selection?.search, forKey: .search) }
                    if query.tool != .income { try values.encodeIfPresent(comparisonSelection, forKey: .comparisonSelection) }
                }
                try values.encodeIfPresent(ModelDates(query.period), forKey: .dates)
                try values.encodeIfPresent(query.measure, forKey: .measure)
                try values.encodeIfPresent(query.scope, forKey: .scope)
                try values.encodeIfPresent(query.state, forKey: .state)
                try values.encodeIfPresent(query.grouping, forKey: .grouping)
                try values.encodeIfPresent(query.periodUnit, forKey: .periodUnit)
                try values.encodeIfPresent(query.includeFuture, forKey: .includeFuture)
                try values.encodeIfPresent(query.recordKind, forKey: .recordKind)
                try values.encodeIfPresent(query.sort, forKey: .sort)
                try values.encodeIfPresent(query.offset, forKey: .offset)
                try values.encodeIfPresent(query.limit, forKey: .limit)
                try values.encodeIfPresent(query.nextOffset, forKey: .nextOffset)
                if query.tool != .expenses, query.tool != .income,
                   let period = query.comparisonPeriod {
                    try values.encodeIfPresent(ModelDates(period), forKey: .comparison)
                }
            }

            private var expenseOperation: String {
                if query.purpose == .upcomingPresets { return "upcomingPresets" }
                switch query.operation {
                case .transactions where query.sort == .largest && query.limit == 1: return "largestPurchase"
                case .ranking, .share:
                    let target: String
                    switch query.grouping {
                    case .card: target = "card"
                    case .merchant: target = "merchant"
                    case .category: target = "category"
                    default: return query.operation.rawValue
                    }
                    return target + (query.operation == .share ? "Shares" : "Totals")
                case .trend: return "periodTotals"
                case .comparison: return "compare"
                default: return query.operation.rawValue
                }
            }
        }

        enum ModelSelection: Encodable {
            case workspace, previous, references([String])
            func encode(to encoder: Encoder) throws {
                var value = encoder.singleValueContainer()
                switch self {
                case .workspace, .previous:
                    try value.encode(self.isWorkspace ? "workspace" : "previous")
                case .references(let references):
                    try value.encode(references.joined(separator: ","))
                }
            }
            private var isWorkspace: Bool { if case .workspace = self { true } else { false } }
        }

        struct ModelComparison: Encodable {
            let selection: ModelSelection
            let dates: ModelDates?
        }

        struct ModelDates: Encodable {
            let period: Period
            init?(_ period: Period) {
                guard period.startDate != nil || period.endDate != nil || period.allTime == true || period.relative != nil else { return nil }
                self.period = period
            }
            enum CodingKeys: String, CodingKey { case start, end }
            func encode(to encoder: Encoder) throws {
                if period.startDate != nil || period.endDate != nil {
                    var values = encoder.container(keyedBy: CodingKeys.self)
                    try values.encodeIfPresent(period.startDate, forKey: .start)
                    try values.encodeIfPresent(period.endDate, forKey: .end)
                } else {
                    var value = encoder.singleValueContainer()
                    try value.encode(period.allTime == true ? "allTime" : period.relative?.rawValue)
                }
            }
        }
        let confirmedEntities: [ModelEntity]?
        let latestQuery: ModelQuery?
        let recentQueries: [ModelQuery]?
        let pendingClarification: ModelClarification?
        init(_ memory: MarinaConversationMemory) {
            confirmedEntities = memory.confirmedEntities.isEmpty ? nil
                : memory.confirmedEntities.map { ModelEntity($0, memory: memory) }
            let latestIndex = memory.recentQueries.lastIndex { $0.tool != .findRecords }
                ?? memory.recentQueries.indices.last
            latestQuery = latestIndex.flatMap { ModelQuery(memory.recentQueries[$0], memory: memory, isLatest: true) }
            let hasFinancialRead = memory.latestFinancialQuery != nil
            let older = memory.recentQueries.enumerated().compactMap { index, query -> ModelQuery? in
                guard index != latestIndex else { return nil }
                if query.tool == .findRecords && hasFinancialRead { return nil }
                return ModelQuery(query, memory: memory, isLatest: false)
            }
            recentQueries = older.isEmpty ? nil : older
            pendingClarification = memory.pendingClarification.map { ModelClarification($0, memory: memory) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, workspaceID, chatID, confirmedEntities, recentQueries, pendingClarification
        case entityReferences, nextReferenceNumber
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported conversation memory version")
        }
        workspaceID = try values.decode(UUID.self, forKey: .workspaceID)
        chatID = try values.decode(UUID.self, forKey: .chatID)
        confirmedEntities = try values.decode([Entity].self, forKey: .confirmedEntities)
        recentQueries = try values.decode([Query].self, forKey: .recentQueries)
        pendingClarification = try values.decodeIfPresent(Clarification.self, forKey: .pendingClarification)
        entityReferences = try values.decodeIfPresent([EntityReference].self, forKey: .entityReferences) ?? []
        let largestReference = entityReferences.compactMap { Int($0.reference.dropFirst()) }.max() ?? 0
        let savedNext = try values.decodeIfPresent(Int.self, forKey: .nextReferenceNumber) ?? 1
        guard entityReferences.count <= Self.maxReferences,
              Set(entityReferences.map(\.reference)).count == entityReferences.count,
              entityReferences.allSatisfy({ entry in
                  entry.reference.first == "r" && Int(entry.reference.dropFirst()).map { $0 > 0 && $0 < Int.max - 1 } == true
                      && Self.bounded(entry.entity.kind) != nil && Self.bounded(entry.entity.id) != nil
                      && Self.bounded(entry.entity.name) != nil
              }), savedNext > 0, savedNext < Int.max else {
            throw DecodingError.dataCorruptedError(forKey: .entityReferences, in: values, debugDescription: "Invalid entity references")
        }
        nextReferenceNumber = max(savedNext, largestReference + 1)
        guard confirmedEntities.count <= Self.maxEntities, recentQueries.count <= Self.maxQueries,
              (pendingClarification?.candidates.count ?? 0) <= Self.maxEntities else {
            throw DecodingError.dataCorruptedError(forKey: .recentQueries, in: values, debugDescription: "Conversation memory exceeds retention bounds")
        }
        // Known version 1 payloads predate references. Upgrade only validated data fields;
        // unknown payload versions still fail above and never become executable context.
        if !values.contains(.entityReferences) {
            for entity in confirmedEntities + (pendingClarification?.candidates ?? []) { _ = reference(for: entity) }
            for query in recentQueries {
                if let selection = query.selection { registerSelection(selection, tool: query.tool, scope: query.scope ?? .all) }
                if let selection = query.comparisonSelection { registerSelection(selection, tool: query.tool, scope: query.scope ?? .all) }
            }
        }
        if let pending = pendingClarification, Self.boundedPrompt(pending.originatingPrompt) != pending.originatingPrompt {
            var bounded = pending
            bounded.originatingPrompt = nil
            pendingClarification = bounded
        }
        trim(to: Self.maxStoredBytes)
    }
}
