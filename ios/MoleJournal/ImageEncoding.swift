import Foundation
import UIKit

struct DetectionOutcome: Equatable {
    var boxes: [MoleBoxDraft]
    var outlinesUnavailable: Bool
}

protocol MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome
}

struct UnavailableDetector: MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome {
        DetectionOutcome(boxes: [], outlinesUnavailable: true)
    }
}

struct UprightImage {
    var width: Int
    var height: Int
    var jpeg: Data
}

func uprightSize(width: Int, height: Int, orientationIsRotated: Bool) -> (width: Int, height: Int) {
    orientationIsRotated ? (height, width) : (width, height)
}

func reviewMessage(_ outcome: DetectionOutcome) -> String? {
    outcome.outlinesUnavailable ? Copy.outlinesUnavailable : nil
}

func jpegData(from image: UIImage) -> UprightImage? {
    let rotated = image.imageOrientation != .up
    let size = uprightSize(
        width: Int(image.size.width * image.scale),
        height: Int(image.size.height * image.scale),
        orientationIsRotated: rotated
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: size.width, height: size.height),
        format: format
    )
    let rendered = renderer.image { _ in
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
    guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return nil }
    return UprightImage(width: size.width, height: size.height, jpeg: jpeg)
}

func croppedUprightImage(_ image: UprightImage, crop: CropRect) -> UprightImage? {
    let rect = crop.rect
    if rect.x == 0, rect.y == 0, rect.width == 1, rect.height == 1 {
        return image
    }
    guard let source = UIImage(data: image.jpeg)?.cgImage else { return nil }
    let cropRect = CGRect(
        x: CGFloat(rect.x) * CGFloat(source.width),
        y: CGFloat(rect.y) * CGFloat(source.height),
        width: CGFloat(rect.width) * CGFloat(source.width),
        height: CGFloat(rect.height) * CGFloat(source.height)
    ).integral
    guard cropRect.width >= 1, cropRect.height >= 1, let cropped = source.cropping(to: cropRect) else { return nil }
    let rendered = UIImage(cgImage: cropped, scale: 1, orientation: .up)
    guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return nil }
    return UprightImage(width: cropped.width, height: cropped.height, jpeg: jpeg)
}
