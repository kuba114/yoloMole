import CoreML
import Foundation
import ImageIO
import Vision

func normalizedRect(
    x1: Double,
    y1: Double,
    x2: Double,
    y2: Double,
    imageWidth: Int,
    imageHeight: Int
) -> MoleBoxDraft {
    MoleBoxDraft(
        x: x1 / Double(imageWidth),
        y: y1 / Double(imageHeight),
        width: (x2 - x1) / Double(imageWidth),
        height: (y2 - y1) / Double(imageHeight),
        confidence: 0.30,
        label: "Mole",
        hidden: false
    )
}

func topLeftRect(
    visionMinX: Double,
    visionMinY: Double,
    visionWidth: Double,
    visionHeight: Double
) -> (x: Double, y: Double, width: Double, height: Double) {
    (
        x: visionMinX,
        y: 1 - (visionMinY + visionHeight),
        width: visionWidth,
        height: visionHeight
    )
}

func keepMoleObservations(
    _ rows: [(label: String, confidence: Double, x: Double, y: Double, width: Double, height: Double)]
) -> [MoleBoxDraft] {
    rows.compactMap { row in
        guard row.label == "Mole", row.confidence >= 0.30 else { return nil }
        return MoleBoxDraft(
            x: row.x,
            y: row.y,
            width: row.width,
            height: row.height,
            confidence: row.confidence,
            label: "Mole",
            hidden: false
        )
    }
}

struct LetterboxPlacement: Equatable {
    var resizedWidth: Int
    var resizedHeight: Int
    var padX: Int
    var padY: Int
    var gainX: Double
    var gainY: Double
}

func letterboxPlacement(imageWidth: Int, imageHeight: Int, modelWidth: Int, modelHeight: Int) -> LetterboxPlacement {
    let gain = min(Double(modelHeight) / Double(imageHeight), Double(modelWidth) / Double(imageWidth))
    let resizedWidth = max(Int((Double(imageWidth) * gain).rounded()), 1)
    let resizedHeight = max(Int((Double(imageHeight) * gain).rounded()), 1)
    return LetterboxPlacement(
        resizedWidth: resizedWidth,
        resizedHeight: resizedHeight,
        padX: Int((Double(modelWidth - resizedWidth) / 2.0 - 0.1).rounded()),
        padY: Int((Double(modelHeight - resizedHeight) / 2.0 - 0.1).rounded()),
        gainX: Double(resizedWidth) / Double(imageWidth),
        gainY: Double(resizedHeight) / Double(imageHeight)
    )
}

func scaleModelBox(
    x1: Double,
    y1: Double,
    x2: Double,
    y2: Double,
    modelWidth: Int,
    modelHeight: Int,
    imageWidth: Int,
    imageHeight: Int
) -> (x1: Double, y1: Double, x2: Double, y2: Double) {
    let place = letterboxPlacement(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        modelWidth: modelWidth,
        modelHeight: modelHeight
    )
    func clip(_ value: Double, limit: Int) -> Double {
        min(max(value, 0), Double(limit))
    }
    return (
        x1: clip((x1 - Double(place.padX)) / place.gainX, limit: imageWidth),
        y1: clip((y1 - Double(place.padY)) / place.gainY, limit: imageHeight),
        x2: clip((x2 - Double(place.padX)) / place.gainX, limit: imageWidth),
        y2: clip((y2 - Double(place.padY)) / place.gainY, limit: imageHeight)
    )
}

func moleBoxesFromEndToEnd(
    rows: [[Double]],
    modelWidth: Int,
    modelHeight: Int,
    imageWidth: Int,
    imageHeight: Int
) -> [MoleBoxDraft] {
    rows.compactMap { row in
        guard row.count >= 6, row[4] >= 0.30, Int(row[5].rounded()) == 1 else { return nil }
        let scaled = scaleModelBox(
            x1: row[0], y1: row[1], x2: row[2], y2: row[3],
            modelWidth: modelWidth, modelHeight: modelHeight,
            imageWidth: imageWidth, imageHeight: imageHeight
        )
        let width = scaled.x2 - scaled.x1
        let height = scaled.y2 - scaled.y1
        guard width > 0, height > 0, imageWidth > 0, imageHeight > 0 else { return nil }
        return MoleBoxDraft(
            x: scaled.x1 / Double(imageWidth),
            y: scaled.y1 / Double(imageHeight),
            width: width / Double(imageWidth),
            height: height / Double(imageHeight),
            confidence: row[4],
            label: "Mole",
            hidden: false
        )
    }
}

