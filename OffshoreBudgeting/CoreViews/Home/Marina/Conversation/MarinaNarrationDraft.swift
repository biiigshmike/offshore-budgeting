import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// A tool-free composition over the query phase's selected, verified evidence.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
struct MarinaNarrationDraft {
    var act: MarinaNarrationAct = .answer
    var introduction: String
    @Guide(description: "Current evidence, focal first.", .maximumCount(6))
    var claims: [MarinaNarrationClaim]
    var question: String
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
enum MarinaNarrationAct: String { case answer, greeting, clarification, help }

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable
struct MarinaNarrationClaim {
    @Guide(description: "Evidence ID.")
    var reference: String
    @Guide(description: "Preserve {subject} {relation} {value}; include {scope}.")
    var wording: String
}

/// Current evidence identifiers are actual generation constraints, not merely examples.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaNarrationSchema {
    static func estimatedTokens(_ schema: GenerationSchema) -> Int {
        guard let data = try? JSONEncoder().encode(schema) else { return 600 }
        return (data.count + 2) / 3 + 32
    }

    static func make(act: MarinaNarrationAct, evidence: [MarinaNarrationEvidence]) throws -> GenerationSchema {
        let ids = Array(Set(evidence.map(\.id))).sorted()
        let reference = DynamicGenerationSchema(name: "EvidenceReference", anyOf: ids.isEmpty ? [""] : ids)
        let claim = DynamicGenerationSchema(name: "EvidenceClaim", properties: [
            .init(name: "reference", schema: reference),
            .init(name: "prefix", description: "Optional neutral transition, such as Also,. No facts.", schema: .init(type: String.self), isOptional: true)
        ])
        let empty = DynamicGenerationSchema(name: "EmptyText", anyOf: [""])
        let root = DynamicGenerationSchema(name: "VerifiedExplanation", properties: [
            .init(name: "act", schema: .init(name: "ResponseAct", anyOf: [act.rawValue])),
            .init(name: "introduction", schema: ids.isEmpty ? .init(type: String.self) : empty),
            .init(name: "claims", schema: .init(arrayOf: claim,
                minimumElements: ids.isEmpty ? 0 : max(1, evidence.filter(\.isFocus).count),
                maximumElements: ids.isEmpty ? 0 : min(6, ids.count))),
            .init(name: "question", schema: ids.isEmpty ? .init(type: String.self) : empty)
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Required propositions are app-owned. The model chooses facts and composes
    /// connective text; the existing validator checks every word around bound facts.
    static func draft(from content: GeneratedContent) throws -> MarinaNarrationDraft {
        let act: MarinaNarrationAct = try content.value(forProperty: "act")
        let introduction: String = try content.value(forProperty: "introduction")
        let question: String = try content.value(forProperty: "question")
        let claims: [GeneratedContent] = try content.value(forProperty: "claims")
        guard claims.count <= 6 else { throw CompositionError.invalidParts }
        let composed = try claims.map { claim -> MarinaNarrationClaim in
            guard case .structure(let fields, _) = claim.kind,
                  fields["reference"] != nil,
                  Set(fields.keys).isSubset(of: ["reference", "prefix"]) else {
                throw CompositionError.invalidParts
            }
            let reference: String = try claim.value(forProperty: "reference")
            let prefix: String? = try claim.value(String?.self, forProperty: "prefix")
            guard (prefix?.count ?? 0) <= 100 else { throw CompositionError.invalidParts }
            var wording = [prefix ?? "", "{subject} {relation} {value} for {scope}"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            for punctuation in [",", ".", "!", "?"] {
                wording = wording.replacingOccurrences(of: " " + punctuation, with: punctuation)
            }
            return .init(reference: reference, wording: wording)
        }
        return .init(act: act, introduction: introduction, claims: composed, question: question)
    }

    private enum CompositionError: Error { case invalidParts }
}
#endif
