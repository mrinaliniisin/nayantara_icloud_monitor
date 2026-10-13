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
    @ObservationIgnored private var recheckTimer: Timer?

    private static let keep = 20
    private static let maxChecksPerFlush = 300
    /// Rows still moving (or failing) are checked again this often: FSEvents only
    /// reports content changes, not a finished upload or a new upload error.
    private static let recheckInterval: TimeInterval = 10
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

        recheckTimer = Timer.scheduledTimer(withTimeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
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

    /// Updates rows that were uploading, downloading or failing, in place: their
    /// position and "seen" time stay, so the list doesn't reshuffle.
    private func recheck() {
        let moving = recent.filter { [.uploading, .downloading, .error].contains($0.state) }.map(\.url.path)
        guard !moving.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let fresh = Dictionary(moving.compactMap(Self.inspect).map { ($0.id, $0) }) { a, _ in a }
            DispatchQueue.main.async {
                self.recent = self.recent.map { old in
                    guard let new = fresh[old.id], new.state != old.state || new.errorText != old.errorText else { return old }
                    return FileActivity(url: old.url, state: new.state, size: new.size, errorText: new.errorText, seen: old.seen)
                }
            }
        }
    }

    /// Forgets rows at or under `path`, once it's excluded from syncing.
    func drop(under path: String) {
        recent.removeAll { $0.url.path == path || $0.url.path.hasPrefix(path + "/") }
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
        // Excluded from syncing (Stop Syncing): not sync activity, and one npm install
        // in an excluded node_modules would push everything else off the list.
        if v.isUbiquitousItem != true, NoSync.isExcluded(path) { return nil }

        // iCloud sets an uploading error ("Couldn't access your iCloud account") on
        // every new file for as long as its upload is in progress, and clears it when
        // the upload finishes. So an error counts only once nothing is moving.
        let moving = v.ubiquitousItemIsUploading == true || v.ubiquitousItemIsDownloading == true
        let error = moving ? nil : v.ubiquitousItemUploadingError ?? v.ubiquitousItemDownloadingError
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
