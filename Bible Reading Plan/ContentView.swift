//
//  ContentView.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/17/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("savedPlan", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedPlan: Int = 0
    @AppStorage("savedDay", store: UserDefaults(suiteName: "group.bible.reading.plan.tracker")) var savedDay: Int = 0
    
    @State private var readingPlans: [ReadingPlan] = []
    // Import UI lives in ReadingPlanSelectionView now
    
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
    @State private var showingImporter: Bool = false
    @State private var importErrorMessage: String?
    @State private var pendingDeletePlan: ReadingPlan?

    var body: some View {
        List {
            ForEach(readingPlans, id: \.id) { plan in
                VStack {
                    Button(action: {
                        savedPlan = plan.id
                        savedDay = 0 // Reset the day when a new plan is selected
                    }) {
                        Text(plan.name)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if ReadingPlanService.shared.isImported(planId: plan.id) {
                            Button(role: .destructive) {
                                pendingDeletePlan = plan
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingImporter = true }) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        _ = try ReadingPlanService.shared.importReadingPlan(from: url)
                        // Refresh list of plans after import
                        readingPlans = ReadingPlanService.shared.loadReadingPlans()
                    } catch {
                        importErrorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert("Import Error", isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        .alert("Delete Imported Plan?", isPresented: Binding(get: { pendingDeletePlan != nil }, set: { if !$0 { pendingDeletePlan = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeletePlan = nil }
            Button("Delete", role: .destructive) {
                if let plan = pendingDeletePlan {
                    do {
                        readingPlans = try ReadingPlanService.shared.deletePlan(withId: plan.id)
                        // Reset selection if deleted plan was selected
                        if !readingPlans.contains(where: { $0.id == savedPlan }) {
                            savedPlan = 0
                            savedDay = 0
                        }
                    } catch {
                        importErrorMessage = error.localizedDescription
                    }
                }
                pendingDeletePlan = nil
            }
        } message: {
            Text("This will remove the imported plan file. If the file contains multiple plans, only this plan will be removed.")
        }
    }

    private func dayLabel(for day: Day, at index: Int) -> Text {
        return Text("Day \(index + 1): \(day.toString())")
    }
}
