import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ReadingPlanStore
    @AppStorage private var youVersionEnabled: Bool
    @AppStorage private var logosEnabled: Bool
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(store: ReadingPlanStore) {
        self.store = store
        _youVersionEnabled = AppStorage(wrappedValue: true, AppPreferenceKey.youVersionEnabled, store: store.preferences)
        _logosEnabled = AppStorage(wrappedValue: false, AppPreferenceKey.logosEnabled, store: store.preferences)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ReadingPlanTheme.background.ignoresSafeArea()
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

                            ForEach(store.state.selectedPlanIDs, id: \.self) { id in
                                if let reading = store.reading(for: id) {
                                    ReadingCard(plan: reading.plan, day: reading.day, dayIndex: reading.dayIndex,
                                                showsYouVersion: youVersionEnabled, showsLogos: logosEnabled,
                                                openYouVersion: openYouVersionURL, openLogos: openLogosURL)
                                        .opacity(hasAppeared ? 1 : 0)
                                        .offset(y: hasAppeared ? 0 : 14)
                                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
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
            }
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion { hasAppeared = true }
                else { withAnimation(.easeOut(duration: 0.35)) { hasAppeared = true } }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.state.selectedPlanIDs)
            .navigationTitle("Bible Reading Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ReadingPlanSelectionView(store: store)) {
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
    }

    private func openYouVersionURL(book: String, chapter: Int) {
        if let url = URL(string: "youversion://bible?reference=\(book).\(chapter)") { openURL(url) }
    }

    private func openLogosURL(book: String, chapter: Int) {
        let bookName = osisToUserFriendlyNames[book] ?? book
        let reference = "Bible.\(bookName).\(chapter)"
        let encodedReference = reference.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reference
        if let url = URL(string: "logosres:esv?ref=\(encodedReference)") { openURL(url) }
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

#Preview("Today’s Readings") {
    ContentView(store: .preview())
}

#Preview("No Reading Plans") {
    ContentView(store: .preview(selected: false))
}
