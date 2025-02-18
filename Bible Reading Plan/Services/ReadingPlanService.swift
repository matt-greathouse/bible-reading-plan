//
//  ReadingPlanService.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/18/25.
//

import Foundation

class ReadingPlanService {
    static let shared = ReadingPlanService()
    
    private init() {}
    
    func loadReadingPlans() -> [ReadingPlan] {
        if let url = Bundle.main.url(forResource: "ReadingPlans", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            return plans
        }
        return []
    }
}
