import Foundation

enum WorkspaceTransferSection: String, Codable, CaseIterable, Identifiable, Hashable {
    case categories
    case cards
    case budgets
    case presets
    case expenseHistory
    case incomes
    case reconciliations
    case savings
    case importRules
    case marinaAliases

    var id: String { rawValue }

    static var userVisibleCases: [WorkspaceTransferSection] {
        allCases.filter { $0 != .marinaAliases }
    }

    var displayTitle: String {
        switch self {
        case .categories: "Categories"
        case .cards: "Cards"
        case .budgets: "Budgets"
        case .presets: "Presets"
        case .expenseHistory: "Expense History"
        case .incomes: "Income"
        case .reconciliations: "Reconciliations"
        case .savings: "Savings"
        case .importRules: "Expense Import Rules"
        case .marinaAliases: "Marina Aliases"
        }
    }

    var systemImage: String {
        switch self {
        case .categories: "tag.fill"
        case .cards: "creditcard"
        case .budgets: "chart.pie.fill"
        case .presets: "list.bullet.rectangle"
        case .expenseHistory: "receipt"
        case .incomes: "calendar"
        case .reconciliations: "person.2.fill"
        case .savings: "banknote.fill"
        case .importRules: "square.and.arrow.down"
        case .marinaAliases: "bubble.left.and.text.bubble.right"
        }
    }
}

struct WorkspaceArchive: Codable, Equatable {
    static let markerValue = "offshore.workspace.export"
    static let supportedSchemaVersion = 1

    var marker: String
    var schemaVersion: Int
    var exportedAt: Date
    var sourceWorkspaceID: UUID
    var selectedSections: [WorkspaceTransferSection]
    var workspace: WorkspacePayload

    var budgets: [BudgetPayload]
    var budgetCardLinks: [BudgetCardLinkPayload]
    var budgetPresetLinks: [BudgetPresetLinkPayload]
    var budgetCategoryLimits: [BudgetCategoryLimitPayload]
    var cards: [CardPayload]
    var categories: [CategoryPayload]
    var presets: [PresetPayload]
    var plannedExpenses: [PlannedExpensePayload]
    var variableExpenses: [VariableExpensePayload]
    var allocationAccounts: [AllocationAccountPayload]
    var expenseAllocations: [ExpenseAllocationPayload]
    var allocationSettlements: [AllocationSettlementPayload]
    var savingsAccounts: [SavingsAccountPayload]
    var savingsLedgerEntries: [SavingsLedgerEntryPayload]
    var importMerchantRules: [ImportMerchantRulePayload]
    var assistantAliasRules: [AssistantAliasRulePayload]
    var incomeSeries: [IncomeSeriesPayload]
    var incomes: [IncomePayload]

