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
