# Nayantara - the iCloud Monitor

A macOS menu bar app that shows what iCloud Drive is doing: what it's uploading and downloading, how fast, how long it will take, and whether it will fit on your disk.

Finder only shows a single "Downloading N items" bubble, with no speed, time left or disk space. Nayantara keeps a live summary in the menu bar and shows the details when you click it:

- **Downloading / Uploading:** percent done, the same "Downloading 1,431 items · 66.3 MB of 229.1 MB" line Finder shows in its iCloud Drive bubble, speed, and time left
- **Disk space:** free space now, plus free space once pending downloads finish, with a warning if they won't fit
- **Active transfers:** each folder being synced, with its own progress bar (click to show it in Finder)
- **Recent file activity:** the 20 most recent files that changed in iCloud-synced folders, each marked Uploading, Downloading, Synced, In iCloud only or Error, and kept up to date while they move
- **Restarts:** when iCloud throws away part of an upload or download and starts it again, the panel says so, for example "Started over 2 times in the last hour · 66 MB sent again"

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
- **Start it automatically:** turn on **Launch at login** in **Settings › General**.
- **🥾iCloud Sync (restart):** if uploads or downloads sit at zero after your network comes back (for example after blocking iCloud with a firewall app), click **🥾iCloud Sync** at the bottom of the panel. It restarts `bird`, the iCloud Drive background process; macOS relaunches it at once, and it picks up its queue again. Nothing queued is lost.
- **Quit:** click **Quit** at the bottom of the popover.
- **Update** after pulling new code: run `./build.sh --run` again. It quits the running copy and replaces it. Or let the app update itself: see [Updates](#updates).

## Settings

Click **Settings** (the gear) at the bottom of the panel for the quick actions:

- **Detach Window** moves the panel out of the menu bar into its own window, titled "Nayantara 👀", that you can drag anywhere. While it's detached, clicking the menu bar icon brings that window forward. **Attach to Menu Bar** puts it back.
- **Pin on Top** keeps the detached window above other windows, on every desktop (Space). Pinning while attached detaches it first.
- **Stop Syncing Items…** and **Resume All Syncing…**: see [Stop syncing items](#stop-syncing-items).
- **Check for Updates…**, **What's New** (the release notes on GitHub) and **About Nayantara**.
- **Settings…** (⌘,) opens the Settings window.

The Settings window has a tab for each area:

- **General:** Launch at login, **Font Size** (Small to Huge, for the panel, its menus and the Settings window; the panel gets wider to fit the text), Detach window, Pin on top, and **Uninstall Nayantara…** (see [Uninstall](#uninstall)).
- **Not Syncing:** everything you've kept out of iCloud Drive, with Resume buttons. See [Stop syncing items](#stop-syncing-items).
- **Updates:** the version you have and whether Nayantara may use the internet to look for new versions. See [Updates](#updates).
- **About:** credits, contact, the project's links (including [upcoming features](Planned%20Features.md)), and a UPI ID if you'd like to support the work.

Settings and the windows' positions are remembered between launches.

## Stop syncing items

Keep chosen files and folders on this Mac but out of iCloud Drive, for example `node_modules`, `.git`, build output or virtual machine images. Nothing is renamed.

- **Right-click** a row in Active transfers or Recent file activity and choose **Stop Syncing "name"…** or **Stop Syncing "folder" Folder…**
- Or click **Settings › Stop Syncing Items…** and choose files and folders.

Nayantara asks before it changes anything. Items that stop syncing:

- **stay on this Mac but are removed from iCloud Drive and your other devices.**
- are listed under **Not syncing** in the panel. Click **Resume** to sync one again; it uploads within seconds. **Settings › Resume All Syncing…** does them all.
- don't appear in Recent file activity.

Things to know:

- **Exclude folders rather than single files where you can.** Many apps save by writing a new file in place of the old one, which loses the exclusion. Nayantara puts it back within a few milliseconds, before iCloud starts uploading, but only while it's running. A folder stays excluded even when Nayantara isn't running.
- **Everything inside an excluded folder is excluded.** You can't sync one item inside it on its own.
- **Items that are only in iCloud can't be excluded** until they're downloaded, since excluding them would leave no copy anywhere. Nayantara offers to download them.
- **Quitting Nayantara doesn't undo anything.** Excluded items stay excluded, and when it opens again it re-applies any exclusion that was lost while it was closed. To undo them, use Resume All Syncing, or tick the box offered by Uninstall.
- Items excluded some other way (see below) show as **Excluded outside Nayantara**, with a Resume button.

## Updates

Nayantara never connects to the internet on its own. In **Settings › Updates** you can let it:

- **Use the internet to tell me about new updates:** about once a day it fetches a small list of releases from this project's GitHub page. When there's a newer version, it shows what's new and asks before installing.
- **Use the internet to download and install updates automatically:** downloads new versions in the background and installs them the next time Nayantara quits. Needs the first option.
- **Check Now…** (or **Check for Updates…** in the gear menu) checks once, when you click it.

Both options are off until you tick them. While they're off, Nayantara makes no network connections. A check sends nothing about you or your files: it only downloads the release list (and the update itself, if you install it). Every update is signed, and Nayantara refuses one whose signature doesn't match.

Updates are handled by [Sparkle](https://sparkle-project.org), an open-source updater under the MIT License; its license is in `Nayantara.app/Contents/Resources/Sparkle-LICENSE`.

## Uninstall

In **Settings › General**, click **Uninstall…**, then **Uninstall**. Nayantara:

1. turns off **Launch at login**
2. deletes its settings and caches
3. moves itself to the Trash (you can put it back from there until you empty the Trash)
4. quits

Your iCloud Drive files aren't touched. macOS leaves an empty settings file, `~/Library/Preferences/local.sindhus.Nayantara.plist`, the same as it does for `defaults delete`.

If you already deleted the app, items you stopped syncing stay out of iCloud. To list them:

```bash
find ~/Library/Mobile\ Documents ~/Desktop ~/Documents -xattrname 'com.apple.fileprovider.ignore#P' ! -type l -print
```

and to sync them all again:

```bash
find ~/Library/Mobile\ Documents ~/Desktop ~/Documents -xattrname 'com.apple.fileprovider.ignore#P' ! -type l -exec xattr -d 'com.apple.fileprovider.ignore#P' {} \;
```

Then remove what the app left behind:

```bash
rm -rf ~/Library/Caches/local.sindhus.Nayantara ~/Library/HTTPStorages/local.sindhus.Nayantara*
```

```bash
defaults delete local.sindhus.Nayantara
```

If you built it from source, also delete the build files:

```bash
rm -rf ~/Library/Caches/Nayantara-build
```

## Troubleshooting

- **The menu bar icon doesn't appear.** On a MacBook with a notch, crowded menu bar icons are hidden behind the notch. Quit a few other menu bar apps, or hold ⌘ and drag icons to rearrange them. To check that Nayantara is running, use `pgrep -lx Nayantara`.
- **Speed shows "Measuring speed…".** Speed and time left are worked out from about 15 seconds of samples, so they appear shortly after a transfer starts. "Stalled" means no bytes moved during that window.
- **"Upload stopped" or "Started over".** iCloud stopped a transfer before it finished, for example after a network error or a restart of its background process, and will usually try again from the start. Repeated restarts of a large upload usually mean the connection to iCloud's storage is slow or dropping. Try **🥾iCloud Sync**, or another network.
- **The build fails with a Swift version error.** Update Xcode or the Command Line Tools. `Package.swift` needs Swift 6.

## How it works

macOS has no single "iCloud sync status" API. Nayantara combines public ones:

- **Progress:** `Progress.addSubscriber(forFileURL:)` on `~/Library/Mobile Documents`, `~/Desktop` and `~/Documents`. This is the same mechanism Finder uses for its progress bubble. The subscription on `Mobile Documents` delivers iCloud's system-wide total. The ones on Desktop and Documents deliver per-folder progress, which can lag behind, so the headline always uses the system-wide total.
- **Speed and time left:** iCloud doesn't report these, so Nayantara works them out from how many bytes moved over the last 15 seconds.
- **Restarts:** iCloud doesn't report these either. A transfer whose progress disappears before it finishes is shown as stopped; if it comes back for the same amount of data but from (near) the start, or its byte count goes backwards, that's a restart. When `bird` is restarted mid-upload, the progress disappears for about 26 seconds and comes back at zero.
- **File states:** iCloud sets an upload error ("Couldn't access your iCloud account") on every new file while its upload is in progress, so Nayantara only shows an error once a file has stopped moving. Rows that are uploading, downloading or failing are checked again every 10 seconds.
- **Which files are moving:** FSEvents watches the synced folders. Each changed file's iCloud state (uploading, downloading, error, and so on) is read from its `URLResourceValues`.
- **Disk space:** `volumeAvailableCapacityForImportantUsageKey`, which counts purgeable space the same way macOS does.
- **Stop syncing:** iCloud Drive skips any item with the `com.apple.fileprovider.ignore#P` extended attribute, and everything in a folder that has it. Nayantara keeps a list of what it excluded. A second FSEvents stream with no delay re-adds the attribute when a save or a recreated folder drops it. iCloud schedules an upload for a new item 50–100 ms after it appears; Nayantara re-adds the attribute in about 15 ms. At launch it checks its list, and scans the synced folders for the attribute set some other way. (The symlinks macOS puts in iCloud Drive for Desktop and Documents carry it too, and are left out.)

`build.sh` puts build output in `~/Library/Caches/Nayantara-build` rather than a `.build` folder next to the source. If the source sits in an iCloud-synced folder such as Desktop or Documents, a `.build` folder would get uploaded to iCloud.

### Limitations

- iCloud's upload queue can't be listed in order.
- Recent file activity covers only changes seen since the app opened.
- iCloud account storage (space left in the cloud) isn't shown. Only local disk space is.
- A single excluded file is protected from save-by-replace only while Nayantara is running.

## Project layout

| File | What it does |
|---|---|
| `Sources/Nayantara/TransferMonitor.swift` | Progress subscriptions, speed and time left, disk space |
| `Sources/Nayantara/ActivityWatcher.swift` | FSEvents watcher and each file's sync state |
| `Sources/Nayantara/App.swift` | App startup and the panel's UI |
| `Sources/Nayantara/StatusItem.swift` | Menu bar icon and popover |
| `Sources/Nayantara/SettingsWindow.swift` | Settings window and its tabs |
| `Sources/Nayantara/DetachedWindow.swift` | Detached window and Pin on Top |
| `Sources/Nayantara/Appearance.swift` | Font Size setting |
| `Sources/Nayantara/Updater.swift` | Settings › Updates (Sparkle) |
| `Sources/Nayantara/SyncRestart.swift` | 🥾iCloud Sync button (restarts `bird`) |
| `Sources/Nayantara/NoSync.swift` | Stop Syncing: exclusion list, the attribute, the fast re-apply stream, its dialogs |
| `Sources/Nayantara/Uninstaller.swift` | Settings › General › Uninstall… |
| `Sources/Nayantara/main.swift` | AppKit entry point |
| `Info.plist` | App bundle settings (`LSUIElement` hides the Dock icon) |
| `Planned Features.md` | What's planned next (linked from Settings › About) |
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
