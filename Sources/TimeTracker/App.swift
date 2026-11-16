import AppKit
import Combine
import CoreServices
import SwiftUI
import TrackerCore

@main
enum TimeTrackerApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var store: TrackerStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private var outsideClickMonitor: Any?
    private var menuSize: () -> NSSize = { .zero }
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preview = CommandLine.arguments.contains("--preview")
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.eventID == kAEOpenApplication &&
            launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        // Reopening an existing instance keeps all writes in one process.
        if !preview, let bundleID = Bundle.main.bundleIdentifier {
            let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other { other.activate(); NSApp.terminate(nil); return }
        }
        store = TrackerStore(preview: preview)
        store.openCalendar = { [weak self] in self?.showCalendar() }
        store.askAboutIdle = { [weak self] away, project, answer in
            // Deferred so the dialog's modal loop never runs inside a timer callback.
            DispatchQueue.main.async { answer(self?.confirmIdleTime(away, project: project) ?? false) }
        }
        makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.delegate = self
        let menu = NSHostingController(rootView: MenuView().environmentObject(store))
        // The popover is sized explicitly in togglePopover. Letting SwiftUI resize it
        // after it is shown moves its top edge, because macOS keeps the bottom fixed.
        menu.sizingOptions = []
        menuSize = { [menu] in menu.sizeThatFits(in: NSSize(width: 340, height: 2000)) }
        popover.contentViewController = menu
        // A message appearing while the popover is open changes its height; resize
        // and re-anchor it so it stays attached to the menu bar.
        store.$error.combineLatest(store.$notice).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.fitPopover() }
        }.store(in: &subscriptions)
        store.$now.combineLatest(store.$data).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        updateStatus()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(locked), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(waking), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // macOS posts this distributed notification immediately when the screen locks;
        // sessionDidResignActive additionally handles switching users.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(locked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        NotificationCenter.default.addObserver(self, selector: #selector(waking), name: .NSCalendarDayChanged, object: nil)
        store.configureLoginOnFirstLaunch()
        if preview || !launchedAtLogin { showCalendar() }
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.title = " " + TimeFormat.clock(store.todayTotal)
        button.image = NSImage(systemSymbolName: store.isRunning ? "timer" : "pause.circle", accessibilityDescription: store.isRunning ? "Timer running" : "Timer paused")
        button.toolTip = "\(store.selectedProject.name) · \(store.isRunning ? "Running" : "Paused") · Today"
        button.setAccessibilityLabel("Time Tracker, \(store.selectedProject.name), \(button.title), \(store.isRunning ? "running" : "paused")")
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        store.refresh()
        guard let button = statusItem.button else { return }
        popover.contentSize = menuSize()
        showPopover(below: button)
        popover.contentViewController?.view.window?.makeKey()
        // As a menu bar accessory the app often is not active, so .transient alone
        // misses clicks in other apps; close on any click outside the app instead.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    /// Anchors to the status item's full-height window rather than the button, which is
    /// shorter than the menu bar on notched displays and would put the arrow inside it.
    private func showPopover(below button: NSStatusBarButton) {
        let anchor = button.window?.contentView ?? button
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private func fitPopover() {
        guard popover.isShown, let button = statusItem.button else { return }
        let size = menuSize()
        guard size != popover.contentSize else { return }
        popover.contentSize = size
        showPopover(below: button)
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor); outsideClickMonitor = nil }
    }

    func showCalendar() {
        popover.performClose(nil)
        store.refresh()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Time Tracker"
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 940, height: 620)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: CalendarView().environmentObject(store))
            window.setFrameAutosaveName("TimeTrackerCalendar")
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCalendar(); return true }
    func applicationWillTerminate(_ notification: Notification) { store?.pause() }
    // Stop at the last input rather than the lock itself, so time spent away
    // before an automatic lock is not counted.
    @objc private func sleeping() { store.pause(reason: "Paused when your Mac went to sleep.", at: store.lastInput) }
    @objc private func locked() { store.pause(reason: "Paused when your Mac locked or switched users.", at: store.lastInput) }

    /// The timer is already running again; this only decides whether the gap counts.
    private func confirmIdleTime(_ away: TimeInterval, project: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "You were away for \(TimeFormat.short(away))"
        alert.informativeText = "The timer paused when you went idle and has started again. Add the time you were away to \(project)?"
        alert.addButton(withTitle: "Don’t Include")
        alert.addButton(withTitle: "Include \(TimeFormat.short(away))")
        alert.icon = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        return alert.runModal() == .alertSecondButtonReturn
    }
    @objc private func waking() { store.refresh() }
    @objc private func openCalendar() { showCalendar() }
    @objc private func revealData() { store.revealData() }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Calendar", action: #selector(openCalendar), keyEquivalent: "1").target = self
        appMenu.addItem(withTitle: "Reveal Data File", action: #selector(revealData), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Time Tracker", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Time Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        editItem.title = "Edit"
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; menu.addItem(editItem)
        let windowItem = NSMenuItem(); windowItem.title = "Window"
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu; menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }
}
