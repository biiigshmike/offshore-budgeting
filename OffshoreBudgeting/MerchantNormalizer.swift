//
//  MerchantNormalizer.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

enum MerchantNormalizer {

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if s.isEmpty { return "" }

        // Common bank prefixes
        s = stripPrefixes(s, prefixes: [
            "pos", "debit", "purchase", "online", "card purchase", "visa", "mastercard"
        ])

        // Remove obvious masked card fragments like xxxxx1234, *1234, #1234
        s = s.replacingOccurrences(of: #"(\*|#|x){2,}\s*\d{2,4}"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b\d{4}\b"#, with: "", options: .regularExpression)

        // Remove trailing location-ish noise (very conservative)
        s = s.replacingOccurrences(of: #"\s+[A-Z]{2}\s+\d{5}(-\d{4})?$"#, with: "", options: .regularExpression)

        // Collapse whitespace
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // If we ended up empty, fall back to raw trimmed
        if s.isEmpty { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        return s.uppercased()
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
}
