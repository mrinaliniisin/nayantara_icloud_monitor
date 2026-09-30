import CoreServices
import Foundation
import Observation

/// A file that recently changed under an iCloud-synced folder, with its current sync state.
struct FileActivity: Identifiable {
    enum State: String {
        case uploading = "Uploading"
        case downloading = "Downloading"
        case synced = "Synced"
        case cloudOnly = "In iCloud only"
        case error = "Error"
        case local = "Not synced"
    }

    var id: String { url.path }
    let url: URL
    let state: State
    let size: Int64?
    let errorText: String?
    let seen: Date
}

/// Watches the iCloud-synced folders with FSEvents and checks each changed file's
/// ubiquitous-item state. There's no public "upload queue" API, so this is how we
/// find out *which* files are moving.
@Observable
@MainActor
final class ActivityWatcher {
    private(set) var recent: [FileActivity] = []

    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var pending = Set<String>()
    @ObservationIgnored private var flushScheduled = false

    private static let keep = 40
    private static let maxChecksPerFlush = 300
    private static let ignoredNames: Set<String> = [".DS_Store", ".localized", "Icon\r"]

    nonisolated private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .fileSizeKey, .isUbiquitousItemKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingErrorKey,
    ]

    func start(roots: [URL]) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
            DispatchQueue.main.async { watcher.enqueue(list.prefix(count)) }
        }

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags)
        else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func enqueue(_ paths: some Sequence<String>) {
        for path in paths where !Self.ignoredNames.contains((path as NSString).lastPathComponent) {
            pending.insert(path)
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.flush() }
    }

    /// Resource lookups talk to the File Provider, so do them off the main thread and cap
    /// each batch — a 30k-item download can fire thousands of events per second.
    private func flush() {
        flushScheduled = false
        let batch = Array(pending.prefix(Self.maxChecksPerFlush))
        pending.removeAll()

        DispatchQueue.global(qos: .utility).async {
            let found = batch.compactMap(Self.inspect)
            DispatchQueue.main.async { self.merge(found) }
        }
    }

    private func merge(_ found: [FileActivity]) {
        guard !found.isEmpty else { return }
        let fresh = Set(found.map(\.id))
        recent = Array((found.sorted { $0.seen > $1.seen } + recent.filter { !fresh.contains($0.id) })
            .prefix(Self.keep))
    }

    nonisolated private static func inspect(_ path: String) -> FileActivity? {
        let url = URL(filePath: path)   // fresh URL => no cached resource values
        guard let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true else { return nil }

        let error = v.ubiquitousItemUploadingError ?? v.ubiquitousItemDownloadingError
        let state: FileActivity.State =
            if error != nil { .error }
            else if v.isUbiquitousItem != true { .local }
            else if v.ubiquitousItemIsUploading == true { .uploading }
            else if v.ubiquitousItemIsDownloading == true { .downloading }
            else if v.ubiquitousItemDownloadingStatus == .notDownloaded { .cloudOnly }
            else if v.ubiquitousItemIsUploaded == false { .uploading }   // queued, not started yet
            else { .synced }

        return FileActivity(
            url: url, state: state, size: v.fileSize.map(Int64.init),
            errorText: error?.localizedDescription, seen: Date())
    }
}
