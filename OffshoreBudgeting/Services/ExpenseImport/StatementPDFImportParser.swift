//
//  StatementPDFImportParser.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/11/26.
//

import Foundation
import PDFKit

enum StatementPDFImportParserError: LocalizedError {
    case unreadableFile
    case emptyDocument
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected PDF could not be opened."
        case .emptyDocument:
            return "The selected PDF did not contain readable text."
        case .noTransactionsFound:
            return "No entry rows were found in this PDF."
        }
    }
}

struct StatementPDFImportParser {

    // MARK: - Public

    static func parse(url: URL) throws -> ParsedCSV {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw StatementPDFImportParserError.unreadableFile
        }

        let lines = normalizedLines(from: document)
        guard !lines.isEmpty else {
            throw StatementPDFImportParserError.emptyDocument
        }

        let context = StatementDateContext(lines: lines)

        var rows: [[String]] = []
        rows.reserveCapacity(lines.count / 3)

        for line in lines {
            guard let row = parseTransactionLine(line, context: context) else { continue }
            rows.append([row.date, row.description, row.amount, row.category, row.type])
        }

        guard !rows.isEmpty else {
            throw StatementPDFImportParserError.noTransactionsFound
        }

        return ParsedCSV(
            headers: [
                "Date",
                "Description",
                "Amount",
                "Category",
                "Type"
            ],
            rows: rows
        )
    }

    // MARK: - Parsing

    private struct ParsedTransactionRow {
        let date: String
        let description: String
        let amount: String
        let category: String
        let type: String
    }

    private static func normalizedLines(from document: PDFDocument) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(max(64, document.pageCount * 40))

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex), let text = page.string else { continue }
            for raw in text.components(separatedBy: .newlines) {
                let normalized = normalizeWhitespace(raw)
                if normalized.isEmpty { continue }
                lines.append(normalized)
            }
        }

        return lines
    }

    private static func parseTransactionLine(_ line: String, context: StatementDateContext) -> ParsedTransactionRow? {
        guard let dateMatch = matchFirst(line, regex: dateAtStartRegex) else { return nil }

        let rawDateToken = substring(from: line, nsRange: dateMatch.range(at: 1))
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedDate = normalizeDateToken(rawDateToken, context: context) else { return nil }

        let fullMatchRange = dateMatch.range(at: 0)
        let remainderStart = fullMatchRange.location + fullMatchRange.length
        guard let remainderRange = Range(NSRange(location: remainderStart, length: max(0, (line as NSString).length - remainderStart)), in: line) else {
            return nil
        }

        let remainder = normalizeWhitespace(String(line[remainderRange]))
        guard !remainder.isEmpty else { return nil }

        let amountMatches = matches(remainder, regex: amountRegex)
        guard !amountMatches.isEmpty else { return nil }
        guard let selectedAmountMatch = selectAmountMatch(in: remainder, matches: amountMatches) else { return nil }

        let amountToken = substring(from: remainder, nsRange: selectedAmountMatch.range(at: 0))
        guard let normalizedAmount = normalizeAmountToken(amountToken) else { return nil }

        let nsRemainder = remainder as NSString
        let descriptionRaw = nsRemainder.replacingCharacters(in: selectedAmountMatch.range(at: 0), with: " ")
        let description = normalizeWhitespace(descriptionRaw)
        guard !description.isEmpty else { return nil }
        guard description.rangeOfCharacter(from: .letters) != nil else { return nil }
        guard !looksLikeSummary(description) else { return nil }

        let numericAmount = Double(normalizedAmount) ?? 0
        let type = inferType(description: description, amount: numericAmount)

        return ParsedTransactionRow(
            date: normalizedDate,
            description: description,
            amount: normalizedAmount,
            category: "",
            type: type
        )
    }

    private static func selectAmountMatch(
        in text: String,
        matches: [NSTextCheckingResult]
    ) -> NSTextCheckingResult? {
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0] }

        let first = matches[0]
        if first.range(at: 0).location <= 2 {
            return first
        }

        return matches[matches.count - 1]
    }

    private static func normalizeAmountToken(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let isParenNegative = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        let hasExplicitMinus = trimmed.contains("-")

        let normalized = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(normalized) else { return nil }

        let signedValue = (isParenNegative || hasExplicitMinus) ? -abs(value) : value
        return String(format: "%.2f", signedValue)
    }

    private static func inferType(description: String, amount: Double) -> String {
        let lower = description.lowercased()

        let incomeKeywords = [
            "payment",
            "thank you",
            "deposit",
            "direct deposit",
            "refund",
            "reversal",
            "credit",
            "daily cash adjustment"
        ]

        let expenseKeywords = [
            "purchase",
            "withdrawal",
            "fee",
            "interest",
            "debit card"
        ]

        if incomeKeywords.contains(where: { lower.contains($0) }) {
            return "income"
        }

        if expenseKeywords.contains(where: { lower.contains($0) }) {
            return "expense"
        }

        if amount < 0 {
            return "income"
        }

        return "expense"
    }

    private static func looksLikeSummary(_ description: String) -> Bool {
        let lower = description.lowercased()
        let summaryKeywords = [
            "total year-to-date",
            "year-to-date",
            "minimum payment due",
            "closing date",
            "payments and credits",
            "apr",
            "interest charge",
            "balance"
        ]

        return summaryKeywords.contains(where: { lower.contains($0) })
    }

    // MARK: - Date Context

    private struct StatementDateContext {
        let referenceDate: Date?
        let candidateYears: [Int]

        init(lines: [String]) {
            self.referenceDate = StatementDateContext.extractReferenceDate(lines: lines)
            self.candidateYears = StatementDateContext.extractCandidateYears(lines: lines)
        }

        private static func extractReferenceDate(lines: [String]) -> Date? {
            for line in lines {
                let lower = line.lowercased()

                if lower.contains("for the period"),
                   let match = matchFirst(line, regex: periodEndDateRegex) {
                    let token = substring(from: line, nsRange: match.range(at: 1))
                    if let parsed = parseDateWithYear(token) {
                        return parsed
                    }
                }

                if lower.contains("opening/closing date"),
                   let match = matchFirst(line, regex: openingClosingEndDateRegex) {
                    let token = substring(from: line, nsRange: match.range(at: 1))
                    if let parsed = parseDateWithYear(token) {
                        return parsed
                    }
                }

                if lower.contains("closing date"),
                   let match = matchFirst(line, regex: closingDateRegex) {
                    let token = substring(from: line, nsRange: match.range(at: 1))
                    if let parsed = parseDateWithYear(token) {
                        return parsed
                    }
                }
            }

            let allFullDates = extractAllFullDates(lines: lines)
            return allFullDates.max()
        }

        private static func extractCandidateYears(lines: [String]) -> [Int] {
            var out: Set<Int> = []

            for line in lines {
                let lineMatches = matches(line, regex: fullDateRegex)
                for m in lineMatches {
                    let token = substring(from: line, nsRange: m.range(at: 0))
                    if let date = parseDateWithYear(token) {
                        out.insert(Calendar.current.component(.year, from: date))
                    }
                }
            }

            return out.sorted()
        }

        private static func extractAllFullDates(lines: [String]) -> [Date] {
            var out: [Date] = []
            out.reserveCapacity(16)

            for line in lines {
                let lineMatches = matches(line, regex: fullDateRegex)
                for m in lineMatches {
                    let token = substring(from: line, nsRange: m.range(at: 0))
                    if let date = parseDateWithYear(token) {
                        out.append(date)
                    }
                }
            }

            return out
        }
    }

    private static func normalizeDateToken(_ token: String, context: StatementDateContext) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        if cleaned.split(separator: "/").count == 3 {
            guard let date = parseDateWithYear(cleaned) else { return nil }
            return outputDateFormatter.string(from: date)
        }

        let parts = cleaned.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]) else {
            return nil
        }

        let candidateYears: [Int]
        if context.candidateYears.isEmpty {
            let currentYear = Calendar.current.component(.year, from: Date())
            candidateYears = [currentYear - 1, currentYear, currentYear + 1]
        } else {
            candidateYears = context.candidateYears
        }

        let calendar = Calendar.current
        var datedCandidates: [Date] = []
        datedCandidates.reserveCapacity(candidateYears.count)

        for year in candidateYears {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            if let date = calendar.date(from: comps) {
                datedCandidates.append(date)
            }
        }

        if datedCandidates.isEmpty { return nil }
        if datedCandidates.count == 1 {
            return outputDateFormatter.string(from: datedCandidates[0])
        }

        guard let referenceDate = context.referenceDate else {
            let best = datedCandidates.sorted { abs($0.timeIntervalSinceNow) < abs($1.timeIntervalSinceNow) }[0]
            return outputDateFormatter.string(from: best)
        }

        let referenceWithGrace = calendar.date(byAdding: .day, value: 7, to: referenceDate) ?? referenceDate
        let best = datedCandidates.sorted { lhs, rhs in
            let lhsIsFarFuture = lhs > referenceWithGrace
            let rhsIsFarFuture = rhs > referenceWithGrace

            if lhsIsFarFuture != rhsIsFarFuture {
                return rhsIsFarFuture
            }

            let lhsDistance = abs(lhs.timeIntervalSince(referenceDate))
            let rhsDistance = abs(rhs.timeIntervalSince(referenceDate))
            return lhsDistance < rhsDistance
        }[0]

        return outputDateFormatter.string(from: best)
    }

    private static func parseDateWithYear(_ token: String) -> Date? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let parts = trimmed.split(separator: "/")
        if parts.count == 3 {
            let yearPart = String(parts[2])
            if yearPart.count == 2 {
                if let date = fullDateFormatter2.date(from: trimmed) {
                    return date
                }
            } else if yearPart.count == 4 {
                if let date = fullDateFormatter4.date(from: trimmed) {
                    return date
                }
            }
        }

        if let date = fullDateFormatter2.date(from: trimmed) {
            return date
        }

        if let date = fullDateFormatter4.date(from: trimmed) {
            return date
        }

        return nil
    }

    // MARK: - Regex

    private static let dateAtStartRegex = regex(#"^\s*(\d{1,2}/\d{1,2}(?:/\d{2,4})?\*?)"#)
    private static let amountRegex = regex(#"[-+]?\$?\(?\d{1,3}(?:,\d{3})*\.\d{2}\)?"#)
    private static let fullDateRegex = regex(#"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#)
    private static let periodEndDateRegex = regex(#"(?i)for\s+the\s+period\s+\d{1,2}/\d{1,2}/\d{2,4}\s+to\s+(\d{1,2}/\d{1,2}/\d{2,4})"#)
    private static let openingClosingEndDateRegex = regex(#"(?i)opening/closing\s+date\s+\d{1,2}/\d{1,2}/\d{2,4}\s*[-–]\s*(\d{1,2}/\d{1,2}/\d{2,4})"#)
    private static let closingDateRegex = regex(#"(?i)closing\s+date\s+(\d{1,2}/\d{1,2}/\d{2,4})"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func matchFirst(_ text: String, regex: NSRegularExpression) -> NSTextCheckingResult? {
        let nsRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: nsRange)
    }

    private static func matches(_ text: String, regex: NSRegularExpression) -> [NSTextCheckingResult] {
        let nsRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: nsRange)
    }

    private static func substring(from text: String, nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: text) else { return "" }
        return String(text[range])
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatters

    private static let fullDateFormatter4: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "M/d/yyyy"
        return df
    }()

    private static let fullDateFormatter2: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "M/d/yy"
        return df
    }()

    private static let outputDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "MM/dd/yyyy"
        return df
    }()
}
