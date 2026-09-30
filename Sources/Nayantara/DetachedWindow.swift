import AppKit
import Observation
import SwiftUI

/// The popover's content in a free-standing window: movable anywhere, and
/// optionally pinned above every other window on every Space.
///
/// An AppKit panel rather than a SwiftUI Window scene because SwiftUI's
/// `.windowLevel` needs macOS 15 and this app supports 14.
@Observable
@MainActor
final class DetachedWindow {
    static let shared = DetachedWindow()

    private(set) var isDetached = false
    private(set) var isPinned = UserDefaults.standard.bool(forKey: Keys.pinned)

    /// Builds the window's content; set once at launch by the App.
    @ObservationIgnored var content: (() -> AnyView)?
    @ObservationIgnored private var panel: NSPanel?

    private enum Keys {
        static let detached = "detached"
        static let pinned = "pinned"
        static let frame = "DetachedWindowFrame"
    }

    /// Re-open the window if it was detached when the app last quit.
    func restore() {
        if UserDefaults.standard.bool(forKey: Keys.detached) { detach() }
    }

    /// Move the panel out of the menu bar into its own window. The popover
    /// closes first: the panel lives in one place at a time.
    func detach() {
        StatusItemController.shared.closePopover()
        let panel = panel ?? makePanel()
        self.panel = panel
        applyPin()
        setDetached(true)
        show()
    }

    /// Bring the detached window to the front (what a menu bar click does while detached).
    func show() {
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Put the panel back in the menu bar, and open it there so it's clear where it went.
    func attach() {
        panel?.close()   // willClose handler records the state
        StatusItemController.shared.showPopover()
    }

    func setPinned(_ on: Bool) {
        isPinned = on
        UserDefaults.standard.set(on, forKey: Keys.pinned)
        // Pinning only means something for a window that outlives the popover.
        if on && !isDetached { detach() } else { applyPin() }
    }

    /// The content is a fixed width that follows the Font Size setting; keep the window matching it.
    func fitWidth() {
        if let panel { fit(panel) }
    }

    private func fit(_ panel: NSPanel) {
        let width = Appearance.shared.width
        panel.minSize = NSSize(width: width, height: 240)
        panel.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        var frame = panel.frame
        frame.size.width = width
        panel.setFrame(frame, display: true, animate: false)
    }

    private func setDetached(_ on: Bool) {
        isDetached = on
        UserDefaults.standard.set(on, forKey: Keys.detached)
    }

    private func applyPin() {
        guard let panel else { return }
        panel.level = isPinned ? .floating : .normal
        panel.collectionBehavior = isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Appearance.shared.width, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "Nayantara 👀"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false        // panels hide when the app loses focus by default
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = NSHostingView(rootView:
            ScrollView { content?() }
                .padding(.top, 18)             // clear the transparent title bar
                .background(Color(nsColor: .windowBackgroundColor)))

        if !panel.setFrameUsingName(Keys.frame) { panel.center() }
        panel.setFrameAutosaveName(Keys.frame)
        fit(panel)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setDetached(false) }
        }
        return panel
    }
}