    init(
        marker: String = WorkspaceArchive.markerValue,
        schemaVersion: Int = WorkspaceArchive.supportedSchemaVersion,
        exportedAt: Date,
        sourceWorkspaceID: UUID,
        selectedSections: [WorkspaceTransferSection],
        workspace: WorkspacePayload,
        budgets: [BudgetPayload] = [],
        budgetCardLinks: [BudgetCardLinkPayload] = [],
        budgetPresetLinks: [BudgetPresetLinkPayload] = [],
        budgetCategoryLimits: [BudgetCategoryLimitPayload] = [],
        cards: [CardPayload] = [],
        categories: [CategoryPayload] = [],
        presets: [PresetPayload] = [],
        plannedExpenses: [PlannedExpensePayload] = [],
        variableExpenses: [VariableExpensePayload] = [],
        allocationAccounts: [AllocationAccountPayload] = [],
        expenseAllocations: [ExpenseAllocationPayload] = [],
        allocationSettlements: [AllocationSettlementPayload] = [],
        savingsAccounts: [SavingsAccountPayload] = [],
        savingsLedgerEntries: [SavingsLedgerEntryPayload] = [],
        importMerchantRules: [ImportMerchantRulePayload] = [],
        assistantAliasRules: [AssistantAliasRulePayload] = [],
        incomeSeries: [IncomeSeriesPayload] = [],
        incomes: [IncomePayload] = []
    ) {
        self.marker = marker
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.sourceWorkspaceID = sourceWorkspaceID
        self.selectedSections = selectedSections
        self.workspace = workspace
        self.budgets = budgets
        self.budgetCardLinks = budgetCardLinks
        self.budgetPresetLinks = budgetPresetLinks
        self.budgetCategoryLimits = budgetCategoryLimits
        self.cards = cards
        self.categories = categories
        self.presets = presets
        self.plannedExpenses = plannedExpenses
        self.variableExpenses = variableExpenses
        self.allocationAccounts = allocationAccounts
        self.expenseAllocations = expenseAllocations
        self.allocationSettlements = allocationSettlements
        self.savingsAccounts = savingsAccounts
        self.savingsLedgerEntries = savingsLedgerEntries
        self.importMerchantRules = importMerchantRules
        self.assistantAliasRules = assistantAliasRules
        self.incomeSeries = incomeSeries
        self.incomes = incomes
    }
}

struct WorkspacePayload: Codable, Equatable {
    var id: UUID
    var name: String
    var hexColor: String
}

struct BudgetPayload: Codable, Equatable {
    var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
}

struct BudgetCardLinkPayload: Codable, Equatable {
    var id: UUID
    var budgetID: UUID?
    var cardID: UUID?
}

struct BudgetPresetLinkPayload: Codable, Equatable {
    var id: UUID
    var budgetID: UUID?
    var presetID: UUID?
}

struct BudgetCategoryLimitPayload: Codable, Equatable {
    var id: UUID
    var minAmount: Double?
    var maxAmount: Double?
    var budgetID: UUID?
    var categoryID: UUID?
}

struct CardPayload: Codable, Equatable {
    var id: UUID
    var name: String
    var theme: String
    var effect: String
}

struct CategoryPayload: Codable, Equatable {
    var id: UUID
    var name: String
    var hexColor: String
    var isArchived: Bool
    var archivedAt: Date?
}

struct PresetPayload: Codable, Equatable {
    var id: UUID
    var title: String
    var plannedAmount: Double
    var isArchived: Bool
    var archivedAt: Date?
    var frequencyRaw: String
    var interval: Int
    var weeklyWeekday: Int
    var monthlyDayOfMonth: Int
    var monthlyIsLastDay: Bool
    var yearlyMonth: Int
    var yearlyDayOfMonth: Int
    var defaultCardID: UUID?
    var defaultCategoryID: UUID?
}

struct PlannedExpensePayload: Codable, Equatable {
    var id: UUID
    var title: String
    var plannedAmount: Double
    var actualAmount: Double
    var expenseDate: Date
    var cardID: UUID?
    var categoryID: UUID?
    var sourcePresetID: UUID?
    var sourceBudgetID: UUID?
}

struct VariableExpensePayload: Codable, Equatable {
    var id: UUID
    var descriptionText: String
    var amount: Double
    var kindRaw: String
    var transactionDate: Date
    var cardID: UUID?
    var categoryID: UUID?
}

struct AllocationAccountPayload: Codable, Equatable {
    var id: UUID
    var name: String
    var hexColor: String
    var isArchived: Bool
    var archivedAt: Date?
}

struct ExpenseAllocationPayload: Codable, Equatable {
    var id: UUID
    var allocatedAmount: Double
    var preservesGrossAmount: Bool
    var createdAt: Date
    var updatedAt: Date
    var accountID: UUID?
    var expenseID: UUID?
    var plannedExpenseID: UUID?
}

struct AllocationSettlementPayload: Codable, Equatable {
    var id: UUID
    var date: Date
    var note: String
    var amount: Double
    var accountID: UUID?
    var expenseID: UUID?
    var plannedExpenseID: UUID?
}

