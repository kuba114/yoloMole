import SwiftData
import SwiftUI

@main
struct MoleJournalApp: App {
    private let container: ModelContainer

    init() {
        container = makeJournalContainer()
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

func applicationSupportDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

func journalFolderName() -> String {
    #if DEBUG
    "MoleJournalDebug"
    #else
    "MoleJournal"
    #endif
}

func journalDirectory() -> URL {
    applicationSupportDirectory().appendingPathComponent(journalFolderName(), isDirectory: true)
}

func makeJournalContainer() -> ModelContainer {
    let schema = Schema([
        ProfileRecord.self,
        BodyAreaRecord.self,
        CheckInRecord.self,
        MoleBoxRecord.self,
    ])
    #if DEBUG
    return try! ModelContainer(for: schema, configurations: ModelConfiguration(url: debugJournalStoreURL()))
    #else
    return try! ModelContainer(for: schema)
    #endif
}

#if DEBUG
func debugJournalStoreURL() -> URL {
    applicationSupportDirectory().appendingPathComponent("MoleJournalDebug.store")
}
#endif
