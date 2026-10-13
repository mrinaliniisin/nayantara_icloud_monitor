import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// A tab in the Settings window's sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notSyncing, updates, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .notSyncing: "Not Syncing"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notSyncing: "icloud.slash"
        case .updates: "arrow.down.app"
        case .about: "info.circle"
        }
    }
}

/// The Settings window: a sidebar of tabs, each a grouped form. The gear menu
/// in the panel keeps only the quick actions and opens this for the rest.
///
/// An AppKit window for the same reason as DetachedWindow: the app has no
/// SwiftUI scenes (main.swift).
@Observable
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()

    var pane = SettingsPane.general
    @ObservationIgnored private var window: NSWindow?

    func show(_ pane: SettingsPane? = nil) {
        if let pane { self.pane = pane }
        // The menu bar popover floats above normal windows and would cover this one.
        StatusItemController.shared.closePopover()
        let window = window ?? makeWindow()
        self.window = window
        matchPinnedLevel()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A pinned detached window floats above normal windows. Settings shares its
    /// level, so whichever was clicked last is in front.
    func matchPinnedLevel() {
        window?.level = DetachedWindow.shared.isPinned ? .floating : .normal
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Nayantara Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = []   // the window keeps the size the person gives it
        window.contentViewController = host
        window.setContentSize(Self.minSize)
        if !window.setFrameUsingName("SettingsWindowFrame") { window.center() }
        window.setFrameAutosaveName("SettingsWindowFrame")
        fit(window)
        return window
    }

    /// The smallest size that fits the text at the current Font Size.
    private static var minSize: NSSize {
        let scale = Appearance.shared.scale
        return NSSize(width: 600 * scale, height: 440 * scale)
    }

    /// Grow the window when Font Size goes up, like the detached window's width.
    func fitSize() {
        if let window { fit(window) }
    }

    private func fit(_ window: NSWindow) {
        let min = Self.minSize
        window.contentMinSize = min
        let content = window.contentRect(forFrameRect: window.frame).size
        guard content.width < min.width || content.height < min.height else { return }
        window.setContentSize(NSSize(width: max(content.width, min.width), height: max(content.height, min.height)))
    }
}

// MARK: - Views

struct SettingsView: View {
    private var settings: SettingsWindow { .shared }
    private var appearance: Appearance { .shared }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 190 * appearance.scale)
            Divider().ignoresSafeArea()
            Group {
                switch settings.pane {
                case .general: GeneralPane()
                case .notSyncing: NotSyncingPane()
                case .updates: UpdatesPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Same Font Size as the panel: every text below goes through scaledFont.
        .scaledFont(.body)
        .environment(\.fontScale, appearance.scale)
        .controlSize(appearance.scale >= 1.3 ? .large : .regular)
    }
}

/// The tabs. Drawn here rather than with NavigationSplitView's sidebar List,
/// whose rows take their size from System Settings' "Sidebar icon size" and
/// ignore .font, so they wouldn't follow Font Size.
private struct Sidebar: View {
    @Environment(\.fontScale) private var scale
    private var settings: SettingsWindow { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            ForEach(SettingsPane.allCases) { pane in
                let selected = settings.pane == pane
                Button { settings.pane = pane } label: {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .foregroundStyle(selected ? Color.white : .accentColor)
                            .frame(width: 20 * scale)
                    }
                    .scaledFont(.body)
                    .foregroundStyle(selected ? Color.white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6 * scale)
                    .padding(.horizontal, 8 * scale)
                    .background(selected ? Color.accentColor : .clear, in: .rect(cornerRadius: 6 * scale))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(SidebarMaterial().ignoresSafeArea())
    }
}

/// The translucent sidebar background Finder and System Settings use.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Font Size's chooser. A Picker would be an NSPopUpButton, which ignores
/// .font, so its title and menu wouldn't follow the size they set; this is a
/// plain button that opens a menu in the scaled font, like the gear menu.
private struct FontSizeButton: View {
    @Environment(\.fontScale) private var scale
    @State private var anchor = NSView()
    private var appearance: Appearance { .shared }

