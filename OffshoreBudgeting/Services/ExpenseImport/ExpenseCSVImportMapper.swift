import Foundation

struct ExpenseCSVImportMapper {

    // MARK: - Tuning

    /// Duplicate window for matching already-entered expenses and planned expenses.
    /// Keep relatively tight (±3 days) to avoid false positives while handling “clearing” delays.
    private static let duplicateDayWindow: Int = 3

    static func map(
        csv: ParsedCSV,
        categories: [Category],
        existingExpenses: [VariableExpense],
        existingPlannedExpenses: [PlannedExpense],
        existingIncomes: [Income],
        learnedRules: [String: ImportMerchantRule]
    ) -> [ExpenseCSVImportRow] {

        let headerMap = HeaderMap(headers: csv.headers)
        let learnedMatcher = ImportMerchantRuleMatcher(rulesByKey: learnedRules)
        let isAppleCardCSV = headerMap.isAppleCardCSV

        var out: [ExpenseCSVImportRow] = []
        out.reserveCapacity(csv.rows.count)

        for (idx, fields) in csv.rows.enumerated() {
            let lineNumber = idx + 2

            let dateText = headerMap.value(in: fields, for: .date, isAppleRow: isAppleCardCSV) ?? ""
            let postedDateText = headerMap.value(in: fields, for: .postedDate, isAppleRow: isAppleCardCSV)
            let descText = headerMap.value(in: fields, for: .description, isAppleRow: isAppleCardCSV) ?? ""
            let merchantText = headerMap.value(in: fields, for: .merchant, isAppleRow: isAppleCardCSV)
            let amountText = headerMap.value(in: fields, for: .amount, isAppleRow: isAppleCardCSV)
            let debitText = headerMap.value(in: fields, for: .debit, isAppleRow: isAppleCardCSV)
            let creditText = headerMap.value(in: fields, for: .credit, isAppleRow: isAppleCardCSV)
            let categoryText = headerMap.value(in: fields, for: .category, isAppleRow: isAppleCardCSV)
            let typeText = headerMap.value(in: fields, for: .type, isAppleRow: isAppleCardCSV)

            let parsedDate = parseDate(postedDateText ?? "") ?? parseDate(dateText)

            let rawMerchant = (merchantText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (merchantText ?? "")
                : descText
            let sourceMerchantKey = MerchantNormalizer.normalizeKey(rawMerchant)
            let descriptionMerchantKey = MerchantNormalizer.normalizeKey(descText)

            let originalAmountText = (amountText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (amountText ?? "")
                : ((debitText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                   ? (debitText ?? "")
                   : (creditText ?? ""))

            guard let date = parsedDate, let rawAmount = resolveRawAmount(amountText: amountText, debitText: debitText, creditText: creditText) else {
                let safeDate = Date()

                let row = ExpenseCSVImportRow(
                    sourceLine: lineNumber,
                    originalDateText: dateText,
                    originalDescriptionText: descText,
                    originalMerchantText: merchantText,
                    originalAmountText: originalAmountText,
                    originalCategoryText: categoryText,
                    sourceMerchantKey: sourceMerchantKey,
                    descriptionMerchantKey: descriptionMerchantKey,
                    finalDate: safeDate,
                    finalMerchant: MerchantNormalizer.displayName(rawMerchant),
                    finalAmount: 0,
                    kind: .expense,
                    suggestedCategory: nil,
                    suggestedConfidence: 0,
                    matchReason: "Missing required data",
                    selectedCategory: nil,
                    rememberMapping: false,
                    includeInImport: false,
                    isDuplicateHint: false,
                    bucket: .needsMoreData
                )

                out.append(row)
                continue
            }

            let learned = learnedMatcher.match(for: sourceMerchantKey)?.rule
                ?? learnedMatcher.match(for: descriptionMerchantKey)?.rule

            // Apply learned preferred name if exists
            let learnedName = learned?.preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalMerchant = (learnedName?.isEmpty == false)
                ? (learnedName ?? "")
                : MerchantNormalizer.displayName(rawMerchant)

            let kind = resolveKind(
                typeText: typeText,
                rawAmount: rawAmount,
                descriptionText: descText,
                categoryText: categoryText
            )
            let finalAmount = abs(rawAmount)

            // Category suggestion
            let suggestion = CategoryMatchingEngine.suggest(
                csvCategory: categoryText,
                merchant: finalMerchant,
                availableCategories: categories,
                learnedRule: learned
            )

            var isDup = false
            if kind == .expense {
                isDup = looksLikeDuplicateExpense(
                    date: date,
                    amount: finalAmount,
                    merchant: finalMerchant,
                    category: suggestion.category,
                    existing: existingExpenses
                )
                if !isDup {
                    isDup = looksLikeDuplicatePlannedExpense(
                        date: date,
                        amount: finalAmount,
                        merchant: finalMerchant,
                        category: suggestion.category,
                        existing: existingPlannedExpenses
                    )
                }
            } else {
                isDup = looksLikeDuplicateIncome(date: date, amount: finalAmount, merchant: finalMerchant, existing: existingIncomes)
            }

            // Default bucket + check behavior
            let bucket: ExpenseCSVImportBucket
            let includeDefault: Bool
            let selectedCategory: Category?

            if isDup {
                bucket = .possibleDuplicate
                includeDefault = false
                selectedCategory = suggestion.category
            } else if kind == .income {
                bucket = .payment
                includeDefault = true
                selectedCategory = nil
            } else {
                if suggestion.category == nil {
                    bucket = .needsMoreData
                    includeDefault = false
                    selectedCategory = nil
                } else if suggestion.confidence >= CategoryMatchingEngine.readyThreshold {
                    bucket = .ready
                    includeDefault = true
                    selectedCategory = suggestion.category
                } else if suggestion.confidence >= CategoryMatchingEngine.possibleThreshold {
                    bucket = .possibleMatch
                    includeDefault = false
                    selectedCategory = suggestion.category
                } else {
                    bucket = .needsMoreData
                    includeDefault = false
                    selectedCategory = nil
                }
            }

            var row = ExpenseCSVImportRow(
                sourceLine: lineNumber,
                originalDateText: dateText,
                originalDescriptionText: descText,
                originalMerchantText: merchantText,
                originalAmountText: originalAmountText,
                originalCategoryText: categoryText,
                sourceMerchantKey: sourceMerchantKey,
                descriptionMerchantKey: descriptionMerchantKey,
                finalDate: date,
                finalMerchant: finalMerchant,
                finalAmount: finalAmount,
                kind: kind,
                suggestedCategory: suggestion.category,
                suggestedConfidence: suggestion.confidence,
                matchReason: suggestion.reason,
                selectedCategory: selectedCategory,
                rememberMapping: false,
                includeInImport: includeDefault,
                isDuplicateHint: isDup,
                bucket: bucket
            )

            row.recomputeBucket()
            out.append(row)
        }

        return out
    }

    // MARK: - Kind resolution

    private static func resolveKind(
        typeText: String?,
        rawAmount: Double,
        descriptionText: String,
        categoryText: String?
    ) -> ExpenseCSVImportKind {
        let t = (typeText ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if !t.isEmpty {
            if t.contains("purchase") || t.contains("debit") { return .expense }
            if t.contains("payment") || t.contains("credit") { return .income }
            if t.contains("refund") || t.contains("reversal") { return .income }
            if t.contains("fee") || t.contains("interest") { return .expense }
        }

        // Amount sign (when present) wins.
        if rawAmount < 0 { return .expense }

        // Heuristics for exports that use unsigned amounts.
        let desc = descriptionText.lowercased()
        let cat = (categoryText ?? "").lowercased()

        if desc.contains("payment") || desc.contains("autopay") || desc.contains("online payment") { return .income }
        if cat.contains("payment") { return .income }

        if desc.contains("refund") || desc.contains("reversal") { return .income }
        if cat.contains("refund") || cat.contains("reversal") { return .income }

        if desc.contains("fee") || desc.contains("interest") { return .expense }

        // Default for this flow: treat unsigned amounts as expenses.
        return .expense
    }

    // MARK: - Header mapping

    private enum Field {
        case date
        case postedDate
        case description
        case merchant
        case amount
        case debit
        case credit
        case category
        case type
    }

    private struct HeaderMap {
        let headers: [String]
        private let lower: [String]
        let isAppleCardCSV: Bool

        init(headers: [String]) {
            self.headers = headers
            self.lower = headers.map { $0.lowercased() }
            self.isAppleCardCSV = HeaderMap.detectAppleCardCSV(lowerHeaders: self.lower)
        }

        func value(in fields: [String], for field: Field, isAppleRow: Bool) -> String? {
            if isAppleRow {
                if let v = appleValue(in: fields, for: field) {
                    let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            }

            guard let idx = index(for: field), idx < fields.count else { return nil }
            let val = fields[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            return val.isEmpty ? nil : val
        }

        private static func detectAppleCardCSV(lowerHeaders: [String]) -> Bool {
            func has(_ needle: String) -> Bool {
                lowerHeaders.contains(where: { $0.contains(needle) })
            }

            // Apple Card CSVs have explicit Merchant + Type columns.
            // Avoid false positives for bank exports that also have 2 date columns + 7 fields (e.g. Chase).
            let hasMerchant = has("merchant")
            let hasType = has("type")
            let hasTransactionDate = has("transaction date")
            let hasPostedOrClearing = has("posted date") || has("clearing date")
            let hasAmount = has("amount")

            return hasMerchant && hasType && hasTransactionDate && hasPostedOrClearing && hasAmount
        }

        // Apple Card common layout:
        // [0]=Transaction Date, [1]=Posted Date, [2]=Description, [3]=Merchant, [4]=Category, [5]=Type, [6]=Amount
        private func appleValue(in fields: [String], for field: Field) -> String? {
            guard fields.count >= 7 else { return nil }
            switch field {
            case .date: return fields[0]
            case .postedDate: return fields[1]
            case .description: return fields[2]
            case .merchant: return fields[3]
            case .category: return fields[4]
            case .type: return fields[5]
            case .amount: return fields[6]
            case .debit: return nil
            case .credit: return nil
            }
        }

        private func index(for field: Field) -> Int? {
            func firstIndex(whereAny keys: [String]) -> Int? {
                for k in keys {
                    if let i = lower.firstIndex(where: { $0.contains(k) }) { return i }
                }
                return nil
            }

            switch field {
            case .date:
                return firstIndex(whereAny: ["transaction date", "date", "posted"])
            case .postedDate:
                return firstIndex(whereAny: ["posted date"])
            case .description:
                return firstIndex(whereAny: ["description", "details", "memo", "name", "payee"])
            case .merchant:
                return firstIndex(whereAny: ["merchant"])
            case .amount:
                return firstIndex(whereAny: ["amount", "amount (usd)", "amt", "value", "total"])
            case .debit:
                return firstIndex(whereAny: ["debit", "withdrawal", "outflow", "charge"])
            case .credit:
                return firstIndex(whereAny: ["credit", "deposit", "inflow"])
            case .category:
                return firstIndex(whereAny: ["category", "classification"])
            case .type:
                return firstIndex(whereAny: ["transaction type", "type"])
            }
        }
    }

    // MARK: - Parsing

    private static func amountHasExplicitSign(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("+") { return true }
        return trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
    }

    private static func resolveRawAmount(amountText: String?, debitText: String?, creditText: String?) -> Double? {
        if let amountText, amountHasExplicitSign(amountText), let v = parseAmount(amountText) {
            return v
        }

        if let debitText, let d = parseAmount(debitText), abs(d) > 0.0001 {
            return -abs(d)
        }

        if let creditText, let c = parseAmount(creditText), abs(c) > 0.0001 {
            return abs(c)
        }

        if let amountText, let v = parseAmount(amountText) {
            return v
        }

        return nil
    }

    private static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let isParenNegative = (trimmed.first == "(") && (trimmed.last == ")")

        var normalized = trimmed
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Some exports use an explicit leading plus.
        if normalized.hasPrefix("+") {
            normalized = String(normalized.dropFirst())
        }

        // Locale-aware parsing (decimal and currency styles) using app-wide formatter behavior.
        guard var val = CurrencyFormatter.parseAmount(normalized) else { return nil }
        if isParenNegative { val = -abs(val) }
        return val
    }

    private static func parseDate(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        let fmts = [
            "M/d/yyyy",
            "MM/dd/yyyy",
            "M/d/yy",
            "MM/dd/yy",
            "yyyy-MM-dd",
            "yyyy/MM/dd"
        ]

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current

        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: t) { return d }
        }

        return nil
    }

    // MARK: - Duplicate hint

    private static func looksLikeDuplicateExpense(
        date: Date,
        amount: Double,
        merchant: String,
        category: Category?,
        existing: [VariableExpense]
    ) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let candidateDays = candidateDaysSet(around: day, calendar: cal, windowDays: duplicateDayWindow)
        let merchantKey = MerchantNormalizer.normalizeKey(merchant)

        var dayAmountMatches: [VariableExpense] = []
        dayAmountMatches.reserveCapacity(4)

        for e in existing {
            if abs(e.amount - amount) > 0.0001 { continue }
            let eDay = cal.startOfDay(for: e.transactionDate)
            if !candidateDays.contains(eDay) { continue }

            dayAmountMatches.append(e)

            let existingMerchant = MerchantNormalizer.normalizeKey(e.descriptionText)
            if existingMerchant == merchantKey { return true }
        }

        if dayAmountMatches.isEmpty { return false }

        if dayAmountMatches.count == 1 { return true }

        guard let category else { return false }
        let sameCategory = dayAmountMatches.filter { $0.category?.id == category.id }
        if sameCategory.isEmpty { return false }

        // Only mark as duplicate if the match is not ambiguous.
        if sameCategory.count == 1 { return true }
        return false
    }

    private static func looksLikeDuplicateIncome(date: Date, amount: Double, merchant: String, existing: [Income]) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        for i in existing {
            if abs(i.amount - amount) > 0.0001 { continue }
            let iDay = cal.startOfDay(for: i.date)
            if iDay != day { continue }

            let existingSource = MerchantNormalizer.normalizeKey(i.source)
            if existingSource == MerchantNormalizer.normalizeKey(merchant) { return true }
        }

        return false
    }

    private static func looksLikeDuplicatePlannedExpense(
        date: Date,
        amount: Double,
        merchant: String,
        category: Category?,
        existing: [PlannedExpense]
    ) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let candidateDays = candidateDaysSet(around: day, calendar: cal, windowDays: duplicateDayWindow)

        let merchantKey = MerchantNormalizer.normalizeKey(merchant)

        var dayAmountMatches: [PlannedExpense] = []
        dayAmountMatches.reserveCapacity(4)

        for p in existing {
            let effectiveAmount = (abs(p.actualAmount) > 0.0001) ? p.actualAmount : p.plannedAmount
            if abs(effectiveAmount - amount) > 0.0001 { continue }
            let pDay = cal.startOfDay(for: p.expenseDate)
            if !candidateDays.contains(pDay) { continue }

            dayAmountMatches.append(p)

            let plannedKey = MerchantNormalizer.normalizeKey(p.title)
            if !merchantKey.isEmpty, plannedKey == merchantKey { return true }
        }

        if dayAmountMatches.isEmpty { return false }

        if dayAmountMatches.count == 1 { return true }

        // Category match: a strong duplicate signal for planned expenses.
        if let category {
            let sameCategory = dayAmountMatches.filter { $0.category?.id == category.id }
            if sameCategory.isEmpty == false {
                if sameCategory.count == 1 { return true }
            }
        }

        // Title similarity fallback (for generic planned categories, e.g. "Gas", "Phone", etc.)
        if !merchantKey.isEmpty {
            let similar = dayAmountMatches.filter {
                let plannedKey = MerchantNormalizer.normalizeKey($0.title)
                if plannedKey.isEmpty { return false }
                return plannedKey.contains(merchantKey) || merchantKey.contains(plannedKey)
            }
            if !similar.isEmpty, (dayAmountMatches.count == 1 || similar.count == 1) { return true }
        }

        return false
    }

    private static func candidateDaysSet(around day: Date, calendar: Calendar, windowDays: Int) -> Set<Date> {
        var days: [Date] = [day]
        if windowDays <= 0 { return Set(days) }

        for offset in 1...windowDays {
            if let earlier = calendar.date(byAdding: .day, value: -offset, to: day) {
                days.append(calendar.startOfDay(for: earlier))
            }
            if let later = calendar.date(byAdding: .day, value: offset, to: day) {
                days.append(calendar.startOfDay(for: later))
            }
        }

        return Set(days)
    }
}
