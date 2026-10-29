import Foundation

/// Conservative constraints from explicit wording in this turn, never a query or date parser.
/// Only explicit, unambiguous universal scopes can remove an unintended individual selection.
nonisolated struct MarinaTurnPolicy {
    enum PeriodCue: Equatable, Sendable {
        case none
        case relative(MarinaDataRequest.RelativePeriod)
        /// Explicit date wording outside the supported single-period cues must not reuse old dates.
        case other
    }

    let periodCue: PeriodCue
    /// A closed vocabulary signal only; callers must also require the same financial tool and
    /// no newly resolved or pending target before reusing the prior selection.
    let isContextualFinancialFollowUp: Bool
    let requiresPeriodComparison: Bool
    let requiresBudgetPace: Bool
    /// Only permits an explicit corrected workspace selection after an invalid reference.
    /// Callers must separately rule out prior financial context and all named/pending targets.
    let permitsUnfilteredSelectionRepair: Bool
    private let explicitFinancialTopic: MarinaDataRequest.Tool?
    private enum IncomeIntent { case planned, actual, progress }
    private let incomeIntent: IncomeIntent?
    private let requiresIncomeReceiptProgress: Bool
    private let requiresIncomeProgressOperation: Bool
    private struct ComparisonPeriods {
        let primary: MarinaDataRequest.RelativePeriod
        let other: MarinaDataRequest.RelativePeriod
    }
    private let orderedComparisonPeriods: ComparisonPeriods?
    private let isEmpty: Bool
    private let affirmativeClauses: [[String]]
    private let allCards: Bool
    private let allSavingsAccounts: Bool
    private let allReconciliationAccounts: Bool
    private let wholeWorkspace: Bool
    private let workspaceMentionIsOnlyScope: Bool
    private let permitsUniversalConstraints: Bool
    private let normalizedPrompt: String
    private let asksForSingleAmount: Bool
    private let asksForAccountActivity: Bool
    var isExplicitFinancialQuestion: Bool { explicitFinancialTopic != nil }

    init(prompt: String) {
        isEmpty = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let clauses = Self.affirmativeClauses(in: prompt)
        affirmativeClauses = clauses
        normalizedPrompt = Self.normalized(prompt)
        asksForSingleAmount = Self.containsAny(["how much", "what is the total", "cuanto", "cuanta", "importe total"], in: clauses)
            && !Self.hasNegationOrComparison(prompt)
            && !Self.containsAny(["rank", "ranking", "rankings", "list", "transactions", "purchases", "share", "shares",
                                  "percent", "percentage", "breakdown", "by card", "top", "largest", "smallest", "sort",
                                  "clasificacion", "lista", "transacciones", "porcentaje", "participacion", "mayor", "menor"], in: clauses)
        asksForAccountActivity = Self.containsAny(["activity", "transactions", "history", "entries", "deposits", "withdrawals",
                                                  "actividad", "transacciones", "movimientos", "depositos", "retiros"], in: clauses)
        let budgetPace = Self.requiresBudgetPace(prompt)
        requiresBudgetPace = budgetPace
        // In the exact pace phrasing, "against the plan" is not a second date or period.
        let datePrompt = budgetPace ? prompt.replacingOccurrences(of: "against", with: "toward", options: .caseInsensitive) : prompt
        periodCue = Self.periodCue(in: datePrompt, clauses: Self.affirmativeClauses(in: datePrompt))
        let receiptProgress = Self.requiresIncomeReceiptProgress(prompt)
        requiresIncomeReceiptProgress = receiptProgress
        requiresIncomeProgressOperation = receiptProgress || Self.requiresExplicitIncomeProgressOperation(prompt)
        incomeIntent = receiptProgress ? .progress : Self.incomeIntent(in: prompt)
        isContextualFinancialFollowUp = Self.isContextualFinancialFollowUp(prompt)
        requiresPeriodComparison = Self.requiresPeriodComparison(prompt)
        orderedComparisonPeriods = Self.orderedComparisonPeriods(prompt)
        permitsUnfilteredSelectionRepair = Self.permitsUnfilteredSelectionRepair(prompt)
        explicitFinancialTopic = Self.explicitFinancialTopic(in: prompt)
        allCards = Self.containsAny([
            "all cards", "all my cards", "all the cards", "all of my cards", "all of the cards",
            "todas mis tarjetas", "todas las tarjetas", "todas tarjetas", "todos mis tarjetas"
        ], in: clauses)
        allSavingsAccounts = Self.containsAny([
            "all savings accounts", "all my savings accounts", "all the savings accounts",
            "all of my savings accounts", "all of the savings accounts",
            "todas mis cuentas de ahorro", "todas las cuentas de ahorro", "todas cuentas de ahorro",
            "todos mis cuentas de ahorro"
        ], in: clauses)
        allReconciliationAccounts = Self.containsAny([
            "all reconciliation accounts", "all my reconciliation accounts", "all the reconciliation accounts",
            "all of my reconciliation accounts", "all of the reconciliation accounts",
            "todas mis cuentas de conciliacion", "todas las cuentas de conciliacion", "todas cuentas de conciliacion",
            "todos mis cuentas de conciliacion", "todas mis cuentas de reconciliacion", "todas las cuentas de reconciliacion"
        ], in: clauses)
        wholeWorkspace = Self.containsAny([
            "whole workspace", "entire workspace", "across the workspace", "across my workspace",
            "todo el espacio de trabajo", "todo mi espacio de trabajo", "todo este espacio de trabajo"
        ], in: clauses)
        var withoutWorkspaceScope = Self.normalized(prompt)
        for phrase in ["whole workspace", "entire workspace", "across the workspace", "across my workspace",
                       "todo el espacio de trabajo", "todo mi espacio de trabajo", "todo este espacio de trabajo"] {
            withoutWorkspaceScope = withoutWorkspaceScope.replacingOccurrences(of: phrase, with: " ")
        }
        let remainingScopeWords = withoutWorkspaceScope.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        workspaceMentionIsOnlyScope = !Self.containsAny(["workspace", "espacio de trabajo"], in: [remainingScopeWords])
        let hasSavings = Self.containsAny(["savings", "ahorro", "ahorros"], in: clauses)
        let hasReconciliation = Self.containsAny(["reconciliation", "conciliacion", "reconciliacion"], in: clauses)
        let hasIncome = Self.containsAny(["income", "ingresos", "ingreso"], in: clauses)
        let hasCards = Self.containsAny(["card", "cards", "tarjeta", "tarjetas"], in: clauses)
        let mixedDomains = (allCards && (hasSavings || hasReconciliation || hasIncome))
            || (allSavingsAccounts && (hasCards || hasReconciliation || hasIncome))
            || (allReconciliationAccounts && (hasCards || hasSavings || hasIncome))
        let multipleTargets = Self.containsAny(["and", "y"], in: clauses)
            || (allCards && clauses.flatMap { $0 }.filter { ["card", "cards", "tarjeta", "tarjetas"].contains($0) }.count > 1)
        permitsUniversalConstraints = [allCards, allSavingsAccounts, allReconciliationAccounts, wholeWorkspace]
            .filter { $0 }.count == 1 && !mixedDomains && !multipleTargets
            && !Self.hasNegationOrComparison(prompt)
    }

    /// The user's universal scope is authoritative only when no comparison or exclusion is present.
    /// Dates, measures, pagination, and unrelated expense filters remain exactly as requested.
    func constrained(_ request: MarinaDataRequest) -> MarinaDataRequest {
        var constrained = request
        if request.operation == .comparison, [.expenses, .income].contains(request.tool),
           let periods = orderedComparisonPeriods, Self.comparisonScopesMatch(request) {
            constrained.relativePeriod = periods.primary
            constrained.startDate = nil
            constrained.endDate = nil
            constrained.allTime = false
            constrained.comparisonPeriod = periods.other
            constrained.comparisonStartDate = nil
            constrained.comparisonEndDate = nil
            constrained.comparisonAllTime = false
        }
        if Self.isSingleRead(request), case .relative(let period) = periodCue,
           [.expenses, .income, .budgetSummary].contains(request.tool)
            || (request.tool == .accounts && (request.operation == .transactions
                || (request.accountID != nil && asksForAccountActivity))) {
            constrained.relativePeriod = period
            constrained.startDate = nil
            constrained.endDate = nil
            constrained.allTime = false
        }
        if request.tool == .expenses, request.purpose == .upcomingPresets, Self.isSingleRead(request),
           periodCue == .none, !Self.hasNegationOrComparison(normalizedPrompt),
           Self.containsAny(["upcoming", "due soon", "por vencer", "pronto"], in: affirmativeClauses),
           !normalizedPrompt.contains(where: \.isNumber),
           !Self.containsAny(["if", "would", "could", "might", "suppose", "imagine", "hypothetical", "si", "seria", "podria",
                              "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                              "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
                              "between", "until", "through", "since", "before", "after", "entre", "hasta", "antes", "despues"], in: affirmativeClauses) {
            constrained.relativePeriod = .nextSevenDays
            constrained.startDate = nil
            constrained.endDate = nil
            constrained.allTime = false
        }
        if asksForSingleAmount, request.tool == .expenses, request.operation == .ranking,
           request.grouping == .card, request.cardID != nil, Self.isSingleRead(request) {
            constrained.operation = .summary
            constrained.grouping = .none
        }
        if requiresBudgetPace, request.tool == .budgetSummary, request.operation == .summary,
           request.grouping == .none, request.periodUnit == nil, Self.isSingleRead(request) {
            constrained.purpose = .budgetPace
        }
        if request.tool == .income, request.operation == .summary, request.grouping == .none,
           request.periodUnit == nil, Self.isSingleRead(request), let incomeIntent {
            switch incomeIntent {
            case .planned, .actual:
                constrained.state = incomeIntent == .planned ? .planned : .actual
                if constrained.purpose == .incomeProgress { constrained.purpose = nil }
            case .progress:
                constrained.state = .all
                constrained.purpose = .incomeProgress
            }
        }
        guard canConstrain(request), request.tool != .findRecords else { return constrained }
        if (wholeWorkspace || allCards) && [.expenses, .income].contains(request.tool) {
            constrained.cardID = nil
        } else if request.tool == .accounts {
            if allSavingsAccounts { constrained.accountID = nil; constrained.scope = .savings }
            if allReconciliationAccounts { constrained.accountID = nil; constrained.scope = .reconciliation }
        }
        return constrained
    }

    /// Prevent an invented individual lookup from creating a missing-name or ambiguity latch.
    func ignoresNamedLookup(_ request: MarinaDataRequest) -> Bool {
        guard request.tool == .findRecords,
              request.search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        let genericNouns = ["workspace", "workspaces", "budget", "budgets", "category", "categories", "card", "cards",
                            "income", "incomes", "source", "sources", "merchant", "merchants", "savings", "reconciliation",
                            "account", "accounts", "preset", "presets", "espacio de trabajo", "presupuesto", "presupuestos",
                            "categoria", "categorias", "tarjeta", "tarjetas", "ingreso", "ingresos", "fuente", "fuentes",
                            "comercio", "comercios", "ahorro", "ahorros", "conciliacion", "cuenta", "cuentas", "preajuste", "preajustes",
                            "spending", "expense", "expenses", "transaction", "transactions", "total", "totals", "balance", "balances",
                            "payment", "payments", "purchase", "purchases", "activity", "money", "gasto", "gastos", "transaccion",
                            "transacciones", "totales", "saldo", "saldos", "pago", "pagos", "compra", "compras", "actividad", "movimientos", "dinero"]
        let proposedName = Self.normalized(request.search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !isEmpty, genericNouns.contains(proposedName), !explicitlyNamesRecord(proposedName) { return true }
        guard canConstrain(request) else { return false }
        let genericIncomeWords = ["income", "incomes", "ingreso", "ingresos"]
        let genericName = genericIncomeWords.contains(proposedName)
            || (workspaceMentionIsOnlyScope && ["workspace", "espacio de trabajo"].contains(proposedName))
        let genericIncomeLookup = wholeWorkspace && explicitFinancialTopic == .income
            && genericName
            && affirmativeClauses.flatMap { $0 }.filter { genericIncomeWords.contains($0) }.count == 1
            && !Self.containsAny(["from", "source", "fuente", "called", "named", "llamado", "llamada"], in: affirmativeClauses)
        return genericIncomeLookup || ((wholeWorkspace || allCards) && request.recordKind == "card")
            || (allSavingsAccounts && request.recordKind == "savingsAccount")
            || (allReconciliationAccounts && request.recordKind == "reconciliationAccount")
    }

    private func explicitlyNamesRecord(_ name: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        if normalizedPrompt.range(of: "[\"“‘']\\s*" + escaped + "\\s*[\"”’']", options: .regularExpression) != nil { return true }
        return Self.containsAny(["named", "called", "source", "from", "llamado", "llamada", "denominado", "denominada", "fuente",
                                "category", "card", "budget", "preset", "merchant", "savings account", "reconciliation account", "income source",
                                "categoria", "tarjeta", "presupuesto", "preajuste", "comercio", "cuenta de ahorro", "cuenta de conciliacion"]
            .map { $0 + " " + name }, in: affirmativeClauses)
    }

    /// Call only after resolving a known, workspace-bound reference. Unknown references still fail.
    func ignoresSelection(kind: String, for request: MarinaDataRequest) -> Bool {
        guard canConstrain(request), request.tool != .findRecords else { return false }
        let knownKinds = ["card", "category", "budget", "preset", "merchant", "incomeSource",
                          "savingsAccount", "reconciliationAccount", "workspace"]
        guard knownKinds.contains(kind) else { return false }
        if (wholeWorkspace || allCards) && [.expenses, .income].contains(request.tool) { return kind == "card" }
        return request.tool == .accounts && (allSavingsAccounts || allReconciliationAccounts)
    }

    private func canConstrain(_ request: MarinaDataRequest) -> Bool {
        permitsUniversalConstraints && Self.isSingleRead(request)
    }

    private static func isSingleRead(_ request: MarinaDataRequest) -> Bool {
        guard case nil = request.comparisonFilter else { return false }
        return request.operation != .comparison
            && request.comparisonPeriod == nil
            && request.comparisonStartDate == nil && request.comparisonEndDate == nil && !request.comparisonAllTime
    }

    /// A kind must come from the current user's affirmative wording, not the model's guess.
    /// Empty prompts support trusted callers which already provide typed requests.
    func confirms(kind: String) -> Bool {
        if isEmpty { return true }
        return Self.containsAny(Self.nouns(for: kind), in: affirmativeClauses)
    }

    /// A type-only reply can narrow offered choices, but a newly supplied name must
    /// be resolved on its own instead of selecting the sole candidate of that type.
    func confirmsOnlyPendingKind(_ kind: String) -> Bool {
        guard !isEmpty, confirms(kind: kind) else { return false }
        let grammaticalWords: Set<String> = ["i", "mean", "meant", "the", "a", "an", "that", "this", "one", "please",
            "yes", "it", "is", "my", "only", "in", "for", "during", "yo", "quiero", "decir", "el", "la", "los", "las",
            "un", "una", "ese", "esa", "este", "esta", "por", "favor", "si", "es", "mi", "solo", "en", "para", "durante"]
        let typeWords = Self.nouns(for: kind).flatMap { $0.split(separator: " ").map(String.init) }
        let periodWords = Self.supportedPeriods.flatMap(\.1).flatMap { $0.split(separator: " ").map(String.init) }
        let allowed = grammaticalWords.union(typeWords).union(periodWords)
        let words = affirmativeClauses.flatMap { $0 }
        if words.allSatisfy(allowed.contains) { return true }
        // Date adjuncts can accompany a type choice without naming another record.
        // A calendar word directly naming the merchant is not such an adjunct.
        let datePrepositions: Set<String> = ["on", "in", "for", "during", "between", "from", "through", "until", "to",
            "en", "para", "durante", "entre", "desde", "hasta", "al"]
        guard periodCue != .none, !Set(words).isDisjoint(with: datePrepositions) else { return false }
        let calendarWords: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december", "enero", "febrero", "marzo", "abril", "mayo", "junio",
            "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        let dateAllowed = allowed.union(datePrepositions).union(calendarWords)
        return words.allSatisfy { dateAllowed.contains($0) || $0.allSatisfy(\.isNumber) }
    }

    private static func nouns(for kind: String) -> [String] {
        switch kind {
        case "card": ["card", "cards", "tarjeta", "tarjetas"]
        case "category": ["category", "categories", "categoria", "categorias"]
        case "budget": ["budget", "budgets", "presupuesto", "presupuestos"]
        case "preset": ["preset", "presets", "preajuste", "preajustes", "plantilla", "plantillas"]
        case "merchant": ["merchant", "merchants", "comercio", "comercios", "comerciante", "comerciantes"]
        case "savingsAccount": ["savings", "ahorro", "ahorros"]
        case "reconciliationAccount": ["reconciliation", "conciliacion", "reconciliacion"]
        case "incomeSource": ["income", "incomes", "ingreso", "ingresos", "income source", "fuente de ingreso"]
        case "workspace": ["workspace", "workspaces", "espacio de trabajo", "espacios de trabajo"]
        default: []
        }
    }

    /// Remove only an invented record-type suffix from a name literally present in the user's
    /// affirmative wording. This does not infer, expand, or otherwise normalize record names.
    func lookupSearch(proposed: String) -> String {
        let tokens = proposed.split { !$0.isLetter && !$0.isNumber }
        let words = tokens.map { Self.normalized(String($0)) }
        guard !words.isEmpty, !Self.containsAny([words.joined(separator: " ")], in: affirmativeClauses) else { return proposed }
        let suffixes: [(String, [String])] = [
            ("savingsAccount", ["savings", "account"]), ("reconciliationAccount", ["reconciliation", "account"]),
            ("incomeSource", ["income", "source"]), ("savingsAccount", ["cuenta", "de", "ahorro"]),
            ("reconciliationAccount", ["cuenta", "de", "conciliacion"]),
            ("card", ["card"]), ("card", ["tarjeta"]), ("category", ["category"]), ("category", ["categoria"]),
            ("budget", ["budget"]), ("budget", ["presupuesto"]), ("preset", ["preset"]), ("preset", ["preajuste"]),
            ("merchant", ["merchant"]), ("merchant", ["comercio"]), ("workspace", ["workspace"])
        ]
        for (kind, suffix) in suffixes where !confirms(kind: kind) && words.count > suffix.count {
            guard words.suffix(suffix.count).elementsEqual(suffix) else { continue }
            let baseCount = words.count - suffix.count
            let baseWords = Array(words.prefix(baseCount))
            guard Self.containsAny([baseWords.joined(separator: " ")], in: affirmativeClauses) else { continue }
            return String(proposed[..<tokens[baseCount].startIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return proposed
    }

    /// A model-selected tool alone never releases an unresolved question.
    func explicitlyChangesFinancialTopic(from originalPrompt: String, to tool: MarinaDataRequest.Tool) -> Bool {
        guard let current = explicitFinancialTopic, current == tool,
              let original = Self.financialTopic(in: originalPrompt) else { return false }
        return original != current
    }

    /// A successful read can repair an earlier wrong-tool attempt only for the sole
    /// affirmative financial domain; no interrogative prefix is required.
    func acceptsCorrectedFinancialTool(_ tool: MarinaDataRequest.Tool) -> Bool {
        tool != .findRecords && Self.financialTopic(in: normalizedPrompt) == tool
    }

    /// A new full question owns its dates even when it selects a candidate from an older question.
    func shouldRetainPendingPeriod(from originalPrompt: String) -> Bool {
        guard let current = explicitFinancialTopic else { return true }
        return isContextualFinancialFollowUp && Self.financialTopic(in: originalPrompt) == current
    }

    func confirmsPendingCandidate(kind: String, name: String,
                                  candidates: [(kind: String, name: String)], ambiguousSearch: String?) -> Bool {
        func words(_ text: String) -> String {
            Self.normalized(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        // Match the complete offered label before tokenizing. Punctuation belongs to the
        // merchant identity; it must not split a single choice into separate clauses.
        let literal = candidates.filter { MarinaNamedTargetRequirement.containsLiteralName($0.name, in: normalizedPrompt) }
        let allMentions = candidates.filter { Self.containsAny([words($0.name)], in: [words(normalizedPrompt).split(separator: " ").map(String.init)]) }
        let specificallyMentioned = allMentions.filter { candidate in
            !allMentions.contains { other in
                words(other.name) != words(candidate.name)
                    && MarinaNamedTargetRequirement.containsLiteralName(words(candidate.name), in: words(other.name))
            }
        }
        if specificallyMentioned.contains(where: { $0.kind == kind && $0.name == name }),
           !MarinaNamedTargetRequirement.containsLiteralName(words(name), in: words(normalizedPrompt)),
           !literal.contains(where: { $0.kind == kind && $0.name == name }) { return false }
        let normalizedMatches = candidates.filter {
            MarinaNamedTargetRequirement.containsLiteralName(words($0.name), in: words(normalizedPrompt))
        }
        let mentioned = literal + normalizedMatches.filter { candidate in
            !literal.contains { $0.kind == candidate.kind && $0.name == candidate.name }
                && !literal.contains { words($0.name) == words(candidate.name) }
        }
        let longest = mentioned.filter { candidate in
            !mentioned.contains { other in
                words(other.name) != words(candidate.name)
                    && MarinaNamedTargetRequirement.containsLiteralName(words(candidate.name), in: words(other.name))
            }
        }
        if longest.isEmpty, confirmsOnlyPendingKind(kind), candidates.filter({ $0.kind == kind }).count == 1 { return true }
        guard longest.count == 1, longest[0].kind == kind, longest[0].name == name else { return false }
        // Repeating the original broad search cannot resolve its own ambiguity. A full
        // offered label is otherwise authoritative, even when another label extends it.
        return words(name) != ambiguousSearch.map(words) || confirms(kind: kind)
    }

    func violation(for request: MarinaDataRequest) -> String? {
        if requiresIncomeProgressOperation, request.tool != .findRecords,
           request.tool != .income || request.operation != .summary || request.grouping != .none
            || request.periodUnit != nil || !Self.isSingleRead(request) {
            return "The user requested planned-to-actual income progress. Call readIncome with operation progress and state all for the requested period; use its calculated progress rather than separate period totals or another financial tool."
        }
        if request.operation == .comparison, [.expenses, .income].contains(request.tool),
           let periods = orderedComparisonPeriods, !Self.comparisonScopesMatch(request) {
            return "This period comparison refers to the same target on both sides. Preserve that selection and use top-level dates \(periods.primary.rawValue), with comparison dates \(periods.other.rawValue). Repair the differing selections; do not swap dates between targets."
        }
        if requiresBudgetPace, request.tool == .expenses {
            return "The user requested budget pace. Call readBudgetSummary with operation pace and the requested period; an expense total or period comparison cannot answer whether the budget is on track."
        }
        guard canConstrain(request) else { return nil }
        let namedLookup = request.tool == .findRecords
            && request.search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let comparison = request.comparisonFilter
        if (allCards || wholeWorkspace) && (request.cardID != nil || comparison?.cardID != nil
                        || (namedLookup && request.recordKind == "card")) {
            return "The user requested all cards. Remove the card selection; keep other explicitly requested filters."
        }
        if allSavingsAccounts && ((request.accountID != nil && [.all, .savings].contains(request.scope))
                                  || (namedLookup && request.recordKind == "savingsAccount")) {
            return "The user requested all savings accounts. Do not select or look up an individual savings account."
        }
        if allReconciliationAccounts && ((request.accountID != nil && [.all, .reconciliation].contains(request.scope))
                                         || (namedLookup && request.recordKind == "reconciliationAccount")) {
            return "The user requested all reconciliation accounts. Do not select or look up an individual reconciliation account."
        }
        return nil
    }

    private static func containsAny(_ phrases: [String], in clauses: [[String]]) -> Bool {
        phrases.contains { phrase in
            let words = phrase.split(separator: " ").map(String.init)
            return clauses.contains { clause in
                guard clause.count >= words.count else { return false }
                return (0...(clause.count - words.count)).contains { start in
                    clause[start..<(start + words.count)].elementsEqual(words)
                }
            }
        }
    }

    private static func normalized(_ prompt: String) -> String {
        prompt.folding(options: [.caseInsensitive, .diacriticInsensitive],
                       locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "n['’]t\\b", with: " not", options: .regularExpression)
    }

    private static func incomeIntent(in prompt: String) -> IncomeIntent? {
        let words = normalized(prompt).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let phrase = words.joined(separator: " ")
        let explicitProgress = containsAny(["progress", "progreso"], in: [words])
            && containsAny(["planned to actual", "planned versus actual", "planned vs actual",
                            "planned and actual", "planificado y real", "previsto y recibido"], in: [words])
        var remainder = phrase
        if explicitProgress {
            for comparison in ["planned versus actual", "planned vs actual"] {
                remainder = remainder.replacingOccurrences(of: comparison, with: "planned actual")
            }
        }
        guard !hasNegationOrComparison(remainder),
              !containsAny(["average", "mean", "median", "list", "transactions", "groups", "trend",
                            "promedio", "media", "lista", "transacciones", "grupos", "tendencia"], in: [words]) else { return nil }
        if explicitProgress { return .progress }
        let planned = containsAny(["planned", "expected", "planificado", "planificados", "previsto", "previstos"], in: [words])
        let spanish = containsAny(["ingreso", "ingresos", "mes", "periodo", "ano"], in: [words])
        let actual = containsAny(["received", "recibido", "recibidos", "real", "reales"], in: [words])
            || (!spanish && words.contains("actual"))
        guard planned != actual else { return nil }
        return planned ? .planned : .actual
    }

    private static func requiresExplicitIncomeProgressOperation(_ prompt: String) -> Bool {
        guard case .progress? = incomeIntent(in: prompt) else { return false }
        let normalized = normalized(prompt)
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let sentences = normalized.components(separatedBy: CharacterSet(charactersIn: ".;!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return sentences.count == 1 && financialTopic(in: prompt) == .income
            && normalized.rangeOfCharacter(from: CharacterSet(charactersIn: "\"“”‘’'")) == nil
            && supportedPeriods.filter { containsAny($0.1, in: [words]) }.count <= 1
            && !containsAny(["if", "would", "could", "might", "suppose", "imagine", "group", "groups", "grouped",
                             "by source", "by card", "by category", "by month", "by year", "by period", "per source", "per card",
                             "ranking", "trend", "average", "list", "transactions", "si", "seria", "podria", "por fuente", "por tarjeta",
                             "por categoria", "por mes", "por ano", "grupos", "tendencia", "promedio"], in: [words])
    }

    private static func isContextualFinancialFollowUp(_ prompt: String) -> Bool {
        let words = normalized(prompt).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty, !hasNegationOrComparison(prompt),
              containsAny(["and", "also", "what about", "how about", "that", "those", "same", "it", "them",
                           "y", "tambien", "ese", "esa", "esos", "esas", "mismo", "misma"], in: [words]) else { return false }
        let allowed: Set<String> = [
            "a", "an", "the", "and", "also", "what", "how", "much", "many", "was", "were", "is", "are", "did", "do", "does",
            "have", "has", "my", "me", "i", "show", "tell", "give", "please", "about", "for", "in", "during", "of", "to", "only",
            "that", "this", "these", "those", "same", "it", "them", "then", "now", "income", "planned", "actual", "received", "expected",
            "progress", "total", "totals", "amount", "amounts", "spending", "spent", "expenses", "purchases", "transactions",
            "month", "months", "period", "periods", "year", "date", "day", "days", "current", "last", "previous", "next", "selected", "seven", "7",
            "y", "tambien", "que", "como", "cuanto", "cuanta", "cuantos", "fue", "fueron", "es", "son", "mi", "mis", "me", "muestra",
            "mostrar", "dime", "por", "favor", "para", "en", "de", "del", "el", "la", "los", "las", "solo", "ese", "esa", "esos", "esas",
            "este", "esta", "mismo", "misma", "ahora", "ingreso", "ingresos", "planificado", "planificados", "previsto", "previstos",
            "recibido", "recibidos", "real", "reales", "progreso", "importe", "importes", "gasto", "gastos", "mes", "meses", "periodo",
            "periodos", "ano", "fecha", "dia", "dias", "pasado", "anterior", "proximo", "seleccionado", "siete"
        ]
        return words.allSatisfy(allowed.contains)
    }

    private static func permitsUnfilteredSelectionRepair(_ prompt: String) -> Bool {
        let normalized = normalized(prompt)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "?.!¿¡-"))
        guard normalized.unicodeScalars.allSatisfy(allowedCharacters.contains),
              !hasNegationOrComparison(prompt), !isContextualFinancialFollowUp(prompt),
              let topic = financialTopic(in: prompt), [.expenses, .income].contains(topic) else { return false }
        let sentences = normalized.components(separatedBy: CharacterSet(charactersIn: ".!?¿¡"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard sentences.count == 1 else { return false }
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard containsAny(["how much", "total", "totals", "amount", "cuanto", "cuanta", "importe"], in: [words]),
              !containsAny(["and", "also", "that", "those", "same", "it", "them", "another", "again", "then",
                            "y", "tambien", "ese", "esa", "esos", "esas", "mismo", "misma", "otra", "otro"], in: [words]) else { return false }

        // Remove only complete known period and universal-scope phrases. A targeting
        // preposition or an unrecognized name left over must keep the reference error latched.
        var remaining = " " + words.joined(separator: " ") + " "
        let universal = ["all cards", "all my cards", "all the cards", "all of my cards", "all of the cards",
                         "whole workspace", "the whole workspace", "my whole workspace", "entire workspace", "the entire workspace", "my entire workspace",
                         "todas mis tarjetas", "todas las tarjetas", "todas tarjetas", "todo el espacio de trabajo", "todo mi espacio de trabajo"]
        let periods = supportedPeriods.flatMap(\.1) + ["all time", "todo el tiempo"]
        let scopePhrases = universal.flatMap { phrase in
            [phrase] + ["across", "on", "for", "in", "en", "para"].map { $0 + " " + phrase }
        }
        let datePhrases = periods.flatMap { phrase in
            [phrase] + ["for", "in", "during", "en", "durante"].map { $0 + " " + phrase }
        }
        for phrase in (scopePhrases + datePhrases).sorted(by: { $0.count > $1.count }) {
            remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " ")
        }
        for phrase in ["total of", "amount of", "total de", "importe de"] {
            remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " total ")
        }
        let allowed: Set<String> = [
            "how", "much", "what", "is", "are", "was", "were", "have", "has", "had", "did", "do", "i", "my", "me", "the", "a", "an",
            "show", "tell", "give", "calculate", "please", "total", "totals", "amount", "spend", "spent", "spending", "expense", "expenses",
            "income", "incomes", "planned", "actual", "receive", "received", "expected", "only",
            "cuanto", "cuanta", "que", "cual", "es", "son", "fue", "he", "ha", "yo", "mi", "mis", "el", "la", "los", "las",
            "muestra", "muestrame", "dime", "calcula", "importe", "gasto", "gastos", "gaste", "gastado", "ingreso", "ingresos",
            "planificado", "planificados", "previsto", "previstos", "recibido", "recibidos", "real", "reales", "solo"
        ]
        return remaining.split(separator: " ").allSatisfy { allowed.contains(String($0)) }
    }

    private static func hasNegationOrComparison(_ prompt: String) -> Bool {
        let words = normalized(prompt).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return containsAny(["not", "no", "never", "without", "except", "excluding", "cannot", "sin", "excepto",
                            "rather than", "compare", "comparison", "compared", "versus", "vs", "against", "difference",
                            "comparar", "compara", "comparacion", "comparado", "diferencia", "frente a"], in: [words])
    }

    private static let supportedPeriods: [(MarinaDataRequest.RelativePeriod, [String])] = [
        (.currentMonth, ["this month", "current month", "este mes", "mes actual"]),
        (.previousMonth, ["last month", "previous month", "mes pasado", "mes anterior"]),
        (.yearToDate, ["year to date", "so far this year", "en lo que va de ano"]),
        (.nextSevenDays, ["next seven days", "next 7 days", "proximos siete dias", "proximos 7 dias"]),
        (.selectedPeriod, ["selected period", "periodo seleccionado"]),
        (.previousPeriod, ["previous period", "last period", "periodo anterior"])
    ]

    private static func requiresIncomeReceiptProgress(_ prompt: String) -> Bool {
        let normalized = normalized(prompt)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "?.!¿¡-"))
        guard normalized.unicodeScalars.allSatisfy(allowedCharacters.contains), !hasNegationOrComparison(prompt) else { return false }
        let sentences = normalized.components(separatedBy: CharacterSet(charactersIn: ".!?¿¡"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard sentences.count == 1 else { return false }
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let periods = supportedPeriods.filter { containsAny($0.1, in: [words]) }
        guard periods.count <= 1 else { return false }
        var remaining = " " + words.joined(separator: " ") + " "
        let periodPhrases = periods.flatMap(\.1).flatMap { phrase in
            [phrase] + ["for", "in", "during", "en", "durante"].map { $0 + " " + phrase }
        }
        for phrase in periodPhrases.sorted(by: { $0.count > $1.count }) {
            remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " ")
        }
        let phrasing = remaining.split(separator: " ").joined(separator: " ")
        let english = ["what percentage", "what percent", "what share", "what fraction"].flatMap { measure in
            [" of my planned income have i received", " of my expected income have i received",
             " of planned income has been received", " of my planned income did i receive"].map { measure + $0 }
        }
        let spanish = ["que porcentaje", "que proporcion", "que fraccion"].flatMap { measure in
            [" de mis ingresos previstos he recibido", " de mis ingresos planificados he recibido"].map { measure + $0 }
        }
        return (english + spanish).contains(phrasing)
    }

    private static func requiresBudgetPace(_ prompt: String) -> Bool {
        let normalized = normalized(prompt)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "?.!¿¡-"))
        guard normalized.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return false }
        let sentences = normalized.components(separatedBy: CharacterSet(charactersIn: ".!?¿¡"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard sentences.count == 1 else { return false }
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let periods = supportedPeriods.filter { containsAny($0.1, in: [words]) }
        guard periods.count <= 1 else { return false }
        var remaining = " " + words.joined(separator: " ") + " "
        let periodPhrases = periods.flatMap(\.1).flatMap { phrase in
            [phrase] + ["for", "in", "during", "en", "durante"].map { $0 + " " + phrase }
        }
        for phrase in periodPhrases.sorted(by: { $0.count > $1.count }) {
            remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " ")
        }
        let phrasing = remaining.split(separator: " ").joined(separator: " ")
        if [
            "am i on track with my budget", "am i on track with the budget", "is my budget on track", "is the budget on track",
            "how is my spending tracking against the plan", "how is my spending tracking against my plan",
            "how is spending tracking against the plan", "how is my spending tracking against the budget",
            "voy bien con mi presupuesto", "como van mis gastos respecto al plan"
        ].contains(phrasing) { return true }
        // Recognize the grammatical frame only. Existing named-target resolution still
        // decides which budget this literal name identifies, including missing/ambiguous names.
        let frames = [("am i on track with my ", " budget"), ("am i on track with the ", " budget"),
                      ("is my ", " budget on track"), ("is the ", " budget on track")]
        for (prefix, suffix) in frames where phrasing.hasPrefix(prefix) && phrasing.hasSuffix(suffix) {
            let name = String(phrasing.dropFirst(prefix.count).dropLast(suffix.count))
            let nameWords = name.split(separator: " ").map(String.init)
            guard (1...6).contains(nameWords.count) else { continue }
            if !containsAny(["and", "or", "but", "if", "would", "could", "not", "no", "except", "compare", "versus", "against",
                             "card", "cards", "category", "categories", "budget", "budgets", "income", "spending", "expenses",
                             "for", "from", "to", "with", "this", "last", "month", "year"], in: [nameWords]) { return true }
        }
        return false
    }

    private static func orderedComparisonPeriods(_ prompt: String) -> ComparisonPeriods? {
        guard requiresPeriodComparison(prompt) else { return nil }
        let normalized = normalized(prompt).replacingOccurrences(of: "['’]s\\b", with: "", options: .regularExpression)
        let allowedCharacters = CharacterSet.letters.union(.decimalDigits).union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "?.!¿¡-"))
        guard normalized.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var found: [(MarinaDataRequest.RelativePeriod, Int)] = []
        var remaining = " " + words.joined(separator: " ") + " "
        for (period, phrases) in supportedPeriods {
            let positions = phrases.compactMap { phrase -> Int? in
                let tokens = phrase.split(separator: " ").map(String.init)
                guard words.count >= tokens.count else { return nil }
                return (0...(words.count - tokens.count)).first { words[$0..<($0 + tokens.count)].elementsEqual(tokens) }
            }
            if let position = positions.min() { found.append((period, position)) }
            for phrase in phrases { remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " ") }
        }
        let remainder = remaining.split(separator: " ").map(String.init)
        let allowed: Set<String> = ["compare", "comparison", "versus", "vs", "with", "to", "against", "on", "in", "for", "the", "my", "that", "same",
                                    "spending", "spent", "expenses", "income", "actual", "planned", "received", "total", "totals", "card", "category", "source",
                                    "compara", "comparar", "comparacion", "con", "en", "de", "del", "la", "el", "mi", "misma", "mismo", "esa", "ese",
                                    "gasto", "gastos", "ingreso", "ingresos", "tarjeta", "categoria", "fuente"]
        guard found.count == 2, remainder.allSatisfy(allowed.contains),
              remainder.filter({ ["card", "category", "source", "tarjeta", "categoria", "fuente"].contains($0) }).count <= 1,
              !(containsAny(["income", "ingreso", "ingresos"], in: [remainder])
                && containsAny(["spending", "spent", "expenses", "gasto", "gastos"], in: [remainder])) else { return nil }
        found.sort { $0.1 < $1.1 }
        return ComparisonPeriods(primary: found[0].0, other: found[1].0)
    }

    private static func comparisonScopesMatch(_ request: MarinaDataRequest) -> Bool {
        guard request.accountID == nil, request.hypotheticalSpending == nil else { return false }
        let primary = MarinaDataRequest.Filter(cardID: request.cardID, categoryID: request.categoryID,
            categoryIDs: request.categoryIDs,
            budgetID: request.budgetID, presetID: request.presetID, search: request.search, merchantName: request.merchantName)
        func canonical(_ filter: MarinaDataRequest.Filter) -> MarinaDataRequest.Filter {
            var filter = filter
            let categories = Set((filter.categoryIDs ?? []) + [filter.categoryID].compactMap { $0 })
            filter.categoryID = nil
            filter.categoryIDs = categories.isEmpty ? nil : categories.sorted()
            return filter
        }
        return canonical(primary) == canonical(request.comparisonFilter ?? primary)
    }

    private static func requiresPeriodComparison(_ prompt: String) -> Bool {
        let words = normalized(prompt).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard containsAny(["compare", "comparison", "versus", "vs", "comparar", "compara", "comparacion"], in: [words]),
              !containsAny(["not", "no", "never", "without", "except", "excluding", "sin", "excepto", "and", "y",
                            "rank", "ranking", "largest", "smallest", "top", "groups", "grouped", "breakdown", "list", "transactions",
                            "cards", "categories", "merchants", "accounts", "rather than",
                            "progress", "progreso", "lista", "transacciones", "grupos", "mayor", "menor"], in: [words]) else { return false }
        let sentences = prompt.components(separatedBy: CharacterSet(charactersIn: ".;!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard sentences.count <= 1,
              normalized(prompt).range(of: "\\b\\d{1,4}[-/]\\d{1,2}", options: .regularExpression) == nil else { return false }
        let periods = supportedPeriods.filter { containsAny($0.1, in: [words]) }
        guard periods.count == 2, !words.contains(where: { $0.count == 4 && $0.allSatisfy(\.isNumber) }) else { return false }
        var remainder = " " + words.joined(separator: " ") + " "
        for phrase in periods.flatMap(\.1) { remainder = remainder.replacingOccurrences(of: " " + phrase + " ", with: " ") }
        let remainingWords = remainder.split(separator: " ").map(String.init)
        return !containsAny(["month", "months", "week", "weeks", "year", "years", "quarter", "yesterday", "today",
                             "mes", "meses", "semana", "semanas", "ano", "anos", "trimestre", "ayer", "hoy"], in: [remainingWords])
    }

    private static func financialTopic(in prompt: String) -> MarinaDataRequest.Tool? {
        let clauses = affirmativeClauses(in: prompt)
        let domains: [(MarinaDataRequest.Tool, [String])] = [
            (.expenses, ["spend", "spent", "spending", "expense", "expenses", "purchases", "gastos", "gaste", "gastado", "compras"]),
            (.income, ["income", "incomes", "ingreso", "ingresos"]),
            (.accounts, ["savings", "reconciliation", "ahorro", "ahorros", "conciliacion", "reconciliacion"]),
            (.budgetSummary, ["budget", "budgets", "presupuesto", "presupuestos"])
        ]
        let matches = domains.filter { containsAny($0.1, in: clauses) }.map(\.0)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func explicitFinancialTopic(in prompt: String) -> MarinaDataRequest.Tool? {
        guard !hasNegationOrComparison(prompt), containsAny([
            "how much", "how many", "what is", "what are", "what did", "show", "list", "calculate", "check", "tell me",
            "cuanto", "cuanta", "muestra", "muestrame", "cual es", "cuales son", "dime", "revisa"
        ], in: affirmativeClauses(in: prompt)) else { return nil }
        return financialTopic(in: prompt)
    }

    private static func periodCue(in prompt: String, clauses: [[String]]) -> PeriodCue {
        let normalized = normalized(prompt)
        let allWords = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let phrases = supportedPeriods
        let dateClauses = normalized.contains("-")
            ? affirmativeClauses(in: normalized.replacingOccurrences(of: "-", with: " ")) : clauses
        let candidates = phrases.filter { containsAny($0.1, in: dateClauses) }.map(\.0)
        let dateWords = ["today", "yesterday", "tomorrow", "month", "months", "week", "weeks", "quarter", "year", "years",
                         "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
                         "hoy", "ayer", "manana", "mes", "meses", "semana", "semanas", "trimestre", "ano", "anos",
                         "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
                         "all time", "todo el tiempo", "selected period", "previous period", "last period", "periodo seleccionado", "periodo anterior"]
        let numericDate = normalized.range(of: "\\b(?:19|20)\\d{2}\\b|\\b\\d{1,4}[-/]\\d{1,2}(?:[-/]\\d{1,4})?\\b|\\b\\d{1,2}(?:st|nd|rd|th)\\b", options: .regularExpression) != nil
        let hasDateWording = numericDate || containsAny(dateWords, in: [allWords])
            || containsAny(phrases.flatMap(\.1), in: [allWords])
        guard hasDateWording else { return .none }
        guard candidates.count == 1, !numericDate, !hasNegationOrComparison(prompt) else { return .other }
        // A supported cue plus another date expression must not silently hide that expression.
        var remaining = " " + allWords.joined(separator: " ") + " "
        for phrase in phrases.first(where: { $0.0 == candidates[0] })?.1 ?? [] {
            remaining = remaining.replacingOccurrences(of: " " + phrase + " ", with: " ")
        }
        let remainingWords = remaining.split(separator: " ").map(String.init)
        guard !containsAny(dateWords, in: [remainingWords]) else { return .other }
        return .relative(candidates[0])
    }

    private static func affirmativeClauses(in prompt: String) -> [[String]] {
        let normalized = normalized(prompt)
        let boundaries = CharacterSet.punctuationCharacters.union(.newlines)
        let negations: Set<String> = ["not", "no", "never", "without", "except", "excluding", "cannot", "sin", "excepto"]
        let contrasts: Set<String> = ["but", "instead", "pero", "sino"]
        return normalized.components(separatedBy: boundaries).flatMap { clause in
            let words = clause.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            var phrases: [[String]] = []
            var affirmative: [String] = []
            var negated = false
            for word in words {
                if contrasts.contains(word) {
                    if !affirmative.isEmpty { phrases.append(affirmative); affirmative = [] }
                    negated = false
                } else if negations.contains(word) {
                    if !affirmative.isEmpty { phrases.append(affirmative); affirmative = [] }
                    negated = true
                } else if !negated { affirmative.append(word) }
            }
            if !affirmative.isEmpty { phrases.append(affirmative) }
            return phrases
        }
    }
}
