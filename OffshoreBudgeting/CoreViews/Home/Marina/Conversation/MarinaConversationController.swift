import Foundation
import Observation
import SwiftData

/// Owns a conversation, not a natural-language parser. Financial access is delegated to tools.
@MainActor
@Observable
final class MarinaConversationController {
    private(set) var isResponding = false
    private var availabilityRevision = 0
    @ObservationIgnored private var runtime: AnyObject?
    @ObservationIgnored private var workspaceID: UUID?
    @ObservationIgnored private var chatID: UUID?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var preparationID: UUID?
    @ObservationIgnored private var generation = UUID()

    func refreshAvailability() { availabilityRevision += 1 }

    var availabilityMessage: String? {
        _ = availabilityRevision
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return MarinaConversationRuntime.availabilityMessage
        }
        #endif
        return "Marina requires iOS 26 or later and Apple Intelligence."
    }

    func reset() {
        generation = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        runtime = nil
        workspaceID = nil
        chatID = nil
        isResponding = false
    }

    var memory: MarinaConversationMemory? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return (runtime as? MarinaConversationRuntime)?.memory
        }
        #endif
        return nil
    }

    @discardableResult
    func recordUIRead(request: MarinaDataRequest, result: MarinaDataResult, answerID: UUID,
                      workspaceID: UUID, chatID: UUID, restoredMemory: MarinaConversationMemory?) -> Bool {
        guard !isResponding, self.workspaceID == workspaceID, self.chatID == chatID else { return false }
        // A suspended preparation captured the previous page's memory. Cancel it before updating.
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *), let active = runtime as? MarinaConversationRuntime {
            return active.recordUIRead(request: request, result: result, answerID: answerID,
                workspaceID: workspaceID, chatID: chatID, restoredMemory: restoredMemory)
        }
        #endif
        return false
    }

    func prepare(history: [HomeAnswer], workspace: Workspace, homeContext: MarinaPanelHomeContext?,
                 defaultBudgetingPeriod: BudgetingPeriod, chatID: UUID,
                 restoredMemory: MarinaConversationMemory?) {
        guard !isResponding, availabilityMessage == nil else { return }
        if workspaceID != workspace.id || self.chatID != chatID { reset() }
        workspaceID = workspace.id
        self.chatID = chatID
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            guard preparationTask == nil else { return }
            let active = (runtime as? MarinaConversationRuntime) ?? MarinaConversationRuntime()
            runtime = active
            let preparation = UUID()
            preparationID = preparation
            preparationTask = Task { [weak self] in
                defer {
                    if self?.preparationID == preparation {
                        self?.preparationTask = nil
                        self?.preparationID = nil
                    }
                }
                await active.prepare(history: history, workspace: workspace, homeContext: homeContext,
                    defaultBudgetingPeriod: defaultBudgetingPeriod, chatID: chatID, restoredMemory: restoredMemory)
            }
        }
        #endif
    }

    func respond(
        prompt: String,
        answerID: UUID = UUID(),
        history: [HomeAnswer],
        workspace: Workspace,
        modelContext: ModelContext,
        homeContext: MarinaPanelHomeContext?,
        defaultBudgetingPeriod: BudgetingPeriod,
        chatID: UUID? = nil,
        restoredMemory: MarinaConversationMemory? = nil,
        onUpdate: @escaping (HomeAnswer) -> Void
    ) async {
        guard !isResponding else { return }
        if workspaceID != workspace.id || self.chatID != chatID { reset() }
        workspaceID = workspace.id
        self.chatID = chatID
        let turn = UUID()
        generation = turn
        isResponding = true
        defer { if generation == turn { isResponding = false } }
        let preparing = preparationTask
        preparing?.cancel()
        await preparing?.value
        guard generation == turn, !Task.isCancelled else { return }
        preparationTask = nil
        preparationID = nil
        let emit: (HomeAnswer) -> Void = { [weak self] answer in
            guard let self, self.generation == turn, !Task.isCancelled else { return }
            onUpdate(answer)
        }
        if let message = availabilityMessage {
#if DEBUG && canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                MarinaTokenDiagnostics.unavailable(historyCount: history.count, warning: MarinaContextStatus.status(in: history))
            }
#endif
            var answer = Self.message(message, prompt: prompt, id: answerID)
            answer.responseState = .unavailable
            emit(answer)
            return
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let active: MarinaConversationRuntime
            if let existing = runtime as? MarinaConversationRuntime {
                active = existing
            } else {
                active = MarinaConversationRuntime()
                runtime = active
            }
            await active.respond(prompt: prompt, history: history, workspace: workspace,
                                 modelContext: modelContext, homeContext: homeContext,
                                 defaultBudgetingPeriod: defaultBudgetingPeriod,
                                 answerID: answerID, chatID: chatID, restoredMemory: restoredMemory, onUpdate: emit)
        }
        #endif
    }

    static func message(_ text: String, prompt: String, id: UUID) -> HomeAnswer {
        HomeAnswer(id: id, queryID: id, kind: .message, userPrompt: prompt,
                   title: "", explanation: text)
    }
}

/// Bounded visible exchanges restore context without persisting model internals or old query plans.
enum MarinaConversationHistory {
    static func recent(_ answers: [HomeAnswer], characterBudget: Int = 2400) -> [(prompt: String, response: String)] {
        var remaining = characterBudget
        var exchanges: [(prompt: String, response: String)] = []
        for answer in answers.reversed() {
            guard answer.responseState == nil || answer.responseState == .complete else { continue }
            guard let prompt = answer.userPrompt, !prompt.isEmpty else { continue }
            var facts: [String] = []
            if let presentations = answer.presentations {
                for presentation in presentations.suffix(2) {
                    facts.append(presentation.title + " · " + presentation.scopeLabel)
                    for metric in presentation.metrics.prefix(2) {
                        facts.append(metric.label + ": " + metric.formatted)
                    }
                    for record in presentation.records.prefix(2) {
                        let amount = record.amount.map { CurrencyFormatter.string(from: $0) } ?? ""
                        facts.append(record.title + ": " + amount)
                    }
                }
            } else {
                facts = answer.rows.prefix(3).map { $0.title + ": " + $0.value }
            }
            let response = ([answer.title, answer.subtitle, answer.primaryValue, answer.explanation]
                .compactMap { $0 }.filter { !$0.isEmpty } + facts).joined(separator: "\n")
            guard prompt.count + response.count <= remaining else { break }
            exchanges.append((prompt, response))
            remaining -= prompt.count + response.count
            if exchanges.count == 4 { break }
        }
        return exchanges.reversed()
    }
}
