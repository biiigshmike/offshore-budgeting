import SwiftData
import XCTest
@testable import Offshore

#if DEBUG
final class DebugScreenshotModeTests: XCTestCase {
    func testModeIsSelectedByBuildConfigurationWithoutLaunchArguments() {
        #if OFFSHORE_SCREENSHOTS
        XCTAssertTrue(DebugScreenshotMode.isCompiledBuild)
        XCTAssertTrue(DebugScreenshotMode.isEnabled)
        XCTAssertEqual(OffshoreAppIdentity.appGroupIdentifier, "group.com.mb.offshore-budgeting.screenshots")
        XCTAssertEqual(OffshoreAppIdentity.urlScheme, "offshore-screenshots")
        #else
        XCTAssertFalse(DebugScreenshotMode.isCompiledBuild)
        XCTAssertFalse(DebugScreenshotMode.isEnabled)
        XCTAssertEqual(OffshoreAppIdentity.appGroupIdentifier, "group.com.mb.offshore-budgeting")
        XCTAssertEqual(OffshoreAppIdentity.urlScheme, "offshore")
        #endif
    }

    func testScreenshotStoreIsDedicatedDevelopmentStore() {
        XCTAssertEqual(DebugScreenshotMode.storeURL.lastPathComponent, "Screenshots.store")
        XCTAssertEqual(DebugScreenshotMode.storeURL.deletingLastPathComponent().lastPathComponent, "Development")
        let configuration = ModelConfiguration(
            DebugScreenshotMode.storeName,
            url: DebugScreenshotMode.storeURL,
            cloudKitDatabase: .none
        )
        XCTAssertTrue(DebugScreenshotMode.owns(configuration))
    }

    func testNormalAndLegacyStoresCannotBeSeedResetTargets() {
        let directory = DebugScreenshotMode.storeURL.deletingLastPathComponent()
        for name in ["Local", "Cloud", "FallbackLocal", "Personal"] {
            let configuration = ModelConfiguration(name, url: directory.appendingPathComponent("\(name).store"), cloudKitDatabase: .none)
            XCTAssertFalse(DebugScreenshotMode.owns(configuration), name)
        }
    }

    func testScreenshotNameAloneDoesNotAuthorizeResetOfAnotherStore() {
        let configuration = ModelConfiguration(
            DebugScreenshotMode.storeName,
            url: DebugScreenshotMode.storeURL.deletingLastPathComponent().appendingPathComponent("Local.store"),
            cloudKitDatabase: .none
        )
        XCTAssertFalse(DebugScreenshotMode.owns(configuration))
    }

    func testCloudBackedConfigurationCannotBeSeedResetTarget() {
        let configuration = ModelConfiguration(
            DebugScreenshotMode.storeName,
            url: DebugScreenshotMode.storeURL,
            cloudKitDatabase: .private("iCloud.com.mb.offshore-budgeting")
        )
        XCTAssertFalse(DebugScreenshotMode.owns(configuration))
    }

    func testInMemoryContainersCannotBeSeedResetTargets() {
        let configuration = ModelConfiguration(DebugScreenshotMode.storeName, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        XCTAssertFalse(DebugScreenshotMode.owns(configuration))
    }
}
#endif
