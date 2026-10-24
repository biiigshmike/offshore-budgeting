import Foundation

/// Decides only whether a reply needs current workspace evidence. It never chooses a tool,
/// entity, operation, amount, or date range, and conversation memory is not evidence.
nonisolated enum MarinaGroundingPolicy {
    /// Identity and boundary explanations use the workspace already supplied in instructions.
    /// Additional names or financial questions keep the normal tool path.
    static func isWorkspaceMetadataQuestion(_ prompt: String) -> Bool {
        let words = prompt.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let allowed: Set<String> = ["which", "what", "workspace", "am", "i", "in", "using", "we", "are", "now",
            "and", "the", "current", "explain", "briefly", "how", "boundaries", "affect", "my", "records"]
        return words.contains("workspace") && (words.contains("which") || words.contains("what"))
            && Set(words).isSubset(of: allowed)
    }

    static func requiresRead(prompt: String, hasFinancialContext: Bool, hasPendingClarification: Bool) -> Bool {
        let text = prompt.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        let tokens = Set(words)
        let normalized = words.joined(separator: " ")
        func contains(_ phrases: [String]) -> Bool {
            phrases.contains { (" " + normalized + " ").contains(" " + $0 + " ") }
        }
        let financial: Set<String> = ["spend", "spent", "spending", "expense", "expenses", "income", "incomes",
            "balance", "balances", "purchase", "purchases", "transaction", "transactions", "budget", "budgets",
            "savings", "reconciliation", "allocation", "ledger", "payment", "payments", "paid", "received", "earned",
            "owe", "owed", "gasto", "gastos", "gaste", "gastado", "ingreso", "ingresos", "saldo", "saldos",
            "compra", "compras", "transaccion", "transacciones", "presupuesto", "presupuestos", "ahorro", "ahorros",
            "conciliacion", "reconciliacion", "pago", "pagos", "pague", "recibi", "recibido", "debo"]
        let personal: Set<String> = ["my", "mine", "our", "ours", "mi", "mis", "mio", "mia", "nuestro", "nuestra", "nuestros", "nuestras"]
        let time: Set<String> = ["today", "yesterday", "week", "weeks", "month", "months", "year", "years", "daily", "monthly",
            "current", "recent", "period", "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december", "hoy", "ayer", "semana", "semanas", "mes", "meses",
            "ano", "anos", "periodo", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
            "septiembre", "octubre", "noviembre", "diciembre"]
        let hasPersonal = !tokens.isDisjoint(with: personal)
        let hasTime = !tokens.isDisjoint(with: time) || words.contains { $0.count == 4 && $0.allSatisfy(\.isNumber) }
        let hasFinance = !tokens.isDisjoint(with: financial)
        let asksForData = contains(["how much", "how many", "cuanto", "cuanta", "cuantos", "cuantas", "am i on track",
            "on track with", "what did i", "what have i", "what do i", "what i spent", "que gaste", "cuanto he",
            "show", "list", "which", "largest", "biggest", "smallest", "compare", "calculate", "check", "summarize", "total", "totals", "breakdown",
            "muestra", "muestrame", "lista", "compara", "calcula", "revisa", "resume", "desglose"])
        let explanatory = contains(["define", "definition", "meaning", "what is a", "what is an", "what does",
            "how does", "how do i", "how to", "explain", "que es", "que son", "definicion", "significa",
            "como funciona", "como funcionan", "como puedo", "como crear", "explica"])
            || contains(["what is income", "what is savings", "what is reconciliation", "what is budgeting"])
        if explanatory && !hasPersonal && !hasTime { return false }
        // Creating a record is handled by the app's forms, not by the read-only financial tools.
        if let first = words.first, ["add", "create", "record", "delete", "agrega", "anade", "crea", "registra", "elimina"].contains(first),
           !contains(["show", "list", "compare", "calculate", "check", "how much", "muestra", "cuanto"]) { return false }
        // Upcoming occurrences are financial data even when an earlier turn only found names.
        // A plain preset inventory still takes the ordinary lookup path below.
        let presetKinds: Set<String> = ["preset", "presets", "preajuste", "preajustes", "plantilla", "plantillas"]
        if !tokens.isDisjoint(with: presetKinds),
           contains(["due", "due soon", "upcoming", "scheduled", "vence", "vencen", "proximos", "proximas", "programados", "programadas"]) {
            return true
        }
        let inventoryKinds: Set<String> = ["cards", "categories", "budgets", "presets", "accounts", "tarjetas", "categorias", "presupuestos", "cuentas"]
        let financialMeasures: Set<String> = ["amount", "amounts", "total", "totals", "balance", "balances", "spend", "spent", "spending",
            "income", "received", "planned", "actual", "pace", "progress", "transactions", "purchases", "remaining",
            "saldo", "saldos", "importe", "importes", "gasto", "gastos", "ingresos", "transacciones", "compras", "ritmo", "progreso"]
        if contains(["show", "list", "names", "muestra", "lista", "nombres"]),
           !tokens.isDisjoint(with: inventoryKinds), tokens.isDisjoint(with: financialMeasures) { return false }
        if hasFinance && (hasPersonal || hasTime || asksForData) { return true }
        if contains(["what is the balance", "what are the balances", "spending total", "income total", "budget pace",
                     "saldo actual", "total de gastos", "total de ingresos", "ritmo del presupuesto"]) { return true }
        if hasPendingClarification && contains(["i mean", "me refiero", "the merchant", "el comercio", "the card", "la tarjeta",
                                               "the category", "la categoria", "the budget", "el presupuesto", "the account", "la cuenta"]) { return true }
        guard hasFinancialContext || hasPendingClarification else { return false }
        if !hasFinance && contains(["workspace", "workspaces", "date range", "currency", "espacio de trabajo", "moneda"]) { return false }
        if contains(["how much", "how many", "cuanto", "cuanta", "cuantos", "cuantas"]) { return true }
        // Deictic follow-ups refer to a previous financial target or period, not a remembered amount.
        if contains(["what about", "how about", "and last", "and this", "same card", "that card", "same account", "that account",
                     "that month", "same month", "that period", "behind that total", "those purchases", "those transactions",
                     "y el mes", "y este mes", "esa tarjeta", "misma tarjeta", "esa cuenta", "misma cuenta", "ese mes", "ese periodo"]) { return true }
        if asksForData && contains(["again", "now", "updated", "latest", "more", "biggest", "largest", "smallest",
                                   "otra vez", "ahora", "actualizado", "mas grande", "mayor", "menor"]) { return true }
        return false
    }
}
