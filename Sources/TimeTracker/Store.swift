import AppKit
import Combine
import ServiceManagement
import SwiftUI
import TrackerCore

@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var data: TrackerData
    @Published var now = Date()
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    let file: DataFile
    let preview: Bool
    private var loadFailed = false
    private var timer: Timer?
    private var idleWatch: Timer?
    private var idleBreak: (entryID: UUID, projectID: UUID, start: Date, stoppedAt: Date)?
    /// `-IdleLimitSeconds 20` as a launch argument shortens the limit for testing.
    private let idleLimit: TimeInterval = {
        let override = UserDefaults.standard.double(forKey: "IdleLimitSeconds")
        return override > 0 ? override : 15 * 60
    }()
    var openCalendar: () -> Void = {}
    /// Asks whether to keep time away from the computer: (duration, project name, answer).
    var askAboutIdle: (TimeInterval, String, @escaping (Bool) -> Void) -> Void = { _, _, _ in }

    init(preview: Bool) {
        self.preview = preview
        let directory = preview
            ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TimeTracker-Preview")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TimeTracker")
        file = DataFile(url: directory.appendingPathComponent("time-data.json"))
        do {
            data = try file.load()
            if data.active != nil {
                data.recoverInterruptedSession()
                try file.save(data)
                notice = "An interrupted timer was saved up to its last checkpoint and paused."
            }
        } catch {
            data = TrackerData()
            self.error = "Could not open your time data: \(error.localizedDescription)"
            loadFailed = true
        }
        if preview && data.entries.isEmpty { seedPreview() }
    }

    var selectedProject: Project { data.projects.first { $0.id == data.selectedProjectID } ?? data.projects[0] }
    var isRunning: Bool { data.active != nil }
    var today: DateInterval { Calendar.current.dateInterval(of: .day, for: now)! }
    var todayTotal: TimeInterval { data.duration(in: today, projectID: data.selectedProjectID, now: now) }
    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    func project(_ id: UUID) -> Project { data.projects.first { $0.id == id } ?? selectedProject }

    @discardableResult
    func change(_ mutation: (inout TrackerData) throws -> Void) -> Bool {
        guard !loadFailed else {
            error = "Your saved file needs attention before tracking can continue. Use Reveal Data File in the app menu to find it."
            return false
        }
        do {
            var next = data
            try mutation(&next)
            try file.save(next)
            data = next
            now = Date()
            updateTimer()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func toggle() {
        let date = Date()
        change { if $0.active == nil { $0.start(at: date) } else { $0.pause(at: date) } }
        notice = nil
    }
    func select(_ id: UUID) {
        change { $0.select(id, at: Date()) }
    }
    func pause(reason: String? = nil, at date: Date = Date()) {
        guard isRunning else { return }
        if change({ $0.pause(at: date) }) { notice = reason }
        else {
            // Stop counting even if a disk error prevents saving. Retain the finished
            // session in memory so the next successful mutation can save it.
            data.pause(at: date)
            updateTimer()
        }
    }
    func save(_ entry: TimeEntry) -> Bool { change { try $0.saveEntry(entry, now: Date()) } }
    func delete(_ id: UUID) -> Bool { change { $0.deleteEntry(id) } }
    func save(_ project: Project) -> Bool { change { try $0.saveProject(project) } }

    func refresh() {
        now = Date()
        loginStatus = SMAppService.mainApp.status
    }

    private func updateTimer() {
        guard isRunning else { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                if Self.idleTime >= self.idleLimit { self.stopForIdle(); return }
                if let active = self.data.active, self.now.timeIntervalSince(active.checkpoint) >= 30 {
                    self.change { $0.active?.checkpoint = self.now }
                }
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Idle

    /// Seconds since the last keyboard, mouse, or trackpad input. Needs no permissions.
    static var idleTime: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    var lastInput: Date { Date().addingTimeInterval(-Self.idleTime) }

    /// Stops the block at the moment input stopped, then waits for the user to return.
    private func stopForIdle() {
        guard let running = data.active else { return }
        let start = max(running.start, lastInput)
        pause(reason: "Paused at \(start.formatted(date: .omitted, time: .shortened)) while you were away.", at: start)
        guard !isRunning else { return }
        idleBreak = (running.id, running.projectID, start, Date())
        let watch = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForReturn() }
        }
        watch.tolerance = 0.5
        RunLoop.main.add(watch, forMode: .common)
        idleWatch = watch
    }

    private func checkForReturn() {
        guard let away = idleBreak, !Self.screenLocked else { return }
        let back = lastInput
        guard back > away.stoppedAt else { return }
        idleWatch?.invalidate(); idleWatch = nil; idleBreak = nil
        if !isRunning { change { $0.start(at: back) } }
        notice = nil
        let resumed = data.active?.start ?? back
        askAboutIdle(back.timeIntervalSince(away.start), project(away.projectID).name) { [weak self] include in
            guard include, let self else { return }
            self.change { try $0.includeIdleTime(after: away.entryID, until: resumed, now: Date()) }
        }
    }

    /// True at the lock screen or while another user is active. Read directly from the
    /// session so a missed lock or unlock notification can never leave the timer stuck.
    private static var screenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        return session["CGSSessionScreenIsLocked"] as? Bool == true || session[kCGSessionOnConsoleKey] as? Bool == false
    }

    func configureLoginOnFirstLaunch() {
        guard !preview, !UserDefaults.standard.bool(forKey: "didConfigureLogin") else { return }
        setLoginEnabled(true)
        if loginEnabled { UserDefaults.standard.set(true, forKey: "didConfigureLogin") }
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard !preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
        } catch {
            self.error = "Could not update launch at login: \(error.localizedDescription)"
            loginStatus = SMAppService.mainApp.status
        }
    }

    func revealData() { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }

    private func seedPreview() {
        let design = Project(name: "Design", color: "purple")
        let development = Project(name: "Development", color: "blue")
        let planning = Project(name: "Planning", color: "orange")
        data.projects = [design, development, planning]
        data.selectedProjectID = design.id
        let calendar = Calendar.current
        let start = CalendarView.weekStart(Date(), calendar: calendar)
        for day in 0..<7 {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            for (hour, length, project) in [(9, 90, design), (11, 120, development), (14, 45, planning)] {
                let begin = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                let end = begin.addingTimeInterval(Double(length * 60))
                if end < Date() {
                    data.entries.append(TimeEntry(projectID: project.id, start: begin, end: end))
                }
            }
        }
        try? file.save(data)
    }
}

