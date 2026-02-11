//
//  ExpenseImageImportParser.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/11/26.
//

import Foundation
import Vision

enum ExpenseImageImportParserError: LocalizedError {
    case noTextFound
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "No text could be recognized from this image."
        case .noTransactionsFound:
            return "No transaction rows were found in this image."
        }
    }
}

struct ExpenseImageImportParser {

    // MARK: - Public

    static func parse(url: URL, referenceDate: Date = .now) throws -> ParsedCSV {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        debugLog("parse(url:) started for \(url.lastPathComponent)")
        let lines = try recognizeTextLines(url: url)
        debugLogLines(lines, title: "OCR raw lines")
        return try parse(recognizedLines: lines, referenceDate: referenceDate)
    }

    static func parse(recognizedLines: [String], referenceDate: Date = .now) throws -> ParsedCSV {
        let lines = recognizedLines
            .map(normalizeWhitespace)
            .filter { !$0.isEmpty }

        debugLog("parse(recognizedLines:) with \(lines.count) normalized lines")
        debugLogLines(lines, title: "OCR normalized lines")

        guard !lines.isEmpty else {
            debugLog("No normalized lines found")
            throw ExpenseImageImportParserError.noTextFound
        }

        if let receipt = parseReceipt(lines: lines, referenceDate: referenceDate) {
            debugLog("Detected receipt-style import")
            debugLogRow(receipt)
            return toParsedCSV(rows: [receipt])
        }

        if let paycheck = parsePaycheckScreenshot(lines: lines, referenceDate: referenceDate) {
            debugLog("Detected paycheck-style import")
            debugLogRow(paycheck)
            return toParsedCSV(rows: [paycheck])
        }

        let dateContext = ImageDateContext(lines: lines, referenceDate: referenceDate)
        debugAnalyzeLines(lines, context: dateContext)
        let rows = parseBankLikeTransactions(lines: lines, context: dateContext)
        debugLog("Bank-like parser produced \(rows.count) rows")
        for row in rows {
            debugLogRow(row)
        }

        guard !rows.isEmpty else {
            debugLog("No transaction rows were found after bank-like parsing")
            throw ExpenseImageImportParserError.noTransactionsFound
        }

        return toParsedCSV(rows: rows)
    }

    // MARK: - OCR

    private static func recognizeTextLines(url: URL) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        if lines.isEmpty {
            throw ExpenseImageImportParserError.noTextFound
        }

