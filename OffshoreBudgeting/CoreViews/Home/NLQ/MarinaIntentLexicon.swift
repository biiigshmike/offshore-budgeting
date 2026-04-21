import Foundation

struct MarinaIntentLexicon {
    static let rankingTop: Set<String> = ["top", "highest", "most", "leading"]
    static let rankingLargest: Set<String> = ["largest", "biggest"]
    static let rankingBottom: Set<String> = ["bottom", "lowest"]
    static let rankingSmallest: Set<String> = ["smallest"]

    static let frequencyTerms: Set<String> = ["frequent", "often", "common"]
    static let comparisonTerms: Set<String> = ["compare", "versus", "vs", "against"]
    static let aggregateTotalTerms: Set<String> = ["spend", "spent", "spending", "total"]
    static let aggregateAmountPhrases = ["how much"]
    static let aggregateAverageTerms: Set<String> = ["average", "avg"]
    static let spendMoneyTerms: Set<String> = ["money"]
    static let movementTerms: Set<String> = ["go", "goes"]

    static let merchantTerms: Set<String> = ["merchant", "store", "vendor", "payee", "shop", "shops", "place", "places"]
    static let categoryTerms: Set<String> = ["category", "categories"]
    static let transactionTerms: Set<String> = ["expense", "expenses", "transaction", "transactions", "purchase", "purchases"]
    static let incomeTerms: Set<String> = ["income", "paycheck", "paychecks", "deposit", "deposits"]
    static let presetTerms: Set<String> = ["preset", "bill", "bills", "upcoming"]

    static let targetMarkers: Set<String> = ["at", "on", "for", "with", "to"]

    static let mostFrequentPhrases = ["most frequent", "most often"]
    static let leastFrequentPhrases = ["least frequent", "least often"]
    static let categoryRankingPhrases = ["what do i spend the most on"]
    static let indirectCategoryRankingPhrases = [
        "what do i spend the most money on",
        "where does most of my money go",
        "where does my money go"
    ]
    static let allTimePhrases = ["all time", "all-time", "lifetime", "ever"]
}
