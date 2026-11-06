import XCTest
import SwiftData
@testable import MoleJournal

final class JournalStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> JournalStore {
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
        return JournalStore(
            context: ModelContext(container),
            imageDirectory: directory
        )
    }

    func testEmptyNameIsRejected() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertThrowsError(try store.createArea(name: "   ", now: Date())) { error in
            XCTAssertEqual(error as? JournalError, .emptyName)
        }
    }

    func testTrimmedDuplicateNamesAreKept() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: " left shoulder ", now: Date(timeIntervalSince1970: 10))
        _ = try store.createArea(name: "left shoulder", now: Date(timeIntervalSince1970: 20))
        let names = try store.areas(sessionAppleID: "apple-a").map(\.name)
        XCTAssertEqual(names, ["left shoulder", "left shoulder"])
    }

    func testSaveHideAndDeleteCheckIn() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        let box = MoleBoxDraft(
            x: 0.1, y: 0.2, width: 0.3, height: 0.4,
            confidence: 0.55, label: "Mole", hidden: false
        )
        let checkIn = try store.saveCheckIn(
            areaID: area.id,
            sessionAppleID: "apple-a",
            jpeg: Data("jpeg".utf8),
            pixelWidth: 800,
            pixelHeight: 600,
            boxes: [box],
            capturedAt: Date(timeIntervalSince1970: 30)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(filename: checkIn.imageFilename).path))
        let savedBox = try XCTUnwrap(checkIn.boxes.first)
        try store.setBoxHidden(boxID: savedBox.id, sessionAppleID: "apple-a", hidden: true)
        let hidden = try XCTUnwrap(store.checkIns(areaID: area.id, sessionAppleID: "apple-a").first?.boxes.first)
        XCTAssertTrue(hidden.hidden)
        try store.setBoxHidden(boxID: savedBox.id, sessionAppleID: "apple-a", hidden: false)
        let shown = try XCTUnwrap(store.checkIns(areaID: area.id, sessionAppleID: "apple-a").first?.boxes.first)
        XCTAssertFalse(shown.hidden)
        try store.deleteCheckIn(id: checkIn.id, sessionAppleID: "apple-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(filename: checkIn.imageFilename).path))
        XCTAssertTrue(try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").isEmpty)
    }

    func testCheckInsAreNewestFirst() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([1]),
            pixelWidth: 1, pixelHeight: 1, boxes: [],
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([2]),
            pixelWidth: 1, pixelHeight: 1, boxes: [],
            capturedAt: Date(timeIntervalSince1970: 20)
        )
        let times = try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").map(\.capturedAt)
        XCTAssertEqual(times, [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 10)])
    }

    func testFailedSaveLeavesNoFileOrRecord() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        store.failNextSave = true
        XCTAssertThrowsError(
            try store.saveCheckIn(
                areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([9]),
                pixelWidth: 2, pixelHeight: 2, boxes: [],
                capturedAt: Date()
            )
        )
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(leftovers.filter { $0.pathExtension == "jpg" }.isEmpty)
        XCTAssertTrue(try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").isEmpty)
    }

    func testSecondAppleIDCannotRead() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: "arm", now: Date())
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-b", now: Date()), .locked)
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertThrowsError(try store.areas(sessionAppleID: "apple-b")) { error in
            XCTAssertEqual(error as? JournalError, .wrongAppleID)
        }
        XCTAssertEqual(try store.areas(sessionAppleID: "apple-a").map(\.name), ["arm"])
    }

    func testSignOutKeepsTheJournalForTheSameAppleID() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: "arm", now: Date())
        store.endSession()
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertEqual(try store.areas(sessionAppleID: "apple-a").map(\.name), ["arm"])
    }

    func testDeleteAreaAndAccountRemoveFiles() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([3]),
            pixelWidth: 1, pixelHeight: 1, boxes: [], capturedAt: Date()
        )
        try store.deleteArea(id: area.id, sessionAppleID: "apple-a")
        XCTAssertTrue(try store.areas(sessionAppleID: "apple-a").isEmpty)
        try store.deleteAccount()
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }
}
