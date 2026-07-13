import SwiftUI
import TadaWordsAppShell

@main
struct TadaWordsPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                TadaWordsApplicationView(demoMode: true)
                    .frame(minWidth: 860, minHeight: 560)
            #else
                TadaWordsApplicationView(demoMode: true)
            #endif
        }
    }
}
