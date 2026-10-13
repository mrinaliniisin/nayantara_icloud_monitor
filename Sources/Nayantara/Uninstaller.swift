import AppKit
import ServiceManagement

/// Settings › Uninstall Nayantara…: turns off Launch at login, deletes the app's
/// settings and caches, moves the app to the Trash and quits.
///
/// A menu bar app has no window to drag to the Trash, and people who download a
/// release never see the README's manual steps, so the app removes itself.
@MainActor
enum Uninstaller {
    static func confirmAndUninstall() {
        // The menu bar popover floats above normal windows and would cover the alert.
        StatusItemController.shared.closePopover()
        NSApp.activate()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Nayantara?"
        alert.informativeText = """
            Nayantara will turn off Launch at login, delete its settings and caches, \
            move itself to the Trash and quit.

            Your iCloud Drive files aren't touched.
            """
        alert.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        // Excluded folders would otherwise stay out of iCloud with nothing left to say why.
        let noSync = NoSync.shared
        let excluded = noSync.rules.count + noSync.foundElsewhere.count
        if excluded > 0 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = excluded == 1
                ? "Resume syncing the 1 item that isn't syncing" : "Resume syncing the \(excluded) items that aren't syncing"
            alert.suppressionButton?.state = .on
        }
        // A pinned detached window floats above normal windows; keep the alert above it.
        if DetachedWindow.shared.isPinned { alert.window.level = .modalPanel }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if excluded > 0, alert.suppressionButton?.state == .on { noSync.resumeAll() }
        uninstall()
    }

    private static func uninstall() {
        let fm = FileManager.default
        let id = Bundle.main.bundleIdentifier ?? "local.sindhus.Nayantara"
        let library = fm.homeDirectoryForCurrentUser.appending(path: "Library")

        if SMAppService.mainApp.status != .notRegistered { try? SMAppService.mainApp.unregister() }

        // Caches, Sparkle's network storage and window state. Missing ones are fine.
        for path in ["Caches/\(id)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies",
                     "Saved Application State/\(id).savedState"] {
            try? fm.removeItem(at: library.appending(path: path))
        }

        // To the Trash rather than deleted, so it can be put back. Skipped when not
        // running from an app bundle (`swift run` during development).
        let app = Bundle.main.bundleURL
        var trashError: Error?
        if app.pathExtension == "app" {
            do { try fm.trashItem(at: app, resultingItemURL: nil) } catch { trashError = error }
        }

        // Through cfprefsd, not by deleting the plist: it holds the settings in
        // memory and would write a deleted file straight back. It still leaves an
        // empty plist, as `defaults delete` does.
        UserDefaults.standard.removePersistentDomain(forName: id)
        CFPreferencesAppSynchronize(id as CFString)

        if let trashError {
            let alert = NSAlert()
            alert.messageText = "Nayantara couldn't move itself to the Trash"
            alert.informativeText = """
                Its settings and caches are gone, and Launch at login is off. \
                Drag Nayantara to the Trash yourself.

                \(trashError.localizedDescription)
                """
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([app])
            }
        }

        // exit, not NSApp.terminate: Sparkle installs a downloaded update when the
        // app terminates, which would put the app straight back. exit skips the
        // termination notifications it listens for.
        exit(0)
    }
}
