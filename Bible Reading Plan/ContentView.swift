//
//  ContentView.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // Legacy single-plan storage for migration
    @AppStorage("savedPlan", store: AppGroup.defaults) var legacySavedPlan: Int = 0
    @AppStorage("savedDay", store: AppGroup.defaults) var legacySavedDay: Int = 0

    @AppStorage(ReadingPlanStateStore.stateKey, store: AppGroup.defaults) private var readingPlanStateData: Data = Data()
    @AppStorage(AppPreferenceKey.youVersionEnabled, store: AppGroup.defaults) private var youVersionEnabled: Bool = true
    @AppStorage(AppPreferenceKey.logosEnabled, store: AppGroup.defaults) private var logosEnabled: Bool = false

    @State private var readingPlans: [ReadingPlan] = []

    // MARK: - Persistence helpers
    private func loadState() -> ReadingPlanState {
        _ = readingPlanStateData
        return ReadingPlanStateStore.load(from: AppGroup.defaults)
    }

    private func saveState(_ state: ReadingPlanState) {
        ReadingPlanStateStore.save(state, to: AppGroup.defaults)
    }

    // MARK: - Data
    private func loadReadingPlans() {
        readingPlans = ReadingPlanService.shared.loadReadingPlans()
        migrateLegacyIfNeeded()
    }

    private func migrateLegacyIfNeeded() {
        let state = loadState()
        let result = ReadingPlanMigration.migrateLegacyIfNeeded(
            selectedPlanIds: state.selectedPlanIds,
            progressMap: state.progressByPlan,
            legacyPlanId: legacySavedPlan,
            legacyDay: legacySavedDay
        )

        if result.didMigrate {
            let updated = ReadingPlanState(
                selectedPlanIds: result.selectedPlanIds,
                progressByPlan: result.progressMap
            )
            saveState(updated)
        }

        if legacySavedPlan != result.legacyPlanId {
            legacySavedPlan = result.legacyPlanId
        }
        if legacySavedDay != result.legacyDay {
            legacySavedDay = result.legacyDay
        }
    }

    // MARK: - View
    var body: some View {
        NavigationView {
            ScrollView {
                let state = loadState()
                let selectedIds = state.selectedPlanIds
                let progress = state.progressByPlan
                if selectedIds.isEmpty {
                    VStack(spacing: 12) {
                        Text("Select Reading Plans")
                            .font(.title)
                        Text("Use the menu to choose one or more plans.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Today's Readings")
                            .font(.title)
                        ForEach(selectedIds, id: \.self) { planId in
                            if let plan = readingPlans.first(where: { $0.id == planId }) {
                                let dayIndex = min(progress[planId] ?? 0, max(plan.days.count - 1, 0))
                                if plan.days.indices.contains(dayIndex) {
                                    let day = plan.days[dayIndex]
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(plan.name)
                                            .font(.headline)
                                        Text(day.toString())
                                            .font(.title3)
                                        if youVersionEnabled || logosEnabled {
                                            VStack(alignment: .leading, spacing: 8) {
                                                if youVersionEnabled {
                                                    Button(action: {
                                                        openYouVersionURL(book: day.book, chapter: day.startChapter)
                                                    }) {
                                                        Text("Open in YouVersion")
                                                            .font(.subheadline)
                                                            .padding(8)
                                                            .background(Color.blue)
                                                            .foregroundColor(.white)
                                                            .cornerRadius(8)
                                                    }
                                                }
                                                if logosEnabled {
                                                    Button(action: {
                                                        openLogosURL(book: day.book, chapter: day.startChapter)
                                                    }) {
                                                        Text("Open in Logos Bible")
                                                            .font(.subheadline)
                                                            .padding(8)
                                                            .background(Color.orange)
                                                            .foregroundColor(.white)
                                                            .cornerRadius(8)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .onAppear(perform: loadReadingPlans)
            .navigationTitle("Bible Reading Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ReadingPlanSelectionView(
                        readingPlans: $readingPlans
                    )) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // Function to open YouVersion URL
    private func openYouVersionURL(book: String, chapter: Int) {
        // Construct the URL
        if let url = URL(string: "youversion://bible?reference=\(book).\(chapter)") {
            // Open the URL
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func openLogosURL(book: String, chapter: Int) {
        let bookName = osisToUserFriendlyNames[book] ?? book
        let reference = "Bible.\(bookName).\(chapter)"
        let encodedReference = reference.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reference
        if let url = URL(string: "logosres:esv?ref=\(encodedReference)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

#Preview {
    ContentView()
}

struct ReadingPlanSelectionView: View {
    @Binding var readingPlans: [ReadingPlan]
    @State private var showingImporter: Bool = false
    @State private var importErrorMessage: String?
    @State private var pendingDeletePlan: ReadingPlan?
    @AppStorage(ReadingPlanStateStore.stateKey, store: AppGroup.defaults) private var readingPlanStateData: Data = Data()
    @AppStorage(AppPreferenceKey.youVersionEnabled, store: AppGroup.defaults) private var youVersionEnabled: Bool = true
    @AppStorage(AppPreferenceKey.logosEnabled, store: AppGroup.defaults) private var logosEnabled: Bool = false

    // Helpers
    private func loadState() -> ReadingPlanState {
        _ = readingPlanStateData
        return ReadingPlanStateStore.load(from: AppGroup.defaults)
    }

    private func updateState(_ update: (inout ReadingPlanState) -> Void) {
        ReadingPlanStateStore.update(in: AppGroup.defaults, update)
    }

    private var iCloudStatusText: String {
        if !ReadingPlanCloudSync.isEnabled {
            return "Off"
        }
        return ReadingPlanCloudSync.isAvailable ? "On" : "Unavailable"
    }

    private var lastUpdatedText: String {
        let timestamp = ReadingPlanStateStore.lastUpdatedTimestamp(in: AppGroup.defaults)
        guard timestamp > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        let state = loadState()
        List {
            ForEach(readingPlans, id: \.id) { plan in
                let isSelected = state.selectedPlanIds.contains(plan.id)
                VStack(alignment: .leading) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { loadState().selectedPlanIds.contains(plan.id) },
                            set: { newValue in
                                updateState { state in
                                    if newValue {
                                        if !state.selectedPlanIds.contains(plan.id) {
                                            state.selectedPlanIds.append(plan.id)
                                        }
                                        if state.progressByPlan[plan.id] == nil {
                                            state.progressByPlan[plan.id] = 0
                                        }
                                    } else {
                                        state.selectedPlanIds.removeAll { $0 == plan.id }
                                        state.progressByPlan.removeValue(forKey: plan.id)
                                    }
                                }
                            }
                        )) {
                            Text(plan.name)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if ReadingPlanService.shared.isImported(planId: plan.id) {
                            Button(role: .destructive) {
                                pendingDeletePlan = plan
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if isSelected {
                        let progress = state.progressByPlan
                        let selection = progress[plan.id] ?? 0
                        Picker("Select Day", selection: Binding(
                            get: {
                                let value = loadState().progressByPlan[plan.id] ?? 0
                                return min(value, max(plan.days.count - 1, 0))
                            },
                            set: { newValue in
                                updateState { state in
                                    state.progressByPlan[plan.id] = newValue
                                }
                            }
                        )) {
                            ForEach(plan.days.indices, id: \.self) { dayIndex in
                                dayLabel(for: plan.days[dayIndex], at: dayIndex)
                                    .tag(dayIndex)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                    }
                }
            }
            Section("Bible Apps") {
                Toggle("YouVersion", isOn: $youVersionEnabled)
                Toggle("Logos Bible", isOn: $logosEnabled)
            }
            Section("iCloud Sync") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(iCloudStatusText)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Last Update")
                    Spacer()
                    Text(lastUpdatedText)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Manage Plans")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingImporter = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        _ = try ReadingPlanService.shared.importReadingPlan(from: url)
                        // Refresh list of plans after import
                        readingPlans = ReadingPlanService.shared.loadReadingPlans()
                    } catch {
                        importErrorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert("Import Error", isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        .alert("Delete Imported Plan?", isPresented: Binding(get: { pendingDeletePlan != nil }, set: { if !$0 { pendingDeletePlan = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeletePlan = nil }
            Button("Delete", role: .destructive) {
                        if let plan = pendingDeletePlan {
                            do {
                                readingPlans = try ReadingPlanService.shared.deletePlan(withId: plan.id)
                                // Remove from selection and progress if deleted
                                updateState { state in
                                    state.selectedPlanIds.removeAll { $0 == plan.id }
                                    state.progressByPlan.removeValue(forKey: plan.id)
                                }
                            } catch {
                                importErrorMessage = error.localizedDescription
                            }
                        }
                pendingDeletePlan = nil
            }
        } message: {
            Text("This will remove the imported plan file. If the file contains multiple plans, only this plan will be removed.")
        }
    }

    private func dayLabel(for day: Day, at index: Int) -> Text {
        return Text("Day \(index + 1): \(day.toString())")
    }
}
