import Foundation

/// Bounded, non-executable references for follow-ups. Financial values always require a fresh tool call.
nonisolated struct MarinaConversationMemory: Codable, Equatable, Sendable {
    static let currentVersion = 1
    // Persistence is distinct from the much smaller, explicitly bounded model context.
    static let maxStoredBytes = 32_768
    static let maxEntities = 12
    static let maxQueries = 6
    static let maxReferences = 24
    static let maxCompletedFrames = 12
    static let maxCompletedFrameBytes = 4_096
    static let maxPendingCompilationBytes = 8_192
    static let maxCompiledClarificationBytes = 24_576

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
        var categoryIDs: [String]? = nil
        var merchantName: String? = nil

        var isEmpty: Bool {
            cardID == nil && categoryID == nil && budgetID == nil && presetID == nil && accountID == nil && search == nil && merchantName == nil && (categoryIDs?.isEmpty ?? true)
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
        var metric: MarinaDataRequest.MetricFocus? = nil
        var chartIntent: MarinaDataRequest.ChartIntent? = nil
        var transactionFilter: MarinaDataRequest.TransactionFilter? = nil
        var availabilityFilter: MarinaDataRequest.AvailabilityFilter? = nil
        var compareLeaders: Bool? = nil
        var positiveOnly: Bool? = nil
        var periodBudgetID: String? = nil

        /// Compatibility reconstruction for conversations saved before completed frames.
        /// The caller must still validate every identity against fresh workspace data.
        var request: MarinaDataRequest {
            var request = MarinaDataRequest(operation: operation, tool: tool)
            request.purpose = purpose; request.metric = metric; request.chartIntent = chartIntent
            request.cardID = selection?.cardID; request.categoryID = selection?.categoryID
            request.categoryIDs = selection?.categoryIDs; request.budgetID = selection?.budgetID
            request.presetID = selection?.presetID; request.accountID = selection?.accountID
            request.search = selection?.search; request.merchantName = selection?.merchantName
            request.allTime = period.allTime ?? false; request.relativePeriod = period.relative
            request.startDate = period.startDate; request.endDate = period.endDate
            request.expenseMeasure = measure ?? .budgetImpact; request.scope = scope ?? .all
            request.state = state ?? .all; request.grouping = grouping ?? .none
            request.periodUnit = periodUnit; request.includeFuture = includeFuture ?? false
            request.recordKind = recordKind; request.sort = sort ?? .newest
            request.offset = offset ?? 0; request.limit = limit ?? 20
            request.transactionFilter = transactionFilter; request.availabilityFilter = availabilityFilter
            request.compareLeaders = compareLeaders; request.positiveOnly = positiveOnly
            request.periodBudgetID = periodBudgetID
            if let comparisonSelection {
                request.comparisonFilter = .init(cardID: comparisonSelection.cardID,
                    categoryID: comparisonSelection.categoryID, categoryIDs: comparisonSelection.categoryIDs,
                    budgetID: comparisonSelection.budgetID, presetID: comparisonSelection.presetID,
                    search: comparisonSelection.search, merchantName: comparisonSelection.merchantName)
            }
            request.comparisonAllTime = comparisonPeriod?.allTime ?? false
            request.comparisonPeriod = comparisonPeriod?.relative
            request.comparisonStartDate = comparisonPeriod?.startDate
            request.comparisonEndDate = comparisonPeriod?.endDate
            return request
        }
    }

    /// An app-committed request, not a tool attempt or a cached financial answer.
    /// The same metadata is attached to its HomeAnswer so old topics survive cache trimming.
    struct CompletedFrame: Codable, Equatable, Sendable {
        let reference: String
        let workspaceID: UUID
        let chatID: UUID
        let answerID: UUID
        let resultID: String?
        let request: MarinaDataRequest
        let prompt: String?
        let scopeLabel: String?
        var dateOrigin: MarinaRequestCompiler.DateOrigin? = nil
    }

    /// Semantic selection can inspect these descriptions without replaying any result values
    /// or accepting a raw database identity as model-generated authority.
    struct CompletedFrameDescriptor: Codable, Equatable, Sendable {
        let reference: String
        let prompt: String?
        let scope: String?
        let tool: MarinaDataRequest.Tool
        let operation: MarinaDataRequest.Operation
        let capability: MarinaCapability?
        let purpose: MarinaDataRequest.Purpose?
        let metric: MarinaDataRequest.MetricFocus?
        let measure: MarinaDataRequest.ExpenseMeasure?
        let grouping: MarinaDataRequest.Grouping?
        let dates: Period
        let comparison: Period?
        let chartIntent: MarinaDataRequest.ChartIntent?
        let expenseScope: MarinaDataRequest.Scope?
        let state: MarinaDataRequest.State?
        let transactionFilter: MarinaDataRequest.TransactionFilter?
        let availabilityFilter: MarinaDataRequest.AvailabilityFilter?

        init(_ frame: CompletedFrame, includesPrompt: Bool = true) {
            let request = frame.request
            reference = frame.reference; prompt = includesPrompt ? frame.prompt : nil
            scope = frame.scopeLabel; tool = request.tool; operation = request.operation
            capability = MarinaCapability.matching(request)
            purpose = request.purpose; metric = request.metric
            measure = request.tool == .expenses ? request.expenseMeasure : nil
            grouping = request.grouping == .none ? nil : request.grouping
            dates = Period(allTime: request.allTime ? true : nil, relative: request.relativePeriod,
                           startDate: request.startDate, endDate: request.endDate)
            comparison = request.comparisonAllTime || request.comparisonPeriod != nil
                || request.comparisonStartDate != nil || request.comparisonEndDate != nil
                ? Period(allTime: request.comparisonAllTime ? true : nil, relative: request.comparisonPeriod,
                    startDate: request.comparisonStartDate, endDate: request.comparisonEndDate) : nil
            chartIntent = request.chartIntent
            expenseScope = request.scope == .all ? nil : request.scope
            state = request.state == .all ? nil : request.state
            transactionFilter = request.transactionFilter; availabilityFilter = request.availabilityFilter
        }
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
        var reason: String? = nil
        var pendingRequest: MarinaDataRequest? = nil
        var selectedEntities: [Entity]? = nil
        var dateOrigin: MarinaRequestCompiler.DateOrigin? = nil
        var compilation: MarinaRequestCompiler.Compilation? = nil
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
    private(set) var completedFrames: [CompletedFrame]
    private var nextFrameNumber: Int

    var latestFinancialQuery: Query? { recentQueries.last { $0.tool != .findRecords } }
    var latestCompletedFrame: CompletedFrame? { completedFrames.last }

    init(workspaceID: UUID, chatID: UUID) {
        version = Self.currentVersion
        self.workspaceID = workspaceID
        self.chatID = chatID
        confirmedEntities = []
        recentQueries = []
        entityReferences = []
        nextReferenceNumber = 1
        completedFrames = []
        nextFrameNumber = 1
    }

    /// Called once the runtime has selected the answer and accepted its verified result.
    /// Exploratory reads still use record(); they never change the completed frame.
    @discardableResult
    mutating func commitCompletedFrame(request: MarinaDataRequest, result: MarinaDataResult,
                                      answerID: UUID, prompt: String? = nil,
                                      dateOrigin: MarinaRequestCompiler.DateOrigin? = nil) -> CompletedFrame? {
        guard ["success", "empty"].contains(result.status), request.tool != .findRecords,
              result.presentation?.pagination.map({ $0.workspaceID == workspaceID }) ?? true,
              result.presentation?.identityKey.map({ $0.hasPrefix(workspaceID.uuidString + ":") }) ?? true,
              !result.records.contains(where: { $0.kind == "workspace" && $0.id != workspaceID.uuidString }) else { return nil }
        var canonical = result.resolvedRequest ?? result.presentation?.pagination?.request ?? request
        canonical.operation = result.presentation?.operation ?? canonical.operation
        canonical.offset = 0
        canonical.forcePresentation = nil
        let existing = completedFrames.first { $0.answerID == answerID }
        guard existing != nil || nextFrameNumber < Int.max - 1 else { return nil }
        let reference = existing?.reference ?? "t\(nextFrameNumber)"
        let frame = CompletedFrame(reference: reference, workspaceID: workspaceID, chatID: chatID,
            answerID: answerID, resultID: Self.bounded(result.presentation?.id), request: canonical,
            prompt: Self.boundedPrompt(prompt) ?? existing?.prompt,
            scopeLabel: Self.boundedPrompt(result.presentation?.scopeLabel ?? result.scope),
            dateOrigin: dateOrigin ?? existing?.dateOrigin)
        guard validCompletedFrame(frame) else { return nil }
        if existing == nil { nextFrameNumber += 1 }
        completedFrames.removeAll { $0.answerID == answerID }
        completedFrames.append(frame)
        if completedFrames.count > Self.maxCompletedFrames {
            completedFrames.removeFirst(completedFrames.count - Self.maxCompletedFrames)
        }
        pendingClarification = nil
        trim(to: Self.maxStoredBytes)
        return frame
    }

    mutating func setPendingDateOrigin(_ origin: MarinaRequestCompiler.DateOrigin?) {
        pendingClarification?.dateOrigin = origin
    }

    /// Explicit topic changes discard only the unresolved question; completed frames remain available.
    mutating func discardPendingClarification() {
        pendingClarification = nil
    }

    /// The compiled path supplies the root question and verified lookup response directly;
    /// unknown names can therefore remain pending without a candidate or a lexical guess.
    /// Build and bound the complete replacement before publishing any memory mutation.
    @discardableResult
    mutating func saveCompiledClarification(compilation: MarinaRequestCompiler.Compilation,
                                           result: MarinaDataResult, answerID: UUID,
                                           prompt: String, search: String?) -> Bool {
        // Only compiled pending state is authoritative here. A legacy lookup callback
        // may have recorded the short reply as its prompt before this method runs.
        let originatingQuestion = pendingClarification?.compilation != nil
            ? pendingClarification?.originatingPrompt ?? prompt : prompt
        guard ["candidates", "empty", "needsPeriodChoice", "needsBudgetChoice", "needsClarification"].contains(result.status),
              Self.validPendingCompilation(compilation),
              let question = Self.boundedPrompt(originatingQuestion),
              Self.bounded(search) == search,
              result.totalCount >= result.records.count,
              result.nextOffset.map({ $0 >= 0 }) ?? true,
              result.presentation?.pagination.map({ $0.workspaceID == workspaceID }) ?? true,
              result.presentation?.identityKey.map({ $0.hasPrefix(workspaceID.uuidString + ":") }) ?? true,
              !result.records.contains(where: { $0.kind == "workspace" && $0.id != workspaceID.uuidString }) else { return false }
        let dateChoice = result.status == "needsPeriodChoice" || result.status == "needsBudgetChoice"
        let allCandidates: [Entity]
        if dateChoice {
            guard result.records.allSatisfy({ $0.kind == "budget" && Self.bounded($0.id) != nil && Self.bounded($0.title) != nil }) else { return false }
            let kind = result.status == "needsPeriodChoice" ? "periodBudget" : "budget"
            allCandidates = result.records.map { Entity(kind: kind, id: $0.id, name: $0.title) }
        } else {
            allCandidates = result.records.compactMap(Self.entity)
            guard allCandidates.count == result.records.count else { return false }
        }
        let candidates = Array(allCandidates.prefix(Self.maxEntities))
        let kinds = Set(candidates.map(\.kind))
        let request = compilation.request
        let period = Period(allTime: request.allTime ? true : nil, relative: request.relativePeriod,
                            startDate: request.startDate, endDate: request.endDate)
        let nextOffset: Int?
        if allCandidates.count > candidates.count {
            let offset = result.resolvedRequest?.offset ?? 0
            guard offset >= 0, offset <= Int.max - candidates.count else { return false }
            nextOffset = offset + candidates.count
        } else { nextOffset = result.nextOffset }
        let pending = Clarification(search: search,
            recordKind: dateChoice ? (result.status == "needsPeriodChoice" ? "periodBudget" : "budget")
                : kinds.count == 1 ? kinds.first : nil,
            candidates: candidates, totalCount: result.totalCount, nextOffset: nextOffset, answerID: answerID,
            originatingPrompt: question, period: period, reason: result.status, pendingRequest: request,
            dateOrigin: compilation.dateOrigin, compilation: compilation)
        guard (try? JSONEncoder().encode(pending).count).map({ $0 <= Self.maxCompiledClarificationBytes }) == true else { return false }
        var replacement = self
        replacement.pendingClarification = pending
        for candidate in candidates {
            guard !replacement.reference(for: candidate).isEmpty else { return false }
        }
        replacement.trim(to: Self.maxStoredBytes)
        guard replacement.pendingClarification == pending,
              (replacement.encoded()?.count ?? Int.max) <= Self.maxStoredBytes else { return false }
        self = replacement
        return true
    }

    @discardableResult
    mutating func setPendingCompilation(_ compilation: MarinaRequestCompiler.Compilation?) -> Bool {
        guard var pending = pendingClarification else { return false }
        if let compilation {
            guard Self.validPendingCompilation(compilation) else { return false }
            pending.pendingRequest = compilation.request
            pending.dateOrigin = compilation.dateOrigin
            let request = compilation.request
            if request.allTime || request.relativePeriod != nil || request.startDate != nil || request.endDate != nil {
                pending.period = Period(allTime: request.allTime ? true : nil, relative: request.relativePeriod,
                                        startDate: request.startDate, endDate: request.endDate)
            }
        }
        pending.compilation = compilation
        pendingClarification = pending
        trim(to: Self.maxStoredBytes)
        return pendingClarification?.compilation == compilation
    }

    /// History owns durable frames. The memory array is only a recent cache; restoring it
    /// also advances the sequence beyond every validated historic reference to avoid reuse.
    mutating func restoreCompletedFrames(from history: [HomeAnswer]) {
        let frames = completedFrames(in: history)
        if let largest = frames.compactMap({ Self.frameNumber($0.reference) }).max() {
            nextFrameNumber = max(nextFrameNumber, largest + 1)
        }
        completedFrames = Array(frames.suffix(Self.maxCompletedFrames))
        trim(to: Self.maxStoredBytes)
    }

    func completedFrame(reference: String, history: [HomeAnswer] = []) -> CompletedFrame? {
        completedFrames(in: history).first { $0.reference == reference }
    }

    func completedFrames(in history: [HomeAnswer]) -> [CompletedFrame] {
        var frames: [CompletedFrame] = []
        var conflictedReferences = Set<String>()
        for frame in history.compactMap({ answer -> CompletedFrame? in
            guard let frame = answer.completedFrame, frame.answerID == answer.id else { return nil }
            return frame
        }) + completedFrames {
            guard validCompletedFrame(frame), !conflictedReferences.contains(frame.reference) else { continue }
            if let index = frames.firstIndex(where: { $0.reference == frame.reference }) {
                guard frames[index].answerID == frame.answerID else {
                    frames.remove(at: index)
                    conflictedReferences.insert(frame.reference)
                    continue
                }
                frames[index] = frame
            } else if !frames.contains(where: { $0.answerID == frame.answerID }) {
                frames.append(frame)
            }
        }
        return frames
    }

    func completedFrameDescriptors(history: [HomeAnswer] = []) -> [CompletedFrameDescriptor] {
        completedFrames(in: history).map { CompletedFrameDescriptor($0) }
    }

    /// A bounded slice for one model step. Callers can select older descriptors for a
    /// separate retrieval step; no financial result payload is needed to recover a request.
    func completedFrameContext(maxBytes: Int, history: [HomeAnswer] = []) -> String {
        guard maxBytes > 0 else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var frames = completedFrames(in: history)
        while !frames.isEmpty {
            let descriptors = frames.map { CompletedFrameDescriptor($0) }
            if let data = try? encoder.encode(descriptors), data.count <= maxBytes {
                return String(decoding: data, as: UTF8.self)
            }
            if frames.count == 1,
               let data = try? encoder.encode([CompletedFrameDescriptor(frames[0], includesPrompt: false)]),
               data.count <= maxBytes {
                return String(decoding: data, as: UTF8.self)
            }
            frames.removeFirst()
        }
        return ""
    }

    private func validCompletedFrame(_ frame: CompletedFrame) -> Bool {
        frame.workspaceID == workspaceID && frame.chatID == chatID
            && Self.frameNumber(frame.reference) != nil && frame.request.tool != .findRecords
            && Self.canRememberQuery(frame.request)
            && [frame.request.periodBudgetID, frame.request.expectedRecordID, frame.resultID].compactMap { $0 }.allSatisfy { Self.bounded($0) != nil }
            && Self.boundedPrompt(frame.prompt) == frame.prompt
            && Self.boundedPrompt(frame.scopeLabel) == frame.scopeLabel
            && (try? JSONEncoder().encode(frame).count).map { $0 <= Self.maxCompletedFrameBytes } == true
    }

    private static func frameNumber(_ reference: String) -> Int? {
        guard reference.first == "t", reference.count > 1,
              reference.dropFirst().utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(reference.dropFirst()), number > 0, number < Int.max - 1,
              reference == "t\(number)" else { return nil }
        return number
    }

    private static func validPendingCompilation(_ compilation: MarinaRequestCompiler.Compilation) -> Bool {
        guard compilation.capability.tool == compilation.request.tool,
              canRememberQuery(compilation.request),
              compilation.unresolvedTargets.count <= maxEntities,
              Set(compilation.unresolvedTargets.map(\.id)).count == compilation.unresolvedTargets.count,
              compilation.unresolvedTargets.allSatisfy({ target in
                  guard bounded(target.id) != nil, bounded(target.name) != nil else { return false }
                  switch target.source {
                  case .userText(let text): return boundedPrompt(text) != nil
                  case .contextReference(let reference): return bounded(reference) != nil
                  }
              }) else { return false }
        return (try? JSONEncoder().encode(compilation).count).map { $0 <= maxPendingCompilationBytes } == true
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

    /// Pagination is a refresh of an existing visual, not an answer to a pending question.
    /// A bounded replacement preserves the entire unresolved intent and its reference IDs.
    @discardableResult
    mutating func recordUIRead(request: MarinaDataRequest, result: MarinaDataResult, answerID: UUID) -> Bool {
        guard ["success", "empty"].contains(result.status),
              result.presentation?.pagination.map({ $0.workspaceID == workspaceID }) ?? true,
              result.presentation?.identityKey.map({ $0.hasPrefix(workspaceID.uuidString + ":") }) ?? true,
              !result.records.contains(where: { $0.kind == "workspace" && $0.id != workspaceID.uuidString }) else { return false }
        guard let pending = pendingClarification else {
            record(request: request, result: result, answerID: answerID)
            return true
        }
        var preservedReferences = Set((pending.candidates + (pending.selectedEntities ?? [])).compactMap {
            reference(forKind: $0.kind, id: $0.id)
        })
        if let request = pending.pendingRequest {
            preservedReferences.formUnion(selectionReferences(Self.selection(request), tool: request.tool) ?? [])
            if let filter = request.comparisonFilter {
                let selection = Selection(cardID: filter.cardID, categoryID: filter.categoryID,
                    budgetID: filter.budgetID, presetID: filter.presetID, search: filter.search,
                    categoryIDs: filter.categoryIDs, merchantName: filter.merchantName)
                preservedReferences.formUnion(selectionReferences(selection, tool: request.tool) ?? [])
            }
        }
        for target in pending.compilation?.unresolvedTargets ?? [] {
            if case .contextReference(let reference) = target.source { preservedReferences.insert(reference) }
        }
        let retainedEntries = entityReferences.filter { preservedReferences.contains($0.reference) }
        var replacement = self
        replacement.record(request: request, result: result, answerID: answerID)
        let refreshed = replacement.recentQueries.last { $0.answerID == answerID && $0.resultID == result.presentation?.id }
        // Keep the active query in place when paging an older report. Update only the
        // already-known report's pagination metadata; no new question has been asked.
        replacement.recentQueries = recentQueries.map { original in
            if let refreshed, original.answerID == refreshed.answerID,
               original.resultID == refreshed.resultID, original.tool == refreshed.tool { return refreshed }
            return original
        }
        replacement.pendingClarification = pending
        for entry in retainedEntries {
            replacement.entityReferences.removeAll {
                $0.reference == entry.reference || ($0.entity.kind == entry.entity.kind && $0.entity.id == entry.entity.id)
            }
            replacement.entityReferences.append(entry)
        }
        while replacement.entityReferences.count > Self.maxReferences { replacement.discardOldestReference() }
        replacement.trim(to: Self.maxStoredBytes)
        guard replacement.pendingClarification == pending,
              retainedEntries.allSatisfy({ replacement.entity(forReference: $0.reference) == $0.entity }),
              (replacement.encoded()?.count ?? Int.max) <= Self.maxStoredBytes else { return false }
        self = replacement
        return true
    }

    /// Call only with the result of the workspace-bound, validating data service.
    mutating func record(request: MarinaDataRequest, result: MarinaDataResult, answerID: UUID, prompt: String? = nil) {
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(result.status) {
            let kind = result.status == "needsPeriodChoice" ? "periodBudget" : "budget"
            let candidates = result.records.map { Entity(kind: kind, id: $0.id, name: $0.title) }
            for candidate in candidates.prefix(Self.maxEntities) { _ = reference(for: candidate) }
            pendingClarification = Clarification(search: nil, recordKind: kind,
                candidates: Array(candidates.prefix(Self.maxEntities)), totalCount: result.totalCount,
                nextOffset: result.nextOffset, answerID: answerID, originatingPrompt: Self.boundedPrompt(prompt),
                reason: result.status, pendingRequest: result.resolvedRequest ?? request)
            trim(to: Self.maxStoredBytes)
            return
        }
        if let request = result.pendingRequest, var pending = pendingClarification {
            pending.pendingRequest = request
            pendingClarification = pending
        }
        guard ["success", "empty", "candidates"].contains(result.status),
              result.presentation?.pagination.map({ $0.workspaceID == workspaceID }) ?? true else { return }
        if let returnedWorkspace = result.records.first(where: { $0.kind == "workspace" }),
           returnedWorkspace.id != workspaceID.uuidString { return }

        let entities = result.records.compactMap(Self.entity)
        if request.tool == .findRecords && result.status == "candidates" {
            // Candidates are deliberately separate from confirmed entities. Never guess a selection.
            let retainedCandidates = Array(entities.prefix(Self.maxEntities))
            let previous = pendingClarification.flatMap { pending in
                let policy = MarinaTurnPolicy(prompt: prompt ?? "")
                let narrowsCandidates = !entities.isEmpty && entities.allSatisfy { entity in pending.candidates.contains(entity) }
                    && request.search.map { search in pending.candidates.contains {
                        MarinaNamedTargetRequirement.containsLiteralName(search, in: $0.name)
                    } } == true
                let sameSearch = pending.search?.compare(request.search ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                return (narrowsCandidates || sameSearch) && !policy.isExplicitFinancialQuestion ? pending : nil
            }
            let period = Self.clarificationPeriod(request: request, result: result, prompt: prompt, previous: previous?.period, isNewQuestion: previous == nil)
            pendingClarification = Clarification(
                search: Self.bounded(request.search), recordKind: Self.bounded(request.recordKind),
                candidates: retainedCandidates, totalCount: result.totalCount,
                nextOffset: result.nextOffset, answerID: answerID,
                originatingPrompt: previous?.originatingPrompt ?? Self.boundedPrompt(prompt), period: period,
                pendingRequest: result.pendingRequest ?? previous?.pendingRequest,
                dateOrigin: previous?.dateOrigin, compilation: previous?.compilation
            )
            for entity in retainedCandidates { _ = reference(for: entity) }
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
            if request.tool == .findRecords, request.exactRecordName == true, result.status == "success", entities.count == 1,
               var pending = pendingClarification {
                pending.selectedEntities = entities
                pendingClarification = pending
            }
            if matchingCandidateLookup, var pending = pendingClarification {
                // Resolving a name is not yet the financial answer. Keep its intent across a
                // cancellation or failure between lookup and the validated financial read.
                pending.period = Self.clarificationPeriod(request: request, result: result, prompt: prompt, previous: pending.period)
                pendingClarification = pending
            } else if (result.status == "success" || result.status == "empty")
                && !(request.tool == .findRecords && pendingClarification != nil
                    && (pendingClarification?.answerID == answerID || !MarinaTurnPolicy(prompt: prompt ?? "").isExplicitFinancialQuestion)) {
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
                      search: Self.bounded($0.search), categoryIDs: $0.categoryIDs, merchantName: Self.bounded($0.merchantName))
        }
        let hasComparison = effective.comparisonAllTime || effective.comparisonPeriod != nil
            || effective.comparisonStartDate != nil || effective.comparisonEndDate != nil || comparison != nil
        let operation = result.presentation?.operation ?? effective.operation
        registerSelection(selection, tool: effective.tool, scope: effective.scope)
        if let comparison { registerSelection(comparison, tool: effective.tool, scope: effective.scope) }
        let isList = effective.tool == .findRecords || effective.tool == .accounts
            || [.transactions, .inventory, .ranking, .share, .trend].contains(operation)
        recentQueries.removeAll { $0.answerID == answerID && $0.resultID == result.presentation?.id && $0.tool == effective.tool }
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
            answerID: answerID, resultID: Self.bounded(result.presentation?.id),
            metric: effective.metric, chartIntent: effective.chartIntent, transactionFilter: effective.transactionFilter,
            availabilityFilter: effective.availabilityFilter, compareLeaders: effective.compareLeaders,
            positiveOnly: effective.positiveOnly, periodBudgetID: effective.periodBudgetID
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
            case "category": return selection.categoryID == candidate.id || selection.categoryIDs?.contains(candidate.id) == true
            case "budget": return selection.budgetID == candidate.id
            case "periodBudget": return request.periodBudgetID == candidate.id
            case "preset": return selection.presetID == candidate.id
            case "savingsAccount", "reconciliationAccount": return selection.accountID == candidate.id
            case "merchant": return request.tool == .expenses && selection.merchantName == candidate.name
            case "incomeSource": return request.tool == .income && selection.search == candidate.name
            default: return false
            }
        }
    }

    private static func canRememberQuery(_ request: MarinaDataRequest) -> Bool {
        let text = [request.cardID, request.categoryID, request.budgetID, request.presetID,
                    request.accountID, request.search, request.merchantName, request.startDate, request.endDate, request.recordKind,
                    request.comparisonStartDate, request.comparisonEndDate, request.comparisonFilter?.cardID,
                    request.comparisonFilter?.categoryID, request.comparisonFilter?.budgetID,
                    request.comparisonFilter?.presetID, request.comparisonFilter?.search, request.comparisonFilter?.merchantName]
        return (text.compactMap { $0 } + (request.categoryIDs ?? []) + (request.comparisonFilter?.categoryIDs ?? [])).allSatisfy { bounded($0) != nil }
    }

    private static func selection(_ request: MarinaDataRequest) -> Selection {
        Selection(cardID: bounded(request.cardID), categoryID: bounded(request.categoryID),
                  budgetID: bounded(request.budgetID), presetID: bounded(request.presetID),
                  accountID: bounded(request.accountID), search: bounded(request.search), categoryIDs: request.categoryIDs, merchantName: bounded(request.merchantName))
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
                                            prompt: String?, previous: Period?, isNewQuestion: Bool = false) -> Period? {
        switch MarinaTurnPolicy(prompt: prompt ?? "").periodCue {
        case .none:
            guard isNewQuestion else { return previous }
            return previous ?? result.resolvedRequest.flatMap {
            guard $0.search == request.search else { return nil }
            return Period(allTime: $0.allTime ? true : nil, relative: $0.relativePeriod, startDate: $0.startDate, endDate: $0.endDate)
        }
        case .other:
            guard request.startDate != nil || request.endDate != nil || request.allTime else { return nil }
            let resolved = result.resolvedRequest ?? request
            return Period(allTime: resolved.allTime ? true : nil, relative: nil, startDate: resolved.startDate, endDate: resolved.endDate)
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
        for id in selection.categoryIDs ?? [] where reference(forKind: "category", id: id) == nil {
            _ = reference(for: Entity(kind: "category", id: id, name: "category"))
        }
        if let name = selection.merchantName ?? selection.search, tool == .expenses || tool == .income {
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
            (tool == .income ? "incomeSource" : "merchant", selection.merchantName ?? selection.search)]
        for (kind, id) in namedIDs {
            guard let id else { continue }
            guard let reference = reference(forKind: kind, id: id) else { return nil }
            references.append(reference)
        }
        for id in selection.categoryIDs ?? [] {
            guard let reference = reference(forKind: "category", id: id) else { return nil }
            if !references.contains(reference) { references.append(reference) }
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
        var protected = Set(((pendingClarification?.candidates ?? []) + (pendingClarification?.selectedEntities ?? [])).compactMap {
            reference(forKind: $0.kind, id: $0.id)
        })
        if let request = pendingClarification?.pendingRequest {
            protected.formUnion(selectionReferences(Self.selection(request), tool: request.tool) ?? [])
            if let filter = request.comparisonFilter {
                let selection = Selection(cardID: filter.cardID, categoryID: filter.categoryID,
                    budgetID: filter.budgetID, presetID: filter.presetID, search: filter.search,
                    categoryIDs: filter.categoryIDs, merchantName: filter.merchantName)
                protected.formUnion(selectionReferences(selection, tool: request.tool) ?? [])
            }
        }
        for target in pendingClarification?.compilation?.unresolvedTargets ?? [] {
            if case .contextReference(let reference) = target.source { protected.insert(reference) }
        }
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
            else if !forModel && completedFrames.count > 1 { completedFrames.removeFirst() }
            else if !confirmedEntities.isEmpty { confirmedEntities.removeFirst() }
            else if let pending = pendingClarification, pending.candidates.count > 1 {
                pendingClarification = Clarification(search: pending.search, recordKind: pending.recordKind,
                    candidates: Array(pending.candidates.dropLast()), totalCount: pending.totalCount,
                    nextOffset: pending.nextOffset, answerID: pending.answerID, originatingPrompt: pending.originatingPrompt, period: pending.period, reason: pending.reason, pendingRequest: pending.pendingRequest, selectedEntities: pending.selectedEntities, dateOrigin: pending.dateOrigin, compilation: pending.compilation)
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
                    nextOffset: pending.nextOffset, answerID: pending.answerID, originatingPrompt: pending.originatingPrompt, period: pending.period, reason: pending.reason, pendingRequest: pending.pendingRequest, selectedEntities: pending.selectedEntities, dateOrigin: pending.dateOrigin, compilation: pending.compilation)
            }
            else if !forModel && !entityReferences.isEmpty { discardOldestReference() }
            else if !recentQueries.isEmpty { recentQueries.removeFirst() }
            else if pendingClarification != nil { pendingClarification = nil }
            else if !forModel && !completedFrames.isEmpty { completedFrames.removeFirst() }
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
            let selected: [ModelEntity]?
            let totalCount: Int
            let nextOffset: Int?
            let originatingPrompt: String?
            let dates: ModelDates?
            let reason: String?
            let pendingTool: MarinaDataRequest.Tool?
            let pendingOperation: MarinaDataRequest.Operation?
            let pendingPurpose: MarinaDataRequest.Purpose?
            let pendingMetric: MarinaDataRequest.MetricFocus?
            init(_ clarification: Clarification, memory: MarinaConversationMemory) {
                search = clarification.search
                recordKind = clarification.recordKind
                candidates = clarification.candidates.map { ModelEntity($0, memory: memory) }
                selected = clarification.selectedEntities?.map { ModelEntity($0, memory: memory) }
                totalCount = clarification.totalCount
                nextOffset = clarification.nextOffset
                originatingPrompt = clarification.originatingPrompt
                dates = clarification.period.flatMap(ModelDates.init)
                reason = clarification.reason
                pendingTool = clarification.pendingRequest?.tool
                pendingOperation = clarification.pendingRequest?.operation
                pendingPurpose = clarification.pendingRequest?.purpose
                pendingMetric = clarification.pendingRequest?.metric
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
                case metric, chartIntent, transactionFilter, status, leadersBy
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
                    try values.encode([operation: ModelComparison(
                        selection: comparisonSelection ?? selection ?? .previous,
                        dates: query.comparisonPeriod.flatMap(ModelDates.init))], forKey: .operation)
                } else if query.tool == .expenses {
                    try values.encode(expenseOperation, forKey: .operation)
                } else {
                    let purposeOperations: [MarinaDataRequest.Purpose: String] = [
                        .incomeProgress: "progress", .incomeTimeline: "timeline", .budgetPace: "pace",
                        .budgetDetails: "details", .categoryAvailability: "categoryAvailability",
                        .savingsOutlook: "savingsOutlook", .savingsTimeline: "savingsTimeline",
                        .budgetCards: "linkedCards", .budgetPresets: "linkedPresets"]
                    let operation = query.purpose.flatMap { purposeOperations[$0] }
                        ?? (query.tool == .budgetSummary && query.periodUnit == nil ? "overview" : query.operation.rawValue)
                    try values.encode(operation, forKey: .operation)
                    if query.purpose != .incomeProgress && query.purpose != .budgetPace {
                        try values.encodeIfPresent(query.purpose, forKey: .purpose)
                    }
                    if query.tool == .findRecords { try values.encodeIfPresent(query.selection?.search, forKey: .search) }
                    if query.tool != .income { try values.encodeIfPresent(comparisonSelection, forKey: .comparisonSelection) }
                }
                try values.encodeIfPresent(ModelDates(query.period), forKey: .dates)
                try values.encodeIfPresent(query.metric, forKey: .metric)
                try values.encodeIfPresent(query.chartIntent, forKey: .chartIntent)
                try values.encodeIfPresent(query.transactionFilter, forKey: .transactionFilter)
                try values.encodeIfPresent(query.availabilityFilter, forKey: .status)
                if query.compareLeaders == true { try values.encodeIfPresent(query.grouping, forKey: .leadersBy) }
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
                if let purpose = query.purpose, [.upcomingPresets, .cardSummary, .nextPlannedExpense, .spendingPatterns].contains(purpose) { return purpose.rawValue }
                switch query.operation {
                case .transactions where query.sort == .largest && query.limit == 1: return "largestPurchase"
                case .transactions where query.sort == .smallest && query.limit == 1: return "smallestPurchase"
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
        case completedFrames, nextFrameNumber
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
        if let pending = pendingClarification, let compilation = pending.compilation {
            guard Self.validPendingCompilation(compilation),
                  (try? JSONEncoder().encode(pending).count).map({ $0 <= Self.maxCompiledClarificationBytes }) == true else {
                throw DecodingError.dataCorruptedError(forKey: .pendingClarification, in: values,
                                                       debugDescription: "Invalid pending request compilation")
            }
        }
        entityReferences = try values.decodeIfPresent([EntityReference].self, forKey: .entityReferences) ?? []
        completedFrames = try values.decodeIfPresent([CompletedFrame].self, forKey: .completedFrames) ?? []
        nextFrameNumber = try values.decodeIfPresent(Int.self, forKey: .nextFrameNumber) ?? 1
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
        guard completedFrames.count <= Self.maxCompletedFrames,
              Set(completedFrames.map(\.reference)).count == completedFrames.count,
              Set(completedFrames.map(\.answerID)).count == completedFrames.count,
              completedFrames.allSatisfy(validCompletedFrame),
              nextFrameNumber > 0, nextFrameNumber < Int.max else {
            throw DecodingError.dataCorruptedError(forKey: .completedFrames, in: values,
                                                   debugDescription: "Invalid completed request frames")
        }
        if let largest = completedFrames.compactMap({ Self.frameNumber($0.reference) }).max() {
            nextFrameNumber = max(nextFrameNumber, largest + 1)
        }
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
