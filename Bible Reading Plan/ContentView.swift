//
//  ContentView.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedPlan: ReadingPlan? {
        didSet {
            if let plan = selectedPlan {
                UserDefaults.standard.set(plan.name, forKey: "selectedPlanName")
            }
        }
    }
    
    func loadReadingPlans() {
        if let url = Bundle.main.url(forResource: "ReadingPlans", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            readingPlans = plans
        }
    }

    func loadSavedState() {
        if let savedPlanName = UserDefaults.standard.string(forKey: "selectedPlanName"),
           let savedDay = UserDefaults.standard.value(forKey: "currentDay") as? Int {
            currentDay = savedDay
            selectedPlan = readingPlans.first(where: { $0.name == savedPlanName })
        }
    }
    
    @State private var currentDay: Int = 0 {
        didSet {
            UserDefaults.standard.set(currentDay, forKey: "currentDay")
        }
    }
    @State private var readingPlans: [ReadingPlan] = []

    var body: some View {
        NavigationView {
            VStack {
                if let plan = selectedPlan, currentDay < plan.days.count {
                    Text("Today's Reading")
                        .font(.title)
                    Text("\(plan.days[currentDay].book) \(plan.days[currentDay].startChapter)-\(plan.days[currentDay].endChapter)")
                        .font(.largeTitle)
                    Button(action: {
                                openYouVersionURL(book: plan.days[currentDay].book, chapter: plan.days[currentDay].startChapter)
                            }) {
                                Text("Open in Bible App")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                } else {
                    Text("Select a Reading Plan")
                        .font(.title)
                }
            }
            .onAppear(perform: loadReadingPlans)
            .onAppear(perform: loadSavedState)
            .navigationTitle("Bible Reading Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ReadingPlanSelectionView(readingPlans: $readingPlans, selectedPlan: $selectedPlan, currentDay: $currentDay)) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    }

    // Function to open YouVersion URL
    private func openYouVersionURL(book: String, chapter: Int) {
        let queryString = "\(book) \(chapter)"
        let encodedQueryString = queryString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? queryString
        // Construct the URL
        if let url = URL(string: "youversion://search/bible?query=\(encodedQueryString)") {
            // Open the URL
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

#Preview {
    ContentView()
}
struct ReadingPlanSelectionView: View {
    @Binding var readingPlans: [ReadingPlan]
    @Binding var selectedPlan: ReadingPlan?
    @Binding var currentDay: Int

    var body: some View {
        List(readingPlans, id: \.name) { plan in
            VStack {
                Button(action: {
                    selectedPlan = plan
                    currentDay = 0
                }) {
                    Text(plan.name)
                }
                if selectedPlan == plan {
                    Picker("Select Day", selection: $currentDay) {
                        ForEach(0..<plan.days.count, id: \.self) { dayIndex in
                            Text("Day \(dayIndex + 1): \(plan.days[dayIndex].book) \(plan.days[dayIndex].startChapter)-\(plan.days[dayIndex].endChapter)")
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .onChange(of: currentDay) { newDay in
                        UserDefaults.standard.set(newDay, forKey: "currentDay")
                    }
                }
            }
        }
        .navigationTitle("Select a Plan")
    }
}
