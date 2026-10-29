import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// A turn-local transaction. Reads may update working references, but only a selected
/// verified answer or a saved clarification is returned for the runtime to commit.
@available(iOS 26.0, macCatalyst 26.0, *)
@MainActor
final class MarinaCompiledTurn {
    struct Outcome {
        var answer: HomeAnswer
        var memory: MarinaConversationMemory?
        var error: String?
        var primaryReference: String?
        var queryDuration: Duration
    }

    enum InterpretationStage: String { case selection, patch }
    struct Interpretation {
        var choice: MarinaRequestTranslator.Choice
        var compilation: MarinaRequestCompiler.Compilation?
    }

    /// One repair is shared by the two tool-free stages. Once a choice succeeds,
    /// a patch or compiler failure can only repair that choice's parameters.
    /// Closures keep this orchestration testable without invoking the native model.
    static func interpret(
        select: (String) async throws -> MarinaRequestTranslator.Choice,
        patchAndCompile: (MarinaRequestTranslator.Choice, String) async throws -> MarinaRequestCompiler.Compilation,
        onRepair: (InterpretationStage, String) -> Void = { _, _ in },
        onDuration: (Duration) -> Void = { _ in }
    ) async throws -> Interpretation {
        var choice: MarinaRequestTranslator.Choice?
        var feedback = ""
        var usedRepair = false
        while true {
            do {
                let started = ContinuousClock.now
                // This callback completes before interpret returns, including for
                // conversational choices and failures, so Outcome sees the duration.
                defer { onDuration(started.duration(to: .now)) }
                try Task.checkCancellation()
                if let choice {
                    let compilation = try await patchAndCompile(choice, feedback)
                    try Task.checkCancellation()
                    return .init(choice: choice, compilation: compilation)
                }
                let selected = try await select(feedback)
                try Task.checkCancellation()
                choice = selected
                feedback = ""
                if selected.hasAdditionalGoals || selected.goals.count != 1
                    || MarinaCapability(rawValue: selected.goal) == nil {
                    return .init(choice: selected, compilation: nil)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw error }
                guard !usedRepair else { throw error }
                usedRepair = true
                let stage: InterpretationStage = choice == nil ? .selection : .patch
                feedback = "\nThe previous \(stage.rawValue) was invalid: \(error.localizedDescription). Correct this stage using only the current question and supplied context."
                onRepair(stage, error.localizedDescription)
            }
        }
    }

    private let service: MarinaReadOnlyDataService
    private let bridge: MarinaToolBridge
    private let originalMemory: MarinaConversationMemory
    private var working: MarinaConversationMemory
    private let history: [HomeAnswer]
    private let prompt: String
    private let answerID: UUID
    private let now: Date
    private let budget: MarinaContextBudget
    private let onUpdate: (HomeAnswer) -> Void
    private let narrate: (MarinaNarrationAct, String, [MarinaNarrationEvidence]) async -> MarinaNarrationDraft
    private var state: MarinaResponseState = .thinking
    private var narration = ""
    private var queryDuration: Duration = .zero
    private var primaryReference: String?
    private var frame: MarinaConversationMemory.CompletedFrame?
    private var freshEntities: [MarinaConversationMemory.Entity] = []
    private var referenceEntities: [MarinaRequestCompiler.Entity] = []
    private var offeredFrames: [MarinaConversationMemory.CompletedFrame] = []

    init(service: MarinaReadOnlyDataService, bridge: MarinaToolBridge, memory: MarinaConversationMemory,
         history: [HomeAnswer], prompt: String, answerID: UUID, now: Date, budget: MarinaContextBudget,
         onUpdate: @escaping (HomeAnswer) -> Void,
         narrate: @escaping (MarinaNarrationAct, String, [MarinaNarrationEvidence]) async -> MarinaNarrationDraft) {
        self.service = service; self.bridge = bridge; originalMemory = memory; working = memory
        self.history = history; self.prompt = prompt; self.answerID = answerID; self.now = now
        self.budget = budget; self.onUpdate = onUpdate; self.narrate = narrate
        working.restoreCompletedFrames(from: history)
    }

