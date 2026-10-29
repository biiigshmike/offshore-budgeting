import Foundation

/// Retrieves request metadata, never financial results or an interpretation of the new turn.
/// The semantic step still chooses whether to continue one of these validated references.
nonisolated enum MarinaFrameRetrieval {
    static let maxEarlierFrames = 4

    /// The active frame comes first, followed by up to `limit` matching earlier frames.
    /// Equal relevance favors the oldest occurrence so repeated later questions cannot
    /// permanently hide the original topic. The hard bound is independent of history size.
    static func frames(for prompt: String, memory: MarinaConversationMemory,
                       history: [HomeAnswer], limit: Int = 4) -> [MarinaConversationMemory.CompletedFrame] {
        let frames = memory.completedFrames(in: history)
        let active: MarinaConversationMemory.CompletedFrame
        if let current = memory.latestCompletedFrame {
            guard let validated = frames.first(where: {
                $0.reference == current.reference && $0.answerID == current.answerID
            }) else { return [] }
            active = validated
        } else {
            guard let latest = frames.last else { return [] }
            active = latest
        }
        let count = min(max(0, limit), maxEarlierFrames)
        guard count > 0 else { return [active] }
        let query = tokens(prompt).sorted()
        guard !query.isEmpty else { return [active] }
        let documents = frames.map { tokens([$0.prompt, $0.scopeLabel].compactMap { $0 }.joined(separator: " ")) }
        var frequency: [String: Int] = [:]
        for document in documents {
            for term in document { frequency[term, default: 0] += 1 }
        }
        let weights = Dictionary(uniqueKeysWithValues: query.map { term in
            (term, log(Double(documents.count + 1) / Double(frequency[term, default: 0] + 1)) + 1)
        })
        let ranked = frames.enumerated().compactMap { index, frame -> (index: Int, score: Double)? in
            guard frame.reference != active.reference else { return nil }
            let score = query.reduce(0.0) { total, term in
                total + (documents[index].contains(term) ? weights[term, default: 0] : 0)
            }
            return score > 0 ? (index, score) : nil
        }.sorted { left, right in
            left.score == right.score ? left.index < right.index : left.score > right.score
        }
        return [active] + ranked.prefix(count).map { frames[$0.index] }
    }

    private static func tokens(_ text: String) -> Set<String> {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                      locale: Locale(identifier: "en_US_POSIX"))
        return Set(normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }
}
