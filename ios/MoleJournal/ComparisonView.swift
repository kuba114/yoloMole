import SwiftUI
import UIKit

enum ComparisonSide {
    case left
    case right
}

func choices(for side: ComparisonSide, selection: ComparisonSelection, newestFirst: [UUID]) -> [UUID] {
    let other = side == .left ? selection.rightID : selection.leftID
    return newestFirst.filter { $0 != other }
}

struct ComparisonView: View {
    let checkIns: [CheckInRecord]
    let image: (String) -> UIImage?
    @State private var selection: ComparisonSelection

    init(checkIns: [CheckInRecord], image: @escaping (String) -> UIImage?) {
        self.checkIns = checkIns
        self.image = image
        let ids = checkIns.map(\.id)
        guard let selection = defaultComparison(newestFirst: ids) else {
            preconditionFailure("ComparisonView requires two check-ins")
        }
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let ids = checkIns.map(\.id)
        VStack {
            HStack {
                photo(id: selection.leftID)
                photo(id: selection.rightID)
            }
            Picker("Left", selection: $selection.leftID) {
                ForEach(choices(for: .left, selection: selection, newestFirst: ids), id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }
            Picker("Right", selection: $selection.rightID) {
                ForEach(choices(for: .right, selection: selection, newestFirst: ids), id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }
        }
    }

    private func photo(id: UUID) -> some View {
        let checkIn = checkIns.first { $0.id == id }
        return VStack {
            if let checkIn, let uiImage = image(checkIn.imageFilename) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: visibleBoxes(checkIn.boxes.map(draft)))
                    }
            }
            if let checkIn {
                Text(checkIn.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func label(for id: UUID) -> String {
        checkIns.first { $0.id == id }?.capturedAt.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    private func draft(_ box: MoleBoxRecord) -> MoleBoxDraft {
        MoleBoxDraft(
            x: box.x, y: box.y, width: box.width, height: box.height,
            confidence: box.confidence, label: box.label, hidden: box.hidden
        )
    }
}
