import Foundation

public struct Project: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var color: String
    public init(id: UUID = UUID(), name: String, color: String) {
        self.id = id; self.name = name; self.color = color
    }
}

public struct TimeEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var projectID: UUID
    public var start: Date
    public var end: Date
    public init(id: UUID = UUID(), projectID: UUID, start: Date, end: Date) {
        self.id = id; self.projectID = projectID; self.start = start; self.end = end
    }
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public struct RunningSession: Codable, Equatable {
    public var id: UUID
    public var projectID: UUID
    public var start: Date
    public var checkpoint: Date
    public var entry: TimeEntry {
        TimeEntry(id: id, projectID: projectID, start: start, end: checkpoint)
    }
}

public enum TrackerError: LocalizedError {
    case invalidRange, futureTime, overlap, missingProject, invalidName, invalidFile
    public var errorDescription: String? {
        switch self {
        case .invalidRange: return "End time must be after start time."
        case .futureTime: return "Time blocks cannot end in the future."
        case .overlap: return "This overlaps another time block. Adjust the times first."
        case .missingProject: return "Choose a project first."
        case .invalidName: return "Give the project a name."
        case .invalidFile: return "The saved time data could not be read. Your original file has been left untouched."
        }
    }
}

public struct TrackerData: Codable, Equatable {
    public var version = 1
    public var projects: [Project]
    public var entries: [TimeEntry] = []
    public var selectedProjectID: UUID
    public var active: RunningSession?

    public init() {
        let project = Project(name: "Personal", color: "blue")
        projects = [project]; selectedProjectID = project.id
    }

    public mutating func start(at date: Date) {
        guard active == nil, projects.contains(where: { $0.id == selectedProjectID }) else { return }
        active = RunningSession(id: UUID(), projectID: selectedProjectID, start: date, checkpoint: date)
    }

    public mutating func pause(at date: Date) {
        guard let running = active else { return }
        if date > running.start {
            entries.append(TimeEntry(id: running.id, projectID: running.projectID, start: running.start, end: date))
        }
        active = nil
    }

    public mutating func select(_ projectID: UUID, at date: Date) {
        guard projects.contains(where: { $0.id == projectID }), projectID != selectedProjectID else { return }
        let wasRunning = active != nil
        pause(at: date)
        selectedProjectID = projectID
        if wasRunning { start(at: date) }
    }

    /// Never count the time while the app was closed or the computer was off.
    public mutating func recoverInterruptedSession() {
        guard let running = active else { return }
        pause(at: max(running.start, running.checkpoint))
    }

    public mutating func saveEntry(_ entry: TimeEntry, now: Date) throws {
        guard projects.contains(where: { $0.id == entry.projectID }) else { throw TrackerError.missingProject }
        guard entry.end > entry.start else { throw TrackerError.invalidRange }
        guard entry.end <= now.addingTimeInterval(1) else { throw TrackerError.futureTime }
        let others = visibleEntries(at: now).filter { $0.id != entry.id }
        guard !others.contains(where: { $0.start < entry.end && entry.start < $0.end }) else {
            throw TrackerError.overlap
        }
        if active?.id == entry.id { active = nil }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
    }

    public mutating func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if active?.id == id { active = nil }
    }

    public mutating func saveProject(_ project: Project) throws {
        var project = project
        project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.name.isEmpty else { throw TrackerError.invalidName }
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else { projects.append(project) }
    }

    public func visibleEntries(at now: Date) -> [TimeEntry] {
        guard let running = active else { return entries }
        return entries + [TimeEntry(id: running.id, projectID: running.projectID,
                                    start: running.start, end: max(running.start, now))]
    }

    public func duration(in interval: DateInterval, projectID: UUID? = nil, now: Date) -> TimeInterval {
        visibleEntries(at: now).reduce(0) { total, entry in
            guard projectID == nil || entry.projectID == projectID else { return total }
            return total + max(0, min(entry.end, interval.end).timeIntervalSince(max(entry.start, interval.start)))
        }
    }

    public func validate() throws {
        let ids = Set(projects.map(\.id))
        let activeValid = active.map { running in
            ids.contains(running.projectID) && running.checkpoint >= running.start &&
                !entries.contains(where: { $0.id == running.id })
        } ?? true
        guard version == 1, !projects.isEmpty, ids.count == projects.count,
              ids.contains(selectedProjectID), Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ ids.contains($0.projectID) && $0.end > $0.start }),
              activeValid
        else { throw TrackerError.invalidFile }
    }
}

public struct DataFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> TrackerData {
        guard FileManager.default.fileExists(atPath: url.path) else { return TrackerData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let data = try decoder.decode(TrackerData.self, from: Data(contentsOf: url))
        try data.validate()
        return data
    }
    public func save(_ data: TrackerData) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A previous valid snapshot stays available alongside the atomic primary file.
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try bytes.write(to: url, options: .atomic)
    }
}

public enum TimeFormat {
    public static func clock(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    public static func short(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration / 60))
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
