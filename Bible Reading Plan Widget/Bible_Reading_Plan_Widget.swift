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
    let configuration: ConfigurationAppIntent
}

struct Bible_Reading_Plan_WidgetEntryView : View {
    @AppStorage(ReadingPlanStateStore.stateKey, store: AppGroup.defaults) private var readingPlanStateData: Data = Data()
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let readingPlans = ReadingPlanService.shared.loadReadingPlans()
        let _ = readingPlanStateData
        let state = ReadingPlanStateStore.load(from: AppGroup.defaults)
        let selectedIds = state.selectedPlanIds
        let progressMap = state.progressByPlan

        if let firstId = selectedIds.first,
           let plan = readingPlans.first(where: { $0.id == firstId }) {
            let idx = min(progressMap[firstId] ?? 0, max(plan.days.count - 1, 0))
            if plan.days.indices.contains(idx) {
                ReadingPlanWidgetContent(plan: plan, day: plan.days[idx], dayIndex: idx, family: widgetFamily)
                    .containerBackground(ReadingPlanTheme.background, for: .widget)
            } else {
                EmptyReadingPlanWidget()
                    .containerBackground(ReadingPlanTheme.background, for: .widget)
            }
        } else {
            EmptyReadingPlanWidget()
                .containerBackground(ReadingPlanTheme.background, for: .widget)
        }
    }
}

private struct ReadingPlanWidgetContent: View {
    let plan: ReadingPlan
    let day: Day
    let dayIndex: Int
    let family: WidgetFamily

    private var dayLabel: String {
        "Day \(dayIndex + 1) of \(max(plan.days.count, 1))"
    }

    private var progress: Double {
        guard !plan.days.isEmpty else { return 0 }
        return Double(dayIndex + 1) / Double(plan.days.count)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 18) {
                    readingDetails
                    Spacer(minLength: 0)
                    progressDetails
                        .frame(width: 92)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    readingDetails
                    Spacer(minLength: 0)
                    progressDetails
                }
            }
        }
        .foregroundStyle(ReadingPlanTheme.primaryText)
        .widgetAccentable()
    }

    private var readingDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TODAY’S READING")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
            Text(plan.name)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(day.toString())
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }

    private var progressDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReadingPlanTheme.accent)
            ProgressView(value: progress)
                .tint(ReadingPlanTheme.accent)
            Text("\(Int(progress * 100))% complete")
                .font(.caption2)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }
}

private struct EmptyReadingPlanWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(ReadingPlanTheme.accent)
            Text("No Reading Plan Selected")
                .font(.headline)
                .foregroundStyle(ReadingPlanTheme.primaryText)
            Text("Choose a plan in the app to see today’s reading.")
                .font(.caption)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }
}

struct Bible_Reading_Plan_Widget: Widget {
    let kind: String = "Bible_Reading_Plan_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Bible_Reading_Plan_WidgetEntryView()
        }
        .configurationDisplayName("Bible Reading Plan Widget")
        .description("Shows the current book and chapter range for the day's reading.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), configuration: ConfigurationAppIntent())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        ReadingPlanService.shared.advanceDailyProgressIfNeeded()
        let currentDate = Date()
        let entry = SimpleEntry(date: currentDate, configuration: ConfigurationAppIntent())
        
        // Refreshing the widget every hour
        let nextUpdateDate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
        completion(timeline)
    }
}

extension ConfigurationAppIntent {
}

#Preview(as: .systemSmall) {
    Bible_Reading_Plan_Widget()
} timeline: {
    SimpleEntry(date: Date(), configuration: ConfigurationAppIntent())
}
