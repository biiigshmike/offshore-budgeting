import Foundation

/// A compact total that expands into one or more related calculation breakdowns.
struct FinancialCalculationDisclosure: Identifiable {
    let id: String
    let sectionTitle: String
    let summary: FinancialCalculationRow
    let sections: [FinancialCalculationSection]
}

extension FinancialCalculationDisclosure {
    init?(section: FinancialCalculationSection) {
        guard let total = section.rows.first(where: \.isTotal) else { return nil }
        self.init(id: section.id, sectionTitle: section.title, summary: total, sections: [section])
    }
}
