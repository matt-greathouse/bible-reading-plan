import Foundation
import UIKit

// Device-local: deliberately excluded from the synced reading-progress snapshot.
enum BibleApp: String, CaseIterable, Identifiable {
    case youVersion, logos
    var id: String { rawValue }
    var title: String { self == .youVersion ? "YouVersion" : "Logos" }
    var alternate: BibleApp { self == .youVersion ? .logos : .youVersion }
    static let preferenceKey = "preferredBibleApp"

    static func migrate(in preferences: UserDefaults) -> BibleApp {
        if let raw = preferences.string(forKey: preferenceKey), let app = BibleApp(rawValue: raw) { return app }
        let youVersion = preferences.object(forKey: AppPreferenceKey.youVersionEnabled) as? Bool ?? true
        let logos = preferences.bool(forKey: AppPreferenceKey.logosEnabled)
        let app: BibleApp = logos && !youVersion ? .logos : .youVersion
        preferences.set(app.rawValue, forKey: preferenceKey)
        return app
    }

    func url(for day: Day) -> URL? {
        switch self {
        case .youVersion:
            var components = URLComponents()
            components.scheme = "youversion"
            components.host = "bible"
            components.queryItems = [URLQueryItem(name: "reference", value: "\(day.book).\(day.startChapter)")]
            return components.url
        case .logos:
            let book = osisToUserFriendlyNames[day.book] ?? day.book
            let reference = "Bible.\(book).\(day.startChapter)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "logosres:esv?ref=\(reference)")
        }
    }
}

@MainActor
struct BibleReadingLauncher {
    var openURL: @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0, options: [:]) }
    func open(_ day: Day, in app: BibleApp) async -> Bool {
        guard let url = app.url(for: day) else { return false }
        return await openURL(url)
    }
}
