import Foundation

struct ReadingPlan: Codable {
    let name: String
    let days: [Day]
}

extension ReadingPlan: Equatable {
    static func == (lhs: ReadingPlan, rhs: ReadingPlan) -> Bool {
        return lhs.name == rhs.name
    }
}

struct Day: Codable {
    let book: String
    let startChapter: Int
    let endChapter: Int
    func toString() -> String {
        let bookName = osisToUserFriendlyNames[book] ?? book
        return "\(bookName) \(startChapter)-\(endChapter)"
    }
}
