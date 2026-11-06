import AVFoundation
import SwiftUI
import UIKit

struct CaptureFlowView: View {
    let previousImage: UIImage?
    let previousFilename: String?
    let detector: any MoleDetecting
    let onSave: (UprightImage, DetectionOutcome) -> Void
    let onCancel: () -> Void
    let onCameraDenied: () -> Void

    @State private var step: CaptureStep
    @State private var accepted: UprightImage?
    @State private var outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
    @State private var drafts: [MoleBoxDraft] = []
    @State private var crop = CropRect.full
    @StateObject private var cameraSession = CameraSession()

    init(
        previousImage: UIImage?,
        previousFilename: String?,
        detector: any MoleDetecting,
        onSave: @escaping (UprightImage, DetectionOutcome) -> Void,
        onCancel: @escaping () -> Void,
        onCameraDenied: @escaping () -> Void
    ) {
        self.previousImage = previousImage
        self.previousFilename = previousFilename
        self.detector = detector
        self.onSave = onSave
        self.onCancel = onCancel
        self.onCameraDenied = onCameraDenied
        _step = State(initialValue: initialCaptureStep(previousImageFilename: previousFilename))
    }

    var body: some View {
        VStack {
            switch step.phase {
            case .instruction:
                instruction
            case .camera:
                camera
            case .review:
                review
            }
        }
        .onDisappear {
            if step.phase != .review {
                accepted = nil
            }
        }
    }

    private var instruction: some View {
        VStack(spacing: 16) {
            if let previousImage, previousFilename != nil {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFit()
            }
            Text(step.instruction)
                .multilineTextAlignment(.center)
            Button("Continue") {
                step = advanceToCamera(step)
            }
            Button("Cancel", action: onCancel)
        }
        .padding()
    }

    private var camera: some View {
        ZStack {
            CameraPreviewView(session: cameraSession.session)
            if step.showsGhost, let previousImage {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.4)
                    .allowsHitTesting(false)
            }
            VStack {
                Spacer()
                Button("Take photo") {
                    cameraSession.capture { image in
                        guard let upright = jpegData(from: image) else { return }
                        accepted = upright
                        outcome = detector.detect(jpeg: upright.jpeg)
                        drafts = outcome.boxes
                        crop = .full
                        step.phase = .review
                        cameraSession.stop()
                    }
                }
                Button("Cancel", action: onCancel)
            }
        }
        .onAppear {
            cameraSession.prepare { granted in
                if !granted { onCameraDenied() }
            }
        }
        .onDisappear { cameraSession.stop() }
    }

    private var review: some View {
        VStack {
            if let message = reviewMessage(outcome) {
                Text(message)
            }
            Text("Drag the edges to remove background.")
                .multilineTextAlignment(.center)
            if let accepted, let image = UIImage(data: accepted.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: boxesForReview(moleNumbers(drafts), section: .together))
                    }
                    .overlay {
                        CropEdges(crop: $crop)
                    }
            }
            ForEach(moleNumbers(drafts).filter { clipBox($0.box, to: crop.rect) != nil }) { item in
                HStack {
                    MoleNumberLabel(number: item.number)
                    Button(item.box.hidden ? "Unhide box" : "Hide box") {
                        drafts[item.index].hidden.toggle()
                    }
                }
            }
            Button("Retake") {
                accepted = nil
                drafts = []
                crop = .full
                outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
                step = advanceToCamera(initialCaptureStep(previousImageFilename: previousFilename))
            }
            Button("Save") {
                guard let accepted, let cropped = croppedUprightImage(accepted, crop: crop) else { return }
                onSave(
                    cropped,
                    DetectionOutcome(
                        boxes: boxesKeptByCrop(drafts, crop: crop),
                        outlinesUnavailable: outcome.outlinesUnavailable
                    )
                )
            }
            Button("Cancel", action: onCancel)
        }
        .padding()
    }
}

