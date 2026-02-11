//
//  PaystubPDFImportParser.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/11/26.
//

import Foundation
import PDFKit

enum PaystubPDFImportParserError: LocalizedError {
    case unreadableFile
    case noTextFound
    case netPayNotFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected paystub PDF could not be opened."
        case .noTextFound:
            return "No readable text was found in this paystub."
        case .netPayNotFound:
            return "No net pay amount was found in this paystub."
        }
    }
}

struct PaystubPDFImportParser {

    // MARK: - Public

    static func parse(url: URL) throws -> ParsedCSV {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw PaystubPDFImportParserError.unreadableFile
        }

        let text = extractedText(from: document)
        guard !text.isEmpty else {
            throw PaystubPDFImportParserError.noTextFound
        }

        guard let amount = extractNetPayAmount(from: text) else {
            throw PaystubPDFImportParserError.netPayNotFound
        }

        let dateText = extractPayDate(from: text) ?? outputDateFormatter.string(from: .now)

        return ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category", "Type"],
            rows: [[dateText, "Paycheck", amount, "", "income"]]
        )
    }

    // MARK: - Parsing

    private static func extractedText(from document: PDFDocument) -> String {
        var allText = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let pageText = page.string else { continue }
            allText += " " + pageText
        }
        return normalizeWhitespace(allText)
    }

    private static func extractNetPayAmount(from text: String) -> String? {
        let patterns: [NSRegularExpression] = [
            regex(#"(?i)\bnet pay\b\s*\$?([\d,]+\.\d{2})"#),
            regex(#"(?i)\bcheck amount\b\s*\$?([\d,]+\.\d{2})"#),
            regex(#"(?i)\bpay day\b.*?\$?([\d,]+\.\d{2})"#)
        ]

        for pattern in patterns {
            if let match = pattern.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
                let token = substring(from: text, nsRange: match.range(at: 1))
                if let normalized = normalizeAmount(token) {
                    return normalized
                }
            }
        }

        return nil
    }

    private static func extractPayDate(from text: String) -> String? {
        let payDayRegex = regex(#"(?i)\bpay day\b\s*:\s*((?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{4})"#)
        if let match = payDayRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            let token = substring(from: text, nsRange: match.range(at: 1))
            if let date = monthDayYearFormatter.date(from: token) ?? monthDayYearShortFormatter.date(from: token) {
                return outputDateFormatter.string(from: date)
            }
        }

        let periodEndRegex = regex(#"(?i)\bpay period\b\s*:\s*(?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{4}\s*-\s*((?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{4})"#)
        if let match = periodEndRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            let token = substring(from: text, nsRange: match.range(at: 1))
            if let date = monthDayYearFormatter.date(from: token) ?? monthDayYearShortFormatter.date(from: token) {
                return outputDateFormatter.string(from: date)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func normalizeAmount(_ token: String) -> String? {
        let cleaned = token
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned) else { return nil }
        return String(format: "%.2f", value)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func substring(from text: String, nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: text) else { return "" }
        return String(text[range])
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    // MARK: - Formatters

    private static let monthDayYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "MMM d, yyyy"
        return df
    }()

    private static let monthDayYearShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "MMMM d, yyyy"
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
