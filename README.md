# Time Tracker

A small native macOS menu bar timer and weekly calendar. SwiftUI + AppKit, no packages, servers, accounts, or network requests. Requires macOS 14 or later.

## Build and open

```sh
./Scripts/build-app.sh
open "build/Time Tracker.app"
```

For daily use, keep the app in `~/Applications` or `/Applications` before opening it. On its first launch it registers to launch at login using Apple's `SMAppService`. If macOS requests approval, use **Settings → Approve in System Settings**. The same menu lets you turn launch at login off.

## App icon

The art is in `Resources/`: `AppIcon-simple-source.png` is in use; `AppIcon-source.png` is the original, more detailed version. The build makes two icons from the same crop of the 1254px art (x 75–1175, y 67–1167, which keeps the original margin above the progress ring):

- `AppIcon.icon`: an Icon Composer file with one unmasked layer. Xcode's `actool` compiles it into `Assets.car`, which macOS 26 masks itself. Without Xcode the build skips it with a warning, and macOS 26 draws small icons inside a grey plate.
- `AppIcon.png`: a 1024px master already masked to the macOS icon grid (824px plate, corners, shadow). `Scripts/MakeIcon.swift` resizes it into `AppIcon.icns` for macOS 14 and 15.

To change the icon, regenerate both from the new art.

## Use

- Click the timer in the menu bar to choose a project, start/pause, or open the calendar. The counter is today's total for the selected project, including earlier sessions.
- Switching projects while running saves the old block and immediately starts the new project.
- Closing the calendar leaves the menu bar app running. **Quit Time Tracker** stops the timer and exits.
- After 15 minutes without keyboard, mouse, or trackpad input, the timer stops at the moment you went idle. When you return, it starts again immediately and asks whether to include the time you were away. Including it joins the gap to the earlier block. This also applies if your Mac locks or sleeps after idling begins.
- Otherwise the timer pauses on sleep, screen lock, and switching users, stopping at your last input rather than the lock itself. It stays paused when you return.
- Navigate weeks using the arrows or Today. Scroll vertically through the 24-hour calendar.
- Click an empty calendar slot or **Add time** to record missed time. Click an existing block to edit its project and dates/times or delete it. Saving an active block pauses the timer.
- Time blocks cannot overlap or end in the future. Blocks spanning midnight appear on each relevant day; totals use actual elapsed time, including daylight saving transitions.
- Add projects with the sidebar's **+**. Right-click a project (or use Settings) to change its name or color. The colors update existing blocks too.

## Local data

Data lives in `~/Library/Application Support/TimeTracker/time-data.json`. Use **Reveal data file** to find it. Writes are atomic, and `time-data.json.backup` holds the previous saved snapshot. Quit the app before manually restoring a backup.

A running timer checkpoints every 30 seconds. After an unexpected shutdown, it restores only through that checkpoint and remains paused, so downtime is never counted. Up to 30 seconds may be lost after a crash. A damaged file is left untouched and tracking is disabled until it is repaired or restored.

## Minimal checks

```sh
./Scripts/check.sh
```

Six focused checks cover project transitions, interruption recovery, editing validation, midnight/daylight saving totals, file persistence, and including idle time. The tiny runner works with Apple's Command Line Tools without requiring a full Xcode installation. For a visual demo isolated from your real data and login settings:

```sh
open "build/Time Tracker.app" --args --preview
```

The demo stores its own data in the temporary `TimeTracker-Preview` directory. Screen lock is observed through macOS's distributed `com.apple.screenIsLocked` notification; sleep and user switching use `NSWorkspace` notifications. Lock behavior should be rechecked on major macOS upgrades because the distributed lock notification is not a documented public API.

Apple API references: [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [sessionDidResignActiveNotification](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification).
