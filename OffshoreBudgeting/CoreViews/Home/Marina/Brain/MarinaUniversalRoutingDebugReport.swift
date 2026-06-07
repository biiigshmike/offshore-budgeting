#if DEBUG
import Foundation

struct MarinaUniversalRoutingDebugFormatter {
    func summary(from diagnostics: MarinaUniversalRoutingDiagnostics) -> String {
        var lines = [
            "Universal: \(diagnostics.usedUniversal ? "used" : "fallback")",
            "Scenario: \(diagnostics.scenario?.rawValue ?? "none")",
            "Entity: \(diagnostics.requestEntity.rawValue)",
            "Operation: \(diagnostics.operation.rawValue)",
            "Measure: \(diagnostics.measure?.rawValue ?? "none")",
            "Fallback: \(diagnostics.fallbackReason?.rawValue ?? "none")"
        ]

        if diagnostics.notes.isEmpty == false {
            lines.append("Notes:")
            lines.append(contentsOf: diagnostics.notes.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}
#endif
