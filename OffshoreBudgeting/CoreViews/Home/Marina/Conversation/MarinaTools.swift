import Foundation

#if canImport(FoundationModels)
import FoundationModels

enum MarinaPendingChoiceResolution {
    case unhandled
    case clarification
    case answer(reference: String)
}

/// Serializes SwiftData access on the main actor, even when the model calls tools concurrently.
@available(iOS 26.0, macCatalyst 26.0, *)
@MainActor
final class MarinaToolBridge {
#if DEBUG
    var diagnostics: MarinaTokenDiagnostics?
    nonisolated static func evaluationTrace(_ label: String, _ value: String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MARINA_MODEL_EVALUATION"] == "1",
              environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" else { return }
        print("MARINA_FIXTURE_TOOL \(label): \(value.prefix(6000))")
    }
#endif
    private var service: MarinaReadOnlyDataService?
    private var onResult: (() -> Void)?
    var onStatus: ((MarinaResponseState) -> Void)?
    var onValidatedResult: ((MarinaDataRequest, MarinaDataResult) -> Void)?
    var haltOnClarification = false
    var requiresFreshRead = false
    var hasNarrationEvidence: Bool {
        !answerResultIndices.isEmpty
    }
    var narrationDraft: MarinaNarrationDraft?
    private var results: [MarinaDataResult] = []
    private var selectedResultIndices: [Int]?
    private var resultSelectionRejected = false
    private var pendingFinancialRequest: MarinaDataRequest?
    /// Entity discovery returns rN selections, not answer references. Keep qN dense
    /// over eligible answers so a lookup/error cannot be advertised as an answer.
    private var answerResultIndices: [Int] {
        results.indices.filter { index in
            (requests[index].tool != .findRecords || requests[index].search == nil)
                && ["success", "empty"].contains(results[index].status)
                && !MarinaNarrationEvidence.facts(request: results[index].resolvedRequest ?? requests[index],
                    result: results[index], prefix: "").isEmpty
        }
    }

    private func answerReference(for index: Int) -> String? {
        answerResultIndices.firstIndex(of: index).map { "q\($0)" }
    }
    var selectedEvidence: [MarinaNarrationEvidence] {
        let indices = selectedResultIndices ?? Array(results.indices.suffix(1))
        return indices.enumerated().flatMap { position, index -> [MarinaNarrationEvidence] in
            guard let reference = answerReference(for: index) else { return [] }
            return MarinaNarrationEvidence.facts(request: results[index].resolvedRequest ?? requests[index],
                result: results[index], prefix: reference).map { fact in
                    var selected = fact
                    selected.isFocus = position == 0 && fact.isFocus
                    return selected
                }
        }
    }

