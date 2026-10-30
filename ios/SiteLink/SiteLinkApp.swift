import SwiftUI

@main
struct SiteLinkApp: App {
    @StateObject private var model = LinkModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
    }
}
