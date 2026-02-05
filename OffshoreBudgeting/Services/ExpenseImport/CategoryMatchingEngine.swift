//
//  CategoryMatchingEngine.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

struct CategoryMatchSuggestion {
    let category: Category?
    let confidence: Double
    let reason: String
}

enum CategoryMatchingEngine {

    // Static synonym map (shipped with app).
    // Keys represent "concept buckets" (normalizeName side will unify).
    // Values are words that should map into that bucket.
    //
    // NOTE: This does not need to match actual category names.
    // it is used as an assist layer for scoring.
    static let synonymMap: [String: [String]] = [
        "dining": ["restaurant", "restaurants", "food", "eat", "drink", "cafe", "coffee"],
        "transportation": ["fuel", "gas", "gasoline", "uber", "lyft", "transit", "parking"],
        "groceries": ["grocery", "groceries", "supermarket", "market", "store"],
        "coffee": ["coffee", "cafe", "starbucks"],
        "shopping": ["retail", "shop", "shopping"],
        "health": ["health", "medical", "pharmacy", "doctor", "dental"],
        "utilities": ["utility", "utilities", "electric", "power", "water", "internet"],
        "entertainment": ["entertainment", "movies", "music", "streaming"],
        "travel": ["travel", "hotel", "air", "airline", "rideshare"],
        "subscriptions": ["subscription", "subscriptions", "membership"]
    ]

    // Thresholds tuned to match bucket behavior.
    static let readyThreshold: Double = 0.86
    static let possibleThreshold: Double = 0.55

    static func suggest(
        csvCategory: String?,
        merchant: String,
        availableCategories: [Category],
        learnedRule: ImportMerchantRule?
    ) -> CategoryMatchSuggestion {

        // 0) Learned rule wins (Option 1 memory)
        if let learnedRule {
            if let cat = learnedRule.preferredCategory {
                return CategoryMatchSuggestion(category: cat, confidence: 1.0, reason: "Learned mapping")
            }
        }

        let csvRaw = (csvCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let csvKey = normalizeName(csvRaw)

        // If CSV category is empty, still try merchant-based inference later
        if csvKey.isEmpty {
            return CategoryMatchSuggestion(category: nil, confidence: 0.0, reason: "No CSV category")
        }

        // 1) Exact / near-exact normalized match
        if let exact = availableCategories.first(where: { normalizeName($0.name) == csvKey }) {
            return CategoryMatchSuggestion(category: exact, confidence: 1.0, reason: "Exact match")
        }

        // 2) Singular/plural assist
        let singularCSV = stripTrailingS(csvKey)
        if let singular = availableCategories.first(where: { stripTrailingS(normalizeName($0.name)) == singularCSV }) {
            return CategoryMatchSuggestion(category: singular, confidence: 0.95, reason: "Singular/plural match")
        }

        // 3) Synonym concept bucket match
        if let concept = conceptKey(for: csvKey) {
            // If any categories also sit in that concept bucket, prefer it.
            // (Example: "Food & Drink" should land in dining.)
            var best: (Category, Double, String)? = nil
            for cat in availableCategories {
                let catKey = normalizeName(cat.name)
                let catConcept = conceptKey(for: catKey)
                if catConcept == concept {
                    // Concept matches are strong, but not perfect.
                    let score = 0.90
                    if best == nil || score > best!.1 {
                        best = (cat, score, "Synonym bucket: \(concept)")
                    }
                }
            }
            if let best {
                return CategoryMatchSuggestion(category: best.0, confidence: best.1, reason: best.2)
            }
        }

        // 4) Contains match (either direction)
        if let contains = availableCategories.first(where: {
            let key = normalizeName($0.name)
            return key.contains(csvKey) || csvKey.contains(key)
        }) {
            return CategoryMatchSuggestion(category: contains, confidence: 0.74, reason: "Contains match")
        }

        // 5) Token overlap score
        let csvTokens = tokenize(csvRaw)
        var best: (Category, Double, String)? = nil

        for cat in availableCategories {
            let catTokens = tokenize(cat.name)
            if catTokens.isEmpty || csvTokens.isEmpty { continue }

            let overlap = csvTokens.intersection(catTokens).count
            if overlap == 0 { continue }

            // Score by overlap ratio (simple, stable)
            let denom = max(csvTokens.count, catTokens.count)
            let ratio = Double(overlap) / Double(denom)

            // Nudge ratio into a reasonable confidence band
            let score = min(0.70, max(0.55, ratio + 0.35))

            if best == nil || score > best!.1 {
                best = (cat, score, "Token overlap")
            }
        }

        if let best {
            return CategoryMatchSuggestion(category: best.0, confidence: best.1, reason: best.2)
        }

        return CategoryMatchSuggestion(category: nil, confidence: 0.0, reason: "No match")
    }

    // MARK: - Helpers

    static func normalizeName(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    static func stripTrailingS(_ s: String) -> String {
        guard s.count > 3, s.hasSuffix("s") else { return s }
        return String(s.dropLast())
    }

    static func tokenize(_ s: String) -> Set<String> {
        let parts = s
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }
        return Set(parts)
    }

    static func conceptKey(for normalized: String) -> String? {
        // normalized is already squished, so check against normalized synonym words.
        for (concept, words) in synonymMap {
            if words.contains(where: { normalizeName($0) == normalized }) {
                return concept
            }
        }
        return nil
    }
}
