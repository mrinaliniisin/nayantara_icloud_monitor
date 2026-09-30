import Foundation
import Observation

/// One in-flight iCloud transfer, as published by the File Provider via NSProgress.
struct Transfer: Identifiable {
    enum Direction { case download, upload, other }

    let id: String                 // "<direction>|<path>" — stable across re-publishes
    let url: URL?
    let direction: Direction
    let isAggregate: Bool          // the File Provider's global total (published on ~/Library/Mobile Documents)
    var completedBytes: Int64
    var totalBytes: Int64
    var completedFiles: Int?
    var totalFiles: Int?
    var bytesPerSecond: Double?
    var secondsRemaining: Double?

    var fraction: Double { totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0 }
    var remainingBytes: Int64 { max(0, totalBytes - completedBytes) }
}

/// Subscribes to NSProgress publications under the iCloud-synced folders — the same
/// mechanism Finder uses for its "Downloading N items" bubble — and derives
/// throughput / ETA ourselves, since the File Provider leaves those keys unset.
@Observable
@MainActor
final class TransferMonitor {
    private(set) var transfers: [Transfer] = []
    private(set) var freeBytes: Int64 = 0
    private(set) var totalDiskBytes: Int64 = 0

    @ObservationIgnored private var live: [String: Progress] = [:]
    @ObservationIgnored private var samples: [String: [(t: Date, bytes: Int64)]] = [:]
    @ObservationIgnored private var tokens: [Any] = []
    @ObservationIgnored private var timer: Timer?

    private static let rateWindow: TimeInterval = 15

    static var watchedRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Mobile Documents carries the global aggregate; Desktop/Documents (when
        // "Desktop & Documents Folders" sync is on) publish per-folder progress.
        return ["Library/Mobile Documents", "Desktop", "Documents"].map { home.appending(path: $0) }
    }

    func start() {
        for root in Self.watchedRoots {
            let token = Progress.addSubscriber(forFileURL: root) { [weak self] progress in
                DispatchQueue.main.async { self?.published(progress) }
                return { DispatchQueue.main.async { self?.unpublished(progress) } }
            }
            tokens.append(token)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: Derived values

    var aggregateDownload: Transfer? { headline(.download) }
    var aggregateUpload: Transfer? { headline(.upload) }

    /// Folder/file-level transfers (everything except the global totals), biggest remaining first.
    var details: [Transfer] {
        transfers.filter { !$0.isAggregate }.sorted { $0.remainingBytes > $1.remainingBytes }
    }

    var isIdle: Bool { transfers.isEmpty }

    /// Free space once every pending download has landed on disk.
    var freeBytesAfterDownloads: Int64 { freeBytes - (aggregateDownload?.remainingBytes ?? 0) }

    /// Prefer the File Provider's global total; fall back to the largest per-folder transfer.
    private func headline(_ direction: Transfer.Direction) -> Transfer? {
        let matching = transfers.filter { $0.direction == direction }
        return matching.first(where: \.isAggregate) ?? matching.max { $0.totalBytes < $1.totalBytes }
    }

    // MARK: Subscription callbacks

    private func published(_ p: Progress) {
        live[key(for: p)] = p
        refresh()
    }

    private func unpublished(_ p: Progress) {
        let k = key(for: p)
        if live[k] === p {
            live[k] = nil
            samples[k] = nil
        }
        refresh()
    }

    private func key(for p: Progress) -> String {
        "\(direction(of: p))|\(p.fileURL?.path ?? String(describing: ObjectIdentifier(p)))"
    }

    private func direction(of p: Progress) -> Transfer.Direction {
        switch p.fileOperationKind {
        case .downloading?: .download
        case .uploading?: .upload
        default: .other
        }
    }

    // MARK: Polling

    private func refresh() {
        let now = Date()
        transfers = live.map { key, p in
            let done = p.completedUnitCount
            var window = (samples[key] ?? []) + [(now, done)]
            window.removeAll { now.timeIntervalSince($0.t) > Self.rateWindow }
            samples[key] = window

            var rate: Double?
            if let first = window.first, let last = window.last, last.t.timeIntervalSince(first.t) >= 2 {
                rate = max(0, Double(last.bytes - first.bytes) / last.t.timeIntervalSince(first.t))
            }
            let remaining = max(0, p.totalUnitCount - done)
            return Transfer(
                id: key,
                url: p.fileURL,
                direction: direction(of: p),
                isAggregate: p.userInfo[ProgressUserInfoKey("FPProgressIsCreatedByFileProviderKey")] != nil,
                completedBytes: done,
                totalBytes: p.totalUnitCount,
                completedFiles: p.fileCompletedCount,
                totalFiles: p.fileTotalCount,
                bytesPerSecond: rate,
                secondsRemaining: rate.flatMap { $0 > 0 ? Double(remaining) / $0 : nil }
            )
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            freeBytes = v.volumeAvailableCapacityForImportantUsage ?? 0
            totalDiskBytes = Int64(v.volumeTotalCapacity ?? 0)
        }
    }
}
