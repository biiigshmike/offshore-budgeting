import Foundation

struct SupportFeedbackDraft: Identifiable {
    enum Kind {
        case feedback
        case problem

        var title: String {
            switch self {
            case .feedback: String(localized: "Send Feedback")
            case .problem: String(localized: "Report a Problem")
            }
        }

        var subject: String {
            switch self {
            case .feedback: String(localized: "Offshore Feedback")
            case .problem: String(localized: "Offshore Problem Report")
            }
        }

        var prompt: String {
            switch self {
            case .feedback:
                String(localized: "What did you like, or what could be clearer?")
            case .problem:
                String(localized: "What happened?\n\nWhat did you expect?\n\nWhat steps led to the problem?")
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let recipient: String?
    let subject: String
    let body: String

    init(kind: Kind, bundle: Bundle = .main) {
        self.kind = kind
        recipient = SupportFeedbackConfiguration.emailAddress
        subject = kind.subject

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        body = """
        \(kind.prompt)


        —
        \(String(localized: "App Version")): \(version) (\(build))
        \(String(localized: "Operating System")): \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }

    var mailURL: URL? {
        guard let recipient else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
