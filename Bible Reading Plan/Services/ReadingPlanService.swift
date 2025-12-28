//
//  ReadingPlanService.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/18/25.
//

import Foundation
import UniformTypeIdentifiers

class ReadingPlanService {
    static let shared = ReadingPlanService()
    
    private init() {}

    private enum DefaultsKey {
        static let selectedPlans = "selectedPlans"
        static let progressByPlan = "progressByPlan"
        static let lastCheckedDate = "lastCheckedDate"
    }

    private let appGroupSuiteName = "group.bible.reading.plan.tracker"
    private var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupSuiteName) ?? .standard
    }

    // Directory to store imported reading plan JSON files
    private var importDirectoryURL: URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("ImportedReadingPlans", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func loadReadingPlans() -> [ReadingPlan] {
        var allPlans: [ReadingPlan] = []
        // Reset sources mapping
        planSources = [:]
        // Load bundled plans
        if let url = Bundle.main.url(forResource: "ReadingPlans", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            allPlans.append(contentsOf: plans)
        }

        // Load imported plans from Documents/ImportedReadingPlans
        if let dir = importDirectoryURL {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension.lowercased() == "json" {
                    if let data = try? Data(contentsOf: file) {
                        if let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
                            for p in plans { planSources[p.id] = file }
                            allPlans.append(contentsOf: plans)
                        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
                            planSources[plan.id] = file
                            allPlans.append(plan)
                        }
                    }
                }
            }
        }

        return allPlans
    }

    func advanceDailyProgressIfNeeded(now: Date = Date(), calendar: Calendar = .current) {
        let defaults = appGroupDefaults
        let lastCheckedDate = defaults.object(forKey: DefaultsKey.lastCheckedDate) as? Date ?? Date()

        guard !calendar.isDateInToday(lastCheckedDate) else { return }

        let plans = loadReadingPlans()
        let planLengths = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, max($0.days.count - 1, 0)) })

        let ids = readSelectedPlanIds(from: defaults)
        var map = readProgressMap(from: defaults)
        var changed = false
        for id in ids {
            let current = map[id] ?? 0
            let maxIndex = planLengths[id] ?? current
            let next = min(current + 1, maxIndex)
            if next != current { changed = true }
            map[id] = next
        }
        if changed {
            writeProgressMap(map, to: defaults)
        }

        defaults.set(now, forKey: DefaultsKey.lastCheckedDate)
    }

    // Import a reading plan JSON file (single plan or array of plans) and store a copy
    @discardableResult
    func importReadingPlan(from sourceURL: URL) throws -> [ReadingPlan] {
        let data = try Data(contentsOf: sourceURL)
        var imported: [ReadingPlan] = []
        if let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            imported = plans
        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
            imported = [plan]
        } else {
            throw NSError(domain: "ReadingPlanService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format for reading plan"])
        }

        // Resolve ID conflicts against existing plans
        let existing = loadReadingPlans()
        var usedIds = Set(existing.map { $0.id })
        var adjusted: [ReadingPlan] = []
        for var p in imported {
            if usedIds.contains(p.id) {
                p = ReadingPlan(id: nextAvailableId(used: &usedIds), name: p.name, days: p.days)
            }
            usedIds.insert(p.id)
            adjusted.append(p)
        }

        // Persist adjusted data for future loads
        guard let destDir = importDirectoryURL else { return adjusted }
        let fm = FileManager.default
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueName = uniqueFileName(basename: fileName.isEmpty ? "ImportedPlan" : fileName, ext: "json", in: destDir)
        let destURL = destDir.appendingPathComponent(uniqueName)

        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }

        let toWrite: Data
        if adjusted.count == 1, let only = adjusted.first {
            toWrite = try JSONEncoder().encode(only)
        } else {
            toWrite = try JSONEncoder().encode(adjusted)
        }
        try toWrite.write(to: destURL, options: .atomic)

        return adjusted
    }

    // Determine if a plan came from an imported file
    func isImported(planId: Int) -> Bool {
        return planSources[planId] != nil
    }

    // Delete a plan by ID. If the plan resides in a multi-plan file, remove just that plan; delete file if empty.
    @discardableResult
    func deletePlan(withId id: Int) throws -> [ReadingPlan] {
        guard let fileURL = planSources[id] else {
            throw NSError(domain: "ReadingPlanService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Plan is not imported or cannot be found"])
        }
        let fm = FileManager.default
        let data = try Data(contentsOf: fileURL)
        if var plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            plans.removeAll { $0.id == id }
            if plans.isEmpty {
                try fm.removeItem(at: fileURL)
            } else {
                let newData = try JSONEncoder().encode(plans)
                try newData.write(to: fileURL, options: .atomic)
            }
        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
            if plan.id == id {
                try fm.removeItem(at: fileURL)
            }
        } else {
            // If file is not decodable, remove it to avoid stale state
            try? fm.removeItem(at: fileURL)
        }

        // Reload to refresh planSources mapping
        return loadReadingPlans()
    }

    // MARK: - Helpers
    private var planSources: [Int: URL] = [:]

    private func readSelectedPlanIds(from defaults: UserDefaults) -> [Int] {
        guard let json = defaults.string(forKey: DefaultsKey.selectedPlans),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return ids
    }

    private func readProgressMap(from defaults: UserDefaults) -> [Int: Int] {
        guard let json = defaults.string(forKey: DefaultsKey.progressByPlan),
              let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([Int: Int].self, from: data) else {
            return [:]
        }
        return map
    }

    private func writeProgressMap(_ map: [Int: Int], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(map),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: DefaultsKey.progressByPlan)
        }
    }

    private func uniqueFileName(basename: String, ext: String, in directory: URL) -> String {
        let fm = FileManager.default
        var attempt = 0
        var candidate: String { attempt == 0 ? "\(basename).\(ext)" : "\(basename)-\(attempt).\(ext)" }
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            attempt += 1
        }
        return candidate
    }

    private func nextAvailableId(used: inout Set<Int>) -> Int {
        var candidate = (used.max() ?? 0) + 1
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }
}
