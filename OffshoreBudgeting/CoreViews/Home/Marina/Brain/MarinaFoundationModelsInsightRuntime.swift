import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaReadAnswerFactsTool: Tool {
    let context: MarinaInsightContext

    let name = "readAnswerFacts"
    let description = "Read facts from Marina's already-computed answer."

    @Generable
    struct Arguments {
        @Guide(description: "Optional focus, like summary, caution, or next step.")
        var focus: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await MarinaAnswerFactsDigest(context: context).text()
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "A short Marina coaching narration grounded only in supplied answer facts.")
struct MarinaGeneratedInsight {
    @Guide(description: "One or two warm, careful sentences. No new math, no invented records, no legal or investment advice.")
    var narration: String
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelsInsightRuntime {
    private let model: SystemLanguageModel
    private let options: GenerationOptions
    private let localeConfiguration: MarinaFoundationModelLocaleConfiguration

    init(
        model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .default),
        options: GenerationOptions = GenerationOptions(
            sampling: .greedy,
            temperature: 0.2,
            maximumResponseTokens: 160
        ),
        localeConfiguration: MarinaFoundationModelLocaleConfiguration = .current
    ) {
        self.model = model
        self.options = options
        self.localeConfiguration = localeConfiguration
    }

    func generateNarration(for context: MarinaInsightContext) async -> String? {
        guard let stream = narrationStream(for: context) else { return nil }
        var latest: String?
        do {
            for try await partial in stream {
                latest = partial
            }
            return latest
        } catch {
            return nil
        }
    }

    func narrationStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error>? {
        guard context.isNarratable else { return nil }
        guard model.isAvailable else { return nil }
        guard model.supportsLocale(localeConfiguration.locale) else { return nil }

        return AsyncThrowingStream { continuation in
            let task = Task {
                let tool = MarinaReadAnswerFactsTool(context: context)
                let session = LanguageModelSession(
                    model: model,
                    tools: [tool],
                    instructions: localeConfiguration.appending(to: instructions)
                )
                var latest: String?

                do {
                    let stream = session.streamResponse(
                        to: prompt,
                        options: options
                    )

                    for try await snapshot in stream {
                        guard Task.isCancelled == false else {
                            continuation.finish()
                            return
                        }

                        let partial = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let sanitized = MarinaVoiceSanitizer.sanitizedStreaming(partial, context: context) else { continue }
                        latest = partial
                        continuation.yield(sanitized)
                    }

                    guard MarinaVoiceSanitizer.sanitizedFinal(latest, context: context) != nil else {
                        continuation.finish(throwing: MarinaFoundationModelsInsightError.invalidNarration)
                        return
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private var instructions: String {
        """
        You are Marina, Offshore's warm and careful budgeting assistant.
        Write as Marina in first person only when referring to your own assistant actions or limitations.
        The financial data belongs to the person using the app, not to you.
        Refer to the person's money, budgets, cards, income, spending, and savings as "your", not "my".
        If the facts include a required relationship sentence, write that sentence exactly.
        Never write "you owe me", "owe me", "my balance", "my income", "my spending", or similar ownership-inverted phrasing.
        Do not prefix the response with your name.
        Use I, me, or my instead of Marina when referring to yourself.
        Before writing, call readAnswerFacts and use only those facts.
        Do not calculate, estimate, or infer new money amounts.
        Do not invent records, dates, categories, cards, accounts, or trends.
        You may mention one suggested follow-up when helpful, but only if it appears under Deterministic follow-ups.
        Do not invent follow-ups, prompts, or next steps outside the supplied follow-up list.
        Do not provide legal, tax, credit, or investment advice.
        Do not mention tools, schemas, prompts, or internal implementation.
        Write one or two concise sentences that help the person understand the answer they are seeing.
        If the facts are thin, simply name what the current answer shows.
        """
    }

    private var prompt: String {
        "Call readAnswerFacts, then write only a short coaching narration for the user's already-computed budgeting answer."
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private enum MarinaFoundationModelsInsightError: Error {
    case invalidNarration
}
#endif