    func run() async -> Outcome {
        bridge.begin(service: service, history: history, prompt: prompt, memory: working, compiled: true) { [weak self] in self?.publish() }
        bridge.requiresFreshRead = true
        bridge.conversationMemory = { [weak self] in self?.working }
        bridge.onValidatedResult = { [weak self] request, result in
            guard let self else { return }
            self.working.record(request: request, result: result, answerID: self.answerID, prompt: self.prompt)
        }
        bridge.onStatus = { [weak self] status in self?.state = status; self?.publish() }
        defer { bridge.end() }
        publish()
        do {
            freshEntities = try service.compiledEntityCatalog()
            offeredFrames = MarinaFrameRetrieval.frames(for: prompt, memory: working, history: history)
            prepareReferences()
            if let pending = working.pendingClarification,
               let candidate = exactCandidate(in: pending.candidates),
               var compilation = pending.compilation {
                guard let live = freshEntities.first(where: { $0.id == candidate.id && $0.kind == (candidate.kind == "periodBudget" ? "budget" : candidate.kind) }),
                      live.name.compare(candidate.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
                    return clarification("That selection has changed or is no longer in this workspace. Please choose it again.", commit: false)
                }
                compilation = try resolvePending(live, pending: pending, compilation: compilation)
                return try await execute(compilation, question: pending.originatingPrompt ?? prompt)
            }

            let interpretation = try await Self.interpret(select: { feedback in
                let choice = try await MarinaRequestTranslator.select(prompt: self.prompt,
                    contextText: self.selectionContext() + feedback, allowedBases: self.allowedBases, budget: self.budget)
                self.trace("choice", choice.goals.joined(separator: ",") + " base=" + choice.base)
                return choice
            }, patchAndCompile: { choice, feedback in
                guard let capability = MarinaCapability(rawValue: choice.goal) else {
                    throw TurnError.invalid("Choose a supported financial answer.")
                }
                let patchResult = try await MarinaRequestTranslator.patch(choice: choice, capability: capability,
                    prompt: self.prompt, contextText: self.patchContext(base: choice.base) + feedback,
                    entityReferences: self.referenceEntities.map(\.reference), allowedBases: self.allowedBases, budget: self.budget)
                return try MarinaRequestCompiler.compile(patchResult.patch, context: self.compilerContext())
            }, onRepair: { stage, message in
                self.state = .recovering; self.publish()
                self.trace("repair-" + stage.rawValue, message)
            }, onDuration: { self.queryDuration += $0 })
            let choice = interpretation.choice
            if choice.goals.count != 1 || choice.hasAdditionalGoals {
                return clarification("Which part would you like me to focus on first? I can look at spending, income, category limits, or savings.", commit: false)
            }
            guard let compiled = interpretation.compilation else {
                guard let act = MarinaNarrationAct(rawValue: choice.goal), act != .answer else {
                    throw TurnError.invalid("Choose a supported answer.")
                }
                bridge.requiresFreshRead = false
                bridge.narrationDraft = await narrate(act, prompt, [])
                try Task.checkCancellation()
                state = .complete
                return outcome(memory: originalMemory)
            }
            let rootQuestion = choice.base == "pending" ? working.pendingClarification?.originatingPrompt ?? prompt : prompt
            if choice.base == "newQuestion" { working.discardPendingClarification() }
            trace("compiled", json(compiled))
            return try await execute(compiled, question: rootQuestion)
        } catch {
            state = .invalidRequest
            bridge.requiresFreshRead = false
            if Task.isCancelled {
                narration = ""
            } else if let failure = error as? TurnError, case .contextLimit(let message) = failure {
                narration = message
            } else {
                narration = "I couldn’t reliably interpret that question. Please clarify the report or selection you mean."
            }
            bridge.narrationDraft = nil
            trace("failure", String(describing: error))
            return outcome(memory: nil, error: String(describing: error))
        }
    }

