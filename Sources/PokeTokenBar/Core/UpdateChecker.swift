import AppKit
import Observation

/// GitHub discovery drives the persistent in-app banner; Sparkle owns installation.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable { let version: String; let url: String }

    private(set) var available: Available?

    let currentVersion: String
    nonisolated static let repository = "sacrezm/PokeTokenBar"
    private let clock: () -> Date
    private let session: URLSession
    private let defaults: UserDefaults
    private let installUpdate: (() -> Void)?
    @ObservationIgnored private var installer: SparkleInstaller?
    @ObservationIgnored private var automaticTask: Task<Void, Never>?
    private(set) var checkFailed = false
    private(set) var noPublishedRelease = false
    private let skippedKey = "tradingFork.skippedUpdateVersion"
    private var lastChecked: Date?
    private var isChecking = false

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init,
         session: URLSession = .shared, defaults: UserDefaults = .standard,
         installUpdate: (() -> Void)? = nil) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.session = session
        self.defaults = defaults
        self.installUpdate = installUpdate
    }

    /// App-owned, so closing the popover does not stop discovery. No silent installs.
    func startAutomaticChecks(interval: TimeInterval = 3600) {
        guard automaticTask == nil, interval.isFinite, interval > 0 else { return }
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.check(minInterval: interval)
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
            }
        }
    }

    func stopAutomaticChecks() {
        automaticTask?.cancel()
        automaticTask = nil
    }

    /// 최신 릴리스 조회 → 새 버전이고 사용자가 그 버전을 'skip' 하지 않았으면 available 설정.
    /// minInterval 보다 자주 호출되면 무시(레이트리밋 보호).
    func check(minInterval: TimeInterval = 1800) async {
        guard !isChecking else { return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        lastChecked = clock()
        isChecking = true
        defer { isChecking = false }
        checkFailed = false
        noPublishedRelease = false
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PokeTokenBar-Trading", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req) else { checkFailed = true; return }
        if (resp as? HTTPURLResponse)?.statusCode == 404 {
            available = nil
            noPublishedRelease = true
            return
        }
        guard
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool == false, json["prerelease"] as? Bool == false,
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              // Only accept release metadata belonging to this fork.
              let htmlURL = URL(string: html),
              htmlURL.absoluteString == "https://github.com/\(Self.repository)/releases/tag/\(tag)"
        else { checkFailed = true; return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = latest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({
            !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil
        }) else { checkFailed = true; return }
        let skipped = defaults.string(forKey: skippedKey)
        if Self.isNewer(latest, than: currentVersion), minInterval == 0 || latest != skipped {
            available = Available(version: latest, url: html)
        } else {
            available = nil
        }
    }

    /// 이 버전은 다시 알리지 않음.
    func skipCurrent() {
        if let v = available?.version { defaults.set(v, forKey: skippedKey) }
        available = nil
    }

    /// Download, signature verification, installation and relaunch use Sparkle's native UI.
    func applyUpdate() {
        guard available != nil else { return }
        if let installUpdate { installUpdate(); return }
        if installer == nil { installer = SparkleInstaller() }
        installer?.install()
    }

    // MARK: 버전 비교

    /// a 가 b 보다 높은 semver 인가. ("2.0.10" > "2.0.9" 등 숫자 비교)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

}
