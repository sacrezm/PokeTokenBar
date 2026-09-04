import AppKit
import Sparkle

/// Keep extraction, signature validation, replacement, rollback and relaunch inside
/// the maintained updater. Never run a downloaded shell script or modify save data.
@MainActor
final class SparkleInstaller {
    private let driver = OneClickUpdateDriver(hostBundle: .main, delegate: nil)
    private lazy var updater = SPUUpdater(
        hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil
    )

    func install() {
        NSApp.activate(ignoringOtherApps: true)
        do {
            try updater.start()
            guard updater.canCheckForUpdates else {
                driver.showUpdateInFocus()
                return
            }
            updater.checkForUpdates()
        } catch {
            driver.showUpdaterError(error, acknowledgement: {})
        }
    }
}

/// The app's Update & Restart click is the user's consent for the entire update.
/// Keep Sparkle's progress/cancel/error UI and security checks, but do not ask for
/// the same download/install consent again or fall back to opening a web page.
@MainActor
final class OneClickUpdateDriver: SPUStandardUserDriver {
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        dismissUpdateInstallation() // Close the initial checking window.
        guard !appcastItem.isInformationOnlyUpdate else {
            reply(.dismiss)
            showUpdaterError(NSError(domain: "PokeTokenBar.Update", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This release has no installable app update. Please try again later."
            ]), acknowledgement: {})
            return
        }
        reply(.install)
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
}
