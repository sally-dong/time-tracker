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
    var openCalendar: () -> Void = {}
    var openProjects: () -> Void = {}

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
    func pause(reason: String? = nil) {
        guard isRunning else { return }
        let date = Date()
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
                if let active = self.data.active, self.now.timeIntervalSince(active.checkpoint) >= 30 {
                    self.change { $0.active?.checkpoint = self.now }
                }
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
    static let names = ["blue", "purple", "green", "orange", "pink", "teal", "red", "indigo"]
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": return Color(red: 0.53, green: 0.38, blue: 0.83)
        case "green": return Color(red: 0.23, green: 0.59, blue: 0.41)
        case "orange": return Color(red: 0.85, green: 0.48, blue: 0.20)
        case "pink": return Color(red: 0.79, green: 0.34, blue: 0.58)
        case "teal": return Color(red: 0.16, green: 0.58, blue: 0.61)
        case "red": return Color(red: 0.79, green: 0.32, blue: 0.31)
        case "indigo": return Color(red: 0.37, green: 0.42, blue: 0.72)
        default: return Color(red: 0.25, green: 0.49, blue: 0.85)
        }
    }
}

struct ProjectDot: View {
    let project: Project
    var body: some View { Circle().fill(Palette.color(project.color)).frame(width: 9, height: 9).accessibilityHidden(true) }
}
