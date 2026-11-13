import SwiftUI
import UserNotifications

@main
struct MossbrookApp: App {
    @State private var store = VillageStore()

    init() {
        UNUserNotificationCenter.current().delegate = QuietNotifications.shared
        SoundFX.shared.prepare()
        PixelButtonStyle.onPress = { SoundFX.shared.play(.pop, volume: 0.7) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mergeSelfTest") { MergeSelfTest.run() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // The app always draws in its own light palette. At night the town is dark behind
                // the clock and battery, so only the system bits switch to their light-on-dark look.
                .environment(\.colorScheme, .light)
                .preferredColorScheme(store.phase == .night ? .dark : .light)
        }
    }
}
