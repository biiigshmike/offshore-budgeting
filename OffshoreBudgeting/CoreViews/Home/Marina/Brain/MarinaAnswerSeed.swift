import Foundation

struct MarinaAnswerSeed: Equatable {
    let answer: HomeAnswer
    let insightContext: MarinaInsightContext?
    let finalExplanationSuffix: String?
}
