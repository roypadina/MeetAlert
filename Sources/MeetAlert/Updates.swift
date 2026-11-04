import AppKit
import Sparkle

/// Sparkle updater: feed URL + public key come from Info.plist.
@MainActor enum Updates {
    static let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: presenter)
    static func check() { controller.checkForUpdates(nil) }
    private static let presenter = Presenter()

    /// A menu-bar-only app's scheduled update alert opens behind other windows, with no Dock icon to
    /// find it by: Dock icon + front while the alert is up, then back to accessory.
    private final class Presenter: NSObject, SPUStandardUserDriverDelegate {
        var supportsGentleScheduledUpdateReminders: Bool { true }

        // Sparkle calls these on the main thread; its header just doesn't say so to Swift.
        func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            }
        }

        func standardUserDriverWillFinishUpdateSession() {
            DispatchQueue.main.async {  // after Sparkle's window has closed
                if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
