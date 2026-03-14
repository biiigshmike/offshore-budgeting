import XCTest
@testable import OffshoreBudgeting

final class ICloudBootstrapTests: XCTestCase {

    func testWorkspaceDiscoveryPhase_localEmptyIsLoadedEmpty() {
        let phase = ICloudBootstrap.workspaceDiscoveryPhase(
            useICloud: false,
            startedAt: 0,
            workspaceCount: 0,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(phase, .loaded(hasWorkspaces: false))
    }

    func testWorkspaceDiscoveryPhase_iCloudEmptyUnderThresholdIsLoading() {
        let phase = ICloudBootstrap.workspaceDiscoveryPhase(
            useICloud: true,
            startedAt: 100,
            workspaceCount: 0,
            now: Date(timeIntervalSince1970: 103)
        )

        XCTAssertEqual(phase, .loading)
    }

    func testWorkspaceDiscoveryPhase_iCloudEmptyOverThresholdIsSlowLoading() {
        let phase = ICloudBootstrap.workspaceDiscoveryPhase(
            useICloud: true,
            startedAt: 100,
            workspaceCount: 0,
            now: Date(timeIntervalSince1970: 108)
        )

        XCTAssertEqual(phase, .loadingSlow)
    }

    func testWorkspaceDiscoveryPhase_withWorkspacesIsLoadedWithData() {
        let phase = ICloudBootstrap.workspaceDiscoveryPhase(
            useICloud: true,
            startedAt: 100,
            workspaceCount: 2,
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertEqual(phase, .loaded(hasWorkspaces: true))
    }
}
