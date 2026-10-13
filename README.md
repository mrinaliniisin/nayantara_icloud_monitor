# Nayantara - the iCloud Monitor

A macOS menu bar app that shows what iCloud Drive is doing: what it's uploading and downloading, how fast, how long it will take, and whether it will fit on your disk.

Finder only shows a single "Downloading N items" bubble, with no speed, time left or disk space. Nayantara keeps a live summary in the menu bar and shows the details when you click it:

- **Downloading / Uploading:** percent done, the same "Downloading 1,431 items · 66.3 MB of 229.1 MB" line Finder shows in its iCloud Drive bubble, speed, and time left
- **Disk space:** free space now, plus free space once pending downloads finish, with a warning if they won't fit
- **Active transfers:** each folder being synced, with its own progress bar (click to show it in Finder)
- **Recent file activity:** the 20 most recent files that changed in iCloud-synced folders, each marked Uploading, Downloading, Synced, In iCloud only or Error

Everything stays on your Mac. The app only reads information macOS already exposes, and it doesn't use the network unless you turn on update checks (see [Updates](#updates)). They're off until you do.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 or later, from either Xcode or the Command Line Tools. If you have neither, install the Command Line Tools:

  ```bash
  xcode-select --install
  ```

  To check your Swift version, run `swift --version`.
- iCloud Drive turned on in System Settings › [your name] › iCloud

## Set up

1. Get the source:

   ```bash
   git clone https://github.com/mrinaliniisin/nayantara_icloud_monitor.git
   cd nayantara_icloud_monitor
   ```

2. Build it, install it and start it:

   ```bash
   ./build.sh --run
   ```

   This compiles a release build, installs `Nayantara.app` in `~/Applications` (the Applications folder in your home folder, not the main one), and opens it. Leave off `--run` to install without opening it.

3. Look for the cloud icon near the right end of your menu bar. While iCloud is syncing, it shows an arrow and a percentage, for example ↓ 78%. Click it to see the details.

Nayantara lives only in the menu bar: it has no Dock icon and no window.

## Everyday use

