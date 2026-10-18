#if DEBUG
import Foundation
import FoundationModels
import OSLog

/// Development-only, value-free observations. Raw snapshots live only until reporting completes.
@available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
@MainActor
final class MarinaTokenDiagnostics {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["MARINA_TOKEN_DIAGNOSTICS"] == "1" }
    private static let logger = Logger(subsystem: "Offshore", category: "MarinaTokens")
    private static var reports: [UUID: Task<Void, Never>] = [:]
    static func announce() {
        guard enabled else { return }
        logger.notice("MarinaTokens diagnostics enabled")
    }
    static func unavailable(historyCount: Int, warning: MarinaContextStatus?) {
        guard enabled else { return }
        announce()
        let diagnostic = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: false, historyCount: historyCount,
            initial: [], instructions: "", tools: [], prompt: "", preparation: .zero, measure: false)
        diagnostic.lines.append("model_session=not_created")
        diagnostic.warning("final", warning)
        diagnostic.finish(entries: [], outcome: "unavailable", reset: false)
    }
    static func flushReports() async {
        let pending = Array(reports.values)
        for task in pending { await task.value }
    }

    private let turn = UUID()
    private let started = ContinuousClock.now
    private var marks: [String: ContinuousClock.Instant] = [:]
    private var lines: [String]
    private var initial: [Transcript.Entry]
    private var instructions: String
    private var tools: [any Tool]
    private var prompt: String
    private var requests: [MarinaDataRequest] = []
    private var outputs: [(Int, String)] = []
    private var arguments: [(Int, String)] = []
    private var attemptStarts: [Int: ContinuousClock.Instant] = [:]
    private var databaseStarts: [Int: ContinuousClock.Instant] = [:]
    private var attempts = 0
    private var executions = 0
    private var finished = false
    private let measure: Bool
    private let onReport: ((String) -> Void)?
    private let active: Bool

    init(sessionID: UUID, rebuilt: Bool, historyCount: Int, initial: [Transcript.Entry], instructions: String,
         tools: [any Tool], prompt: String, preparation: Duration, measure: Bool = true,
         enabled: Bool = MarinaTokenDiagnostics.enabled, onReport: ((String) -> Void)? = nil) {
        self.initial = initial; self.instructions = instructions; self.tools = tools; self.prompt = prompt
        self.measure = measure; self.onReport = onReport; self.active = enabled
        lines = ["format=4", "os=\(ProcessInfo.processInfo.operatingSystemVersionString)",
                 "session=\(sessionID) turn=\(turn)",
                 "session_created=\(rebuilt) saved_answer_count=\(historyCount) initial_entries=\(initial.count)",
                 "accounting=component counts overlap; do not sum with transcript counts",
                 "session_preparation_seconds=\(Self.seconds(preparation))"]
    }
    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    private static func safe(_ value: String, _ allowed: [String]) -> String { allowed.contains(value) ? value : "unknown" }
    private static func toolName(_ name: String) -> String {
        safe(name, ["findRecords", "readExpenses", "readIncome", "readBudgetSummary", "readAccounts"])
    }
    func checkpoint(_ fixed: String) {
        guard active, ["preflight_start", "preflight_end", "stream_start", "stream_end", "stream_failed", "postflight_start", "postflight_end"].contains(fixed) else { return }
        marks[fixed] = .now
    }
    func warning(_ phase: String, _ status: MarinaContextStatus?) {
        guard active else { return }
        lines.append("warning_\(Self.safe(phase, ["history", "preflight", "final"]))=\(status?.rawValue ?? "none")")
    }
    func entered(tool: String, arguments: String? = nil) -> Int {
        guard active else { return 0 }
        attempts += 1
        attemptStarts[attempts] = .now
        if let arguments { self.arguments.append((attempts, arguments)) }
        lines.append("attempt=\(attempts) stage=entered tool=\(Self.toolName(tool))")
        return attempts
    }
    func mapped(attempt: Int, request: MarinaDataRequest) {
        guard active else { return }
        let previous = requests.firstIndex(of: request).map { String($0 + 1) } ?? "none"
        requests.append(request)
        let filters = [("card", request.cardID != nil), ("category", request.categoryID != nil),
                       ("budget", request.budgetID != nil), ("preset", request.presetID != nil),
                       ("account", request.accountID != nil), ("search", request.search != nil)]
            .filter(\.1).map(\.0).joined(separator: ",")
        lines.append("attempt=\(attempt) stage=mapped request_call=\(requests.count) operation=\(request.operation.rawValue) purpose=\(request.purpose?.rawValue ?? "none") measure=\(request.expenseMeasure.rawValue) grouping=\(request.grouping.rawValue) filter_types=\(filters.isEmpty ? "none" : filters) pagination_requested=\(request.offset != 0) same_request_as_call=\(previous)")
    }
    func database(attempt: Int) {
        guard active else { return }
        executions += 1
        databaseStarts[attempt] = .now
        lines.append("attempt=\(attempt) stage=database_execution")
    }
    func output(attempt: Int, text: String, status: String) {
        guard active else { return }
        outputs.append((attempt, text))
        let elapsed = attemptStarts[attempt].map { String(Self.seconds($0.duration(to: .now))) } ?? "unavailable"
        let execution = databaseStarts[attempt].map { String(Self.seconds($0.duration(to: .now))) } ?? "unavailable"
        lines.append("attempt=\(attempt) tool_elapsed_seconds=\(elapsed) execution_and_presentation_seconds=\(execution)")
        lines.append("attempt=\(attempt) stage=returned status=\(Self.safe(status, ["success", "empty", "candidates", "needsClarification", "invalidRequest", "unavailable", "failure"]))")
    }
    func failed(attempt: Int) {
        guard active else { return }
        lines.append("attempt=\(attempt) stage=failed")
    }
    func firstText() {
        guard active, marks["first_text"] == nil else { return }
        marks["first_text"] = .now
    }
    func finish(entries: [Transcript.Entry], outcome: String, reset: Bool) {
        guard active, !finished else { return }
        finished = true
        lines.append("outcome=\(Self.safe(outcome, ["complete", "cancelled", "invalidRequest", "unavailable", "contextLimit", "generationFailed", "failed", "failure"])) session_reset=\(reset)")
        lines.append("attempt_count=\(attempts) database_execution_count=\(executions) tool_execution_count=\(outputs.count)")
        lines.append("collector_to_completion_elapsed_seconds=\(Self.seconds(started.duration(to: .now)))")
        for (label, start, end) in [("context_preflight", "preflight_start", "preflight_end"), ("stream_to_first_text", "stream_start", "first_text"), ("stream_completion", "stream_start", "stream_end"), ("stream_failure", "stream_start", "stream_failed"), ("context_postflight", "postflight_start", "postflight_end")] {
            let value = marks[start].flatMap { first in marks[end].map { String(Self.seconds(first.duration(to: $0))) } } ?? "unavailable"
            lines.append("\(label)_seconds=\(value)")
        }
        Self.reports[turn] = Task { await self.report(entries: entries); Self.reports[self.turn] = nil }
    }
    private func report(entries: [Transcript.Entry]) async {
        defer { initial = []; instructions = ""; tools = []; prompt = ""; requests = []; outputs = []; arguments = [] }
        if measure, #available(iOS 26.4, macCatalyst 26.4, macOS 26.4, *) {
            let model = SystemLanguageModel.default
            func count(_ label: String, _ action: () async throws -> Int) async {
                let number = try? await action()
                lines.append("\(label)=\(number.map(String.init) ?? "unavailable")")
            }
            lines.append("measurement=Apple tokenCount capacity=\(model.contextSize)")
            await count("instructions_component") { try await model.tokenCount(for: Instructions(self.instructions)) }
            await count("all_tools_component") { try await model.tokenCount(for: self.tools) }
            for tool in tools {
                let name = Self.toolName(tool.name)
                await count("argument_schema tool=\(name) tokens") { try await model.tokenCount(for: tool.parameters) }
                await count("tool_definition tool=\(name) tokens") { try await model.tokenCount(for: [tool]) }
            }
            await count("submitted_prompt_component") { try await model.tokenCount(for: self.prompt) }
            await count("initial_transcript") { try await model.tokenCount(for: self.initial) }
            if let initialCount = try? await model.tokenCount(for: initial),
               let promptCount = try? await model.tokenCount(for: prompt) {
                lines.append("warning_preflight_accounting=\(initialCount + promptCount)")
            } else { lines.append("warning_preflight_accounting=unavailable") }
            for (attempt, argument) in arguments {
                await count("attempt=\(attempt) representation=reencoded_generated_content entered_arguments_component") { try await model.tokenCount(for: argument) }
            }
            for (attempt, output) in outputs {
                await count("attempt=\(attempt) exact_returned_output_component") { try await model.tokenCount(for: output) }
            }
            for (index, entry) in entries.enumerated() where index >= initial.count {
                if case .toolCalls(let calls) = entry {
                    for call in calls {
                        await count("entry=\(index) tool=\(Self.toolName(call.toolName)) arguments_component") { try await model.tokenCount(for: call.arguments.jsonString) }
                    }
                }
                await count("entry=\(index) entry_tokens") { try await model.tokenCount(for: [entry]) }
                await count("entry=\(index) cumulative_transcript") { try await model.tokenCount(for: Array(entries.prefix(index + 1))) }
            }
            await count("final_transcript") { try await model.tokenCount(for: entries) }
            if let finalCount = try? await model.tokenCount(for: entries) {
                lines.append("transcript_remaining=\(model.contextSize - finalCount)")
            } else { lines.append("transcript_remaining=unavailable") }
            lines.append("remaining excludes overhead not represented by transcript API; validate with Instruments")
        } else {
            lines.append("measurement=unavailable capacity=unavailable")
            for name in ["instructions_component", "all_tools_component", "submitted_prompt_component", "initial_transcript", "final_transcript", "warning_preflight_accounting", "transcript_remaining"] { lines.append("\(name)=unavailable") }
            for tool in tools {
                lines.append("argument_schema tool=\(Self.toolName(tool.name)) tokens=unavailable")
                lines.append("tool_definition tool=\(Self.toolName(tool.name)) tokens=unavailable")
            }
            for (attempt, _) in arguments { lines.append("attempt=\(attempt) representation=reencoded_generated_content entered_arguments_component=unavailable") }
            for (attempt, _) in outputs { lines.append("attempt=\(attempt) exact_returned_output_component=unavailable") }
        }
        lines.append("threshold_fraction=0.75")
        let report = (["BEGIN REPORT"] + lines + ["END REPORT"]).map { "MarinaTokens [\(turn)] \($0)" }.joined(separator: "\n")
        if let onReport { onReport(report) } else {
            for line in report.split(separator: "\n") { Self.logger.notice("\(line, privacy: .public)") }
        }
    }
}
#endif
