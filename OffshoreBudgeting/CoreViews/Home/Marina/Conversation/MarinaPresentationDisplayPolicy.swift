import Foundation

/// Presentation-only comparison of verified snapshots, not conversational query state.
enum MarinaPresentationDisplayPolicy {
    static func previousResults(in history: [HomeAnswer]) -> [MarinaPresentation] {
        history.reversed().compactMap(\.presentations).first(where: { !$0.isEmpty }) ?? []
    }

    static func shouldShow(_ current: MarinaPresentation, after previous: [MarinaPresentation]) -> Bool {
        // Requested records and clarification choices must remain visible.
        guard current.forcePresentation != true,
              current.operation != .transactions, current.operation != .inventory,
              let identity = current.identityKey,
              let prior = previous.first(where: { $0.identityKey == identity && $0.topicKey == current.topicKey }) else { return true }
        return displayValues(current) != displayValues(prior)
    }

    static func coalesced(_ presentations: [MarinaPresentation]) -> [MarinaPresentation] {
        presentations.reduce(into: []) { unique, candidate in
            let duplicate = candidate.identityKey != nil && unique.contains {
                $0.identityKey == candidate.identityKey && displayValues($0) == displayValues(candidate)
            }
            if !duplicate { unique.append(candidate) }
        }
    }

    static func isVisible(_ presentation: MarinaPresentation, in answer: HomeAnswer) -> Bool {
        switch answer.responseState {
        case .generationFailed, .contextLimit, .invalidRequest, .cancelled, .unavailable: return true
        default: return !(answer.suppressedPresentationIDs ?? []).contains(presentation.id)
        }
    }

    private static func displayValues(_ presentation: MarinaPresentation) -> MarinaPresentation {
        var values = presentation
        values.id = ""
        values.pagination = nil
        values.isUpdated = false
        values.forcePresentation = nil
        return values
    }
}
