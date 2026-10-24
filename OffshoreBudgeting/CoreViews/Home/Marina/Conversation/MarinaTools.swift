import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Serializes SwiftData access on the main actor, even when the model calls tools concurrently.
@available(iOS 26.0, macCatalyst 26.0, *)
@MainActor
final class MarinaToolBridge {
#if DEBUG
    var diagnostics: MarinaTokenDiagnostics?
#endif
    private var service: MarinaReadOnlyDataService?
    private var onResult: (() -> Void)?
    var onStatus: ((MarinaResponseState) -> Void)?
    var onValidatedResult: ((MarinaDataRequest, MarinaDataResult) -> Void)?
    var haltOnClarification = false
    var requiresFreshRead = false
    private var results: [MarinaDataResult] = []
    private var evidence: [(tool: MarinaDataRequest.Tool, verified: Bool, answer: HomeAnswer)] = []
    private var previousPresentations: [MarinaPresentation] = []
    private var calls = 0
    var conversationMemory: (() -> MarinaConversationMemory?)?
    private var turnMemory: MarinaConversationMemory?
    private var pendingCandidates: [MarinaConversationMemory.Entity] = []
    private var clarificationCandidates: [MarinaConversationMemory.Entity] = []
    private var clarificationPeriod: MarinaConversationMemory.Period?
    private var clarificationOriginatingPrompt: String?
    private var clarificationSearch: String?
    private var cachedNamedTargetRequirements: [MarinaNamedTargetRequirement]?
    private var ambiguityDiscoveredThisTurn = false
    private var namedLookupTargets: [MarinaConversationMemory.Entity] = []
    private var memory: MarinaConversationMemory? { conversationMemory?() ?? turnMemory }
    private var argumentIssue: String?
    private var failedFinancialTool: MarinaDataRequest.Tool?
    private var invalidReferenceTools: Set<MarinaDataRequest.Tool> = []
    private var repairableUnknownReferenceTools: Set<MarinaDataRequest.Tool> = []
    private var unresolvedLookup: (name: String, kind: String?)?
    private var turnPrompt = ""
    private var turnPolicy = MarinaTurnPolicy(prompt: "")
    private(set) var requests: [MarinaDataRequest] = []
    var hasResults: Bool { !results.isEmpty }
    var hasFinancialResults: Bool { evidence.contains { $0.tool != .findRecords && $0.verified } }
    var hasGroundedAnswer: Bool {
        hasFinancialResults || zip(requests, results).contains { request, result in
            request.tool == .findRecords && request.search != nil
                && (result.status == "candidates" || result.status == "empty")
        }
    }
    var hasInvalidRequest: Bool { argumentIssue != nil || results.last?.status == "invalidRequest" }

    /// Generated arguments can fail before a tool body can return validation feedback.
    /// Only our explicit argument errors are eligible for the runtime's bounded repair.
    nonisolated static func argumentErrorFeedback(_ error: any Error) -> String? {
        if let argumentError = error as? MarinaToolArgumentError { return argumentError.message }
        guard let callError = error as? LanguageModelSession.ToolCallError,
              let argumentError = callError.underlyingError as? MarinaToolArgumentError else { return nil }
        return argumentError.message
    }

    func begin(service: MarinaReadOnlyDataService, history: [HomeAnswer] = [], prompt: String = "", memory: MarinaConversationMemory? = nil, onResult: @escaping () -> Void) {
        previousPresentations = MarinaPresentationDisplayPolicy.previousResults(in: history)
        self.service = service
        self.onResult = onResult
        results = []
        evidence = []
        requests = []
        calls = 0
        turnMemory = memory
        turnPrompt = prompt
        turnPolicy = MarinaTurnPolicy(prompt: prompt)
        pendingCandidates = memory?.pendingClarification?.candidates ?? []
        clarificationCandidates = pendingCandidates
        clarificationPeriod = memory?.pendingClarification?.period
        clarificationOriginatingPrompt = memory?.pendingClarification?.originatingPrompt
        clarificationSearch = memory?.pendingClarification?.search
        cachedNamedTargetRequirements = nil
        ambiguityDiscoveredThisTurn = false
        namedLookupTargets = []
        argumentIssue = nil
        failedFinancialTool = nil
        invalidReferenceTools = []
        repairableUnknownReferenceTools = []
        unresolvedLookup = nil
    }

    func end() { service = nil; onResult = nil; onStatus = nil; onValidatedResult = nil }

