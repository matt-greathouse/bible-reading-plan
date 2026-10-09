import SwiftUI

@main
struct Bible_Reading_PlanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = ReadingPlanStore.live()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if store.uiTesting && ProcessInfo.processInfo.arguments.contains("--widget-previews") {
                    WidgetPreviewGallery()
                } else {
                    ContentView(store: store)
                }
                #else
                ContentView(store: store)
                #endif
            }
                .task { await store.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.activate() } }
                }
        }
    }
}
