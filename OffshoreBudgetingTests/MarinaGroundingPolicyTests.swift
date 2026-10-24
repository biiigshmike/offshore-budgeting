import Testing
@testable import Offshore

struct MarinaGroundingPolicyTests {
    @Test func onlyWorkspaceIdentityQuestionsDisableTools() {
        #expect(MarinaGroundingPolicy.isWorkspaceMetadataQuestion("Which workspace am I using?"))
        #expect(MarinaGroundingPolicy.isWorkspaceMetadataQuestion("What workspace am I in?"))
        #expect(!MarinaGroundingPolicy.isWorkspaceMetadataQuestion("Which workspace has my Apple Card?"))
        #expect(!MarinaGroundingPolicy.isWorkspaceMetadataQuestion("How much did I spend across the workspace?"))
        #expect(!MarinaGroundingPolicy.isWorkspaceMetadataQuestion("Show my cards in this workspace."))
    }

    @Test func personalFinancialQuestionsAlwaysNeedFreshEvidence() {
        for prompt in ["How much did I spend on Apple Card this month?", "Which purchase was biggest last month?", "Which purchase was the biggest?",
                       "Show the purchases behind that total.", "My actual income this month", "How much income was planned?",
                       "What is my current balance?", "Am I on track with my Monthly budget?", "List all reconciliation balances.",
                       "Compare my savings with last month.", "¿Cuánto gasté este mes?", "Muestra mis transacciones.",
                       "¿Cuál es el saldo de mi cuenta?", "Compara los ingresos de septiembre.", "Mis ahorros"] {
            #expect(MarinaGroundingPolicy.requiresRead(prompt: prompt, hasFinancialContext: false, hasPendingClarification: false), Comment(rawValue: prompt))
        }
    }

    @Test func contextualFollowUpsNeedFreshReadsWithoutReusingOldAmounts() {
        for prompt in ["What about last month?", "And this month?", "How much of that was on Debit Card?", "Show that card again.", "Show the purchases.",
                       "What was biggest in that month?", "Y el mes pasado?", "Muestra esa cuenta."] {
            #expect(MarinaGroundingPolicy.requiresRead(prompt: prompt, hasFinancialContext: true, hasPendingClarification: false), Comment(rawValue: prompt))
        }
        #expect(!MarinaGroundingPolicy.requiresRead(prompt: "What about last month?", hasFinancialContext: false, hasPendingClarification: false))
        #expect(MarinaGroundingPolicy.requiresRead(prompt: "I mean the merchant, not Apple Card.", hasFinancialContext: false, hasPendingClarification: true))
    }

    @Test func upcomingPresetOccurrencesRequireFreshReadsEvenWithoutFinancialHistory() {
        for prompt in ["Oh, and what about my presets? Do I have any due soon?",
                       "Show my upcoming presets.", "¿Qué plantillas vencen pronto?"] {
            #expect(MarinaGroundingPolicy.requiresRead(prompt: prompt, hasFinancialContext: false, hasPendingClarification: false))
        }
        #expect(!MarinaGroundingPolicy.requiresRead(prompt: "Show my presets", hasFinancialContext: false, hasPendingClarification: false))
        #expect(!MarinaGroundingPolicy.requiresRead(prompt: "What is an upcoming preset?", hasFinancialContext: false, hasPendingClarification: false))
    }

    @Test func greetingsDefinitionsAndAppMetadataRemainUngated() {
        for context in [false, true] {
            for prompt in ["Hi Marina", "Thanks!", "What is a budget?", "Explain planned versus actual income.",
                           "How does reconciliation work?", "What is savings?", "¿Qué es un presupuesto?",
                           "Explica cómo funciona el ahorro.", "Which workspace am I in?", "What date range is selected?",
                           "What currency do you use?", "How many workspaces are there?", "How do I create a budget?", "Add a $10 expense for yesterday.",
                           "", "Show my cards", "List my budgets", "Show savings accounts", "Lista mis categorias"] {
                #expect(!MarinaGroundingPolicy.requiresRead(prompt: prompt, hasFinancialContext: context, hasPendingClarification: false), Comment(rawValue: prompt))
            }
        }
    }
}