struct SavingsAccountPayload: Codable, Equatable {
    var id: UUID
    var name: String
    var total: Double
    var didBackfillHistory: Bool
    var autoCaptureThroughDate: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct SavingsLedgerEntryPayload: Codable, Equatable {
    var id: UUID
    var date: Date
    var amount: Double
    var note: String
    var kindRaw: String
    var linkedAllocationSettlementID: UUID?
    var periodStartDate: Date?
    var periodEndDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var accountID: UUID?
    var variableExpenseID: UUID?
    var plannedExpenseID: UUID?
}

struct ImportMerchantRulePayload: Codable, Equatable {
    var id: UUID
    var merchantKey: String
    var preferredName: String?
    var preferredCategoryID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct AssistantAliasRulePayload: Codable, Equatable {
    var id: UUID
    var aliasKey: String
    var targetValue: String
    var entityTypeRaw: String
    var createdAt: Date
    var updatedAt: Date
}

struct IncomeSeriesPayload: Codable, Equatable {
    var id: UUID
    var source: String
    var amount: Double
    var isPlanned: Bool
    var frequencyRaw: String
    var interval: Int
    var weeklyWeekday: Int
    var monthlyDayOfMonth: Int
    var monthlyIsLastDay: Bool
    var yearlyMonth: Int
    var yearlyDayOfMonth: Int
    var startDate: Date
    var endDate: Date
}

struct IncomePayload: Codable, Equatable {
    var id: UUID
    var source: String
    var amount: Double
    var date: Date
    var isPlanned: Bool
    var isException: Bool
    var seriesID: UUID?
    var cardID: UUID?
}

struct WorkspaceArchivePayloadCounts: Equatable {
    var budgets: Int
    var budgetCardLinks: Int
    var budgetPresetLinks: Int
    var budgetCategoryLimits: Int
    var cards: Int
    var categories: Int
    var presets: Int
    var plannedExpenses: Int
    var variableExpenses: Int
    var allocationAccounts: Int
    var expenseAllocations: Int
    var allocationSettlements: Int
    var savingsAccounts: Int
    var savingsLedgerEntries: Int
    var importMerchantRules: Int
    var assistantAliasRules: Int
    var incomeSeries: Int
    var incomes: Int

    var totalRecords: Int {
        budgets + budgetCardLinks + budgetPresetLinks + budgetCategoryLimits + cards + categories + presets +
        plannedExpenses + variableExpenses + allocationAccounts + expenseAllocations + allocationSettlements +
        savingsAccounts + savingsLedgerEntries + importMerchantRules + assistantAliasRules + incomeSeries + incomes
    }

    var userVisibleTotalRecords: Int {
        totalRecords - assistantAliasRules
    }

    init(archive: WorkspaceArchive) {
        budgets = archive.budgets.count
        budgetCardLinks = archive.budgetCardLinks.count
        budgetPresetLinks = archive.budgetPresetLinks.count
        budgetCategoryLimits = archive.budgetCategoryLimits.count
        cards = archive.cards.count
        categories = archive.categories.count
        presets = archive.presets.count
        plannedExpenses = archive.plannedExpenses.count
        variableExpenses = archive.variableExpenses.count
        allocationAccounts = archive.allocationAccounts.count
        expenseAllocations = archive.expenseAllocations.count
        allocationSettlements = archive.allocationSettlements.count
        savingsAccounts = archive.savingsAccounts.count
        savingsLedgerEntries = archive.savingsLedgerEntries.count
        importMerchantRules = archive.importMerchantRules.count
        assistantAliasRules = archive.assistantAliasRules.count
        incomeSeries = archive.incomeSeries.count
        incomes = archive.incomes.count
    }
}

enum WorkspaceArchiveCoding {
    static func encode(_ archive: WorkspaceArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> WorkspaceArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceArchive.self, from: data)
    }
}
