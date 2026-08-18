import Foundation
import SwiftUI
import UIKit

enum ReadingPlanTheme {
    static let accent = adaptiveColor(light: 0x404A7A, dark: 0xAAB8FF)
    static let background = adaptiveColor(light: 0xF7F3EA, dark: 0x161514)
    static let card = adaptiveColor(light: 0xFFFCF6, dark: 0x2A2825)
    static let primaryText = adaptiveColor(light: 0x25231F, dark: 0xFFF9F0)
    static let secondaryText = adaptiveColor(light: 0x68635B, dark: 0xD5CEC3)
    static let progressTrack = adaptiveColor(light: 0xE7E0D3, dark: 0x514D46)
    static let cardBorder = adaptiveColor(light: 0xE9E1D4, dark: 0x57524B)

    static let cardCornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 10
    static let cardSpacing: CGFloat = 16

    private static func adaptiveColor(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(
                red: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 16 & 0xFF) / 255,
                green: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 8 & 0xFF) / 255,
                blue: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct ReadingPlan: Codable {
    let id: Int
    let name: String
    let days: [Day]
}

extension ReadingPlan: Equatable {
    static func == (lhs: ReadingPlan, rhs: ReadingPlan) -> Bool {
        return lhs.id == rhs.id
    }
}

extension ReadingPlan {
    static let previewPlans = [
        ReadingPlan(
            id: 1,
            name: "New Testament in a Year",
            days: [
                Day(book: "John", startChapter: 1, endChapter: 1),
                Day(book: "John", startChapter: 2, endChapter: 2),
                Day(book: "John", startChapter: 3, endChapter: 3)
            ]
        ),
        ReadingPlan(
            id: 2,
            name: "Psalms and Proverbs",
            days: [
                Day(book: "Ps", startChapter: 1, endChapter: 2),
                Day(book: "Prov", startChapter: 1, endChapter: 1),
                Day(book: "Ps", startChapter: 3, endChapter: 4)
            ]
        )
    ]
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
