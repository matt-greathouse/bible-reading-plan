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
    @AppStorage("savedPlan", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var legacySavedPlan: Int = 0
    @AppStorage("savedDay", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var legacySavedDay: Int = 0

    // New multi-plan storage
    @AppStorage("selectedPlans", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) private var selectedPlansJSON: String = "[]"
    @AppStorage("progressByPlan", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) private var progressByPlanJSON: String = "{}"

    @State private var readingPlans: [ReadingPlan] = []

    // MARK: - Persistence helpers
    private func getSelectedPlanIds() -> [Int] {
        if let data = selectedPlansJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([Int].self, from: data) {
            return ids
        }
        return []
    }

    private func setSelectedPlanIds(_ ids: [Int]) {
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            selectedPlansJSON = json
        }
    }

    private func getProgressMap() -> [Int: Int] {
        if let data = progressByPlanJSON.data(using: .utf8),
           let map = try? JSONDecoder().decode([Int: Int].self, from: data) {
            return map
        }
        return [:]
    }

    private func setProgressMap(_ map: [Int: Int]) {
        if let data = try? JSONEncoder().encode(map),
           let json = String(data: data, encoding: .utf8) {
            progressByPlanJSON = json
        }
    }

    // MARK: - Data
    private func loadReadingPlans() {
        readingPlans = ReadingPlanService.shared.loadReadingPlans()
        migrateLegacyIfNeeded()
    }

    private func migrateLegacyIfNeeded() {
        var ids = getSelectedPlanIds()
        var map = getProgressMap()

        if ids.isEmpty && legacySavedPlan != 0 {
            ids = [legacySavedPlan]
            map[legacySavedPlan] = legacySavedDay
            setSelectedPlanIds(ids)
            setProgressMap(map)
        }
    }

    // MARK: - View
    var body: some View {
        NavigationView {
            ScrollView {
                let selectedIds = getSelectedPlanIds()
                let progress = getProgressMap()
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
                                        Button(action: {
                                            openYouVersionURL(book: day.book, chapter: day.startChapter)
                                        }) {
                                            Text("Open in Bible App")
                                                .font(.subheadline)
                                                .padding(8)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
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
                        readingPlans: $readingPlans,
                        selectedPlansJSON: $selectedPlansJSON,
                        progressByPlanJSON: $progressByPlanJSON
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
}

#Preview {
    ContentView()
}

struct ReadingPlanSelectionView: View {
    @Binding var readingPlans: [ReadingPlan]
    @Binding var selectedPlansJSON: String
    @Binding var progressByPlanJSON: String
    @State private var showingImporter: Bool = false
    @State private var importErrorMessage: String?
    @State private var pendingDeletePlan: ReadingPlan?

    // Helpers
    private func getSelectedPlanIds() -> [Int] {
        if let data = selectedPlansJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([Int].self, from: data) {
            return ids
        }
        return []
    }

    private func setSelectedPlanIds(_ ids: [Int]) {
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            selectedPlansJSON = json
        }
    }

    private func getProgressMap() -> [Int: Int] {
        if let data = progressByPlanJSON.data(using: .utf8),
           let map = try? JSONDecoder().decode([Int: Int].self, from: data) {
            return map
        }
        return [:]
    }

    private func setProgressMap(_ map: [Int: Int]) {
        if let data = try? JSONEncoder().encode(map),
           let json = String(data: data, encoding: .utf8) {
            progressByPlanJSON = json
        }
    }

    var body: some View {
        List {
            ForEach(readingPlans, id: \.id) { plan in
                let isSelected = getSelectedPlanIds().contains(plan.id)
                VStack(alignment: .leading) {
                    HStack {
                        Toggle(isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                var ids = getSelectedPlanIds()
                                var progress = getProgressMap()
                                if newValue {
                                    if !ids.contains(plan.id) { ids.append(plan.id) }
                                    if progress[plan.id] == nil { progress[plan.id] = 0 }
                                } else {
                                    ids.removeAll { $0 == plan.id }
                                    progress.removeValue(forKey: plan.id)
                                }
                                setSelectedPlanIds(ids)
                                setProgressMap(progress)
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
                        let progress = getProgressMap()
                        let selection = progress[plan.id] ?? 0
                        Picker("Select Day", selection: Binding(
                            get: { min(selection, max(plan.days.count - 1, 0)) },
                            set: { newValue in
                                var map = getProgressMap()
                                map[plan.id] = newValue
                                setProgressMap(map)
                            }
                        )) {
                            ForEach(plan.days.indices, id: \.self) { dayIndex in
                                dayLabel(for: plan.days[dayIndex], at: dayIndex)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                    }
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
                        var ids = getSelectedPlanIds()
                        var map = getProgressMap()
                        ids.removeAll { $0 == plan.id }
                        map.removeValue(forKey: plan.id)
                        setSelectedPlanIds(ids)
                        setProgressMap(map)
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
