import SwiftData
import SwiftUI

@main
struct MoleJournalApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            ProfileRecord.self,
            BodyAreaRecord.self,
            CheckInRecord.self,
            MoleBoxRecord.self,
        ])
        container = try! ModelContainer(for: schema)
    }

    var body: some Scene {
        WindowGroup {
            SessionGateView(
                store: JournalStore(
                    context: ModelContext(container),
                    imageDirectory: journalDirectory()
                )
            )
        }
    }
}

func journalDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("MoleJournal", isDirectory: true)
}
