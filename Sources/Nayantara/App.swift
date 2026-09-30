import AppKit
import ServiceManagement
import SwiftUI

@main
struct NayantaraApp: App {
    @State private var monitor: TransferMonitor
    @State private var activity: ActivityWatcher

    init() {
        let monitor = TransferMonitor()
        let activity = ActivityWatcher()
        monitor.start()
        activity.start(roots: TransferMonitor.watchedRoots)
        _monitor = State(initialValue: monitor)
        _activity = State(initialValue: activity)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: monitor, activity: activity)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let monitor: TransferMonitor

    var body: some View {
        let down = monitor.aggregateDownload, up = monitor.aggregateUpload
        let symbol =
            down != nil && up != nil ? "arrow.up.arrow.down.circle"
            : down != nil ? "icloud.and.arrow.down"
            : up != nil ? "icloud.and.arrow.up"
            : "icloud"
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if let t = down ?? up {
                Text(t.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    let monitor: TransferMonitor
    let activity: ActivityWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if monitor.isIdle {
                Label("iCloud Drive is up to date", systemImage: "checkmark.icloud")
                    .font(.headline)
            }
            if let d = monitor.aggregateDownload { HeadlineCard(title: "Downloading", symbol: "arrow.down.circle.fill", t: d) }
            if let u = monitor.aggregateUpload { HeadlineCard(title: "Uploading", symbol: "arrow.up.circle.fill", t: u) }

            DiskCard(monitor: monitor)

            if !monitor.details.isEmpty {
                Section("Active transfers") {
                    ForEach(monitor.details) { TransferRow(t: $0) }
                }
            }

            Section("Recent file activity") {
                if activity.recent.isEmpty {
                    Text("No changes seen since launch").foregroundStyle(.secondary).font(.callout)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(activity.recent) { FileRow(f: $0) }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            Divider()
            Footer()
        }
        .padding(14)
        .frame(width: 380)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

struct HeadlineCard: View {
    let title: String, symbol: String, t: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                Text(t.fraction, format: .percent.precision(.fractionLength(1))).monospacedDigit().bold()
            }
            ProgressView(value: t.fraction)
            HStack {
                Text("\(bytes(t.completedBytes)) of \(bytes(t.totalBytes))")
                Spacer()
                if let done = t.completedFiles, let all = t.totalFiles {
                    Text("\(done.formatted()) / \(all.formatted()) items")
                }
            }
            .font(.callout).monospacedDigit()
            HStack {
                Text(t.bytesPerSecond.map { "\(bytes(Int64($0)))/s" } ?? "Measuring speed…")
                Spacer()
                Text(t.secondsRemaining.map { "\(duration($0)) left" } ?? (t.bytesPerSecond == 0 ? "Stalled" : "—"))
            }
            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
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
                Label("Macintosh HD", systemImage: "internaldrive").font(.headline)
                Spacer()
                Text("\(bytes(monitor.freeBytes)) free").monospacedDigit()
            }
            ProgressView(value: Double(max(0, used)), total: Double(max(1, monitor.totalDiskBytes)))
                .tint(after < 5_000_000_000 ? .red : .accentColor)
            if monitor.aggregateDownload != nil {
                Text(after < 0
                     ? "Not enough space: pending downloads need \(bytes(-after)) more"
                     : "\(bytes(after)) free once downloads finish")
                    .font(.callout)
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
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .contentShape(.rect)
        .onTapGesture { if let u = t.url { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
    }
}

struct FileRow: View {
    let f: FileActivity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(f.errorText ?? displayPath(f.url.deletingLastPathComponent()))
                    .font(.caption).foregroundStyle(f.errorText == nil ? .secondary : Color.red)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(f.state.rawValue).font(.caption).foregroundStyle(color)
                if let s = f.size { Text(bytes(s)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .help(f.url.path)
        .contentShape(.rect)
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
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

struct Footer: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            Spacer()
            Button("iCloud Drive") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Mobile Documents/com~apple~CloudDocs"))
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

// MARK: - Formatting

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