enum Palette {
    /// Project colors in picker order; unknown names fall back to the first.
    private static let colors: [(name: String, color: Color)] = [
        ("blue", Color(red: 0.25, green: 0.49, blue: 0.85)),
        ("purple", Color(red: 0.53, green: 0.38, blue: 0.83)),
        ("green", Color(red: 0.23, green: 0.59, blue: 0.41)),
        ("orange", Color(red: 0.85, green: 0.48, blue: 0.20)),
        ("pink", Color(red: 0.79, green: 0.34, blue: 0.58)),
        ("teal", Color(red: 0.16, green: 0.58, blue: 0.61)),
        ("red", Color(red: 0.79, green: 0.32, blue: 0.31)),
        ("indigo", Color(red: 0.37, green: 0.42, blue: 0.72)),
    ]
    static let names = colors.map(\.name)
    static func color(_ name: String) -> Color { (colors.first { $0.name == name } ?? colors[0]).color }
}

struct ProjectDot: View {
    let project: Project
    var body: some View { Circle().fill(Palette.color(project.color)).frame(width: 9, height: 9).accessibilityHidden(true) }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary) }
}

struct TimerButton: View {
    @EnvironmentObject private var store: TrackerStore
    var body: some View {
        Button(action: store.toggle) {
            Label(store.isRunning ? "Pause timer" : "Start timer", systemImage: store.isRunning ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity).padding(.vertical, 5)
        }.buttonStyle(.borderedProminent).tint(Palette.color(store.selectedProject.color)).controlSize(.large)
    }
}
