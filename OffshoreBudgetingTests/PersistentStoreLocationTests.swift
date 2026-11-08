import XCTest
@testable import Offshore

final class PersistentStoreLocationTests: XCTestCase {
    func testReleasePreservesEveryExistingStorePath() {
        let root = URL(fileURLWithPath: "/Application Support", isDirectory: true)
        for name in ["Local.store", "Cloud.store", "FallbackLocal.store"] {
            XCTAssertEqual(
                PersistentStoreLocation.directory(in: root, isDevelopment: false).appendingPathComponent(name),
                root.appendingPathComponent(name)
            )
        }
    }

    func testDevelopmentIsolatesNormalFallbackAndOverrideStores() {
        let root = URL(fileURLWithPath: "/Application Support", isDirectory: true)
        for name in ["Local.store", "Cloud.store", "FallbackLocal.store", "Personal.store", "UITestCloud.store"] {
            let directory = PersistentStoreLocation.directory(in: root, isDevelopment: true)
            XCTAssertEqual(directory.path, root.appendingPathComponent("Development").path)
            XCTAssertNotEqual(directory.appendingPathComponent(name), root.appendingPathComponent(name))
        }
    }

    func testDefaultMatchesCompiledBuildConfiguration() {
        let root = URL(fileURLWithPath: "/Application Support", isDirectory: true)
        #if DEBUG
        XCTAssertEqual(PersistentStoreLocation.directory(in: root).lastPathComponent, "Development")
        #else
        XCTAssertEqual(PersistentStoreLocation.directory(in: root), root)
        #endif
    }

    func testSelectingDevelopmentDirectoryLeavesExistingFilesUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["Local.store", "Cloud.store", "Cloud.store-wal", "Cloud.store-shm", "FallbackLocal.store"]
        let original = Data("existing store contents".utf8)
        for name in names {
            try original.write(to: root.appendingPathComponent(name))
        }

        let development = PersistentStoreLocation.directory(in: root, isDevelopment: true)
        try FileManager.default.createDirectory(at: development, withIntermediateDirectories: true)
        try Data("development contents".utf8).write(to: development.appendingPathComponent("Cloud.store"))

        for name in names {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), original)
        }
    }
}
