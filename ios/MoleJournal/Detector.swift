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
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width > 0, image.height > 0
        else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let input = modelInputSize(mlModel)
        let windows = sliceWindows(
            imageWidth: image.width,
            imageHeight: image.height,
            sliceWidth: input.width,
            sliceHeight: input.height
        )
        guard !windows.isEmpty else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        var found: [SliceBox] = []
        for window in windows {
            switch readSlice(
                image: image,
                window: window,
                visionModel: visionModel,
                modelWidth: input.width,
                modelHeight: input.height
            ) {
            case .failed:
                return DetectionOutcome(boxes: [], outlinesUnavailable: true)
            case .found(let boxes):
                found.append(contentsOf: boxes)
            }
        }
        return DetectionOutcome(
            boxes: moleDrafts(from: greedyNMM(found), imageWidth: image.width, imageHeight: image.height),
            outlinesUnavailable: false
        )
    }
}

private enum SliceRead {
    case found([SliceBox])
    case failed
}

private func readSlice(
    image: CGImage,
    window: SliceWindow,
    visionModel: VNCoreMLModel,
    modelWidth: Int,
    modelHeight: Int
) -> SliceRead {
    let cropWidth = window.maxX - window.minX
    let cropHeight = window.maxY - window.minY
    guard
        cropWidth >= 1, cropHeight >= 1,
        let crop = image.cropping(to: CGRect(x: window.minX, y: window.minY, width: cropWidth, height: cropHeight)),
        let letterboxed = letterboxedImage(crop, modelWidth: modelWidth, modelHeight: modelHeight)
    else {
        return .failed
    }
    let request = VNCoreMLRequest(model: visionModel)
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(cgImage: letterboxed, orientation: .up)
    do {
        try handler.perform([request])
    } catch {
        return .failed
    }
    let arrays = request.results?.compactMap {
        ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
    } ?? []
    if let rows = arrays.compactMap(endToEndRows).first {
        return .found(sliceBoxesFromEndToEnd(
            rows: rows,
            modelWidth: modelWidth,
            modelHeight: modelHeight,
            cropWidth: crop.width,
            cropHeight: crop.height,
            originX: window.minX,
            originY: window.minY
        ))
    }
    let observations = request.results?.compactMap { $0 as? VNRecognizedObjectObservation } ?? []
    guard !observations.isEmpty else { return .failed }
    let boxes = observations.compactMap { observation -> SliceBox? in
        guard observation.labels.first?.identifier == "Mole", observation.confidence >= 0.40 else { return nil }
        let rect = topLeftRect(
            visionMinX: observation.boundingBox.minX,
            visionMinY: observation.boundingBox.minY,
            visionWidth: observation.boundingBox.width,
            visionHeight: observation.boundingBox.height
        )
        let pixels = scaleModelBox(
            x1: rect.x * Double(modelWidth),
            y1: rect.y * Double(modelHeight),
            x2: (rect.x + rect.width) * Double(modelWidth),
            y2: (rect.y + rect.height) * Double(modelHeight),
            modelWidth: modelWidth,
            modelHeight: modelHeight,
            imageWidth: crop.width,
            imageHeight: crop.height
        )
        guard pixels.x2 > pixels.x1, pixels.y2 > pixels.y1 else { return nil }
        return shiftSliceBox(
            SliceBox(x1: pixels.x1, y1: pixels.y1, x2: pixels.x2, y2: pixels.y2, score: Double(observation.confidence)),
            originX: window.minX,
            originY: window.minY
        )
    }
    return .found(boxes)
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
