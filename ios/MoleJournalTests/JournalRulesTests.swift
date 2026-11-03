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

    func testCatalogCountsEveryMoleIncludingHiddenOnes() {
        XCTAssertEqual(catalogMoleCount([]), "0 moles")
        XCTAssertEqual(catalogMoleCount(["Mole"]), "1 mole")
        XCTAssertEqual(catalogMoleCount(["Mole", "Mole", "images"]), "2 moles")
    }

    func testTogetherKeepsVisibleBoxesInPlace() {
        let shown = mole(x: 0.1, y: 0.2, width: 0.3, height: 0.4, hidden: false)
        let hidden = mole(x: 0.1, y: 0.2, width: 0.3, height: 0.4, hidden: true)
        XCTAssertEqual(boxesForReview([shown, hidden], section: .together), [shown])
        XCTAssertEqual(ReviewSection.together.title, "Together")
    }

    func testSectionShowsOnlyItsMolesAtTheCroppedScale() {
        let topLeft = mole(x: 0.1, y: 0.1, width: 0.2, height: 0.2, hidden: false)
        let bottomRight = mole(x: 0.6, y: 0.7, width: 0.2, height: 0.1, hidden: false)
        let hidden = mole(x: 0.1, y: 0.1, width: 0.1, height: 0.1, hidden: true)
        let shown = boxesForReview([topLeft, bottomRight, hidden], section: .topLeft)
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown[0].x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(shown[0].y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(shown[0].width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(shown[0].height, 0.4, accuracy: 0.0001)
        XCTAssertEqual(ReviewSection.topLeft.title, "Top left")
        XCTAssertEqual(ReviewSection.topRight.title, "Top right")
        XCTAssertEqual(ReviewSection.bottomLeft.title, "Bottom left")
        XCTAssertEqual(ReviewSection.bottomRight.title, "Bottom right")
    }

    func testSectionClipsAMoleThatCrossesTheBoundary() {
        let crossing = mole(x: 0.4, y: 0.4, width: 0.2, height: 0.2, hidden: false)
        let shown = boxesForReview([crossing], section: .topLeft)
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown[0].x, 0.8, accuracy: 0.0001)
        XCTAssertEqual(shown[0].y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(shown[0].width, 0.2, accuracy: 0.0001)
        XCTAssertEqual(shown[0].height, 0.2, accuracy: 0.0001)
        let right = boxesForReview([crossing], section: .topRight)
        XCTAssertEqual(right[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(right[0].width, 0.2, accuracy: 0.0001)
    }

    func testMoleNumbersRunTopToBottomThenLeftToRight() {
        let lower = mole(x: 0.2, y: 0.6, width: 0.1, height: 0.1, hidden: false)
        let upperRight = mole(x: 0.7, y: 0.2, width: 0.1, height: 0.1, hidden: false)
        let upperLeft = mole(x: 0.1, y: 0.2, width: 0.1, height: 0.1, hidden: false)
        let hidden = mole(x: 0.05, y: 0.05, width: 0.1, height: 0.1, hidden: true)
        let numbered = moleNumbers([lower, upperRight, upperLeft, hidden])
        XCTAssertEqual(numbered.map(\.number), [4, 3, 2, 1])
        XCTAssertEqual(boxesForReview(numbered, section: .together).map(\.number), [4, 3, 2])
        XCTAssertEqual(boxesForReview(numbered, section: .topLeft).map(\.number), [2])
    }

    func testHiddenBoxesAreOmitted() {
        let shown = MoleBoxDraft(x: 0, y: 0, width: 0.1, height: 0.1, confidence: 0.4, label: "Mole", hidden: false)
        let hidden = MoleBoxDraft(x: 0.2, y: 0.2, width: 0.1, height: 0.1, confidence: 0.8, label: "Mole", hidden: true)
        XCTAssertEqual(visibleBoxes([shown, hidden]), [shown])
    }

    private func mole(x: Double, y: Double, width: Double, height: Double, hidden: Bool) -> MoleBoxDraft {
        MoleBoxDraft(x: x, y: y, width: width, height: height, confidence: 0.5, label: "Mole", hidden: hidden)
    }
}
