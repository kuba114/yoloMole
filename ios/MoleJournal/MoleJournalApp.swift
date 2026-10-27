import SwiftUI

@main
struct MoleJournalApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text(Copy.signInDisclaimer)
                    .multilineTextAlignment(.center)
                Text("Sign in with Apple")
            }
            .padding()
        }
    }
}
