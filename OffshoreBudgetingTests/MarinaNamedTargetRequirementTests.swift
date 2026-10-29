import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaNamedTargetRequirementTests {
    private typealias Entity = MarinaConversationMemory.Entity
    private let card = Entity(kind: "card", id: "card-blue", name: "BlueCard")
    private let appleCard = Entity(kind: "card", id: "card-apple", name: "Apple Card")
    private let appleMerchant = Entity(kind: "merchant", id: "Apple", name: "Apple")
    private let hair = Entity(kind: "category", id: "category-hair", name: "Hair Care")
    private let tea = Entity(kind: "category", id: "category-tea", name: "Café 🍵")

    private var catalog: [Entity] { [card, appleCard, appleMerchant, hair, tea] }

    @Test func explicitCategoryCannotDisappearIntoOldCardOrRanking() throws {
        for (prompt, category) in [
            ("What did I spend in the Hair Care category this month?", hair),
            ("¿Cuánto gasté este mes en la categoría Café 🍵?", tea)
        ] {
            let requirement = try #require(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog).first)
            #expect(requirement.recordKind == "category" && requirement.candidates == [category])
            #expect(!requirement.isAmbiguous)
            let oldCardRanking = MarinaDataRequest(operation: .ranking, tool: .expenses, cardID: card.id, grouping: .category)
            #expect(!requirement.includes(in: oldCardRanking))
            let selected = MarinaDataRequest(tool: .expenses, categoryID: category.id)
            #expect(requirement.includes(in: selected))
        }
    }

    @Test func unqualifiedAppleIncludesSamePartialCandidatesAsLookup() throws {
        let requirements = MarinaNamedTargetRequirement.requirements(prompt: "How much did I spend at Apple this month?", catalog: catalog)
        let requirement = try #require(requirements.first)
        #expect(requirements.count == 1 && requirement.search == "Apple")
        #expect(requirement.recordKind == nil && requirement.isAmbiguous)
        #expect(Set(requirement.candidates.map(\.id)) == [appleCard.id, appleMerchant.id])
        #expect(!requirement.includes(in: .init(tool: .expenses, cardID: card.id)))
        #expect(requirement.includes(in: .init(merchantName: "Apple", tool: .expenses)))
    }

    @Test func explicitFullNameWinsOverItsContainedMerchantName() throws {
        let requirements = MarinaNamedTargetRequirement.requirements(prompt: "Show all transactions on Apple Card this month.", catalog: catalog)
        let requirement = try #require(requirements.first)
        #expect(requirements.count == 1 && requirement.search == "Apple Card")
        #expect(requirement.recordKind == "card" && requirement.candidates == [appleCard])
        #expect(!requirement.includes(in: .init(merchantName: "Apple", tool: .expenses)))
        #expect(requirement.includes(in: .init(tool: .expenses, cardID: appleCard.id)))
    }

    @Test func explicitKindDisambiguatesIdenticalNamesWithoutGuessingFromOldSelections() throws {
        let sameNameCard = Entity(kind: "card", id: "card-alex", name: "Alex")
        let account = Entity(kind: "reconciliationAccount", id: "account-alex", name: "Alex")
        let merchant = Entity(kind: "merchant", id: "merchant-alex", name: "Alex")
        let localCatalog = [sameNameCard, account, merchant]
        let unknownKind = try #require(MarinaNamedTargetRequirement.requirements(prompt: "Show Alex this month", catalog: localCatalog).first)
        #expect(unknownKind.isAmbiguous && unknownKind.recordKind == nil)
        let selected = try #require(MarinaNamedTargetRequirement.requirements(prompt: "Show the Alex reconciliation account", catalog: localCatalog).first)
        #expect(selected.candidates == [account] && selected.recordKind == "reconciliationAccount")
        #expect(!selected.includes(in: .init(tool: .expenses, cardID: sameNameCard.id)))
        #expect(selected.includes(in: .init(tool: .accounts, accountID: account.id, scope: .reconciliation)))
    }

    @Test func namesKeepEmojiAndWordBoundariesWithCaseAndAccentInsensitiveMatching() throws {
        let otherTea = Entity(kind: "category", id: "category-coffee", name: "Café ☕")
        let requirements = MarinaNamedTargetRequirement.requirements(prompt: "Show the CAFE 🍵 category", catalog: catalog + [otherTea])
        #expect(requirements.count == 1 && requirements.first?.candidates == [tea])
        #expect(MarinaNamedTargetRequirement.requirements(prompt: "How much did I spend at Pineapple?", catalog: catalog).isEmpty)
        #expect(MarinaNamedTargetRequirement.requirements(prompt: "Show the Hair Careful category", catalog: catalog).isEmpty)
    }

    @Test func genericRankingsAndDomainWordsDoNotInventNamedFilters() {
        let generic = [Entity(kind: "incomeSource", id: "Income", name: "Income"),
                       Entity(kind: "budget", id: "budget-october", name: "October"),
                       Entity(kind: "savingsAccount", id: "default-savings", name: "Savings Account")]
        for prompt in ["What are my top spending categories this month?", "How much income did I receive this month?",
                       "Show my spending in October", "Show all savings accounts"] {
            #expect(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog + generic).isEmpty)
        }
        let namedBudget = MarinaNamedTargetRequirement.requirements(prompt: "Show the October budget", catalog: generic)
        #expect(namedBudget.first?.recordKind == "budget")
    }

    @Test func negatedNamesAreNotRequiredAndContrastRestoresAffirmativeSelection() {
        for prompt in ["Show all categories except Hair Care", "Show spending not on Apple Card", "Gastos sin Café 🍵",
                       "Do not show the Hair Care category"] {
            #expect(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog).isEmpty)
        }
        let contrasted = MarinaNamedTargetRequirement.requirements(prompt: "Not Apple Card, show the Hair Care category", catalog: catalog)
        #expect(contrasted.count == 1 && contrasted.first?.candidates == [hair])
        let otherContrast = MarinaNamedTargetRequirement.requirements(prompt: "Not Apple Card but the Hair Care category", catalog: catalog)
        #expect(otherContrast.count == 1 && otherContrast.first?.candidates == [hair])
    }

    @Test func comparisonsCanSatisfyEachMentionedTargetOnEitherSide() throws {
        let requirements = MarinaNamedTargetRequirement.requirements(prompt: "Compare BlueCard and Apple Card spending", catalog: catalog)
        #expect(requirements.count == 2)
        var request = MarinaDataRequest(operation: .comparison, tool: .expenses, cardID: card.id)
        #expect(requirements.contains { !$0.includes(in: request) })
        request.comparisonFilter = .init(cardID: appleCard.id)
        #expect(requirements.allSatisfy { $0.includes(in: request) })
    }

    @Test func duplicateSameKindNamesRemainAmbiguous() throws {
        let duplicate = Entity(kind: "category", id: "other-hair", name: "Hair Care")
        let requirement = try #require(MarinaNamedTargetRequirement.requirements(prompt: "Show the Hair Care category", catalog: catalog + [duplicate]).first)
        #expect(requirement.recordKind == "category" && requirement.isAmbiguous)
        #expect(requirement.candidates.count == 2)
    }

    @Test func absentAndForeignLiteralCardNamesStillRequireLookup() throws {
        for name in ["Missing Fixture Card", "Foreign Card", "Café 🍵 Card"] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: "How much did I spend on \(name) this month?", catalog: catalog)
            let requirement = try #require(requirements.first)
            #expect(requirements.count == 1 && requirement.search == name && requirement.recordKind == "card")
            #expect(requirement.candidates.isEmpty && !requirement.isAmbiguous)
            #expect(!requirement.includes(in: .init(tool: .expenses)))
            #expect(!requirement.includes(in: .init(tool: .expenses, cardID: card.id)))
        }
    }

    @Test func quotedAndExplicitlyNamedUnknownTargetsPreserveLiteralText() throws {
        for (prompt, name, kind) in [
            ("Show the category \"Absent Café 🍵\" this month", "Absent Café 🍵", "category"),
            ("Show the savings account ‘Trip 🏖️’", "Trip 🏖️", "savingsAccount"),
            ("How much did I spend on the card named Missing Fixture Card this month?", "Missing Fixture Card", "card"),
            ("Show the category called Hair Styling this month", "Hair Styling", "category"),
            ("Show the category \"Income\"", "Income", "category")
        ] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog)
            let requirement = try #require(requirements.first)
            #expect(requirements.count == 1 && requirement.search == name && requirement.recordKind == kind)
            #expect(requirement.candidates.isEmpty)
        }
    }

    @Test func unknownLiteralPatternsDoNotCaptureGenericScopesDatesOrNegation() {
        for prompt in ["How much did I spend on my card this month?", "Show all cards this month", "Show spending in October",
                       "Show spending not on Foreign Card", "Do not use the card named Missing Fixture Card",
                       "I said 'this month'", "Show spending on the previous month card"] {
            #expect(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog).isEmpty)
        }
    }

    @Test func nearbyCardWordCannotChooseTheKindOfAnUnqualifiedAppleName() throws {
        let requirement = try #require(MarinaNamedTargetRequirement.requirements(
            prompt: "How much did I spend on my card at Apple this month?", catalog: catalog).first)
        #expect(requirement.search == "Apple" && requirement.recordKind == nil && requirement.isAmbiguous)
        #expect(Set(requirement.candidates.map(\.id)) == [appleCard.id, appleMerchant.id])
    }

    @Test func sharedCatalogPrefixesRemainRequiredBesideACompleteCardName() {
        let merchants = ["Parcel - Market", "Parcel - Corner!", "Parcel - Corner! Delivery"].map {
            Entity(kind: "merchant", id: $0, name: $0)
        }
        let records = catalog + merchants
        let partial = MarinaNamedTargetRequirement.requirements(prompt: "Show Parcel expenses on BlueCard this month", catalog: records)
        #expect(partial.contains { $0.search == "Parcel" && $0.candidates.count == 3 && $0.isAmbiguous })
        #expect(partial.contains { $0.search == "BlueCard" })
        let complete = MarinaNamedTargetRequirement.requirements(prompt: "Show Parcel - Corner! expenses on BlueCard", catalog: records)
        #expect(!complete.contains { $0.search == "Parcel" })
        #expect(complete.contains { $0.search == "Parcel - Corner!" })
        let negated = MarinaNamedTargetRequirement.requirements(prompt: "Show BlueCard expenses, not Parcel", catalog: records)
        #expect(!negated.contains { $0.search == "Parcel" })
        let generic = ["The Card Store", "The Card Shop"].map { Entity(kind: "merchant", id: $0, name: $0) }
        #expect(MarinaNamedTargetRequirement.requirements(prompt: "Show the card this month", catalog: generic).isEmpty)
    }

    @Test func separateCardAndMerchantRetainTheirOwnKindsAndFilters() {
        for prompt in ["Show spending on BlueCard at the Apple merchant this month",
                       "Show spending on the card named BlueCard at the merchant Apple this month"] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog)
            #expect(requirements.count == 2)
            let merchant = requirements.first { $0.search == "Apple" }
            #expect(merchant?.recordKind == "merchant" && merchant?.candidates == [appleMerchant])
            let scoped = MarinaDataRequest(merchantName: "Apple", tool: .expenses, cardID: card.id)
            #expect(requirements.allSatisfy { $0.includes(in: scoped) })
            let wrongCard = MarinaDataRequest(merchantName: "Apple", tool: .expenses, cardID: appleCard.id)
            #expect(!requirements.allSatisfy { $0.includes(in: wrongCard) })
        }
    }

    @Test func unquotedNamedCardEndsBeforeTheNextCategoryFilter() {
        for prompt in ["Show spending on the card named BlueCard and the Hair Care category this month",
                       "Show spending on the card called BlueCard with the Hair Care category this month"] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog)
            #expect(requirements.count == 2)
            #expect(Set(requirements.map(\.search)) == ["BlueCard", "Hair Care"])
            #expect(requirements.first { $0.search == "BlueCard" }?.recordKind == "card")
            #expect(requirements.first { $0.search == "Hair Care" }?.recordKind == "category")
            let scoped = MarinaDataRequest(tool: .expenses, cardID: card.id, categoryID: hair.id)
            #expect(requirements.allSatisfy { $0.includes(in: scoped) })
        }
        let unknown = MarinaNamedTargetRequirement.requirements(
            prompt: "Show the card named Missing Card and the Hair Care category this month", catalog: catalog)
        #expect(unknown.count == 2)
        #expect(unknown.first { $0.search == "Missing Card" }?.candidates.isEmpty == true)
        #expect(unknown.first { $0.search == "Hair Care" }?.candidates == [hair])
    }

    @Test func quotedNamesAndCompleteKnownNamesKeepInternalConjunctions() {
        let quoted = MarinaNamedTargetRequirement.requirements(
            prompt: "Show the card named \"Salt and Pepper Card\" and the Hair Care category this month", catalog: catalog)
        #expect(quoted.count == 2)
        #expect(quoted.first { $0.search == "Salt and Pepper Card" }?.recordKind == "card")
        #expect(quoted.first { $0.search == "Salt and Pepper Card" }?.candidates.isEmpty == true)
        #expect(quoted.first { $0.search == "Hair Care" }?.candidates == [hair])

        let merchant = Entity(kind: "merchant", id: "Salt and Pepper", name: "Salt and Pepper")
        let known = MarinaNamedTargetRequirement.requirements(
            prompt: "Show the merchant named Salt and Pepper with the Hair Care category this month", catalog: catalog + [merchant])
        #expect(known.count == 2)
        #expect(known.first { $0.search == merchant.name }?.candidates == [merchant])
        #expect(!known.contains { $0.search == "Salt" })
    }

    @Test func attachedKindsKeepSameNamedCardMerchantAndAccountSeparate() throws {
        let card = Entity(kind: "card", id: "alex-card", name: "Alex")
        let merchant = Entity(kind: "merchant", id: "alex-merchant", name: "Alex")
        let account = Entity(kind: "reconciliationAccount", id: "alex-account", name: "Alex")
        let catalog = [card, merchant, account]
        for (prompt, target) in [("Show the card named Alex", card), ("Show the merchant called Alex", merchant),
                                 ("Show the reconciliation account named Alex", account), ("Show the Alex reconciliation account", account)] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog)
            let requirement = try #require(requirements.first)
            #expect(requirements.count == 1 && requirement.recordKind == target.kind && requirement.candidates == [target])
        }
        let unqualified = try #require(MarinaNamedTargetRequirement.requirements(
            prompt: "Show spending on my card at Alex", catalog: catalog).first)
        #expect(unqualified.recordKind == nil && unqualified.candidates.count == 3)
    }

    @Test func genericCardArticlesNeverBecomeExtraNamedRequirements() throws {
        for name in ["BlueCard", "r1", "upcomingPresets", "readExpenses"] {
            let record = Entity(kind: "card", id: "card-\(name)", name: name)
            for phrasing in ["on the card named", "with the card called"] {
                let requirements = MarinaNamedTargetRequirement.requirements(
                    prompt: "How much did I spend \(phrasing) \(name) this month?", catalog: [record])
                let requirement = try #require(requirements.first)
                #expect(requirements.count == 1 && requirement.search == name)
                #expect(requirement.recordKind == "card" && requirement.candidates == [record])
                #expect(requirement.includes(in: .init(tool: .expenses, cardID: record.id)))
            }
        }
        for prompt in ["Show spending on the card", "Show spending with The Card", "Show spending on my card"] {
            #expect(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: catalog).isEmpty)
        }
    }

    @Test func literalNameProvenancePreservesActualNamesAndOnlyNormalizesCaseAccentsAndWhitespace() {
        for (name, prompt) in [
            ("r1", "Show spending on the card named r1"),
            ("AppleCard", "Show APPLECARD spending"),
            ("Café 🍵", "Show the CAFE  🍵 category"),
            ("Rainy Day", "Show Rainy\n  Day savings"),
            ("Mom's Café", "What did I spend at Mom's Café?"),
            ("O’Reilly", "Show spending at O’Reilly"),
            ("No Frills", "What did I spend at No Frills?"),
            ("Marina", "Show the merchant named Marina")
        ] {
            #expect(MarinaNamedTargetRequirement.containsLiteralName(name, in: prompt))
        }
    }

    @Test func literalNameProvenanceRejectsInventedNamesSubstringsAndChangedEmojiOrPunctuation() {
        for (name, prompt) in [
            ("Marina", "How much have I spent this month?"),
            ("r1", "Show r10 spending"),
            ("Apple", "Show Pineapple spending"),
            ("Apple", "Show AppleCard spending"),
            ("AppleCard", "Show Apple Card spending"),
            ("Café 🍵", "Show Café ☕ spending"),
            ("Mom's Café", "Show Moms Cafe spending"),
            ("Coffee", "Show Café spending"),
            ("", "Show spending"),
            (" \n ", "Show spending"),
            ("Apple", "")
        ] {
            #expect(!MarinaNamedTargetRequirement.containsLiteralName(name, in: prompt))
        }
    }

    @Test func literalNameProvenanceRequiresAnAffirmativeOccurrence() {
        for prompt in ["Not Apple", "Show spending except Apple", "Show spending without Apple",
                       "Gastos sin Apple", "No Apple", "Do not look up Apple", "Show spending excluding Apple"] {
            #expect(!MarinaNamedTargetRequirement.containsLiteralName("Apple", in: prompt))
        }
        for prompt in ["Not BlueCard but Apple", "Not BlueCard; show Apple", "Sin BlueCard, muestra Apple",
                       "No BlueCard sino Apple", "Use Apple, not BlueCard", "Not Apple; actually show Apple"] {
            #expect(MarinaNamedTargetRequirement.containsLiteralName("Apple", in: prompt))
        }
        #expect(!MarinaNamedTargetRequirement.containsLiteralName("BlueCard", in: "Use Apple, not BlueCard"))
    }

    @Test func singleAccountDomainBalanceAndActivityPhrasesResolveTheirOwnAlex() throws {
        let savings = Entity(kind: "savingsAccount", id: "alex-savings", name: "Alex")
        let reconciliation = Entity(kind: "reconciliationAccount", id: "alex-reconciliation", name: "Alex")
        let merchant = Entity(kind: "merchant", id: "alex-merchant", name: "Alex")
        let localCatalog = [savings, reconciliation, merchant]
        for (prompt, expected) in [
            ("What is my current reconciliation balance with Alex?", reconciliation),
            ("Show reconciliation account activity for Alex this month", reconciliation),
            ("Show reconciliation current balance with my Alex", reconciliation),
            ("What is the savings balance in Alex?", savings),
            ("Show savings balance for Alex", savings),
            ("Show savings account entries in Alex this month", savings)
        ] {
            let requirements = MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: localCatalog)
            let requirement = try #require(requirements.first)
            #expect(requirements.count == 1 && requirement.recordKind == expected.kind)
            #expect(!requirement.isAmbiguous && requirement.candidates == [expected])
            #expect(requirement.includes(in: .init(tool: .accounts, accountID: expected.id)))
            let other = expected.id == savings.id ? reconciliation : savings
            #expect(!requirement.includes(in: .init(tool: .accounts, accountID: other.id)))
        }
    }

    @Test func accountDomainPhraseDoesNotResolveMixedDomainsMultipleTargetsOrNegatedNames() throws {
        let alexSavings = Entity(kind: "savingsAccount", id: "alex-savings", name: "Alex")
        let alexReconciliation = Entity(kind: "reconciliationAccount", id: "alex-reconciliation", name: "Alex")
        let patSavings = Entity(kind: "savingsAccount", id: "pat-savings", name: "Pat")
        let patReconciliation = Entity(kind: "reconciliationAccount", id: "pat-reconciliation", name: "Pat")
        let localCatalog = [alexSavings, alexReconciliation, patSavings, patReconciliation]
        for prompt in ["Compare savings and reconciliation balance with Alex", "Show reconciliation balance with Alex and Pat",
                       "Show reconciliation balance with Alex versus savings", "Show reconciliation balance with Alex; show Pat"] {
            let requirement = try #require(MarinaNamedTargetRequirement.requirements(prompt: prompt, catalog: localCatalog).first { $0.search == "Alex" })
            #expect(requirement.recordKind == nil && requirement.isAmbiguous)
        }
        #expect(MarinaNamedTargetRequirement.requirements(prompt: "Do not show reconciliation balance with Alex", catalog: localCatalog).isEmpty)
        let apple = try #require(MarinaNamedTargetRequirement.requirements(
            prompt: "How much did I spend on my card at Apple this month?", catalog: catalog).first)
        #expect(apple.recordKind == nil && apple.isAmbiguous)
    }
}
