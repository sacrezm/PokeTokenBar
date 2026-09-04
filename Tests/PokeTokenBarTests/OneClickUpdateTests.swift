import XCTest
import Sparkle
@testable import PokeTokenBar

@MainActor
final class OneClickUpdateTests: XCTestCase {
    func testProductionAndSmokeBundlesVerifyArchivesBeforeExtraction() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["scripts/build-app.sh", "scripts/updater-smoke/Info.plist"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let start = try XCTUnwrap(source.range(of: "<?xml"))
            let end = try XCTUnwrap(source.range(of: "</plist>", range: start.lowerBound..<source.endIndex))
            let xml = String(source[start.lowerBound..<end.upperBound])
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
                from: Data(xml.utf8), format: nil) as? [String: Any])
            XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true, path)
            XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true, path)
            XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, false, path)
            XCTAssertEqual(plist["SUAutomaticallyUpdate"] as? Bool, false, path)
        }
    }

    func testReadyUpdateContinuesToInstallAndRelaunchWithoutAnotherClick() {
        let driver = OneClickUpdateDriver(hostBundle: .main, delegate: nil)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertEqual(choices, [.install])
    }
}
