//
//  Bible_Reading_PlanApp.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @AppStorage("lastCheckedDate", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var lastCheckedDate: Date = Date()
    // New multi-plan progress storage
    @AppStorage("selectedPlans", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) private var selectedPlansJSON: String = "[]"
    @AppStorage("progressByPlan", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) private var progressByPlanJSON: String = "{}"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: setupDailyCheck)
        }
        WindowGroup {
            ContentView()
        }
    }
    func setupDailyCheck() {
        let currentDate = Date()
        let calendar = Calendar.current

        guard !calendar.isDateInToday(lastCheckedDate) else { return }

        // Increment progress for all selected plans, clamped to plan length - 1
        let plans = ReadingPlanService.shared.loadReadingPlans()
        let planLengths = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, max($0.days.count - 1, 0)) })

        if let idsData = selectedPlansJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([Int].self, from: idsData),
           var map = try? JSONDecoder().decode([Int: Int].self, from: progressByPlanJSON.data(using: .utf8) ?? Data("{}".utf8)) {
            var changed = false
            for id in ids {
                let current = map[id] ?? 0
                let maxIndex = planLengths[id] ?? current
                let next = min(current + 1, maxIndex)
                if next != current { changed = true }
                map[id] = next
            }
            if changed, let data = try? JSONEncoder().encode(map),
               let json = String(data: data, encoding: .utf8) {
                progressByPlanJSON = json
            }
        }

        lastCheckedDate = currentDate
    }
}
