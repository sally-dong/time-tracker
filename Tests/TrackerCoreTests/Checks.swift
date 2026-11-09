import Foundation
import TrackerCore

// A tiny test runner that also works with Command Line Tools, without full Xcode.
struct CheckFailure: Error { let message: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure(message: message) }
}
func expectFailure(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure(message: "Expected validation to fail")
}

@main
enum Checks {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("Switching projects and pausing", transitions),
            ("Interrupted timer recovery", recovery),
            ("Editing and overlap validation", editing),
            ("Midnight and daylight saving totals", totals),
            ("Persistence, backup, and damaged data", persistence)
        ]
        for (name, test) in tests { try test(); print("PASS  \(name)") }
        print("\(tests.count) checks passed.")
    }

    static func transitions() throws {
        var data = TrackerData()
        let firstID = data.selectedProjectID
        let second = Project(name: "Second", color: "green")
        try data.saveProject(second)
        data.start(at: start)
        data.select(second.id, at: start.addingTimeInterval(60))
        data.pause(at: start.addingTimeInterval(180))
        data.pause(at: start.addingTimeInterval(200))
        try check(data.active == nil, "Pause must stop timer")
        try check(data.entries.map(\.duration) == [60, 120], "Incorrect session durations")
        try check(data.entries.map(\.projectID) == [firstID, second.id], "Incorrect project assignment")
        try check(data.entries[0].end == data.entries[1].start, "Switch must not leave a gap")
    }

    static func recovery() throws {
        var data = TrackerData()
        data.start(at: start)
        data.active?.checkpoint = start.addingTimeInterval(30)
        data.recoverInterruptedSession()
        data.recoverInterruptedSession()
        try check(data.active == nil, "Recovered timer must stay paused")
        try check(data.entries.map(\.duration) == [30], "Must only recover through checkpoint, once")
    }

    static func editing() throws {
        var data = TrackerData()
        let id = data.selectedProjectID
        let now = start.addingTimeInterval(1000)
        let original = TimeEntry(projectID: id, start: start, end: start.addingTimeInterval(60))
        try data.saveEntry(original, now: now)
        try expectFailure { try data.saveEntry(TimeEntry(projectID: id, start: start, end: start), now: now) }
        try expectFailure { try data.saveEntry(TimeEntry(projectID: id, start: start.addingTimeInterval(30), end: start.addingTimeInterval(90)), now: now) }
        try expectFailure { try data.saveEntry(TimeEntry(projectID: id, start: now, end: now.addingTimeInterval(60)), now: now) }
        var changed = original
        changed.end = start.addingTimeInterval(90)
        try data.saveEntry(changed, now: now)
        data.start(at: start.addingTimeInterval(100))
        let runningID = data.active!.id
        try data.saveEntry(TimeEntry(id: runningID, projectID: id, start: start.addingTimeInterval(100), end: now), now: now)
        try check(data.active == nil && data.entries.count == 2, "Active edit must pause and save exactly one block")
        data.deleteEntry(original.id)
        try check(data.entries.count == 1, "Delete must remove the selected block")
    }

    static func totals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let interval = calendar.dateInterval(of: .day, for: day)!
        try check(interval.duration == 25 * 3600, "Fixture must span the fall daylight saving transition")
        var data = TrackerData()
        try data.saveEntry(TimeEntry(projectID: data.selectedProjectID,
                                    start: day.addingTimeInterval(-3600), end: interval.end.addingTimeInterval(3600)),
                           now: interval.end.addingTimeInterval(3600))
        try check(data.duration(in: interval, now: interval.end) == 25 * 3600, "Totals must clip to the actual day")
    }

    static func persistence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = DataFile(url: folder.appendingPathComponent("data.json"))
        var data = TrackerData()
        data.start(at: start.addingTimeInterval(0.125))
        data.pause(at: start.addingTimeInterval(0.5))
        try file.save(data)
        try check(try file.load() == data, "Persistence must retain subsecond entries")
        data.start(at: start.addingTimeInterval(1))
        try file.save(data)
        try check(FileManager.default.fileExists(atPath: file.url.appendingPathExtension("backup").path), "Missing backup")
        try Data("not valid JSON".utf8).write(to: file.url)
        try expectFailure { _ = try file.load() }
        try check(try String(contentsOf: file.url) == "not valid JSON", "Damaged source must be untouched")
    }
}
