#if DEBUG && canImport(FoundationModels)
import Foundation
import FoundationModels
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaTokenDiagnosticsTests {
    @Test func reportIsPrivateCorrelatedAndSingleEvenOnCancellation() async {
        let session = UUID()
        var reports: [String] = []
        let diagnostic = MarinaTokenDiagnostics(sessionID: session, rebuilt: true, historyCount: 0,
            initial: [], instructions: "SECRET instructions", tools: [], prompt: "SECRET question", preparation: .zero,
            measure: false, enabled: true, onReport: { reports.append($0) })
        let attempt = diagnostic.entered(tool: "SECRET tool", arguments: "SECRET argument 987654.32")
        var request = MarinaDataRequest(tool: .expenses)
        request.cardID = "SECRET record ID"; request.startDate = "2067-12-30"; request.search = "SECRET merchant"
        request.hypotheticalSpending = 987654.32
        diagnostic.mapped(attempt: attempt, request: request)
        diagnostic.database(attempt: attempt)
        diagnostic.output(attempt: attempt, text: "SECRET response 987654.32", status: "SECRET status")
        diagnostic.failed(attempt: attempt)
        diagnostic.checkpoint("SECRET checkpoint")
        diagnostic.warning("SECRET warning", .approaching)
        diagnostic.finish(entries: [], outcome: "cancelled", reset: true)
        diagnostic.finish(entries: [], outcome: "complete", reset: false)
        await MarinaTokenDiagnostics.flushReports()
        #expect(reports.count == 1)
        let report = reports.first ?? ""
        #expect(!report.contains("SECRET")); #expect(!report.contains("987654.32")); #expect(!report.contains("2067-12-30"))
        #expect(report.contains("session=\(session)"))
        #expect(report.contains("attempt=1 stage=entered tool=unknown"))
        #expect(report.contains("attempt=1 stage=mapped"))
        #expect(report.contains("attempt=1 stage=database_execution"))
        #expect(report.contains("attempt=1 stage=failed"))
        #expect(report.contains("outcome=cancelled session_reset=true"))
        #expect(report.contains("format=4"))
        #expect(report.contains("final_transcript=unavailable"))
        #expect(report.contains("stream_to_first_text_seconds=unavailable"))
        #expect(report.contains("threshold_fraction=0.75"))
        let lines = report.split(separator: "\n")
        #expect(lines.first?.hasSuffix("BEGIN REPORT") == true)
        #expect(lines.last?.hasSuffix("END REPORT") == true)
        let prefix = lines.first?.components(separatedBy: "]").first
        #expect(lines.allSatisfy { $0.components(separatedBy: "]").first == prefix })
    }

    @Test func repeatedRequestsCompareAllFieldsAndCountsDistinguishExecution() async {
        var report = ""
        let diagnostic = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: false, historyCount: 1,
            initial: [], instructions: "", tools: [], prompt: "", preparation: .zero,
            measure: false, enabled: true, onReport: { report = $0 })
        let request = MarinaDataRequest(tool: .expenses)
        for index in 0..<4 {
            let attempt = diagnostic.entered(tool: "readExpenses")
            var variant = request
            if index == 2 { variant.forcePresentation = true }
            if index == 3 { variant.comparisonStartDate = "2026-10-01" }
            diagnostic.mapped(attempt: attempt, request: variant)
            if index == 0 { diagnostic.database(attempt: attempt) }
        }
        diagnostic.checkpoint("preflight_start"); diagnostic.checkpoint("preflight_end")
        diagnostic.checkpoint("stream_start"); diagnostic.firstText(); diagnostic.firstText(); diagnostic.checkpoint("stream_end")
        diagnostic.checkpoint("postflight_start"); diagnostic.checkpoint("postflight_end")
        diagnostic.finish(entries: [], outcome: "failed", reset: true)
        await MarinaTokenDiagnostics.flushReports()
        #expect(report.contains("attempt_count=4 database_execution_count=1 tool_execution_count=0"))
        let requests = report.split(separator: "\n").filter { $0.contains("stage=mapped") }
        #expect(requests[1].hasSuffix("same_request_as_call=1"))
        #expect(requests[2].hasSuffix("same_request_as_call=none"))
        #expect(requests[3].hasSuffix("same_request_as_call=none"))
        #expect(!report.contains("stream_to_first_text_seconds=unavailable"))
        #expect(!report.contains("context_preflight_seconds=unavailable"))
        #expect(!report.contains("context_postflight_seconds=unavailable"))
    }

    @Test func disabledCollectorProducesNothing() async {
        var reports: [String] = []
        let diagnostic = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: true, historyCount: 0,
            initial: [], instructions: "", tools: [], prompt: "", preparation: .zero,
            measure: false, enabled: false, onReport: { reports.append($0) })
        #expect(diagnostic.entered(tool: "readExpenses") == 0)
        diagnostic.finish(entries: [], outcome: "complete", reset: false)
        await MarinaTokenDiagnostics.flushReports()
        #expect(reports.isEmpty)
    }

    @Test func instrumentationLeavesReturnedFactsAndQueriesUnchanged() async throws {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let workspace = Workspace(name: "SECRET workspace", hexColor: "#FFFFFF")
        context.insert(workspace)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        context.insert(VariableExpense(descriptionText: "SECRET purchase", amount: 31.38, transactionDate: now, workspace: workspace))
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: now)
        var request = MarinaDataRequest(tool: .expenses); request.relativePeriod = .currentMonth
        let plain = MarinaToolBridge(); plain.begin(service: service, onResult: {})
        let expected = try plain.call(request)
        let measured = MarinaToolBridge(); measured.begin(service: service, onResult: {})
        var report = ""
        let diagnostic = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: true, historyCount: 0, initial: [], instructions: "", tools: [], prompt: "", preparation: .zero, measure: false, enabled: true, onReport: { report = $0 })
        measured.diagnostics = diagnostic
        let attempt = diagnostic.entered(tool: "readExpenses")
        #expect(try measured.call(request, diagnosticAttempt: attempt) == expected)
        #expect(measured.requests == plain.requests)
        let id = UUID()
        let left = measured.answer(id: id, prompt: "Total", narration: "Answer")
        let right = plain.answer(id: id, prompt: "Total", narration: "Answer")
        #expect(left.rows.map(\.amount) == right.rows.map(\.amount))
        #expect(left.contextStatus == right.contextStatus)
        diagnostic.finish(entries: [], outcome: "complete", reset: false)
        await MarinaTokenDiagnostics.flushReports()
        #expect(!report.contains("SECRET")); #expect(!report.contains("31.38"))
        #expect(report.contains("tool_execution_count=1"))
        plain.end(); measured.end()
    }
}
#endif
