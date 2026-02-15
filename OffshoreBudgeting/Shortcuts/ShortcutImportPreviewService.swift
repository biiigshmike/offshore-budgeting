import Foundation
import SwiftData

// MARK: - ShortcutImportPreviewError

enum ShortcutImportPreviewError: LocalizedError {
    case emptyClipboard
    case couldNotParseClipboard
    case imageFileUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "Clipboard text is empty."
        case .couldNotParseClipboard:
            return "Could not parse clipboard text into entries."
        case .imageFileUnavailable:
            return "The image file could not be read."
        }
    }
}

// MARK: - ShortcutImportPreview

struct ShortcutImportPreview {
    let summaryText: String
    let totalRows: Int
    let expenseRows: Int
    let incomeRows: Int
    let importableIncomeRows: Int
}

// MARK: - ShortcutImportPreviewService

@MainActor
final class ShortcutImportPreviewService {
    static let shared = ShortcutImportPreviewService()

    private init() {}

    func previewFromClipboard(text: String, referenceDate: Date = .now) throws -> ShortcutImportPreview {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ShortcutImportPreviewError.emptyClipboard }

        let parsed: ParsedCSV
        if let csvParsed = try parseAsCSVIfPossible(from: normalized) {
            parsed = csvParsed
        } else {
            let lines = normalized
                .split(whereSeparator: \.isNewline)
                .map { String($0) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else { throw ShortcutImportPreviewError.emptyClipboard }
            do {
                parsed = try ExpenseImageImportParser.parse(
                    recognizedLines: lines,
                    referenceDate: referenceDate
                )
            } catch {
                throw ShortcutImportPreviewError.couldNotParseClipboard
            }
        }

        return try preview(from: parsed)
    }

    func previewFromImage(url: URL, referenceDate: Date = .now) throws -> ShortcutImportPreview {
        let parsed = try ExpenseImageImportParser.parse(url: url, referenceDate: referenceDate)
        return try preview(from: parsed)
    }

    private func preview(from parsed: ParsedCSV) throws -> ShortcutImportPreview {
        let dataStore = OffshoreIntentDataStore.shared

        return try dataStore.performInSelectedWorkspace { modelContext, workspace in
            let categories = (workspace.categories ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let learnedRules = ImportLearningStore.fetchRules(for: workspace, modelContext: modelContext)

            let rows = ExpenseCSVImportMapper.map(
                csv: parsed,
                categories: categories,
                existingExpenses: workspace.variableExpenses ?? [],
                existingPlannedExpenses: workspace.plannedExpenses ?? [],
                existingIncomes: workspace.incomes ?? [],
                learnedRules: learnedRules
            )

            let totalRows = rows.count
            let expenseRows = rows.filter { !$0.isBlocked && $0.kind == .expense }.count
            let incomeRows = rows.filter { !$0.isBlocked && $0.kind == .income }.count
            let importableIncomeRows = rows.filter { row in
                !row.isBlocked &&
                row.kind == .income &&
                row.includeInImport &&
                !row.isMissingRequiredData
            }.count

            return ShortcutImportPreview(
                summaryText: makeSummaryText(
                    from: rows,
                    expenseRows: expenseRows,
                    incomeRows: incomeRows,
                    importableIncomeRows: importableIncomeRows
                ),
                totalRows: totalRows,
                expenseRows: expenseRows,
                incomeRows: incomeRows,
                importableIncomeRows: importableIncomeRows
            )
        }
    }

    private func parseAsCSVIfPossible(from text: String) throws -> ParsedCSV? {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let separators = [",", "\t", ";"]
        guard separators.contains(where: { firstLine.contains($0) }) else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offshore-shortcuts-clipboard-\(UUID().uuidString).csv")
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try CSVParser.parse(url: tempURL)
    }

    private func makeSummaryText(
        from rows: [ExpenseCSVImportRow],
        expenseRows: Int,
        incomeRows: Int,
        importableIncomeRows: Int
    ) -> String {
        let totalRows = rows.count
        let readyRows = rows.filter { !$0.isBlocked && $0.bucket == .ready }.count
        let possibleMatchRows = rows.filter { !$0.isBlocked && $0.bucket == .possibleMatch }.count
        let possibleDuplicateRows = rows.filter { !$0.isBlocked && $0.bucket == .possibleDuplicate }.count
        let needsMoreDataRows = rows.filter { !$0.isBlocked && $0.bucket == .needsMoreData }.count
        let paymentRows = rows.filter { !$0.isBlocked && $0.bucket == .payment }.count
        let includedRows = rows.filter { !$0.isBlocked && $0.includeInImport && !$0.isMissingRequiredData }.count

        var lines: [String] = []
        lines.append("Parsed \(totalRows.formatted()) rows")
        lines.append("\(expenseRows.formatted()) expenses, \(incomeRows.formatted()) income")
        lines.append("Ready: \(readyRows.formatted())")
        lines.append("Possible matches: \(possibleMatchRows.formatted())")
        lines.append("Possible duplicates: \(possibleDuplicateRows.formatted())")
        lines.append("Needs more data: \(needsMoreDataRows.formatted())")
        if paymentRows > 0 {
            lines.append("Payments/income rows: \(paymentRows.formatted())")
        }
        lines.append("Immediately importable: \(includedRows.formatted())")
        lines.append("Nothing is saved yet. Offshore saves only after you confirm Import.")

        if expenseRows > 0 && importableIncomeRows == 0 {
            lines.append("Detected expense-style rows only. Income Import won't save those rows.")
            lines.append("To import expenses, open a Card and use Import Expenses.")
        } else if incomeRows > 0 && importableIncomeRows == 0 {
            lines.append("No income rows are ready yet. Review fields in Offshore before importing.")
        }

        return lines.joined(separator: "\n")
    }
}
