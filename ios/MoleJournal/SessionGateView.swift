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
        case .signedIn where currentProfileID() != nil:
            signedIn
        case .locked:
            signInScreen(message: Copy.lockedJournal)
        case .signedIn, .signedOut:
            signInScreen(message: Copy.signInDisclaimer)
        }
    }

    private func signInScreen(message: String) -> some View {
        VStack(spacing: 20) {
            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            debugContinueButton
            signInButton
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    #if DEBUG
    private var debugContinueButton: some View {
        Button(DebugSignIn.continueTitle) {
            let next = (try? store.beginSession(appleUserID: DebugSignIn.appleUserID, now: Date())) ?? .signedOut
            session = next
        }
        .buttonStyle(.borderedProminent)
        .frame(width: 280, height: 44)
    }
    #else
    private var debugContinueButton: some View {
        EmptyView()
    }
    #endif

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
        .signInWithAppleButtonStyle(.black)
        .frame(width: 280, height: 44)
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
