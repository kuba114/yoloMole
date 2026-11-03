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

func boxesForReview(_ boxes: [MoleBoxDraft], section: ReviewSection) -> [MoleBoxDraft] {
    let visible = visibleBoxes(boxes)
    guard let rect = sectionRect(section) else { return visible }
    return visible.compactMap { box in
        let x1 = max(box.x, rect.x)
        let y1 = max(box.y, rect.y)
        let x2 = min(box.x + box.width, rect.x + rect.width)
        let y2 = min(box.y + box.height, rect.y + rect.height)
        guard x2 > x1, y2 > y1 else { return nil }
        var clipped = box
        clipped.x = (x1 - rect.x) / rect.width
        clipped.y = (y1 - rect.y) / rect.height
        clipped.width = (x2 - x1) / rect.width
        clipped.height = (y2 - y1) / rect.height
        return clipped
    }
}
