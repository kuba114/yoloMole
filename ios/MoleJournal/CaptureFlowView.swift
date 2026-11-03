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
            if let accepted, let image = UIImage(data: accepted.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: boxesForReview(moleNumbers(drafts), section: .together))
                    }
            }
            ForEach(moleNumbers(drafts)) { item in
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
                outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
                step = advanceToCamera(initialCaptureStep(previousImageFilename: previousFilename))
            }
            Button("Save") {
                guard let accepted else { return }
                onSave(accepted, DetectionOutcome(boxes: drafts, outlinesUnavailable: outcome.outlinesUnavailable))
            }
            Button("Cancel", action: onCancel)
        }
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
