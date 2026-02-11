//
//  StatementPDFImportParserTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/11/26.
//

import Foundation
import Testing
@testable import Offshore

struct StatementPDFImportParserTests {

    // MARK: - PDF Extraction

    @Test func statementOpt1_ExtractsExpectedTransactions() throws {
        let rows = try parsedRows(fromFixture: "StatementOpt1.pdf")

        #expect(rows.count >= 12)
        #expect(
            rows.contains {
                $0.date == "12/24/2025"
                    && $0.description.lowercased().contains("direct deposit")
                    && $0.amount == "2817.83"
                    && $0.type == "income"
            }
        )
        #expect(
            rows.contains {
                $0.date == "01/06/2026"
                    && $0.description.lowercased().contains("openai")
                    && $0.amount == "40.00"
                    && $0.type == "expense"
            }
        )
        #expect(
            rows.contains {
                $0.description.lowercased().contains("atm transaction fee")
                    && $0.amount == "3.00"
                    && $0.type == "expense"
            }
        )
        #expect(rows.allSatisfy { !$0.description.lowercased().contains("transaction summary") })
    }

    @Test func statementOpt2_ExtractsExpectedTransactionsAndSkipsSummary() throws {
        let rows = try parsedRows(fromFixture: "StatementOpt2.pdf")

        #expect(rows.count >= 30)
        #expect(
            rows.contains {
                $0.date == "01/04/2026"
                    && $0.description.lowercased().contains("ach deposit")
                    && $0.amount == "-703.51"
                    && $0.type == "income"
            }
        )
        #expect(
            rows.contains {
                $0.description.uppercased().contains("STARBUCKS")
                    && $0.amount == "25.00"
                    && $0.type == "expense"
            }
        )
        #expect(
            rows.contains {
                $0.date == "01/06/2026"
                    && $0.description.uppercased().contains("APPLE.COM/BILL")
                    && $0.amount == "51.97"
                    && $0.type == "expense"
            }
        )
        #expect(rows.allSatisfy { !$0.description.lowercased().contains("total payments for this period") })
    }

    @Test func statementOpt3_ExtractsExpectedTransactionsAndIgnoresPointsNoise() throws {
        let rows = try parsedRows(fromFixture: "StatementOpt3.pdf")

        #expect(rows.count >= 5)
        #expect(rows.count <= 8)
        #expect(
            rows.contains {
                $0.date == "01/02/2026"
                    && $0.description.lowercased().contains("automatic payment")
                    && $0.amount == "-277.64"
                    && $0.type == "income"
            }
        )
        #expect(
            rows.contains {
                $0.date == "12/10/2025"
                    && $0.description.uppercased().contains("AMAZON MARKETPLACE")
                    && $0.amount == "11.92"
                    && $0.type == "expense"
            }
        )
        #expect(rows.allSatisfy { $0.amount != "1192.00" })
    }

    @Test func statementOpt4_ExtractsPaymentRowAndSkipsAprRows() throws {
        let rows = try parsedRows(fromFixture: "StatementOpt4.pdf")

        #expect(rows.count >= 1)
        #expect(
            rows.contains {
                $0.date == "11/15/2025"
                    && $0.description.lowercased().contains("mobile payment")
                    && $0.amount == "-45.44"
                    && $0.type == "income"
            }
        )
        #expect(rows.allSatisfy { !$0.description.lowercased().contains("25.74%") })
    }

    // MARK: - Mapper Behavior

    @Test func pdfRows_FirstPassWithoutLearning_StayNeedsMoreData() throws {
        let parsed = try StatementPDFImportParser.parse(url: fixtureURL(named: "StatementOpt2.pdf"))
        let starbucksSource = try #require(parsed.rows.first { row in
            row.count >= 2 && row[1].uppercased().contains("STARBUCKS")
        })

        let csv = ParsedCSV(headers: parsed.headers, rows: [starbucksSource])
        let localCategory = Category(name: "Food & Drink", hexColor: "#000000")

        let mapped = ExpenseCSVImportMapper.map(
            csv: csv,
            categories: [localCategory],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(mapped.count == 1)
        #expect(mapped[0].kind == .expense)
        #expect(mapped[0].bucket == .needsMoreData)
        #expect(mapped[0].includeInImport == false)
    }

    @Test func pdfRows_AfterLearning_MoveToReady() throws {
        let parsed = try StatementPDFImportParser.parse(url: fixtureURL(named: "StatementOpt2.pdf"))
        let starbucksSource = try #require(parsed.rows.first { row in
            row.count >= 2 && row[1].uppercased().contains("STARBUCKS")
        })

        let csv = ParsedCSV(headers: parsed.headers, rows: [starbucksSource])
        let localCategory = Category(name: "Food & Drink", hexColor: "#000000")

        let firstPass = ExpenseCSVImportMapper.map(
            csv: csv,
            categories: [localCategory],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(firstPass.count == 1)
        let learnedKey = firstPass[0].sourceMerchantKey

        let learnedRule = ImportMerchantRule(
            merchantKey: learnedKey,
            preferredName: nil,
            preferredCategory: localCategory,
            workspace: nil
        )

        let secondPass = ExpenseCSVImportMapper.map(
            csv: csv,
            categories: [localCategory],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [learnedKey: learnedRule]
        )

        #expect(secondPass.count == 1)
        #expect(secondPass[0].bucket == .ready)
        #expect(secondPass[0].includeInImport == true)
        #expect(secondPass[0].selectedCategory?.id == localCategory.id)
    }

    @Test func pdfRows_RespectExplicitIncomeTypeInMapper() throws {
        let parsed = try StatementPDFImportParser.parse(url: fixtureURL(named: "StatementOpt1.pdf"))
        let depositSource = try #require(parsed.rows.first { row in
            row.count >= 2 && row[1].lowercased().contains("direct deposit")
        })

        let csv = ParsedCSV(headers: parsed.headers, rows: [depositSource])
        let mapped = ExpenseCSVImportMapper.map(
            csv: csv,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(mapped.count == 1)
        #expect(mapped[0].kind == .income)
        #expect(mapped[0].bucket == .payment)
        #expect(mapped[0].includeInImport == true)
    }

    // MARK: - Helpers

    private struct ParsedRow {
        let date: String
        let description: String
        let amount: String
        let category: String
        let type: String

        init?(fields: [String]) {
            guard fields.count >= 5 else { return nil }
            self.date = fields[0]
            self.description = fields[1]
            self.amount = fields[2]
            self.category = fields[3]
            self.type = fields[4]
        }
    }

    private func parsedRows(fromFixture fileName: String) throws -> [ParsedRow] {
        let parsed = try StatementPDFImportParser.parse(url: fixtureURL(named: fileName))
        #expect(parsed.headers == ["Date", "Description", "Amount", "Category", "Type"])
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }
        #expect(rows.count == parsed.rows.count)
        return rows
    }

    private func fixtureURL(named fileName: String) -> URL {
        let testsFolderURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoURL = testsFolderURL.deletingLastPathComponent()
        let url = repoURL.appendingPathComponent(fileName)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }
}
