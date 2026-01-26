//
//  ImportMerchantRuleMatcher.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

struct ImportMerchantRuleMatch {
    let rule: ImportMerchantRule
    let matchedKey: String
    let confidence: Double
}

/// Fuzzy matcher over `ImportMerchantRule.merchantKey`.
///
/// Why: merchant keys are derived from bank CSV descriptions which vary wildly; exact-key lookup is too strict.
struct ImportMerchantRuleMatcher {

    private let rulesByKey: [String: ImportMerchantRule]
    private let tokenIndex: [String: [String]]
    private let tokensByKey: [String: Set<String>]

    init(rulesByKey: [String: ImportMerchantRule]) {
        self.rulesByKey = rulesByKey

        var tokensByKey: [String: Set<String>] = [:]
        tokensByKey.reserveCapacity(rulesByKey.count)

        var tokenIndex: [String: [String]] = [:]
        tokenIndex.reserveCapacity(rulesByKey.count * 2)

        for key in rulesByKey.keys {
            let tokens = Self.tokenizeKey(key)
            tokensByKey[key] = tokens
            for t in tokens {
                tokenIndex[t, default: []].append(key)
            }
        }

        self.tokensByKey = tokensByKey
        self.tokenIndex = tokenIndex
    }

    func match(for merchantKey: String) -> ImportMerchantRuleMatch? {
        let key = merchantKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        if let exact = rulesByKey[key] {
            return ImportMerchantRuleMatch(rule: exact, matchedKey: key, confidence: 1.0)
        }

        let queryTokens = Self.tokenizeKey(key)
        if queryTokens.isEmpty { return nil }

        var candidates: Set<String> = []
        candidates.reserveCapacity(64)

        for t in queryTokens {
            if let keys = tokenIndex[t] {
                for k in keys { candidates.insert(k) }
            }
        }

        // If token-based candidate search yields nothing and the rule set is small, fall back to scanning.
        if candidates.isEmpty, rulesByKey.count <= 150 {
            candidates = Set(rulesByKey.keys)
        }

        guard !candidates.isEmpty else { return nil }

        var best: (key: String, score: Double)? = nil
        var secondBestScore: Double = 0

        let queryCondensed = Self.condense(key)
        let querySet = queryTokens

        for candidateKey in candidates {
            guard let candidateSet = tokensByKey[candidateKey] else { continue }

            let interCount = querySet.intersection(candidateSet).count
            if interCount == 0 { continue }

            let overlap = Self.overlapCoefficient(intersectionCount: interCount, aCount: querySet.count, bCount: candidateSet.count)

            let candidateCondensed = Self.condense(candidateKey)
            let jw = Self.jaroWinkler(queryCondensed, candidateCondensed)

            var score = (0.80 * overlap) + (0.20 * jw)

            // Penalize single-token overlap when the query has multiple tokens (too ambiguous).
            if interCount == 1, querySet.count >= 3 {
                score *= 0.85
            }

            if candidateCondensed.contains(queryCondensed) || queryCondensed.contains(candidateCondensed) {
                score = min(1.0, score + 0.05)
            }

            if let currentBest = best, score > currentBest.score {
                secondBestScore = currentBest.score
                best = (candidateKey, score)
            } else if best == nil {
                best = (candidateKey, score)
            } else if score > secondBestScore {
                secondBestScore = score
            }
        }

        guard let best else { return nil }

        // Guardrails against incorrect matches.
        // - Require a high score
        // - Require some separation from the 2nd best
        let threshold = 0.88
        let minMargin = 0.04
        guard best.score >= threshold else { return nil }
        guard best.score - secondBestScore >= minMargin else { return nil }

        guard let rule = rulesByKey[best.key] else { return nil }
        return ImportMerchantRuleMatch(rule: rule, matchedKey: best.key, confidence: best.score)
    }

    // MARK: - Helpers

    private static func tokenizeKey(_ s: String) -> Set<String> {
        let parts = s
            .uppercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        var out: Set<String> = []
        out.reserveCapacity(parts.count * 2)

        for p in parts {
            out.insert(p)
            let collapsed = p.replacingOccurrences(of: "-", with: "")
            if collapsed != p, !collapsed.isEmpty {
                out.insert(collapsed)
            }
        }

        return out
    }

    private static func condense(_ s: String) -> String {
        s.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func overlapCoefficient(intersectionCount: Int, aCount: Int, bCount: Int) -> Double {
        let denom = min(aCount, bCount)
        if denom <= 0 { return 0 }
        return Double(intersectionCount) / Double(denom)
    }

    // Jaro-Winkler similarity in [0, 1]
    private static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let a = Array(s1)
        let b = Array(s2)

        let matchDistance = max(a.count, b.count) / 2 - 1
        var aMatches = Array(repeating: false, count: a.count)
        var bMatches = Array(repeating: false, count: b.count)

        var matches = 0
        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, b.count)
            if start >= end { continue }
            for j in start..<end where !bMatches[j] {
                if a[i] == b[j] {
                    aMatches[i] = true
                    bMatches[j] = true
                    matches += 1
                    break
                }
            }
        }

        if matches == 0 { return 0.0 }

        var t = 0
        var j = 0
        for i in 0..<a.count where aMatches[i] {
            while j < b.count, !bMatches[j] { j += 1 }
            if j < b.count, a[i] != b[j] { t += 1 }
            j += 1
        }

        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - Double(t) / 2.0) / m) / 3.0

        // Winkler prefix boost
        var prefix = 0
        let maxPrefix = 4
        for i in 0..<min(maxPrefix, min(a.count, b.count)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }

        let p = 0.10
        return jaro + Double(prefix) * p * (1.0 - jaro)
    }
}
