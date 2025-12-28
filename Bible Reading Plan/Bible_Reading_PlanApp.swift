//
//  Bible_Reading_PlanApp.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: setupDailyCheck)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        ReadingPlanCloudSync.shared.start()
                    }
                }
        }
    }

    private func setupDailyCheck() {
        ReadingPlanCloudSync.shared.start()
        ReadingPlanService.shared.advanceDailyProgressIfNeeded()
    }
}
