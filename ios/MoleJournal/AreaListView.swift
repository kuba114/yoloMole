import AVFoundation
import SwiftData
import SwiftUI
import UIKit

func canSaveAreaName(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct AreaListView: View {
    @Bindable var store: JournalStoreModel
    var onSignOut: () -> Void = {}
    var onDeleteAccount: () -> Void = {}
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            List(store.areas) { area in
                NavigationLink(area.name) {
                    AreaDetailView(store: store, areaID: area.id)
                }
            }
            .overlay {
                if store.areas.isEmpty {
                    Text("Add a body area")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Body area", text: $draftName)
                    Button("Add") {
                        store.addArea(name: draftName)
                        draftName = ""
                    }
                    .disabled(!canSaveAreaName(draftName))
                }
                .padding()
            }
            .navigationTitle("Body areas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out", action: onSignOut)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete account", action: onDeleteAccount)
                }
            }
        }
    }
}

@MainActor
@Observable
final class JournalStoreModel {
    private(set) var areas: [BodyAreaRecord] = []
    let sessionAppleID: String
    private let store: JournalStore

    init(store: JournalStore, sessionAppleID: String) {
        self.store = store
        self.sessionAppleID = sessionAppleID
        reload()
    }

    func reload() {
        areas = (try? store.areas(sessionAppleID: sessionAppleID)) ?? []
    }

    func addArea(name: String) {
        guard canSaveAreaName(name) else { return }
        _ = try? store.createArea(name: name, now: Date())
        reload()
    }

    func checkIns(areaID: UUID) -> [CheckInRecord] {
        (try? store.checkIns(areaID: areaID, sessionAppleID: sessionAppleID)) ?? []
    }

    func setBoxHidden(boxID: UUID, hidden: Bool) {
        try? store.setBoxHidden(boxID: boxID, sessionAppleID: sessionAppleID, hidden: hidden)
        reload()
    }

    func imageURL(filename: String) -> URL {
        store.imageURL(filename: filename)
    }

    func saveCheckIn(areaID: UUID, upright: UprightImage, outcome: DetectionOutcome) {
        _ = try? store.saveCheckIn(
            areaID: areaID,
            sessionAppleID: sessionAppleID,
            jpeg: upright.jpeg,
            pixelWidth: upright.width,
            pixelHeight: upright.height,
            boxes: outcome.boxes,
            capturedAt: Date()
        )
        reload()
    }
}

struct AreaDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID
    @State private var showCapture = false
    @State private var cameraDenied = false

    var body: some View {
        let items = store.checkIns(areaID: areaID)
        List(items) { item in
            NavigationLink {
                CheckInDetailView(store: store, areaID: areaID, checkInID: item.id)
            } label: {
                HStack(spacing: 12) {
                    checkInThumbnail(item)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        Text(catalogMoleCount(item.boxes.map(\.label)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(store.areas.first { $0.id == areaID }?.name ?? "")
        .toolbar {
            Button("New check-in") {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .denied || status == .restricted {
                    cameraDenied = true
                } else {
                    showCapture = true
                }
            }
            if items.count >= 2 {
                NavigationLink("Compare") {
                    ComparisonView(checkIns: items) { filename in
                        UIImage(contentsOfFile: store.imageURL(filename: filename).path)
                    }
                }
            }
        }
        .alert(Copy.cameraRequired, isPresented: $cameraDenied) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Close", role: .cancel) {}
        }
        .sheet(isPresented: $showCapture) {
            let latest = items.first
            CaptureFlowView(
                previousImage: latest.flatMap {
                    UIImage(contentsOfFile: store.imageURL(filename: $0.imageFilename).path)
                },
                previousFilename: latest?.imageFilename,
                detector: CoreMLMoleDetector(),
                onSave: { upright, outcome in
                    store.saveCheckIn(areaID: areaID, upright: upright, outcome: outcome)
                    showCapture = false
                },
                onCancel: { showCapture = false },
                onCameraDenied: {
                    showCapture = false
                    cameraDenied = true
                }
            )
        }
    }

    @ViewBuilder
    private func checkInThumbnail(_ item: CheckInRecord) -> some View {
        if let uiImage = UIImage(contentsOfFile: store.imageURL(filename: item.imageFilename).path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
        }
    }
}

struct ReviewSectionControl: View {
    @Binding var section: ReviewSection

    var body: some View {
        VStack(spacing: 8) {
            sectionButton(.together)
            HStack(spacing: 8) {
                sectionButton(.topLeft)
                sectionButton(.topRight)
            }
            HStack(spacing: 8) {
                sectionButton(.bottomLeft)
                sectionButton(.bottomRight)
            }
        }
        .buttonStyle(.bordered)
    }

    private func sectionButton(_ item: ReviewSection) -> some View {
        Button(item.title) { section = item }
            .tint(section == item ? Color.accentColor : Color.secondary)
    }
}

struct CheckInDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID
    let checkInID: UUID
    @State private var section = ReviewSection.together

    var body: some View {
        let checkIn = store.checkIns(areaID: areaID).first { $0.id == checkInID }
        ScrollView {
            VStack(spacing: 16) {
                ReviewSectionControl(section: $section)
                if let checkIn, let uiImage = UIImage(contentsOfFile: store.imageURL(filename: checkIn.imageFilename).path) {
                    Image(uiImage: croppedPhoto(uiImage, section: section))
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            BoxOverlay(boxes: boxesForReview(moleNumbers(checkIn.boxes.map(boxDraft)), section: section))
                        }
                }
                if let checkIn {
                    let numbered = moleNumbers(checkIn.boxes.map(boxDraft))
                    ForEach(numbered) { item in
                        HStack {
                            MoleNumberLabel(number: item.number)
                            Button(item.box.hidden ? "Unhide box" : "Hide box") {
                                store.setBoxHidden(boxID: checkIn.boxes[item.index].id, hidden: !item.box.hidden)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func boxDraft(_ box: MoleBoxRecord) -> MoleBoxDraft {
        MoleBoxDraft(
            x: box.x, y: box.y, width: box.width, height: box.height,
            confidence: box.confidence, label: box.label, hidden: box.hidden
        )
    }
}
