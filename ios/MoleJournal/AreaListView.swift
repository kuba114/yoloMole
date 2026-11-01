import SwiftData
import SwiftUI

func canSaveAreaName(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct AreaListView: View {
    @Bindable var store: JournalStoreModel
    var onSignOut: () -> Void = {}
    var onDeleteAccount: () -> Void = {}
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            List(store.areas) { area in
                NavigationLink(area.name) {
                    AreaDetailView(store: store, areaID: area.id)
                }
            }
            .overlay {
                if store.areas.isEmpty {
                    Text("Add a body area")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Body area", text: $draftName)
                    Button("Add") {
                        store.addArea(name: draftName)
                        draftName = ""
                    }
                    .disabled(!canSaveAreaName(draftName))
                }
                .padding()
            }
            .navigationTitle("Body areas")
            .toolbar {
                Button("Sign out", action: onSignOut)
                Button("Delete account", action: onDeleteAccount)
            }
        }
    }
}

@MainActor
@Observable
final class JournalStoreModel {
    private(set) var areas: [BodyAreaRecord] = []
    let sessionAppleID: String
    private let store: JournalStore

    init(store: JournalStore, sessionAppleID: String) {
        self.store = store
        self.sessionAppleID = sessionAppleID
        reload()
    }

    func reload() {
        areas = (try? store.areas(sessionAppleID: sessionAppleID)) ?? []
    }

    func addArea(name: String) {
        guard canSaveAreaName(name) else { return }
        _ = try? store.createArea(name: name, now: Date())
        reload()
    }

    func checkIns(areaID: UUID) -> [CheckInRecord] {
        (try? store.checkIns(areaID: areaID, sessionAppleID: sessionAppleID)) ?? []
    }
}

struct AreaDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID

    var body: some View {
        let items = store.checkIns(areaID: areaID)
        List(items) { item in
            Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .navigationTitle(store.areas.first { $0.id == areaID }?.name ?? "")
    }
}
