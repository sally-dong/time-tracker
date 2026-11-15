# Time Tracker

A native macOS menu bar timer with a weekly calendar. SwiftUI and AppKit; no packages, servers, accounts, or network requests. Requires macOS 14 or later.

## Build and open

```sh
./Scripts/build-app.sh
open "build/Time Tracker.app"
```

For daily use, move the app to `~/Applications` or `/Applications` before opening it. On first launch it registers to launch at login with `SMAppService`. If macOS asks for approval, choose **Settings → Approve in System Settings**. The same menu turns launch at login off.

## Release for download

```sh
./Scripts/release.sh
```

Builds a universal app (Apple silicon and Intel) into `build/release/TimeTracker-<version>.dmg`, which shows the app beside an Applications shortcut. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` for each release.

The default build is ad-hoc signed, so Gatekeeper blocks it on other Macs. To let it open normally, sign it with a Developer ID and notarize it (requires the paid Apple Developer Program):

1. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates → + ).
2. Store notary credentials once, using an [app-specific password](https://support.apple.com/102654):
   `xcrun notarytool store-credentials TimeTrackerNotary --apple-id <email> --team-id <TEAMID>`
3. Build, sign, notarize, and staple:
   `DEVELOPER_ID="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=TimeTrackerNotary ./Scripts/release.sh`

## App icon

The art is in `Resources/`: `AppIcon-simple-source.png` is in use; `AppIcon-source.png` is the original, more detailed version. The build makes two icons from the same crop of the 1254px art (x 75–1175, y 67–1167, which keeps the original margin above the progress ring):

- `AppIcon.icon`: an Icon Composer file with one unmasked layer. Xcode's `actool` compiles it into `Assets.car`, which macOS 26 masks itself. Without Xcode the build skips it with a warning, and macOS 26 draws small icons inside a grey plate.
- `AppIcon.png`: a 1024px master already masked to the macOS icon grid (824px plate, corners, shadow). `Scripts/MakeIcon.swift` resizes it into `AppIcon.icns` for macOS 14 and 15.

To change the icon, regenerate both from the new art.

## Use

- Click the menu bar timer to choose a project, start or pause, or open the calendar. The counter shows today's total for the selected project, including earlier sessions.
- Switching projects while running saves the current block and starts the new project.
- Closing the calendar leaves the menu bar app running. **Quit Time Tracker** stops the timer and exits.
- After 15 minutes without keyboard, mouse, or trackpad input, the timer stops at the last input. When you return, it restarts and asks whether to include the time away; including it joins the gap to the earlier block. This also applies if the Mac locks or sleeps after idling starts.
- Sleep, screen lock, and switching users also stop the timer at the last input rather than at the lock. It stays paused when you return.
- Change weeks with the arrows or **Today**. Scroll vertically through the 24-hour calendar.
- Click an empty slot or **Add time** to record missed time. Click a block to edit its project, dates, and times, or to delete it. Saving the active block pauses the timer.
- Blocks cannot overlap or end in the future. Blocks spanning midnight appear on each day they cover; totals use actual elapsed time, including across daylight saving changes.
- Add projects with the sidebar's **+**. Right-click a project to rename or recolor it; existing blocks take the new color.

## Local data

Data is stored in `~/Library/Application Support/TimeTracker/time-data.json`; **Reveal data file** shows it. Writes are atomic, and `time-data.json.backup` holds the previous snapshot. Quit the app before restoring a backup by hand.

A running timer checkpoints every 30 seconds. After a crash or unexpected shutdown, it restores through the last checkpoint and stays paused, so downtime is never counted; up to 30 seconds can be lost. A damaged file is left untouched, and tracking stays disabled until it is repaired or restored.

## Checks

```sh
./Scripts/check.sh
```

Six checks cover project switching, interruption recovery, edit validation, midnight and daylight saving totals, file persistence, and including idle time. The runner needs only Apple's Command Line Tools, not Xcode.

For a visual demo isolated from your real data and login settings:

```sh
open "build/Time Tracker.app" --args --preview
```

The demo keeps its data in a temporary `TimeTracker-Preview` directory.

Screen lock is detected through the distributed notification `com.apple.screenIsLocked`, which is not a documented public API; recheck lock behavior after major macOS upgrades. Sleep and user switching use `NSWorkspace` notifications.

Apple API references: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [sessionDidResignActiveNotification](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification).
