import XCTest

final class GameplayPreviewPackagingTests: XCTestCase {
    func testPreviewPackagesTheCurrentExecutableName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/preview-gameplay.sh"),
                                encoding: .utf8)
        let appSource = try String(contentsOf: root.appendingPathComponent("Sources/PokeTokenBar/PokeTokenBarApp.swift"),
                                   encoding: .utf8)
        let plistData = try Data(contentsOf: root.appendingPathComponent("scripts/gameplay-preview/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])

        XCTAssertTrue(script.contains("PTB_BIN_NAME=PokeForge"))
        XCTAssertTrue(script.contains("$PTB_BIN_DIR/$PTB_BIN_NAME"))
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "PokeForge")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "local.pokeforge.gameplay-preview")
        XCTAssertTrue(appSource.contains("Bundle.main.bundleIdentifier == \"local.pokeforge.gameplay-preview\""))
        XCTAssertFalse(appSource.contains("local.poketokenbar.progression-preview"))
    }
}
