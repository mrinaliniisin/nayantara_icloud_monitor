import AppKit
import CoreServices
import Foundation
import Observation

/// Stop Syncing: keeps chosen files and folders out of iCloud Drive without renaming them.
///
/// The File Provider skips any item carrying the `com.apple.fileprovider.ignore#P`
/// extended attribute (the "label"), and everything inside a labelled folder.
/// Labelling an item that already synced deletes it from iCloud and the user's
/// other devices; the copy on this Mac stays.
///
/// The label lives on the item, so it can be lost: an app that saves by writing a
/// new file and renaming it over the old one drops it, and so does `npm ci`
/// deleting and recreating `node_modules`. iCloud schedules an upload for an
/// unlabelled item 50–100 ms after it appears, so a dedicated FSEvents stream with
/// no latency re-adds the label to anything in `rules`, typically within 15 ms.
/// At launch every rule is checked, for labels lost while Nayantara wasn't running.
///
/// `rules` (what Nayantara excluded) is saved in UserDefaults. Labels set some
/// other way (by hand, by another tool, or a rule list wiped by reinstalling) are
/// found by a scan at launch and listed in `foundElsewhere`.
@Observable
@MainActor
final class NoSync {
    static let shared = NoSync()
    nonisolated static let attribute = "com.apple.fileprovider.ignore#P"

    enum Status: Equatable {
        case excluded
        case reapplied(Date)    // the label was lost and put back
        case missing            // moved or deleted
        case failed(String)
    }

    private(set) var rules: [String] = UserDefaults.standard.stringArray(forKey: Keys.rules) ?? [] {
        didSet {
            UserDefaults.standard.set(rules, forKey: Keys.rules)
            guardian.setPaths(Set(rules))
        }
    }
    private(set) var status: [String: Status] = [:]
    /// Labelled items Nayantara didn't label, found at launch.
    private(set) var foundElsewhere: [String] = []

    /// Called with each newly excluded path, so the activity list can drop what's under it.
    @ObservationIgnored var didExclude: ((String) -> Void)?
    @ObservationIgnored private let guardian = Guardian()

    private enum Keys { static let rules = "noSyncRules" }

    var isEmpty: Bool { rules.isEmpty && foundElsewhere.isEmpty }

    func start(roots: [URL]) {
        guardian.setPaths(Set(rules))
        guardian.onReapplied = { path in
            DispatchQueue.main.async { NoSync.shared.status[path] = .reapplied(Date()) }
        }
        guardian.start(roots: roots)
        for path in rules { check(path) }

        // Takes several seconds; rules may change meanwhile, so filter on arrival.
        DispatchQueue.global(qos: .utility).async {
            let found = Self.scan(roots)
            DispatchQueue.main.async {
                self.foundElsewhere = found.filter { !self.rules.contains($0) && Self.hasLabel($0) }
            }
        }
    }

    /// Labels each item and adds a rule for it. Call `problem(with:)` first.
    func exclude(_ urls: [URL]) {
        for url in urls {
            let path = Self.canonical(url)
            if let error = Self.setLabel(path) {
                status[path] = .failed(error)
            } else {
                status[path] = .excluded
                didExclude?(path)
            }
            // Excluding a folder covers the rules under it.
            rules.removeAll { $0.hasPrefix(path + "/") }
            if !rules.contains(path) { rules.append(path) }
        }
    }

    /// Removes the label and the rule (or forgets a label found elsewhere). iCloud
    /// uploads the item again within seconds.
    func resume(_ path: String) {
        if let error = Self.removeLabel(path), FileManager.default.fileExists(atPath: path) {
            status[path] = .failed(error)
            return
        }
        rules.removeAll { $0 == path }
        foundElsewhere.removeAll { $0 == path }
        status[path] = nil
    }

    func resumeAll() {
        for path in rules + foundElsewhere { resume(path) }
    }

    struct Problem {
        let reason: String
        var needsDownload = false
    }

