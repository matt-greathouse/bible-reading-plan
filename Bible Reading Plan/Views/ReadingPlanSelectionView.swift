import SwiftUI
import UniformTypeIdentifiers

struct ReadingPlanSelectionView: View {
    @ObservedObject var store: ReadingPlanStore
    @ObservedObject private var reminders: ReadingReminderManager
    @State private var editingReminder: CatalogPlan?
    @State private var showingImporter = false
    @State private var pendingDeletePlan: CatalogPlan?
    @AppStorage private var preferredBibleApp: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ReadingPlanStore) {
        self.store = store
        self.reminders = store.reminders
        _preferredBibleApp = AppStorage(wrappedValue: BibleApp.migrate(in: store.preferences).rawValue, BibleApp.preferenceKey, store: store.preferences)
    }

    var body: some View {
        List {
            ForEach(store.plans) { item in
                let isSelected = store.state.selectedPlanIDs.contains(item.id)
                VStack(alignment: .leading) {
                    Toggle(isOn: Binding(
                        get: { store.state.selectedPlanIDs.contains(item.id) },
                        set: { enabled in Task { await store.select(item.id, enabled: enabled) } }
                    )) { Text(item.plan.name) }
                    .accessibilityIdentifier("select-" + item.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.isImported {
                            Button(role: .destructive) { pendingDeletePlan = item } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if isSelected {
                        Picker("Select Day", selection: Binding(
                            get: { store.reading(for: item.id)?.dayIndex ?? 0 },
                            set: { index in store.chooseDay(index, for: item.id) }
                        )) {
                            ForEach(item.plan.days.indices, id: \.self) { index in
                                Text("Day \(index + 1): \(item.plan.days[index].toString())").tag(index)
                            }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityIdentifier("day-" + item.id)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        Button { editingReminder = item } label: {
                            HStack {
                                Label("Reminder", systemImage: "bell")
                                Spacer()
                                Text(reminders.summary(for: item.id)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reminder-" + item.id)
                        if reminders.blocked && reminders.configuration(for: item.id).enabled,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Notification Settings", destination: url).font(.footnote)
                        }
                    }
                }
                .listRowBackground(ReadingPlanTheme.card)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isSelected)
            }
            Section("Bible App") {
                Picker("Preferred Bible App", selection: $preferredBibleApp) {
                    ForEach(BibleApp.allCases) { app in Text(app.title).tag(app.rawValue) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("preferred-bible-app")
            }
            Section("iCloud Sync") {
                LabeledContent("Status", value: store.syncStatus)
                LabeledContent("Changes Pending", value: String(store.pendingCount))
                LabeledContent("Last Update", value: store.lastSuccessfulSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                if let failure = store.syncFailure {
                    Text(failure).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !store.loadErrors.isEmpty {
                Section("Plan Loading Errors") {
                    ForEach(store.loadErrors, id: \.self) { Text($0).font(.footnote) }
                }
            }
            if !store.state.unresolvedSelectedIDs.isEmpty || !store.state.unresolvedProgress.isEmpty {
                Section("Preserved Progress") {
                    Text("Some older plan IDs could not be matched uniquely. Original files and progress are backed up; they have not been assigned to another plan.")
                        .font(.footnote)
                }
            }
            if store.uiTesting {
                Button("Import Test Fixture") { Task { await store.importTestFixture() } }
                    .accessibilityIdentifier("import-test-fixture")
                Button("Open Test Reading Route") {
                    if let id = store.state.selectedPlanIDs.last, let url = ReadingRoute.url(planID: id) {
                        ReadingRouteHandler.shared.open(url: url)
                    }
                }
                .accessibilityIdentifier("open-test-reading-route")
            }
        }
        .scrollContentBackground(.hidden)
        .background(ReadingPlanTheme.background)
        .listStyle(.insetGrouped)
        .navigationTitle("Manage Plans")
        .tint(ReadingPlanTheme.accent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Import Reading Plan")
            }
        }
        .onChange(of: preferredBibleApp) { _, _ in Task { await store.reconcileReminders() } }
        .sheet(item: $editingReminder) { PlanReminderEditor(store: store, plan: $0) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await store.importPlan(from: url) }
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .alert("Delete Imported Plan?", isPresented: Binding(get: { pendingDeletePlan != nil }, set: { if !$0 { pendingDeletePlan = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeletePlan = nil }
            Button("Delete", role: .destructive) {
                if let item = pendingDeletePlan { Task { await store.delete(item.id) } }
                pendingDeletePlan = nil
            }
        } message: {
            Text("This removes this plan and its progress from all your devices when iCloud sync completes. Other plans from the same import will remain.")
        }
    }
}

#Preview("Manage Plans") {
    NavigationStack { ReadingPlanSelectionView(store: .preview()) }
}
