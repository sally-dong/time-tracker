import ServiceManagement
import SwiftUI
import TrackerCore

struct CalendarView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var week = Self.weekStart(Date())
    @State private var entryDraft: EntryDraft?
    @State private var projectDraft: Project?
    @State private var showNewProject = false
    private let hourHeight: CGFloat = 64
    private let gutter: CGFloat = 52
    private var calendar: Calendar { Calendar.current }
    private var days: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: week)! } }
    private var interval: DateInterval { DateInterval(start: week, end: calendar.date(byAdding: .day, value: 7, to: week)!) }
    private var weekTotal: TimeInterval { store.data.duration(in: interval, now: store.now) }

    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start)!
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 225)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                dayHeaders
                Divider()
                calendarGrid
                Divider()
                HStack {
                    Circle().fill(store.isRunning ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(store.isRunning ? "Tracking \(store.selectedProject.name)" : (store.notice ?? "Timer paused"))
                    Spacer()
                    Text("Click an empty slot to add time").foregroundStyle(.tertiary)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 34)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $entryDraft) { draft in EntryEditor(draft: draft).environmentObject(store) }
        .sheet(item: $projectDraft) { project in ProjectEditor(project: project, isNew: showNewProject).environmentObject(store) }
        .onReceive(NotificationCenter.default.publisher(for: .addTrackerProject)) { _ in newProject() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refresh() }
        .alert("Time Tracker", isPresented: Binding(get: { store.error != nil && entryDraft == nil && projectDraft == nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "timer").font(.title3).foregroundStyle(.secondary)
                Text("Time Tracker").font(.headline)
            }.padding(.bottom, 30)
            Text("TODAY").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            Text(TimeFormat.clock(store.todayTotal)).font(.system(size: 31, weight: .light, design: .rounded)).monospacedDigit().padding(.top, 8)
            HStack(spacing: 7) { ProjectDot(project: store.selectedProject); Text(store.selectedProject.name).lineLimit(1) }
                .font(.callout).foregroundStyle(.secondary).padding(.top, 7)
            Button(action: store.toggle) {
                Label(store.isRunning ? "Pause timer" : "Start timer", systemImage: store.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent).tint(Palette.color(store.selectedProject.color)).controlSize(.large).padding(.top, 20)
            Divider().padding(.vertical, 24)
            HStack {
                Text("PROJECTS").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                Button(action: newProject) { Image(systemName: "plus") }.buttonStyle(.plain).help("New project").accessibilityLabel("New project")
            }.padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.data.projects) { project in
                        Button { store.select(project.id) } label: {
                            HStack(spacing: 9) {
                                ProjectDot(project: project)
                                Text(project.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(TimeFormat.short(store.data.duration(in: interval, projectID: project.id, now: store.now)))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }.padding(.horizontal, 10).padding(.vertical, 10)
                                .background(store.data.selectedProjectID == project.id ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help("Select \(project.name). Right-click to edit name or color.")
                            .contextMenu { Button("Edit project…") { showNewProject = false; store.error = nil; projectDraft = project } }
                    }
                }
            }.padding(.horizontal, -10)
            Text("Project totals for this week").font(.caption2).foregroundStyle(.tertiary).padding(.top, 10)
            Spacer(minLength: 24)
            Divider().padding(.bottom, 16)
            Menu {
                Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLoginEnabled))
                if store.loginStatus == .requiresApproval {
                    Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Button("Reveal data file", action: store.revealData)
                Button("Edit selected project…") { showNewProject = false; projectDraft = store.selectedProject }
                Divider()
                Button("Quit Time Tracker") { NSApplication.shared.terminate(nil) }
            } label: { Label("Settings", systemImage: "gearshape").font(.callout).foregroundStyle(.secondary) }
            .menuStyle(.borderlessButton).fixedSize()
            Text("Saved on this Mac").font(.caption2).foregroundStyle(.tertiary).padding(.top, 10)
        }.padding(22).background(Color.primary.opacity(0.018))
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(weekTitle).font(.system(size: 21, weight: .semibold))
                Text("\(TimeFormat.short(weekTotal)) tracked this week").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }.help("Previous week").accessibilityLabel("Previous week")
                Button("Today") { week = Self.weekStart(Date()) }
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }.help("Next week").accessibilityLabel("Next week")
            }.controlSize(.regular)
            Button { addTime(at: Date().addingTimeInterval(-3600)) } label: { Label("Add time", systemImage: "plus") }
                .controlSize(.regular)
        }.padding(.horizontal, 24).padding(.vertical, 22)
    }

    private var weekTitle: String {
        let last = days[6]
        let firstText = week.formatted(.dateTime.month(.abbreviated).day())
        let lastText = last.formatted(.dateTime.month(.abbreviated).day())
        let year = last.formatted(.dateTime.year())
        if calendar.component(.year, from: week) != calendar.component(.year, from: last) {
            return "\(firstText), \(week.formatted(.dateTime.year())) – \(lastText), \(year)"
        }
        return "\(firstText) – \(lastText), \(year)"
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                let total = store.data.duration(in: calendar.dateInterval(of: .day, for: day)!, now: store.now)
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day())).font(.callout.weight(isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                            .frame(width: 26, height: 26).background(isToday ? Color.accentColor : Color.clear, in: Circle())
                    }
                    Text(total > 0 ? TimeFormat.short(total) : "—").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }.padding(.trailing, 12).frame(height: 76)
    }

    private var calendarGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(0..<24) { hour in
                            Text(String(format: "%02d:00", hour)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                                .frame(width: gutter, height: hourHeight, alignment: .top).offset(y: -6).id(hour)
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            DayColumn(day: day, hourHeight: hourHeight, entries: entries(on: day),
                                      project: store.project, activeID: store.data.active?.id, now: store.now,
                                      edit: { entry in
                                          store.error = nil
                                          entryDraft = EntryDraft(entry: entry, running: store.data.active?.id == entry.id)
                                      }, add: addTime)
                        }
                    }
                }.padding(.top, 10).padding(.trailing, 12)
            }.onAppear { proxy.scrollTo(8, anchor: .top) }
        }
    }

    private func entries(on day: Date) -> [TimeEntry] {
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        return store.data.visibleEntries(at: store.now).filter { $0.start < next && $0.end >= day }
    }
    private func moveWeek(_ offset: Int) { week = calendar.date(byAdding: .day, value: offset * 7, to: week)! }
    private func newProject() {
        store.error = nil; showNewProject = true
        projectDraft = Project(name: "", color: Palette.names[store.data.projects.count % Palette.names.count])
    }
    private func addTime(at start: Date) {
        store.error = nil
        guard start < Date() else { store.error = "Choose a time in the past to add a block."; return }
        let rounded = calendar.date(bySetting: .second, value: 0, of: start) ?? start
        entryDraft = EntryDraft(entry: TimeEntry(projectID: store.data.selectedProjectID, start: rounded,
                                                end: min(rounded.addingTimeInterval(3600), Date())), existing: false)
    }
}

