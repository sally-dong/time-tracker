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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: TrackerStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
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
        store.openProjects = { [weak self] in self?.showCalendar(addProject: true) }
        makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.contentViewController = NSHostingController(rootView: MenuView().environmentObject(store))
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showCalendar(addProject: Bool = false) {
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
        if addProject {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .addTrackerProject, object: nil) }
        }
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCalendar(); return true }
    func applicationWillTerminate(_ notification: Notification) { store?.pause() }
    @objc private func sleeping() { store.pause(reason: "Paused when your Mac went to sleep.") }
    @objc private func locked() { store.pause(reason: "Paused when your Mac locked or switched users.") }
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

extension Notification.Name {
    static let addTrackerProject = Notification.Name("addTrackerProject")
}
