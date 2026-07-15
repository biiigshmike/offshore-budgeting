import CryptoKit
import Foundation

@testable import Offshore

/// Exact, value-sensitive signatures for physical-device evaluation. Reports
/// receive only the SHA-256 output; the framed answer and evidence values never
/// leave the test process.
enum MarinaFoundationModelDeviceSignature {
  static func answer(_ answer: HomeAnswer) -> String {
    var components = [
      answer.kind.rawValue,
      answer.title,
      answer.subtitle ?? "nil",
      answer.primaryValue ?? "nil",
      String(answer.rows.count),
    ]
    for row in answer.rows {
      components += [
        row.title,
        row.value,
        row.amount?.description ?? "nil",
        row.date?.timeIntervalSinceReferenceDate.description ?? "nil",
        row.role.rawValue,
        row.objectType?.rawValue ?? "nil",
      ]
    }
    return hash(components)
  }

  static func evidence(_ summaries: [String]) -> String {
    hash(summaries)
  }

  private static func hash(_ components: [String]) -> String {
    let framed = components.map { component in
      "\(component.utf8.count):\(component)"
    }.joined(separator: "|")
    let digest = SHA256.hash(data: Data(framed.utf8))
    return "sha256:\(Data(digest).base64EncodedString())"
  }
}
