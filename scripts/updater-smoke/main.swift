import AppKit

/// A disposable app with no Pokémon, usage or trading code. It runs the production
/// installer, then the replacement binary proves that Sparkle relaunched it.
@MainActor
final class SmokeDelegate: NSObject, NSApplicationDelegate {
    let installer = SparkleInstaller()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2.0.0" {
            let path = Bundle.main.object(forInfoDictionaryKey: "PTBSmokeResultPath") as! String
            try! Data("installed-and-relaunched\n".utf8).write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        } else {
            installer.install()
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = SmokeDelegate()
    application.delegate = delegate
    application.run()
}