    /// Why `url` can't be excluded, or nil if it can. Can take a while for a big
    /// folder (it checks every file is downloaded), so call it off the main thread.
    nonisolated static func problem(with url: URL, roots: [URL]) -> Problem? {
        let path = canonical(url)
        let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents").path
        if roots.contains(where: { $0.path == path }) || path == mobileDocuments + "/com~apple~CloudDocs" {
            return Problem(reason: "It's a whole synced folder. Choose files and folders inside it instead.")
        }
        guard roots.contains(where: { path.hasPrefix($0.path + "/") }) else {
            return Problem(reason: "It isn't in iCloud Drive, Desktop or Documents.")
        }
        if (path as NSString).deletingLastPathComponent == mobileDocuments {
            return Problem(reason: "It's a whole iCloud container. Choose folders inside it instead.")
        }
        if isExcluded(path) { return Problem(reason: "It's already excluded.") }
        if let notHere = firstNotDownloaded(url) {
            let what = notHere == url ? "It" : "“\(notHere.lastPathComponent)” inside it"
            return Problem(reason: "\(what) is only in iCloud, so excluding it would leave no copy anywhere. Download it first.",
                           needsDownload: true)
        }
        return nil
    }

    /// The path FSEvents reports for `url`: iCloud Drive's Desktop and Documents
    /// are symlinks to ~/Desktop and ~/Documents. The item itself isn't resolved,
    /// in case it's a symlink.
    nonisolated static func canonical(_ url: URL) -> String {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: url.lastPathComponent).path
    }

    // MARK: - Labels

    nonisolated static func hasLabel(_ path: String) -> Bool {
        getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Whether `path` or a folder above it carries the label.
    nonisolated static func isExcluded(_ path: String) -> Bool {
        var p = path
        while p.count > 1 {
            if hasLabel(p) { return true }
            p = (p as NSString).deletingLastPathComponent
        }
        return false
    }

    /// nil on success, else the reason.
    nonisolated static func setLabel(_ path: String) -> String? {
        setxattr(path, attribute, "1", 1, 0, XATTR_NOFOLLOW) == 0 ? nil : String(cString: strerror(errno))
    }

    nonisolated static func removeLabel(_ path: String) -> String? {
        removexattr(path, attribute, XATTR_NOFOLLOW) == 0 || errno == ENOATTR ? nil : String(cString: strerror(errno))
    }

    // MARK: - Private

    /// Puts back a label lost while Nayantara wasn't running.
    private func check(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { status[path] = .missing; return }
        if Self.hasLabel(path) { status[path] = .excluded; return }
        status[path] = Self.setLabel(path).map(Status.failed) ?? .reapplied(Date())
    }

    /// The item, or the first file inside it, that's in iCloud but not on this Mac.
    nonisolated private static func firstNotDownloaded(_ url: URL) -> URL? {
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        func cloudOnly(_ u: URL) -> Bool {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isUbiquitousItem == true else { return false }
            return v.ubiquitousItemDownloadingStatus == .notDownloaded
        }
        if cloudOnly(url) { return url }
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return nil }
        for case let child as URL in walk where cloudOnly(child) { return child }
        return nil
    }

    /// Every labelled item under `roots`. Doesn't look inside labelled folders, or
    /// inside folders whose contents are only in iCloud (listing those would fetch
    /// them, and nothing in them can carry a label). Skips symlinks: macOS labels
    /// iCloud Drive's own Desktop and Documents links so they don't sync.
    nonisolated private static func scan(_ roots: [URL]) -> [String] {
        var found: [String] = []
        for root in roots {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk {
                let path = url.path
                var st = stat()
                guard lstat(path, &st) == 0, st.st_mode & S_IFMT != S_IFLNK else { continue }
                if hasLabel(path) {
                    found.append(path)
                    walk.skipDescendants()
                } else if st.st_flags & UInt32(SF_DATALESS) != 0 {
                    walk.skipDescendants()
                }
            }
        }
        return found
    }
}