private struct DayColumn: View {
    let day: Date
    let hourHeight: CGFloat
    let entries: [TimeEntry]
    let project: (UUID) -> Project
    let activeID: UUID?
    let now: Date
    let edit: (TimeEntry) -> Void
    let add: (Date) -> Void
    private var calendar: Calendar { Calendar.current }
    private var nextDay: Date { calendar.date(byAdding: .day, value: 1, to: day)! }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(calendar.isDateInToday(day) ? Color.accentColor.opacity(0.025) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let minute = min(1439, max(0, Int(location.y / hourHeight * 60) / 15 * 15))
                        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
                        add(date)
                    }
                Path { path in
                    path.move(to: .zero); path.addLine(to: CGPoint(x: 0, y: hourHeight * 24))
                    for hour in 0...24 {
                        let y = CGFloat(hour) * hourHeight
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }.stroke(Color.primary.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false)
                let layouts = blockLayouts()
                ForEach(layouts) { layout in
                    let entry = layout.entry
                    let p = project(entry.projectID)
                    let color = Palette.color(p.color)
                    let width = max(20, (geometry.size.width - 6) / CGFloat(layout.laneCount) - 2)
                    Button { edit(entry) } label: {
                        HStack(alignment: .top, spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 3) {
                                    if entry.id == activeID { Image(systemName: "timer").font(.system(size: 9)) }
                                    Text(p.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                }
                                if layout.height >= 40 {
                                    Text("\(compactTime(entry.start))–\(entry.id == activeID ? "now" : compactTime(entry.end))")
                                        .font(.system(size: 9)).lineLimit(1)
                                }
                                if layout.height >= 60 {
                                    Text(TimeFormat.short(entry.duration)).font(.system(size: 10)).opacity(0.75).lineLimit(1)
                                }
                            }.padding(.vertical, layout.height < 30 ? 2 : 6)
                            Spacer(minLength: 0)
                        }.padding(.leading, 3).padding(.trailing, 3)
                            .frame(width: width, height: layout.height, alignment: .topLeading)
                            .foregroundStyle(color)
                            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(entry.id == activeID ? 0.65 : 0.12)))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .offset(x: 3 + CGFloat(layout.lane) * (width + 2), y: layout.y)
                        .help("\(p.name) · \(entry.start.formatted()) – \(entry.end.formatted())\nClick to edit")
                        .accessibilityLabel("\(p.name), \(TimeFormat.short(entry.duration)), \(entry.start.formatted()). Edit time block")
                }
                if calendar.isDateInToday(day) {
                    Rectangle().fill(Color.accentColor.opacity(0.7)).frame(height: 1)
                        .overlay(alignment: .leading) { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                        .offset(y: position(now)).allowsHitTesting(false)
                }
            }
        }.frame(height: hourHeight * 24)
    }

    private func position(_ date: Date) -> CGFloat {
        if date >= nextDay { return 24 * hourHeight }
        if date < day { return 0 }
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (CGFloat(parts.hour ?? 0) + CGFloat(parts.minute ?? 0) / 60 + CGFloat(parts.second ?? 0) / 3600) * hourHeight
    }
    private func compactTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }
    private struct BlockLayout: Identifiable {
        let entry: TimeEntry
        let y: CGFloat
        let height: CGFloat
        let lane: Int
        var laneCount = 1
        var id: UUID { entry.id }
    }
    private func blockLayouts() -> [BlockLayout] {
        var bottoms: [CGFloat] = []
        var result: [BlockLayout] = []
        var groupStart = 0
        for entry in entries.sorted(by: { position($0.start) < position($1.start) }) {
            let top = position(max(day, entry.start))
            let height = max(20, position(min(nextDay, entry.end)) - top - 2)
            if top >= (bottoms.max() ?? 0) {
                for index in groupStart..<result.count { result[index].laneCount = max(1, bottoms.count) }
                groupStart = result.count
                bottoms = []
            }
            let lane = bottoms.firstIndex(where: { $0 <= top }) ?? bottoms.count
            if lane == bottoms.count { bottoms.append(top + height + 2) } else { bottoms[lane] = top + height + 2 }
            result.append(BlockLayout(entry: entry, y: top, height: height, lane: lane))
        }
        for index in groupStart..<result.count { result[index].laneCount = max(1, bottoms.count) }
        return result
    }
}