    /// Current-turn query references never survive renewal or silently select another read.
    @discardableResult
    func selectResults(primary: String?, supporting: [String]) -> Bool {
        func index(_ reference: String) -> Int? {
            guard reference.first == "q", let value = Int(reference.dropFirst()),
                  reference == "q\(value)", answerResultIndices.indices.contains(value) else { return nil }
            return answerResultIndices[value]
        }
        guard let primary, let main = index(primary),
              !requiresFreshRead || requests[main].tool != .findRecords, supporting.count <= 2,
              Set([primary] + supporting).count == supporting.count + 1,
              supporting.allSatisfy({ index($0) != nil }) else {
            selectedResultIndices = []
            resultSelectionRejected = true
            return false
        }
        selectedResultIndices = [main] + supporting.compactMap(index)
        resultSelectionRejected = false
        // Follow-ups resume the answer the model selected, never its last exploratory read.
        turnMemory?.record(request: requests[main], result: results[main], answerID: turnAnswerID, prompt: turnPrompt)
        onValidatedResult?(requests[main], results[main])
        return true
    }
    private var evidence: [(tool: MarinaDataRequest.Tool, verified: Bool, answer: HomeAnswer)] = []
    private var previousPresentations: [MarinaPresentation] = []
    private var calls = 0
    private var isCompiledTurn = false
    private var turnAnswerID = UUID()
    var conversationMemory: (() -> MarinaConversationMemory?)?
    private var turnMemory: MarinaConversationMemory?
    private var pendingCandidates: [MarinaConversationMemory.Entity] = []
    private var confirmedPendingSelection: [MarinaConversationMemory.Entity] = []
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
        hasFinancialResults || results.contains { ["needsPeriodChoice", "needsBudgetChoice"].contains($0.status) } || zip(requests, results).contains { request, result in
            request.tool == .findRecords && ((!requiresFreshRead && request.search == nil && ["success", "empty"].contains(result.status))
                || (request.search != nil && (result.status == "candidates" || result.status == "empty")))
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

    func begin(service: MarinaReadOnlyDataService, history: [HomeAnswer] = [], prompt: String = "", memory: MarinaConversationMemory? = nil, compiled: Bool = false, onResult: @escaping () -> Void) {
        previousPresentations = MarinaPresentationDisplayPolicy.previousResults(in: history)
        self.service = service
        isCompiledTurn = compiled
        self.onResult = onResult
        results = []
        selectedResultIndices = nil
        resultSelectionRejected = false
        pendingFinancialRequest = memory?.pendingClarification?.pendingRequest
        narrationDraft = nil
        evidence = []
        requests = []
        calls = 0
        turnAnswerID = UUID()
        turnMemory = memory
        turnPrompt = prompt
        turnPolicy = MarinaTurnPolicy(prompt: prompt)
        confirmedPendingSelection = memory?.pendingClarification?.selectedEntities ?? []
        pendingCandidates = confirmedPendingSelection.isEmpty ? memory?.pendingClarification?.candidates ?? [] : []
        clarificationCandidates = memory?.pendingClarification?.candidates ?? []
        clarificationPeriod = memory?.pendingClarification?.period
        clarificationOriginatingPrompt = memory?.pendingClarification?.originatingPrompt
        clarificationSearch = memory?.pendingClarification?.search
        if !compiled, let original = clarificationOriginatingPrompt, !turnPolicy.shouldRetainPendingPeriod(from: original) {
            // A full new question owns its target. The fresh literal-name guards below
            // still require every explicitly named record, including renewed ambiguity.
            confirmedPendingSelection = []
            pendingCandidates = []
            clarificationCandidates = []
            clarificationPeriod = nil
            clarificationOriginatingPrompt = nil
            clarificationSearch = nil
            pendingFinancialRequest = nil
        }
        cachedNamedTargetRequirements = nil
        ambiguityDiscoveredThisTurn = false
        namedLookupTargets = confirmedPendingSelection
        argumentIssue = nil
        failedFinancialTool = nil
        invalidReferenceTools = []
        repairableUnknownReferenceTools = []
        unresolvedLookup = nil
    }

    /// Consume a reply to choices already offered by the app before asking the model
    /// to reinterpret it. Names and IDs are re-read inside the bound workspace.
    func resolvePendingChoice() throws -> MarinaPendingChoiceResolution {
        guard let pending = memory?.pendingClarification, !pending.candidates.isEmpty,
              !turnPolicy.isExplicitFinancialQuestion else { return .unhandled }
        let choices = pending.candidates.map { ($0.kind, $0.name) }
        let selected = pending.candidates.filter {
            turnPolicy.confirmsPendingCandidate(kind: $0.kind, name: $0.name,
                candidates: choices, ambiguousSearch: pending.search)
        }
        let priorHalt = haltOnClarification
        haltOnClarification = false
        defer { haltOnClarification = priorHalt }
        var candidate: MarinaConversationMemory.Entity?
        if selected.count == 1 { candidate = selected[0] }
        else {
            let kinds = Set(pending.candidates.map(\.kind)).filter { turnPolicy.confirmsOnlyPendingKind($0) }
            guard kinds.count == 1, let kind = kinds.first, let search = pending.search else { return .unhandled }
            var lookup = MarinaDataRequest(tool: .findRecords)
            lookup.operation = .inventory; lookup.recordKind = kind; lookup.search = search; lookup.limit = 5
            _ = try call(lookup)
            guard let result = results.last, result.status == "success", result.records.count == 1 else { return .clarification }
            let record = result.records[0]
            candidate = .init(kind: record.kind, id: record.id, name: record.title)
        }
        guard let candidate else { return .unhandled }
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.operation = .inventory; lookup.recordKind = candidate.kind == "periodBudget" ? "budget" : candidate.kind; lookup.search = candidate.name
        lookup.exactRecordName = true; lookup.expectedRecordID = candidate.id; lookup.limit = 5
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(pending.reason) { lookup.allTime = true }
        _ = try call(lookup)
        guard let result = results.last, result.status == "success", result.records.count == 1 else { return .clarification }
        confirmedPendingSelection = [candidate]
        pendingCandidates = []
        clarificationCandidates = pending.candidates.contains(candidate) ? pending.candidates : pending.candidates + [candidate]
        namedLookupTargets = [candidate]
        ambiguityDiscoveredThisTurn = false
        let bareChoice = turnPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(candidate.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        guard bareChoice, turnPolicy.periodCue == .none, !turnPolicy.requiresPeriodComparison,
              var request = pending.pendingRequest else { return .unhandled }
        try applyEntities([candidate], to: &request)
        _ = try call(request)
        guard let index = results.indices.last, requests[index].tool != .findRecords,
              let reference = answerReference(for: index) else { return .clarification }
        return .answer(reference: reference)
    }

    func end() { service = nil; onResult = nil; onStatus = nil; onValidatedResult = nil }

    /// Only the app compiler uses this entry. Model-generated tool arguments keep
    /// their existing resolution guards in `call`; compiled requests have already
    /// passed the typed intent/target boundary and share the fresh read below.
    @discardableResult
    func executeCompiledRead(_ request: MarinaDataRequest, pendingRequest: MarinaDataRequest? = nil) throws -> MarinaDataResult {
        guard isCompiledTurn else { throw MarinaToolArgumentError(message: "A compiled request requires a compiled turn.") }
        calls += 1
        guard calls <= 8 else { throw ToolLimitError() }
        guard request.purpose != .cardSummary || request.cardID != nil else {
            throw MarinaToolArgumentError(message: "Choose a card for its summary.")
        }
        pendingFinancialRequest = pendingRequest
        let previousHalt = haltOnClarification
        haltOnClarification = false
        defer { haltOnClarification = previousHalt }
        _ = try executeRead(request)
        guard let result = results.last else { throw CancellationError() }
        return result
    }

    func selectCompiledResult() -> String? {
        guard let index = results.indices.last, let reference = answerReference(for: index),
              selectResults(primary: reference, supporting: []) else { return nil }
        return reference
    }

    func presentCompiledDateChoice(_ result: MarinaDataResult, request: MarinaDataRequest) throws {
        guard isCompiledTurn, ["needsPeriodChoice", "needsBudgetChoice"].contains(result.status) else {
            throw MarinaToolArgumentError(message: "Expected a verified date choice.")
        }
        let previousHalt = haltOnClarification
        haltOnClarification = false
        defer { haltOnClarification = previousHalt }
        _ = try executeRead(request, preparedChoice: result)
    }

    func call(_ request: MarinaDataRequest, diagnosticAttempt: Int? = nil) throws -> String {
#if DEBUG
        if let json = try? JSONEncoder().encode(request) { Self.evaluationTrace("mapped", String(decoding: json, as: UTF8.self)) }
#endif
        var request = request
        if request.tool != .findRecords, let pending = memory?.pendingClarification, let original = pending.pendingRequest,
           pending.originatingPrompt.map({ turnPolicy.shouldRetainPendingPeriod(from: $0) }) ?? true,
           let selected = pending.candidates.first(where: { includes($0, in: request) }),
           (confirmedPendingSelection.contains(selected) || turnPolicy.confirmsPendingCandidate(kind: selected.kind, name: selected.name,
               candidates: pending.candidates.map { ($0.kind, $0.name) }, ambiguousSearch: pending.search)) {
            let incoming = request
            let chosenDates = (request.relativePeriod, request.startDate, request.endDate, request.allTime)
            request = original
            request.cardID = request.cardID ?? incoming.cardID
            request.categoryID = request.categoryID ?? incoming.categoryID
            request.categoryIDs = request.categoryIDs ?? incoming.categoryIDs
            request.budgetID = request.budgetID ?? incoming.budgetID
            request.presetID = request.presetID ?? incoming.presetID
            request.chartIntent = incoming.chartIntent ?? request.chartIntent
            // A clarification replaces the unresolved target of that kind. It is not an
            // additional category or a second incompatible account selection.
            switch selected.kind {
            case "category":
                let unresolved = Set(pending.candidates.filter { $0.kind == "category" }.map(\.id))
                if let id = request.categoryID, unresolved.contains(id) { request.categoryID = nil }
                request.categoryIDs = request.categoryIDs?.filter { !unresolved.contains($0) }
                if request.categoryIDs?.isEmpty == true { request.categoryIDs = nil }
            case "merchant": request.search = nil; request.merchantName = nil
            case "savingsAccount", "reconciliationAccount": request.accountID = nil; request.scope = .all
            default: break
            }
            try applyEntities([selected], to: &request)
            if turnPolicy.periodCue != .none {
                request.relativePeriod = chosenDates.0; request.startDate = chosenDates.1
                request.endDate = chosenDates.2; request.allTime = chosenDates.3
            }
        }
        request = turnPolicy.constrained(request)
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
            request.categoryIDs = previous.selection?.categoryIDs
            request.budgetID = previous.selection?.budgetID
            request.presetID = previous.selection?.presetID
            request.accountID = previous.selection?.accountID
            request.search = previous.selection?.search
            request.merchantName = previous.selection?.merchantName
            request.chartIntent = request.chartIntent ?? previous.chartIntent
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
            if let candidate = clarificationCandidates.first(where: {
                turnPolicy.confirmsPendingCandidate(kind: $0.kind, name: $0.name,
                    candidates: clarificationCandidates.map { ($0.kind, $0.name) }, ambiguousSearch: clarificationSearch)
                    && (MarinaNamedTargetRequirement.containsLiteralName(proposed, in: $0.name)
                        || proposed.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ").caseInsensitiveCompare(
                            $0.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")) == .orderedSame)
            }) {
                request.search = candidate.name
                request.recordKind = candidate.kind
                request.exactRecordName = true
            }
        }
        if request.tool == .findRecords, request.search != nil, let kind = request.recordKind,
           !turnPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, request.exactRecordName != true,
           !lookupKindIsGrounded(kind, name: request.search ?? "") {
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
        if request.tool == .findRecords, let search = request.search,
           search.compare(service.workspaceIdentity.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
           MarinaNamedTargetRequirement.explicitKind(for: search, in: turnPrompt) == "workspace" {
            request.recordKind = "workspace"
            request.exactRecordName = true
        }
        calls += 1
        guard calls <= 8 else { throw ToolLimitError() }
        if request.tool == .findRecords, let search = request.search,
           let correction = protocolLookupCorrection(search) {
            return try invalidArguments(.init(message: correction), diagnosticAttempt: diagnosticAttempt,
                                        alreadyCounted: true, tool: .findRecords)
        }
        if request.tool == .findRecords, let search = request.search,
           search.compare(service.workspaceIdentity.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
           !MarinaNamedTargetRequirement.containsLiteralName(search, in: turnPrompt) {
            return "{\"status\":\"scopeAlreadyResolved\",\"selection\":\"workspace\",\"explanation\":\"The current workspace is already bound by the app. Use workspace for this unnamed question; no name lookup is needed.\"}"
        }
        if request.tool == .findRecords, let search = request.search,
           !ignoredLookup, !lookupNameIsGrounded(search) {
            return try invalidArguments(.init(message: "That lookup name was not supplied in this question or its relevant context. Look up only the user's literal target name. Use workspace for unnamed totals or previous for contextual follow-ups; do not invent a name."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: .findRecords)
        }
        if turnPolicy.requiresPeriodComparison, [.expenses, .income].contains(request.tool),
           request.operation != .comparison {
            let comparison = request.tool == .income ? "compareIncome" : "compare"
            return try invalidArguments(.init(message: "The user requested a calculated comparison. Use the \(comparison) operation with the other side's selection and dates inside it. Top-level selection and dates identify the first side. Preserve the user's named periods and targets. Do not substitute separate reads or a budget summary."),
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
                && !confirmedPendingSelection.contains(candidate)
                && !turnPolicy.confirmsPendingCandidate(kind: candidate.kind, name: candidate.name,
                    candidates: clarificationCandidates.map { (kind: $0.kind, name: $0.name) },
                    ambiguousSearch: clarificationSearch)
        }
        if request.tool != .findRecords,
           (ambiguityDiscoveredThisTurn && !requiredCandidates.isEmpty)
            || (!requiredCandidates.isEmpty && !requiredCandidates.contains(where: { includes($0, in: request) }))
            || lacksExplicitChoice {
            retainPendingRequest(request)
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
           requiredTargets.contains(where: { Self.accepts(kind: $0.kind, tool: request.tool) && !includes($0, in: request) }) {
            let detail = try selectionRepairFeedback(for: request, requiredTargets: requiredTargets)
            return try invalidArguments(.init(message: "The named target was omitted. \(detail) Never replace a resolved target with workspace."),
                                        diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
        }
        if request.tool != .findRecords {
            let requirements = try currentNamedTargetRequirements().map { requirement in
                let chosen = requirement.candidates.filter { candidate in
                    clarificationCandidates.contains(candidate) && includes(candidate, in: request)
                        && (confirmedPendingSelection.contains(candidate) || turnPolicy.confirmsPendingCandidate(kind: candidate.kind, name: candidate.name,
                            candidates: clarificationCandidates.map { ($0.kind, $0.name) }, ambiguousSearch: clarificationSearch))
                }
                return chosen.count == 1 ? MarinaNamedTargetRequirement(search: chosen[0].name,
                    recordKind: chosen[0].kind, candidates: chosen) : requirement
            }
            if let ambiguous = requirements.first(where: \.isAmbiguous) {
                retainPendingRequest(request)
                return try invalidArguments(.init(message: "The current name \(ambiguous.search) matches competing records. Call findRecords to resolve that exact name and ask which record the person means; an earlier reference does not resolve this ambiguity."),
                                            diagnosticAttempt: diagnosticAttempt, alreadyCounted: true, tool: request.tool)
            }
            if let missing = requirements.first(where: { !$0.includes(in: request) }) {
                retainPendingRequest(request)
                let kind = missing.recordKind.map { " with kind \($0)" } ?? ""
                let detail = try selectionRepairFeedback(for: request, requiredTargets: requiredTargets)
                return try invalidArguments(.init(message: "The current question names \(missing.search). Resolve that name\(kind) using findRecords and include its selection; do not substitute an earlier target or workspace. \(detail)"),
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
        return try executeRead(request, diagnosticAttempt: diagnosticAttempt)
    }

    /// Shared execution boundary for model tools and app-compiled requests. The data
    /// service revalidates all identities, workspace membership and financial semantics.
    /// The compiled path resolves intent before arriving here; lexical policy must not
    /// rewrite its operation, dates or filters.
    private func executeRead(_ request: MarinaDataRequest, diagnosticAttempt: Int? = nil, preparedChoice: MarinaDataResult? = nil) throws -> String {
        try Task.checkCancellation()
        guard let service else { throw CancellationError() }
#if DEBUG
        var diagnosticOutput: String?
        var diagnosticStatus = "needsClarification"
        defer {
            if let diagnosticAttempt, let diagnosticOutput {
                diagnostics?.output(attempt: diagnosticAttempt, text: diagnosticOutput, status: diagnosticStatus)
            }
        }
#endif
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
        var result = try preparedChoice ?? service.execute(request)
        if request.tool == .findRecords { result.pendingRequest = pendingFinancialRequest }
        turnMemory?.record(request: request, result: result, answerID: turnAnswerID, prompt: turnPrompt)
        onValidatedResult?(request, result)
        if result.status == "invalidRequest" {
            argumentIssue = result.explanation ?? "The requested data could not be read."
            if request.tool != .findRecords {
                failedFinancialTool = request.tool
                if request.cardID != nil || request.categoryID != nil || request.budgetID != nil
                    || request.presetID != nil || request.accountID != nil || request.search != nil || request.merchantName != nil
                    || request.comparisonFilter != nil {
                    invalidReferenceTools.insert(request.tool)
                    repairableUnknownReferenceTools.remove(request.tool)
                }
            }
        }
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(result.status) {
            argumentIssue = nil
            failedFinancialTool = nil
            ambiguityDiscoveredThisTurn = true
            pendingCandidates = memory?.pendingClarification?.candidates ?? []
            clarificationCandidates = pendingCandidates
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
                clarificationOriginatingPrompt = memory?.pendingClarification?.originatingPrompt ?? clarificationOriginatingPrompt
                clarificationPeriod = memory?.pendingClarification?.period ?? clarificationPeriod
                clarificationSearch = memory?.pendingClarification?.search ?? clarificationSearch
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
                    if clarificationCandidates.contains(entity) { pendingCandidates = [] }
                    if !clarificationCandidates.contains(entity),
                       clarificationOriginatingPrompt == nil || turnPolicy.isExplicitFinancialQuestion {
                        pendingCandidates = []
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
            if kind == "workspace", id == currentMemory?.workspaceID.uuidString { return "workspace" }
            let referenceKind = result.status == "needsPeriodChoice" && kind == "budget" ? "periodBudget" : kind
            return currentMemory?.reference(forKind: referenceKind, id: id)
        }
        var facts = (try? JSONSerialization.jsonObject(with: Data(modelFacts.utf8))) as? [String: Any] ?? [:]
        facts["visualPresentation"] = display
        facts["resultReference"] = answerReference(for: results.count - 1)
        facts["resultReferences"] = answerResultIndices.enumerated().map { ordinal, index in
            let request = results[index].resolvedRequest ?? requests[index]
            var metadata = ["reference": "q\(ordinal)", "tool": request.tool.rawValue,
                "operation": request.operation.rawValue, "status": results[index].status,
                "scope": results[index].presentation?.scopeLabel ?? results[index].scope]
            metadata["purpose"] = request.purpose?.rawValue
            metadata["metric"] = request.metric?.rawValue
            if request.grouping != .none { metadata["grouping"] = request.grouping.rawValue }
            return metadata
        }
        facts["purpose"] = request.purpose?.rawValue
        facts["metric"] = request.metric?.rawValue
        let narrationEvidence = answerReference(for: results.count - 1).map {
            MarinaNarrationEvidence.facts(request: result.resolvedRequest ?? request, result: result, prefix: $0)
        } ?? []
        if request.tool != .findRecords, verified, !narrationEvidence.isEmpty {
            // The saved visual retains the complete report. The model needs the compact
            // authoritative propositions, not duplicate chart, metric and transaction arrays.
            for key in ["report", "reportIsPreview", "metrics", "records", "explanation"] { facts.removeValue(forKey: key) }
            if let policy = result.report?.policy,
               let encoded = try? JSONEncoder().encode(policy),
               let policyFacts = try? JSONSerialization.jsonObject(with: encoded) {
                facts["calculationPolicy"] = policyFacts
            }
        }
        let sharedScope = narrationEvidence.first?.scope ?? result.presentation?.scopeLabel ?? result.scope
        facts["scope"] = sharedScope
        facts["verifiedSummary"] = narrationEvidence.prefix(3).map { fact in
            var summary = ["subject": fact.subject, "relation": fact.relation, "value": fact.value]
            // Comparisons retain the other side's period; ordinary facts share one scope.
            if fact.scope != sharedScope { summary["scope"] = fact.scope }
            return summary
        }
        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
#if DEBUG
            diagnosticOutput = json
#endif
            if haltOnClarification && (["needsPeriodChoice", "needsBudgetChoice"].contains(result.status)
                || (request.tool == .findRecords && (result.status == "candidates" || (request.search != nil && result.status == "empty")))) {
                throw MarinaClarificationRequired()
            }
            return json
        }
#if DEBUG
        diagnosticOutput = modelFacts
#endif
        if haltOnClarification && (["needsPeriodChoice", "needsBudgetChoice"].contains(result.status)
            || (request.tool == .findRecords && (result.status == "candidates" || (request.search != nil && result.status == "empty")))) {
            throw MarinaClarificationRequired()
        }
        return modelFacts
    }

    private func retainPendingRequest(_ request: MarinaDataRequest) {
        pendingFinancialRequest = request
        guard memory?.pendingClarification != nil else { return }
        var pending = MarinaDataResult(status: "needsClarification", scope: service?.workspaceIdentity.name ?? "")
        pending.pendingRequest = request
        onValidatedResult?(request, pending)
    }

    private func lookupKindIsGrounded(_ kind: String, name: String) -> Bool {
        if kind == "workspace", turnPolicy.confirms(kind: kind),
           MarinaNamedTargetRequirement.containsLiteralName(name, in: turnPrompt) { return true }
        if clarificationCandidates.contains(where: {
            $0.kind == kind && MarinaNamedTargetRequirement.containsLiteralName(name, in: $0.name)
        }), turnPolicy.confirms(kind: kind) { return true }
        return (try? currentNamedTargetRequirements())?.contains {
            $0.recordKind == kind && MarinaNamedTargetRequirement.containsLiteralName(name, in: $0.search)
        } == true
    }

    private func lookupNameIsGrounded(_ name: String) -> Bool {
        guard !turnPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        if MarinaNamedTargetRequirement.containsLiteralName(name, in: turnPrompt) { return true }
        if clarificationCandidates.contains(where: {
            MarinaNamedTargetRequirement.containsLiteralName(name, in: $0.name)
                && turnPolicy.confirmsPendingCandidate(kind: $0.kind, name: $0.name,
                    candidates: clarificationCandidates.map { ($0.kind, $0.name) }, ambiguousSearch: clarificationSearch)
        }) { return true }
        if let original = clarificationOriginatingPrompt,
           turnPolicy.shouldRetainPendingPeriod(from: original),
           MarinaNamedTargetRequirement.containsLiteralName(name, in: original) { return true }
        guard let query = memory?.latestFinancialQuery, let selected = query.selection else { return false }
        let words = Set(turnPrompt.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        let refersToSelection = !words.isDisjoint(with: ["this", "that", "same", "previous", "selected", "esa", "ese", "misma", "mismo"])
        guard turnPolicy.isContextualFinancialFollowUp || refersToSelection else { return false }
        if let search = selected.merchantName ?? selected.search,
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
#if DEBUG
        Self.evaluationTrace("invalidArguments \(tool?.rawValue ?? "unknown")", error.message)
#endif
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
        let original = clarificationOriginatingPrompt.flatMap {
            turnPolicy.shouldRetainPendingPeriod(from: $0) ? $0 : nil
        }
        let requirements = try service.namedTargetRequirements(prompt: original ?? turnPrompt)
        cachedNamedTargetRequirements = requirements
        return requirements
    }

    private func selectionRepairFeedback(for request: MarinaDataRequest,
                                         requiredTargets: [MarinaConversationMemory.Entity]) throws -> String {
        // A repair must preserve the complete resolved scope. Naming only the missing
        // reference can make the model alternate between two individually valid targets.
        let unambiguous = try currentNamedTargetRequirements().filter { $0.candidates.count == 1 }.flatMap(\.candidates)
        var targets: [MarinaConversationMemory.Entity] = []
        for target in requiredTargets + unambiguous
        where Self.accepts(kind: target.kind, tool: request.tool) && !turnPolicy.ignoresSelection(kind: target.kind, for: request) {
            if !targets.contains(where: { $0.kind == target.kind && $0.id == target.id }) { targets.append(target) }
        }
        let references = targets.compactMap { memory?.reference(forKind: $0.kind, id: $0.id) }
        guard !references.isEmpty else { return "Resolve all requested targets before reading their data." }
        let selection = references.joined(separator: ",")
        if references.count == targets.count {
            return "Use selection \"\(selection)\" to keep all resolved targets together."
        }
        return "Keep selection \"\(selection)\" and add the remaining target references; do not replace these filters."
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
            request.chartIntent = request.chartIntent ?? query.chartIntent
            guard let selected = query.selection else {
                try requireToolArgument(query.tool == request.tool || selectionIsExplicitlyUniversal,
                                        "Previous financial query belongs to another topic. Choose workspace or copy a current reference explicitly.")
                try requireToolArgument(!invalidReferenceTools.contains(request.tool), "Resolve the failed reference before using an unfiltered previous selection.")
                if request.tool == .expenses && query.tool == .expenses {
                    request.expenseMeasure = query.measure ?? .budgetImpact
                    request.scope = query.scope ?? .all
                    request.includeFuture = query.includeFuture ?? false
                    if request.transactionFilter == nil { request.transactionFilter = query.transactionFilter }
                }
                return
            }
            var entities: [MarinaConversationMemory.Entity] = []
            func add(_ kind: String, _ id: String?) {
                if let id { entities.append(.init(kind: kind, id: id, name: id)) }
            }
            add("card", selected.cardID); add("category", selected.categoryID)
            for id in selected.categoryIDs ?? [] where id != selected.categoryID { add("category", id) }
            add("budget", selected.budgetID); add("preset", selected.presetID)
            if let id = selected.accountID {
                let kind = ["savingsAccount", "reconciliationAccount"].first { memory?.reference(forKind: $0, id: id) != nil }
                    ?? memory?.confirmedEntities.first { $0.id == id && ["savingsAccount", "reconciliationAccount"].contains($0.kind) }?.kind
                guard let kind else { throw MarinaToolArgumentError(message: "Resolve the previous account again before reading it.") }
                add(kind, id)
            }
            if let name = selected.merchantName {
                entities.append(.init(kind: "merchant", id: name, name: name))
            } else if let search = selected.search {
                if query.tool == .income { entities.append(.init(kind: "incomeSource", id: search, name: search)) }
                else { request.search = search } // Preserve legacy broad text filters as broad filters.
            }
            request.chartIntent = request.chartIntent ?? query.chartIntent
            try requireToolArgument(query.tool == request.tool || (!entities.isEmpty && entities.allSatisfy { turnPolicy.ignoresSelection(kind: $0.kind, for: request) }),
                                    "Previous financial query belongs to another topic. Choose workspace or copy a current reference explicitly.")
            try applyEntities(entities, to: &request)
            if request.tool == .expenses {
                request.expenseMeasure = query.measure ?? .budgetImpact
                request.scope = query.scope ?? .all
                request.includeFuture = query.includeFuture ?? false
                if request.transactionFilter == nil { request.transactionFilter = query.transactionFilter }
            }
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

    fileprivate func inheritExpenseContext(for request: inout MarinaDataRequest) {
        guard request.tool == .expenses, let previous = memory?.latestFinancialQuery,
              previous.tool == .expenses else { return }
        let selected = previous.selection
        let previousCategories = Set((selected?.categoryIDs ?? []) + [selected?.categoryID].compactMap { $0 })
        let requestedCategories = Set((request.categoryIDs ?? []) + [request.categoryID].compactMap { $0 })
        guard request.cardID == selected?.cardID, requestedCategories == previousCategories,
              request.budgetID == selected?.budgetID, request.presetID == selected?.presetID,
              request.accountID == selected?.accountID, request.search == selected?.search,
              request.merchantName == selected?.merchantName else { return }
        // A repeated validated target retains its calculation basis and filters whether
        // the model chooses its reference again or uses `previous`. Explicit arguments
        // override these defaults in the tool mapper; dates can change independently.
        request.expenseMeasure = previous.measure ?? request.expenseMeasure
        request.scope = previous.scope ?? .all
        request.includeFuture = previous.includeFuture ?? false
        request.transactionFilter = request.transactionFilter ?? previous.transactionFilter
        request.chartIntent = request.chartIntent ?? previous.chartIntent
    }

    private func applyEntities(_ entities: [MarinaConversationMemory.Entity], to request: inout MarinaDataRequest) throws {
        var kinds: Set<String> = []
        for entity in entities {
            if turnPolicy.ignoresSelection(kind: entity.kind, for: request) { continue }
            if entity.kind == "workspace" {
                try requireToolArgument(entity.id == memory?.workspaceID.uuidString, "This workspace reference belongs to another workspace.")
                continue
            }
            try requireToolArgument(Self.accepts(kind: entity.kind, tool: request.tool), "A \(entity.kind) reference cannot select \(request.tool.rawValue). Resolve the intended target.")
            let kind = ["savingsAccount", "reconciliationAccount"].contains(entity.kind) ? "account" : entity.kind
            try requireToolArgument(kinds.insert(kind).inserted || kind == "category", "Use at most one \(kind) reference in a selection.")
            switch entity.kind {
            case "card": request.cardID = entity.id
            case "category":
                if let first = request.categoryID, first != entity.id {
                    request.categoryIDs = Array(Set((request.categoryIDs ?? [first]) + [entity.id])).sorted()
                    request.categoryID = nil
                } else if request.categoryIDs != nil {
                    request.categoryIDs = Array(Set((request.categoryIDs ?? []) + [entity.id])).sorted()
                } else { request.categoryID = entity.id }
            case "periodBudget": request.periodBudgetID = entity.id
            case "budget":
                if memory?.pendingClarification?.reason == "needsPeriodChoice",
                   memory?.pendingClarification?.candidates.contains(where: { $0.id == entity.id }) == true {
                    request.periodBudgetID = entity.id
                } else { request.budgetID = entity.id }
            case "preset": request.presetID = entity.id
            case "merchant": request.merchantName = entity.name; request.search = nil
            case "incomeSource": request.search = entity.name
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
        case .expenses: ["workspace", "periodBudget", "card", "category", "budget", "preset", "merchant"].contains(kind)
        case .income: ["workspace", "periodBudget", "card", "budget", "incomeSource"].contains(kind)
        case .budgetSummary: ["workspace", "periodBudget", "card", "category", "budget"].contains(kind)
        case .accounts: ["workspace", "savingsAccount", "reconciliationAccount"].contains(kind)
        case .findRecords: false
        }
    }

    private func includes(_ entity: MarinaConversationMemory.Entity, in request: MarinaDataRequest) -> Bool {
        switch entity.kind {
        case "card": request.cardID == entity.id || request.comparisonFilter?.cardID == entity.id
        case "category": request.categoryID == entity.id || request.categoryIDs?.contains(entity.id) == true || request.comparisonFilter?.categoryID == entity.id || request.comparisonFilter?.categoryIDs?.contains(entity.id) == true
        case "budget": request.budgetID == entity.id || request.periodBudgetID == entity.id || request.comparisonFilter?.budgetID == entity.id
        case "periodBudget": request.periodBudgetID == entity.id
        case "workspace": memory?.workspaceID.uuidString == entity.id
        case "preset": request.presetID == entity.id || request.comparisonFilter?.presetID == entity.id
        case "merchant": request.merchantName == entity.name || request.comparisonFilter?.merchantName == entity.name
        case "incomeSource": request.search == entity.name || request.comparisonFilter?.search == entity.name
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
                guard let previous = memory?.pendingClarification?.period ?? memory?.latestFinancialQuery?.period else {
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

    func answer(id: UUID, prompt: String, narration: String, failureExplanation: String? = nil) -> HomeAnswer {
        let unresolvedChoice = confirmedPendingSelection.isEmpty ? results.indices.last {
            results[$0].status == "candidates" || ["needsPeriodChoice", "needsBudgetChoice"].contains(results[$0].status)
        } : nil
        let chosen = selectedResultIndices ?? unresolvedChoice.map { [$0] } ?? Array(results.indices.suffix(1))
        // Supporting reads validate an explanation. Only an explicitly requested extra
        // visual joins the primary presentation; evidence selection stays unchanged.
        let indices = chosen.enumerated().compactMap { position, index in
            position == 0 || requests[index].forcePresentation == true ? index : nil
        }
        let visible = indices.map { evidence[$0] }
        // Preserve typed, independently scoped results rather than flattening their UI.
        var presentations: [MarinaPresentation] = []
        for index in indices {
            let result = results[index]
            guard let presentation = result.presentation else { continue }
            let request = requests[index]
            if request.tool == .findRecords && request.search != nil && result.status != "candidates" { continue }
            if let existing = presentations.firstIndex(where: { $0.id == presentation.id }) {
                presentations[existing] = presentation
            } else { presentations.append(presentation) }
        }
        presentations = MarinaPresentationDisplayPolicy.coalesced(presentations)
        // Publish a verified fallback while the draft is in flight. A completed,
        // evidence-validated model composition can replace it without changing the visual.
        let verifiedNarration = chosen.prefix(1).compactMap { index in
            MarinaVerifiedNarration.text(request: requests[index], result: results[index])
        }
        var seenCaptions = Set<String>()
        let allFacts = selectedEvidence
        let validatedNarration = MarinaNarrationValidator.render(draft: narrationDraft, evidence: allFacts,
            requiresFinancialEvidence: requiresFreshRead || hasFinancialResults)
        let fallback = verifiedNarration.filter { seenCaptions.insert($0).inserted }.joined(separator: "\n\n")
        let conversationFallback: String
        switch narrationDraft?.act {
        case .greeting: conversationFallback = "Hi, I’m Marina, your Offshore budgeting assistant. What would you like to look at?"
        case .clarification, .help: conversationFallback = "Would you like to look at spending, category limits, income, or savings?"
        default: conversationFallback = narration
        }
        let explanation = resultSelectionRejected ? narration : hasInvalidRequest || (requiresFreshRead && !hasGroundedAnswer) ? ""
            : validatedNarration ?? (fallback.isEmpty ? (hasFinancialResults || requiresFreshRead ? "I couldn’t verify that explanation. The checked results are shown here." : conversationFallback) : fallback)
        let argumentNotice = argumentIssue.map { [HomeAnswerRow(title: $0, value: "", role: .assumption)] } ?? []
        var answer = HomeAnswer(id: id, queryID: id, kind: .message,
                          userPrompt: prompt, title: "", rows: visible.flatMap { $0.answer.rows } + argumentNotice,
                          explanation: failureExplanation ?? explanation, presentations: presentations)
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
@Generable enum MarinaChartIntent: String { case periodComparison, movementOverTime }
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
        var lookup: MarinaRecordLookup
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        MarinaToolBridge.evaluationTrace(name, arguments.generatedContent.jsonString)
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
    case summary, transactions, upcomingPresets, largestPurchase, smallestPurchase, cardSummary, nextPlannedExpense, spendingPatterns, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals
}
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaExpenseOperation: Generable, Sendable {
    case summary, transactions, upcomingPresets, largestPurchase, smallestPurchase, cardSummary, nextPlannedExpense, spendingPatterns, categoryTotals, cardTotals, merchantTotals, categoryShares, cardShares, merchantShares, periodTotals
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
            case .smallestPurchase: self = .smallestPurchase
            case .cardSummary: self = .cardSummary
            case .nextPlannedExpense: self = .nextPlannedExpense
            case .spendingPatterns: self = .spendingPatterns
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
        case .smallestPurchase: MarinaExpenseSimpleOperation.smallestPurchase.generatedContent
        case .cardSummary: MarinaExpenseSimpleOperation.cardSummary.generatedContent
        case .nextPlannedExpense: MarinaExpenseSimpleOperation.nextPlannedExpense.generatedContent
        case .spendingPatterns: MarinaExpenseSimpleOperation.spendingPatterns.generatedContent
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
        // Keep the framework's native string schema. The decoder enforces canonical
        // selection syntax; the bridge validates fresh records and workspace scope.
        String.generationSchema
    }
    private static let validationFeedback = "Selection must be one string: \"workspace\" for an unnamed or all-records scope; \"previous\" only for a relevant follow-up; otherwise copy exact references returned by findRecords, comma-separated without spaces or duplicates. Never invent references or use names, IDs, or an empty selection."

    init(_ content: GeneratedContent) throws {
#if DEBUG
        if ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
           ProcessInfo.processInfo.environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" {
            print("MarinaSelectionSynthetic content=\(content.jsonString)")
        }
#endif
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
@Generable enum MarinaIncomeSummaryKind: String { case summary, progress, timeline }
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
    case timeline
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
            case .timeline: self = .timeline
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
        case .timeline: MarinaIncomeSummaryKind.timeline.generatedContent
        case .transactions(let order, let offset): MarinaIncomeTransactions(order: order, offset: offset).generatedContent
        case .groups(let by, let offset): MarinaIncomeGroups(by: by, offset: offset).generatedContent
        case .periodTotals(let unit, let offset): MarinaPeriodPage(unit: unit, offset: offset).generatedContent
        case .compareIncome(let selection, let dates): MarinaIncomeComparisonOperation(compareIncome: .init(selection: selection, dates: dates)).generatedContent
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaExpensesTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readExpenses"
    let description = "Spending, purchases, rankings and patterns."
    typealias Arguments = ExpenseQueryArguments
    @Generable struct ExpenseQueryArguments {
        var operation: MarinaExpenseOperation
        var chartIntent: MarinaChartIntent? = nil
        var showVisual: Bool? = nil
        @Guide(description: "workspace, previous, or returned rN refs; never names.")
        var selection: MarinaSelection
        var dates: MarinaDateSelection
        var sort: MarinaDataSort?
        var periodUnit: MarinaPeriodUnit?
        var offset: Int?
        var scope: MarinaExpenseScope?
        var measure: MarinaExpenseMeasure?
        var includeFuture: Bool?
        var metric: MarinaRecordMetric? = nil
        var limit: Int? = nil
        var transactionFilter: MarinaTransactionFilter? = nil
        @Guide(description: "Compare each period's leader by this dimension.")
        var leadersBy: MarinaDataGrouping? = nil

        init(showVisual: Bool? = nil, selection: MarinaSelection, dates: MarinaDateSelection,
             operation: MarinaExpenseOperation, sort: MarinaDataSort? = nil, periodUnit: MarinaPeriodUnit? = nil,
             offset: Int? = nil, scope: MarinaExpenseScope? = nil, measure: MarinaExpenseMeasure? = nil,
             includeFuture: Bool? = nil) {
            self.showVisual = showVisual; self.selection = selection; self.dates = dates
            self.operation = operation
            self.sort = sort; self.periodUnit = periodUnit; self.offset = offset; self.scope = scope
            self.measure = measure; self.includeFuture = includeFuture
        }

        func validatedOperation() throws -> MarinaExpenseOperation {
            if case .compare = operation {
                if let leadersBy {
                    try requireToolArgument([.category, .card, .merchant].contains(leadersBy),
                        "Compare period leaders by category, card, or merchant.")
                }
            } else {
                try requireToolArgument(leadersBy == nil, "leadersBy requires the compare operation with selection and dates.")
            }
            return operation
        }
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        MarinaToolBridge.evaluationTrace(name, arguments.generatedContent.jsonString)
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .expenses)
            request.forcePresentation = arguments.showVisual
            try await bridge.applyDates(arguments.dates, to: &request)
            request.limit = min(50, max(1, arguments.limit ?? 5))
            request.offset = arguments.offset ?? 0
            request.metric = arguments.metric.flatMap { MarinaDataRequest.MetricFocus(rawValue: $0.rawValue) }
            request.transactionFilter = arguments.transactionFilter.flatMap { MarinaDataRequest.TransactionFilter(rawValue: $0.rawValue) }
            if request.metric == .averagePerPeriod { request.periodUnit = periodUnit(arguments.periodUnit) }
            switch try arguments.validatedOperation() {
            case .summary: request.operation = .summary
            case .upcomingPresets: request.purpose = .upcomingPresets
            case .largestPurchase: request.operation = .transactions; request.sort = .largest; request.limit = 1; request.positiveOnly = arguments.measure != .ledger
            case .smallestPurchase: request.operation = .transactions; request.sort = .smallest; request.limit = 1; request.positiveOnly = arguments.measure != .ledger
            case .cardSummary: request.purpose = .cardSummary
            case .nextPlannedExpense: request.purpose = .nextPlannedExpense
            case .spendingPatterns: request.purpose = .spendingPatterns; request.periodUnit = periodUnit(arguments.periodUnit)
            case .categoryShares: request.operation = .share; request.grouping = .category
            case .cardShares: request.operation = .share; request.grouping = .card
            case .merchantShares: request.operation = .share; request.grouping = .merchant
            case .transactions: request.operation = .transactions; request.sort = sort(arguments.sort)
            case .categoryTotals: request.operation = .ranking; request.grouping = .category; request.sort = arguments.sort == .smallest ? .smallest : .largest
            case .cardTotals: request.operation = .ranking; request.grouping = .card; request.sort = arguments.sort == .smallest ? .smallest : .largest
            case .merchantTotals: request.operation = .ranking; request.grouping = .merchant; request.sort = arguments.sort == .smallest ? .smallest : .largest
            case .periodTotals: request.operation = .trend; request.periodUnit = periodUnit(arguments.periodUnit)
            case .compare(let otherSelection, let otherDates):
                request.operation = .comparison
                if let by = arguments.leadersBy {
                    try requireToolArgument([MarinaDataGrouping.category, .merchant, .card].contains(by), "Compare leaders by category, merchant or card.")
                    request.compareLeaders = true
                    request.grouping = grouping(by)
                    request.sort = arguments.sort == .smallest ? .smallest : .largest
                    request.limit = 1
                }
                var selection = MarinaDataRequest(tool: .expenses)
                selection.operation = .comparison
                try await bridge.applySelection(otherSelection, to: &selection)
                request.comparisonFilter = .init(cardID: selection.cardID, categoryID: selection.categoryID, categoryIDs: selection.categoryIDs,
                                                 budgetID: selection.budgetID, presetID: selection.presetID, search: selection.search, merchantName: selection.merchantName)
                try await bridge.applyComparisonDates(otherDates, to: &request)
            }
            try await bridge.applySelection(arguments.selection, to: &request)
            await bridge.inheritExpenseContext(for: &request)
            try requireToolArgument(request.purpose != .cardSummary || request.cardID != nil,
                "cardSummary requires one selected card. For a breakdown across cards use cardTotals; for a combined total use summary. Preserve the requested scope instead of choosing a card arbitrarily.")
            if let intent = arguments.chartIntent { request.chartIntent = .init(rawValue: intent.rawValue) }
            switch arguments.scope { case .all: request.scope = .all; case .variable: request.scope = .variable; case .planned: request.scope = .planned; case nil: break }
            if let includeFuture = arguments.includeFuture { request.includeFuture = includeFuture }
            switch arguments.measure { case .budgetImpact: request.expenseMeasure = .budgetImpact; case .ledger: request.expenseMeasure = .ledger; case .spending: request.expenseMeasure = .spending; case .planned: request.expenseMeasure = .planned; case .actual: request.expenseMeasure = .actual; case nil: break }
            if request.positiveOnly != nil { request.positiveOnly = request.expenseMeasure != .ledger }
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
        var operation: MarinaIncomeOperation
        var chartIntent: MarinaChartIntent? = nil
        var showVisual: Bool? = nil
        @Guide(description: "workspace, previous, or returned rN refs; never names.")
        var selection: MarinaSelection
        var dates: MarinaDateSelection
        var state: MarinaIncomeState
        var metric: MarinaRecordMetric? = nil
        var periodUnit: MarinaPeriodUnit? = nil

        init(showVisual: Bool? = nil, selection: MarinaSelection, dates: MarinaDateSelection,
             state: MarinaIncomeState, operation: MarinaIncomeOperation) {
            self.showVisual = showVisual; self.selection = selection; self.dates = dates; self.state = state
            self.operation = operation
        }

        func validatedOperation() throws -> MarinaIncomeOperation { operation }
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        MarinaToolBridge.evaluationTrace(name, arguments.generatedContent.jsonString)
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .income)
            request.forcePresentation = arguments.showVisual
            request.metric = arguments.metric.flatMap { MarinaDataRequest.MetricFocus(rawValue: $0.rawValue) }
            if request.metric == .averagePerPeriod { request.periodUnit = periodUnit(arguments.periodUnit) }
            try await bridge.applyDates(arguments.dates, to: &request)
            switch arguments.state { case .planned: request.state = .planned; case .all: request.state = .all; case .actual: request.state = .actual }
            switch try arguments.validatedOperation() {
            case .summary: request.operation = .summary
            case .progress: request.purpose = .incomeProgress; request.state = .all
            case .timeline: request.purpose = .incomeTimeline; request.state = .all; request.periodUnit = periodUnit(arguments.periodUnit)
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
            if let intent = arguments.chartIntent { request.chartIntent = .init(rawValue: intent.rawValue) }
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
@Generable enum MarinaBudgetSummaryKind: String { case overview, pace, details, categoryAvailability, savingsOutlook, savingsTimeline, linkedCards, linkedPresets }
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaBudgetOperation: Generable, Sendable {
    case overview
    case pace
    case details, categoryAvailability, savingsOutlook, savingsTimeline, linkedCards, linkedPresets
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
            case .details: self = .details
            case .categoryAvailability: self = .categoryAvailability
            case .savingsOutlook: self = .savingsOutlook
            case .savingsTimeline: self = .savingsTimeline
            case .linkedCards: self = .linkedCards
            case .linkedPresets: self = .linkedPresets
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
        case .details: MarinaBudgetSummaryKind.details.generatedContent
        case .categoryAvailability: MarinaBudgetSummaryKind.categoryAvailability.generatedContent
        case .savingsOutlook: MarinaBudgetSummaryKind.savingsOutlook.generatedContent
        case .savingsTimeline: MarinaBudgetSummaryKind.savingsTimeline.generatedContent
        case .linkedCards: MarinaBudgetSummaryKind.linkedCards.generatedContent
        case .linkedPresets: MarinaBudgetSummaryKind.linkedPresets.generatedContent
        case .savingsTrend(let unit, let offset): MarinaPeriodPage(unit: unit, offset: offset).generatedContent
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaBudgetTool: Tool {
    let bridge: MarinaToolBridge
    let name = "readBudgetSummary"
    let description = "Period income/expenses, actual/projected savings, category limits and linked records."
    typealias Arguments = BudgetQueryArguments
    @Generable struct BudgetQueryArguments {
        var operation: MarinaBudgetOperation
        var chartIntent: MarinaChartIntent? = nil
        @Guide(description: "workspace, previous, or returned rN refs; never names.")
        var selection: MarinaSelection
        var showVisual: Bool? = nil
        var dates: MarinaDateSelection?
        var hypotheticalSpending: Double?
        var metric: MarinaMetricFocus? = nil
        var status: MarinaAvailabilityFilter? = nil
        var periodUnit: MarinaPeriodUnit? = nil

        init(selection: MarinaSelection, operation: MarinaBudgetOperation, showVisual: Bool? = nil,
             dates: MarinaDateSelection? = nil, hypotheticalSpending: Double? = nil,
             metric: MarinaMetricFocus? = nil, status: MarinaAvailabilityFilter? = nil,
             periodUnit: MarinaPeriodUnit? = nil, chartIntent: MarinaChartIntent? = nil) {
            self.selection = selection; self.operation = operation; self.showVisual = showVisual
            self.dates = dates; self.hypotheticalSpending = hypotheticalSpending; self.metric = metric
            self.status = status; self.periodUnit = periodUnit; self.chartIntent = chartIntent
        }
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        MarinaToolBridge.evaluationTrace(name, arguments.generatedContent.jsonString)
        let attempt = await bridge.diagnostics?.entered(tool: name, arguments: arguments.generatedContent.jsonString)
#endif
        do {
            var request = MarinaDataRequest(tool: .budgetSummary)
            request.forcePresentation = arguments.showVisual
            try await bridge.applyDates(arguments.dates, to: &request)
            try await bridge.applySelection(arguments.selection, to: &request)
            if let intent = arguments.chartIntent { request.chartIntent = .init(rawValue: intent.rawValue) }
            switch arguments.operation {
            case .overview: break
            case .pace: request.purpose = .budgetPace
            case .details: request.purpose = .budgetDetails
            case .categoryAvailability: request.purpose = .categoryAvailability
            case .savingsOutlook: request.purpose = .savingsOutlook
            case .savingsTimeline: request.purpose = .savingsTimeline; request.periodUnit = periodUnit(arguments.periodUnit)
            case .linkedCards: request.purpose = .budgetCards
            case .linkedPresets: request.purpose = .budgetPresets
            case .savingsTrend(let unit, let offset): request.periodUnit = periodUnit(unit); request.offset = offset
            }
            request.hypotheticalSpending = arguments.hypotheticalSpending
            request.metric = arguments.metric.flatMap { MarinaDataRequest.MetricFocus(rawValue: $0.rawValue) }
            request.availabilityFilter = arguments.status.flatMap { MarinaDataRequest.AvailabilityFilter(rawValue: $0.rawValue) }
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
        @Guide(description: "workspace, previous, or returned rN refs; never names.")
        var selection: MarinaSelection
        var showVisual: Bool? = nil
        var scope: MarinaAccountScope?
        var dates: MarinaDateSelection?
        var offset: Int?
    }
    func call(arguments: Arguments) async throws -> String {
#if DEBUG
        MarinaToolBridge.evaluationTrace(name, arguments.generatedContent.jsonString)
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
    init(message: String) {
        self.message = message
#if DEBUG
        if #available(iOS 26.0, macCatalyst 26.0, *) { MarinaToolBridge.evaluationTrace("argumentError", message) }
#endif
    }
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
