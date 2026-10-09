//
//  Bible_Reading_Plan_Widget.swift
//  Bible Reading Plan Widget
//
//  Created by Matt Greathouse on 2/17/25.
//

import WidgetKit
import SwiftUI



struct SimpleEntry: TimelineEntry {
    let date: Date
    let reading: ReadingSnapshot?
    var message: String? = nil

    static var preview: SimpleEntry {
        SimpleEntry(date: Date(), reading: ReadingSnapshot(plan: ReadingPlan.previewPlans[0], dayIndex: 1))
    }
}

struct Bible_Reading_Plan_WidgetEntryView: View {
    let entry: SimpleEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            if let reading = entry.reading {
                ReadingPlanWidgetContent(plan: reading.plan, day: reading.day, dayIndex: reading.dayIndex, family: widgetFamily)
            } else {
                EmptyReadingPlanWidget(message: entry.message)
            }
        }
        .containerBackground(ReadingPlanTheme.background, for: .widget)
    }
}

struct Bible_Reading_Plan_Widget: Widget {
    let kind: String = "Bible_Reading_Plan_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Bible_Reading_Plan_WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Bible Reading Plan Widget")
        .description("Shows the current book and chapter range for the day's reading.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        if context.isPreview { completion(.preview); return }
        Task.detached { completion(Self.entry(advancing: false)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task.detached {
            let entry = Self.entry(advancing: true)
            let next = Calendar.current.dateInterval(of: .day, for: entry.date)?.end ?? entry.date.addingTimeInterval(86400)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private static func entry(advancing: Bool) -> SimpleEntry {
        let now = Date()
        do {
            let repository = try ReadingPlanRepository.live(isWidget: true)
            let snapshot = try advancing ? repository.advance(now: now) : repository.load()
            let state = snapshot.envelope.state
            let reading = state.selectedPlanIDs.first.flatMap {
                ReadingSnapshot.resolve(id: $0, state: state, catalog: snapshot.catalog(bundled: repository.bundled))
            }
            let missing = !state.selectedPlanIDs.isEmpty || !state.unresolvedSelectedIDs.isEmpty
            return SimpleEntry(date: now, reading: reading, message: reading == nil && missing ? "Open the app to download or restore this plan." : nil)
        } catch {
            return SimpleEntry(date: now, reading: nil, message: "Open the app to check reading-plan storage.")
        }
    }
}

#Preview(as: .systemSmall) {
    Bible_Reading_Plan_Widget()
} timeline: {
    SimpleEntry.preview
}

#Preview("Widget · Small", traits: .fixedLayout(width: 169, height: 169)) {
    ReadingPlanWidgetContent(
        plan: ReadingPlan.previewPlans[0],
        day: ReadingPlan.previewPlans[0].days[1],
        dayIndex: 1,
        family: .systemSmall
    )
    .padding()
    .background(ReadingPlanTheme.background)
}

#Preview("Widget · Medium", traits: .fixedLayout(width: 329, height: 155)) {
    ReadingPlanWidgetContent(
        plan: ReadingPlan.previewPlans[1],
        day: ReadingPlan.previewPlans[1].days[2],
        dayIndex: 2,
        family: .systemMedium
    )
    .padding()
    .background(ReadingPlanTheme.background)
}