    func call(_ request: MarinaDataRequest, diagnosticAttempt: Int? = nil) throws -> String {
        var request = turnPolicy.constrained(request)
        if let original = clarificationOriginatingPrompt,
           turnPolicy.explicitlyChangesFinancialTopic(from: original, to: request.tool) {
            pendingCandidates = []
            clarificationCandidates = []
            clarificationPeriod = nil
            clarificationOriginatingPrompt = nil
            clarificationSearch = nil
            ambiguityDiscoveredThisTurn = false
        }
        if turnPolicy.isContextualFinancialFollowUp,
           namedLookupTargets.isEmpty, pendingCandidates.isEmpty, unresolvedLookup == nil,
           !invalidReferenceTools.contains(request.tool),
           request.operation != .comparison, request.comparisonFilter == nil,
           request.comparisonPeriod == nil, request.comparisonStartDate == nil,
           request.comparisonEndDate == nil, !request.comparisonAllTime,
           let previous = memory?.latestFinancialQuery, previous.tool == request.tool {
            // A generic continuation retains the latest validated target, including workspace.
            // A reference to an older topic must not silently replace that target.
            request.cardID = previous.selection?.cardID
            request.categoryID = previous.selection?.categoryID
            request.budgetID = previous.selection?.budgetID
            request.presetID = previous.selection?.presetID
            request.accountID = previous.selection?.accountID
            request.search = previous.selection?.search
            if request.tool == .accounts { request.scope = previous.scope ?? .all }
        }
        let ignoredLookup = turnPolicy.ignoresNamedLookup(request)
        let scopeViolation = ignoredLookup ? nil : turnPolicy.violation(for: request)
        if request.tool == .findRecords, request.search != nil,
           case .relative(let period) = turnPolicy.periodCue {
            request.relativePeriod = period
            request.startDate = nil; request.endDate = nil; request.allTime = false
        }
        if request.tool != .findRecords,
           clarificationCandidates.contains(where: { includes($0, in: request) }) {
            switch turnPolicy.periodCue {
            case .none:
                if clarificationOriginatingPrompt.map({ turnPolicy.shouldRetainPendingPeriod(from: $0) }) ?? true,
                   let period = clarificationPeriod {
                    request.relativePeriod = period.relative
                    request.startDate = period.startDate; request.endDate = period.endDate
                    request.allTime = period.allTime == true
                }
            case .relative(let period):
                request.relativePeriod = period
                request.startDate = nil; request.endDate = nil; request.allTime = false
            case .other: break
            }
        }
        if request.tool == .findRecords, let proposed = request.search {
            request.search = turnPolicy.lookupSearch(proposed: proposed)
        }
        if request.tool == .findRecords, request.search != nil, let kind = request.recordKind,
           !turnPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !turnPolicy.confirms(kind: kind) {
            // A model-chosen kind must not hide candidates when the person supplied only a name.
            request.recordKind = nil
        }
#if DEBUG
        if let diagnosticAttempt { diagnostics?.mapped(attempt: diagnosticAttempt, request: request) }
        var diagnosticOutput: String?
        var diagnosticStatus = "needsClarification"
        defer {
            if let diagnosticAttempt, let diagnosticOutput {
                diagnostics?.output(attempt: diagnosticAttempt, text: diagnosticOutput, status: diagnosticStatus)
            }
        }
#endif
        try Task.checkCancellation()
        guard let service else { throw CancellationError() }
        calls += 1
        guard calls <= 8 else { throw ToolLimitError() }
        if request.tool == .findRecords, let search = request.search,
           let correction = protocolLookupCorrection(search) {
            return try invalidArguments(.init(message: correction), diagnosticAttempt: diagnosticAttempt,
                                        alreadyCounted: true, tool: .findRecords)
        }
        if requiresFreshRead, request.tool == .findRecords, let search = request.search,
           !ignoredLookup, !lookupNameIsGrounded(search) {
            return try invalidArguments(.init(message: "That lookup name was not supplied in this question or its relevant context. Look up only the user's literal target name. Use workspace for unnamed totals or previous for contextual follow-ups; do not invent a name."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: .findRecords)
        }
        if turnPolicy.requiresPeriodComparison, [.expenses, .income].contains(request.tool),
           request.operation != .comparison {
            let comparison = request.tool == .income ? "compareIncome" : "compare"
            return try invalidArguments(.init(message: "The user requested a calculated comparison. Use operation \"\(comparison)\" and comparison {\"selection\":\"workspace\",\"dates\":\"previousMonth\"}, replacing the example selection/dates with the requested other side. Top-level selection/dates identify the first side. Do not use separate reads or switch to a budget tool."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
        }
        if ignoredLookup {
            let output = "{\"status\":\"scopeAlreadyResolved\",\"explanation\":\"This generic term or all-records scope does not require a named lookup. Call the financial tool: workspace for an unfiltered or all-records question, previous for a contextual follow-up. Preserve explicitly named filters.\"}"
#if DEBUG
            diagnosticStatus = "scopeAlreadyResolved"
            diagnosticOutput = output
#endif
            return output
        }
        if let scopeViolation {
            return try invalidArguments(.init(message: scopeViolation), diagnosticAttempt: diagnosticAttempt,
                                        alreadyCounted: true, tool: request.tool == .findRecords ? nil : request.tool)
        }
        let requiredCandidates = pendingCandidates.filter { !turnPolicy.ignoresSelection(kind: $0.kind, for: request) }
        let requiredTargets = namedLookupTargets.filter { !turnPolicy.ignoresSelection(kind: $0.kind, for: request) }
        let lacksExplicitChoice = !ambiguityDiscoveredThisTurn && clarificationCandidates.contains { candidate in
            !turnPolicy.ignoresSelection(kind: candidate.kind, for: request) && includes(candidate, in: request)
                && !turnPolicy.confirmsPendingCandidate(kind: candidate.kind, name: candidate.name,
                    candidates: clarificationCandidates.map { (kind: $0.kind, name: $0.name) },
                    ambiguousSearch: clarificationSearch)
        }
        if request.tool != .findRecords,
           (ambiguityDiscoveredThisTurn && !requiredCandidates.isEmpty)
            || (!requiredCandidates.isEmpty && !requiredCandidates.contains(where: { includes($0, in: request) }))
            || lacksExplicitChoice {
            let output = "{\"status\":\"needsClarification\",\"explanation\":\"A lookup found competing records. Ask the person which candidate they mean before reading financial data.\"}"
#if DEBUG
            diagnosticOutput = output
#endif
            return output
        }
        if request.tool != .findRecords, let unresolvedLookup {
            return try invalidArguments(.init(message: "No matching record was found for \(unresolvedLookup.name). Resolve that target before reading financial data; do not replace it with workspace."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
        }
        if request.tool != .findRecords, !requiredTargets.isEmpty,
           !requiredTargets.contains(where: { Self.accepts(kind: $0.kind, tool: request.tool) }) {
            return try invalidArguments(.init(message: "The resolved target is not valid for \(request.tool.rawValue). Use the financial tool matching its record kind."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true)
        }
        if request.tool != .findRecords,
           let target = requiredTargets.first(where: { Self.accepts(kind: $0.kind, tool: request.tool) && !includes($0, in: request) }) {
            let ref = memory?.reference(forKind: target.kind, id: target.id)
            let detail = ref.map { "Use selection \"\($0)\" for \(target.name)." } ?? "Resolve \(target.name) again."
            return try invalidArguments(.init(message: "The named target was omitted. \(detail) Never replace a resolved target with workspace."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
        }
        if request.tool != .findRecords {
            let requirements = try currentNamedTargetRequirements()
            if let ambiguous = requirements.first(where: \.isAmbiguous) {
                return try invalidArguments(.init(message: "The current name \(ambiguous.search) matches competing records. Call findRecords to resolve that exact name and ask which record the person means; an earlier reference does not resolve this ambiguity."),
                                            diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
            }
            if let missing = requirements.first(where: { !$0.includes(in: request) }) {
                let kind = missing.recordKind.map { " with kind \($0)" } ?? ""
                return try invalidArguments(.init(message: "The current question names \(missing.search). Resolve that name\(kind) using findRecords and include its selection; do not substitute an earlier target or workspace."),
                                            diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
            }
            if request.tool == .expenses, request.operation != .comparison,
               turnPolicy.isExplicitFinancialQuestion, request.cardID != nil,
               !turnPolicy.confirms(kind: "card"),
               !requirements.contains(where: { $0.candidates.contains { $0.kind == "card" } }),
               let category = requirements.first(where: { $0.recordKind == "category" }) {
                let reference = category.candidates.first.flatMap { memory?.reference(forKind: $0.kind, id: $0.id) }
                let hint = reference.map { " Use selection \"\($0)\"." } ?? ""
                return try invalidArguments(.init(message: "This question selects the category \(category.search) without a card filter. Remove the earlier card selection.\(hint)"),
                                            diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
            }
        }
        let status: MarinaResponseState
        switch request.tool {
        case .findRecords: status = .readingRecords
        case .expenses: status = .readingExpenses
        case .income: status = .readingIncome
        case .budgetSummary: status = .readingBudget
        case .accounts: status = .readingAccounts
        }
        onStatus?(status)
        requests.append(request)
#if DEBUG
        if let diagnosticAttempt { diagnostics?.database(attempt: diagnosticAttempt) }
#endif
        let result = try service.execute(request)
        turnMemory?.record(request: request, result: result, answerID: UUID(), prompt: turnPrompt)
        onValidatedResult?(request, result)
        if result.status == "invalidRequest" {
            argumentIssue = result.explanation ?? "The requested data could not be read."
            if request.tool != .findRecords {
                failedFinancialTool = request.tool
                if request.cardID != nil || request.categoryID != nil || request.budgetID != nil
                    || request.presetID != nil || request.accountID != nil || request.search != nil
                    || request.comparisonFilter != nil {
                    invalidReferenceTools.insert(request.tool)
                    repairableUnknownReferenceTools.remove(request.tool)
                }
            }
        }
        if request.tool != .findRecords && ["success", "empty"].contains(result.status) {
            invalidReferenceTools.remove(request.tool)
            repairableUnknownReferenceTools.remove(request.tool)
            let answersSoleRequestedTopic = turnPolicy.acceptsCorrectedFinancialTool(request.tool)
                || (turnPolicy.requiresBudgetPace && request.tool == .budgetSummary && request.purpose == .budgetPace)
            if failedFinancialTool == nil || failedFinancialTool == request.tool || answersSoleRequestedTopic {
                // A verified answer to the sole requested topic supersedes an accidental
                // wrong-tool argument attempt. Other tools' reference guards remain intact.
                argumentIssue = nil
                failedFinancialTool = nil
            }
            pendingCandidates = []
            clarificationCandidates = []
            clarificationPeriod = nil
            clarificationOriginatingPrompt = nil
            clarificationSearch = nil
            namedLookupTargets = []
        }
#if DEBUG
        diagnosticStatus = result.status
#endif
        results.append(result)
        if request.tool == .findRecords {
            let entities = result.records.map { MarinaConversationMemory.Entity(kind: $0.kind, id: $0.id, name: $0.title) }
            if let search = request.search, result.status == "empty" {
                unresolvedLookup = (search, request.recordKind)
                // A verified missing name is a safe clarification, even after bad arguments.
                // The unresolved-name and invalid-reference gates still prevent broad fallback.
                argumentIssue = nil
                failedFinancialTool = nil
            }
            if result.status == "candidates" {
                argumentIssue = nil
                failedFinancialTool = nil
                let repeatedPending = !pendingCandidates.isEmpty && entities.allSatisfy { pendingCandidates.contains($0) }
                if !repeatedPending { ambiguityDiscoveredThisTurn = true }
                pendingCandidates = entities
            } else if request.search != nil && result.status == "success" && result.totalCount == 1, let entity = entities.first {
                if let unresolved = unresolvedLookup,
                   (unresolved.kind == nil || unresolved.kind == entity.kind),
                   unresolved.name.compare(request.search ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                    unresolvedLookup = nil
                }
                if entity.kind != "workspace" {
                    namedLookupTargets.removeAll { $0.kind == entity.kind && $0.id == entity.id }
                    namedLookupTargets.append(entity)
                }
                if !ambiguityDiscoveredThisTurn {
                    pendingCandidates = []
                    if !clarificationCandidates.contains(entity) {
                        clarificationCandidates = []
                        clarificationPeriod = nil
                        clarificationOriginatingPrompt = nil
                        clarificationSearch = nil
                    }
                }
            }
        }
        let card = result.homeAnswer
        let verified = result.status == "success" || result.status == "empty"
        let notice = !verified ? result.explanation.map { [HomeAnswerRow(title: $0, value: "", role: .assumption)] } ?? [] : []
        evidence.append((request.tool, verified, HomeAnswer(queryID: card.queryID, kind: card.kind,
            title: card.title, subtitle: card.subtitle,
            rows: [HomeAnswerRow(title: result.scope, value: "", role: .assumption)] + notice + card.rows,
            explanation: card.explanation)))
        onResult?()
        onStatus?(.responding)
        let display = result.presentation.map {
            MarinaPresentationDisplayPolicy.shouldShow($0, after: previousPresentations + results.dropLast().compactMap(\.presentation)) ? "displayed" : "alreadyShown"
        } ?? "none"
        // Presentation metadata describes app behavior; it never chooses or changes the query.
        let currentMemory = memory
        let modelFacts = result.modelFactsJSON(for: request) { kind, id in
            currentMemory?.reference(forKind: kind, id: id)
        }
        var facts = (try? JSONSerialization.jsonObject(with: Data(modelFacts.utf8))) as? [String: Any] ?? [:]
        facts["visualPresentation"] = display
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
#if DEBUG
            diagnosticOutput = json
#endif
            if haltOnClarification && request.tool == .findRecords
                && (result.status == "candidates" || (request.search != nil && result.status == "empty")) {
                throw MarinaClarificationRequired()
            }
            return json
        }
#if DEBUG
        diagnosticOutput = modelFacts
#endif
        if haltOnClarification && request.tool == .findRecords
            && (result.status == "candidates" || (request.search != nil && result.status == "empty")) {
            throw MarinaClarificationRequired()
        }
        return modelFacts
    }

    private func lookupNameIsGrounded(_ name: String) -> Bool {
        guard !turnPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        if MarinaNamedTargetRequirement.containsLiteralName(name, in: turnPrompt) { return true }
        if let original = clarificationOriginatingPrompt,
           turnPolicy.shouldRetainPendingPeriod(from: original),
           MarinaNamedTargetRequirement.containsLiteralName(name, in: original) { return true }
        guard turnPolicy.isContextualFinancialFollowUp,
              let query = memory?.latestFinancialQuery, let selected = query.selection else { return false }
        if let search = selected.search,
           MarinaNamedTargetRequirement.containsLiteralName(name, in: search) { return true }
        let ids = Set([selected.cardID, selected.categoryID, selected.budgetID,
                       selected.presetID, selected.accountID].compactMap { $0 })
        return memory?.confirmedEntities.contains {
            ids.contains($0.id) && MarinaNamedTargetRequirement.containsLiteralName(name, in: $0.name)
        } == true
    }

    /// Protocol values are not names unless the person actually supplied the literal name.
    private func protocolLookupCorrection(_ proposed: String) -> String? {
        let reference = proposed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isReference = reference.range(of: "^r[0-9]+$", options: .regularExpression) != nil
        let identifiers: Set<String> = [
            "findrecords", "readexpenses", "readincome", "readbudgetsummary", "readaccounts",
            "resolvename", "inventory", "summary", "transactions", "upcomingpresets",
            "largestpurchase", "categorytotals", "cardtotals", "merchanttotals", "categoryshares",
            "cardshares", "merchantshares", "periodtotals", "compare", "compareincome", "progress",
            "groups", "overview", "pace", "savingstrend"
        ]
        guard isReference || identifiers.contains(reference) else { return nil }
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let userWords = turnPrompt.lowercased().components(separatedBy: wordCharacters.inverted)
        // Real records named r1 or upcomingPresets remain searchable when the person names them.
        guard !userWords.contains(reference) else { return nil }
        if !isReference {
            return "\(proposed) is a tool or operation identifier, not a record name supplied by the person. Use it in its tool or operation field. Resolve only the actual named target; use previous for a contextual follow-up or workspace for an unnamed total. Preserve explicitly named filters."
        }
        if let entity = memory?.entity(forReference: reference) {
            return "\(reference) is a selection reference for \(entity.name), not a record name supplied by the person. Use selection \"\(reference)\" only if that target matches the question. Use workspace for an unnamed total, or resolve the actual names in the question. Preserve explicitly named filters."
        }
        return "\(reference) looks like a selection reference, not a record name supplied by the person. Do not search or invent names from it. Resolve the actual named target; use previous for a contextual follow-up or workspace for an unnamed total. Preserve explicitly named filters."
    }

    /// Give the model a chance to correct malformed arguments without executing a broader query.
    fileprivate func invalidArguments(_ error: MarinaToolArgumentError, diagnosticAttempt: Int? = nil, alreadyCounted: Bool = false, tool: MarinaDataRequest.Tool? = nil) throws -> String {
        try Task.checkCancellation()
        guard service != nil else { throw CancellationError() }
        if !alreadyCounted { calls += 1 }
        guard calls <= 8 else { throw ToolLimitError() }
        argumentIssue = error.message
        if let tool, tool != .findRecords { failedFinancialTool = tool }
        struct Feedback: Encodable { let status = "invalidRequest"; let explanation: String }
        let data = try JSONEncoder().encode(Feedback(explanation: error.message))
        let output = String(decoding: data, as: UTF8.self)
#if DEBUG
        if let diagnosticAttempt { diagnostics?.output(attempt: diagnosticAttempt, text: output, status: "invalidRequest") }
#endif
        onResult?()
        onStatus?(.responding)
        return output
    }

    private func currentNamedTargetRequirements() throws -> [MarinaNamedTargetRequirement] {
        if let cachedNamedTargetRequirements { return cachedNamedTargetRequirements }
        guard let service else { throw CancellationError() }
        let requirements = try service.namedTargetRequirements(prompt: turnPrompt)
        cachedNamedTargetRequirements = requirements
        return requirements
    }

    private func permitsExplicitWorkspaceRepair(for request: MarinaDataRequest) throws -> Bool {
        guard repairableUnknownReferenceTools.contains(request.tool),
              [.expenses, .income].contains(request.tool), request.operation != .comparison,
              turnPolicy.permitsUnfilteredSelectionRepair, memory?.latestFinancialQuery == nil,
              namedLookupTargets.isEmpty, pendingCandidates.isEmpty, clarificationCandidates.isEmpty,
              unresolvedLookup == nil else { return false }
        return try currentNamedTargetRequirements().isEmpty
    }

    fileprivate func applySelection(_ selection: MarinaSelection, to request: inout MarinaDataRequest) throws {
        switch selection {
        case .workspace:
            if invalidReferenceTools.contains(request.tool) {
                try requireToolArgument(try permitsExplicitWorkspaceRepair(for: request),
                                        "A reference failed to resolve. Resolve the intended target and use valid refs before reading workspace data.")
            }
            return
        case .previous:
            if !namedLookupTargets.isEmpty {
                let compatible = namedLookupTargets.filter {
                    Self.accepts(kind: $0.kind, tool: request.tool) || turnPolicy.ignoresSelection(kind: $0.kind, for: request)
                }
                try requireToolArgument(!compatible.isEmpty && compatible.count == namedLookupTargets.count,
                                        "The latest resolved targets do not all belong to this financial topic. Choose their selection explicitly.")
                try applyEntities(compatible, to: &request)
                return
            }
            let selectionIsExplicitlyUniversal = ["card", "category", "budget", "preset", "merchant", "incomeSource", "savingsAccount", "reconciliationAccount"]
                .filter { Self.accepts(kind: $0, tool: request.tool) }
                .allSatisfy { turnPolicy.ignoresSelection(kind: $0, for: request) }
            if selectionIsExplicitlyUniversal && !invalidReferenceTools.contains(request.tool) { return }
            guard let query = memory?.latestFinancialQuery else {
                if selectionIsExplicitlyUniversal && !invalidReferenceTools.contains(request.tool) { return }
                throw MarinaToolArgumentError(message: "There is no previous financial selection. Resolve the target or choose workspace explicitly.")
            }
            guard let selected = query.selection else {
                try requireToolArgument(query.tool == request.tool || selectionIsExplicitlyUniversal,
                                        "Previous financial query belongs to another topic. Choose workspace or copy a current reference explicitly.")
                try requireToolArgument(!invalidReferenceTools.contains(request.tool), "Resolve the failed reference before using an unfiltered previous selection.")
                return
            }
            var entities: [MarinaConversationMemory.Entity] = []
            func add(_ kind: String, _ id: String?) {
                if let id { entities.append(.init(kind: kind, id: id, name: id)) }
            }
            add("card", selected.cardID); add("category", selected.categoryID)
            add("budget", selected.budgetID); add("preset", selected.presetID)
            if let id = selected.accountID {
                let kind = ["savingsAccount", "reconciliationAccount"].first { memory?.reference(forKind: $0, id: id) != nil }
                    ?? memory?.confirmedEntities.first { $0.id == id && ["savingsAccount", "reconciliationAccount"].contains($0.kind) }?.kind
                guard let kind else { throw MarinaToolArgumentError(message: "Resolve the previous account again before reading it.") }
                add(kind, id)
            }
            if let search = selected.search {
                entities.append(.init(kind: query.tool == .income ? "incomeSource" : "merchant", id: search, name: search))
            }
            try requireToolArgument(query.tool == request.tool || (!entities.isEmpty && entities.allSatisfy { turnPolicy.ignoresSelection(kind: $0.kind, for: request) }),
                                    "Previous financial query belongs to another topic. Choose workspace or copy a current reference explicitly.")
            try applyEntities(entities, to: &request)
        case .references(let refs):
            do {
                try requireToolArgument(!refs.isEmpty && Set(refs).count == refs.count, "Use one or more distinct references from findRecords.")
                let entities = try refs.map { ref in
                    guard let entity = memory?.entity(forReference: ref) else {
                        throw MarinaToolArgumentError(message: "Unknown or expired reference \(ref). Resolve the name with findRecords; never drop the target.")
                    }
                    return entity
                }
                try applyEntities(entities, to: &request)
            } catch {
                // A model-invented reference may be corrected explicitly on a first unnamed
                // total. Known stale/foreign/wrong-kind targets never permit that recovery.
                let onlyUnknown = !refs.isEmpty && refs.allSatisfy { memory?.entity(forReference: $0) == nil }
                if onlyUnknown && (!invalidReferenceTools.contains(request.tool) || repairableUnknownReferenceTools.contains(request.tool)) {
                    repairableUnknownReferenceTools.insert(request.tool)
                } else { repairableUnknownReferenceTools.remove(request.tool) }
                invalidReferenceTools.insert(request.tool)
                throw error
            }
        }
    }

    private func applyEntities(_ entities: [MarinaConversationMemory.Entity], to request: inout MarinaDataRequest) throws {
        var kinds: Set<String> = []
        for entity in entities {
            if turnPolicy.ignoresSelection(kind: entity.kind, for: request) { continue }
            try requireToolArgument(Self.accepts(kind: entity.kind, tool: request.tool), "A \(entity.kind) reference cannot select \(request.tool.rawValue). Resolve the intended target.")
            let kind = ["savingsAccount", "reconciliationAccount"].contains(entity.kind) ? "account" : entity.kind
            try requireToolArgument(kinds.insert(kind).inserted, "Use at most one \(kind) reference in a selection.")
            switch entity.kind {
            case "card": request.cardID = entity.id
            case "category": request.categoryID = entity.id
            case "budget": request.budgetID = entity.id
            case "preset": request.presetID = entity.id
            case "merchant", "incomeSource": request.search = entity.name
            case "savingsAccount", "reconciliationAccount":
                try requireToolArgument(request.scope == .all || (entity.kind == "savingsAccount" ? request.scope == .savings : request.scope == .reconciliation),
                                        "The account reference does not match the requested account kind.")
                request.accountID = entity.id
                request.scope = entity.kind == "savingsAccount" ? .savings : .reconciliation
            default: break
            }
        }
    }

    private static func accepts(kind: String, tool: MarinaDataRequest.Tool) -> Bool {
        switch tool {
        case .expenses: ["card", "category", "budget", "preset", "merchant"].contains(kind)
        case .income: ["card", "budget", "incomeSource"].contains(kind)
        case .budgetSummary: ["card", "category", "budget"].contains(kind)
        case .accounts: ["savingsAccount", "reconciliationAccount"].contains(kind)
        case .findRecords: false
        }
    }

    private func includes(_ entity: MarinaConversationMemory.Entity, in request: MarinaDataRequest) -> Bool {
        switch entity.kind {
        case "card": request.cardID == entity.id || request.comparisonFilter?.cardID == entity.id
        case "category": request.categoryID == entity.id || request.comparisonFilter?.categoryID == entity.id
        case "budget": request.budgetID == entity.id || request.comparisonFilter?.budgetID == entity.id
        case "preset": request.presetID == entity.id || request.comparisonFilter?.presetID == entity.id
        case "merchant", "incomeSource": request.search == entity.name || request.comparisonFilter?.search == entity.name
        case "savingsAccount", "reconciliationAccount": request.accountID == entity.id
        default: false
        }
    }

    fileprivate func applyDates(_ value: MarinaDateSelection?, to request: inout MarinaDataRequest) throws {
        guard let value else { return }
        switch value {
        case .dates(let start, let end):
            request.startDate = try requiredText(start, "Explicit dates require both start and end as yyyy-MM-dd.")
            request.endDate = try requiredText(end, "Explicit dates require both start and end as yyyy-MM-dd.")
        case .calendar(let period):
            switch period {
            case .selectedPeriod: request.relativePeriod = .selectedPeriod
            case .previousPeriod: request.relativePeriod = .previousPeriod
            case .currentMonth: request.relativePeriod = .currentMonth
            case .previousMonth: request.relativePeriod = .previousMonth
            case .yearToDate: request.relativePeriod = .yearToDate
            case .nextSevenDays: request.relativePeriod = .nextSevenDays
            case .allTime: request.allTime = true
            case .previousQuery:
                guard let previous = memory?.latestFinancialQuery?.period else {
                    throw MarinaToolArgumentError(message: "There is no previous financial period. Choose dates explicitly.")
                }
                request.allTime = previous.allTime == true
                request.relativePeriod = previous.relative
                request.startDate = previous.startDate; request.endDate = previous.endDate
                try requireToolArgument(request.allTime || request.relativePeriod != nil || (request.startDate != nil && request.endDate != nil),
                                        "The previous query has no reusable period. Choose dates explicitly.")
            }
        }
    }

    fileprivate func applyComparisonDates(_ value: MarinaDateSelection?, to request: inout MarinaDataRequest) throws {
        var dates = MarinaDataRequest(tool: request.tool)
        try applyDates(value, to: &dates)
        request.comparisonStartDate = dates.startDate; request.comparisonEndDate = dates.endDate
        request.comparisonPeriod = dates.relativePeriod; request.comparisonAllTime = dates.allTime
    }

    func answer(id: UUID, prompt: String, narration: String) -> HomeAnswer {
        let financial = evidence.filter { $0.tool != .findRecords && $0.verified }
        let visible = financial.isEmpty ? Array(evidence.suffix(1)) : financial
        // Preserve typed, independently scoped results rather than flattening their UI.
        var presentations: [MarinaPresentation] = []
        for (index, result) in results.enumerated() {
            guard let presentation = result.presentation else { continue }
            let request = requests[index]
            if request.tool == .findRecords && request.search != nil && result.status != "candidates" { continue }
            if let existing = presentations.firstIndex(where: { $0.id == presentation.id }) {
                presentations[existing] = presentation
            } else { presentations.append(presentation) }
        }
        presentations = MarinaPresentationDisplayPolicy.coalesced(presentations)
        // Publish verified financial captions as soon as a read completes. Generated prose
        // remains available for nonfinancial conversation and clarification questions.
        let verifiedNarration = zip(requests, results).compactMap { request, result in
            MarinaVerifiedNarration.text(request: request, result: result)
        }
        var seenCaptions = Set<String>()
        let explanation = hasInvalidRequest || (requiresFreshRead && !hasGroundedAnswer) ? "" : verifiedNarration.isEmpty ? narration
            : verifiedNarration.filter { seenCaptions.insert($0).inserted }.joined(separator: "\n\n")
        let argumentNotice = argumentIssue.map { [HomeAnswerRow(title: $0, value: "", role: .assumption)] } ?? []
        var answer = HomeAnswer(id: id, queryID: id, kind: .message,
                          userPrompt: prompt, title: "", rows: visible.flatMap { $0.answer.rows } + argumentNotice,
                          explanation: explanation, presentations: presentations)
        answer.suppressedPresentationIDs = presentations.filter {
            !MarinaPresentationDisplayPolicy.shouldShow($0, after: previousPresentations)
        }.map(\.id)
        return answer
    }

    private struct ToolLimitError: LocalizedError {
        var errorDescription: String? { "This question needs too many data requests. Try a narrower question." }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDateSelectionKind: String {
    case selectedPeriod, previousPeriod, currentMonth, previousMonth, yearToDate, nextSevenDays, allTime, previousQuery
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaExplicitDateRange {
    var start: String
    var end: String
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaDateSelection: Generable, Sendable {
    case calendar(period: MarinaDateSelectionKind)
    case dates(start: String, end: String)

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, anyOf: [MarinaDateSelectionKind.self, MarinaExplicitDateRange.self])
    }

    init(_ content: GeneratedContent) throws {
        switch content.kind {
        case .string:
            self = .calendar(period: try MarinaDateSelectionKind(content))
        case .structure(let properties, _):
            try requireToolArgument(Set(properties.keys) == ["start", "end"],
                                    "Explicit dates require only start and end as yyyy-MM-dd.")
            let range = try MarinaExplicitDateRange(content)
            self = .dates(start: try requiredText(range.start, "Explicit dates require a start date."),
                          end: try requiredText(range.end, "Explicit dates require an end date."))
        default:
            throw MarinaToolArgumentError(message: "Choose a calendar period or an explicit start/end range.")
        }
    }

    var generatedContent: GeneratedContent {
        switch self {
        case .calendar(let period): period.generatedContent
        case .dates(let start, let end): MarinaExplicitDateRange(start: start, end: end).generatedContent
        }
    }

    static var selectedPeriod: Self { .calendar(period: .selectedPeriod) }
    static var previousPeriod: Self { .calendar(period: .previousPeriod) }
    static var currentMonth: Self { .calendar(period: .currentMonth) }
    static var previousMonth: Self { .calendar(period: .previousMonth) }
    static var yearToDate: Self { .calendar(period: .yearToDate) }
    static var nextSevenDays: Self { .calendar(period: .nextSevenDays) }
    static var allTime: Self { .calendar(period: .allTime) }
    static var previousQuery: Self { .calendar(period: .previousQuery) }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseScope: String { case all, variable, planned }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeState: String { case all, actual, planned }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDataGrouping: String { case none, card, category, merchant, source }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaDataSort: String { case newest, oldest, largest, smallest }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseMeasure: String { case budgetImpact, ledger, spending, planned, actual }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaPeriodUnit: String { case day, week, month, quarter, year }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaRecordKind: String { case card, category, budget, preset, savingsAccount, reconciliationAccount, incomeSource, merchant, workspace }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaAccountScope: String { case all, savings, reconciliation }

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaRecordLookup {
    case resolveName(name: String, kind: MarinaRecordKind? = nil)
    case inventory(kind: MarinaRecordKind?, offset: Int)
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFindRecordsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "findRecords"
    let description = "Resolve names or list workspace entities."
    typealias Arguments = RecordLookupArguments
    @Generable struct RecordLookupArguments {
        var showVisual: Bool? = nil
        @Guide(description: "Named target: resolveName. List entities: inventory.")
        var lookup: MarinaRecordLookup
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .findRecords)
            request.forcePresentation = arguments.showVisual
            request.operation = .inventory
            request.limit = 5
            switch arguments.lookup {
            case .resolveName(let name, let kind):
                request.recordKind = kind?.rawValue
                request.search = try requiredText(name, "resolveName requires a name.")
            case .inventory(let kind, let offset):
                request.recordKind = kind?.rawValue
                request.offset = offset
            }
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch let error as MarinaToolArgumentError {
#if DEBUG
            return try await bridge.invalidArguments(error, diagnosticAttempt: attempt, tool: .findRecords)
#else
            return try await bridge.invalidArguments(error, tool: .findRecords)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseSimpleOperation: String {
    case summary, transactions, upcomingPresets, largestPurchase, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaExpenseOperation: Generable, Sendable {
    case summary, transactions, upcomingPresets, largestPurchase, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals
    case compare(selection: MarinaSelection, dates: MarinaDateSelection)

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, anyOf: [MarinaExpenseSimpleOperation.self, MarinaExpenseComparisonOperation.self])
    }

    init(_ content: GeneratedContent) throws {
        switch content.kind {
        case .string:
            switch try MarinaExpenseSimpleOperation(content) {
            case .summary: self = .summary
            case .transactions: self = .transactions
            case .upcomingPresets: self = .upcomingPresets
            case .largestPurchase: self = .largestPurchase
            case .categoryTotals: self = .categoryTotals
            case .cardTotals: self = .cardTotals
            case .merchantTotals: self = .merchantTotals
            case .categoryShares: self = .categoryShares
            case .cardShares: self = .cardShares
            case .merchantShares: self = .merchantShares
            case .periodTotals: self = .periodTotals
            }
        case .structure(let properties, _):
            guard Set(properties.keys) == ["compare"], let payload = properties["compare"],
                  case .structure(let fields, _) = payload.kind, Set(fields.keys) == ["selection", "dates"] else {
                throw MarinaToolArgumentError(message: "Use compare containing only the other selection and dates.")
            }
            let value = try MarinaExpenseComparison(payload)
            self = .compare(selection: value.selection, dates: value.dates)
        default:
            throw MarinaToolArgumentError(message: "Choose an expense operation or a comparison selection/dates.")
        }
    }

    var generatedContent: GeneratedContent {
        switch self {
        case .summary: MarinaExpenseSimpleOperation.summary.generatedContent
        case .transactions: MarinaExpenseSimpleOperation.transactions.generatedContent
        case .upcomingPresets: MarinaExpenseSimpleOperation.upcomingPresets.generatedContent
        case .largestPurchase: MarinaExpenseSimpleOperation.largestPurchase.generatedContent
        case .categoryTotals: MarinaExpenseSimpleOperation.categoryTotals.generatedContent
        case .cardTotals: MarinaExpenseSimpleOperation.cardTotals.generatedContent
        case .merchantTotals: MarinaExpenseSimpleOperation.merchantTotals.generatedContent
        case .categoryShares: MarinaExpenseSimpleOperation.categoryShares.generatedContent
        case .cardShares: MarinaExpenseSimpleOperation.cardShares.generatedContent
        case .merchantShares: MarinaExpenseSimpleOperation.merchantShares.generatedContent
        case .periodTotals: MarinaExpenseSimpleOperation.periodTotals.generatedContent
        case .compare(let selection, let dates): MarinaExpenseComparisonOperation(compare: .init(selection: selection, dates: dates)).generatedContent
        }
    }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaSelection: Generable, Sendable {
    case workspace
    case previous
    case references([String])

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self,
            description: "workspace: all records; previous: latest resolved or financial target; otherwise copy a selection returned by findRecords.",
            anyOf: [String.self])
    }
    private static let validationFeedback = "Selection must be one string: \"workspace\" for an unnamed or all-records scope; \"previous\" only for a relevant follow-up; otherwise copy exact references returned by findRecords, comma-separated without spaces or duplicates. Never invent references or use names, IDs, or an empty selection."

    init(_ content: GeneratedContent) throws {
        guard case .string(let value) = content.kind else {
            throw MarinaToolArgumentError(message: Self.validationFeedback)
        }
        switch value {
        case "workspace": self = .workspace
        case "previous": self = .previous
        default:
            let refs = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let valid = refs.allSatisfy { ref in
                let bytes = Array(ref.utf8)
                return bytes.count >= 2 && bytes[0] == 114 && (49...57).contains(bytes[1])
                    && bytes.dropFirst(2).allSatisfy { (48...57).contains($0) }
            }
            try requireToolArgument(valid && Set(refs).count == refs.count, Self.validationFeedback)
            self = .references(refs)
        }
    }
    var generatedContent: GeneratedContent {
        switch self {
        case .workspace: "workspace".generatedContent
        case .previous: "previous".generatedContent
        case .references(let refs): refs.joined(separator: ",").generatedContent
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaExpenseComparison {
    var selection: MarinaSelection
    var dates: MarinaDateSelection
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaExpenseComparisonOperation {
    var compare: MarinaExpenseComparison
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeSummaryKind: String { case summary, progress }
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaIncomeTransactions {
    var order: MarinaDataSort
    var offset: Int
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaIncomeGroups {
    var by: MarinaDataGrouping
    var offset: Int
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaPeriodPage {
    var unit: MarinaPeriodUnit
    var offset: Int
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaIncomeComparison {
    var selection: MarinaSelection
    var dates: MarinaDateSelection
}
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable struct MarinaIncomeComparisonOperation {
    var compareIncome: MarinaIncomeComparison
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaIncomeOperation: Generable, Sendable {
    case summary
    case progress
    case transactions(order: MarinaDataSort, offset: Int)
    case groups(by: MarinaDataGrouping, offset: Int)
    case periodTotals(unit: MarinaPeriodUnit, offset: Int)
    case compareIncome(selection: MarinaSelection, dates: MarinaDateSelection)

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, anyOf: [MarinaIncomeSummaryKind.self, MarinaIncomeTransactions.self,
            MarinaIncomeGroups.self, MarinaPeriodPage.self, MarinaIncomeComparisonOperation.self])
    }

    init(_ content: GeneratedContent) throws {
        switch content.kind {
        case .string:
            switch try MarinaIncomeSummaryKind(content) {
            case .summary: self = .summary
            case .progress: self = .progress
            }
        case .structure(let properties, _):
            let keys = Set(properties.keys)
            if keys == ["order", "offset"] {
                let value = try MarinaIncomeTransactions(content)
                self = .transactions(order: value.order, offset: value.offset)
            } else if keys == ["by", "offset"] {
                let value = try MarinaIncomeGroups(content)
                self = .groups(by: value.by, offset: value.offset)
            } else if keys == ["unit", "offset"] {
                let value = try MarinaPeriodPage(content)
                self = .periodTotals(unit: value.unit, offset: value.offset)
            } else if keys == ["compareIncome"], let payload = properties["compareIncome"],
                      case .structure(let fields, _) = payload.kind, Set(fields.keys) == ["selection", "dates"] {
                let value = try MarinaIncomeComparison(payload)
                self = .compareIncome(selection: value.selection, dates: value.dates)
            } else {
                throw MarinaToolArgumentError(message: "Choose one income operation: summary, progress, order/offset, by/offset, unit/offset, or compareIncome containing selection/dates.")
            }
        default:
            throw MarinaToolArgumentError(message: "Choose a supported income operation.")
        }
    }

    var generatedContent: GeneratedContent {
        switch self {
        case .summary: MarinaIncomeSummaryKind.summary.generatedContent
        case .progress: MarinaIncomeSummaryKind.progress.generatedContent
        case .transactions(let order, let offset): MarinaIncomeTransactions(order: order, offset: offset).generatedContent
        case .groups(let by, let offset): MarinaIncomeGroups(by: by, offset: offset).generatedContent
        case .periodTotals(let unit, let offset): MarinaPeriodPage(unit: unit, offset: offset).generatedContent
        case .compareIncome(let selection, let dates): MarinaIncomeComparisonOperation(compareIncome: .init(selection: selection, dates: dates)).generatedContent
        }
    }
}

/// The model chooses a comparison using the same string-shaped field as ordinary totals.
/// Swift callers keep the richer operation enum; the other side is required by validation.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaExpenseOperationChoice: String {
    case summary, transactions, upcomingPresets, largestPurchase, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals, compare

    init(_ operation: MarinaExpenseOperation) {
        switch operation {
        case .summary: self = .summary
        case .transactions: self = .transactions
        case .upcomingPresets: self = .upcomingPresets
        case .largestPurchase: self = .largestPurchase
        case .categoryTotals: self = .categoryTotals
        case .cardTotals: self = .cardTotals
        case .merchantTotals: self = .merchantTotals
        case .categoryShares: self = .categoryShares
        case .cardShares: self = .cardShares
        case .merchantShares: self = .merchantShares
        case .periodTotals: self = .periodTotals
        case .compare: self = .compare
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaIncomeOperationLabel: String { case summary, progress, compareIncome }

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaIncomeOperationChoice: Generable, Sendable {
    case standard(MarinaIncomeOperation)
    case compareIncome

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, anyOf: [MarinaIncomeOperationLabel.self,
            MarinaIncomeTransactions.self, MarinaIncomeGroups.self, MarinaPeriodPage.self])
    }
    init(_ content: GeneratedContent) throws {
        if case .string("compareIncome") = content.kind { self = .compareIncome; return }
        if case .structure(let fields, _) = content.kind {
            let keys = Set(fields.keys)
            try requireToolArgument(keys == ["order", "offset"] || keys == ["by", "offset"] || keys == ["unit", "offset"],
                                    "Use an income operation string, or one complete order/offset, by/offset, or unit/offset payload. Put comparison selection/dates in the top-level comparison field.")
        }
        self = .standard(try MarinaIncomeOperation(content))
    }
    init(_ operation: MarinaIncomeOperation) {
        if case .compareIncome = operation { self = .compareIncome }
        else { self = .standard(operation) }
    }
    var generatedContent: GeneratedContent {
        switch self {
        case .standard(let operation): operation.generatedContent
        case .compareIncome: "compareIncome".generatedContent
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaExpensesTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readExpenses"
    let description = "Spending and purchases. Resolve names with findRecords; copy its selection string."
    typealias Arguments = ExpenseQueryArguments
    @Generable struct ExpenseQueryArguments {
        var showVisual: Bool? = nil
        @Guide(description: "workspace: all records. previous: latest resolved or financial target. Named targets: copy the returned selection.")
        var selection: MarinaSelection
        @Guide(description: "Requested period; previousQuery reuses the last financial query dates.")
        var dates: MarinaDateSelection
        @Guide(description: "summary: total; transactions: purchases; compare: calculated comparison requiring comparison.")
        var operation: MarinaExpenseOperationChoice
        @Guide(description: "Required only for compare; the other selection and dates.")
        var comparison: MarinaExpenseComparison? = nil
        var sort: MarinaDataSort?
        var periodUnit: MarinaPeriodUnit?
        var offset: Int?
        var scope: MarinaExpenseScope?
        var measure: MarinaExpenseMeasure?
        var includeFuture: Bool?

        init(showVisual: Bool? = nil, selection: MarinaSelection, dates: MarinaDateSelection,
             operation: MarinaExpenseOperation, sort: MarinaDataSort? = nil, periodUnit: MarinaPeriodUnit? = nil,
             offset: Int? = nil, scope: MarinaExpenseScope? = nil, measure: MarinaExpenseMeasure? = nil,
             includeFuture: Bool? = nil) {
            self.showVisual = showVisual; self.selection = selection; self.dates = dates
            self.operation = .init(operation)
            if case .compare(let selection, let dates) = operation { comparison = .init(selection: selection, dates: dates) }
            self.sort = sort; self.periodUnit = periodUnit; self.offset = offset; self.scope = scope
            self.measure = measure; self.includeFuture = includeFuture
        }

        func validatedOperation() throws -> MarinaExpenseOperation {
            if operation == .compare {
                guard let comparison else {
                    throw MarinaToolArgumentError(message: "operation compare requires comparison containing both selection and dates.")
                }
                return .compare(selection: comparison.selection, dates: comparison.dates)
            }
            try requireToolArgument(comparison == nil, "Only operation compare accepts a comparison payload.")
            return try MarinaExpenseOperation(operation.rawValue.generatedContent)
        }
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .expenses)
            request.forcePresentation = arguments.showVisual
            try await bridge.applyDates(arguments.dates, to: &request)
            request.limit = 5
            request.offset = arguments.offset ?? 0
            switch try arguments.validatedOperation() {
            case .summary: request.operation = .summary
            case .upcomingPresets: request.purpose = .upcomingPresets
            case .largestPurchase: request.operation = .transactions; request.sort = .largest; request.limit = 1
            case .categoryShares: request.operation = .share; request.grouping = .category
            case .cardShares: request.operation = .share; request.grouping = .card
            case .merchantShares: request.operation = .share; request.grouping = .merchant
            case .transactions: request.operation = .transactions; request.sort = sort(arguments.sort)
            case .categoryTotals: request.operation = .ranking; request.grouping = .category
            case .cardTotals: request.operation = .ranking; request.grouping = .card
            case .merchantTotals: request.operation = .ranking; request.grouping = .merchant
            case .periodTotals: request.operation = .trend; request.periodUnit = periodUnit(arguments.periodUnit)
            case .compare(let otherSelection, let otherDates):
                request.operation = .comparison
                var selection = MarinaDataRequest(tool: .expenses)
                selection.operation = .comparison
                try await bridge.applySelection(otherSelection, to: &selection)
                request.comparisonFilter = .init(cardID: selection.cardID, categoryID: selection.categoryID,
                                                 budgetID: selection.budgetID, presetID: selection.presetID, search: selection.search)
                try await bridge.applyComparisonDates(otherDates, to: &request)
            }
            try await bridge.applySelection(arguments.selection, to: &request)
            switch arguments.scope { case .variable: request.scope = .variable; case .planned: request.scope = .planned; default: break }
            request.includeFuture = arguments.includeFuture ?? false
            switch arguments.measure { case .ledger: request.expenseMeasure = .ledger; case .spending: request.expenseMeasure = .spending; case .planned: request.expenseMeasure = .planned; case .actual: request.expenseMeasure = .actual; default: break }
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch let error as MarinaToolArgumentError {
#if DEBUG
            return try await bridge.invalidArguments(error, diagnosticAttempt: attempt, tool: .expenses)
#else
            return try await bridge.invalidArguments(error, tool: .expenses)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaIncomeTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readIncome"
    let description = "Income totals, progress, activity and comparisons."
    typealias Arguments = IncomeQueryArguments
    @Generable struct IncomeQueryArguments {
        var showVisual: Bool? = nil
        var selection: MarinaSelection
        var dates: MarinaDateSelection
        @Guide(description: "planned: expected income; actual: received income; all: both.")
        var state: MarinaIncomeState
        @Guide(description: "summary: one total; progress: planned/received totals and percentage; compareIncome: two-period/target comparison requiring comparison.")
        var operation: MarinaIncomeOperationChoice
        @Guide(description: "Required only for compareIncome; the other selection and dates.")
        var comparison: MarinaIncomeComparison? = nil

        init(showVisual: Bool? = nil, selection: MarinaSelection, dates: MarinaDateSelection,
             state: MarinaIncomeState, operation: MarinaIncomeOperation) {
            self.showVisual = showVisual; self.selection = selection; self.dates = dates; self.state = state
            self.operation = .init(operation)
            if case .compareIncome(let selection, let dates) = operation { comparison = .init(selection: selection, dates: dates) }
        }

        func validatedOperation() throws -> MarinaIncomeOperation {
            switch operation {
            case .compareIncome:
                guard let comparison else {
                    throw MarinaToolArgumentError(message: "operation compareIncome requires comparison containing both selection and dates.")
                }
                return .compareIncome(selection: comparison.selection, dates: comparison.dates)
            case .standard(let operation):
                try requireToolArgument(comparison == nil, "Only operation compareIncome accepts a comparison payload.")
                return operation
            }
        }
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .income)
            request.forcePresentation = arguments.showVisual
            try await bridge.applyDates(arguments.dates, to: &request)
            switch arguments.state { case .planned: request.state = .planned; case .all: request.state = .all; case .actual: request.state = .actual }
            switch try arguments.validatedOperation() {
            case .summary: request.operation = .summary
            case .progress: request.purpose = .incomeProgress; request.state = .all
            case .transactions(let order, let offset):
                request.operation = .transactions; request.sort = sort(order); request.offset = offset
            case .groups(let by, let offset):
                try requireToolArgument(by != .none, "groups requires a grouping dimension.")
                request.operation = .ranking; request.grouping = grouping(by); request.offset = offset
            case .periodTotals(let unit, let offset):
                request.operation = .trend; request.periodUnit = periodUnit(unit); request.offset = offset
            case .compareIncome(let selection, let dates):
                request.operation = .comparison
                var comparison = MarinaDataRequest(tool: .income)
                comparison.operation = .comparison
                try await bridge.applySelection(selection, to: &comparison)
                request.comparisonFilter = .init(cardID: comparison.cardID, budgetID: comparison.budgetID, search: comparison.search)
                try await bridge.applyComparisonDates(dates, to: &request)
            }
            try await bridge.applySelection(arguments.selection, to: &request)
            request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch let error as MarinaToolArgumentError {
#if DEBUG
            return try await bridge.invalidArguments(error, diagnosticAttempt: attempt, tool: .income)
#else
            return try await bridge.invalidArguments(error, tool: .income)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaBudgetSummaryKind: String { case overview, pace }
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaBudgetOperation: Generable, Sendable {
    case overview
    case pace
    case savingsTrend(unit: MarinaPeriodUnit, offset: Int)

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, anyOf: [MarinaBudgetSummaryKind.self, MarinaPeriodPage.self])
    }

    init(_ content: GeneratedContent) throws {
        switch content.kind {
        case .string:
            switch try MarinaBudgetSummaryKind(content) {
            case .overview: self = .overview
            case .pace: self = .pace
            }
        case .structure(let properties, _):
            try requireToolArgument(Set(properties.keys) == ["unit", "offset"], "A savings trend requires only unit and offset.")
            let value = try MarinaPeriodPage(content)
            self = .savingsTrend(unit: value.unit, offset: value.offset)
        default:
            throw MarinaToolArgumentError(message: "Choose overview, pace, or a savings trend unit/offset.")
        }
    }

    var generatedContent: GeneratedContent {
        switch self {
        case .overview: MarinaBudgetSummaryKind.overview.generatedContent
        case .pace: MarinaBudgetSummaryKind.pace.generatedContent
        case .savingsTrend(let unit, let offset): MarinaPeriodPage(unit: unit, offset: offset).generatedContent
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaBudgetTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readBudgetSummary"
    let description = "Budget room, pace, category limits and savings forecasts."
    typealias Arguments = BudgetQueryArguments
    @Generable struct BudgetQueryArguments {
        var selection: MarinaSelection
        var operation: MarinaBudgetOperation
        var showVisual: Bool? = nil
        var dates: MarinaDateSelection?
        var hypotheticalSpending: Double?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .budgetSummary)
            request.forcePresentation = arguments.showVisual
            try await bridge.applyDates(arguments.dates, to: &request)
            try await bridge.applySelection(arguments.selection, to: &request)
            switch arguments.operation {
            case .overview: break
            case .pace: request.purpose = .budgetPace
            case .savingsTrend(let unit, let offset): request.periodUnit = periodUnit(unit); request.offset = offset
            }
            request.hypotheticalSpending = arguments.hypotheticalSpending
            request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch let error as MarinaToolArgumentError {
#if DEBUG
            return try await bridge.invalidArguments(error, diagnosticAttempt: attempt, tool: .budgetSummary)
#else
            return try await bridge.invalidArguments(error, tool: .budgetSummary)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaAccountsTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readAccounts"
    let description = "Savings or reconciliation balances and activity."
    typealias Arguments = AccountQueryArguments
    @Generable struct AccountQueryArguments {
        var selection: MarinaSelection
        var showVisual: Bool? = nil
        var scope: MarinaAccountScope?
        var dates: MarinaDateSelection?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .accounts)
            request.forcePresentation = arguments.showVisual
            switch arguments.scope { case .savings: request.scope = .savings; case .reconciliation: request.scope = .reconciliation; default: break }
            try await bridge.applySelection(arguments.selection, to: &request)
            try await bridge.applyDates(arguments.dates, to: &request)
            request.offset = arguments.offset ?? 0; request.limit = 5
#if DEBUG
            return try await bridge.call(request, diagnosticAttempt: attempt)
#else
            return try await bridge.call(request)
#endif
        } catch let error as MarinaToolArgumentError {
#if DEBUG
            return try await bridge.invalidArguments(error, diagnosticAttempt: attempt, tool: .accounts)
#else
            return try await bridge.invalidArguments(error, tool: .accounts)
#endif
        } catch {
#if DEBUG
            if let attempt { await bridge.diagnostics?.failed(attempt: attempt) }
#endif
            throw error
        }
    }
}

fileprivate struct MarinaToolArgumentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

nonisolated private func requireToolArgument(_ condition: Bool, _ message: String) throws {
    guard condition else { throw MarinaToolArgumentError(message: message) }
}

nonisolated private func requiredText(_ text: String?, _ message: String) throws -> String {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw MarinaToolArgumentError(message: message)
    }
    return text
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func grouping(_ value: MarinaDataGrouping?) -> MarinaDataRequest.Grouping {
    switch value { case .card: .card; case .category: .category; case .merchant: .merchant; case .source: .source; default: .none }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func sort(_ value: MarinaDataSort?) -> MarinaDataRequest.Sort {
    switch value { case .oldest: .oldest; case .largest: .largest; case .smallest: .smallest; default: .newest }
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated private func periodUnit(_ value: MarinaPeriodUnit?) -> MarinaDataRequest.PeriodUnit? {
    switch value { case .day: .day; case .week: .week; case .month: .month; case .quarter: .quarter; case .year: .year; case nil: nil }
}
#endif
