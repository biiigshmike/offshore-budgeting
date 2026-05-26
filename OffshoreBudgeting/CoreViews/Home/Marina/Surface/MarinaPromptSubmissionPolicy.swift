import Foundation

enum MarinaPromptSubmissionPolicy {
    static func shouldHandleFreeText(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return false
    }
}
