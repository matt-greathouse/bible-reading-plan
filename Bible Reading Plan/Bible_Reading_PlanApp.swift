//
//  Bible_Reading_PlanApp.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: setupDailyCheck)
        }
    }

    private func setupDailyCheck() {
        ReadingPlanService.shared.advanceDailyProgressIfNeeded()
    }
}
