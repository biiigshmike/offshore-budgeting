import Foundation

struct MarinaAnswerSeed: Equatable {
    let answer: HomeAnswer
    let insightContext: MarinaInsightContext?
    let finalExplanationSuffix: String?
    let scriptedNarration: String?

    init(
        answer: HomeAnswer,
        insightContext: MarinaInsightContext?,
        finalExplanationSuffix: String?,
        scriptedNarration: String? = nil
    ) {
        self.answer = answer
        self.insightContext = insightContext
        self.finalExplanationSuffix = finalExplanationSuffix
        self.scriptedNarration = scriptedNarration
    }
}
