import Foundation
import CryptoKit

struct ReadingPlan: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let days: [Day]
}

extension ReadingPlan {
    static let previewPlans = [
        ReadingPlan(
            id: 1,
            name: "New Testament in a Year",
            days: [
                Day(book: "JHN", startChapter: 1, endChapter: 1),
                Day(book: "JHN", startChapter: 2, endChapter: 2),
                Day(book: "JHN", startChapter: 3, endChapter: 3)
            ]
        ),
        ReadingPlan(
            id: 2,
            name: "Psalms and Proverbs",
            days: [
                Day(book: "PSA", startChapter: 1, endChapter: 2),
                Day(book: "PRO", startChapter: 1, endChapter: 1),
                Day(book: "PSA", startChapter: 3, endChapter: 4)
            ]
        )
    ]
}

struct Day: Codable, Equatable, Sendable {
    let book: String
    let startChapter: Int
    let endChapter: Int
    func toString() -> String {
        let bookName = osisToUserFriendlyNames[book] ?? book
        return startChapter == endChapter ? "\(bookName) \(startChapter)" : "\(bookName) \(startChapter)–\(endChapter)"
    }
}

/// Import JSON retains integer IDs; runtime identity never depends on an imported ID.
struct CatalogPlan: Identifiable, Equatable, Sendable {
    let id: String
    let plan: ReadingPlan
    var isImported: Bool { id.hasPrefix("imported:") }
}

enum PlanError: LocalizedError {
    case invalidJSON, emptyImport, invalidPlan(String), storageUnavailable, invalidCloudRecord
    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Choose a JSON file containing a reading plan or an array of reading plans."
        case .emptyImport: return "The file contains no reading plans."
        case .invalidPlan(let reason): return reason
        case .storageUnavailable: return "Shared reading-plan storage is unavailable. Please reopen the app."
        case .invalidCloudRecord: return "An iCloud reading plan could not be verified. Your local copy was preserved."
        }
    }
}

enum PlanCodec {
    static func decode(_ data: Data) throws -> [ReadingPlan] {
        let decoder = JSONDecoder()
        let plans: [ReadingPlan]
        if let array = try? decoder.decode([ReadingPlan].self, from: data) {
            plans = array
        } else if let single = try? decoder.decode(ReadingPlan.self, from: data) {
            plans = [single]
        } else { throw PlanError.invalidJSON }
        guard !plans.isEmpty else { throw PlanError.emptyImport }
        return try plans.map(normalize)
    }

    static func normalize(_ plan: ReadingPlan) throws -> ReadingPlan {
        let name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PlanError.invalidPlan("A reading plan needs a name.") }
        guard !plan.days.isEmpty else { throw PlanError.invalidPlan("“\(name)” contains no readings.") }
        let days = try plan.days.map { day in
            let rawBook = day.book.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // Older bundled/imported files sometimes used the full name (for example “Jude”).
            let book = osisToUserFriendlyNames[rawBook] != nil ? rawBook :
                osisToUserFriendlyNames.first(where: { $0.value.uppercased() == rawBook })?.key ?? rawBook
            guard osisToUserFriendlyNames[book] != nil else {
                throw PlanError.invalidPlan("“\(name)” uses an unknown book code: \(day.book).")
            }
            guard day.startChapter >= 1, day.endChapter >= day.startChapter else {
                throw PlanError.invalidPlan("“\(name)” has an invalid chapter range.")
            }
            return Day(book: book, startChapter: day.startChapter, endChapter: day.endChapter)
        }
        return ReadingPlan(id: plan.id, name: name, days: days)
    }

    static func importedID(for plan: ReadingPlan) throws -> String {
        struct Content: Encodable { let name: String; let days: [Day] }
        let normalized = try normalize(plan)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Content(name: normalized.name, days: normalized.days))
        return "imported:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ReadingPlanState: Codable, Equatable, Sendable {
    var selectedPlanIDs: [String] = []
    var progressByPlan: [String: Int] = [:]
    var lastAdvancedReadingDay: String?
    // Unresolvable integer IDs are device-local: never guess which import they meant.
    var unresolvedSelectedIDs: [Int] = []
    var unresolvedProgress: [Int: Int] = [:]
}

struct StateEnvelope: Codable, Equatable, Sendable {
    var state = ReadingPlanState()
    var modifiedAt = Date(timeIntervalSince1970: 0)
}

struct ImportedPlanRecord: Codable, Equatable, Sendable {
    var id: String
    var plan: ReadingPlan?
    var deleted: Bool
    var modifiedAt: Date
    var pending: Bool
}

struct ReadingPlanSnapshot: Codable, Equatable, Sendable {
    var version = 2
    var envelope = StateEnvelope()
    var statePending = false
    var imports: [String: ImportedPlanRecord] = [:]
    var loadErrors: [String] = []
    var migratedSources: [String] = []
    var legacyAliases: [Int: [String]] = [:]
    var lastSuccessfulSync: Date?

    var pendingCount: Int { imports.values.filter(\.pending).count + (statePending ? 1 : 0) }
    func catalog(bundled: [ReadingPlan]) -> [CatalogPlan] {
        var seen = Set<String>()
        let builtIn = bundled.compactMap { plan -> CatalogPlan? in
            let id = "bundled:\(plan.id)"
            return seen.insert(id).inserted ? CatalogPlan(id: id, plan: plan) : nil
        }
        let custom = imports.values.filter { !$0.deleted }.sorted { $0.id < $1.id }.compactMap { record in
            record.plan.map { CatalogPlan(id: record.id, plan: $0) }
        }
        return builtIn + custom
    }
}

enum DailyProgress {
    static func dayIdentifier(_ date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func advance(_ state: inout ReadingPlanState, catalog: [CatalogPlan], now: Date, calendar: Calendar) {
        let today = dayIdentifier(now, calendar: calendar)
        guard state.lastAdvancedReadingDay != today else { return }
        // A new install starts at day one. A migrated checkpoint is seeded by the repository.
        if state.lastAdvancedReadingDay != nil {
            for item in catalog where state.selectedPlanIDs.contains(item.id) {
                let current = min(max(0, state.progressByPlan[item.id] ?? 0), item.plan.days.count - 1)
                state.progressByPlan[item.id] = min(current + 1, item.plan.days.count - 1)
            }
        }
        state.lastAdvancedReadingDay = today
    }
}

struct ReadingSnapshot: Equatable, Sendable {
    let plan: ReadingPlan
    let dayIndex: Int
    var day: Day { plan.days[dayIndex] }
    var progress: Double { Double(dayIndex + 1) / Double(plan.days.count) }

    static func resolve(id: String, state: ReadingPlanState, catalog: [CatalogPlan]) -> ReadingSnapshot? {
        guard let plan = catalog.first(where: { $0.id == id })?.plan, !plan.days.isEmpty else { return nil }
        let index = min(max(0, state.progressByPlan[id] ?? 0), plan.days.count - 1)
        return ReadingSnapshot(plan: plan, dayIndex: index)
    }
}
