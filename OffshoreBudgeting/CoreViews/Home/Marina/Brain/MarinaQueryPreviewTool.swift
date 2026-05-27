import Foundation

protocol MarinaQueryPreviewTooling: Sendable {
    var descriptor: MarinaQueryPreviewToolDescriptor { get }
}

struct MarinaQueryPreviewToolDescriptor: Equatable, Sendable {
    let name: String
    let description: String
    let isEnabled: Bool

    static let reservedReadOnlyPreview = MarinaQueryPreviewToolDescriptor(
        name: "marina_query_preview",
        description: "Reserved read-only query preview tool for future Foundation Models tool calling.",
        isEnabled: false
    )
}
