//
//  ContentView.swift
//  MedLens
//
//  Created by Gen Ichihashi on 2026-10-14.
//

import SwiftUI

/// The whole app: a white page with one camera button. Tapping it grows the button's
/// black circle into the live camera view; the same button then becomes the close button.
struct ContentView: View {
    @State private var isScanning = false
    @State private var model = ScannerModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.white.ignoresSafeArea()

                if isScanning {
                    ScanResultView(model: model)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                CameraLens(
                    model: model,
                    isOpen: isScanning,
                    // 10pt from each side; about 80% of the screen height.
                    openSize: CGSize(width: proxy.size.width - 20, height: proxy.size.height * 0.8)
                )

                CameraButton(isScanning: isScanning) {
                    withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
                        isScanning.toggle()
                    }
                }
            }
        }
        .task(id: isScanning) {
            if isScanning {
                model.reset()
                await model.start()
            } else {
                model.stop()
            }
        }
    }
}

/// One button in one place: a camera icon on the home screen, an X on the camera screen.
struct CameraButton: View {
    static let size: CGFloat = 72
    /// Distance from the physical bottom of the screen: the camera view's 10pt edge gap
    /// plus 24pt inside it, so the button sits at the same spot on both screens.
    static let bottomInset: CGFloat = 34

    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isScanning ? "xmark" : "camera.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isScanning ? .black : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
                .background {
                    if isScanning {
                        Circle()
                            .fill(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .accessibilityLabel(isScanning ? "Close camera" : "Scan prescription label")
        // A light tap of vibration each time the camera opens or closes.
        .sensoryFeedback(.impact(weight: .light), trigger: isScanning)
        .padding(.bottom, Self.bottomInset)
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ContentView()
}