        return lines
    }

    // MARK: - Receipt

    private static func parseReceipt(lines: [String], referenceDate: Date) -> ImportRow? {
        let hasOrderSummary = lines.contains { $0.lowercased().contains("order summary") }
        let hasGrandTotal = lines.contains { $0.lowercased().contains("grand total") }
        guard hasOrderSummary && hasGrandTotal else { return nil }

        guard let amountText = firstAmount(afterPrefix: "grand total", in: lines),
              let amount = normalizeAmountToken(amountText) else {
            return nil
        }

        let orderPlacedLine = lines.first { $0.lowercased().contains("order placed") }
        let dateText = normalizeDate(
            from: orderPlacedLine ?? "",
            context: ImageDateContext(lines: lines, referenceDate: referenceDate)
        ) ?? outputDateFormatter.string(from: referenceDate)

        let description = lines.first(where: {
            let lower = $0.lowercased()
            return !lower.contains("search")
                && !lower.contains("see details")
                && !lower.contains("order summary")
                && !lower.contains("order placed")
                && !lower.contains("grand total")
                && !lower.contains("item(s) subtotal")
                && !lower.contains("shipping & handling")
                && !lower.contains("payment method")
                && !lower.contains("track package")
                && $0.rangeOfCharacter(from: .letters) != nil
        }) ?? "Amazon Receipt"

        return ImportRow(
            date: dateText,
            description: descriptionWithoutAmount(from: description, amountText: amountText),
            amount: amount,
            category: "",
            type: "expense"
        )
    }

    // MARK: - Paycheck screenshot

    private static func parsePaycheckScreenshot(lines: [String], referenceDate: Date) -> ImportRow? {
        let hasPaycheck = lines.contains { $0.lowercased().contains("paycheck") }
        let hasTakeHome = lines.contains { $0.lowercased().contains("take home pay") }
        guard hasPaycheck || hasTakeHome else { return nil }

        let amountLine = lines.first(where: { $0.lowercased().contains("take home pay") })
            ?? lines.first(where: { $0.lowercased().contains("earned this period") })
            ?? lines.first(where: { amountRegex.firstMatch(in: $0, options: [], range: NSRange(location: 0, length: ($0 as NSString).length)) != nil })

        guard let amountLine,
              let amountMatch = amountRegex.firstMatch(in: amountLine, options: [], range: NSRange(location: 0, length: (amountLine as NSString).length)) else {
            return nil
        }

        let amountText = substring(from: amountLine, nsRange: amountMatch.range(at: 0))
        guard let amount = normalizeAmountToken(amountText) else { return nil }

        let rangeLine = lines.first(where: { rangeDateRegex.firstMatch(in: $0, options: [], range: NSRange(location: 0, length: ($0 as NSString).length)) != nil })

        let dateText: String
        if let rangeLine,
           let rangeMatch = rangeDateRegex.firstMatch(in: rangeLine, options: [], range: NSRange(location: 0, length: (rangeLine as NSString).length)) {
            let monthToken = substring(from: rangeLine, nsRange: rangeMatch.range(at: 3))
            let dayToken = substring(from: rangeLine, nsRange: rangeMatch.range(at: 4))
            dateText = normalizeMonthDayWithoutYear(
                monthName: monthToken,
                dayText: dayToken,
                context: ImageDateContext(lines: lines, referenceDate: referenceDate)
            ) ?? outputDateFormatter.string(from: referenceDate)
        } else {
            dateText = outputDateFormatter.string(from: referenceDate)
        }

        return ImportRow(
            date: dateText,
            description: "Paycheck",
            amount: amount,
            category: "",
            type: "income"
        )
    }

    // MARK: - Bank-like list parser

    private static func parseBankLikeTransactions(lines: [String], context: ImageDateContext) -> [ImportRow] {
        var rows: [ImportRow] = []
        rows.reserveCapacity(max(8, lines.count / 6))

        var currentSectionDate: String? = nil
        var pendingUndatedRowIndex: Int? = nil
        var pendingDescriptionCandidate: String? = nil
        var merchantSeeds: [MerchantSeed] = []
        merchantSeeds.reserveCapacity(max(8, lines.count / 5))
        var lastUndatedSeedIndex: Int? = nil
        var separatedAmountTokens: [String] = []
        separatedAmountTokens.reserveCapacity(max(8, lines.count / 6))

        for line in lines {
            if let monthYearDate = normalizeMonthYearHeader(line, context: context) {
                currentSectionDate = monthYearDate
                pendingDescriptionCandidate = nil
                continue
            }

            if let transaction = parseTransactionLine(
                line,
                fallbackDate: currentSectionDate,
                context: context,
                fallbackDescription: pendingDescriptionCandidate
            ) {
                rows.append(transaction)
                pendingUndatedRowIndex = transaction.date.isEmpty ? (rows.count - 1) : nil
                pendingDescriptionCandidate = nil
                debugLog("Accepted row from line: \(line)")
                continue
            }

            if let standaloneDate = normalizeDate(from: line, context: context) {
                if let idx = pendingUndatedRowIndex, rows.indices.contains(idx), rows[idx].date.isEmpty {
                    rows[idx].date = standaloneDate
                    pendingUndatedRowIndex = nil
                    pendingDescriptionCandidate = nil
                    continue
                }

                if let seedIndex = lastUndatedSeedIndex,
                   merchantSeeds.indices.contains(seedIndex),
                   merchantSeeds[seedIndex].date == nil {
                    merchantSeeds[seedIndex].date = standaloneDate
                    lastUndatedSeedIndex = nil
                }

                currentSectionDate = standaloneDate
                pendingDescriptionCandidate = nil
                continue
            }

            if let amountToken = extractNormalizedAmountIfAmountOnlyLine(line) {
                separatedAmountTokens.append(amountToken)
                debugLog("Captured separated amount token: \(amountToken) from line: \(line)")
                continue
            }

            if isDescriptionCandidateLine(line, context: context) {
                let candidate = normalizeWhitespace(line)
                if let existing = pendingDescriptionCandidate {
                    if descriptionCandidateScore(candidate) >= descriptionCandidateScore(existing) {
                        pendingDescriptionCandidate = candidate
                        debugLog("Updated fallback description candidate: \(candidate)")
                    }
                } else {
                    pendingDescriptionCandidate = candidate
                    debugLog("Captured fallback description candidate: \(candidate)")
                }
                merchantSeeds.append(MerchantSeed(description: candidate, date: nil))
                lastUndatedSeedIndex = merchantSeeds.count - 1
                continue
            }
        }

        var filtered = rows.filter { !$0.description.isEmpty }
        if filtered.isEmpty {
            let synthesized = synthesizeRowsFromSeparatedColumns(
                merchantSeeds: merchantSeeds,
                separatedAmountTokens: separatedAmountTokens,
                fallbackDate: currentSectionDate
            )
            if !synthesized.isEmpty {
                debugLog("Synthesized \(synthesized.count) rows from separated merchant/amount columns")
                filtered = synthesized
            }
        }

        return filtered
    }

    private static func parseTransactionLine(
        _ line: String,
        fallbackDate: String?,
        context: ImageDateContext,
        fallbackDescription: String?
    ) -> ImportRow? {
        let lower = line.lowercased()
        if rejectionKeywords.contains(where: { lower.contains($0) }) { return nil }
        if line.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil { return nil }

        let nsRange = NSRange(location: 0, length: (line as NSString).length)
        let amountMatches = amountRegex.matches(in: line, options: [], range: nsRange)
        guard !amountMatches.isEmpty else { return nil }

        guard let selectedAmountMatch = selectAmountMatch(in: line, matches: amountMatches) else { return nil }
        let amountText = substring(from: line, nsRange: selectedAmountMatch.range(at: 0))
        guard let normalizedAmount = normalizeAmountToken(amountText) else { return nil }

        let lineDescription = cleanedMerchantDescription(
            from: descriptionWithoutAmount(from: line, amountText: amountText)
        )
        let description: String
        if isUsableMerchantDescription(lineDescription) {
            description = lineDescription
        } else if let fallbackDescription,
                  isUsableMerchantDescription(cleanedMerchantDescription(from: fallbackDescription)) {
            description = cleanedMerchantDescription(from: fallbackDescription)
        } else {
            return nil
        }

        let explicitDate = normalizeDate(from: line, context: context)
        let date = explicitDate ?? fallbackDate ?? ""
        let numericAmount = Double(normalizedAmount) ?? 0
        let type = inferType(description: description, amount: numericAmount)

        return ImportRow(
            date: date,
            description: description,
            amount: normalizedAmount,
            category: "",
            type: type
        )
    }

    private static func selectAmountMatch(in line: String, matches: [NSTextCheckingResult]) -> NSTextCheckingResult? {
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0] }

        if let signed = matches.first(where: {
            let token = substring(from: line, nsRange: $0.range(at: 0))
            return token.contains("-") || token.contains("+")
        }) {
            return signed
        }

        return matches[0]
    }

    // MARK: - Types

    private static func inferType(description: String, amount: Double) -> String {
        let lower = description.lowercased()

        if lower.contains("payment") {
            if incomePaymentHints.contains(where: { lower.contains($0) }) {
                return "income"
            }
            if expensePaymentHints.contains(where: { lower.contains($0) }) {
                return "expense"
            }
            if amount > 0 {
                return "income"
            }
        }

        if incomeKeywords.contains(where: { lower.contains($0) }) {
            return "income"
        }

        if expenseKeywords.contains(where: { lower.contains($0) }) {
            return "expense"
        }

        if amount < 0 {
            return "expense"
        }

        return "expense"
    }

    private static let incomePaymentHints: [String] = [
        "thank",
        "automatic payment",
        "autopay",
        "auto pay",
        "mobile payment",
        "applecard",
        "gsbank",
        "credit card"
    ]

    private static let expensePaymentHints: [String] = [
        "payment pos",
        "pos"
    ]

    private static let incomeKeywords: [String] = [
        "thank you",
        "deposit",
        "credit",
        "refund",
        "reversal",
        "take home pay",
        "paycheck",
        "daily cash adjustment",
        "adjustment"
    ]

    private static let expenseKeywords: [String] = [
        "purchase",
        "withdrawal",
        "fee",
        "marketplace",
        "card purchase",
        "atm"
    ]

    private static let rejectionKeywords: [String] = [
        "search or ask a question",
        "latest card transactions",
        "recent transactions",
        "sort by",
        "statement balance",
        "download statement",
        "2 transactions",
        "order summary",
        "item(s) subtotal",
        "shipping & handling",
        "estimated tax to be collected",
        "payment method",
        "card ending",
        "hours",
        "regular",
        "overtime",
        "double ot",
        "federal income tax",
        "state and local taxes",
        "social security and medicare"
    ]

    private static let detailLineKeywords: [String] = [
        "apple pay",
        "card number used",
        "pending",
        "from ",
        "hour ago",
        "today",
        "yesterday",
        "saturday",
        "sunday",
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday"
    ]

    private static let allowedNumericMerchantNames: Set<String> = [
        "76"
    ]

    // MARK: - Dates

    private struct ImageDateContext {
        let referenceDate: Date
        let candidateYears: [Int]
        let dateCandidates: [Date]

        init(lines: [String], referenceDate: Date) {
            self.referenceDate = referenceDate

            var foundDates: [Date] = []
            foundDates.reserveCapacity(16)

            for line in lines {
                let normalized = normalizeWhitespace(line)

                for match in fullNumericDateRegex.matches(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) {
                    let token = substring(from: normalized, nsRange: match.range(at: 0))
                    if let d = parseFullDate(token) {
                        foundDates.append(d)
                    }
                }

                for match in monthDayYearRegex.matches(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) {
                    let token = substring(from: normalized, nsRange: match.range(at: 0))
                    if let d = parseMonthDayYearDate(token) {
                        foundDates.append(d)
                    }
                }
            }

            self.dateCandidates = foundDates
            self.candidateYears = Array(Set(foundDates.map { Calendar.current.component(.year, from: $0) })).sorted()
        }
    }

    private static func normalizeDate(from text: String, context: ImageDateContext) -> String? {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return nil }

        if let match = monthDayYearRegex.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) {
            let token = substring(from: normalized, nsRange: match.range(at: 0))
            if let d = parseMonthDayYearDate(token) {
                return outputDateFormatter.string(from: d)
            }
        }

        if let match = fullNumericDateRegex.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) {
            let token = substring(from: normalized, nsRange: match.range(at: 0))
            if let d = parseFullDate(token) {
                return outputDateFormatter.string(from: d)
            }
        }

        if let match = shortNumericDateRegex.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) {
            let monthToken = substring(from: normalized, nsRange: match.range(at: 1))
            let dayToken = substring(from: normalized, nsRange: match.range(at: 2))
            if let d = inferDate(month: monthToken, day: dayToken, context: context) {
                return outputDateFormatter.string(from: d)
            }
        }

        if let relative = inferRelativeDate(from: normalized, context: context) {
            return outputDateFormatter.string(from: relative)
        }

        return nil
    }

    private static func inferRelativeDate(from text: String, context: ImageDateContext) -> Date? {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return nil }

        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: context.referenceDate)
        let nsRange = NSRange(location: 0, length: (normalized as NSString).length)

        if todayRegex.firstMatch(in: normalized, options: [], range: nsRange) != nil {
            return referenceDay
        }

        if yesterdayRegex.firstMatch(in: normalized, options: [], range: nsRange) != nil {
            return calendar.date(byAdding: .day, value: -1, to: referenceDay)
        }

        if let agoMatch = relativeAgoRegex.firstMatch(in: normalized, options: [], range: nsRange) {
            let quantityText = substring(from: normalized, nsRange: agoMatch.range(at: 1))
            let unitText = substring(from: normalized, nsRange: agoMatch.range(at: 2)).lowercased()
            if let quantity = Int(quantityText), quantity >= 0 {
                if abs(context.referenceDate.timeIntervalSince(referenceDay)) < 1 {
                    return referenceDay
                }
                let component: Calendar.Component = (unitText.hasPrefix("hour") || unitText == "hr" || unitText == "hrs") ? .hour : .minute
                if let shifted = calendar.date(byAdding: component, value: -quantity, to: context.referenceDate) {
                    return calendar.startOfDay(for: shifted)
                }
            }
        }

        if let weekdayMatch = weekdayRegex.firstMatch(in: normalized, options: [], range: nsRange) {
            let weekdayText = substring(from: normalized, nsRange: weekdayMatch.range(at: 1)).lowercased()
            if let weekday = weekdayNumber(from: weekdayText) {
                return mostRecentWeekday(weekday, onOrBefore: referenceDay)
            }
        }

        return nil
    }

    private static func weekdayNumber(from lowerWeekday: String) -> Int? {
        let map: [String: Int] = [
            "sunday": 1,
            "monday": 2,
            "tuesday": 3,
            "wednesday": 4,
            "thursday": 5,
            "friday": 6,
            "saturday": 7
        ]
        return map[lowerWeekday]
    }

    private static func mostRecentWeekday(_ weekday: Int, onOrBefore referenceDay: Date) -> Date? {
        let calendar = Calendar.current
        for offset in 0...6 {
            guard let candidate = calendar.date(byAdding: .day, value: -offset, to: referenceDay) else { continue }
            if calendar.component(.weekday, from: candidate) == weekday {
                return candidate
            }
        }
        return nil
    }

    private static func normalizeMonthYearHeader(_ text: String, context: ImageDateContext) -> String? {
        let normalized = normalizeWhitespace(text)
        guard let match = monthYearHeaderRegex.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: (normalized as NSString).length)) else {
            return nil
        }

        let monthName = substring(from: normalized, nsRange: match.range(at: 1))
        let yearText = substring(from: normalized, nsRange: match.range(at: 2))

        guard let month = monthNumber(from: monthName),
              let year = Int(yearText) else {
            return nil
        }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1

        guard let d = Calendar.current.date(from: comps) else { return nil }
        return outputDateFormatter.string(from: d)
    }

    private static func normalizeMonthDayWithoutYear(monthName: String, dayText: String, context: ImageDateContext) -> String? {
        guard let month = monthNumber(from: monthName),
              let day = Int(dayText) else {
            return nil
        }

        return inferDate(month: String(month), day: String(day), context: context).map {
            outputDateFormatter.string(from: $0)
        }
    }

    private static func inferDate(month: String, day: String, context: ImageDateContext) -> Date? {
        guard let m = Int(month), let d = Int(day) else { return nil }

        let calendar = Calendar.current
        let years: [Int]
        if context.candidateYears.isEmpty {
            let refYear = calendar.component(.year, from: context.referenceDate)
            years = [refYear - 1, refYear, refYear + 1]
        } else {
            years = context.candidateYears + [calendar.component(.year, from: context.referenceDate)]
        }

        var candidates: [Date] = []
        for y in Array(Set(years)).sorted() {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            if let date = calendar.date(from: comps) {
                candidates.append(date)
            }
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        let graceReference = calendar.date(byAdding: .day, value: 7, to: context.referenceDate) ?? context.referenceDate
        return candidates.sorted { lhs, rhs in
            let lhsFuture = lhs > graceReference
            let rhsFuture = rhs > graceReference
            if lhsFuture != rhsFuture {
                return rhsFuture
            }
            return abs(lhs.timeIntervalSince(context.referenceDate)) < abs(rhs.timeIntervalSince(context.referenceDate))
        }[0]
    }

    private static func parseFullDate(_ token: String) -> Date? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let slashParts = trimmed.split(separator: "/")
        if slashParts.count == 3 {
            let yearPart = String(slashParts[2])
            if yearPart.count == 2 {
                return fullDateFormatter2.date(from: trimmed)
            }
            if yearPart.count == 4 {
                return fullDateFormatter4.date(from: trimmed)
            }
        }

        return fullDateFormatter4.date(from: trimmed) ?? fullDateFormatter2.date(from: trimmed)
    }

    private static func parseMonthDayYearDate(_ token: String) -> Date? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return monthDayYearFormatter.date(from: trimmed) ?? monthDayYearShortFormatter.date(from: trimmed)
    }

    private static func monthNumber(from monthName: String) -> Int? {
        let lower = monthName.lowercased()
        let map: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]
        return map[lower]
    }

    // MARK: - Amount + text helpers

    private static func firstAmount(afterPrefix prefix: String, in lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.lowercased().contains(prefix.lowercased()) }) else { return nil }
        let nsRange = NSRange(location: 0, length: (line as NSString).length)
        guard let match = amountRegex.firstMatch(in: line, options: [], range: nsRange) else { return nil }
        return substring(from: line, nsRange: match.range(at: 0))
    }

    private static func normalizeAmountToken(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let isParenNegative = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        let isNegative = isParenNegative || trimmed.contains("-")

        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(cleaned) else { return nil }
        let signed = isNegative ? -abs(value) : abs(value)
        return String(format: "%.2f", signed)
    }

    private static func extractNormalizedAmountIfAmountOnlyLine(_ line: String) -> String? {
        let lower = line.lowercased()
        if rejectionKeywords.contains(where: { lower.contains($0) }) { return nil }

        let nsRange = NSRange(location: 0, length: (line as NSString).length)
        let amountMatches = amountRegex.matches(in: line, options: [], range: nsRange)
        guard !amountMatches.isEmpty else { return nil }
        guard let selectedAmountMatch = selectAmountMatch(in: line, matches: amountMatches) else { return nil }

        let amountText = substring(from: line, nsRange: selectedAmountMatch.range(at: 0))
        guard let normalizedAmount = normalizeAmountToken(amountText) else { return nil }

        let description = descriptionWithoutAmount(from: line, amountText: amountText)
        if isUsableMerchantDescription(description) { return nil }

        return normalizedAmount
    }

    private static func synthesizeRowsFromSeparatedColumns(
        merchantSeeds: [MerchantSeed],
        separatedAmountTokens: [String],
        fallbackDate: String?
    ) -> [ImportRow] {
        let usableSeeds = merchantSeeds.filter { isUsableMerchantDescription($0.description) }
        let pairCount = min(usableSeeds.count, separatedAmountTokens.count)
        guard pairCount > 0 else { return [] }

        let pairedSeeds = Array(usableSeeds.suffix(pairCount))
        let pairedAmounts = Array(separatedAmountTokens.suffix(pairCount))
        var rows: [ImportRow] = []
        rows.reserveCapacity(pairCount)

        for idx in 0..<pairCount {
            let seed = pairedSeeds[idx]
            let amount = pairedAmounts[idx]
            let numericAmount = Double(amount) ?? 0
            let row = ImportRow(
                date: seed.date ?? fallbackDate ?? "",
                description: seed.description,
                amount: amount,
                category: "",
                type: inferType(description: seed.description, amount: numericAmount)
            )
            rows.append(row)
        }

        return rows
    }

    private static func descriptionWithoutAmount(from line: String, amountText: String) -> String {
        var text = line.replacingOccurrences(of: amountText, with: " ")
        text = text.replacingOccurrences(of: "›", with: " ")
        text = text.replacingOccurrences(of: ">", with: " ")
        text = text.replacingOccurrences(of: "<", with: " ")
        text = text.replacingOccurrences(of: #"\b\d{1,3}%\b"#, with: " ", options: .regularExpression)
        text = normalizeWhitespace(text)
        return text
    }

    private static func cleanedMerchantDescription(from text: String) -> String {
        var cleaned = normalizeWhitespace(text)
        if cleaned.isEmpty { return cleaned }

        cleaned = replaceMatches(in: cleaned, regex: amountRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: monthDayYearRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: fullNumericDateRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: shortNumericDateRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: relativeAgoRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: weekdayRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: todayRegex, with: " ")
        cleaned = replaceMatches(in: cleaned, regex: yesterdayRegex, with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\b\d{1,3}%\b"#, with: " ", options: .regularExpression)
        cleaned = normalizeWhitespace(cleaned)
        return cleaned
    }

    private static func replaceMatches(in text: String, regex: NSRegularExpression, with template: String) -> String {
        let nsRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: template)
    }

    private static func hasAlphaNumericContent(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .alphanumerics) != nil
    }

    private static func hasLetterContent(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .letters) != nil
    }

    private static func isDescriptionCandidateLine(_ line: String, context: ImageDateContext) -> Bool {
        let normalized = normalizeWhitespace(line)
        if normalized.isEmpty { return false }
        if !hasAlphaNumericContent(normalized) { return false }

        let nsRange = NSRange(location: 0, length: (normalized as NSString).length)
        if amountRegex.firstMatch(in: normalized, options: [], range: nsRange) != nil { return false }
        if normalizeDate(from: normalized, context: context) != nil { return false }

        return isUsableMerchantDescription(normalized)
    }

    private static func looksLikePercentBadge(_ text: String) -> Bool {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return false }
        return normalized.range(of: #"^\d{1,3}%$"#, options: .regularExpression) != nil
    }

    private static func looksLikeLocationLine(_ text: String) -> Bool {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return false }
        return normalized.range(of: #"^[A-Za-z .'\-]+,\s?[A-Z]{2}$"#, options: .regularExpression) != nil
    }

    private static func isUsableMerchantDescription(_ text: String) -> Bool {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return false }
        if !hasAlphaNumericContent(normalized) { return false }
        if looksLikePercentBadge(normalized) { return false }
        if looksLikeLocationLine(normalized) { return false }

        let lower = normalized.lowercased()
        if rejectionKeywords.contains(where: { lower.contains($0) }) { return false }
        if detailLineKeywords.contains(where: { lower.contains($0) }) { return false }

        if hasLetterContent(normalized) { return true }
        return allowedNumericMerchantNames.contains(normalized)
    }

    private static func descriptionCandidateScore(_ text: String) -> Int {
        let normalized = normalizeWhitespace(text)
        if normalized.isEmpty { return Int.min }

        var score = 0
        if hasLetterContent(normalized) { score += 6 }
        if normalized.contains(" ") { score += 2 }
        if normalized.count >= 4 { score += 1 }
        if normalized.rangeOfCharacter(from: .decimalDigits) != nil { score -= 1 }
        if looksLikeLocationLine(normalized) { score -= 4 }
        return score
    }

    nonisolated private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func substring(from text: String, nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: text) else { return "" }
        return String(text[range])
    }

    // MARK: - Output

    private struct MerchantSeed {
        var description: String
        var date: String?
    }

    private struct ImportRow {
        var date: String
        let description: String
        let amount: String
        let category: String
        let type: String
    }

    private static func toParsedCSV(rows: [ImportRow]) -> ParsedCSV {
        ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category", "Type"],
            rows: rows.map { [$0.date, $0.description, $0.amount, $0.category, $0.type] }
        )
    }

    // MARK: - Regex + formatters

    private static let amountRegex = regex(#"[-+]?\$?\(?\d{1,3}(?:,\d{3})*\.\d{2}\)?"#)
    private static let fullNumericDateRegex = regex(#"\b\d{1,2}/\d{1,2}/\d{4}\b"#)
    private static let shortNumericDateRegex = regex(#"\b(\d{1,2})/(\d{1,2})(?:/\d{2,4})?\b"#)
    private static let monthDayYearRegex = regex(#"\b(?:Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2},\s+\d{2,4}\b"#)
    private static let monthYearHeaderRegex = regex(#"^(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+(\d{4})$"#)
    private static let rangeDateRegex = regex(#"(?i)(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+(\d{1,2})\s*-\s*(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+(\d{1,2})"#)
    private static let todayRegex = regex(#"(?i)\btoday\b"#)
    private static let yesterdayRegex = regex(#"(?i)\byesterday\b"#)
    private static let relativeAgoRegex = regex(#"(?i)\b(\d+)\s*(hour|hours|hr|hrs|minute|minutes|min|mins)\s+ago\b"#)
    private static let weekdayRegex = regex(#"(?i)\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

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

    // MARK: - Debug

    private static func debugLog(_ message: String) {
#if DEBUG
        print("[ImageImportOCR] \(message)")
#endif
    }

    private static func debugLogLines(_ lines: [String], title: String) {
#if DEBUG
        debugLog("\(title):")
        for (idx, line) in lines.enumerated() {
            debugLog("  [\(idx + 1)] \(line)")
        }
#endif
    }

    private static func debugAnalyzeLines(_ lines: [String], context: ImageDateContext) {
#if DEBUG
        debugLog("Line analysis:")
        for (idx, line) in lines.enumerated() {
            let nsRange = NSRange(location: 0, length: (line as NSString).length)
            let hasAmount = amountRegex.firstMatch(in: line, options: [], range: nsRange) != nil
            let detectedDate = normalizeDate(from: line, context: context) ?? "-"
            let monthHeader = normalizeMonthYearHeader(line, context: context) ?? "-"
            let descriptionCandidate = isDescriptionCandidateLine(line, context: context)
            debugLog("  [\(idx + 1)] amount=\(hasAmount) date=\(detectedDate) monthHeader=\(monthHeader) descCandidate=\(descriptionCandidate) text=\(line)")
        }
#endif
    }

    private static func debugLogRow(_ row: ImportRow) {
#if DEBUG
        debugLog("  row date=\(row.date) desc=\(row.description) amount=\(row.amount) type=\(row.type)")
#endif
    }
}