    private func execute(_ initial: MarinaRequestCompiler.Compilation, question: String) async throws -> Outcome {
        var compiled = initial
        while true {
            // Resolve each independent window before any name clarification. Repeat
            // after resolving a budget so subsequent target choices keep its dates.
            var deferredSides = Set(compiled.unresolvedTargets.filter {
                [.budget, .periodBudget].contains($0.field)
            }.map { $0.isComparison ? MarinaRequestCompiler.DateSide.comparison : .primary })
            if deferredSides.contains(.primary), compiled.comparisonUsesPrimarySelection {
                deferredSides.insert(.comparison)
            }
            let prepared = try service.prepareCompiledDates(compiled.request, deferringBudgetSides: deferredSides)
            let dated = prepared.result
            if let request = dated.resolvedRequest { compiled.request = request }
            compiled.pendingDateSide = prepared.pendingDateSide
            if ["needsPeriodChoice", "needsBudgetChoice"].contains(dated.status) {
                try bridge.presentCompiledDateChoice(dated, request: compiled.request)
                guard working.saveCompiledClarification(compilation: compiled, result: dated,
                    answerID: answerID, prompt: question, search: nil) else { throw TurnError.invalid("The pending question is too large to save.") }
                return clarification(nil, commit: true)
            }
            guard dated.status == "ready", dated.resolvedRequest != nil else {
                throw TurnError.invalid(dated.explanation ?? "The dates could not be resolved.")
            }
            guard let target = compiled.unresolvedTargets.first else { break }
            try Task.checkCancellation()
            var lookup = MarinaDataRequest(operation: .inventory, tool: .findRecords)
            lookup.allTime = true; lookup.search = target.name; lookup.limit = 20
            // Search across types first. A model-chosen type cannot hide a genuine
            // same-name collision; a confirmed typed candidate can resolve it.
            let result = try bridge.executeCompiledRead(lookup, pendingRequest: compiled.request)
            guard result.status == "success", result.totalCount == 1, let record = result.records.first else {
                guard working.saveCompiledClarification(compilation: compiled, result: result,
                    answerID: answerID, prompt: question, search: target.name) else { throw TurnError.invalid("The pending question is too large to save.") }
                return clarification(result.status == "empty" ? "I couldn’t find “\(target.name)” in your current workspace. Which record did you mean?" : nil, commit: true)
            }
            let entity = MarinaConversationMemory.Entity(kind: record.kind, id: record.id, name: record.title)
            let reference = try register(entity)
            compiled = try MarinaRequestCompiler.resolving(target.id, with: reference, in: compiled, context: compilerContext())
        }
        bridge.requiresFreshRead = compiled.request.tool != .findRecords
        let started = ContinuousClock.now
        let result = try bridge.executeCompiledRead(compiled.request)
        queryDuration += started.duration(to: .now)
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(result.status) {
            guard working.saveCompiledClarification(compilation: compiled, result: result,
                answerID: answerID, prompt: question, search: nil) else { throw TurnError.invalid("The pending question is too large to save.") }
            return clarification(nil, commit: true)
        }
        guard ["success", "empty"].contains(result.status), let selected = bridge.selectCompiledResult() else {
            throw TurnError.invalid(result.explanation ?? "The financial request did not produce verified evidence.")
        }
        primaryReference = selected
        state = .responding; publish()
        bridge.narrationDraft = await narrate(.answer, question, bridge.selectedEvidence)
        try Task.checkCancellation()
        if compiled.request.tool != .findRecords {
            guard let completed = working.commitCompletedFrame(request: compiled.request, result: result,
                answerID: answerID, prompt: question, dateOrigin: compiled.dateOrigin),
                  working.latestCompletedFrame == completed else {
                throw TurnError.contextLimit("This answer exceeds Marina’s saved context limit. Please simplify the selection or start a new chat before continuing.")
            }
            frame = completed
        }
        state = .complete
        return outcome(memory: working)
    }

