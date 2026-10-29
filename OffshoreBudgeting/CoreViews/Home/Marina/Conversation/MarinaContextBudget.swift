import Foundation

/// A working-context budget, independent of the saved, user-visible conversation.
nonisolated struct MarinaContextBudget: Equatable, Sendable {
    let capacity: Int
    var reserve: Int { max(1024, (max(0, capacity) + 3) / 4) }
    var inputLimit: Int { max(0, capacity - reserve) }
    func fits(_ tokens: Int) -> Bool { tokens >= 0 && tokens <= inputLimit }

    /// Deliberately conservative fallback, never reported as a native token count.
    static func estimatedTokens(_ text: String) -> Int {
        let ascii = text.utf8.reduce(0) { $0 + ($1 < 128 ? 1 : 0) }
        return (ascii + 1) / 2 + text.utf8.count - ascii
    }

    /// Calibrated separately for the app's fixed English prose and JSON schemas. The
    /// general-input estimate above is too pessimistic for this known prefix on 4K devices.
    /// Four schema bytes per token plus tool-definition/guide framing covers the measured
    /// production prefix; the native benchmark enforces that calibration. Count non-ASCII bytes conservatively.
    static func estimatedPrefixTokens(instructions: String, schemaBytes: Int) -> Int {
        let ascii = instructions.utf8.reduce(0) { $0 + ($1 < 128 ? 1 : 0) }
        return (ascii + 3) / 4 + instructions.utf8.count - ascii + (schemaBytes + 3) / 4 + 192
    }
}
