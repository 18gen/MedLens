//
//  ContentView.swift
//  MedLens
//
//  Created by Gen Ichihashi on 2026-10-14.
//

import SwiftUI

/// The whole app: today's medications above one camera button. Tapping it grows the
/// button's black circle into the live camera view; the same button then closes it.
struct ContentView: View {
    @State private var isScanning = false
    @State private var model = ScannerModel()
    @State private var store = MedicationStore()
    @State private var showingMedications = false
    /// What the latest scan did, shown in the camera view.
    @State private var scanOutcome: ScanOutcome?
    /// Medications already handled while the camera is open, so slightly different reads
    /// of the same bottle ("500 MG" / "500MG") don't count it twice.
    @State private var handledMedicationIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Color.white.ignoresSafeArea()

                    if !isScanning {
                        HomeView(store: store, onShowMedications: { showingMedications = true })
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            // Keep clear of the "Scan Label" hint and button.
                            .padding(.bottom, CameraButton.homeReservedHeight)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(CameraButton.hintTransition)
                    }

                    if isScanning {
                        ScanResultView(model: model)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    }

                    CameraLens(
                        model: model,
                        isOpen: isScanning,
                        // 10pt from each side; about 80% of the screen height.
                        openSize: CGSize(width: proxy.size.width - 20, height: proxy.size.height * 0.8),
                        outcome: scanOutcome,
                        onUndo: undoLastCheck
                    )

                    CameraButton(isScanning: isScanning) {
                        setScanning(!isScanning)
                    }
                }
            }
            .onChange(of: model.medicationName) { _, name in
                guard isScanning, let name else { return }
                handleScan(of: name)
            }
            // After a successful check, close the camera so the ticked row is visible.
            .task(id: scanOutcome) {
                guard isScanning, case .checked = scanOutcome else { return }
                do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
                setScanning(false)
            }
            .sensoryFeedback(trigger: scanOutcome) {
                switch scanOutcome {
                case .checked: return .success
                case .alreadyTaken, .tooEarly: return .warning
                case .notOnList, .unsure, .notScheduledToday: return .error
                case nil: return nil
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
            // Home has its own header instead of a navigation bar.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingMedications) {
                MedicationsPage(medications: store.medications)
            }
        }
    }

    private func setScanning(_ open: Bool) {
        scanOutcome = nil
        handledMedicationIDs = []
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
            isScanning = open
        }
    }

    private func handleScan(of name: String) {
        if case .match(let medication) = MedicationMatcher.match(scannedName: name, in: store.medications) {
            guard !handledMedicationIDs.contains(medication.id) else { return }
            handledMedicationIDs.insert(medication.id)
        }
        let outcome = store.recordScan(scannedName: name)
        scanOutcome = outcome
        AccessibilityNotification.Announcement(ScanOutcomeBanner.announcement(for: outcome)).post()
    }

    private func undoLastCheck() {
        if case .checked(let dose) = scanOutcome {
            store.markNotTaken(dose)
        }
        // Cancels the automatic close too.
        scanOutcome = nil
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

    /// Height at the bottom of the home screen used by the hint and button.
    static let homeReservedHeight: CGFloat = 170

    /// Leave quickly as the camera grows; return once it has shrunk back.
    static let hintTransition = AnyTransition.asymmetric(
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
