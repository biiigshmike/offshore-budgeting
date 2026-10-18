import Foundation
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaToolSetBenchmarkTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_SCHEMA_BENCHMARK"] == "1",
                   "Set MARINA_SCHEMA_BENCHMARK=1 on a device supporting native token counting."))
    func unchangedProductionToolCombinations() async throws {
        guard #available(iOS 26.4, macCatalyst 26.4, macOS 26.4, *) else {
            print("MarinaBenchmark blocked=token_api_unavailable")
            throw BenchmarkError.measurementUnavailable
        }
        let model = SystemLanguageModel.default
        let runtime = MarinaConversationRuntime()
        let workspace = Workspace(name: "Benchmark Workspace", hexColor: "#123456")
        let instructions = runtime.diagnosticInstructions(workspace: workspace, homeContext: nil,
            defaultBudgetingPeriod: .monthly, now: Date(timeIntervalSince1970: 1_792_224_000))
        let all = runtime.diagnosticTools()
        let sets: [(String, [String])] = [
            ("baseline", all.map(\.name)),
            ("spending", ["findRecords", "readExpenses"]),
            ("income", ["findRecords", "readIncome"]),
            ("budget", ["findRecords", "readBudgetSummary"]),
            ("accounts", ["findRecords", "readAccounts"]),
            ("combined", ["findRecords", "readExpenses", "readIncome"])
        ]
        print("MarinaBenchmark accounting=component counts overlap; do not sum")
        var baselineTools: Int?
        var baselineTranscript: Int?
        for (name, names) in sets {
            let tools = all.filter { names.contains($0.name) }
            #expect(tools.count == names.count)
            let session = LanguageModelSession(tools: tools, instructions: instructions)
            do {
                let toolTokens = try await model.tokenCount(for: tools)
                let transcriptTokens = try await model.tokenCount(for: Array(session.transcript))
                if name == "baseline" { baselineTools = toolTokens; baselineTranscript = transcriptTokens }
                let toolDelta = baselineTools.map { toolTokens - $0 }.map(String.init) ?? "unavailable"
                let transcriptDelta = baselineTranscript.map { transcriptTokens - $0 }.map(String.init) ?? "unavailable"
                print("MarinaBenchmark configuration=\(name) tool_set=\(toolTokens) initial_transcript=\(transcriptTokens) tool_delta=\(toolDelta) transcript_delta=\(transcriptDelta)")
            } catch {
                print("MarinaBenchmark configuration=\(name) measurement=unavailable")
                throw BenchmarkError.measurementUnavailable
            }
        }
        for tool in all {
            let schema = try await model.tokenCount(for: tool.parameters)
            let complete = try await model.tokenCount(for: [tool])
            print("MarinaBenchmark tool=\(tool.name) argument_schema=\(schema) complete_definition=\(complete)")
        }
    }
    private enum BenchmarkError: Error { case measurementUnavailable }
}
#endif