/// The fast FSEvents stream that re-labels excluded items. Runs on its own queue,
/// not the main thread, so a busy UI can't push it past iCloud's 50 ms.
private final class Guardian: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Nayantara.NoSync", qos: .userInitiated)
    private var stream: FSEventStreamRef?
    private var _paths = Set<String>()
    var onReapplied: ((String) -> Void)?

    func setPaths(_ paths: Set<String>) { queue.async { self._paths = paths } }

    func start(roots: [URL]) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let guardian = Unmanaged<Guardian>.fromOpaque(info).takeUnretainedValue()
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
            guardian.handle(list.prefix(count))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// On `queue`. A set lookup per event, so a big download's flood of events is cheap.
    private func handle(_ events: some Sequence<String>) {
        for path in events where _paths.contains(path) {
            guard FileManager.default.fileExists(atPath: path), !NoSync.hasLabel(path),
                  NoSync.setLabel(path) == nil
            else { continue }
            onReapplied?(path)
        }
    }
}

// MARK: - Dialogs

extension NoSync {
    /// Settings › Stop Syncing Items…: pick files and folders, then confirm.
    func chooseAndExclude() {
        prepareForDialog()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true   // .git, .build and friends are the usual suspects
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        panel.prompt = "Stop Syncing"
        panel.message = "Choose files and folders to keep on this Mac but out of iCloud Drive."
        if DetachedWindow.shared.isPinned { panel.level = .modalPanel }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        confirmAndExclude(panel.urls)
    }

    /// Checks each item, then asks before excluding the ones that can be.
    func confirmAndExclude(_ urls: [URL]) {
        let roots = TransferMonitor.watchedRoots
        DispatchQueue.global(qos: .userInitiated).async {
            let checked = urls.map { ($0, Self.problem(with: $0, roots: roots)) }
            DispatchQueue.main.async { self.confirm(checked) }
        }
    }

    private func confirm(_ checked: [(URL, Problem?)]) {
        let ok = checked.filter { $0.1 == nil }.map(\.0)
        let skipped = checked.compactMap { url, problem in problem.map { (url, $0) } }
        let toDownload = skipped.filter { $0.1.needsDownload }.map(\.0)
        let skippedText = skipped.map { "“\($0.0.lastPathComponent)”: \($0.1.reason)" }.joined(separator: "\n\n")

        prepareForDialog()
        let alert = NSAlert()
        if DetachedWindow.shared.isPinned { alert.window.level = .modalPanel }

        guard !ok.isEmpty else {
            alert.messageText = checked.count == 1
                ? "Can't stop syncing “\(checked[0].0.lastPathComponent)”" : "Can't stop syncing these items"
            alert.informativeText = checked.count == 1 ? skipped[0].1.reason : skippedText
            if !toDownload.isEmpty { alert.addButton(withTitle: "Download") }
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn, !toDownload.isEmpty { download(toDownload) }
            return
        }

        let isFolder = { (u: URL) in (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        let files = ok.filter { !isFolder($0) }
        alert.alertStyle = .warning
        alert.messageText = ok.count == 1
            ? "Stop syncing “\(ok[0].lastPathComponent)”?" : "Stop syncing \(ok.count) items?"
        var info = (ok.count == 1 ? "It stays" : "They stay") + " on this Mac but " +
            (ok.count == 1 ? "is" : "are") + " removed from iCloud Drive and your other devices. " +
            "Nayantara keeps " + (ok.count == 1 ? "it" : "them") + " out of iCloud until you choose Resume Syncing."
        if !files.isEmpty {
            info += "\n\nA single file stays out of iCloud only while Nayantara is running: many apps save by " +
                "replacing the file, and the new one would upload. Excluding its folder works even when Nayantara isn't running."
        }
        if !skipped.isEmpty { info += "\n\nSkipped:\n\n" + skippedText }
        alert.informativeText = info
        alert.addButton(withTitle: "Stop Syncing").hasDestructiveAction = true
        let offerFolder = ok.count == 1 && files.count == 1
        if offerFolder { alert.addButton(withTitle: "Stop Syncing Its Folder") }
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: exclude(ok)
        case .alertSecondButtonReturn where offerFolder: confirmAndExclude([ok[0].deletingLastPathComponent()])
        default: break
        }
    }

    private func download(_ urls: [URL]) {
        for url in urls { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
    }

    /// The popover floats above normal windows and would cover the dialog.
    private func prepareForDialog() {
        StatusItemController.shared.closePopover()
        NSApp.activate()
    }
}
