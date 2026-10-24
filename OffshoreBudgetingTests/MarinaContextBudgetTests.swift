import Foundation
import Testing
@testable import Offshore

struct MarinaContextBudgetTests {
    @Test func reservesToolAndResponseSpaceAtBothCapacities() {
        let small = MarinaContextBudget(capacity: 4096)
        #expect(small.reserve == 1024)
        #expect(small.fits(3072))
        #expect(!small.fits(3073))
        let large = MarinaContextBudget(capacity: 8192)
        #expect(large.reserve == 2048)
        #expect(large.inputLimit == 6144)
        #expect(MarinaContextBudget(capacity: 512).inputLimit == 0)
        #expect(!small.fits(-1))
    }

    @Test func fallbackAccountsForMultibyteInput() {
        #expect(MarinaContextBudget.estimatedTokens("abcd") == 2)
        #expect(MarinaContextBudget.estimatedTokens("咖啡☕️") >= 5)
        #expect(MarinaContextBudget.estimatedTokens("") == 0)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaTranscriptWindowTests {
    @Test func neverEvictsInstructionsOrToolsWhenFrameworkSuppliesMergedTranscript() {
        let instructions = Transcript.Entry.instructions(.init(segments: [.text(.init(content: String(repeating: "rules ", count: 300)))], toolDefinitions: []))
        let old = [prompt("old"), response("answer")]
        let current = [prompt("current")]
        #expect(MarinaTranscriptWindow.bounded([instructions] + old + current,
            tokenLimit: MarinaTranscriptWindow.estimatedTokens(current)) == [instructions] + current)
    }

    @Test func keepsCurrentToolChainWholeAndMemoryPinned() throws {
        let memory = response("reference", id: MarinaTranscriptWindow.memoryID)
        let older = [prompt(String(repeating: "old ", count: 200)), response("old answer")]
        let latestPrompt = prompt("Show those purchases")
        let call = Transcript.Entry.toolCalls(Transcript.ToolCalls([
            Transcript.ToolCall(id: "call", toolName: "readExpenses", arguments: try GeneratedContent(json: "{}"))
        ]))
        let output = Transcript.Entry.toolOutput(.init(id: "call", toolName: "readExpenses", segments: [.text(.init(content: "verified facts"))]))
        let current = [latestPrompt, call, output]
        let limit = MarinaTranscriptWindow.estimatedTokens([memory] + current)
        #expect(MarinaTranscriptWindow.bounded([memory] + older + current, tokenLimit: limit) == [memory] + current)
        // An oversized active turn must throw at the model boundary, not be silently severed.
        #expect(MarinaTranscriptWindow.bounded([memory] + current, tokenLimit: 1) == [memory] + current)
    }

    @Test func preservesUnchangedHistoryAndDropsWholeOldestTurns() {
        let first = [prompt("first"), response("one")]
        let second = [prompt("second"), response("two")]
        let third = [prompt("third"), response("three")]
        let history = first + second + third
        #expect(MarinaTranscriptWindow.bounded(history, tokenLimit: 10_000) == history)
        #expect(MarinaTranscriptWindow.bounded(history, tokenLimit: MarinaTranscriptWindow.estimatedTokens(second + third)) == second + third)
    }

    private func prompt(_ text: String) -> Transcript.Entry {
        .prompt(.init(segments: [.text(.init(content: text))]))
    }
    private func response(_ text: String, id: String = UUID().uuidString) -> Transcript.Entry {
        .response(.init(id: id, assetIDs: [], segments: [.text(.init(content: text))]))
    }
}
#endif
