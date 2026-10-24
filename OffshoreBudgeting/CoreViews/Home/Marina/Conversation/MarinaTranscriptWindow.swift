import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Keeps complete turns together: never orphan a tool result or remove a current-turn call.
@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaTranscriptWindow {
    static let memoryID = "marina-context-memory"

    static func estimatedTokens(_ entries: [Transcript.Entry]) -> Int {
        entries.reduce(0) { total, entry in
            let text: String
            switch entry {
            case .instructions(let value):
                text = segments(value.segments)
            case .prompt(let value): text = segments(value.segments)
            case .response(let value): text = segments(value.segments)
            case .toolOutput(let value): text = segments(value.segments)
            case .toolCalls(let calls): text = calls.map { $0.toolName + $0.arguments.jsonString }.joined()
            default:
                if #available(iOS 27.0, macCatalyst 27.0, *), case .reasoning(let value) = entry {
                    text = segments(value.segments)
                } else { text = "" }
            }
            return total + 16 + MarinaContextBudget.estimatedTokens(text)
        }
    }

    static func bounded(_ history: [Transcript.Entry], tokenLimit: Int) -> [Transcript.Entry] {
        // Some framework paths provide the merged transcript to a transform. Instructions
        // contain the tool definitions and are budgeted separately; they must never be evicted.
        let instructions = history.filter { if case .instructions = $0 { true } else { false } }
        let entries = history.filter { if case .instructions = $0 { false } else { true } }
        guard estimatedTokens(entries) > tokenLimit else { return history }
        let memory = entries.filter { $0.id == memoryID }
        let remainder = entries.filter { $0.id != memoryID }
        var turns: [[Transcript.Entry]] = []
        for entry in remainder {
            if case .prompt = entry { turns.append([]) }
            if turns.isEmpty { turns.append([]) }
            turns[turns.count - 1].append(entry)
        }
        // The newest turn may still be running. Its complete tool chain is indivisible,
        // even if it alone overflows; the runtime handles overflow with one fresh retry.
        guard let current = turns.popLast() else { return instructions + memory }
        var kept = current
        var remaining = tokenLimit - estimatedTokens(memory + current)
        for turn in turns.reversed() {
            let cost = estimatedTokens(turn)
            guard cost <= remaining else { break }
            kept.insert(contentsOf: turn, at: 0)
            remaining -= cost
        }
        return instructions + memory + kept
    }

    private static func segments(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let value): value.content
            case .structure(let value): value.content.jsonString
            default: ""
            }
        }.joined(separator: "\n")
    }
}
#endif
