import SwiftUI

@main
struct iCloudPhotosBackupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About iCloud Photos Backup") {
                    // TODO: Show about window
                }
            }
        }
    }
}
