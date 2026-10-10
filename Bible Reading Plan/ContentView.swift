import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ReadingPlanStore
    private let launcher: BibleReadingLauncher
    @AppStorage private var preferredBibleApp: String
    @ObservedObject private var routes = ReadingRouteHandler.shared
    @State private var navigationPath = NavigationPath()
    @State private var focusedPlanID: String?
    @State private var focusToken = UUID()
    @State private var routeMessage: String?
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    init(store: ReadingPlanStore, launcher: BibleReadingLauncher? = nil) {
        self.store = store
        self.launcher = launcher ?? BibleReadingLauncher()
        _preferredBibleApp = AppStorage(wrappedValue: BibleApp.migrate(in: store.preferences).rawValue, BibleApp.preferenceKey, store: store.preferences)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ReadingPlanTheme.background.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        if store.state.selectedPlanIDs.isEmpty && store.state.unresolvedSelectedIDs.isEmpty {
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

                                if let routeMessage {
                                    Text(routeMessage).font(.subheadline).foregroundStyle(ReadingPlanTheme.secondaryText)
                                }
                                ForEach(store.state.selectedPlanIDs, id: \.self) { id in
                                    if let reading = store.reading(for: id) {
                                        ReadingCard(plan: reading.plan, day: reading.day, dayIndex: reading.dayIndex,
                                                    preferredApp: BibleApp(rawValue: preferredBibleApp) ?? .youVersion, launcher: launcher)
                                            .opacity(hasAppeared ? 1 : 0)
                                            .offset(y: hasAppeared ? 0 : 14)
                                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                                            .id(id)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: ReadingPlanTheme.cardCornerRadius)
                                                    .stroke(focusedPlanID == id ? ReadingPlanTheme.accent : .clear, lineWidth: 2)
                                            }
                                            .accessibilityIdentifier("reading-" + id)
                                    } else {
                                        Text("This reading plan is downloading or unavailable. Open Manage Plans to check iCloud sync.")
                                            .foregroundStyle(ReadingPlanTheme.secondaryText)
                                            .padding()
                                    }
                                }
                                if !store.state.unresolvedSelectedIDs.isEmpty {
                                    Text("Some older selections could not be matched safely. Your original progress has been preserved. Reimport the original plans or choose a plan in Manage Plans.")
                                        .foregroundStyle(ReadingPlanTheme.secondaryText)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 20)
                        }
                    }
                    .task(id: focusToken) {
                        guard let id = focusedPlanID else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        if reduceMotion { proxy.scrollTo(id, anchor: .top) }
                        else { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                    }
                }
            }
            .navigationDestination(for: String.self) { _ in ReadingPlanSelectionView(store: store) }
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion { hasAppeared = true }
                else { withAnimation(.easeOut(duration: 0.35)) { hasAppeared = true } }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.state.selectedPlanIDs)
            .navigationTitle("Bible Reading Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: "manage-plans") {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage Plans")
                    .accessibilityIdentifier("manage-plans")
                }
            }
            .tint(ReadingPlanTheme.accent)
            .alert("Reading Plan Error", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "Unknown error") }
        }
        .task(id: routes.pending?.token) {
            guard let route = routes.pending else { return }
            navigationPath = NavigationPath()
            await store.prepareReadingRoute()
            guard !Task.isCancelled else { return }
            if store.state.selectedPlanIDs.contains(route.planID), store.reading(for: route.planID) != nil {
                routeMessage = nil
                focusedPlanID = route.planID
                // Allow the scroll view to lay out newly loaded cards before scrolling.
                await Task.yield()
                focusToken = UUID()
            } else {
                focusedPlanID = nil
                routeMessage = "This plan is no longer selected or is unavailable. Open Manage Plans to check it."
                store.errorMessage = routeMessage
            }
        }
        .task(id: focusToken) {
            guard focusedPlanID != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            focusedPlanID = nil
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
    let preferredApp: BibleApp
    var launcher = BibleReadingLauncher()
    @State private var failedApp: BibleApp?
    @State private var opening = false

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

            HStack(spacing: 10) {
                Button { launch(preferredApp) } label: {
                    Label("Read in " + preferredApp.title, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReadingPlanTheme.accent)
                .disabled(opening)
                Menu {
                    Button("Open in " + preferredApp.alternate.title) { launch(preferredApp.alternate) }
                    Button("Copy Passage", systemImage: "doc.on.doc") { UIPasteboard.general.string = day.toString() }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel("More reading options")
            }
            if let failedApp {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t open " + failedApp.title + ". Try another Bible app or copy the passage.")
                        .font(.footnote).foregroundStyle(ReadingPlanTheme.secondaryText)
                    HStack {
                        Button("Open in " + failedApp.alternate.title) { launch(failedApp.alternate) }
                        Button("Copy Passage") { UIPasteboard.general.string = day.toString() }
                    }.font(.footnote)
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

    private func launch(_ app: BibleApp) {
        opening = true
        Task {
            let success = await launcher.open(day, in: app)
            failedApp = success ? nil : app
            opening = false
        }
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

#Preview("Today’s Readings") {
    ContentView(store: .preview())
}

#Preview("No Reading Plans") {
    ContentView(store: .preview(selected: false))
}
