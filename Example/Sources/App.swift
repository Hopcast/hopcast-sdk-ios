import SwiftUI

@main
struct HopcastExampleApp: App {
    @StateObject private var controller = HopcastController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
        }
    }
}
