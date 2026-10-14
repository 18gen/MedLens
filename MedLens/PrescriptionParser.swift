//
//  PrescriptionParser.swift
//  MedLens
//

import Foundation

/// Pulls the medication and how often to take it out of recognized label text.
/// It only reports wording that is actually printed on the label and returns nil
/// rather than guessing when the text is unclear.
nonisolated enum PrescriptionParser {

    // MARK: Medication name

    /// A strength such as "10 mg", "0.5MG", "250 mcg", "5 mL", "1%".
    private static let strengthPattern = #"\b\d+(\.\d+)?\s?(mg|mcg|µg|g|ml|iu|units?)\b|\b\d+(\.\d+)?\s?%"#

    /// Lines with these words are directions or pharmacy details, not the drug line.
    private static let nonNameWords: Set<String> = [
        "take", "use", "apply", "inhale", "give", "insert", "instill", "dissolve", "chew",
        "swallow", "directions", "sig", "qty", "quantity", "refill", "refills", "exceed", "maximum",
    ]

    /// The first line that reads like "<name> <strength>", e.g. "ATORVASTATIN 20 MG TABLET"
    /// → "ATORVASTATIN 20 MG". Returned exactly as read, without the dosage form.
    static func medicationName(in lines: [String]) -> String? {
        lines.lazy.compactMap(nameCandidate).first
    }

    /// Index of the line `medicationName(in:)` uses, for highlighting it on screen.
    static func medicationLineIndex(in lines: [String]) -> Int? {
        lines.firstIndex { nameCandidate(from: $0) != nil }
    }

    private static func nameCandidate(from line: String) -> String? {
        let text = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard words.isDisjoint(with: nonNameWords),
              let strength = text.range(of: strengthPattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }

        // Require a real word before the strength, not just a stray letter or two.
        guard text[..<strength.lowerBound].filter(\.isLetter).count >= 3 else { return nil }
        return String(text[..<strength.upperBound])
    }

    // MARK: Frequency

    private static let perDay = #"\s+(daily|a day|per day|each day|every day)\b"#

    /// Checked in order; the first match wins.
    private static let frequencyRules: [(pattern: String, label: String?)] = [
        (#"\b(four times|4 times|4x)"# + perDay + #"|\bqid\b"#, "Four times daily"),
        (#"\b(three times|3 times|3x)"# + perDay + #"|\btid\b"#, "Three times daily"),
        (#"\b(twice|two times|2 times|2x)"# + perDay + #"|\bbid\b"#, "Twice daily"),
        (#"\b(once|one time|1 time|1x)"# + perDay + #"|\bqd\b"#, "Once daily"),
        (#"\bevery\s+(\d+|one|two|three|four|six|eight|twelve)\s+hours?\b"#, nil),  // shown as printed
        (#"\b(once a week|once per week|once weekly|every week)\b"#, "Once weekly"),
        (#"\b(every|each) morning\b"#, nil),
        (#"\b(at bedtime|every night|each night|nightly)\b"#, nil),
        (#"\b(every day|each day)\b"#, "Daily"),
    ]

    private static let asNeededPattern = #"\b(as needed|when needed|if needed|prn)\b"#

    /// e.g. "Once daily", "Twice daily", "Every 8 hours", "As needed".
    static func frequency(in lines: [String]) -> String? {
        // Directions often wrap across lines, so search the whole label as one string.
        let text = lines.joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        var found: String?
        for rule in frequencyRules {
            if let range = text.range(of: rule.pattern, options: .regularExpression) {
                found = rule.label ?? capitalizedFirst(String(text[range]))
                break
            }
        }

        // A bare "daily" counts only when the label has no "do not exceed … daily" style limits.
        if found == nil,
           text.range(of: #"\bdaily\b"#, options: .regularExpression) != nil,
           text.range(of: #"\b(exceed|max|maximum|up to|more than)\b"#, options: .regularExpression) == nil {
            found = "Daily"
        }

        let asNeeded = text.range(of: asNeededPattern, options: .regularExpression) != nil
        switch (found, asNeeded) {
        case let (frequency?, true): return "\(frequency), as needed"
        case let (frequency?, false): return frequency
        case (nil, true): return "As needed"
        case (nil, false): return nil
        }
    }

    /// Indices of the lines that hold the frequency wording, for highlighting on screen.
    /// Directions often wrap, so if no single line has it, adjacent pairs are checked.
    static func frequencyLineIndices(in lines: [String]) -> [Int] {
        guard frequency(in: lines) != nil else { return [] }
        let single = lines.indices.filter { frequency(in: [lines[$0]]) != nil }
        if !single.isEmpty { return single }
        for index in lines.indices.dropLast() where frequency(in: [lines[index], lines[index + 1]]) != nil {
            return [index, index + 1]
        }
        return []
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
