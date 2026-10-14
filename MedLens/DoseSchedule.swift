//
//  DoseSchedule.swift
//  MedLens
//

import Foundation

/// One scheduled dose of a medication on a specific day.
nonisolated struct Dose: Identifiable, Hashable, Sendable {
    let medication: Medication
    let time: DoseTime
    let scheduled: Date
    /// Stable within a day, e.g. "metformin-500@8:00"; combined with the day for storage.
    let id: String

    init(medication: Medication, time: DoseTime, day: Date, calendar: Calendar = .current) {
        self.medication = medication
        self.time = time
        self.scheduled = time.date(on: day, calendar: calendar)
        self.id = "\(medication.id)@\(time.hour):\(String(format: "%02d", time.minute))"
    }
}

/// Where a dose stands right now.
nonisolated enum DoseState: Hashable, Sendable {
    /// More than `dueWindow` before its time.
    case upcoming
    /// Within `dueWindow` of its time.
    case due
    /// More than `dueWindow` past its time, not taken, and not yet replaced by the next dose.
    case late
    /// Not taken, and a later dose of the same medication is taken or already due.
    /// Shown as missed (not late) so nobody is nudged into a double dose.
    case missed
    case taken(at: Date)

    var isTaken: Bool {
        if case .taken = self { return true }
        return false
    }

    /// Doses still to take: upcoming, due, or late.
    var isPending: Bool {
        switch self {
        case .upcoming, .due, .late: return true
        case .missed, .taken: return false
        }
    }
}

/// What happened when a label was scanned.
nonisolated enum ScanOutcome: Hashable, Sendable {
    /// The dose was marked taken just now.
    case checked(Dose)
    /// Every dose due so far was already taken; `next` is the next one today, if any.
    case alreadyTaken(Dose, at: Date, next: Dose?)
    /// Nothing taken yet and the first dose is more than `earlyWindow` away.
    case tooEarly(next: Dose)
    /// The medication has no doses scheduled today.
    case notScheduledToday(Medication)
    /// The scanned medication is not one of the registered ones.
    case notOnList(scannedName: String)
    /// More than one registered medication fits the scanned text.
    case unsure(scannedName: String)
}

/// Pure scheduling rules, independent of storage and UI so they can be checked in isolation.
nonisolated enum DoseSchedule {
    /// "Now" means within 15 minutes either side of the dose time.
    static let dueWindow: TimeInterval = 15 * 60
    /// A scan may check a dose up to 1 hour before its time.
    static let earlyWindow: TimeInterval = 60 * 60

    /// All of the given medications' doses on `day`, in time order.
    static func doses(for medications: [Medication], on day: Date, calendar: Calendar = .current) -> [Dose] {
        medications
            .flatMap { medication in
                medication.doseTimes.map { Dose(medication: medication, time: $0, day: day, calendar: calendar) }
            }
            .sorted { ($0.scheduled, $0.medication.name) < ($1.scheduled, $1.medication.name) }
    }

    /// The state of `dose`, given when each of the day's doses was taken (keyed by `Dose.id`).
    static func state(of dose: Dose, among dayDoses: [Dose], takenAt: [String: Date], now: Date) -> DoseState {
        if let time = takenAt[dose.id] {
            return .taken(at: time)
        }

        let laterSameMedication = dayDoses.filter {
            $0.medication.id == dose.medication.id && $0.scheduled > dose.scheduled
        }
        if laterSameMedication.contains(where: { takenAt[$0.id] != nil || $0.scheduled <= now }) {
            return .missed
        }

        let untilDose = dose.scheduled.timeIntervalSince(now)
        if untilDose > dueWindow { return .upcoming }
        if untilDose >= -dueWindow { return .due }
        return .late
    }

    /// Today's list: doses still to take first (earliest on top), then taken and missed ones.
    static func ordered(_ dayDoses: [Dose], takenAt: [String: Date], now: Date) -> [(dose: Dose, state: DoseState)] {
        let withStates = dayDoses.map { ($0, state(of: $0, among: dayDoses, takenAt: takenAt, now: now)) }
        let pending = withStates.filter { $0.1.isPending }
        let done = withStates.filter { !$0.1.isPending }
        return (pending + done).map { (dose: $0.0, state: $0.1) }
    }

    /// Decides what a scan of `medication` should do now. Never checks more than one dose,
    /// and when an earlier dose was skipped it checks the current one, not the skipped one,
    /// so the next scheduled dose is never left looking untaken.
    static func scanOutcome(for medication: Medication, dayDoses: [Dose], takenAt: [String: Date], now: Date) -> ScanOutcome {
        let doses = dayDoses.filter { $0.medication.id == medication.id }
        guard !doses.isEmpty else { return .notScheduledToday(medication) }

        let states = doses.map { (dose: $0, state: state(of: $0, among: dayDoses, takenAt: takenAt, now: now)) }

        // The latest pending dose that is due, late, or at most `earlyWindow` away.
        let checkable = states.filter {
            $0.state.isPending && $0.dose.scheduled <= now.addingTimeInterval(earlyWindow)
        }
        if let dose = checkable.last?.dose {
            return .checked(dose)
        }

        let next = states.first { $0.state.isPending }?.dose
        let lastTaken = states.last { $0.state.isTaken }
        if let lastTaken, case .taken(let time) = lastTaken.state {
            return .alreadyTaken(lastTaken.dose, at: time, next: next)
        }
        if let next {
            return .tooEarly(next: next)
        }
        // Only missed doses remain: treat like nothing more to take today.
        return .notScheduledToday(medication)
    }
}

