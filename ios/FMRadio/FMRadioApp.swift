import SwiftUI

@main
struct FMRadioApp: App {
    @StateObject private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}
