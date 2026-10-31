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
