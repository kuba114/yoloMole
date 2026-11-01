import SwiftData
import XCTest
@testable import MoleJournal

final class SessionTests: XCTestCase {
    func testCancelStaysSignedOut() {
        XCTAssertEqual(sessionAfterAppleResult(.cancel, current: .signedOut), .signedOut)
    }

    func testMatchingIDSignsIn() {
        XCTAssertEqual(sessionAfterAppleResult(.matched, current: .signedOut), .signedIn)
    }

    func testDifferentIDLocks() {
        XCTAssertEqual(sessionAfterAppleResult(.differentID, current: .signedOut), .locked)
    }

    func testJournalFolderMatchesBuildConfiguration() {
        #if DEBUG
        XCTAssertEqual(journalFolderName(), "MoleJournalDebug")
        XCTAssertEqual(debugJournalStoreURL().lastPathComponent, "MoleJournalDebug.store")
        XCTAssertFalse(journalDirectory().lastPathComponent == "MoleJournal")
        #else
        XCTAssertEqual(journalFolderName(), "MoleJournal")
        #endif
    }

    #if DEBUG
    func testDebugTestingIdentityIsSeparateFromAnAppleAccount() throws {
        XCTAssertEqual(DebugSignIn.appleUserID, "debug.molejournal.testing")
        XCTAssertEqual(DebugSignIn.continueTitle, "Continue for Testing")

        let ownedByApple = try makeStore()
        XCTAssertEqual(try ownedByApple.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        _ = try ownedByApple.createArea(name: "arm", now: Date())
        XCTAssertEqual(try ownedByApple.beginSession(appleUserID: DebugSignIn.appleUserID, now: Date()), .locked)
        XCTAssertThrowsError(try ownedByApple.areas(sessionAppleID: DebugSignIn.appleUserID)) { error in
            XCTAssertEqual(error as? JournalError, .wrongAppleID)
        }
        XCTAssertEqual(try ownedByApple.areas(sessionAppleID: "apple-a").map(\.name), ["arm"])

        let testingJournal = try makeStore()
        XCTAssertEqual(try testingJournal.beginSession(appleUserID: DebugSignIn.appleUserID, now: Date()), .signedIn)
        _ = try testingJournal.createArea(name: "left shoulder", now: Date())
        XCTAssertEqual(try testingJournal.beginSession(appleUserID: "apple-a", now: Date()), .locked)
        XCTAssertThrowsError(try testingJournal.areas(sessionAppleID: "apple-a")) { error in
            XCTAssertEqual(error as? JournalError, .wrongAppleID)
        }
        XCTAssertEqual(try testingJournal.areas(sessionAppleID: DebugSignIn.appleUserID).map(\.name), ["left shoulder"])
    }

    private func makeStore() throws -> JournalStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let schema = Schema([
            ProfileRecord.self,
            BodyAreaRecord.self,
            CheckInRecord.self,
            MoleBoxRecord.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return JournalStore(context: ModelContext(container), imageDirectory: directory)
    }
    #endif
}
