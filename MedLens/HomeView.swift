//
//  HomeView.swift
//  MedLens
//

import SwiftUI

/// Home screen content above the scan button: date and time, the "My Medications"
/// button, and today's doses.
struct HomeView: View {
    let store: MedicationStore

    var body: some View {
        // Redraw every minute so the clock and "in 2 hr" labels stay current.
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 20) {
                HomeHeader(now: context.date, medications: store.medications)
                TodayCard(store: store, now: context.date)
            }
        }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    let now: Date
    let medications: [Medication]
    @State private var showingMedications = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Side by side when there is room, stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) { dateText; timeText }
                VStack(alignment: .leading, spacing: 2) { dateText; timeText }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                showingMedications.toggle()
            } label: {
                Image(systemName: "cross.vial.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(showingMedications ? .white : .black)
                    .frame(width: 52, height: 52)
                    .background {
                        Circle().fill(showingMedications ? Color.black : Color(white: 0.94))
                    }
            }
            .accessibilityLabel("My medications")
            .popover(isPresented: $showingMedications, arrowEdge: .top) {
                MedicationListPopover(medications: medications)
                    // Show as a dropdown popover on iPhone too, not a full sheet.
                    .presentationCompactAdaptation(.popover)
                    // Solid, so the list behind doesn't show through and hurt readability.
                    .presentationBackground(.white)
            }
        }
    }

    private var dateText: some View {
        Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color(white: 0.25))
    }

    private var timeText: some View {
        Text(now.formatted(date: .omitted, time: .shortened))
            .font(.largeTitle.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.black)
    }
}

// MARK: - Today card

private struct TodayCard: View {
    let store: MedicationStore
    let now: Date
    @State private var doseToUncheck: Dose?

