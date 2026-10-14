//
//  ScannerView.swift
//  MedLens
//

import SwiftUI
import AVFoundation

/// The medication name and frequency shown above the camera.
struct ScanResultView: View {
    let model: ScannerModel

    var body: some View {
        VStack(spacing: 20) {
            Text(model.medicationName ?? "Scanning...")
                .font(.largeTitle.bold())
                .foregroundStyle(model.medicationName == nil ? .secondary : .primary)
                .minimumScaleFactor(0.5)
                .lineLimit(3)

            Text(model.frequency ?? "Scanning...")
                .font(.title.weight(.semibold))
                .foregroundStyle(model.frequency == nil ? .secondary : .primary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}

/// One black shape that is the camera button's circle when closed and grows into the
/// rounded live camera view when open. Being a single view, it animates size and
/// corner radius smoothly instead of cross-fading between two shapes.
struct CameraLens: View {
    let model: ScannerModel
    let isOpen: Bool
    /// Size of the camera view when open.
    let openSize: CGSize
    /// Result of the latest scan, shown as a banner above the close button.
    var outcome: ScanOutcome? = nil
    var onUndo: () -> Void = {}

    /// Where the user last tapped to focus, shown briefly as a square.
    @State private var focusMark: CGPoint?
    @State private var focusTapCount = 0

    var body: some View {
        ZStack {
            Color.black

            if isOpen {
                CameraPreview(session: model.session) { devicePoint, viewPoint in
                    model.focus(at: devicePoint)
                    focusMark = viewPoint
                    focusTapCount += 1
                }
                .transition(.opacity)

                TextBoxOverlay(lines: model.lines, frameSize: model.frameSize)
                    .transition(.opacity)

                if let focusMark {
                    FocusMark()
                        .position(focusMark)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                }

                if let message = model.cameraMessage {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(32)
                        .transition(.opacity)
                }

                if let outcome {
                    VStack {
                        Spacer()
                        ScanOutcomeBanner(outcome: outcome, onUndo: onUndo)
                    }
                    .padding(.horizontal, 12)
                    // Sit just above the close button.
                    .padding(.bottom, CameraButton.size + 24 + 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(outcome)
                }
            }
        }
        .animation(.spring(duration: 0.4), value: outcome)
        .frame(width: isOpen ? openSize.width : CameraButton.size,
               height: isOpen ? openSize.height : CameraButton.size)
        // Open: radius roughly follows the screen's rounded corners at a 10pt inset.
        // Closed: half the size, i.e. a circle.
        .clipShape(RoundedRectangle(cornerRadius: isOpen ? 44 : CameraButton.size / 2, style: .continuous))
        // Open: same 10pt gap from the bottom as from the sides.
        .padding(.bottom, isOpen ? 10 : CameraButton.bottomInset)
        .ignoresSafeArea(edges: .bottom)
        .accessibilityHidden(!isOpen)
        // Hide the focus square a moment after each tap.
        .task(id: focusTapCount) {
            guard focusMark != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.3)) { focusMark = nil }
        }
        .animation(.easeOut(duration: 0.2), value: focusTapCount)
    }
}

/// Tells the person what their scan did: checked a dose, warned about a double dose,
/// too early, or not one of their medications.
struct ScanOutcomeBanner: View {
    let outcome: ScanOutcome
    let onUndo: () -> Void

    var body: some View {
        let content = Self.content(for: outcome)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: content.icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(content.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.headline)
                    .foregroundStyle(.black)
                Text(content.message)
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if case .checked = outcome {
                Button("Undo", action: onUndo)
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .tint(.black)
                    .accessibilityHint("Marks this dose as not taken")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
    }

    /// Spoken by VoiceOver when the banner appears.
    static func announcement(for outcome: ScanOutcome) -> String {
        let content = content(for: outcome)
        return "\(content.title). \(content.message)"
    }

    private static func content(for outcome: ScanOutcome) -> (icon: String, color: Color, title: String, message: String) {
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

        switch outcome {
        case .checked(let dose):
            return ("checkmark.circle.fill", Palette.taken,
                    "Checked: \(dose.medication.displayName)",
                    "\(time(dose.scheduled)) dose marked as taken.")
        case .alreadyTaken(let dose, let takenAt, let next):
            let nextText = next.map { "Next dose at \(time($0.scheduled))." } ?? "No more doses today."
            return ("exclamationmark.triangle.fill", Palette.late,
                    "Already taken today",
                    "\(dose.medication.displayName) was taken at \(time(takenAt)). \(nextText)")
        case .tooEarly(let next):
            return ("clock.fill", Palette.late,
                    "Not time yet",
                    "Next \(next.medication.displayName) dose is at \(time(next.scheduled)).")
        case .notScheduledToday(let medication):
            return ("info.circle.fill", Color(white: 0.45),
                    "No dose to take now",
                    "\(medication.displayName) has no more doses today.")
        case .notOnList(let scannedName):
            return ("questionmark.circle.fill", Color(white: 0.45),
                    "Not on your list",
                    "\(scannedName) isn't one of your medications.")
        case .unsure:
            return ("questionmark.circle.fill", Color(white: 0.45),
                    "Not sure which medication",
                    "Check the label and try again.")
        }
    }
}

/// Draws a box around only the text MedLens actually uses: yellow for the line the
/// medication name comes from, cyan for the frequency line(s). Other text is not boxed.
struct TextBoxOverlay: View {
    let lines: [RecognizedLine]
    let frameSize: CGSize

    private var usedLines: [RecognizedLine] {
        lines.filter { $0.role != .other }
    }

    var body: some View {
        GeometryReader { proxy in
            if frameSize.width > 0, frameSize.height > 0 {
                ForEach(Array(usedLines.enumerated()), id: \.offset) { _, line in
                    let rect = Self.viewRect(for: line.box, frameSize: frameSize, viewSize: proxy.size)
                        .insetBy(dx: -4, dy: -3)
                    let color = Self.color(for: line.role)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.25))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(color, lineWidth: 0.5)
                                // Dark edge keeps yellow and cyan outlines visible on white labels.
                                .shadow(color: .black.opacity(0.6), radius: 1)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        // Glide boxes between frames instead of jumping.
        .animation(.easeOut(duration: 0.1), value: usedLines)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func color(for role: RecognizedLine.Role) -> Color {
        role == .name ? .yellow : .cyan
    }

    /// Maps Vision's normalized box (origin bottom-left) onto the preview, which shows the
    /// camera frame scaled to fill the view and cropped equally on both sides.
    static func viewRect(for box: CGRect, frameSize: CGSize, viewSize: CGSize) -> CGRect {
        let scale = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let shown = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        let offset = CGPoint(x: (viewSize.width - shown.width) / 2, y: (viewSize.height - shown.height) / 2)
        return CGRect(
            x: offset.x + box.minX * shown.width,
            y: offset.y + (1 - box.maxY) * shown.height,
            width: box.width * shown.width,
            height: box.height * shown.height
        )
    }
}

/// Small square marking where the user tapped to focus, like the Camera app.
struct FocusMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Shows the live camera feed from an `AVCaptureSession`. Tapping it reports the point in
/// camera device coordinates (for focusing) and in view coordinates (for the focus square).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onTap = onTap
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint, CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let viewPoint = gesture.location(in: self)
            // Accounts for the preview's rotation and aspect-fill crop.
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onTap?(devicePoint, viewPoint)
        }
    }
}
