//
//  Bible_Reading_PlanApp.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @AppStorage("lastCheckedDate", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var lastCheckedDate: Date?
    @AppStorage("savedDay", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedDay: Int = 0

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

        if let lastDate = lastCheckedDate {
            if !calendar.isDateInToday(lastDate) {
                savedDay += 1
            }
        }
        lastCheckedDate = currentDate
    }
}
