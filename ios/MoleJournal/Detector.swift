import Foundation
import Vision
import CoreML

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

struct CoreMLMoleDetector: MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome {
        guard
            let modelURL = Bundle.main.url(forResource: "MoleModel", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: modelURL),
            let visionModel = try? VNCoreMLModel(for: mlModel)
        else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(data: jpeg, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let rows = observations.map { observation in
            let rect = topLeftRect(
                visionMinX: observation.boundingBox.minX,
                visionMinY: observation.boundingBox.minY,
                visionWidth: observation.boundingBox.width,
                visionHeight: observation.boundingBox.height
            )
            let label = observation.labels.first?.identifier ?? ""
            return (
                label: label,
                confidence: Double(observation.confidence),
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        }
        return DetectionOutcome(boxes: keepMoleObservations(rows), outlinesUnavailable: false)
    }
}
