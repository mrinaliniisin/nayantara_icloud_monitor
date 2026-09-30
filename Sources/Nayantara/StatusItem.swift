import AppKit
import Observation
import SwiftUI

/// The menu bar icon. AppKit instead of SwiftUI's MenuBarExtra, because a
/// MenuBarExtra always opens its popover on click. Here the click goes to
/// whichever home the panel has right now: the popover when attached, or the
/// detached window, never both.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var monitor: TransferMonitor?

    func start(monitor: TransferMonitor, content: @escaping () -> AnyView) {
        self.monitor = monitor

        popover.behavior = .transient          // closes when you click elsewhere
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: content())

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.imagePosition = .imageLeading
        }
        observe()
    }

    @objc private func clicked() {
        if DetachedWindow.shared.isDetached {
            DetachedWindow.shared.show()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = item.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    // MARK: Icon

    /// Redraw the icon now, then again whenever the transfers it reads change.
    private func observe() {
        withObservationTracking { updateIcon() } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observe() }
        }
    }

    private func updateIcon() {
        guard let monitor, let button = item.button else { return }
        let down = monitor.aggregateDownload, up = monitor.aggregateUpload
        let symbol =
            down != nil && up != nil ? "arrow.up.arrow.down.circle"
            : down != nil ? "icloud.and.arrow.down"
            : up != nil ? "icloud.and.arrow.up"
            : "icloud"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Nayantara")
        image?.isTemplate = true
        button.image = image
        button.title = (down ?? up).map { " " + $0.fraction.formatted(.percent.precision(.fractionLength(0))) } ?? ""
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
}
