import XCTest
@testable import MoleJournal

final class SlicePredictionTests: XCTestCase {
    func testSquarePhotoIsOneFullWindow() {
        XCTAssertEqual(
            sliceWindows(imageWidth: 800, imageHeight: 800),
            [SliceWindow(minX: 0, minY: 0, maxX: 800, maxY: 800)]
        )
    }

    func testPhotoSmallerThanTheModelIsOneWindow() {
        XCTAssertEqual(
            sliceWindows(imageWidth: 400, imageHeight: 400),
            [SliceWindow(minX: 0, minY: 0, maxX: 400, maxY: 400)]
        )
    }

    func testWidePhotoPullsTheLastWindowBackToTheEdge() {
        XCTAssertEqual(
            sliceWindows(imageWidth: 1000, imageHeight: 800),
            [
                SliceWindow(minX: 0, minY: 0, maxX: 800, maxY: 800),
                SliceWindow(minX: 200, minY: 0, maxX: 1000, maxY: 800),
            ]
        )
    }

    func testTwelveMegapixelPhotoUsesThirtyFiveFullWindows() {
        let windows = sliceWindows(imageWidth: 4032, imageHeight: 3024)
        XCTAssertEqual(windows.count, 35)
        XCTAssertEqual(windows.first, SliceWindow(minX: 0, minY: 0, maxX: 800, maxY: 800))
        XCTAssertEqual(windows.last, SliceWindow(minX: 3232, minY: 2224, maxX: 4032, maxY: 3024))
        XCTAssertTrue(windows.allSatisfy { $0.maxX - $0.minX == 800 && $0.maxY - $0.minY == 800 })
    }

    func testBoxShiftsByTheWindowOrigin() {
        let shifted = shiftSliceBox(
            SliceBox(x1: 10, y1: 20, x2: 30, y2: 40, score: 0.40),
            originX: 640,
            originY: 1280
        )
        XCTAssertEqual(shifted, SliceBox(x1: 650, y1: 1300, x2: 670, y2: 1320, score: 0.40))
    }

    func testSliceKeepsMoleAtTheConfidenceFloor() {
        let kept = sliceBoxesFromEndToEnd(
            rows: [
                [0, 0, 40, 40, 0.40, 1],
                [0, 0, 40, 40, 0.39, 1],
                [10, 10, 50, 50, 0.90, 0],
            ],
            modelWidth: 800,
            modelHeight: 800,
            cropWidth: 800,
            cropHeight: 800,
            originX: 100,
            originY: 200
        )
        XCTAssertEqual(kept, [SliceBox(x1: 100, y1: 200, x2: 140, y2: 240, score: 0.40)])
    }

    func testGreedyMergeDropsTheBoxThatMissesTheGrownUnion() {
        let merged = greedyNMM([
            SliceBox(x1: 5, y1: 0, x2: 15, y2: 10, score: 0.90),
            SliceBox(x1: 0, y1: 0, x2: 14, y2: 10, score: 0.80),
            SliceBox(x1: 7, y1: 0, x2: 17, y2: 10, score: 0.70),
        ])
        XCTAssertEqual(merged, [SliceBox(x1: 0, y1: 0, x2: 15, y2: 10, score: 0.90)])
    }

    func testDisjointBoxesBothRemain() {
        let merged = greedyNMM([
            SliceBox(x1: 0, y1: 0, x2: 10, y2: 10, score: 0.90),
            SliceBox(x1: 30, y1: 0, x2: 40, y2: 10, score: 0.80),
        ])
        XCTAssertEqual(
            merged,
            [
                SliceBox(x1: 0, y1: 0, x2: 10, y2: 10, score: 0.90),
                SliceBox(x1: 30, y1: 0, x2: 40, y2: 10, score: 0.80),
            ]
        )
    }

    func testEqualScoresMergeIntoTheSmallerX() {
        let merged = greedyNMM([
            SliceBox(x1: 2, y1: 0, x2: 12, y2: 10, score: 0.50),
            SliceBox(x1: 0, y1: 0, x2: 10, y2: 10, score: 0.50),
        ])
        XCTAssertEqual(merged, [SliceBox(x1: 0, y1: 0, x2: 12, y2: 10, score: 0.50)])
    }

    func testMergedBoxIsStoredAsFractionsOfThePhoto() {
        let drafts = moleDrafts(
            from: [SliceBox(x1: 10, y1: 20, x2: 30, y2: 60, score: 0.40)],
            imageWidth: 100,
            imageHeight: 200
        )
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].x, 0.10, accuracy: 0.0001)
        XCTAssertEqual(drafts[0].y, 0.10, accuracy: 0.0001)
        XCTAssertEqual(drafts[0].width, 0.20, accuracy: 0.0001)
        XCTAssertEqual(drafts[0].height, 0.20, accuracy: 0.0001)
        XCTAssertEqual(drafts[0].confidence, 0.40)
        XCTAssertEqual(drafts[0].label, "Mole")
        XCTAssertFalse(drafts[0].hidden)
    }
}
