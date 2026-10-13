import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = TransferMonitor()
    private let activity = ActivityWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()
        activity.start(roots: TransferMonitor.watchedRoots)
        NoSync.shared.didExclude = { [activity] in activity.drop(under: $0) }
        NoSync.shared.start(roots: TransferMonitor.watchedRoots)

        StatusItemController.shared.start(monitor: monitor) { [monitor, activity] in
            AnyView(PopoverView(monitor: monitor, activity: activity))
        }
        DetachedWindow.shared.content = { [monitor, activity] in
            AnyView(PopoverView(monitor: monitor, activity: activity, stretches: true))
        }
        DetachedWindow.shared.restore()
        _ = Updater.shared   // starts Sparkle; it connects only if the user turned updates on
        NSApp.mainMenu = keyboardShortcuts()
    }

    /// Never shown (the app has no menu bar of its own), but its key equivalents
    /// still work while one of the app's windows is in front: ⌘, opens Settings,
    /// ⌘W closes the Settings or detached window, and text fields get copy and paste.
    private func keyboardShortcuts() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        main.addItem(withTitle: "Nayantara", action: nil, keyEquivalent: "").submenu = app
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }
}

// MARK: - Popover

struct PopoverView: View {
    let monitor: TransferMonitor
    let activity: ActivityWatcher
    /// Fill the width it's given (the resizable detached window) rather than
    /// staying at the fixed popover width.
    var stretches = false
    private var appearance: Appearance { .shared }
    private var noSync: NoSync { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if monitor.isIdle {
                Label("iCloud Drive is up to date", systemImage: "checkmark.icloud")
                    .scaledFont(.headline)
            }
            if let d = monitor.aggregateDownload { HeadlineCard(title: "Downloading", symbol: "arrow.down.circle.fill", t: d) }
            if let u = monitor.aggregateUpload { HeadlineCard(title: "Uploading", symbol: "arrow.up.circle.fill", t: u) }

            DiskCard(monitor: monitor)

            if !monitor.details.isEmpty {
                Section("Active transfers") {
                    CappedScroll(maxHeight: 220 * appearance.scale) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(monitor.details) { TransferRow(t: $0) }
                        }
                    }
                }
            }

            Section("Recent file activity") {
                if activity.recent.isEmpty {
                    Text("No changes seen since launch").foregroundStyle(.secondary).scaledFont(.callout)
                } else {
                    CappedScroll(maxHeight: 220 * appearance.scale) {
                        VStack(alignment: .leading, spacing: 4) {
                            // Only the newest row says how long ago: that's "when did anything last sync".
                            ForEach(activity.recent) { FileRow(f: $0, showTime: $0.id == activity.recent.first?.id) }
                        }
                    }
                }
            }

            if !noSync.isEmpty {
                Section("Not syncing") {
                    CappedScroll(maxHeight: 160 * appearance.scale) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(noSync.rules, id: \.self) { NoSyncRow(path: $0) }
                            ForEach(noSync.foundElsewhere, id: \.self) { NoSyncRow(path: $0, elsewhere: true) }
                        }
                    }
                }
            }

            Divider()
            Footer()
        }
        .padding(14)
        .scaledFont(.body)
        .environment(\.fontScale, appearance.scale)
        .frame(minWidth: appearance.width, maxWidth: stretches ? .infinity : appearance.width)
        // Solid, not the menu bar popover's default translucent material.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A ScrollView as tall as its content, up to `maxHeight`. A bare ScrollView has
/// no height of its own, so it's the first thing squeezed when space runs short.
private struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content.background(GeometryReader { g in
                Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
            })
        }
        .frame(height: min(contentHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).scaledFont(.caption2, weight: .semibold).foregroundStyle(.secondary)
            content
        }
    }
}

