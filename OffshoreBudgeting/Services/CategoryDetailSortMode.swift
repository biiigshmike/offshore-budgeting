import Foundation

enum CategoryDetailSortMode: String, CaseIterable, Identifiable {
    case az
    case za
    case amountAsc
    case amountDesc
    case dateAsc
    case dateDesc

    var id: String { rawValue }
}
