import Foundation
import Observation

/// The "🥾iCloud Sync" button: kills `bird`, the iCloud Drive daemon, which launchd
/// relaunches straight away. After the network drops out (TripMode, flaky
/// Wi-Fi) iCloud can sit on a ready upload queue without retrying; a fresh
/// `bird` re-reads its queue and gets going again.
///
/// Only this user's `bird` is touched: killall can't signal other users'
/// processes without root. Nothing queued is lost; the queue lives on disk.
@Observable
@MainActor
final class SyncRestart {
    static let shared = SyncRestart()

    enum State: Equatable {
        case idle, restarting, done, failed(String)
    }

    private(set) var state = State.idle

    func restart() {
        guard state != .restarting else { return }
        state = .restarting

        DispatchQueue.global(qos: .userInitiated).async {
            let killed = Self.run("/usr/bin/killall", "bird") == 0
            // launchd relaunches bird on demand; give it a moment, then check.
            var back = false
            for _ in 0..<10 where !back {
                Thread.sleep(forTimeInterval: 0.5)
                back = Self.run("/usr/bin/pgrep", "-x", "-u", "\(getuid())", "bird") == 0
            }
            let result: State =
                !killed ? .failed("bird wasn't running")
                : back ? .done
                : .failed("bird hasn't restarted yet")

            DispatchQueue.main.async {
                self.state = result
                // Let the result show briefly, then go back to the plain button.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.state == result { self.state = .idle }
                }
            }
        }
    }

    nonisolated private static func run(_ path: String, _ args: String...) -> Int32 {
        let p = Process()
        p.executableURL = URL(filePath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