    var body: some View {
        Button { popUp() } label: {
            HStack(spacing: 6 * scale) {
                Text(appearance.fontSize.title)
                Image(systemName: "chevron.up.chevron.down").imageScale(.small)
            }
        }
        .background(AnchorView(view: anchor))
    }

    private func popUp() {
        let font = NSFont.menuFont(ofSize: (NSFont.systemFontSize * scale).rounded())
        let menu = NSMenu()
        menu.font = font
        for size in FontSize.allCases {
            let item = NSMenuItem.action(size.title, nil, font) { Appearance.shared.fontSize = size }
            item.state = appearance.fontSize == size ? .on : .off
            menu.addItem(item)
        }
        menu.popUpBelow(anchor)
    }
}

/// A form row's grey second line, sized by Font Size. Form styles its own
/// subtitles with a fixed system font, so they're spelled out here.
private struct Subtitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).scaledFont(.subheadline).foregroundStyle(.secondary) }
}

/// A form section's heading, sized by Font Size.
private struct Header: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).scaledFont(.headline) }
}

private struct GeneralPane: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private var appearance: Appearance { .shared }
    private var window: DetachedWindow { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            } header: { Header("Startup") }

            Section {
                LabeledContent {
                    FontSizeButton()
                } label: {
                    Text("Font size")
                    Subtitle("All of Nayantara's text, in the panel and here")
                }
                Toggle(isOn: Binding(
                    get: { window.isDetached },
                    set: { on in
                        if on { window.detach() } else { window.attach(showingPopover: false) }
                        SettingsWindow.shared.show()   // stay in front of the window that just opened
                    }
                )) {
                    Text("Detach window")
                    Subtitle("Move the panel out of the menu bar into a window you can drag anywhere")
                }
                Toggle(isOn: Binding(
                    get: { window.isPinned },
                    set: { window.setPinned($0); SettingsWindow.shared.show() }
                )) {
                    Text("Pin on top")
                    Subtitle("Keep the detached window above other windows, on every desktop")
                }
            } header: { Header("Panel") }

            Section {
                LabeledContent {
                    Button("Uninstall…") { Uninstaller.confirmAndUninstall() }
                } label: {
                    Text("Uninstall Nayantara")
                    Subtitle("Turns off Launch at login, deletes settings and caches, and moves the app to the Trash. Your iCloud Drive files aren't touched.")
                }
            }
        }
    }
}

private struct NotSyncingPane: View {
    private var noSync: NoSync { .shared }

    var body: some View {
        Form {
            Section {
                Text("Items you stop syncing stay on this Mac but are removed from iCloud Drive and your other devices. Right-click a file in the panel to stop syncing it or its folder.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if noSync.isEmpty {
                    Text("Everything in iCloud Drive is syncing.").foregroundStyle(.secondary)
                } else {
                    ForEach(noSync.rules, id: \.self) { NoSyncRow(path: $0) }
                    ForEach(noSync.foundElsewhere, id: \.self) { NoSyncRow(path: $0, elsewhere: true) }
                }
            } header: { Header("Not syncing") }

            Section {
                HStack {
                    Button("Stop Syncing Items…") { noSync.chooseAndExclude() }
                    Spacer()
                    Button("Resume All Syncing…") { confirmResumeAll() }
                        .disabled(noSync.isEmpty)
                }
            }
        }
    }
}

