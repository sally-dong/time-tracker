import ServiceManagement
import SwiftUI
import TrackerCore

struct MenuView: View {
    @EnvironmentObject private var store: TrackerStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TIME TRACKER").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(store.isRunning ? "Running" : "Paused").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(TimeFormat.clock(store.todayTotal)).font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                Text("Today on \(store.selectedProject.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Picker("Project", selection: Binding(get: { store.data.selectedProjectID }, set: { store.select($0) })) {
                ForEach(store.data.projects) { project in
                    HStack { ProjectDot(project: project); Text(project.name) }.tag(project.id)
                }
            }.labelsHidden().frame(maxWidth: .infinity)
            Button(action: store.toggle) {
                Label(store.isRunning ? "Pause timer" : "Start timer", systemImage: store.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent).tint(Palette.color(store.selectedProject.color)).controlSize(.large)
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            } else if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Open calendar", action: store.openCalendar).buttonStyle(.plain)
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
            }.contentShape(Rectangle()).onTapGesture(perform: store.openCalendar)
            HStack {
                Button("New project…", action: store.openProjects).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLoginEnabled))
                    if store.loginStatus == .requiresApproval {
                        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Button("Reveal data file", action: store.revealData)
                    Divider()
                    Button("Quit Time Tracker") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).fixedSize().help("Settings")
            }.font(.caption)
        }.padding(20).frame(width: 300)
    }
}
