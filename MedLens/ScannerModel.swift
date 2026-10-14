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
    /// Text read in the latest camera frame, with positions, for the on-screen boxes.
    private(set) var lines: [RecognizedLine] = []
    /// Upright size of the camera frames the boxes are measured against.
    private(set) var frameSize: CGSize = .zero

    @ObservationIgnored private let camera = CameraSession()
    @ObservationIgnored private var nameReading = StableReading()
    @ObservationIgnored private var frequencyReading = StableReading()

    var session: AVCaptureSession { camera.session }

    func start() async {
        guard await Self.hasCameraPermission() else {
            cameraMessage = "Camera access is off.\nTurn it on in Settings › MedLens."
            return
        }
        camera.onText = { [weak self] lines, frameSize in
            Task { @MainActor [weak self] in self?.read(lines, frameSize: frameSize) }
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
        lines = []
        nameReading = StableReading()
        frequencyReading = StableReading()
    }

    /// Only shows a value after it has been read the same way several times in a row,
    /// so a single misread frame never reaches the screen.
    private func read(_ lines: [RecognizedLine], frameSize: CGSize) {
        let texts = lines.map(\.text)

        // Mark which lines the name and frequency come from in this frame.
        var lines = lines
        if let index = PrescriptionParser.medicationLineIndex(in: texts) {
            lines[index].role = .name
        }
        for index in PrescriptionParser.frequencyLineIndices(in: texts) where lines[index].role == .other {
            lines[index].role = .frequency
        }
        self.lines = lines
        self.frameSize = frameSize

        if let name = nameReading.confirm(PrescriptionParser.medicationName(in: texts)) {
            medicationName = name
        }
        if let frequency = frequencyReading.confirm(PrescriptionParser.frequency(in: texts)) {
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

/// One line of text Vision read, and where it is in the frame.
nonisolated struct RecognizedLine: Sendable, Equatable {
    enum Role: Sendable { case other, name, frequency }

    let text: String
    /// Vision's normalized box in the upright frame: 0–1, origin at the bottom-left.
    let box: CGRect
    var role: Role = .other
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

    /// Called on a background queue with the recognized lines (top to bottom) and the
    /// upright frame size. Set before calling `start()`.
    var onText: (@Sendable ([RecognizedLine], CGSize) -> Void)?

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
            .compactMap { observation -> RecognizedLine? in
                // Drop text Vision is unsure about instead of guessing; it is not boxed either.
                guard let best = observation.topCandidates(1).first, best.confidence >= 0.5 else { return nil }
                return RecognizedLine(text: best.string, box: observation.boundingBox)
            }

        // Frames arrive landscape; rotated upright (`.right`) width and height swap.
        var frameSize = CGSize.zero
        if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            frameSize = CGSize(width: CVPixelBufferGetHeight(buffer), height: CVPixelBufferGetWidth(buffer))
        }
        onText?(lines, frameSize)
    }
}
