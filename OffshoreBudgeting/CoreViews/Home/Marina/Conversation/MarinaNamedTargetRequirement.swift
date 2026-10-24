import Foundation

/// Literal, affirmative names in the current question must not disappear from a financial read.
/// This checks scope only. Name resolution and every calculation remain in the data service.
nonisolated struct MarinaNamedTargetRequirement: Equatable, Sendable {
    let search: String
    let recordKind: String?
    let candidates: [MarinaConversationMemory.Entity]

    var isAmbiguous: Bool { candidates.count > 1 }

    /// Name provenance only: exact affirmative wording, allowing case, accents, and whitespace
    /// differences. No aliases, inferred kinds, phonetic matching, or emoji substitution.
    static func containsLiteralName(_ name: String, in prompt: String) -> Bool {
        let name = folded(name)
        let text = folded(prompt)
        guard !name.isEmpty, !text.isEmpty else { return false }
        var remaining = text.startIndex..<text.endIndex
        while let range = text.range(of: name, range: remaining) {
            if hasWordBoundaries(range, in: text), isAffirmative(prefix: String(text[..<range.lowerBound])) {
                return true
            }
            guard range.upperBound < text.endIndex else { break }
            remaining = range.upperBound..<text.endIndex
        }
        return false
    }

    func includes(in request: MarinaDataRequest) -> Bool {
        candidates.contains { entity in
            switch entity.kind {
            case "card":
                return sameID(entity.id, request.cardID) || sameID(entity.id, request.comparisonFilter?.cardID)
            case "category":
                return sameID(entity.id, request.categoryID) || sameID(entity.id, request.comparisonFilter?.categoryID)
            case "budget":
                return sameID(entity.id, request.budgetID) || sameID(entity.id, request.comparisonFilter?.budgetID)
            case "preset":
                return sameID(entity.id, request.presetID) || sameID(entity.id, request.comparisonFilter?.presetID)
            case "savingsAccount", "reconciliationAccount":
                return request.tool == .accounts && sameID(entity.id, request.accountID)
            case "merchant":
                return request.tool == .expenses && (sameName(entity.name, request.search)
                    || sameName(entity.name, request.comparisonFilter?.search))
            case "incomeSource":
                return request.tool == .income && (sameName(entity.name, request.search)
                    || sameName(entity.name, request.comparisonFilter?.search))
            default: return false
            }
        }
    }

    private func sameID(_ id: String, _ selected: String?) -> Bool {
        selected.map { id.caseInsensitiveCompare($0) == .orderedSame } ?? false
    }

    private func sameName(_ name: String, _ selected: String?) -> Bool {
        selected.map { Self.folded(name) == Self.folded($0) } ?? false
    }

    /// The catalog is the same fresh, workspace-scoped catalog used by findRecords. An untyped
    /// literal expands with its existing contains matching, so Apple also considers Apple Card.
    static func requirements(prompt: String, catalog: [MarinaConversationMemory.Entity]) -> [Self] {
        let text = folded(prompt)
        guard !text.isEmpty else { return [] }
        let explicitNames = explicitLiterals(in: prompt, catalogNames: catalog.map(\.name))
        let searchable = catalog.filter { $0.kind != "workspace" && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        struct Match {
            let name: String
            let range: Range<String.Index>
        }
        var matches: [Match] = []
        var seenNames = Set<String>()
        for entity in searchable {
            let name = folded(entity.name)
            guard seenNames.insert(name).inserted else { continue }
            var remaining = text.startIndex..<text.endIndex
            while let range = text.range(of: name, range: remaining) {
                if hasWordBoundaries(range, in: text) {
                    matches.append(.init(name: entity.name, range: range))
                }
                guard range.upperBound < text.endIndex else { break }
                remaining = range.upperBound..<text.endIndex
            }
        }
        // The literal Apple Card must not also create a separate requirement for Apple.
        matches.sort {
            let left = text.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
            let right = text.distance(from: $1.range.lowerBound, to: $1.range.upperBound)
            return left == right ? $0.range.lowerBound < $1.range.lowerBound : left > right
        }
        var selected: [Match] = []
        for match in matches where !selected.contains(where: { $0.range.overlaps(match.range) }) {
            selected.append(match)
        }
        let affirmativeNames = Set(selected.filter {
            !genericNames.contains(folded($0.name)) && !calendarNames.contains(folded($0.name))
                && isAffirmative(prefix: String(text[..<$0.range.lowerBound]))
        }.map { folded($0.name) } + explicitNames.map { folded($0.name) })
        var requirements: [Self] = []
        for match in selected.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            // A full explicit unknown name also outranks a known shorter name inside it.
            // For example, Café 🍵 Card must not become the existing Café 🍵 category.
            let isInsideLongerLiteral = explicitNames.contains { literal in
                let name = folded(literal.name)
                guard name != folded(match.name) else { return false }
                var remaining = text.startIndex..<text.endIndex
                while let range = text.range(of: name, range: remaining) {
                    if range.lowerBound <= match.range.lowerBound && range.upperBound >= match.range.upperBound { return true }
                    guard range.upperBound < text.endIndex else { break }
                    remaining = range.upperBound..<text.endIndex
                }
                return false
            }
            if isInsideLongerLiteral { continue }
            let prefix = String(text[..<match.range.lowerBound])
            guard isAffirmative(prefix: prefix) else { continue }
            let before = words(prefix).suffix(5)
            let matching = searchable.filter {
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(match.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
            }
            let suffix = String(text[match.range.upperBound...])
            let matchingKinds = Set(matching.map(\.kind))
            let kind = attachedKind(prefix: prefix, name: match.name, suffix: suffix, kinds: matchingKinds)
                ?? accountDomainKind(prefix: prefix, suffix: suffix,
                    hasSingleTarget: affirmativeNames.count == 1, kinds: matchingKinds)
            let namedExplicitly = before.contains("named") || before.contains("called")
                || before.contains("nombre") || before.contains("llamada") || before.contains("llamado")
            if genericNames.contains(folded(match.name)) && !namedExplicitly { continue }
            if calendarNames.contains(folded(match.name)) && kind == nil && !namedExplicitly { continue }
            let targetingWords: Set<String> = ["at", "on", "using", "with", "in", "for", "from", "show", "use", "compare",
                                               "en", "con", "para", "de", "muestra", "mostrar", "usa", "compara"]
            let isWholePrompt = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) == folded(match.name)
            guard kind != nil || namedExplicitly || before.suffix(4).contains(where: targetingWords.contains) || isWholePrompt else { continue }
            let candidates = matching.filter { kind == nil || $0.kind == kind }
            let requirement = Self(search: match.name, recordKind: kind, candidates: candidates)
            if !candidates.isEmpty && !requirements.contains(where: {
                folded($0.search) == folded(requirement.search) && $0.recordKind == requirement.recordKind
            }) { requirements.append(requirement) }
        }
        // Unknown names cannot come from the workspace catalog. Keep this deliberately narrow:
        // explicit quoted/named records, and anchored title-case names ending in Card/Tarjeta.
        // An empty candidate list still requires a lookup; it never authorizes workspace fallback.
        for literal in explicitNames {
            guard !requirements.contains(where: { folded($0.search) == folded(literal.name) }) else { continue }
            let candidates = searchable.filter {
                (literal.kind == nil || $0.kind == literal.kind)
                    && $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .contains(literal.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
            }
            requirements.append(.init(search: literal.name, recordKind: literal.kind, candidates: candidates))
        }
        return requirements
    }

    private static func explicitLiterals(in prompt: String, catalogNames: [String]) -> [(name: String, kind: String?)] {
        var literals: [(name: String, kind: String?)] = []
        func append(_ name: String, range: Range<String.Index>, forcedKind: String? = nil, requiresNamedWord: Bool = false, isQuoted: Bool = false) {
            let prefix = String(prompt[..<range.lowerBound])
            guard isAffirmative(prefix: folded(prefix)) else { return }
            let before = words(folded(prefix)).suffix(5)
            let explicitlyNamed = before.contains("named") || before.contains("called") || before.contains("nombre")
                || before.contains("llamada") || before.contains("llamado")
            if requiresNamedWord && !explicitlyNamed { return }
            let kind = forcedKind ?? attachedKind(prefix: prefix, name: name,
                suffix: String(prompt[range.upperBound...]), kinds: Set(kindNames.keys))
            guard kind != nil || explicitlyNamed else { return }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !genericNames.contains(folded(name)) || explicitlyNamed || isQuoted else { return }
            literals.append((name, kind))
        }
        let entireRange = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        let quoted = #"["“]([^"”]{1,120})["”]|['‘]([^'’]{1,120})['’]"#
        if let regex = try? NSRegularExpression(pattern: quoted) {
            for match in regex.matches(in: prompt, range: entireRange) {
                let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                guard let range = Range(capture, in: prompt) else { continue }
                append(String(prompt[range]), range: range, isQuoted: true)
            }
        }
        // The final kind word bounds the name before dates or the remainder of the question.
        let anchoredCard = #"\b(?:on|using|with|en|con)\s+(?:(?:the|my|la|mi)\s+)?([^\n,;.?!]{1,100}?\b(?:card|tarjeta))\b"#
        if let regex = try? NSRegularExpression(pattern: anchoredCard, options: .caseInsensitive) {
            for match in regex.matches(in: prompt, range: entireRange) {
                guard let range = Range(match.range(at: 1), in: prompt) else { continue }
                let name = String(prompt[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tokens = name.split(whereSeparator: \.isWhitespace)
                guard tokens.count > 1, tokens.count <= 7 else { continue }
                let nameTokens = tokens.dropLast()
                let connectors: Set<String> = ["of", "the", "de", "del", "la", "el", "my", "mi", "a", "an"]
                func isTitleToken(_ token: Substring) -> Bool {
                    token.first?.isUppercase == true || token.first?.isNumber == true
                        || token.unicodeScalars.allSatisfy { $0.properties.isEmoji || $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
                }
                let isTitle = nameTokens.allSatisfy { token in
                    connectors.contains(folded(String(token))) || isTitleToken(token)
                }
                // The optional article may backtrack in the regex. “the card” is still a
                // generic noun phrase, including before “named BlueCard”, never a record name.
                let hasName = nameTokens.contains { !connectors.contains(folded(String($0))) && isTitleToken($0) }
                guard isTitle && hasName else { continue }
                append(name, range: range, forcedKind: "card")
            }
        }
        let named = #"\b(?:named|called|llamado|llamada)\s+([^\n,;.?!"“”'‘’]{1,120})"#
        if let regex = try? NSRegularExpression(pattern: named, options: .caseInsensitive) {
            for match in regex.matches(in: prompt, range: entireRange) {
                guard let range = Range(match.range(at: 1), in: prompt) else { continue }
                var name = String(prompt[range])
                // Preserve a complete known name containing a conjunction. Unknown unquoted
                // names end before another target/filter; quoted names never use this branch.
                let knownPrefix = catalogNames.compactMap { known -> Range<String.Index>? in
                    guard let match = name.range(of: known, options: [.anchored, .caseInsensitive, .diacriticInsensitive]),
                          hasWordBoundaries(match, in: name) else { return nil }
                    let remainder = String(name[match.upperBound...])
                    guard remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || remainder.range(of: "^" + namedBoundary, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
                    return match
                }.max { $0.upperBound < $1.upperBound }
                if let knownPrefix { name = String(name[knownPrefix]) }
                else if let trailing = name.range(of: namedBoundary, options: [.regularExpression, .caseInsensitive]) {
                    name = String(name[..<trailing.lowerBound])
                }
                let end = prompt.index(range.lowerBound, offsetBy: name.count)
                append(name, range: range.lowerBound..<end, requiresNamedWord: true)
            }
        }
        return literals
    }

    private static let namedBoundary = #"\s+(?:and|or|but|with|on|at|within|plus|y|o|pero|con|en|this|last|current|previous|today|yesterday|during|in|for|este|esta|el mes|durante)\b"#

    private static let kindNames: [String: [String]] = [
        "card": ["card", "cards", "tarjeta", "tarjetas"],
        "category": ["category", "categories", "categoria", "categorias"],
        "budget": ["budget", "budgets", "presupuesto", "presupuestos"],
        "preset": ["preset", "presets", "preajuste", "preajustes", "plantilla", "plantillas"],
        "merchant": ["merchant", "merchants", "comercio", "comercios", "comerciante", "comerciantes"],
        "incomeSource": ["income source", "income", "fuente de ingreso", "fuente de ingresos"],
        "savingsAccount": ["savings account", "savings", "cuenta de ahorro", "cuenta de ahorros", "ahorro", "ahorros"],
        "reconciliationAccount": ["reconciliation account", "reconciliation", "cuenta de conciliacion", "cuenta de reconciliacion", "conciliacion", "reconciliacion"]
    ]

    /// A kind must touch this target, rather than occur somewhere in a nearby clause. In
    /// “on my card at Apple”, the intervening “at” prevents card from qualifying Apple.
    private static func attachedKind(prefix: String, name: String, suffix: String, kinds: Set<String>) -> String? {
        let boundaries = CharacterSet(charactersIn: ",;.!?\n")
        var before = words(folded(prefix.components(separatedBy: boundaries).last ?? ""))
        let after = words(folded(suffix.components(separatedBy: boundaries).first ?? ""))
        let nameWords = words(folded(name))
        let articles: Set<String> = ["the", "a", "an", "el", "la", "un", "una"]
        if let last = before.last, articles.contains(last) { before.removeLast() }
        if let last = before.last, ["named", "called", "llamado", "llamada"].contains(last) { before.removeLast() }
        let matches = kinds.filter { kind in
            kindNames[kind, default: []].contains { phrase in
                let tokens = words(phrase)
                return before.suffix(tokens.count).elementsEqual(tokens)
                    || after.prefix(tokens.count).elementsEqual(tokens)
                    || (nameWords.count > tokens.count && nameWords.suffix(tokens.count).elementsEqual(tokens))
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// A single account-domain subject can also qualify its balance/activity target through
    /// a preposition. This deliberately does not generalize to “on my card at Apple”.
    private static func accountDomainKind(prefix: String, suffix: String,
                                          hasSingleTarget: Bool, kinds: Set<String>) -> String? {
        guard hasSingleTarget else { return nil }
        let outsideName = prefix + " " + suffix
        let policy = MarinaTurnPolicy(prompt: outsideName)
        let domains = ["savingsAccount", "reconciliationAccount"].filter { policy.confirms(kind: $0) }
        guard domains.count == 1, let kind = domains.first, kinds.contains(kind) else { return nil }
        let comparisonWords: Set<String> = ["and", "or", "versus", "vs", "compare", "between", "y", "o", "contra", "compara", "comparar"]
        guard !words(folded(outsideName)).contains(where: comparisonWords.contains) else { return nil }
        let clause = folded(prefix.components(separatedBy: CharacterSet(charactersIn: ",;.!?\n")).last ?? "")
        let domain = kind == "savingsAccount" ? "savings" : "reconciliation"
        let prepositions = kind == "savingsAccount" ? "in|for" : "with|in|for"
        let pattern = #"\b"# + domain + #"(?: account)?(?: current)? (?:balance|balances|activity|entries|ledger) (?:"#
            + prepositions + #")(?: (?:my|the|our))?$"#
        return clause.range(of: pattern, options: .regularExpression) == nil ? nil : kind
    }

    private static let genericNames: Set<String> = [
        "card", "cards", "category", "categories", "budget", "budgets", "preset", "presets",
        "income", "incomes", "spending", "expenses", "transactions", "total", "planned", "actual",
        "savings", "savings account", "reconciliation", "reconciliation account", "workspace",
        "tarjeta", "tarjetas", "categoria", "categorias", "presupuesto", "presupuestos", "ingreso", "ingresos",
        "ahorro", "ahorros", "cuenta de ahorro", "cuenta de conciliacion"
    ]

    private static let calendarNames: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
        "daily", "weekly", "monthly", "quarterly", "yearly"
    ]

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func words(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func hasWordBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        let startsWord = text[range.lowerBound].isLetter || text[range.lowerBound].isNumber
        let last = text[text.index(before: range.upperBound)]
        let endsWord = last.isLetter || last.isNumber
        if startsWord && range.lowerBound > text.startIndex {
            let prior = text[text.index(before: range.lowerBound)]
            if prior.isLetter || prior.isNumber { return false }
        }
        if endsWord && range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber { return false }
        }
        return true
    }

    private static func isAffirmative(prefix: String) -> Bool {
        // Preserve punctuation and emoji in the actual literal match; only the preceding clause
        // is tokenized to avoid treating an excluded name as an affirmative selection.
        let clause = prefix.components(separatedBy: CharacterSet(charactersIn: ",;.!?\n")).last ?? ""
        let negations: Set<String> = ["not", "no", "never", "without", "except", "excluding", "cannot", "sin", "excepto"]
        let contrasts: Set<String> = ["but", "instead", "pero", "sino"]
        var affirmative = true
        for word in words(clause) {
            if contrasts.contains(word) { affirmative = true }
            else if negations.contains(word) { affirmative = false }
        }
        return affirmative
    }
}