private struct UpdatesPane: View {
    // Sparkle keeps these in UserDefaults, not anything SwiftUI can observe,
    // so mirror them and read them back after every change.
    @State private var checks = Updater.shared.checksAutomatically
    @State private var downloads = Updater.shared.downloadsAutomatically

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed", value: Updater.version)
            }

            Section {
                Toggle(isOn: $checks) {
                    Text("Use the internet to tell me about new updates")
                    Subtitle("Checks GitHub about once a day")
                }
                Toggle(isOn: $downloads) {
                    Text("Use the internet to download and install updates automatically")
                    Subtitle("Downloads new versions in the background and installs them the next time Nayantara quits")
                }
                .disabled(!checks)   // installing needs the check
            } footer: {
                Subtitle("While both are off, Nayantara doesn't use the network.")
            }

            Section {
                LabeledContent {
                    Button("Check Now…") { Updater.shared.checkNow() }
                        .disabled(!Updater.shared.canCheck)
                } label: {
                    Text("Check for updates")
                    Subtitle("Connects to GitHub once, now")
                }
            }
        }
        .onChange(of: checks) { _, on in
            Updater.shared.checksAutomatically = on
            downloads = Updater.shared.downloadsAutomatically
        }
        .onChange(of: downloads) { _, on in
            Updater.shared.downloadsAutomatically = on
            checks = Updater.shared.checksAutomatically
        }
    }
}

private struct AboutPane: View {
    @Environment(\.fontScale) private var scale

    var body: some View {
        // Scrolls rather than truncating when Font Size makes it taller than the window.
        ScrollView {
            content.frame(maxWidth: .infinity)
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96 * scale, height: 96 * scale)
            Text("Nayantara").scaledFont(.title1, weight: .bold)
            Text(Updater.version).foregroundStyle(.secondary)
            Text("Made with lots of tokens and ❤️ by Claude and Mrinalini S.")
                .fixedSize(horizontal: false, vertical: true)   // wrap, don't truncate
                .padding(.top, 6)
            VStack(spacing: 4) {
                Link("Write to \(Links.email)", destination: URL(string: "mailto:\(Links.email)")!)
                Link("Project on GitHub", destination: Links.project)
                Link("What's New", destination: Links.releases)
                Link("Upcoming features", destination: Links.plannedFeatures)
            }
            VStack(spacing: 2) {
                Text("Feel like supporting my work?").foregroundStyle(.secondary)
                UPILink()
            }
            .padding(.top, 8)
            Spacer().frame(height: 12)
            if let license = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: nil) {
                Button("Updates by Sparkle, MIT License") { NSWorkspace.shared.open(license) }
                    .buttonStyle(.link)
                    .scaledFont(.caption1).foregroundStyle(.secondary)
            } else {
                Text("Updates by Sparkle, MIT License").scaledFont(.caption1).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }
}

/// The UPI ID, linked to a payment request. Macs rarely have an app for upi://
/// links, so without one the click copies the ID instead of doing nothing.
private struct UPILink: View {
    @State private var copied = false

    var body: some View {
        Button {
            if NSWorkspace.shared.urlForApplication(toOpen: Links.upiPayment) != nil {
                NSWorkspace.shared.open(Links.upiPayment)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Links.upi, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
        } label: {
            Text(copied ? "Copied \(Links.upi)" : Links.upi).monospaced()
        }
        .buttonStyle(.link)
        .help("Pay by UPI. Copies the UPI ID if no app on this Mac opens UPI links.")
        .contextMenu {
            Button("Copy UPI ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Links.upi, forType: .string)
            }
        }
    }
}

enum Links {
    static let email = "mrinalini_s@icloud.com"
    static let upi = "mrinalinis@upi"
    static let upiPayment = URL(string: "upi://pay?pa=mrinalinis@upi&pn=Mrinalini%20S&cu=INR")!
    static let project = URL(string: "https://github.com/mrinaliniisin/nayantara_icloud_monitor")!
    static let releases = URL(string: "https://github.com/mrinaliniisin/nayantara_icloud_monitor/releases")!
    static let plannedFeatures = URL(string: "https://github.com/mrinaliniisin/nayantara_icloud_monitor/blob/main/Planned%20Features.md")!
}
