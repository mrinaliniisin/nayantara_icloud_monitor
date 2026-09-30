# Nayantara - the iCloud Monitor

A macOS menu bar app that shows what iCloud Drive is doing: what it's uploading and downloading, how fast, how long it will take, and whether it will fit on your disk.

Finder only shows a single "Downloading N items" bubble, with no speed, time left or disk space. Nayantara keeps a live summary in the menu bar and shows the details when you click it:

- **Downloading / Uploading:** percent done, bytes done out of total, items done out of total, speed, and time left
- **Disk space:** free space now, plus free space once pending downloads finish, with a warning if they won't fit
- **Active transfers:** each folder being synced, with its own progress bar (click to show it in Finder)
- **Recent file activity:** the last 40 files that changed in iCloud-synced folders, each marked Uploading, Downloading, Synced, In iCloud only or Error

Everything stays on your Mac. The app only reads information macOS already exposes, and it doesn't use the network.

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
- **Quit:** click **Quit** at the bottom of the popover.
- **Update** after pulling new code: run `./build.sh --run` again. It quits the running copy and replaces it.

## Uninstall

1. If you ticked **Launch at login**, untick it first.
2. Click **Quit** in the popover.
3. Delete the app and its build files:

   ```bash
   rm -rf ~/Applications/Nayantara.app ~/Library/Caches/Nayantara-build
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
| `Sources/Nayantara/App.swift` | Menu bar item and popover UI |
| `Info.plist` | App bundle settings (`LSUIElement` hides the Dock icon) |
| `build.sh` | Builds, installs and optionally opens the app |
