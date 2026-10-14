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
/// On the home screen a "Scan Label" hint and a hand-drawn arrow point to it; they are
/// part of the same button, so tapping the hint opens the camera too.
struct CameraButton: View {
    static let size: CGFloat = 72
    /// Distance from the physical bottom of the screen: the camera view's 10pt edge gap
    /// plus 24pt inside it, so the button sits at the same spot on both screens.
    static let bottomInset: CGFloat = 34

    /// Leave quickly as the camera grows; return once it has shrunk back.
    private static let hintTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.3)),
        removal: .opacity.animation(.easeOut(duration: 0.12))
    )

    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 28) {
                if !isScanning {
                    Text("Scan Label")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(white: 0.1))
                        .transition(Self.hintTransition)
                }

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
                    // The arrow curls from under the text into the button's left side.
                    .overlay(alignment: .leading) {
                        if !isScanning {
                            ScanArrow()
                                .frame(width: 56, height: 78)
                                .offset(x: -62, y: -24)
                                .transition(Self.hintTransition)
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(isScanning ? "Close camera" : "Scan Label")
        .accessibilityHint(isScanning ? "" : "Opens the camera to read your prescription label")
        // A light tap of vibration each time the camera opens or closes.
        .sensoryFeedback(.impact(weight: .light), trigger: isScanning)
        .padding(.bottom, Self.bottomInset)
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    ContentView()
}