struct HeadlineCard: View {
    let title: String, symbol: String, t: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).scaledFont(.headline)
                Spacer()
                Text(t.fraction, format: .percent.precision(.fractionLength(1))).monospacedDigit().bold()
            }
            ProgressView(value: t.fraction)
            // Same wording as Finder's iCloud Drive bubble; falls back to our own
            // formatting for the moment before NSProgress has filled its strings in.
            HStack {
                if let summary = t.finderSummary {
                    Text(summary)
                } else if let all = t.totalFiles {
                    Text("\(all.formatted()) items")
                }
                Spacer()
                Text(t.finderDetail ?? "\(bytes(t.completedBytes)) of \(bytes(t.totalBytes))")
            }
            .scaledFont(.callout).monospacedDigit()
            .help("As shown by Finder's iCloud Drive progress bubble")
            HStack {
                Text(t.bytesPerSecond.map { "\(bytes(Int64($0)))/s" } ?? "Measuring speed…")
                Spacer()
                Text(t.secondsRemaining.map { "\(duration($0)) left" } ?? (t.bytesPerSecond == 0 ? "Stalled" : "—"))
            }
            .scaledFont(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

struct DiskCard: View {
    let monitor: TransferMonitor

    var body: some View {
        let used = monitor.totalDiskBytes - monitor.freeBytes
        let after = monitor.freeBytesAfterDownloads
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive").scaledFont(.headline)
                Spacer()
                Text("\(bytes(monitor.freeBytes)) free").monospacedDigit()
            }
            ProgressView(value: Double(max(0, used)), total: Double(max(1, monitor.totalDiskBytes)))
                .tint(after < 5_000_000_000 ? .red : .accentColor)
            if monitor.aggregateDownload != nil {
                Text(after < 0
                     ? "Not enough space: pending downloads need \(bytes(-after)) more"
                     : "\(bytes(after)) free once downloads finish")
                    .scaledFont(.callout)
                    .foregroundStyle(after < 5_000_000_000 ? .red : .secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

struct TransferRow: View {
    let t: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: t.direction == .upload ? "arrow.up" : "arrow.down")
                Text(t.url.map(displayPath) ?? "Unknown item").lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(t.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            ProgressView(value: t.fraction).controlSize(.small)
            HStack {
                Text("\(bytes(t.completedBytes)) of \(bytes(t.totalBytes))")
                if let done = t.completedFiles, let all = t.totalFiles { Text("· \(done.formatted())/\(all.formatted()) items") }
                Spacer()
                if let s = t.secondsRemaining { Text("\(duration(s)) left") }
            }
            .scaledFont(.caption1).foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(.rect)
        .onTapGesture { if let u = t.url { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
        .contextMenu { if let u = t.url { StopSyncingMenu(url: u) } }
    }
}

struct FileRow: View {
    let f: FileActivity
    var showTime = false
    @Environment(\.fontScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(f.errorText ?? displayPath(f.url.deletingLastPathComponent()))
                    .scaledFont(.caption1).foregroundStyle(f.errorText == nil ? .secondary : Color.red)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(f.state.rawValue).scaledFont(.caption1).foregroundStyle(color)
                Group {
                    if showTime {
                        // Re-rendered every second so "2s ago" keeps counting up.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(([f.size.map(bytes)] + [ago(f.seen, now: context.date)]).compactMap { $0 }
                                .joined(separator: " · "))
                        }
                    } else if let s = f.size {
                        Text(bytes(s))
                    }
                }
                .scaledFont(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .help("\(f.url.path)\nSeen at \(f.seen.formatted(date: .omitted, time: .standard))")
        .contentShape(.rect)
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
        .contextMenu { StopSyncingMenu(url: f.url) }
    }

    private var icon: String {
        switch f.state {
        case .uploading: "arrow.up.circle"
        case .downloading: "arrow.down.circle"
        case .synced: "checkmark.circle"
        case .cloudOnly: "icloud"
        case .error: "exclamationmark.triangle"
        case .local: "circle.dashed"
        }
    }

    private var color: Color {
        switch f.state {
        case .uploading, .downloading: .blue
        case .synced: .green
        case .error: .red
        case .cloudOnly, .local: .secondary
        }
    }
}

/// Right-click menu on a file or transfer row.
struct StopSyncingMenu: View {
    let url: URL

    var body: some View {
        Button("Stop Syncing “\(url.lastPathComponent)”…") { NoSync.shared.confirmAndExclude([url]) }
        Button("Stop Syncing “\(url.deletingLastPathComponent().lastPathComponent)” Folder…") {
            NoSync.shared.confirmAndExclude([url.deletingLastPathComponent()])
        }
    }
}

/// A row in Not syncing: an excluded item, what's happening to it, and Resume.
struct NoSyncRow: View {
    let path: String
    var elsewhere = false
    @Environment(\.fontScale) private var scale
    private var noSync: NoSync { .shared }

    var body: some View {
        let url = URL(filePath: path)
        let status = noSync.status[path]
        HStack(spacing: 6) {
            Image(systemName: status == .missing ? "questionmark.circle"
                  : { if case .failed = status { return "exclamationmark.triangle" }; return "icloud.slash" }())
                .foregroundStyle(.secondary).frame(width: 16 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(detail(status, parent: displayPath(url.deletingLastPathComponent())))
                    .scaledFont(.caption1).foregroundStyle(isProblem(status) ? Color.red : .secondary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Button(status == .missing ? "Remove" : "Resume") { noSync.resume(path) }
                .controlSize(.small)
                .help(status == .missing ? "Forget this item" : "Upload it to iCloud Drive again")
        }
        .help(path)
        .contentShape(.rect)
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func detail(_ status: NoSync.Status?, parent: String) -> String {
        switch status {
        case .missing: return "Missing: moved or deleted"
        case .failed(let why): return "Couldn't exclude: \(why)"
        case .reapplied(let when): return "Kept out of iCloud \(ago(when)) · \(parent)"
        case .excluded, nil: return elsewhere ? "Excluded outside Nayantara · \(parent)" : parent
        }
    }

    private func isProblem(_ status: NoSync.Status?) -> Bool {
        if case .failed = status { return true }
        return status == .missing
    }
}

struct Footer: View {
    @Environment(\.fontScale) private var scale

    var body: some View {
        HStack {
            RestartSyncButton()
            Spacer()
            SettingsMenu()
            Button("Quit") { NSApp.terminate(nil) }
                .help(NoSync.shared.isEmpty ? "" :
                      "Items you stopped syncing stay out of iCloud after you quit. To undo that, use Settings › Resume All Syncing.")
        }
        .controlSize(scale >= 1.3 ? .regular : .small)
    }
}

struct RestartSyncButton: View {
    private var restart: SyncRestart { .shared }

    var body: some View {
        Button { restart.restart() } label: {
            switch restart.state {
            case .idle: Text("🥾iCloud Sync")   // the boot is the icon: "boot" as in restart
            case .restarting: Label("Restarting…", systemImage: "arrow.clockwise")
            case .done: Label("Restarted", systemImage: "checkmark")
            case .failed: Label("Failed", systemImage: "exclamationmark.triangle")
            }
        }
        .disabled(restart.state == .restarting)
        .help({
            if case .failed(let why) = restart.state { return "Couldn't restart iCloud Drive: \(why)" }
            return "Restart iCloud Drive's sync process (bird). Use it when uploads or downloads sit at zero after the network comes back. Nothing queued is lost."
        }())
    }
}

struct SettingsMenu: View {
    @Environment(\.fontScale) private var scale
    @State private var anchor = NSView()

    var body: some View {
        // A plain Button rather than SwiftUI's Menu: Menu becomes an NSMenu that
        // ignores .font, so neither its label nor its items followed Font Size.
        Button { popUp() } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .background(AnchorView(view: anchor))
        .help("Detach or pin this panel, stop syncing items, and open Settings")
    }

    /// Quick actions only; everything else is in the Settings window.
    private func popUp() {
        let window = DetachedWindow.shared
        let font = NSFont.menuFont(ofSize: (NSFont.systemFontSize * scale).rounded())
        let menu = NSMenu()
        menu.font = font

        if window.isDetached {
            menu.addItem(.action("Attach to Menu Bar", "menubar.arrow.up.rectangle", font) { window.attach() })
        } else {
            menu.addItem(.action("Detach Window", "macwindow.on.rectangle", font) { window.detach() })
        }
        let pin = NSMenuItem.action("Pin on Top", "pin", font) { window.setPinned(!window.isPinned) }
        pin.state = window.isPinned ? .on : .off
        menu.addItem(pin)
        menu.addItem(.separator())

        let noSync = NoSync.shared
        menu.addItem(.action("Stop Syncing Items…", "icloud.slash", font) { noSync.chooseAndExclude() })
        if !noSync.isEmpty {
            menu.addItem(.action("Resume All Syncing…", "icloud.and.arrow.up", font) { confirmResumeAll() })
        }
        menu.addItem(.separator())

        let check = NSMenuItem.action("Check for Updates…", "arrow.down.app", font) { Updater.shared.checkNow() }
        check.isEnabled = Updater.shared.canCheck
        menu.autoenablesItems = false
        menu.addItem(check)
        menu.addItem(.action("What's New", "sparkles", font) { NSWorkspace.shared.open(Links.releases) })
        menu.addItem(.action("About Nayantara", "info.circle", font) { SettingsWindow.shared.show(.about) })
        let settings = NSMenuItem.action("Settings…", "gearshape", font) { SettingsWindow.shared.show() }
        settings.keyEquivalent = ","
        menu.addItem(settings)

        menu.popUpBelow(anchor)
    }
}

/// Settings › Resume All Syncing…
@MainActor
func confirmResumeAll() {
    let noSync = NoSync.shared
    let count = noSync.rules.count + noSync.foundElsewhere.count
    StatusItemController.shared.closePopover()
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = count == 1 ? "Resume syncing 1 item?" : "Resume syncing all \(count) items?"
    alert.informativeText = "They upload to iCloud Drive again and come back on your other devices."
    alert.addButton(withTitle: "Resume Syncing")
    alert.addButton(withTitle: "Cancel")
    if DetachedWindow.shared.isPinned { alert.window.level = .modalPanel }
    if alert.runModal() == .alertFirstButtonReturn { noSync.resumeAll() }
}

extension NSMenu {
    /// Opens the menu just under `anchor`, once the app is frontmost.
    ///
    /// The panel can be open while another app is still frontmost: since macOS 14,
    /// NSApp.activate() is a request the system may grant late. Clicking the panel
    /// then activates Nayantara a moment after the click, and that switch closes
    /// any menu already open, so the first click's menu flashed and vanished.
    /// Waiting for the activation (or a short timeout, if it's refused) avoids that.
    func popUpBelow(_ anchor: NSView) {
        let open = { [self] in
            _ = popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
        }
        guard !NSApp.isActive else { return open() }

        var opened = false
        var observer: NSObjectProtocol?
        let openOnce = {
            guard !opened else { return }
            opened = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            open()
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in DispatchQueue.main.async(execute: openOnce) }
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: openOnce)
    }
}

/// An empty view laid under the Settings button, so the menu can open just below it.
struct AnchorView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Runs a closure when its menu item is chosen. The item keeps it alive through
/// representedObject, since NSMenuItem.target is weak.
final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

extension NSMenuItem {
    static func action(_ title: String, _ symbol: String?, _ font: NSFont,
                       _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular))
        }
        return item
    }
}

// MARK: - Formatting

/// "just now", "12s ago", "3 min ago", "2 hr ago".
func ago(_ date: Date, now: Date = .now) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    switch s {
    case ..<2: return "just now"
    case ..<60: return "\(s)s ago"
    case ..<3600: return "\(s / 60) min ago"
    default: return "\(s / 3600) hr ago"
    }
}

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

func duration(_ seconds: Double) -> String {
    let f = DateComponentsFormatter()
    f.unitsStyle = .abbreviated
    f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute, .second] : [.second]
    f.maximumUnitCount = 2
    return f.string(from: max(1, seconds)) ?? "—"
}

/// "~/Desktop/Theo" style, and "iCloud Drive/…" for the CloudDocs container.
func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let cloudDocs = home + "/Library/Mobile Documents/com~apple~CloudDocs"
    let p = url.path
    if p.hasPrefix(cloudDocs) { return "iCloud Drive" + p.dropFirst(cloudDocs.count) }
    if p == home + "/Library/Mobile Documents" || p == home + "/Library/Mobile Documents/" { return "All of iCloud" }
    if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
    return p
}
