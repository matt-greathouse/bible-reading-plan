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
    @AppStorage("savedPlanName", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedPlanName: String = ""
    @AppStorage("savedDay", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedDay: Int = 0
    
    var body: some View {
        let readingPlans = ReadingPlanService.shared.loadReadingPlans()
        
        if let plan = readingPlans.first(where: { $0.name == savedPlanName }), savedDay < plan.days.count {
            let day = plan.days[savedDay]
            VStack {
                Text("Today's Reading")
                    .font(.subheadline)
                Text(day.toString())
                    .font(.headline)
            }
            .containerBackground(Color.clear, for: .widget)
        } else {
            VStack {
                Text("No Reading Plan Selected")
                    .font(.headline)
            }
            .containerBackground(Color.clear, for: .widget)
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
