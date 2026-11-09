import SwiftUI
import TrackerCore

struct EntryDraft: Identifiable {
    let id: UUID
    var projectID: UUID
    var start: Date
    var end: Date
    var existing: Bool
    var running: Bool
    init(entry: TimeEntry, existing: Bool = true, running: Bool = false) {
        id = entry.id; projectID = entry.projectID; start = entry.start; end = entry.end
        self.existing = existing; self.running = running
    }
}

struct EntryEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: EntryDraft
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.existing ? "Edit time" : "Add time").font(.title2.weight(.semibold))
                Text(draft.running ? "Saving this block will pause its timer." : "Choose a project and adjust the start and end time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Form {
                Picker("Project", selection: $draft.projectID) {
                    ForEach(store.data.projects) { Text($0.name).tag($0.id) }
                }
                DatePicker("Start", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
            }.formStyle(.columns)
            HStack {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(TimeFormat.short(draft.end.timeIntervalSince(draft.start))).font(.callout.weight(.medium))
                Spacer()
            }
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                if draft.existing {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { store.error = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.running ? "Save & pause" : "Save") {
                    let entry = TimeEntry(id: draft.id, projectID: draft.projectID, start: draft.start, end: draft.end)
                    if store.save(entry) { store.error = nil; dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
        .alert("Delete this time block?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { if store.delete(draft.id) { dismiss() } }
        } message: { Text("This removes \(TimeFormat.short(draft.end.timeIntervalSince(draft.start))) from your calendar.") }
    }
}

struct ProjectEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    var isNew: Bool
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(isNew ? "New project" : "Edit project").font(.title2.weight(.semibold))
            TextField("Project name", text: $project.name).textFieldStyle(.roundedBorder).focused($nameFocused)
            VStack(alignment: .leading, spacing: 10) {
                Text("Color").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Palette.names, id: \.self) { name in
                        Button { project.color = name } label: {
                            Circle().fill(Palette.color(name)).frame(width: 27, height: 27)
                                .overlay { if project.color == name { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } }
                        }.buttonStyle(.plain).help(name.capitalized).accessibilityLabel(name.capitalized)
                    }
                }
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { store.error = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create project" : "Save") {
                    if store.save(project) { store.error = nil; dismiss() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 360).onAppear { nameFocused = true }
    }
}
