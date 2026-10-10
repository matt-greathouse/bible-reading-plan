import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @UIApplicationDelegateAdaptor(ReadingNotificationDelegate.self) private var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ReadingPlanStore.live()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if store.uiTesting && ProcessInfo.processInfo.arguments.contains("--widget-previews") {
                    WidgetPreviewGallery()
                } else {
                    ContentView(store: store, launcher: store.uiTesting
                                ? BibleReadingLauncher(opener: PreviewBibleURLOpener()) : BibleReadingLauncher())
                }
                #else
                ContentView(store: store)
                #endif
            }
                .onOpenURL { ReadingRouteHandler.shared.open(url: $0) }
                .task {
                    #if DEBUG
                    if store.uiTesting, let id = ProcessInfo.processInfo.environment["UITEST_READING_ROUTE"] {
                        ReadingRouteHandler.shared.open(planID: id)
                    }
                    #endif
                    await store.activate()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.activate() } }
                }
        }
    }
}