private struct CropEdges: View {
    @Binding var crop: CropRect

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                CropDimming(crop: crop, size: size)
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(
                        width: size.width * (crop.right - crop.left),
                        height: size.height * (crop.bottom - crop.top)
                    )
                    .position(
                        x: size.width * (crop.left + crop.right) / 2,
                        y: size.height * (crop.top + crop.bottom) / 2
                    )
                    .allowsHitTesting(false)
                cropHandle(.top, size: size)
                cropHandle(.bottom, size: size)
                cropHandle(.left, size: size)
                cropHandle(.right, size: size)
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: "crop")
        }
    }

    private func cropHandle(_ edge: CropEdge, size: CGSize) -> some View {
        let vertical = edge == .left || edge == .right
        let span = vertical ? size.height * (crop.bottom - crop.top) : size.width * (crop.right - crop.left)
        return Color.clear
            .frame(width: vertical ? 32 : max(span, 32), height: vertical ? max(span, 32) : 32)
            .overlay {
                Rectangle()
                    .fill(Color.white)
                    .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
            }
            .position(handleCenter(edge, size: size))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                    .onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let position = vertical ? value.location.x / size.width : value.location.y / size.height
                        crop = movedCrop(crop, edge: edge, to: position)
                    }
            )
    }

    private func handleCenter(_ edge: CropEdge, size: CGSize) -> CGPoint {
        switch edge {
        case .left:
            CGPoint(x: size.width * crop.left, y: size.height * (crop.top + crop.bottom) / 2)
        case .right:
            CGPoint(x: size.width * crop.right, y: size.height * (crop.top + crop.bottom) / 2)
        case .top:
            CGPoint(x: size.width * (crop.left + crop.right) / 2, y: size.height * crop.top)
        case .bottom:
            CGPoint(x: size.width * (crop.left + crop.right) / 2, y: size.height * crop.bottom)
        }
    }
}

private struct CropDimming: View {
    let crop: CropRect
    let size: CGSize

    var body: some View {
        let width = size.width
        let height = size.height
        ZStack {
            shade(
                width: width,
                height: height * crop.top,
                x: width / 2,
                y: height * crop.top / 2
            )
            shade(
                width: width,
                height: height * (1 - crop.bottom),
                x: width / 2,
                y: height * (crop.bottom + 1) / 2
            )
            shade(
                width: width * crop.left,
                height: height * (crop.bottom - crop.top),
                x: width * crop.left / 2,
                y: height * (crop.top + crop.bottom) / 2
            )
            shade(
                width: width * (1 - crop.right),
                height: height * (crop.bottom - crop.top),
                x: width * (crop.right + 1) / 2,
                y: height * (crop.top + crop.bottom) / 2
            )
        }
        .allowsHitTesting(false)
    }

    private func shade(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Color.black.opacity(0.55)
            .frame(width: max(width, 0), height: max(height, 0))
            .position(x: x, y: y)
    }
}

func croppedPhoto(_ image: UIImage, section: ReviewSection) -> UIImage {
    guard let rect = sectionRect(section) else { return image }
    let upright = uprightPhoto(image)
    guard let cgImage = upright.cgImage else { return image }
    let crop = CGRect(
        x: CGFloat(rect.x) * CGFloat(cgImage.width),
        y: CGFloat(rect.y) * CGFloat(cgImage.height),
        width: CGFloat(rect.width) * CGFloat(cgImage.width),
        height: CGFloat(rect.height) * CGFloat(cgImage.height)
    ).integral
    guard crop.width >= 1, crop.height >= 1, let cropped = cgImage.cropping(to: crop) else { return image }
    return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
}

private func uprightPhoto(_ image: UIImage) -> UIImage {
    guard image.imageOrientation != .up || image.cgImage == nil else { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

struct MoleNumberLabel: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(Color.black.opacity(0.75), in: Capsule())
    }
}

struct BoxOverlay: View {
    let boxes: [NumberedMoleBox]

    var body: some View {
        GeometryReader { proxy in
            ForEach(boxes) { item in
                let box = item.box
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(
                        width: proxy.size.width * box.width,
                        height: proxy.size.height * box.height
                    )
                    .position(
                        x: proxy.size.width * (box.x + box.width / 2),
                        y: proxy.size.height * (box.y + box.height / 2)
                    )
                MoleNumberLabel(number: item.number)
                    .position(x: moleNumberX(box, in: proxy.size), y: moleNumberY(box, in: proxy.size))
            }
        }
    }

    private func moleNumberX(_ box: MoleBoxDraft, in size: CGSize) -> CGFloat {
        min(max(14, size.width * box.x + 14), max(14, size.width - 14))
    }

    private func moleNumberY(_ box: MoleBoxDraft, in size: CGSize) -> CGFloat {
        let top = size.height * box.y
        return top < 20 ? min(top + 14, max(14, size.height - 14)) : top - 14
    }
}

final class CameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "MoleJournal.camera")
    private var onImage: ((UIImage) -> Void)?
    private var configured = false

    func prepare(onGranted: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
            onGranted(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.start() }
                    onGranted(granted)
                }
            }
        default:
            onGranted(false)
        }
    }

    func start() {
        queue.async {
            guard !self.configured else {
                if !self.session.isRunning { self.session.startRunning() }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.output)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.configured = true
            self.session.startRunning()
        }
    }

    func capture(onImage: @escaping (UIImage) -> Void) {
        self.onImage = onImage
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onImage?(image) }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
