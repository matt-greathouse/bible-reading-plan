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
