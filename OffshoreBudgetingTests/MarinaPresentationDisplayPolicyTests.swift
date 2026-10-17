import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaPresentationDisplayPolicyTests {
    private func result(_ topic: String = "budget", scope: String = "month", value: Double = 100.38) -> MarinaPresentation {
        .init(id: UUID().uuidString, identityKey: "\(topic):\(scope)", topicKey: topic,
              operation: .summary, title: topic, scopeLabel: scope,
              metrics: [.init(label: "Total", value: value)])
    }

    @Test func unchangedFollowupsAreSuppressedButScopeValuesAndTopicChangesShow() {
        let budget = result()
        #expect(MarinaPresentationDisplayPolicy.shouldShow(budget, after: []))
        #expect(!MarinaPresentationDisplayPolicy.shouldShow(result(), after: [budget]))
        #expect(MarinaPresentationDisplayPolicy.shouldShow(result(scope: "last month"), after: [budget]))
        #expect(MarinaPresentationDisplayPolicy.shouldShow(result(value: 101.38), after: [budget]))
        let income = result("income")
        #expect(MarinaPresentationDisplayPolicy.shouldShow(income, after: [budget]))
        #expect(!MarinaPresentationDisplayPolicy.shouldShow(result("income"), after: [income]))
        #expect(MarinaPresentationDisplayPolicy.shouldShow(budget, after: [income]))
    }

    @Test func explicitVisualsListsAndLegacyResultsAlwaysShow() {
        var current = result()
        let previous = current
        current.forcePresentation = true
        #expect(MarinaPresentationDisplayPolicy.shouldShow(current, after: [previous]))
        current.forcePresentation = nil
        for operation in [MarinaDataRequest.Operation.transactions, .inventory] {
            current.operation = operation
            #expect(MarinaPresentationDisplayPolicy.shouldShow(current, after: [current]))
        }
        current.operation = .summary
        current.identityKey = nil
        #expect(MarinaPresentationDisplayPolicy.shouldShow(current, after: [current]))
    }

    @Test func savedSuppressionKeepsVerifiedDataAndFailureRestoresVisual() throws {
        let presentation = result()
        var answer = HomeAnswer(queryID: UUID(), kind: .message, title: "", presentations: [presentation], responseState: .complete)
        answer.suppressedPresentationIDs = [presentation.id]
        let restored = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(answer))
        #expect(restored.presentations == [presentation])
        #expect(!MarinaPresentationDisplayPolicy.isVisible(presentation, in: restored))
        let explanation = HomeAnswer(queryID: UUID(), kind: .message, title: "", presentations: [])
        #expect(MarinaPresentationDisplayPolicy.previousResults(in: [restored, explanation]) == [presentation])
        for failure in [MarinaResponseState.generationFailed, .contextLimit, .invalidRequest, .cancelled] {
            answer.responseState = failure
            #expect(MarinaPresentationDisplayPolicy.isVisible(presentation, in: answer))
        }
        #expect(MarinaPresentationDisplayPolicy.previousResults(in: []).isEmpty)
    }

    @Test func repeatedToolResultsCoalesceWithoutLosingDifferentScopesOrValues() {
        let first = result()
        let duplicate = result()
        let changed = result(value: 101.38)
        let otherScope = result(scope: "last month")
        let merged = MarinaPresentationDisplayPolicy.coalesced([first, duplicate, changed, otherScope])
        #expect(merged.count == 3)
        #expect(merged.first?.id == first.id)
        #expect(merged.contains { $0.id == changed.id })
        #expect(merged.contains { $0.id == otherScope.id })
    }

    @Test func nonFinancialMetadataDoesNotRetriggerVisual() {
        let original = result()
        var changed = original
        changed.id = UUID().uuidString
        changed.isUpdated = true
        changed.forcePresentation = false
        #expect(!MarinaPresentationDisplayPolicy.shouldShow(changed, after: [original]))
    }
}
