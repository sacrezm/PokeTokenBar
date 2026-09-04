import XCTest
import Observation
@testable import PokeTokenBar

@MainActor
final class ForkUpdateTests: XCTestCase {
    private func fixture() -> (UpdateChecker, UserDefaults, String) {
        let name = "ForkUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForkReleaseProtocol.self]
        let checker = UpdateChecker(currentVersion: "2.5.3", session: URLSession(configuration: config),
                                    defaults: defaults)
        return (checker, defaults, name)
    }

    private func release(tag: String = "v2.6.0", repository: String = "sacrezm/PokeTokenBar",
                         prerelease: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": "https://github.com/\(repository)/releases/tag/\(tag)",
            "draft": false, "prerelease": prerelease,
        ])
    }

    func testChecksForkWithoutCredentialsAndFindsNewRelease() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        let data = release()
        ForkReleaseProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://api.github.com/repos/sacrezm/PokeTokenBar/releases/latest")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, data)
        }
        await checker.check()
        XCTAssertEqual(checker.available?.version, "2.6.0")
        XCTAssertFalse(checker.checkFailed)
    }

    func testSkipPersistsButManualCheckCanFindSkippedRelease() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        let data = release()
        ForkReleaseProtocol.handler = { _ in (200, data) }
        await checker.check()
        checker.skipCurrent()
        XCTAssertNil(checker.available)
        XCTAssertEqual(defaults.string(forKey: "tradingFork.skippedUpdateVersion"), "2.6.0")
        await checker.check(minInterval: -1)
        XCTAssertNil(checker.available)
        await checker.check(minInterval: 0)
        XCTAssertEqual(checker.available?.version, "2.6.0")
    }

    func testRejectsUpstreamPrereleaseAndInvalidVersion() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        for data in [release(repository: "chattymin/PokeTokenBar"),
                     release(prerelease: true), release(tag: "v99.0.0-beta"), release(tag: "v99..0")] {
            ForkReleaseProtocol.handler = { _ in (200, data) }
            await checker.check(minInterval: 0)
            XCTAssertNil(checker.available)
            XCTAssertTrue(checker.checkFailed)
        }
    }

    func testNoReleaseAndNetworkFailureAreNotReportedAsUpToDate() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        ForkReleaseProtocol.handler = { _ in (404, Data()) }
        await checker.check()
        XCTAssertTrue(checker.noPublishedRelease)
        ForkReleaseProtocol.handler = { _ in (403, Data()) }
        await checker.check(minInterval: 0)
        XCTAssertTrue(checker.checkFailed)
        XCTAssertFalse(checker.noPublishedRelease)
    }

    func testEqualOrOlderReleaseDoesNotNotify() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        for version in ["v2.5.3", "v2.5.2"] {
            let data = release(tag: version)
            ForkReleaseProtocol.handler = { _ in (200, data) }
            await checker.check(minInterval: 0)
            XCTAssertNil(checker.available)
            XCTAssertFalse(checker.checkFailed)
        }
    }

    func testAutomaticChecksAreThrottled() async {
        let (checker, defaults, name) = fixture()
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        let data = release()
        ForkReleaseProtocol.handler = { _ in (200, data) }
        await checker.check()
        ForkReleaseProtocol.handler = { _ in XCTFail("Repeated automatic check should be throttled"); return (500, Data()) }
        await checker.check()
    }

    func testUpdateUsesInAppInstallerOnlyWhenReleaseIsAvailable() async {
        let name = "ForkUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForkReleaseProtocol.self]
        var installs = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", session: URLSession(configuration: config),
                                    defaults: defaults, installUpdate: { installs += 1 })
        checker.applyUpdate()
        XCTAssertEqual(installs, 0)
        let data = release()
        ForkReleaseProtocol.handler = { _ in (200, data) }
        await checker.check()
        checker.applyUpdate()
        XCTAssertEqual(installs, 1)
    }

    func testPeriodicDiscoveryFindsLaterReleaseWithoutPopoverOrAutomaticInstall() async {
        let name = "ForkUpdateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); ForkReleaseProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ForkReleaseProtocol.self]
        var installs = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", session: URLSession(configuration: config),
                                    defaults: defaults, installUpdate: { installs += 1 })
        let first = release(tag: "v2.5.3")
        let second = release()
        let counter = RequestCounter()
        ForkReleaseProtocol.handler = { _ in (200, counter.next() == 1 ? first : second) }
        let discovered = expectation(description: "A later periodic check publishes the new version")
        withObservationTracking { _ = checker.available } onChange: { discovered.fulfill() }
        checker.startAutomaticChecks(interval: 0.02)
        checker.startAutomaticChecks(interval: 0.02) // Must not start a second polling loop.
        await fulfillment(of: [discovered], timeout: 2)
        checker.stopAutomaticChecks()
        XCTAssertEqual(checker.available?.version, "2.6.0")
        XCTAssertEqual(installs, 0, "Discovery must never quit the app or install silently")
        XCTAssertGreaterThanOrEqual(counter.value, 2)
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

private final class ForkReleaseProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (status, data) = Self.handler?(request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
