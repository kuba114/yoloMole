import Foundation

struct MoleBoxDraft: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double
    var label: String
    var hidden: Bool
}

struct CaptureStep: Equatable {
    enum Phase: Equatable {
        case instruction
        case camera
        case review
    }

    var phase: Phase
    var previousImageFilename: String?
    var instruction: String
    var showsGhost: Bool
}

func initialCaptureStep(previousImageFilename: String?) -> CaptureStep {
    if let previousImageFilename {
        return CaptureStep(
            phase: .instruction,
            previousImageFilename: previousImageFilename,
            instruction: Copy.matchPose,
            showsGhost: false
        )
    }
    return CaptureStep(
        phase: .instruction,
        previousImageFilename: nil,
        instruction: Copy.framingNote,
        showsGhost: false
    )
}

func advanceToCamera(_ step: CaptureStep) -> CaptureStep {
    var next = step
    next.phase = .camera
    next.showsGhost = step.previousImageFilename != nil
    return next
}

struct ComparisonSelection: Equatable {
    var leftID: UUID
    var rightID: UUID
}

func defaultComparison(newestFirst: [UUID]) -> ComparisonSelection? {
    guard newestFirst.count >= 2 else { return nil }
    return ComparisonSelection(leftID: newestFirst[0], rightID: newestFirst[1])
}

func visibleBoxes(_ boxes: [MoleBoxDraft]) -> [MoleBoxDraft] {
    boxes.filter { !$0.hidden }
}

func catalogMoleCount(_ labels: [String]) -> String {
    let count = labels.filter { $0 == "Mole" }.count
    return count == 1 ? "1 mole" : "\(count) moles"
}

enum ReviewSection: String, CaseIterable, Identifiable, Hashable {
    case together
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .together: "Together"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

struct NormalizedRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

func sectionRect(_ section: ReviewSection) -> NormalizedRect? {
    switch section {
    case .together:
        nil
    case .topLeft:
        NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
    case .topRight:
        NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    case .bottomLeft:
        NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
    case .bottomRight:
        NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    }
}

struct NumberedMoleBox: Equatable, Identifiable {
    var number: Int
    var index: Int
    var box: MoleBoxDraft

    var id: Int { number }
}

func moleNumbers(_ boxes: [MoleBoxDraft]) -> [NumberedMoleBox] {
    let ranked = boxes.indices.sorted { lhs, rhs in
        let a = boxes[lhs]
        let b = boxes[rhs]
        if a.y != b.y { return a.y < b.y }
        if a.x != b.x { return a.x < b.x }
        return lhs < rhs
    }
    var numbers = Array(repeating: 0, count: boxes.count)
    for (rank, index) in ranked.enumerated() {
        numbers[index] = rank + 1
    }
    return boxes.indices.map { NumberedMoleBox(number: numbers[$0], index: $0, box: boxes[$0]) }
}

func boxesForReview(_ boxes: [MoleBoxDraft], section: ReviewSection) -> [MoleBoxDraft] {
    boxesForReview(moleNumbers(boxes), section: section).map(\.box)
}

func boxesForReview(_ boxes: [NumberedMoleBox], section: ReviewSection) -> [NumberedMoleBox] {
    let visible = boxes.filter { !$0.box.hidden }
    guard let rect = sectionRect(section) else { return visible }
    return visible.compactMap { item in
        guard let clipped = clipBox(item.box, to: rect) else { return nil }
        return NumberedMoleBox(number: item.number, index: item.index, box: clipped)
    }
}

enum CropEdge {
    case left
    case right
    case top
    case bottom
}

struct CropRect: Equatable {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double

    static let full = CropRect(left: 0, top: 0, right: 1, bottom: 1)

    var rect: NormalizedRect {
        NormalizedRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

func movedCrop(_ crop: CropRect, edge: CropEdge, to position: Double, minimumSpan: Double = 0.2) -> CropRect {
    let position = min(max(position, 0), 1)
    var next = crop
    switch edge {
    case .left:
        next.left = min(position, crop.right - minimumSpan)
    case .right:
        next.right = max(position, crop.left + minimumSpan)
    case .top:
        next.top = min(position, crop.bottom - minimumSpan)
    case .bottom:
        next.bottom = max(position, crop.top + minimumSpan)
    }
    return next
}

func clipBox(_ box: MoleBoxDraft, to rect: NormalizedRect) -> MoleBoxDraft? {
    let x1 = max(box.x, rect.x)
    let y1 = max(box.y, rect.y)
    let x2 = min(box.x + box.width, rect.x + rect.width)
    let y2 = min(box.y + box.height, rect.y + rect.height)
    guard x2 > x1, y2 > y1, rect.width > 0, rect.height > 0 else { return nil }
    var clipped = box
    clipped.x = (x1 - rect.x) / rect.width
    clipped.y = (y1 - rect.y) / rect.height
    clipped.width = (x2 - x1) / rect.width
    clipped.height = (y2 - y1) / rect.height
    return clipped
}

func boxesKeptByCrop(_ boxes: [MoleBoxDraft], crop: CropRect) -> [MoleBoxDraft] {
    boxes.compactMap { clipBox($0, to: crop.rect) }
}