    private func resolvePending(_ candidate: MarinaConversationMemory.Entity,
                                pending: MarinaConversationMemory.Clarification,
                                compilation: MarinaRequestCompiler.Compilation) throws -> MarinaRequestCompiler.Compilation {
        var result = compilation
        if ["needsPeriodChoice", "needsBudgetChoice"].contains(pending.reason) {
            if result.pendingDateSide == .comparison {
                var periodRequest = MarinaDataRequest(tool: .expenses)
                periodRequest.periodBudgetID = candidate.id
                periodRequest.relativePeriod = result.request.comparisonPeriod
                let prepared = try service.prepareCompiledDates(periodRequest)
                guard prepared.status == "ready", let dates = prepared.resolvedRequest,
                      let start = dates.startDate, let end = dates.endDate else {
                    throw TurnError.invalid("The comparison period is no longer available. Please choose its dates again.")
                }
                result.request.comparisonPeriod = nil
                result.request.comparisonStartDate = start
                result.request.comparisonEndDate = end
                result.request.comparisonAllTime = false
                if pending.reason == "needsBudgetChoice" {
                    if result.request.comparisonFilter == nil { result.request.comparisonFilter = .init() }
                    result.request.comparisonFilter?.budgetID = candidate.id
                    result.comparisonUsesPrimarySelection = false
                }
                result.pendingDateSide = nil
                return result
            }
            if pending.reason == "needsPeriodChoice" { result.request.periodBudgetID = candidate.id }
            else { result.request.budgetID = candidate.id }
            if result.dateOrigin != .explicit {
                result.request.relativePeriod = nil; result.request.startDate = nil; result.request.endDate = nil
                result.request.allTime = false
            }
            result.pendingDateSide = nil
            return result
        }
        guard let target = result.unresolvedTargets.first else { throw TurnError.invalid("There is no pending target to fill.") }
        let reference = try register(candidate)
        return try MarinaRequestCompiler.resolving(target.id, with: reference, in: result, context: compilerContext())
    }

