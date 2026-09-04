import AppKit
import Sparkle

/// Keep extraction, signature validation, replacement, rollback and relaunch inside
/// the maintained updater. Never run a downloaded shell script or modify save data.
@MainActor
final class SparkleInstaller {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    func install() {
        NSApp.activate(ignoringOtherApps: true)
        guard controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
