import Foundation

#if canImport(FoundationModels)
/// Validates the generated composition before it can replace verified fallback prose.
/// Model-authored connective language is allowed around complete, bound propositions.
/// A read does not authorize arbitrary additional financial assertions.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaNarrationValidator {
    static func render(draft: MarinaNarrationDraft?, evidence: [MarinaNarrationEvidence],
                       requiresFinancialEvidence: Bool) -> String? {
        guard let draft else { return nil }
        let introduction = draft.introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard introduction.count <= 300, question.count <= 300, draft.claims.count <= 6 else { return nil }
        if evidence.isEmpty {
            guard !requiresFinancialEvidence, draft.claims.isEmpty, draft.act != .answer,
                  safeConversation(introduction, act: draft.act, isQuestion: false),
                  safeConversation(question, act: draft.act, isQuestion: true) else { return nil }
            let text = [introduction, question].filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        guard draft.act == .answer, !draft.claims.isEmpty, question.isEmpty, neutralFraming(introduction) else { return nil }
        let byID = Dictionary(evidence.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = Set(draft.claims.map(\.reference))
        // The selected primary result supplies the answer focus. Supporting facts
        // cannot displace the requested answer or introduce an exploratory report.
        let required = evidence.filter(\.isFocus)
        guard let focus = required.first, draft.claims.first?.reference == focus.id,
              required.allSatisfy({ selected.contains($0.id) }),
              selected.count == draft.claims.count else { return nil }
        var sentences: [String] = []
        var scopes: Set<String> = []
        for claim in draft.claims {
            guard let fact = byID[claim.reference], claim.wording.count <= 500 else { return nil }
            var sentence = claim.wording.trimmingCharacters(in: .whitespacesAndNewlines)
            let required = scopes.contains(fact.scope) ? ["subject", "relation", "value"] : ["subject", "relation", "value", "scope"]
            for slot in required where occurrences(of: "{\(slot)}", in: sentence) != 1 { return nil }
            guard occurrences(of: "{scope}", in: sentence) <= 1,
                  sentence.range(of: #"\{subject\}\s+\{relation\}\s+\{value\}"#, options: .regularExpression) != nil else { return nil }
            var connective = sentence
            for slot in ["subject", "relation", "value", "scope"] {
                connective = connective.replacingOccurrences(of: "{\(slot)}", with: " ")
            }
            // Only connective wording remains outside bound facts: no invented names,
            // values, negation, comparison direction or financial interpretation.
            guard safeConnective(connective) else { return nil }
            for (slot, value) in [("subject", fact.subject), ("relation", fact.relation), ("value", fact.value), ("scope", fact.scope)] {
                sentence = sentence.replacingOccurrences(of: "{\(slot)}", with: value)
            }
            guard !sentence.contains("{") && !sentence.contains("}") else { return nil }
            if let first = sentence.first { sentence.replaceSubrange(sentence.startIndex...sentence.startIndex, with: String(first).uppercased()) }
            if !sentence.hasSuffix(".") && !sentence.hasSuffix("!") { sentence += "." }
            sentences.append(sentence)
            scopes.insert(fact.scope)
        }
        let body = sentences.joined(separator: " ")
        return introduction.isEmpty ? body : introduction + " " + body
    }

    private static func occurrences(of needle: String, in value: String) -> Int {
        value.components(separatedBy: needle).count - 1
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    }

    private static func safeConnective(_ text: String) -> Bool {
        guard !text.contains(where: \.isNumber),
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "{}$€£¥%<>")) == nil,
              !text.contains("—"), !text.contains(";") else { return false }
        let allowed: Set<String> = ["a", "an", "the", "and", "also", "for", "in", "during", "at", "on", "with", "of", "to",
            "your", "you", "here", "s", "this", "that", "it", "as", "across", "overall", "meanwhile", "then",
            "looking", "from", "which", "while", "is", "are", "was", "were", "by", "together",
            "put", "context", "as", "ve", "have", "got",
            "en", "para", "durante", "con", "de", "del", "la", "el", "los", "las", "y", "tambien", "tu", "tus", "su", "sus"]
        return Set(tokens(text)).isSubset(of: allowed)
    }

    private static func neutralFraming(_ text: String) -> Bool {
        guard !text.contains(where: \.isNumber), text.count <= 180,
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "$€£¥%{}<>")) == nil else { return false }
        if text.isEmpty { return true }
        // These are output compositions, never routes for user questions. A vocabulary
        // alone could combine harmless words into an unsupported assessment such as
        // “your results are okay.” Keep framing free of propositions about finances.
        let allowed: Set<String> = [
            "here s what stands out", "here is what stands out", "here s the breakdown", "here is the breakdown",
            "here s a quick breakdown", "here s a look", "here s a closer look", "here s what i found", "here is what i found",
            "here are the details", "here are your results", "here s your summary", "here is your summary",
            "here s the summary", "here is the summary", "let s take a look", "let us take a look",
            "okay", "ok", "sure", "got it", "claro", "aqui esta el resumen", "aquí está el resumen"
        ]
        return allowed.contains(tokens(text).joined(separator: " "))
    }

    private static func safeConversation(_ text: String, act: MarinaNarrationAct, isQuestion: Bool) -> Bool {
        guard !text.contains(where: \.isNumber),
              text.rangeOfCharacter(from: CharacterSet(charactersIn: "$€£¥%{}<>")) == nil else { return false }
        if text.isEmpty { return true }
        if !isQuestion && neutralFraming(text) { return true }
        let common: Set<String> = ["a", "an", "the", "and", "or", "with", "to", "at", "for", "of", "on", "in", "about",
            "i", "m", "am", "marina", "offshore", "your", "you", "we", "our", "s", "re", "can", "could", "would", "will",
            "like", "want", "help", "look", "explore", "review", "check", "show", "see", "focus", "start", "choose", "use",
            "what", "which", "how", "me", "us", "let", "do", "shall", "should", "please", "these", "this", "that",
            "spending", "expenses", "category", "categories", "limits", "income", "savings", "budget", "budgets", "budgeting",
            "card", "cards", "workspace", "reconciliation", "accounts", "records", "period", "assistant", "question", "questions",
            "hola", "soy", "tu", "asistente", "de", "presupuesto", "que", "quieres", "ver", "gastos", "ingresos", "ahorros"]
        let greeting: Set<String> = ["hey", "hi", "hello", "welcome", "thanks", "thank", "nice", "meet", "happy", "glad", "sure", "okay", "ok", "there", "again", "today"]
        let allowed = act == .greeting ? common.union(greeting) : common
        guard Set(tokens(text)).isSubset(of: allowed) else { return false }
        if isQuestion {
            // A clarification requests a topic or target, never presupposes a financial state.
            return text.hasSuffix("?") && ["what", "which", "how", "would", "could", "shall", "should", "do", "que"].contains(tokens(text).first ?? "")
        }
        if act == .greeting { return true }
        // Free financial definitions/assessments cannot use help as an evidence bypass.
        // Help is limited to first-person capability statements.
        let words = tokens(text)
        return words.starts(with: ["i", "can"]) || words.starts(with: ["i", "m", "marina"])
            || words.starts(with: ["i", "am", "marina"]) || words.starts(with: ["soy", "marina"])
    }
}
#endif
