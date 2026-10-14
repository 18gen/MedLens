//
//  Medication.swift
//  MedLens
//

import Foundation

/// A medication the person takes, with the times of day they take it.
nonisolated struct Medication: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let strength: String
    let doseTimes: [DoseTime]
    /// Placeholder picture until real photos exist: an SF Symbol and a colour.
    let symbol: String
    let tint: PillTint

    var displayName: String { "\(name) \(strength)" }
}

/// A time of day, independent of date.
nonisolated struct DoseTime: Hashable, Comparable, Sendable {
    let hour: Int
    let minute: Int

    init(_ hour: Int, _ minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    static func < (lhs: DoseTime, rhs: DoseTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    /// This time on the given day.
    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// Colours for the placeholder pill pictures.
nonisolated enum PillTint: String, Hashable, Sendable {
    case blue, orange, pink, green, purple
}

/// Temporary sample data until medications can be registered in the app.
/// These are common real medications so printed or real labels can be scanned,
/// but the schedules are examples only, not advice.
nonisolated enum SampleMedications {
    static let all: [Medication] = [
        Medication(
            id: "metformin-500",
            name: "Metformin",
            strength: "500 mg",
            doseTimes: [DoseTime(8), DoseTime(18)],
            symbol: "pill.fill",
            tint: .blue
        ),
        Medication(
            id: "lisinopril-10",
            name: "Lisinopril",
            strength: "10 mg",
            doseTimes: [DoseTime(8)],
            symbol: "pill.fill",
            tint: .orange
        ),
        Medication(
            id: "atorvastatin-20",
            name: "Atorvastatin",
            strength: "20 mg",
            doseTimes: [DoseTime(21)],
            symbol: "capsule.fill",
            tint: .pink
        ),
    ]
}
