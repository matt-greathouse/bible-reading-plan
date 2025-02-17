//
//  Bible_Reading_PlanApp.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @State private var lastCheckedDate: Date?

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
                incrementDayIfNeeded()
            }
        }
        lastCheckedDate = currentDate
    }

    func incrementDayIfNeeded() {
        if let selectedPlan = UserDefaults.standard.string(forKey: "selectedPlanName"),
           var currentDay = UserDefaults.standard.value(forKey: "currentDay") as? Int {
            currentDay += 1
            UserDefaults.standard.set(currentDay, forKey: "currentDay")
        }
    }
}
