import AppKit
import Sparkle

/// Update checks, through Sparkle (MIT licensed, bundled in Contents/Frameworks).
///
/// The app promises not to use the network, so updates are off until the user
/// ticks a box in Settings › Updates. Info.plist sets SUEnableAutomaticChecks
/// to false, which stops Sparkle from checking on its own and from asking on
/// second launch whether it may. With both boxes unticked nothing connects;
/// "Check for Updates Now…" connects once, when clicked.
///
/// The feed is appcast.xml on the latest GitHub release (scripts/release.sh).
@MainActor
final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {   // Sparkle calls it on the main thread
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!
    private var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        keepUpdateWindowsAbovePinnedPanel()
    }

    /// "Use the internet to tell me about new updates": a check about once a day.
    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            updater.automaticallyChecksForUpdates = newValue
            if !newValue { updater.automaticallyDownloadsUpdates = false }
        }
    }

    /// "…download and install updates automatically": installed on the next quit.
    /// Needs the daily check, so turning it on turns that on too.
    var downloadsAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates }
        set {
            if newValue { updater.automaticallyChecksForUpdates = true }
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var canCheck: Bool { updater.canCheckForUpdates }

    func checkNow() {
        NSApp.activate()   // a menu bar app isn't frontmost, so Sparkle's window would open behind
        controller.checkForUpdates(nil)
    }

    /// "Version 1.1 (42)"
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// A menu bar app has no Dock icon to badge, so a scheduled check that finds an
    /// update would otherwise open its window quietly behind other apps.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate && !state.userInitiated { NSApp.activate() }
    }

    /// A pinned detached window floats above normal windows, as Sparkle's are;
    /// lift each of Sparkle's windows above it as it opens, like showAbout() does.
    private func keepUpdateWindowsAbovePinnedPanel() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard DetachedWindow.shared.isPinned, let window = note.object as? NSWindow,
                      window.level == .normal,
                      let owner = window.windowController.map({ NSStringFromClass(type(of: $0)) }),
                      owner.hasPrefix("SU") || owner.hasPrefix("SPU")
                else { return }
                window.level = .modalPanel
            }
        }
    }
}
