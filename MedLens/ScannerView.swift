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

    var body: some View {
        ZStack {
            Color.black

            if isOpen {
                CameraPreview(session: model.session)
                    .transition(.opacity)

                TextBoxOverlay(lines: model.lines, frameSize: model.frameSize)
                    .transition(.opacity)

                if let message = model.cameraMessage {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(32)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: isOpen ? openSize.width : CameraButton.size,
               height: isOpen ? openSize.height : CameraButton.size)
        // Open: radius roughly follows the screen's rounded corners at a 10pt inset.
        // Closed: half the size, i.e. a circle.
        .clipShape(RoundedRectangle(cornerRadius: isOpen ? 44 : CameraButton.size / 2, style: .continuous))
        // Open: same 10pt gap from the bottom as from the sides.
        .padding(.bottom, isOpen ? 10 : CameraButton.bottomInset)
        .ignoresSafeArea(edges: .bottom)
        .accessibilityHidden(!isOpen)
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
        .animation(.easeOut(duration: 0.2), value: usedLines)
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

/// Shows the live camera feed from an `AVCaptureSession`.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
