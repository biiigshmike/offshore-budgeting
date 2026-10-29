import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// The query session chooses verified results. It never writes the financial explanation.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
struct MarinaQueryOutcome {
    var act: MarinaNarrationAct
    @Guide(description: "Answer first; empty for conversation.", .maximumCount(3))
    var results: [MarinaQueryResultReference]

    var primary: MarinaQueryResultReference? { results.first }
    var supporting: [MarinaQueryResultReference] { Array(results.dropFirst()) }

    init(act: MarinaNarrationAct, primary: MarinaQueryResultReference?, supporting: [MarinaQueryResultReference]) {
        self.act = act
        results = (primary.map { [$0] } ?? []) + supporting
    }

    var hasValidReferenceShape: Bool { results.count <= 3 }

    /// Repeating a checked result adds no information. Drop only exact duplicates;
    /// invalid or unknown references still reach the normal validation boundary.
    var normalizedSupporting: [String] {
        var seen = Set(primary.map { [$0.rawValue] } ?? [])
        return supporting.map(\.rawValue).filter { seen.insert($0).inserted }
    }

    /// A conversational turn with no reads has no result to select. Ignore unused
    /// generated references only after the app rules out a financial answer/read.
    func normalizedConversation(hasToolResults: Bool, requiresFreshRead: Bool) -> MarinaQueryOutcome? {
        guard act != .answer, hasValidReferenceShape, !hasToolResults, !requiresFreshRead else { return nil }
        return .init(act: act, primary: nil, supporting: [])
    }
}

/// The bridge permits at most eight calls per turn. Generation can only choose one
/// of those bounded result identifiers; the bridge then verifies it exists now.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
enum MarinaQueryResultReference: String, CaseIterable {
    case q0, q1, q2, q3, q4, q5, q6, q7
}
#endif
