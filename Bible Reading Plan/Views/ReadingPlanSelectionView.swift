import SwiftUI
import UniformTypeIdentifiers

struct ReadingPlanSelectionView: View {
    @ObservedObject var store: ReadingPlanStore
    @State private var showingImporter = false
    @State private var pendingDeletePlan: CatalogPlan?
    @AppStorage private var youVersionEnabled: Bool
    @AppStorage private var logosEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ReadingPlanStore) {
        self.store = store
        _youVersionEnabled = AppStorage(wrappedValue: true, AppPreferenceKey.youVersionEnabled, store: store.preferences)
        _logosEnabled = AppStorage(wrappedValue: false, AppPreferenceKey.logosEnabled, store: store.preferences)
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
                    }
                }
                .listRowBackground(ReadingPlanTheme.card)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isSelected)
            }
            Section("Bible Apps") {
                Toggle("YouVersion", isOn: $youVersionEnabled)
                Toggle("Logos Bible", isOn: $logosEnabled)
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
