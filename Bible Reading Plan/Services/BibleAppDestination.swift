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
protocol BibleURLOpener {
    func open(_ url: URL) async -> Bool
}

@MainActor
struct SystemBibleURLOpener: BibleURLOpener {
    func open(_ url: URL) async -> Bool { await UIApplication.shared.open(url, options: [:]) }
}

@MainActor
struct BibleReadingLauncher {
    var opener: any BibleURLOpener = SystemBibleURLOpener()
    func open(_ day: Day, in app: BibleApp) async -> Bool {
        guard let url = app.url(for: day) else { return false }
        return await opener.open(url)
    }
}

#if DEBUG
/// UI tests exercise the failure UI without handing off to an installed third-party app.
struct PreviewBibleURLOpener: BibleURLOpener {
    func open(_ url: URL) async -> Bool { false }
}
#endif
