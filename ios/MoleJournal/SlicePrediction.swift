import Foundation

struct SliceWindow: Equatable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
}

struct SliceBox: Equatable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var score: Double
}

func sliceWindows(
    imageWidth: Int,
    imageHeight: Int,
    sliceWidth: Int = 800,
    sliceHeight: Int = 800,
    overlapWidthRatio: Double = 0.20,
    overlapHeightRatio: Double = 0.20
) -> [SliceWindow] {
    guard imageWidth > 0, imageHeight > 0, sliceWidth > 0, sliceHeight > 0 else { return [] }
    guard overlapWidthRatio < 1, overlapHeightRatio < 1 else { return [] }
    let xOverlap = Int(overlapWidthRatio * Double(sliceWidth))
    let yOverlap = Int(overlapHeightRatio * Double(sliceHeight))
    var windows: [SliceWindow] = []
    var yMax = 0
    var yMin = 0
    while yMax < imageHeight {
        var xMin = 0
        var xMax = 0
        yMax = yMin + sliceHeight
        while xMax < imageWidth {
            xMax = xMin + sliceWidth
            if yMax > imageHeight || xMax > imageWidth {
                xMax = min(imageWidth, xMax)
                yMax = min(imageHeight, yMax)
                xMin = max(0, xMax - sliceWidth)
                yMin = max(0, yMax - sliceHeight)
            }
            windows.append(SliceWindow(minX: xMin, minY: yMin, maxX: xMax, maxY: yMax))
            xMin = xMax - xOverlap
        }
        yMin = yMax - yOverlap
    }
    return windows
}

func shiftSliceBox(_ box: SliceBox, originX: Int, originY: Int) -> SliceBox {
    SliceBox(
        x1: box.x1 + Double(originX),
        y1: box.y1 + Double(originY),
        x2: box.x2 + Double(originX),
        y2: box.y2 + Double(originY),
        score: box.score
    )
}

func sliceBoxesFromEndToEnd(
    rows: [[Double]],
    modelWidth: Int,
    modelHeight: Int,
    cropWidth: Int,
    cropHeight: Int,
    originX: Int,
    originY: Int,
    minimumConfidence: Double = 0.40
) -> [SliceBox] {
    rows.compactMap { row in
        guard row.count >= 6, row[4] >= minimumConfidence, Int(row[5].rounded()) == 1 else { return nil }
        let scaled = scaleModelBox(
            x1: row[0], y1: row[1], x2: row[2], y2: row[3],
            modelWidth: modelWidth, modelHeight: modelHeight,
            imageWidth: cropWidth, imageHeight: cropHeight
        )
        guard scaled.x2 > scaled.x1, scaled.y2 > scaled.y1 else { return nil }
        return shiftSliceBox(
            SliceBox(x1: scaled.x1, y1: scaled.y1, x2: scaled.x2, y2: scaled.y2, score: row[4]),
            originX: originX,
            originY: originY
        )
    }
}

func intersectionOverUnion(_ a: SliceBox, _ b: SliceBox) -> Double {
    let width = max(0, min(a.x2, b.x2) - max(a.x1, b.x1))
    let height = max(0, min(a.y2, b.y2) - max(a.y1, b.y1))
    let intersection = width * height
    let union = max(0, a.x2 - a.x1) * max(0, a.y2 - a.y1) + max(0, b.x2 - b.x1) * max(0, b.y2 - b.y1) - intersection
    guard union > 0 else { return 0 }
    return intersection / union
}

func greedyNMM(_ boxes: [SliceBox], matchThreshold: Double = 0.5) -> [SliceBox] {
    let order = boxes.indices.sorted { lhs, rhs in
        let a = boxes[lhs]
        let b = boxes[rhs]
        if a.score != b.score { return a.score > b.score }
        if a.x1 != b.x1 { return a.x1 < b.x1 }
        if a.y1 != b.y1 { return a.y1 < b.y1 }
        if a.x2 != b.x2 { return a.x2 < b.x2 }
        return a.y2 < b.y2
    }
    var suppressed = Array(repeating: false, count: boxes.count)
    var kept: [SliceBox] = []
    for (position, index) in order.enumerated() {
        if suppressed[index] { continue }
        let original = boxes[index]
        var current = original
        let matches = order.dropFirst(position + 1).filter { candidate in
            !suppressed[candidate] && intersectionOverUnion(original, boxes[candidate]) >= matchThreshold
        }
        for candidate in matches {
            suppressed[candidate] = true
        }
        for candidate in matches where intersectionOverUnion(current, boxes[candidate]) >= matchThreshold {
            current = SliceBox(
                x1: min(current.x1, boxes[candidate].x1),
                y1: min(current.y1, boxes[candidate].y1),
                x2: max(current.x2, boxes[candidate].x2),
                y2: max(current.y2, boxes[candidate].y2),
                score: max(current.score, boxes[candidate].score)
            )
        }
        kept.append(current)
    }
    return kept
}

func moleDrafts(from boxes: [SliceBox], imageWidth: Int, imageHeight: Int) -> [MoleBoxDraft] {
    guard imageWidth > 0, imageHeight > 0 else { return [] }
    return boxes.compactMap { box in
        let width = box.x2 - box.x1
        let height = box.y2 - box.y1
        guard width > 0, height > 0 else { return nil }
        return MoleBoxDraft(
            x: box.x1 / Double(imageWidth),
            y: box.y1 / Double(imageHeight),
            width: width / Double(imageWidth),
            height: height / Double(imageHeight),
            confidence: box.score,
            label: "Mole",
            hidden: false
        )
    }
}
