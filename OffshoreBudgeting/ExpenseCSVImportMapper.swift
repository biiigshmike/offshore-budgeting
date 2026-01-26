import Foundation

struct ExpenseCSVImportMapper {

    static func map(
        csv: ParsedCSV,
        categories: [Category],
        existingExpenses: [VariableExpense],
        learnedRules: [String: ImportMerchantRule]
    ) -> [ExpenseCSVImportRow] {

        let headerMap = HeaderMap(headers: csv.headers)

        var out: [ExpenseCSVImportRow] = []
        out.reserveCapacity(csv.rows.count)

        for (idx, fields) in csv.rows.enumerated() {
            let lineNumber = idx + 2

            let isAppleRow = headerMap.isAppleCardRow(fields: fields)

            let dateText = headerMap.value(in: fields, for: .date, isAppleRow: isAppleRow) ?? ""
            let postedDateText = headerMap.value(in: fields, for: .postedDate, isAppleRow: isAppleRow)
            let descText = headerMap.value(in: fields, for: .description, isAppleRow: isAppleRow) ?? ""
            let merchantText = headerMap.value(in: fields, for: .merchant, isAppleRow: isAppleRow)
            let amountText = headerMap.value(in: fields, for: .amount, isAppleRow: isAppleRow) ?? ""
            let categoryText = headerMap.value(in: fields, for: .category, isAppleRow: isAppleRow)
            let typeText = headerMap.value(in: fields, for: .type, isAppleRow: isAppleRow)

            let parsedDate = parseDate(postedDateText ?? "") ?? parseDate(dateText)

            guard let date = parsedDate, let rawAmount = parseAmount(amountText) else {
                let safeDate = Date()
                let rawMerchant = merchantText?.isEmpty == false ? (merchantText ?? "") : descText

                let row = ExpenseCSVImportRow(
                    sourceLine: lineNumber,
                    originalDateText: dateText,
                    originalDescriptionText: descText,
                    originalAmountText: amountText,
                    originalCategoryText: categoryText,
                    finalDate: safeDate,
                    finalMerchant: MerchantNormalizer.normalize(rawMerchant),
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

            let rawMerchant = (merchantText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (merchantText ?? "")
                : descText

            let normalizedMerchantKey = MerchantNormalizer.normalize(rawMerchant)
            let learned = learnedRules[normalizedMerchantKey]

            // Apply learned preferred name if exists
            let finalMerchant = learned?.preferredName ?? normalizedMerchantKey

            let kind = resolveKind(typeText: typeText, rawAmount: rawAmount)
            let finalAmount = abs(rawAmount)

            var isDup = false
            if kind == .expense {
                isDup = looksLikeDuplicate(date: date, amount: finalAmount, merchant: finalMerchant, existing: existingExpenses)
            }

            // Category suggestion
            let suggestion = CategoryMatchingEngine.suggest(
                csvCategory: categoryText,
                merchant: finalMerchant,
                availableCategories: categories,
                learnedRule: learned
            )

            // Default bucket + check behavior matches your old flow
            let bucket: ExpenseCSVImportBucket
            let includeDefault: Bool
            let selectedCategory: Category?

            if kind == .income {
                bucket = .payment
                includeDefault = true
                selectedCategory = nil
            } else if isDup {
                bucket = .possibleDuplicate
                includeDefault = false
                selectedCategory = suggestion.category
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
                originalAmountText: amountText,
                originalCategoryText: categoryText,
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

    private static func resolveKind(typeText: String?, rawAmount: Double) -> ExpenseCSVImportKind {
        let t = (typeText ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if !t.isEmpty {
            if t.contains("purchase") || t.contains("debit") { return .expense }
            if t.contains("payment") || t.contains("credit") { return .income }
            if t.contains("refund") || t.contains("reversal") { return .income }
            if t.contains("fee") || t.contains("interest") { return .expense }
        }

        // Fallback (for exports without Type)
        return rawAmount < 0 ? .expense : .income
    }

    // MARK: - Header mapping

    private enum Field {
        case date
        case postedDate
        case description
        case merchant
        case amount
        case category
        case type
    }

    private struct HeaderMap {
        let headers: [String]
        private let lower: [String]

        init(headers: [String]) {
            self.headers = headers
            self.lower = headers.map { $0.lowercased() }
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

        func isAppleCardRow(fields: [String]) -> Bool {
            guard fields.count >= 7 else { return false }
            let a = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let b = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let c = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)

            if parseDate(a) == nil { return false }
            if parseDate(b) == nil { return false }
            return !c.isEmpty
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
            case .category:
                return firstIndex(whereAny: ["category", "classification"])
            case .type:
                return firstIndex(whereAny: ["transaction type", "type"])
            }
        }
    }

    // MARK: - Parsing

    private static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let isParenNegative = (trimmed.first == "(") && (trimmed.last == ")")

        let stripped = trimmed
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard var val = Double(stripped) else { return nil }
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

    private static func looksLikeDuplicate(date: Date, amount: Double, merchant: String, existing: [VariableExpense]) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)

        for e in existing {
            if abs(e.amount - amount) > 0.0001 { continue }
            let eDay = cal.startOfDay(for: e.transactionDate)
            if eDay != day { continue }

            let existingMerchant = MerchantNormalizer.normalize(e.descriptionText)
            if existingMerchant == MerchantNormalizer.normalize(merchant) { return true }
        }

        return false
    }
}