    var body: some View {
        let items = store.todayList(now: now)
        let takenCount = items.filter { $0.state.isTaken }.count
        let allDone = !items.isEmpty && !items.contains { $0.state.isPending }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
                Spacer()
                if allDone {
                    Label("All done", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Palette.taken)
                } else if !items.isEmpty {
                    Text("\(takenCount) of \(items.count) taken")
                        .font(.headline)
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            .accessibilityElement(children: .combine)

            if items.isEmpty {
                Text("No medications scheduled today.")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.4))
            } else {
                // Plain list when it fits; scrolls when it doesn't.
                ViewThatFits(in: .vertical) {
                    rows(items)
                    ScrollView { rows(items) }
                        .scrollIndicators(.visible)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.96)))
        .animation(.spring(duration: 0.45), value: items.map { "\($0.dose.id)|\($0.state)" })
        .sensoryFeedback(.impact(weight: .light), trigger: takenCount)
        .confirmationDialog(
            uncheckTitle,
            isPresented: Binding(get: { doseToUncheck != nil }, set: { if !$0 { doseToUncheck = nil } }),
            titleVisibility: .visible
        ) {
            Button("Mark as Not Taken", role: .destructive) {
                if let dose = doseToUncheck { store.markNotTaken(dose) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var uncheckTitle: String {
        guard let dose = doseToUncheck else { return "" }
        return "Mark \(dose.medication.displayName) (\(dose.scheduled.formatted(date: .omitted, time: .shortened))) as not taken?"
    }

    @ViewBuilder
    private func rows(_ items: [(dose: Dose, state: DoseState)]) -> some View {
        let firstDoneIndex = items.firstIndex { !$0.state.isPending }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.dose.id) { index, item in
                if index == firstDoneIndex {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.45))
                        .padding(.top, index == 0 ? 0 : 14)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                } else if index > 0 {
                    Divider()
                }

                DoseRow(dose: item.dose, state: item.state, now: now) {
                    if item.state.isTaken {
                        // Unchecking could lead to a second dose, so ask first.
                        doseToUncheck = item.dose
                    } else {
                        store.markTaken(item.dose)
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct DoseRow: View {
    let dose: Dose
    let state: DoseState
    let now: Date
    let onToggle: () -> Void

    private var timeText: String {
        dose.scheduled.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: state.isTaken ? "checkmark.square.fill" : "square")
                    .font(.system(size: 30))
                    .foregroundStyle(state.isTaken ? Palette.taken : Color(white: 0.3))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            PillImage(medication: dose.medication, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.medication.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(dose.medication.strength) · \(timeText)")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.35))
            }

            Spacer(minLength: 4)

            DoseStatusText(state: state, scheduled: dose.scheduled, now: now)
        }
        .padding(.vertical, 8)
        .opacity(state.isPending ? 1 : 0.75)
        // VoiceOver: one element per dose, double-tap toggles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dose.medication.displayName), \(timeText)")
        .accessibilityValue(DoseStatusText.spokenStatus(state: state, scheduled: dose.scheduled, now: now))
        .accessibilityHint(state.isTaken ? "Double tap to mark as not taken" : "Double tap to mark as taken")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
    }
}

/// "in 2 hr", "Now", "1 hr late", "Missed", or "Taken 8:02 AM".
private struct DoseStatusText: View {
    let state: DoseState
    let scheduled: Date
    let now: Date

    var body: some View {
        switch state {
        case .upcoming:
            label("in \(Self.duration(scheduled.timeIntervalSince(now)))", color: Color(white: 0.4))
        case .due:
            label("Now", color: Palette.due, weight: .bold)
        case .late:
            label("\(Self.duration(now.timeIntervalSince(scheduled))) late", color: Palette.late, weight: .bold)
        case .missed:
            label("Missed", color: Color(white: 0.45))
        case .taken(let time):
            VStack(alignment: .trailing, spacing: 0) {
                label("Taken", color: Palette.taken, weight: .bold)
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Palette.taken)
            }
        }
    }

    private func label(_ text: String, color: Color, weight: Font.Weight = .semibold) -> some View {
        Text(text)
            .font(.headline.weight(weight))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .fixedSize()
    }

    /// Rounded to whole minutes under an hour, otherwise whole hours.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        return "\(Int((Double(minutes) / 60).rounded())) hr"
    }

    static func spokenStatus(state: DoseState, scheduled: Date, now: Date) -> String {
        func spoken(_ seconds: TimeInterval) -> String {
            duration(seconds).replacingOccurrences(of: "hr", with: "hours").replacingOccurrences(of: "min", with: "minutes")
        }
        switch state {
        case .upcoming: return "Not taken. Due in \(spoken(scheduled.timeIntervalSince(now)))"
        case .due: return "Not taken. Due now"
        case .late: return "Not taken. \(spoken(now.timeIntervalSince(scheduled))) late"
        case .missed: return "Missed"
        case .taken(let time): return "Taken at \(time.formatted(date: .omitted, time: .shortened))"
        }
    }
}

// MARK: - Registered medications dropdown

private struct MedicationListPopover: View {
    let medications: [Medication]

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(width: 330)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("My Medications")
                .font(.title3.weight(.bold))
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(medications.enumerated()), id: \.element.id) { index, medication in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    PillImage(medication: medication, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.displayName)
                            .font(.title3.weight(.semibold))
                        Text(medication.doseTimes.sorted().map { timeText($0) }.joined(separator: " · "))
                            .font(.body)
                            .foregroundStyle(Color(white: 0.35))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
    }

    private func timeText(_ time: DoseTime) -> String {
        time.date(on: Date()).formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Shared pieces

/// Placeholder medication picture: a coloured pill symbol on a soft tile.
struct PillImage: View {
    let medication: Medication
    var size: CGFloat = 48

    var body: some View {
        let color = Palette.tint(medication.tint)
        Image(systemName: medication.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(color.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

/// Colours chosen to stay readable on the light grey card.
enum Palette {
    static let taken = Color(red: 0.10, green: 0.50, blue: 0.22)
    static let due = Color(red: 0.0, green: 0.40, blue: 0.85)
    static let late = Color(red: 0.78, green: 0.32, blue: 0.0)

    static func tint(_ tint: PillTint) -> Color {
        switch tint {
        case .blue: return Color(red: 0.15, green: 0.45, blue: 0.90)
        case .orange: return Color(red: 0.90, green: 0.45, blue: 0.10)
        case .pink: return Color(red: 0.85, green: 0.25, blue: 0.50)
        case .green: return Color(red: 0.15, green: 0.60, blue: 0.35)
        case .purple: return Color(red: 0.50, green: 0.30, blue: 0.80)
        }
    }
}