/// Matches the name read from a label (e.g. "METFORMIN HCL 500MG") to a registered medication.
nonisolated enum MedicationMatcher {
    /// Release-type words that make a different product ("Metformin ER" is not "Metformin").
    private static let formulationWords: Set<String> = ["er", "xr", "sr", "xl", "cr", "dr", "la", "cd", "odt"]

    private static let unitAliases: [String: String] = [
        "mg": "mg", "mcg": "mcg", "µg": "mcg", "ug": "mcg", "g": "g", "ml": "ml",
        "iu": "iu", "unit": "unit", "units": "unit", "%": "%",
    ]

    enum Result: Equatable {
        case match(Medication)
        case none
        case ambiguous
    }

    /// Requires every word of the registered name, the exact same strength, and no extra
    /// release-type word on the label.
    static func match(scannedName: String, in medications: [Medication]) -> Result {
        let scanned = tokens(scannedName)
        let scannedWords = Set(scanned)
        let scannedStrengths = strengths(in: scanned)
        guard !scannedStrengths.isEmpty else { return .none }

        let matches = medications.filter { medication in
            let nameTokens = tokens(medication.name)
            guard !nameTokens.isEmpty, nameTokens.allSatisfy(scannedWords.contains) else { return false }
            guard strengths(in: tokens(medication.strength)) == scannedStrengths else { return false }
            let extraFormulation = scannedWords.intersection(formulationWords).subtracting(nameTokens)
            return extraFormulation.isEmpty
        }

        switch matches.count {
        case 0: return .none
        case 1: return .match(matches[0])
        default: return .ambiguous
        }
    }

    /// Lowercased words and numbers, with "500mg" split into "500" "mg".
    static func tokens(_ text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in text.lowercased() {
            if let previous, previous.isNumber != character.isNumber,
               previous.isLetter || previous.isNumber, character.isLetter || character.isNumber {
                spaced.append(" ")
            }
            spaced.append(character)
            previous = character
        }
        return spaced
            .split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "%") }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    /// Number + unit pairs, e.g. ["500 mg"], with numbers normalised ("500.0" → "500").
    static func strengths(in tokens: [String]) -> Set<String> {
        var result = Set<String>()
        for (index, token) in tokens.enumerated() where index + 1 < tokens.count {
            guard let value = Double(token), let unit = unitAliases[tokens[index + 1]] else { continue }
            let number = value.rounded() == value ? String(Int(value)) : String(value)
            result.insert("\(number) \(unit)")
        }
        return result
    }
}
