//
//  MedicationStore.swift
//  MedLens
//

import Foundation
import Observation

/// The registered medications and which doses have been taken, saved on the device.
@Observable
final class MedicationStore {
    private(set) var medications: [Medication]

    /// When each dose was taken, keyed by "<day>|<Dose.id>", e.g. "2026-10-14|metformin-500@8:00".
    private var takenLog: [String: Date] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    private static let storageKey = "takenDoses"
    /// Older records are dropped on launch; only today's matter.
    private static let keepDays = 14

    init(medications: [Medication] = SampleMedications.all,
         defaults: UserDefaults = .standard,
         calendar: Calendar = .current) {
        self.medications = medications
        self.defaults = defaults
        self.calendar = calendar
        self.takenLog = Self.load(from: defaults, calendar: calendar)
    }

    // MARK: Reading

    func doses(on day: Date) -> [Dose] {
        DoseSchedule.doses(for: medications, on: day, calendar: calendar)
    }

    /// Today's doses in display order (pending first, earliest on top) with their states.
    func todayList(now: Date) -> [(dose: Dose, state: DoseState)] {
        let doses = doses(on: now)
        return DoseSchedule.ordered(doses, takenAt: takenTimes(on: now), now: now)
    }

    // MARK: Changing

    func markTaken(_ dose: Dose, at time: Date = Date()) {
        takenLog[key(for: dose)] = time
    }

    func markNotTaken(_ dose: Dose) {
        takenLog[key(for: dose)] = nil
    }

    /// Handles a medication name confirmed by the scanner: finds the medication, decides
    /// which dose (if any) it counts for, and marks that dose taken.
    func recordScan(scannedName: String, now: Date = Date()) -> ScanOutcome {
        let medication: Medication
        switch MedicationMatcher.match(scannedName: scannedName, in: medications) {
        case .match(let found): medication = found
        case .none: return .notOnList(scannedName: scannedName)
        case .ambiguous: return .unsure(scannedName: scannedName)
        }

        let outcome = DoseSchedule.scanOutcome(
            for: medication,
            dayDoses: doses(on: now),
            takenAt: takenTimes(on: now),
            now: now
        )
        if case .checked(let dose) = outcome {
            markTaken(dose, at: now)
        }
        return outcome
    }

    // MARK: Storage

    /// The given day's taken times keyed by `Dose.id`.
    private func takenTimes(on day: Date) -> [String: Date] {
        let prefix = Self.dayKey(day, calendar: calendar) + "|"
        var result: [String: Date] = [:]
        for (key, time) in takenLog where key.hasPrefix(prefix) {
            result[String(key.dropFirst(prefix.count))] = time
        }
        return result
    }

    private func key(for dose: Dose) -> String {
        Self.dayKey(dose.scheduled, calendar: calendar) + "|" + dose.id
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        defaults.set(takenLog.mapValues(\.timeIntervalSince1970), forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults, calendar: Calendar) -> [String: Date] {
        let stored = defaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: Date()) ?? .distantPast
        return stored
            .mapValues { Date(timeIntervalSince1970: $0) }
            .filter { $0.value >= cutoff }
    }
}
