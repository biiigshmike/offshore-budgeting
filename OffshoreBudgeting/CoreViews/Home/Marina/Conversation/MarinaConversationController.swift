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
        runtime = nil
        workspaceID = nil
        isResponding = false
    }

    func respond(
        prompt: String,
        answerID: UUID = UUID(),
        history: [HomeAnswer],
        workspace: Workspace,
        modelContext: ModelContext,
        homeContext: MarinaPanelHomeContext?,
        defaultBudgetingPeriod: BudgetingPeriod,
        onUpdate: @escaping (HomeAnswer) -> Void
    ) async {
        guard !isResponding else { return }
        if workspaceID != workspace.id { reset() }
        workspaceID = workspace.id
        let turn = UUID()
        generation = turn
        isResponding = true
        defer { if generation == turn { isResponding = false } }
        let emit: (HomeAnswer) -> Void = { [weak self] answer in
            guard let self, self.generation == turn, !Task.isCancelled else { return }
            onUpdate(answer)
        }
        if let message = availabilityMessage {
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
                                 answerID: answerID, onUpdate: emit)
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
