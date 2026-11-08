import SwiftUI

@main
struct XingyujiApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
