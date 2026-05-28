import SwiftUI

@main
struct ClipApp: App {
    @StateObject private var clipStore = ClipStore()
    @StateObject private var optimizerStore = PromptOptimizerStore()

    var body: some Scene {
        WindowGroup {
            ContentView(clipStore: clipStore, optimizerStore: optimizerStore)
        }
        .windowResizability(.contentSize)
    }
}
