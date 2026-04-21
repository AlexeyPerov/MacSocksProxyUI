import SwiftUI

@main
struct MacProxyUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MacProxyUI") {
            MainView(appState: appDelegate.appState)
        }
        .defaultSize(
            width: MainView.minimumWindowWidth,
            height: MainView.minimumWindowHeight
        )
    }
}