    private func exactCandidate(in candidates: [MarinaConversationMemory.Entity]) -> MarinaConversationMemory.Entity? {
        let exact = candidates.filter { $0.name.compare(prompt.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if exact.count == 1 { return exact[0] }
        guard exact.isEmpty else { return nil }
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let normalizedMatches = candidates.filter { normalized($0.name) == normalized(prompt) }
        return normalizedMatches.count == 1 ? normalizedMatches[0] : nil
    }

    private var allowedBases: [String] {
        ["newQuestion"] + (activeRequest == nil ? [] : ["active"])
            + (working.pendingClarification?.pendingRequest == nil ? [] : ["pending"])
            + offeredFrames.map(\.reference)
    }
    private var activeRequest: MarinaDataRequest? { working.latestCompletedFrame?.request ?? working.latestFinancialQuery?.request }

    private func compilerContext() -> MarinaRequestCompiler.Context {
        .init(workspaceID: working.workspaceID, prompt: prompt, now: now,
              activeRequest: activeRequest,
              earlierRequests: Dictionary(uniqueKeysWithValues: offeredFrames.map { ($0.reference, $0.request) }),
              pendingRequest: working.pendingClarification?.pendingRequest,
              pendingCompilation: working.pendingClarification?.compilation, entities: referenceEntities,
              activeDateOrigin: working.latestCompletedFrame?.dateOrigin ?? .explicit,
              earlierDateOrigins: Dictionary(uniqueKeysWithValues: offeredFrames.map { ($0.reference, $0.dateOrigin ?? .explicit) }),
              pendingDateOrigin: working.pendingClarification?.dateOrigin ?? .explicit,
              validatedContextReferences: Set(allowedBases.filter { $0 != "newQuestion" }))
    }

    private func prepareReferences() {
        var identities = Set((working.confirmedEntities + (working.pendingClarification?.candidates ?? [])).map { $0.kind + ":" + $0.id })
        for request in offeredFrames.map(\.request) + [activeRequest].compactMap({ $0 }) {
            for (kind, id) in [("card", request.cardID), ("budget", request.budgetID), ("budget", request.periodBudgetID),
                               ("category", request.categoryID), ("preset", request.presetID)] {
                if let id { identities.insert(kind + ":" + id) }
            }
            for id in request.categoryIDs ?? [] { identities.insert("category:" + id) }
            if let name = request.merchantName { identities.insert("merchant:" + name) }
        }
        // An old reference that can no longer be represented must not be offered.
        // A target selected for this turn is registered separately and fails closed.
        for entity in freshEntities where identities.contains(entity.kind + ":" + entity.id) { _ = try? register(entity) }
    }

    @discardableResult
    private func register(_ entity: MarinaConversationMemory.Entity) throws -> String {
        let reference = working.reference(for: entity)
        guard reference.first == "r", let number = Int(reference.dropFirst()),
              number > 0, number < Int.max - 1, reference == "r\(number)",
              working.entity(forReference: reference) == entity else {
            throw TurnError.contextLimit("That selection is too large for Marina’s saved context. Please view the record in the app or ask about a broader group.")
        }
        referenceEntities.removeAll { $0.reference == reference }
        referenceEntities.append(.init(reference: reference, workspaceID: working.workspaceID,
                                       kind: entity.kind, id: entity.id, name: entity.name))
        return reference
    }

    private func selectionContext() -> String {
        let descriptors = working.completedFrameDescriptors(history: history).filter { descriptor in
            offeredFrames.contains { $0.reference == descriptor.reference }
        }
        return "Bound workspace: \(json(service.workspaceIdentity.name)); today: \(now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).\nActive request: \(json(activeRequest))\nEarlier answers: \(json(descriptors))\nPending question: \(json(working.pendingClarification?.originatingPrompt))\nLatest exchange: \(json(history.last?.userPrompt))"
    }

    private func patchContext(base: String) -> String {
        let request = base == "active" ? activeRequest : base == "pending" ? working.pendingClarification?.pendingRequest
            : offeredFrames.first { $0.reference == base }?.request
        struct Ref: Encodable { let reference: String; let kind: String; let name: String }
        let refs = referenceEntities.map { Ref(reference: $0.reference, kind: $0.kind, name: $0.name) }
        return "Bound workspace: \(json(service.workspaceIdentity.name)); today: \(now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).\nBase request: \(json(request))\nAvailable entities: \(json(refs))\nPending question: \(json(working.pendingClarification?.originatingPrompt))"
    }

    private func clarification(_ text: String?, commit: Bool) -> Outcome {
        bridge.requiresFreshRead = false
        if let text { narration = text; bridge.narrationDraft = nil }
        state = .complete
        return outcome(memory: commit ? working : originalMemory)
    }
    private func outcome(memory: MarinaConversationMemory?, error: String? = nil) -> Outcome {
        var answer = bridge.answer(id: answerID, prompt: prompt, narration: narration,
                                   failureExplanation: state == .invalidRequest && !narration.isEmpty ? narration : nil)
        answer.responseState = state; answer.contextStatus = nil; answer.completedFrame = frame
        return .init(answer: answer, memory: memory, error: error, primaryReference: primaryReference, queryDuration: queryDuration)
    }
    private func publish() { onUpdate(outcome(memory: nil).answer) }
    private func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
    private func trace(_ stage: String, _ value: String) {
#if DEBUG
        if ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1" {
            print("MARINA_TRANSLATION \(stage): \(value.prefix(6000))")
        }
#endif
    }
    private enum TurnError: LocalizedError {
        case invalid(String)
        case contextLimit(String)
        var errorDescription: String? {
            switch self { case .invalid(let message), .contextLimit(let message): message }
        }
    }
}
#endif
