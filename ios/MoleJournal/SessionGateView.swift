import AuthenticationServices
import SwiftUI

enum AppleSignInResult: Equatable {
    case cancel
    case matched
    case differentID
}

func sessionAfterAppleResult(_ result: AppleSignInResult, current: SessionState) -> SessionState {
    switch result {
    case .cancel:
        return current == .locked ? .locked : .signedOut
    case .matched:
        return .signedIn
    case .differentID:
        return .locked
    }
}

struct SessionGateView: View {
    let store: JournalStore
    @State private var session: SessionState

    init(store: JournalStore) {
        self.store = store
        _session = State(initialValue: store.restoreSession())
    }

    var body: some View {
        switch session {
        case .signedIn:
            signedIn
        case .locked:
            VStack(spacing: 16) {
                Text(Copy.lockedJournal)
                    .multilineTextAlignment(.center)
                signInButton
            }
            .padding()
        case .signedOut:
            VStack(spacing: 16) {
                Text(Copy.signInDisclaimer)
                    .multilineTextAlignment(.center)
                signInButton
            }
            .padding()
        }
    }

    private var signInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                let next = (try? store.beginSession(appleUserID: credential.user, now: Date())) ?? .signedOut
                session = next
            case .failure:
                session = sessionAfterAppleResult(.cancel, current: session)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var signedIn: some View {
        if let profileID = currentProfileID() {
            AreaListView(
                store: JournalStoreModel(store: store, sessionAppleID: profileID),
                onSignOut: {
                    store.endSession()
                    session = .signedOut
                },
                onDeleteAccount: {
                    try? store.deleteAccount()
                    session = .signedOut
                }
            )
        }
    }

    private func currentProfileID() -> String? {
        guard case .signedIn = session else { return nil }
        return store.signedInAppleID()
    }
}
