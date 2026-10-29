import Foundation

/// Reduces a semantic patch against app-owned context. No model, database access,
/// prompt routing, financial calculation, or memory mutation happens here.
nonisolated enum MarinaRequestCompiler {
    enum DateOrigin: String, Codable, Equatable, Sendable { case explicit, budgetDefault, appDefault }
    enum DateSide: String, Codable, Hashable, Sendable { case primary, comparison }

    struct Entity: Codable, Equatable, Sendable {
        var reference: String
        var workspaceID: UUID
        var kind: String
        var id: String
        var name: String
    }

    struct Context: Sendable {
        var workspaceID: UUID
        var prompt: String
        var now: Date
        var calendar: Calendar = .current
        var activeRequest: MarinaDataRequest? = nil
        var earlierRequests: [String: MarinaDataRequest] = [:]
        var pendingRequest: MarinaDataRequest? = nil
        var pendingCompilation: Compilation? = nil
        var entities: [Entity] = []
        var defaultPeriod: MarinaTurnPatch.DateIntent = .relative(.selectedPeriod)
        var activeDateOrigin: DateOrigin = .explicit
        var earlierDateOrigins: [String: DateOrigin] = [:]
        var pendingDateOrigin: DateOrigin = .explicit
        var validatedContextReferences: Set<String> = []
    }

    struct UnresolvedTarget: Codable, Equatable, Sendable {
        var id: String
        var field: MarinaTurnPatch.TargetField
        var name: String
        var isComparison: Bool
        var source: MarinaPatchSource
    }

    struct Compilation: Codable, Equatable, Sendable {
        var capability: MarinaCapability
        var request: MarinaDataRequest
        var dateOrigin: DateOrigin
        var unresolvedTargets: [UnresolvedTarget] = []
        var comparisonUsesPrimarySelection: Bool = false
        var pendingDateSide: DateSide? = nil
        var isReady: Bool { unresolvedTargets.isEmpty }
    }

    struct Failure: Error, Equatable, LocalizedError, Sendable {
        enum Code: String, Sendable { case missingBase, missingCapability, invalidSource, unknownReference, wrongWorkspace, incompatibleTarget, invalidValue, missingField }
        var code: Code
        var message: String
        var errorDescription: String? { message }
    }

    static func compile(_ patch: MarinaTurnPatch, context: Context) throws -> Compilation {
        let base: MarinaDataRequest?
        var origin: DateOrigin
        switch patch.base {
        case .newQuestion: base = nil; origin = .appDefault
        case .active:
            base = context.activeRequest; origin = context.activeDateOrigin
            guard base != nil else { throw failure(.missingBase, "There is no completed active question to continue.") }
        case .earlier(let reference):
            base = context.earlierRequests[reference]; origin = context.earlierDateOrigins[reference] ?? .explicit
            guard base != nil else { throw failure(.missingBase, "That earlier question is unavailable. Clarify which question to resume.") }
        case .pending:
            base = context.pendingCompilation?.request ?? context.pendingRequest
            origin = context.pendingCompilation?.dateOrigin ?? context.pendingDateOrigin
            guard base != nil else { throw failure(.missingBase, "There is no pending typed question to complete.") }
        }
        let previousCapability = base.flatMap(MarinaCapability.matching)
        let capability = try value(patch.capability, keeping: previousCapability, context: context)
        guard let capability else { throw failure(.missingCapability, "Choose the requested report before compiling its filters.") }
        var request = base ?? MarinaDataRequest(tool: capability.tool)
        let capabilityChanged = previousCapability != capability
        applyCapability(capability, previous: previousCapability, to: &request)
        if capabilityChanged { request.metric = nil }
        var compiled = Compilation(capability: capability, request: request, dateOrigin: origin)
        if case .pending = patch.base, let pending = context.pendingCompilation {
            compiled.unresolvedTargets = pending.unresolvedTargets
            compiled.comparisonUsesPrimarySelection = pending.comparisonUsesPrimarySelection
            compiled.pendingDateSide = pending.pendingDateSide
        }
        try applyTargets(patch.targets, comparison: false, to: &compiled, context: context)
        if !patch.comparisonTargets.isEmpty && !capability.isComparison {
            throw failure(.invalidValue, "Only comparisons accept a second selection.")
        }
        if capability.isComparison, compiled.request.comparisonFilter == nil {
            compiled.request.comparisonFilter = filter(compiled.request)
        }
        compiled.comparisonUsesPrimarySelection = capability.isComparison && patch.comparisonTargets.isEmpty
            && (compiled.comparisonUsesPrimarySelection || base?.comparisonFilter == nil
                || base.map { sameSelection($0.comparisonFilter ?? filter($0), filter($0)) } == true)
        try applyTargets(patch.comparisonTargets, comparison: true, to: &compiled, context: context)
        request = compiled.request

        request.metric = try value(patch.metric, keeping: request.metric, context: context)
        request.expenseMeasure = try value(patch.measure, keeping: request.expenseMeasure, context: context) ?? .budgetImpact
        request.scope = try value(patch.scope, keeping: request.scope, context: context) ?? .all
        request.state = try value(patch.state, keeping: request.state, context: context) ?? .all
        request.grouping = try value(patch.grouping, keeping: request.grouping, context: context) ?? .none
        if let grouping = capability.fixedGrouping { request.grouping = grouping }
        request.sort = try value(patch.sort, keeping: request.sort, context: context) ?? defaultSort(capability)
        request.limit = try value(patch.limit, keeping: request.limit, context: context) ?? 5
        request.periodUnit = try value(patch.periodUnit, keeping: request.periodUnit, context: context)
        request.chartIntent = try value(patch.chartIntent, keeping: request.chartIntent, context: context)
        request.transactionFilter = try value(patch.transactionFilter, keeping: request.transactionFilter, context: context)
        request.availabilityFilter = try value(patch.availabilityFilter, keeping: request.availabilityFilter, context: context)
        request.includeFuture = try value(patch.includeFuture, keeping: request.includeFuture, context: context) ?? false
        request.recordKind = try value(patch.recordKind, keeping: request.recordKind, context: context)

        switch patch.dates {
        case .keep:
            let changesBudget = patch.targets.contains { change in
                guard change.field == .budget || change.field == .periodBudget else { return false }
                if case .keep = change.change { return false }; return true
            }
            if base == nil || (changesBudget && origin != .explicit) {
                clearDates(&request, preservingPeriodBudget: true)
                if request.budgetID != nil || request.periodBudgetID != nil
                    || compiled.unresolvedTargets.contains(where: { $0.field == .budget || $0.field == .periodBudget }) {
                    origin = .budgetDefault
                } else if capability.tool != .accounts && capability.tool != .findRecords {
                    let period: MarinaTurnPatch.DateIntent = capability == .upcomingPresets ? .relative(.nextSevenDays) : context.defaultPeriod
                    try applyDate(period, to: &request, context: context, base: base)
                    origin = .appDefault
                }
            }
        case .set(let intent, let source):
            try validateDateSource(source, intent: intent, context: context)
            try applyDate(intent, to: &request, context: context, base: base)
            origin = .explicit
        case .clear(let source):
            try validateEdit(source, context: context)
            clearDates(&request, preservingPeriodBudget: true)
            if request.budgetID != nil || request.periodBudgetID != nil { origin = .budgetDefault }
            else {
                if capability.tool != .accounts && capability.tool != .findRecords {
                    try applyDate(context.defaultPeriod, to: &request, context: context, base: nil)
                }
                origin = .appDefault
            }
        }
        if capability.isComparison {
            switch patch.comparisonDates {
            case .keep: break
            case .set(let intent, let source):
                try validateDateSource(source, intent: intent, context: context)
                var other = MarinaDataRequest(tool: request.tool)
                try applyDate(intent, to: &other, context: context, base: base)
                // Period-only budget references cannot be stored on the other side of
                // the legacy request; resolve that window before supplying the patch.
                guard other.periodBudgetID == nil else { throw failure(.invalidValue, "Resolve the comparison budget's date window first.") }
                setComparisonDates(from: other, on: &request)
            case .clear(let source):
                try validateEdit(source, context: context)
                setComparisonDates(from: MarinaDataRequest(tool: request.tool), on: &request)
            }
        } else if case .set = patch.comparisonDates {
            throw failure(.invalidValue, "A second period requires a comparison capability.")
        }
        if [.largestExpense, .smallestExpense].contains(capability) {
            request.sort = capability == .largestExpense ? .largest : .smallest
            request.limit = 1
            request.positiveOnly = request.expenseMeasure != .ledger
        }
        if capability == .leaderComparison { request.limit = 1 }
        if capability == .upcomingPresets {
            request.operation = .transactions; request.scope = .planned; request.state = .planned
            request.expenseMeasure = .planned; request.includeFuture = true; request.sort = .oldest
        }
        if capability == .nextPlannedExpense {
            request.operation = .transactions; request.scope = .planned; request.state = .all
            request.expenseMeasure = .spending; request.includeFuture = true; request.sort = .oldest; request.limit = 1
        }
        if [.linkedCards, .linkedPresets].contains(capability) { request.operation = .inventory }
        if [.incomeProgress, .incomeTimeline].contains(capability) { request.state = .all }
        compiled.request = request; compiled.dateOrigin = origin
        if compiled.comparisonUsesPrimarySelection { compiled.request.comparisonFilter = filter(compiled.request) }
        try validate(compiled)
        return compiled
    }

    /// Fills a resolver-confirmed typed reference without another language-model pass.
    /// Call only after a fresh workspace lookup or an explicit offered-candidate choice.
    static func resolving(_ targetID: String, with reference: String, in compilation: Compilation,
                          context: Context) throws -> Compilation {
        guard let target = compilation.unresolvedTargets.first(where: { $0.id == targetID }) else {
            throw failure(.unknownReference, "That unresolved target is no longer pending.")
        }
        let entity = try entity(reference, context: context)
        var result = compilation
        try apply(entity, field: target.field, comparison: target.isComparison, to: &result.request)
        if result.comparisonUsesPrimarySelection { result.request.comparisonFilter = filter(result.request) }
        result.unresolvedTargets.removeAll { $0.id == targetID }
        try validate(result)
        return result
    }

    private static func applyCapability(_ capability: MarinaCapability, previous: MarinaCapability?, to request: inout MarinaDataRequest) {
        let oldTool = request.tool
        request.tool = capability.tool; request.purpose = nil; request.operation = .summary
        request.offset = 0; request.forcePresentation = nil; request.hypotheticalSpending = nil
        request.exactRecordName = nil; request.expectedRecordID = nil; request.positiveOnly = nil
        if oldTool != request.tool { request.expenseMeasure = .budgetImpact; request.state = .all; request.scope = .all }
        if !capability.usesGrouping { request.grouping = .none }
        if !capability.usesPeriodUnit { request.periodUnit = nil }
        if capability.tool != .expenses { request.transactionFilter = nil }
        if capability != .categoryAvailability { request.availabilityFilter = nil }
        if capability != .inventory { request.recordKind = nil }
        if previous != capability { request.sort = defaultSort(capability); request.limit = 5 }
        if !capability.isComparison {
            request.comparisonFilter = nil; request.comparisonPeriod = nil; request.comparisonAllTime = false
            request.comparisonStartDate = nil; request.comparisonEndDate = nil
        }
        request.compareLeaders = capability == .leaderComparison ? true : nil
        switch capability {
        case .transactions, .largestExpense, .smallestExpense, .incomeTransactions, .accountActivity: request.operation = .transactions
        case .rankedSpending, .categoryRanking, .cardRanking, .merchantRanking, .incomeGroups: request.operation = .ranking
        case .spendingShares: request.operation = .share
        case .spendingComparison, .leaderComparison, .incomeComparison: request.operation = .comparison
        case .spendingTrend, .incomeTrend, .savingsTrend:
            request.operation = .trend; request.periodUnit = request.periodUnit ?? .month
        case .cardSummary:
            request.purpose = .cardSummary; request.expenseMeasure = .spending; request.scope = .all; request.transactionFilter = nil
        case .spendingPatterns: request.purpose = .spendingPatterns
        case .upcomingPresets: request.purpose = .upcomingPresets
        case .nextPlannedExpense: request.purpose = .nextPlannedExpense
        case .incomeProgress: request.purpose = .incomeProgress; request.state = .all
        case .incomeTimeline: request.purpose = .incomeTimeline; request.state = .all
        case .budgetDetails: request.purpose = .budgetDetails
        case .budgetPace: request.purpose = .budgetPace
        case .categoryAvailability: request.purpose = .categoryAvailability
        case .savingsOutlook: request.purpose = .savingsOutlook
        case .savingsTimeline: request.purpose = .savingsTimeline
        case .linkedCards: request.purpose = .budgetCards
        case .linkedPresets: request.purpose = .budgetPresets
        case .inventory: request.operation = .inventory
        default: break
        }
    }

    private static func defaultSort(_ capability: MarinaCapability) -> MarinaDataRequest.Sort {
        switch capability { case .rankedSpending, .categoryRanking, .cardRanking, .merchantRanking, .spendingShares, .leaderComparison, .largestExpense: .largest
        case .smallestExpense: .smallest; default: .newest }
    }

    private static func value<T>(_ patch: MarinaFieldPatch<T>, keeping existing: T?, context: Context) throws -> T? {
        switch patch {
        case .keep: return existing
        case .set(let value, let source): try validateEdit(source, context: context); return value
        case .clear(let source): try validateEdit(source, context: context); return nil
        }
    }

    private static func validateEdit(_ source: MarinaPatchSource, context: Context) throws {
        guard case .userText = source else { throw failure(.invalidSource, "A changed value or removal needs current user wording; use keep to retain prior context.") }
        try validate(source, context: context)
    }

    private static func validateDateSource(_ source: MarinaPatchSource, intent: MarinaTurnPatch.DateIntent, context: Context) throws {
        if case .contextReference(let reference) = source {
            switch intent {
            case .query(let requested) where requested == reference && context.earlierRequests[reference] != nil:
                break
            case .budget(let requested) where requested == reference:
                let target = try entity(reference, context: context)
                guard ["budget", "periodBudget"].contains(target.kind) else { throw failure(.invalidSource, "A budget date source requires a budget reference.") }
            default: throw failure(.invalidSource, "A context date source can only copy that reference's own period.")
            }
        }
        try validate(source, context: context)
    }

    private static func validate(_ source: MarinaPatchSource, context: Context) throws {
        switch source {
        case .userText(let quote):
            guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  context.prompt.range(of: quote) != nil else { throw failure(.invalidSource, "The proposed change has no matching span in the current message.") }
        case .contextReference(let reference):
            let known = context.validatedContextReferences.contains(reference) || context.earlierRequests[reference] != nil
                || context.entities.contains { $0.reference == reference && $0.workspaceID == context.workspaceID }
            guard known else { throw failure(.invalidSource, "The proposed change refers to unavailable context.") }
        }
    }

    private static func applyTargets(_ changes: [MarinaTurnPatch.TargetChange], comparison: Bool,
                                     to compilation: inout Compilation, context: Context) throws {
        guard Set(changes.map(\.field)).count == changes.count else { throw failure(.invalidValue, "A target field may be changed only once per side.") }
        for change in changes {
            switch change.change {
            case .keep: continue
            case .clear(let source):
                try validateEdit(source, context: context)
                compilation.unresolvedTargets.removeAll { $0.field == change.field && $0.isComparison == comparison }
                try clear(change.field, comparison: comparison, in: &compilation.request)
            case .set(let targets, let source):
                try validate(source, context: context)
                guard !targets.isEmpty, change.field == .categories || targets.count == 1 else { throw failure(.invalidValue, "Use one target per field, or one or more categories.") }
                compilation.unresolvedTargets.removeAll { $0.field == change.field && $0.isComparison == comparison }
                try clear(change.field, comparison: comparison, in: &compilation.request)
                for (index, target) in targets.enumerated() {
                    switch target {
                    case .reference(let reference):
                        let selected = try entity(reference, context: context)
                        if case .contextReference(let sourceReference) = source,
                           !sourceSupports(selected, field: change.field, reference: sourceReference, context: context) {
                            throw failure(.invalidSource, "The context source does not select that target.")
                        }
                        try apply(selected, field: change.field, comparison: comparison, to: &compilation.request)
                    case .name(let name):
                        guard case .userText(let quote) = source, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              quote.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                            throw failure(.invalidSource, "An unresolved name must come from the current message's quoted target.")
                        }
                        compilation.unresolvedTargets.append(.init(id: "\(comparison ? "other" : "primary").\(change.field.rawValue).\(index)",
                            field: change.field, name: name, isComparison: comparison, source: source))
                    }
                }
            }
        }
    }

    private static func entity(_ reference: String, context: Context) throws -> Entity {
        guard let entity = context.entities.first(where: { $0.reference == reference }) else { throw failure(.unknownReference, "The selected reference is unavailable; resolve it again.") }
        guard entity.workspaceID == context.workspaceID else { throw failure(.wrongWorkspace, "The selected reference belongs to another workspace.") }
        return entity
    }

    private static func sourceSupports(_ entity: Entity, field: MarinaTurnPatch.TargetField, reference: String, context: Context) -> Bool {
        if reference == entity.reference { return true }
        let request = context.earlierRequests[reference]
            ?? (reference == "active" ? context.activeRequest : nil)
            ?? (reference == "pending" ? context.pendingCompilation?.request ?? context.pendingRequest : nil)
        guard let request else { return false }
        switch field {
        case .card: return request.cardID == entity.id
        case .categories: return request.categoryID == entity.id || request.categoryIDs?.contains(entity.id) == true
        case .budget: return request.budgetID == entity.id
        case .periodBudget: return request.periodBudgetID == entity.id || request.budgetID == entity.id
        case .preset: return request.presetID == entity.id
        case .merchant: return request.merchantName == entity.name
        case .incomeSource: return request.search == entity.name
        case .account: return request.accountID == entity.id
        }
    }

    private static func apply(_ entity: Entity, field: MarinaTurnPatch.TargetField, comparison: Bool, to request: inout MarinaDataRequest) throws {
        let compatible: Bool
        switch field {
        case .card: compatible = entity.kind == "card"
        case .categories: compatible = entity.kind == "category"
        case .budget, .periodBudget: compatible = ["budget", "periodBudget"].contains(entity.kind)
        case .preset: compatible = entity.kind == "preset"
        case .merchant: compatible = entity.kind == "merchant"
        case .incomeSource: compatible = entity.kind == "incomeSource"
        case .account: compatible = ["savingsAccount", "reconciliationAccount"].contains(entity.kind)
        }
        guard compatible else { throw failure(.incompatibleTarget, "The resolved record does not match the requested target type.") }
        if comparison {
            guard ![MarinaTurnPatch.TargetField.account, .periodBudget].contains(field) else { throw failure(.incompatibleTarget, "This target cannot select a comparison side.") }
            var other = requestFromFilter(request.comparisonFilter ?? filter(request), tool: request.tool)
            try apply(entity, field: field, comparison: false, to: &other)
            request.comparisonFilter = filter(other)
            return
        }
        switch field {
        case .card: request.cardID = entity.id
        case .categories:
            let ids = Set((request.categoryIDs ?? []) + [request.categoryID].compactMap { $0 } + [entity.id])
            request.categoryID = nil; request.categoryIDs = ids.sorted()
        case .budget: request.budgetID = entity.id
        case .periodBudget: request.periodBudgetID = entity.id
        case .preset: request.presetID = entity.id
        case .merchant: request.merchantName = entity.name; request.search = nil
        case .incomeSource: request.search = entity.name
        case .account:
            request.accountID = entity.id; request.scope = entity.kind == "savingsAccount" ? .savings : .reconciliation
        }
    }

    private static func clear(_ field: MarinaTurnPatch.TargetField, comparison: Bool, in request: inout MarinaDataRequest) throws {
        if comparison {
            guard ![MarinaTurnPatch.TargetField.account, .periodBudget].contains(field) else { throw failure(.incompatibleTarget, "This target cannot select a comparison side.") }
            var other = requestFromFilter(request.comparisonFilter ?? filter(request), tool: request.tool)
            try clear(field, comparison: false, in: &other); request.comparisonFilter = filter(other); return
        }
        switch field {
        case .card: request.cardID = nil
        case .categories: request.categoryID = nil; request.categoryIDs = nil
        case .budget: request.budgetID = nil
        case .periodBudget: request.periodBudgetID = nil
        case .preset: request.presetID = nil
        case .merchant: request.merchantName = nil; request.search = nil
        case .incomeSource: request.search = nil
        case .account: request.accountID = nil; request.scope = .all
        }
    }

    private static func filter(_ request: MarinaDataRequest) -> MarinaDataRequest.Filter {
        .init(cardID: request.cardID, categoryID: request.categoryID, categoryIDs: request.categoryIDs,
            budgetID: request.budgetID, presetID: request.presetID, search: request.search, merchantName: request.merchantName)
    }
    private static func requestFromFilter(_ filter: MarinaDataRequest.Filter, tool: MarinaDataRequest.Tool) -> MarinaDataRequest {
        .init(merchantName: filter.merchantName, categoryIDs: filter.categoryIDs, tool: tool, presetID: filter.presetID,
            cardID: filter.cardID, categoryID: filter.categoryID, budgetID: filter.budgetID, search: filter.search)
    }

    private static func sameSelection(_ lhs: MarinaDataRequest.Filter, _ rhs: MarinaDataRequest.Filter) -> Bool {
        func canonical(_ input: MarinaDataRequest.Filter) -> MarinaDataRequest.Filter {
            var value = input
            value.cardID = value.cardID?.lowercased(); value.budgetID = value.budgetID?.lowercased(); value.presetID = value.presetID?.lowercased()
            let categories = Set(((value.categoryIDs ?? []) + [value.categoryID].compactMap { $0 }).map { $0.lowercased() })
            value.categoryID = nil; value.categoryIDs = categories.isEmpty ? nil : categories.sorted()
            value.merchantName = value.merchantName?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            value.search = value.search?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return value
        }
        return canonical(lhs) == canonical(rhs)
    }

    private static func applyDate(_ intent: MarinaTurnPatch.DateIntent, to request: inout MarinaDataRequest,
                                  context: Context, base: MarinaDataRequest?) throws {
        clearDates(&request)
        switch intent {
        case .range(let start, let end):
            guard let first = parseDate(start, calendar: context.calendar), let last = parseDate(end, calendar: context.calendar), first <= last else {
                throw failure(.invalidValue, "Provide a valid inclusive start and end date.")
            }
            request.startDate = start; request.endDate = end
        case .allTime: request.allTime = true
        case .query(let reference):
            guard let earlier = context.earlierRequests[reference] else { throw failure(.unknownReference, "The referenced period is unavailable.") }
            request.startDate = earlier.startDate; request.endDate = earlier.endDate; request.relativePeriod = earlier.relativePeriod
            request.allTime = earlier.allTime; request.periodBudgetID = earlier.periodBudgetID
        case .budget(let reference):
            try apply(entity(reference, context: context), field: .periodBudget, comparison: false, to: &request)
        case .month(let year, let month):
            let inheritedYear = base?.startDate.flatMap { parseDate($0, calendar: context.calendar) }.map { context.calendar.component(.year, from: $0) }
            let year = year ?? inheritedYear ?? context.calendar.component(.year, from: context.now)
            guard (1...9999).contains(year), (1...12).contains(month), let first = context.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let interval = context.calendar.dateInterval(of: .month, for: first) else { throw failure(.invalidValue, "The requested month is invalid.") }
            setRange(interval.start, interval.end.addingTimeInterval(-0.001), on: &request, calendar: context.calendar)
        case .year(let year):
            guard (1...9999).contains(year), let first = context.calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let interval = context.calendar.dateInterval(of: .year, for: first) else { throw failure(.invalidValue, "The requested year is invalid.") }
            setRange(interval.start, interval.end.addingTimeInterval(-0.001), on: &request, calendar: context.calendar)
        case .relative(let period):
            switch period {
            case .selectedPeriod, .previousPeriod: request.relativePeriod = period
            case .currentMonth, .previousMonth:
                let anchor = period == .previousMonth ? context.calendar.date(byAdding: .month, value: -1, to: context.now) : context.now
                guard let anchor, let interval = context.calendar.dateInterval(of: .month, for: anchor) else { throw failure(.invalidValue, "The calendar month is unavailable.") }
                setRange(interval.start, interval.end.addingTimeInterval(-0.001), on: &request, calendar: context.calendar)
            case .yearToDate:
                guard let interval = context.calendar.dateInterval(of: .year, for: context.now) else { throw failure(.invalidValue, "The calendar year is unavailable.") }
                setRange(interval.start, context.now, on: &request, calendar: context.calendar)
            case .nextSevenDays:
                guard let end = context.calendar.date(byAdding: .day, value: 6, to: context.now) else { throw failure(.invalidValue, "The requested date window is unavailable.") }
                setRange(context.now, end, on: &request, calendar: context.calendar)
            }
        }
    }

    private static func clearDates(_ request: inout MarinaDataRequest, preservingPeriodBudget: Bool = false) {
        request.startDate = nil; request.endDate = nil; request.relativePeriod = nil; request.allTime = false
        if !preservingPeriodBudget { request.periodBudgetID = nil }
    }
    private static func setComparisonDates(from other: MarinaDataRequest, on request: inout MarinaDataRequest) {
        request.comparisonStartDate = other.startDate; request.comparisonEndDate = other.endDate
        request.comparisonPeriod = other.relativePeriod; request.comparisonAllTime = other.allTime
    }
    private static func setRange(_ start: Date, _ end: Date, on request: inout MarinaDataRequest, calendar: Calendar) {
        let formatter = formatter(calendar)
        request.startDate = formatter.string(from: start); request.endDate = formatter.string(from: end)
    }
    private static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let formatter = formatter(calendar)
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }; return date
    }
    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let value = DateFormatter(); value.calendar = calendar; value.timeZone = calendar.timeZone
        value.locale = Locale(identifier: "en_US_POSIX"); value.dateFormat = "yyyy-MM-dd"; value.isLenient = false; return value
    }

    private static func validate(_ compilation: Compilation) throws {
        let request = compilation.request, capability = compilation.capability
        guard (1...50).contains(request.limit) else { throw failure(.invalidValue, "Choose a result count between one and fifty.") }
        if let metric = request.metric, !capability.allowedMetrics.contains(metric) {
            throw failure(.invalidValue, "That metric is not supplied by the selected report.")
        }
        if capability.usesGrouping {
            let valid: [MarinaDataRequest.Grouping] = capability == .incomeGroups ? [.card, .source] : [.category, .card, .merchant]
            guard valid.contains(request.grouping) else { throw failure(.missingField, "Choose the requested grouping dimension.") }
        } else if request.grouping != .none { throw failure(.invalidValue, "This report does not accept grouping.") }
        if capability.isComparison && request.comparisonStartDate == nil && request.comparisonPeriod == nil && !request.comparisonAllTime {
            let hasUnresolvedOther = compilation.unresolvedTargets.contains(where: \.isComparison)
            let sameSubject = request.comparisonFilter.map { sameSelection($0, filter(request)) } ?? true
            if compilation.comparisonUsesPrimarySelection || (sameSubject && !hasUnresolvedOther) {
                throw failure(.missingField, "Choose the other comparison period; an unchanged selection alone cannot compare a period with itself.")
            }
        }
        if capability == .cardSummary && request.cardID == nil && !compilation.unresolvedTargets.contains(where: { $0.field == .card && !$0.isComparison }) {
            throw failure(.missingField, "A card summary requires one selected card; use ranked spending to compare cards.")
        }
        if capability == .cardSummary && (request.scope != .all || request.expenseMeasure != .spending || request.transactionFilter != nil
            || request.merchantName != nil || request.categoryID != nil || request.categoryIDs != nil || request.presetID != nil) {
            throw failure(.invalidValue, "A complete card summary uses all planned and variable card spending. Use an expense report for a narrower selection.")
        }
        if [.linkedCards, .linkedPresets].contains(capability) && request.budgetID == nil
            && !compilation.unresolvedTargets.contains(where: { $0.field == .budget && !$0.isComparison }) {
            throw failure(.missingField, "Choose the budget whose linked records are requested.")
        }
        if request.tool != .expenses && (request.presetID != nil || request.merchantName != nil || request.transactionFilter != nil || request.expenseMeasure != .budgetImpact) {
            throw failure(.incompatibleTarget, "The prior expense filters do not belong to this report. Explicitly choose a new question or clear them.")
        }
        if request.accountID != nil && request.tool != .accounts { throw failure(.incompatibleTarget, "Account selection requires an account report.") }
        if request.availabilityFilter != nil && capability != .categoryAvailability { throw failure(.invalidValue, "Category status filtering requires category availability.") }
        if request.periodUnit != nil && !capability.usesPeriodUnit && request.metric != .averagePerPeriod { throw failure(.invalidValue, "A period unit requires a timeline or per-period average.") }
        if request.recordKind != nil && capability != .inventory { throw failure(.invalidValue, "Record-kind selection requires an inventory.") }
    }

    private static func failure(_ code: Failure.Code, _ message: String) -> Failure { .init(code: code, message: message) }
}
