import Foundation
import SwiftUI
import UIKit

enum ReadingPlanTheme {
    static let accent = Color(red: 0.25, green: 0.29, blue: 0.48)
    static let background = adaptiveColor(light: 0xF7F3EA, dark: 0x161514)
    static let card = adaptiveColor(light: 0xFFFCF6, dark: 0x24221F)
    static let primaryText = adaptiveColor(light: 0x25231F, dark: 0xF5F1E8)
    static let secondaryText = adaptiveColor(light: 0x68635B, dark: 0xBDB6AA)
    static let progressTrack = adaptiveColor(light: 0xE7E0D3, dark: 0x3B3833)
    static let cardBorder = adaptiveColor(light: 0xE9E1D4, dark: 0x3A3732)

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

struct Day: Codable {
    let book: String
    let startChapter: Int
    let endChapter: Int
    func toString() -> String {
        let bookName = osisToUserFriendlyNames[book] ?? book
        return "\(bookName) \(startChapter)-\(endChapter)"
    }
}
