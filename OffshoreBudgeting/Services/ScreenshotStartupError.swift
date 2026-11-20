import Foundation

#if DEBUG
enum ScreenshotStartupError: LocalizedError {
    case invalidStore
    case missingSampleData
    case unavailable(String)
    case injectedFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidStore:
            "Screenshot Mode refused a container outside its isolated Screenshots.store."
        case .missingSampleData:
            "Screenshot data is incomplete. Retry, or enable -resetSeed in the Screenshots scheme to rebuild the demo data."
        case .unavailable(let message):
            message
        case .injectedFailure(let stage):
            "Injected screenshot setup failure: \(stage)."
        }
    }
}
#endif
