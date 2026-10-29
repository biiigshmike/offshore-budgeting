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
        print("MarinaBenchmark context_capacity=\(model.contextSize)")
        let queryTokens = try await model.tokenCount(for: MarinaQueryOutcome.generationSchema)
        let queryEstimate = runtime.diagnosticEstimatedQuerySchemaTokens
        print("MarinaBenchmark phases=query_with_five_tools,narration_without_tools query_schema=\(queryTokens) query_schema_estimate=\(queryEstimate)")
        #expect(queryEstimate >= queryTokens, "Recalibrate the query schema fallback when its schema changes.")
        for factCount in [0, 1, 6] {
            let facts = (0..<factCount).map { index in
                MarinaNarrationEvidence(id: "q0f\(index)", subject: "Verified subject", relation: "totals",
                    value: "$100", scope: "October", isFocus: index == 0)
            }
            let schema = try MarinaNarrationSchema.make(act: facts.isEmpty ? .greeting : .answer, evidence: facts)
            let narrationTokens = try await model.tokenCount(for: schema)
            let narrationEstimate = MarinaNarrationSchema.estimatedTokens(schema)
            print("MarinaBenchmark narration_facts=\(factCount) narration_schema=\(narrationTokens) fallback_narration_estimate=\(narrationEstimate)")
            #expect(narrationEstimate >= narrationTokens, "Recalibrate the current evidence schema fallback when its schema changes.")
        }
        var baselineTools: Int?
        var baselineTranscript: Int?
        for (name, names) in sets {
            let tools = all.filter { names.contains($0.name) }
            #expect(tools.count == names.count)
            let session = LanguageModelSession(tools: tools, instructions: instructions)
            do {
                let toolTokens = try await model.tokenCount(for: tools)
                let transcriptTokens = try await model.tokenCount(for: Array(session.transcript))
                if name == "baseline" {
                    baselineTools = toolTokens; baselineTranscript = transcriptTokens
                    let schemaBytes = try tools.reduce(0) { try $0 + JSONEncoder().encode($1.parameters).count }
                    let estimate = MarinaContextBudget.estimatedPrefixTokens(instructions: instructions, schemaBytes: schemaBytes)
                    print("MarinaBenchmark fallback_initial_estimate=\(estimate) schema_bytes=\(schemaBytes)")
                    print("MarinaBenchmark query_prefix_with_output_schema=\(transcriptTokens + queryTokens)")
                    #expect(estimate >= transcriptTokens, "Recalibrate the prefix fallback when production instructions or schemas change.")
                }
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
