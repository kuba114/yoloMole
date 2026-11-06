import UIKit
import XCTest
@testable import MoleJournal

final class ComparisonTests: XCTestCase {
    func testEachSideExcludesTheOtherCheckIn() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let selection = ComparisonSelection(leftID: a, rightID: b)
        XCTAssertEqual(choices(for: .left, selection: selection, newestFirst: [a, b, c]), [a, c])
        XCTAssertEqual(choices(for: .right, selection: selection, newestFirst: [a, b, c]), [b, c])
    }

    func testSectionCropIsOneQuarterOfThePhoto() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let cropped = croppedPhoto(image, section: .topLeft)
        XCTAssertEqual(cropped.cgImage?.width, 50)
        XCTAssertEqual(cropped.cgImage?.height, 100)
        let whole = croppedPhoto(image, section: .together)
        XCTAssertEqual(whole.cgImage?.width, 100)
        XCTAssertEqual(whole.cgImage?.height, 200)
    }
}
