import Foundation

enum SupportFeedbackConfiguration {
    static var emailAddress: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OffshoreSupportEmail") as? String else {
            return nil
        }
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    static let reviewURL = URL(string: "https://apps.apple.com/app/id6754517095?action=write-review")!
    static let developerWebsiteURL = URL(string: "https://offshore-budgeting.notion.site/Offshore-Budgeting-295b42cd2e6c80cf817dd73a5761bb7e")!
}
