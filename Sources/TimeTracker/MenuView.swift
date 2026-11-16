import SwiftUI
import TrackerCore

struct MenuView: View {
    @EnvironmentObject private var store: TrackerStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel("TIME TRACKER")
                Spacer()
                Text(store.isRunning ? "Running" : "Paused").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .center) {
                Text(TimeFormat.clock(store.todayTotal)).font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                    .lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                Picker("Project", selection: Binding(get: { store.data.selectedProjectID }, set: { store.select($0) })) {
                    ForEach(store.data.projects) { project in
                        HStack { ProjectDot(project: project); Text(project.name) }.tag(project.id)
                    }
                }.labelsHidden()
            }
            TimerButton()
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
        }.padding(20).frame(width: 340)
    }
}