- **Open it again** after quitting or restarting: search Spotlight (⌘ Space) for **Nayantara**, or run `open ~/Applications/Nayantara.app`.
- **Start it automatically:** tick **Launch at login** at the bottom of the popover.
- **🥾iCloud Sync (restart):** if uploads or downloads sit at zero after your network comes back (for example after blocking iCloud with a firewall app), click **🥾iCloud Sync** at the bottom of the panel. It restarts `bird`, the iCloud Drive background process; macOS relaunches it at once, and it picks up its queue again. Nothing queued is lost.
- **Quit:** click **Quit** at the bottom of the popover.
- **Update** after pulling new code: run `./build.sh --run` again. It quits the running copy and replaces it. Or let the app update itself: see [Updates](#updates).

## Settings

Click **Settings** (the gear) at the bottom of the panel:

- **Detach Window** moves the panel out of the menu bar into its own window, titled "Nayantara 👀", that you can drag anywhere. While it's detached, clicking the menu bar icon brings that window forward. **Attach to Menu Bar** puts it back.
- **Pin on Top** keeps the detached window above other windows, on every desktop (Space). Pinning while attached detaches it first.
- **Font Size** goes from Small to Huge. The panel gets wider to fit the text.

- **Updates** shows the version you have and lets you choose whether Nayantara may use the internet to look for new versions. See below.

Settings and the window's position are remembered between launches.

## Updates

Nayantara never connects to the internet on its own. Under **Settings › Updates** you can let it:

- **Use the internet to tell me about new updates:** about once a day it fetches a small list of releases from this project's GitHub page. When there's a newer version, it shows what's new and asks before installing.
- **Use the internet to download and install updates automatically:** downloads new versions in the background and installs them the next time Nayantara quits. Needs the first option.
- **Check for Updates Now…** checks once, when you click it.

Both options are off until you tick them. While they're off, Nayantara makes no network connections. A check sends nothing about you or your files: it only downloads the release list (and the update itself, if you install it). Every update is signed, and Nayantara refuses one whose signature doesn't match.

Updates are handled by [Sparkle](https://sparkle-project.org), an open-source updater under the MIT License; its license is in `Nayantara.app/Contents/Resources/Sparkle-LICENSE`.

## Uninstall

1. If you ticked **Launch at login**, untick it first.
2. Click **Quit** in the popover.
3. Delete the app and its build files:

   ```bash
   rm -rf ~/Applications/Nayantara.app ~/Library/Caches/Nayantara-build ~/Library/Caches/local.sindhus.Nayantara
   ```

4. Optionally, delete its settings too:

   ```bash
   defaults delete local.sindhus.Nayantara
   ```

## Troubleshooting

- **The menu bar icon doesn't appear.** On a MacBook with a notch, crowded menu bar icons are hidden behind the notch. Quit a few other menu bar apps, or hold ⌘ and drag icons to rearrange them. To check that Nayantara is running, use `pgrep -lx Nayantara`.
- **Speed shows "Measuring speed…".** Speed and time left are worked out from about 15 seconds of samples, so they appear shortly after a transfer starts. "Stalled" means no bytes moved during that window.
- **The build fails with a Swift version error.** Update Xcode or the Command Line Tools. `Package.swift` needs Swift 6.

## How it works

macOS has no single "iCloud sync status" API. Nayantara combines public ones:

- **Progress:** `Progress.addSubscriber(forFileURL:)` on `~/Library/Mobile Documents`, `~/Desktop` and `~/Documents`. This is the same mechanism Finder uses for its progress bubble. The subscription on `Mobile Documents` delivers iCloud's system-wide total. The ones on Desktop and Documents deliver per-folder progress, which can lag behind, so the headline always uses the system-wide total.
- **Speed and time left:** iCloud doesn't report these, so Nayantara works them out from how many bytes moved over the last 15 seconds.
- **Which files are moving:** FSEvents watches the synced folders. Each changed file's iCloud state (uploading, downloading, error, and so on) is read from its `URLResourceValues`.
- **Disk space:** `volumeAvailableCapacityForImportantUsageKey`, which counts purgeable space the same way macOS does.

`build.sh` puts build output in `~/Library/Caches/Nayantara-build` rather than a `.build` folder next to the source. If the source sits in an iCloud-synced folder such as Desktop or Documents, a `.build` folder would get uploaded to iCloud.

### Limitations

- iCloud's upload queue can't be listed in order.
- Recent file activity covers only changes seen since the app opened.
- iCloud account storage (space left in the cloud) isn't shown. Only local disk space is.

## Project layout

| File | What it does |
|---|---|
| `Sources/Nayantara/TransferMonitor.swift` | Progress subscriptions, speed and time left, disk space |
| `Sources/Nayantara/ActivityWatcher.swift` | FSEvents watcher and each file's sync state |
| `Sources/Nayantara/App.swift` | App startup and the panel's UI |
| `Sources/Nayantara/StatusItem.swift` | Menu bar icon and popover |
| `Sources/Nayantara/DetachedWindow.swift` | Detached window and Pin on Top |
| `Sources/Nayantara/Appearance.swift` | Font Size setting |
| `Sources/Nayantara/SyncRestart.swift` | 🥾iCloud Sync button (restarts `bird`) |
| `Sources/Nayantara/main.swift` | AppKit entry point |
| `Info.plist` | App bundle settings (`LSUIElement` hides the Dock icon) |
| `build.sh` | Builds, installs and optionally opens the app |
| `Resources/AppIcon.icns` | App icon (👀) |
| `scripts/make-icon.swift` | Regenerates the app icon from the emoji |

## Releasing

Published releases are what the in-app updater installs. `scripts/release.sh` builds a Developer ID signed copy, has Apple notarize it, signs the zip for Sparkle, and creates the GitHub release with `appcast.xml`, the list the app checks.

**Once, before the first release:**

1. Store notarization credentials. Make an app-specific password at [account.apple.com](https://account.apple.com) › Sign-In and Security, then:

   ```bash
   xcrun notarytool store-credentials nayantara --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

2. Make the update signing key. It's saved in your login Keychain and the public half is printed:

   ```bash
   ~/Library/Caches/Nayantara-build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Add the printed `SUPublicEDKey` line to `Info.plist`, then back up the private key somewhere safe outside iCloud Drive, for example a password manager. **If it's lost, copies already installed can never accept another update.**

   ```bash
   ~/Library/Caches/Nayantara-build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
   ```

**Each release:**

1. Raise `CFBundleShortVersionString` in `Info.plist` (for example `1.0` → `1.1`), commit and push. The build number is the commit count, so it goes up by itself.
2. Optionally write what's new in a Markdown file. It's shown in the update window and on GitHub.
3. Run:

   ```bash
   scripts/release.sh notes.md
   ```

`./build.sh --release` on its own makes the signed copy in `~/Library/Caches/Nayantara-build/dist` without publishing anything.
