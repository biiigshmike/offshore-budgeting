import Foundation
import NaturalLanguage

/// Shared, deterministic text forms for Marina's workspace candidate resolution.
///
/// Canonicalization keeps letters and numbers from every script, folds case/width/
/// diacritics for comparison, and treats punctuation as a word boundary. Inflection
/// handling uses Apple's locale-aware Natural Language lemmatizer. If no lemma is
/// available, only a narrow, conservative English noun fallback is applied.
nonisolated enum MarinaCanonicalTextNormalizer {
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")
    private static let retainedScalars = CharacterSet.alphanumerics.union(.nonBaseCharacters)

    static func canonical(_ value: String) -> String {
        let folded = value
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: comparisonLocale
            )
            .lowercased(with: comparisonLocale)

        var unicodeSafe = ""
        unicodeSafe.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            if retainedScalars.contains(scalar) {
                unicodeSafe.unicodeScalars.append(scalar)
            } else {
                unicodeSafe.append(" ")
            }
        }

        return unicodeSafe
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }

    static func morphologyForms(_ value: String) -> Set<String> {
        lemmaForms(forCanonical: canonical(value))
    }

    static func areStronglyEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonical(lhs)
        let right = canonical(rhs)
        guard left.isEmpty == false, right.isEmpty == false else { return false }
        if left == right { return true }
        return lemmaForms(forCanonical: left).isDisjoint(
            with: lemmaForms(forCanonical: right)
        ) == false
    }

    private static func lemmaForms(forCanonical canonical: String) -> Set<String> {
        guard canonical.isEmpty == false else { return [] }
        var forms: Set<String> = [canonical]
        var lemmas: [String] = []
        var producedLemma = false
        if let language = NLLanguageRecognizer.dominantLanguage(for: canonical) {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = canonical
            let fullRange = canonical.startIndex..<canonical.endIndex
            tagger.setLanguage(language, range: fullRange)
            tagger.enumerateTags(
                in: fullRange,
                unit: .word,
                scheme: .lemma,
                options: [.omitWhitespace, .omitPunctuation]
            ) { tag, tokenRange in
                let token = tag?.rawValue ?? String(canonical[tokenRange])
                let normalizedLemma = self.canonical(token)
                if normalizedLemma.isEmpty == false {
                    lemmas.append(normalizedLemma)
                    producedLemma = producedLemma || tag != nil
                }
                return true
            }
        }

        if producedLemma, lemmas.isEmpty == false {
            forms.insert(lemmas.joined(separator: " "))
        } else if let fallback = conservativeEnglishLemmaFallback(canonical) {
            forms.insert(fallback)
        }
        return forms
    }

    /// Some devices do not have the Natural Language lemma scheme installed.
    /// Keep the fallback intentionally narrow: common consonant + `y` nouns such
    /// as grocery/groceries and category/categories, without stripping a generic
    /// trailing `s` from gas, status, or business.
    private static func conservativeEnglishLemmaFallback(_ canonical: String) -> String? {
        let tokens = canonical.split(separator: " ").map(String.init)
        var changed = false
        let lemmas = tokens.map { token -> String in
            guard token.count > 5,
                  token.hasSuffix("ries"),
                  token != "series" else {
                return token
            }
            changed = true
            return String(token.dropLast(3)) + "y"
        }
        return changed ? lemmas.joined(separator: " ") : nil
    }
}
