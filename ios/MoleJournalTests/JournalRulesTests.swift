import XCTest
@testable import MoleJournal

final class JournalRulesTests: XCTestCase {
    func testFirstCheckInHasNoGhost() {
        let step = initialCaptureStep(previousImageFilename: nil)
        XCTAssertEqual(step.instruction, Copy.framingNote)
        XCTAssertNil(step.previousImageFilename)
        let camera = advanceToCamera(step)
        XCTAssertEqual(camera.phase, .camera)
        XCTAssertFalse(camera.showsGhost)
    }

    func testLaterCheckInShowsPreviousPhotoThenGhost() {
        let step = initialCaptureStep(previousImageFilename: "last.jpg")
        XCTAssertEqual(step.phase, .instruction)
        XCTAssertEqual(step.instruction, Copy.matchPose)
        XCTAssertFalse(step.showsGhost)
        let camera = advanceToCamera(step)
        XCTAssertTrue(camera.showsGhost)
        XCTAssertEqual(camera.previousImageFilename, "last.jpg")
    }

    func testComparisonNeedsTwoDifferentCheckIns() {
        let only = UUID()
        XCTAssertNil(defaultComparison(newestFirst: [only]))
        let newest = UUID()
        let older = UUID()
        let pair = defaultComparison(newestFirst: [newest, older])
        XCTAssertEqual(pair?.leftID, newest)
        XCTAssertEqual(pair?.rightID, older)
        XCTAssertNotEqual(pair?.leftID, pair?.rightID)
    }

    func testHiddenBoxesAreOmitted() {
        let shown = MoleBoxDraft(x: 0, y: 0, width: 0.1, height: 0.1, confidence: 0.4, label: "Mole", hidden: false)
        let hidden = MoleBoxDraft(x: 0.2, y: 0.2, width: 0.1, height: 0.1, confidence: 0.8, label: "Mole", hidden: true)
        XCTAssertEqual(visibleBoxes([shown, hidden]), [shown])
    }
}
