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
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        NavigationStack {
            ZStack {
                ReadingPlanTheme.background
                    .ignoresSafeArea()

                ScrollView {
                let state = loadState()
                let selectedIds = state.selectedPlanIds
                let progress = state.progressByPlan
                if selectedIds.isEmpty {
                    EmptyReadingPlansView()
                        .padding(.top, 96)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: ReadingPlanTheme.cardSpacing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today’s Readings")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(ReadingPlanTheme.primaryText)
                            Text("A quiet place to begin your day.")
                                .font(.subheadline)
                                .foregroundStyle(ReadingPlanTheme.secondaryText)
                        }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                        ForEach(selectedIds, id: \.self) { planId in
                            if let plan = readingPlans.first(where: { $0.id == planId }) {
                                let dayIndex = min(progress[planId] ?? 0, max(plan.days.count - 1, 0))
                                if plan.days.indices.contains(dayIndex) {
                                    ReadingCard(
                                        plan: plan,
                                        day: plan.days[dayIndex],
                                        dayIndex: dayIndex,
                                        showsYouVersion: youVersionEnabled,
                                        showsLogos: logosEnabled,
                                        openYouVersion: openYouVersionURL,
                                        openLogos: openLogosURL
                                    )
                                    .opacity(hasAppeared ? 1 : 0)
                                    .offset(y: hasAppeared ? 0 : 14)
                                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 20)
                }
            }
            }
            .onAppear(perform: loadReadingPlans)
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.35)) {
                        hasAppeared = true
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedIdsForAnimation)
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
            .tint(ReadingPlanTheme.accent)
        }
    }

    private var selectedIdsForAnimation: [Int] {
        loadState().selectedPlanIds
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

private struct EmptyReadingPlansView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ReadingPlanTheme.accent)
                .padding(16)
                .background(ReadingPlanTheme.card, in: Circle())

            Text("Select Reading Plans")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ReadingPlanTheme.primaryText)
            Text("Choose one or more plans from the menu to see today’s readings here.")
                .font(.subheadline)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
        }
        .padding(28)
    }
}

private struct ReadingCard: View {
    let plan: ReadingPlan
    let day: Day
    let dayIndex: Int
    let showsYouVersion: Bool
    let showsLogos: Bool
    let openYouVersion: (String, Int) -> Void
    let openLogos: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(ReadingPlanTheme.primaryText)
                    .lineLimit(2)
                Spacer(minLength: 8)
                DayBadge(day: dayIndex + 1, total: plan.days.count)
            }

            Text(day.toString())
                .font(.title3.weight(.medium))
                .foregroundStyle(ReadingPlanTheme.primaryText)

            ReadingProgressBar(currentDay: dayIndex + 1, totalDays: plan.days.count)

            if showsYouVersion || showsLogos {
                HStack(spacing: 10) {
                    if showsYouVersion {
                        DestinationLinkButton(title: "YouVersion", icon: "arrow.up.right") {
                            openYouVersion(day.book, day.startChapter)
                        }
                    }
                    if showsLogos {
                        DestinationLinkButton(title: "Logos Bible", icon: "arrow.up.right") {
                            openLogos(day.book, day.startChapter)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(ReadingPlanTheme.card, in: RoundedRectangle(cornerRadius: ReadingPlanTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReadingPlanTheme.cardCornerRadius, style: .continuous)
                .stroke(ReadingPlanTheme.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
    }
}

private struct DayBadge: View {
    let day: Int
    let total: Int

    var body: some View {
        Text("Day \(day) of \(max(total, 1))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ReadingPlanTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(ReadingPlanTheme.accent.opacity(0.11), in: Capsule())
            .accessibilityLabel("Day \(day) of \(max(total, 1))")
    }
}

private struct ReadingProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let currentDay: Int
    let totalDays: Int

    private var progress: Double {
        guard totalDays > 0 else { return 0 }
        return min(max(Double(currentDay) / Double(totalDays), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ReadingPlanTheme.progressTrack)
                    Capsule()
                        .fill(ReadingPlanTheme.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 5)

            Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: progress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading plan progress, \(currentDay) of \(max(totalDays, 1)) days, \(Int(progress * 100)) percent complete")
    }
}

private struct DestinationLinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(ReadingPlanButtonStyle())
    }
}

private struct ReadingPlanButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ReadingPlanTheme.accent)
            .background(ReadingPlanTheme.accent.opacity(configuration.isPressed ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: ReadingPlanTheme.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReadingPlanTheme.compactCornerRadius, style: .continuous)
                    .stroke(ReadingPlanTheme.accent.opacity(0.2), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .scrollContentBackground(.hidden)
        .background(ReadingPlanTheme.background)
        .listStyle(.insetGrouped)
        .navigationTitle("Manage Plans")
        .tint(ReadingPlanTheme.accent)
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
