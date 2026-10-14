//
//  ScannerModel.swift
//  MedLens
//

import AVFoundation
import Observation
import Vision

/// Runs the camera, reads text with Vision, and publishes what it found.
@Observable
final class ScannerModel {
    private(set) var medicationName: String?
    private(set) var frequency: String?
    private(set) var cameraMessage: String?

    @ObservationIgnored private let camera = CameraSession()
    @ObservationIgnored private var nameReading = StableReading()
    @ObservationIgnored private var frequencyReading = StableReading()

    var session: AVCaptureSession { camera.session }

    func start() async {
        guard await Self.hasCameraPermission() else {
            cameraMessage = "Camera access is off.\nTurn it on in Settings › MedLens."
            return
        }
        camera.onText = { [weak self] lines in
            Task { @MainActor [weak self] in self?.read(lines) }
        }
        if await !camera.start() {
            cameraMessage = "No camera is available on this device."
        }
    }

    func stop() {
        camera.stop()
    }

    /// Clears the previous label so each scan starts from "Scanning...".
    func reset() {
        medicationName = nil
        frequency = nil
        cameraMessage = nil
        nameReading = StableReading()
        frequencyReading = StableReading()
    }

    /// Only shows a value after it has been read the same way several times in a row,
    /// so a single misread frame never reaches the screen.
    private func read(_ lines: [String]) {
        if let name = nameReading.confirm(PrescriptionParser.medicationName(in: lines)) {
            medicationName = name
        }
        if let frequency = frequencyReading.confirm(PrescriptionParser.frequency(in: lines)) {
            self.frequency = frequency
        }
    }

    private static func hasCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// Confirms a value once it has been seen `required` times in a row.
/// Frames where nothing was read are ignored rather than counted.
struct StableReading {
    var required = 3
    private var candidate: String?
    private var count = 0

    mutating func confirm(_ value: String?) -> String? {
        guard let value else { return nil }
        if value == candidate {
            count += 1
        } else {
            candidate = value
            count = 1
        }
        return count >= required ? value : nil
    }
}

/// Owns the capture session and runs Vision text recognition on video frames.
/// Lives off the main actor: all camera work happens on its own queues.
nonisolated final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Called on a background queue with the recognized lines, top to bottom.
    /// Set before calling `start()`.
    var onText: (@Sendable ([String]) -> Void)?

    private let sessionQueue = DispatchQueue(label: "MedLens.session")
    private let videoQueue = DispatchQueue(label: "MedLens.video")
    private var isConfigured = false
    private var lastScan = Date.distantPast

    /// Configures (once) and starts the camera. Returns false if no camera is available.
    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.isConfigured {
                    self.isConfigured = self.configure()
                }
                if self.isConfigured && !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume(returning: self.isConfigured)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        // Labels are read up close, so prefer near focus where supported.
        if device.isAutoFocusRangeRestrictionSupported, (try? device.lockForConfiguration()) != nil {
            device.autoFocusRangeRestriction = .near
            device.unlockForConfiguration()
        }
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // A few reads per second is plenty and saves battery.
        let now = Date()
        guard now.timeIntervalSince(lastScan) > 0.3 else { return }
        lastScan = now

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction could "fix" a drug name into a different word, so it is off.
        request.usesLanguageCorrection = false

        // Back camera frames arrive rotated; `.right` makes them upright for a portrait phone.
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right)
        try? handler.perform([request])

        let lines = (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }   // top of label first
            .compactMap { observation -> String? in
                // Drop text Vision is unsure about instead of guessing.
                guard let best = observation.topCandidates(1).first, best.confidence >= 0.5 else { return nil }
                return best.string
            }
        onText?(lines)
    }
}
