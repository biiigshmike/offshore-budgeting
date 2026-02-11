//
//  ExpenseImageAndPaystubImportParserTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/11/26.
//

import Foundation
import Testing
@testable import Offshore

struct ExpenseImageAndPaystubImportParserTests {

    // MARK: - Image OCR line fixtures

    @Test func imageRef1Style_ParsesAppleCardRowsWithPaymentAndExpenses() throws {
        let lines = [
            "Latest Card Transactions",
            "Payment +$1,030.27",
            "The Gentlemens Cutlery $75.00",
            "ARCO $27.50 2/3/26",
            "Safeway $50.00 2/3/26",
            "DoorDash $20.78 2/2/26"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 5)
        #expect(rows.contains {
            $0.description.lowercased().contains("payment")
                && $0.amount == "1030.27"
                && $0.type == "income"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("DOORDASH")
                && $0.date == "02/02/2026"
                && $0.amount == "20.78"
                && $0.type == "expense"
        })
    }

    @Test func imageRef1Style_FragmentedAmountChevronLinesUsePreviousMerchant() throws {
        let lines = [
            "Latest Card Transactions",
            "DoorDash",
            "$20.78 > 2%",
            "2/2/26",
            "Safeway",
            "$50.00 > 2%",
            "2/3/26"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 2)
        #expect(rows.contains {
            $0.description.uppercased().contains("DOORDASH")
                && $0.date == "02/02/2026"
                && $0.amount == "20.78"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("SAFEWAY")
                && $0.date == "02/03/2026"
                && $0.amount == "50.00"
                && $0.type == "expense"
        })
    }

    @Test func imageRef1Style_DetailAndLocationLinesDoNotOverrideMerchant() throws {
        let lines = [
            "DoorDash",
            "Apple Pay",
            "$20.78 > 2%",
            "2/2/26",
            "Safeway",
            "Sacramento, CA",
            "$50.00 > 2%",
            "2/3/26"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 2)
        #expect(rows.contains {
            $0.description.uppercased().contains("DOORDASH")
                && $0.amount == "20.78"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("SAFEWAY")
                && $0.amount == "50.00"
                && $0.type == "expense"
        })
        #expect(!rows.contains { $0.description == "2%" || $0.description == "43)" })
    }

    @Test func imageRef1Style_SeparatedColumnsStillProduceRows() throws {
        let lines = [
            "Card Transactions",
            "Payment",
            "From PNC Bank (...1115)",
            "The Gentlemens Cutlery",
            "Apple Pay",
            "Home Chef",
            "Apple Pay",
            "ARCO",
            "2/3/26",
            "Safeway",
            "2/3/26",
            "DoorDash",
            "2/2/26",
            "Target",
            "2/2/26",
            "Starbucks",
            "2/2/26",
            "DoorDash",
            "1/30/26",
            "+$1,030.27",
            "$75.00",
            "$100.90",
            "$27.50",
            "$50.00",
            "$20.78",
            "$102.14",
            "$25.00",
            "$113.06"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 8)
        #expect(rows.contains {
            $0.description.uppercased().contains("THE GENTLEMENS CUTLERY")
                && $0.amount == "75.00"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("HOME CHEF")
                && $0.amount == "100.90"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("DOORDASH")
                && $0.amount == "20.78"
                && $0.type == "expense"
        })
    }

    @Test func imageRelativeDate_HoursAgoUsesReferenceDay() throws {
        let lines = [
            "Payment +$1,030.27",
            "2 hours ago"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 1)
        #expect(rows.contains {
            $0.description.lowercased().contains("payment")
                && $0.date == "02/11/2026"
                && $0.amount == "1030.27"
                && $0.type == "income"
        })
    }

    @Test func imageRelativeDate_WeekdayUsesMostRecentMatchingDay() throws {
        let lines = [
            "DoorDash $20.78",
            "Saturday"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 1)
        #expect(rows.contains {
            $0.description.uppercased().contains("DOORDASH")
                && $0.date == "02/07/2026"
                && $0.amount == "20.78"
                && $0.type == "expense"
        })
    }

    @Test func imageRef2Style_ParsesMonthHeaderAndDatedRows() throws {
        let lines = [
            "December 2025",
            "ParkStash $165.08 12/13/25",
            "DD * doordashdashpass $9.99 12/13/25",
            "Balance Adjustment $52.99 12/12/25",
            "DoorDash $61.93 12/12/25",
            "Nugget Markets $53.22 12/12/25"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 5)
        #expect(rows.contains {
            $0.description.uppercased().contains("PARKSTASH")
                && $0.date == "12/13/2025"
                && $0.amount == "165.08"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.description.lowercased().contains("balance adjustment")
                && $0.amount == "52.99"
        })
    }

    @Test func imageRef3Style_ParsesJanuaryRows() throws {
        let lines = [
            "January 2026",
            "Daily Cash Adjustment $1.06 1/9/26",
            "Home Chef $120.68 1/9/26",
            "Target $27.89 1/9/26",
            "76 $41.78 1/9/26",
            "Ucdh Midtown Multispcl $522.08 1/6/26"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 5)
        #expect(rows.contains {
            $0.description.lowercased().contains("daily cash adjustment")
                && $0.date == "01/09/2026"
                && $0.amount == "1.06"
                && $0.type == "income"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("HOME CHEF")
                && $0.amount == "120.68"
                && $0.type == "expense"
        })
    }

    @Test func imageRef4Style_ParsesBankTransactions() throws {
        let lines = [
            "February 09, 2026",
            "APPLECARD GSBANK PAYMENT ACH WEB x8892 -$1,030.27 $3,397.03",
            "February 06, 2026",
            "ATM TRANSACTION FEE - WITHDRAWAL -$3.00 $4,427.30",
            "ATM WITHDRAWAL MACRCx2465N0205 0336 -$103.50 $4,430.30",
            "February 05, 2026",
            "CALIFORNIA EDD DI DEPOSIT ACH CREDIT $2,792.00 $4,533.80"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 4)
        #expect(rows.contains {
            $0.date == "02/09/2026"
                && $0.description.uppercased().contains("APPLECARD GSBANK PAYMENT")
                && $0.amount == "-1030.27"
                && $0.type == "income"
        })
        #expect(rows.contains {
            $0.date == "02/06/2026"
                && $0.description.uppercased().contains("ATM TRANSACTION FEE")
                && $0.amount == "-3.00"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.date == "02/05/2026"
                && $0.description.uppercased().contains("CALIFORNIA EDD DI DEPOSIT")
                && $0.amount == "2792.00"
                && $0.type == "income"
        })
    }

    @Test func imageRef6Style_ParsesBankRowsWithSectionDates() throws {
        let lines = [
            "January 21, 2026",
            "ATM TRANSACTION FEE - WITHDRAWAL -$3.00 $626.37",
            "ATM WITHDRAWAL MACRCx2470N0121 0336 -$98.50 $629.37",
            "NISSAN RET AUTO LOAN ACH WEB-RECUR x9552 -$318.00 $727.87",
            "January 20, 2026",
            "TMOBILE AU BELLEVUE WA N0120 0336 PAYMENT POS001 x8897 -$106.14 $1,045.87"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 4)
        #expect(rows.contains {
            $0.date == "01/21/2026"
                && $0.description.uppercased().contains("ATM TRANSACTION FEE")
                && $0.amount == "-3.00"
                && $0.type == "expense"
        })
        #expect(rows.contains {
            $0.date == "01/20/2026"
                && $0.description.uppercased().contains("TMOBILE")
                && $0.amount == "-106.14"
                && $0.type == "expense"
        })
    }

    @Test func imageRef5Style_ParsesPaymentsAndExpenses() throws {
        let lines = [
            "Feb 03, 2026",
            "AUTOMATIC PAYMENT - THANK -$225.07",
            "AMAZON MARKETPLACE $14.13",
            "Feb 02, 2026",
            "AMAZON MARKETPLACE $58.71",
            "AMAZON MARKETPLACE $48.60"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 3)
        #expect(rows.contains {
            $0.date == "02/03/2026"
                && $0.description.uppercased().contains("AUTOMATIC PAYMENT")
                && $0.amount == "-225.07"
                && $0.type == "income"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("AMAZON MARKETPLACE")
                && $0.amount == "14.13"
                && $0.type == "expense"
        })
    }

    @Test func imageRef7Style_ParsesAmexStyleRows() throws {
        let lines = [
            "Oct 23 - Nov 21, 2025",
            "MOBILE PAYMENT - THANK YOU -$45.44",
            "Nov 15, 2025",
            "BP FDMS CAT $45.44",
            "Nov 10, 2025"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count >= 2)
        #expect(rows.contains {
            $0.description.uppercased().contains("MOBILE PAYMENT")
                && $0.amount == "-45.44"
                && $0.type == "income"
        })
        #expect(rows.contains {
            $0.description.uppercased().contains("BP FDMS CAT")
                && $0.amount == "45.44"
                && $0.type == "expense"
        })
    }

    @Test func imageRef8Style_ParsesAmazonReceiptGrandTotal() throws {
        let lines = [
            "See details",
            "Anker USB C to USB C Cable, Type-C",
            "Order summary",
            "Order placed February 2, 2026",
            "Grand Total: $14.13"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count == 1)
        #expect(rows[0].date == "02/02/2026")
        #expect(rows[0].amount == "14.13")
        #expect(rows[0].type == "expense")
        #expect(!rows[0].description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func imageRef9Style_ParsesPaycheckScreenshotAsIncome() throws {
        let lines = [
            "Paycheck",
            "Dec 8 - Dec 21",
            "$2,817.83",
            "Take home pay $2,817.83"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count == 1)
        #expect(rows[0].date == "12/21/2025")
        #expect(rows[0].description == "Paycheck")
        #expect(rows[0].amount == "2817.83")
        #expect(rows[0].type == "income")
    }

    @Test func imagePayrollSignalsWithoutExactPaycheckWord_StillParsesIncome() throws {
        let lines = [
            "Pay check",
            "Dec 8 - Dec 21",
            "$2,817.83",
            "Paycheck breakdown",
            "Earned this period $4,284.00",
            "Federal income tax -$553.97",
            "State and local taxes -$284.60",
            "Social Security and Medicare -$327.72"
        ]

        let parsed = try ExpenseImageImportParser.parse(recognizedLines: lines, referenceDate: fixedNow)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(rows.count == 1)
        #expect(rows[0].date == "12/21/2025")
        #expect(rows[0].description == "Paycheck")
        #expect(rows[0].amount == "2817.83")
        #expect(rows[0].type == "income")
    }

    // MARK: - Paystub PDF

    @Test func paystubPDF_ParsesNetPayAndDate() throws {
        let url = fixtureURL(named: "paystub.pdf")
        let parsed = try PaystubPDFImportParser.parse(url: url)
        let rows = parsed.rows.compactMap { ParsedRow(fields: $0) }

        #expect(parsed.headers == ["Date", "Description", "Amount", "Category", "Type"])
        #expect(rows.count == 1)
        #expect(rows[0].date == "12/24/2025")
        #expect(rows[0].description == "Paycheck")
        #expect(rows[0].amount == "2817.83")
        #expect(rows[0].type == "income")
    }

    // MARK: - Helpers

    private var fixedNow: Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 2
        comps.day = 11
        return Calendar.current.date(from: comps) ?? .now
    }

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

    private func fixtureURL(named fileName: String) -> URL {
        let testsFolderURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoURL = testsFolderURL.deletingLastPathComponent()
        let url = repoURL.appendingPathComponent(fileName)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }
}
