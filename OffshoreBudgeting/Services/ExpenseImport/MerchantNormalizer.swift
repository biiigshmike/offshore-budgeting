//
//  MerchantNormalizer.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

enum MerchantNormalizer {

    /// Stable key for dictionary lookups (uppercased, noise stripped, address/phone removed).
    static func normalize(_ raw: String) -> String { normalizeKey(raw) }

    static func normalizeKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Fast path for common noisy descriptors.
        if let rewritten = canonicalRewrite(trimmed) {
            return rewritten
        }

        let core = stripWrappersAndPrefixes(trimmed)
        let tokens = extractMeaningfulTokens(core)
        if tokens.isEmpty { return trimmed.uppercased() }
        return tokens.joined(separator: " ").uppercased()
    }

    /// Human-facing suggestion (still deterministic, but keeps nicer casing).
    static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        if let rewritten = canonicalRewrite(trimmed) {
            return titleize(rewritten)
        }

        let core = stripWrappersAndPrefixes(trimmed)
        let tokens = extractMeaningfulTokens(core)
        if tokens.isEmpty { return trimmed }
        return titleize(tokens.joined(separator: " "))
    }

    private static func stripPrefixes(_ s: String, prefixes: [String]) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)

        while true {
            let lower = out.lowercased()
            if let p = prefixes.first(where: { lower.hasPrefix($0 + " ") }) {
                out = String(out.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            break
        }

        return out
    }

    // MARK: - Normalization pipeline

    private static func canonicalRewrite(_ s: String) -> String? {
        // Canonicalize "Apple bill" style descriptors.
        let upper = s.uppercased()
        if upper.contains("APPLE.COM/BILL") || upper.contains("ITUNES.COM/BILL") {
            return "APPLE SERVICES"
        }
        if upper.contains("APPLE CASH") {
            return "APPLE CASH"
        }
        return nil
    }

    private static func stripWrappersAndPrefixes(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop common "provider wrappers" like "SQ *", "TST*", "PAYPAL *"
        out = out.replacingOccurrences(of: #"(?i)^\s*(SQ|TST)\s*\*+\s*"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?i)^\s*(PAYPAL|VENMO|CASH\s*APP|CASHAPP|ZELLE)\s*\*+\s*"#, with: "", options: .regularExpression)

        // Common bank/export prefixes (allow repeated stripping).
        out = stripPrefixes(out, prefixes: [
            "recurring", "recur", "debit card purchase", "debit card", "card purchase",
            "purchase", "pos", "online", "visa", "mastercard", "debit", "credit", "ach", "payment"
        ])

        // Remove obvious masked card fragments like xxxxx1234, *1234, #1234
        out = out.replacingOccurrences(of: #"(?i)(\*|#|x){2,}\s*\d{2,4}"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?i)x{6,}\d{2,6}"#, with: "", options: .regularExpression)

        // Remove POS-ish markers and short export codes.
        out = out.replacingOccurrences(of: #"(?i)\bPOS\d{1,4}\b"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?i)\b[A-Z]\d{3,5}\b"#, with: "", options: .regularExpression)

        // Collapse whitespace
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    private static func extractMeaningfulTokens(_ s: String) -> [String] {
        if s.isEmpty { return [] }

        let upper = s.uppercased()

        // Replace common separators with spaces so tokenization is stable.
        var cleaned = upper
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "&", with: " AND ")

        // Treat "*" as a boundary for short processor prefixes.
        // Example: "DD *DOORDASH ..." -> "DOORDASH ..."
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[A-Z0-9]{1,3}\s*\*\s*"#, with: "", options: .regularExpression)

        // Drop country tokens.
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bUSA\b"#, with: "", options: .regularExpression)

        // Normalize punctuation into spaces (keep hyphens inside tokens).
        cleaned = cleaned.replacingOccurrences(of: #"[^A-Z0-9\-\s]"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return [] }

        let stopWords: Set<String> = [
            "CARD", "DEBIT", "CREDIT", "PURCHASE", "ONLINE", "PAYMENT", "TRANSFER",
            "RECURRING", "ACH", "POS", "CHECK", "WITHDRAWAL", "DEPOSIT", "FEE", "INTEREST"
        ]

        let addressStopWords: Set<String> = [
            "ST", "STREET", "AVE", "AVENUE", "RD", "ROAD", "BLVD", "BOULEVARD",
            "DR", "DRIVE", "LN", "LANE", "CT", "COURT", "WAY", "PKWY", "PARKWAY",
            "HWY", "HIGHWAY", "SUITE", "STE", "SU", "UNIT", "APT"
        ]

        func isLikelyPhoneOrZip(_ token: String) -> Bool {
            // 7+ digit phone-ish or 5/9 digit zip.
            if token.allSatisfy(\.isNumber) {
                if token.count >= 7 { return true }
                if token.count == 5 { return true }
                if token.count == 9 { return true }
            }
            return false
        }

        func splitAlphaNumericRuns(_ token: String) -> [String] {
            // Break "MRPICKLE303" into ["MRPICKLE"] and drop numeric-only runs.
            var out: [String] = []
            var current = ""
            var currentIsDigit: Bool? = nil

            for ch in token {
                let isDigit = ch.isNumber
                if currentIsDigit == nil {
                    currentIsDigit = isDigit
                    current = String(ch)
                } else if currentIsDigit == isDigit {
                    current.append(ch)
                } else {
                    if currentIsDigit == false {
                        out.append(current)
                    }
                    currentIsDigit = isDigit
                    current = String(ch)
                }
            }

            if currentIsDigit == false {
                out.append(current)
            }
            return out
        }

        let rawTokens = cleaned.split(separator: " ").map(String.init)
        var meaningful: [String] = []
        meaningful.reserveCapacity(min(8, rawTokens.count))

        for token in rawTokens {
            if token.isEmpty { continue }

            // Ignore store numbers like "#2684"
            if token.hasPrefix("#"), token.dropFirst().allSatisfy(\.isNumber) { continue }

            // Expand combined alpha+numeric tokens, dropping numeric chunks.
            let expanded = splitAlphaNumericRuns(token)
            for part in expanded {
                if part.isEmpty { continue }
                if stopWords.contains(part) { continue }
                if part.count == 1, part.allSatisfy({ $0.isLetter }) { continue }

                // If we already have a merchant prefix, treat a big numeric token as the start of address/location.
                if isLikelyPhoneOrZip(part) {
                    return meaningful
                }

                // A 2+ digit numeric token usually starts an address (but allow a leading single digit like "7-ELEVEN").
                if part.allSatisfy(\.isNumber), !meaningful.isEmpty {
                    return meaningful
                }

                if addressStopWords.contains(part), !meaningful.isEmpty {
                    return meaningful
                }

                meaningful.append(part)
                if meaningful.count >= 8 { return meaningful }
            }
        }

        // Drop trailing state-ish tokens (common in exports: "... CA", "... PA").
        while meaningful.count >= 2 {
            let last = meaningful[meaningful.count - 1]
            if last.count == 2, last.allSatisfy({ $0.isLetter }) {
                meaningful.removeLast()
                continue
            }
            break
        }

        return meaningful
    }

    private static func titleize(_ s: String) -> String {
        let words = s
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        func titleWord(_ w: String) -> String {
            // Keep short acronyms (common in exports: HPSO, IRS, etc.) uppercase.
            let honorifics: Set<String> = ["MR", "MRS", "MS", "DR"]
            if w.count <= 4,
               !honorifics.contains(w),
               w.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "-" }) {
                return w
            }
            // Preserve hyphenated words.
            if w.contains("-") {
                return w.split(separator: "-").map { titleWord(String($0)) }.joined(separator: "-")
            }
            return w.lowercased().prefix(1).uppercased() + w.lowercased().dropFirst()
        }

        return words.map(titleWord).joined(separator: " ")
    }
}
