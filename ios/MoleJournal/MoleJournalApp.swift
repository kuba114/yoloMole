import SwiftUI

@main
struct MoleJournalApp: App {
    var body: some Scene {
        WindowGroup {
            Text(Copy.signInDisclaimer)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