func endToEndRows(from array: MLMultiArray) -> [[Double]]? {
    let shape = array.shape.map(\.intValue)
    guard shape.count >= 2, shape.last == 6 else { return nil }
    let count = shape[shape.count - 2]
    guard shape.dropLast(2).allSatisfy({ $0 == 1 }) else { return nil }
    return (0..<count).map { detection in
        (0..<6).map { component in
            let index = shape.dropLast(2).map { _ in NSNumber(value: 0) } + [
                NSNumber(value: detection),
                NSNumber(value: component),
            ]
            return array[index].doubleValue
        }
    }
}

struct CoreMLMoleDetector: MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome {
        guard
            let modelURL = Bundle.main.url(forResource: "MoleModel", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: modelURL),
            let visionModel = try? VNCoreMLModel(for: mlModel),
            let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let input = modelInputSize(mlModel)
        guard let letterboxed = letterboxedImage(image, modelWidth: input.width, modelHeight: input.height) else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: letterboxed, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let arrays = request.results?.compactMap {
            ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
        } ?? []
        if let rows = arrays.compactMap(endToEndRows).first {
            return DetectionOutcome(
                boxes: moleBoxesFromEndToEnd(
                    rows: rows,
                    modelWidth: input.width,
                    modelHeight: input.height,
                    imageWidth: image.width,
                    imageHeight: image.height
                ),
                outlinesUnavailable: false
            )
        }
        let observations = request.results?.compactMap { $0 as? VNRecognizedObjectObservation } ?? []
        guard !observations.isEmpty else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let rows = observations.map { observation in
            let rect = topLeftRect(
                visionMinX: observation.boundingBox.minX,
                visionMinY: observation.boundingBox.minY,
                visionWidth: observation.boundingBox.width,
                visionHeight: observation.boundingBox.height
            )
            let pixels = scaleModelBox(
                x1: rect.x * Double(input.width),
                y1: rect.y * Double(input.height),
                x2: (rect.x + rect.width) * Double(input.width),
                y2: (rect.y + rect.height) * Double(input.height),
                modelWidth: input.width,
                modelHeight: input.height,
                imageWidth: image.width,
                imageHeight: image.height
            )
            return (
                label: observation.labels.first?.identifier ?? "",
                confidence: Double(observation.confidence),
                x: pixels.x1 / Double(image.width),
                y: pixels.y1 / Double(image.height),
                width: (pixels.x2 - pixels.x1) / Double(image.width),
                height: (pixels.y2 - pixels.y1) / Double(image.height)
            )
        }
        return DetectionOutcome(boxes: keepMoleObservations(rows), outlinesUnavailable: false)
    }
}

private func modelInputSize(_ model: MLModel) -> (width: Int, height: Int) {
    for input in model.modelDescription.inputDescriptionsByName.values {
        if let image = input.imageConstraint, image.pixelsWide > 0, image.pixelsHigh > 0 {
            return (image.pixelsWide, image.pixelsHigh)
        }
    }
    return (800, 800)
}

private func letterboxedImage(_ image: CGImage, modelWidth: Int, modelHeight: Int) -> CGImage? {
    let place = letterboxPlacement(
        imageWidth: image.width,
        imageHeight: image.height,
        modelWidth: modelWidth,
        modelHeight: modelHeight
    )
    guard let context = CGContext(
        data: nil,
        width: modelWidth,
        height: modelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    let gray = 114.0 / 255.0
    context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: modelWidth, height: modelHeight))
    context.interpolationQuality = .high
    context.draw(
        image,
        in: CGRect(
            x: place.padX,
            y: modelHeight - place.padY - place.resizedHeight,
            width: place.resizedWidth,
            height: place.resizedHeight
        )
    )
    return context.makeImage()
}
