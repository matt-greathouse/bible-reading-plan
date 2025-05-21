//
//  ContentView.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("savedPlan", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedPlan: Int = 0
    @AppStorage("savedDay", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedDay: Int = 0
    
    @State private var readingPlans: [ReadingPlan] = []
    
    func loadReadingPlans() {
        readingPlans = ReadingPlanService.shared.loadReadingPlans()
    }

    var body: some View {
        NavigationView {
            VStack {
                let selectedPlan = readingPlans.first(where: { $0.id == savedPlan })
                if let plan = selectedPlan, savedDay < plan.days.count {
                    Text("Today's Reading")
                        .font(.title)
                    Text("\(plan.days[savedDay].toString())")
                        .font(.largeTitle)
                    Button(action: {
                                openYouVersionURL(book: plan.days[savedDay].book, chapter: plan.days[savedDay].startChapter)
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
            .navigationTitle("Bible Reading Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ReadingPlanSelectionView(readingPlans: $readingPlans, savedPlan: $savedPlan, savedDay: $savedDay)) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    }

    // Function to open YouVersion URL
    private func openYouVersionURL(book: String, chapter: Int) {
        // Construct the URL
        if let url = URL(string: "youversion://bible?reference=\(book).\(chapter)") {
            // Open the URL
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

#Preview {
    ContentView()
}
struct ReadingPlanSelectionView: View {
    @Binding var readingPlans: [ReadingPlan]
    @Binding var savedPlan: Int
    @Binding var savedDay: Int

    var body: some View {
        List {
            ForEach(readingPlans, id: \.name) { plan in
                VStack {
                    Button(action: {
                        savedPlan = plan.id
                        savedDay = 0 // Reset the day when a new plan is selected
                    }) {
                        Text(plan.name)
                    }
                    if savedPlan == plan.id {
                        Picker("Select Day", selection: $savedDay) {
                            ForEach(plan.days.indices, id: \.self) { dayIndex in
                                dayLabel(for: plan.days[dayIndex], at: dayIndex)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                    }
                }
            }
        }
        .navigationTitle("Select a Plan")
    }

    private func dayLabel(for day: Day, at index: Int) -> Text {
        return Text("Day \(index + 1): \(day.toString())")
    }
}
