//
//  MedicationsPage.swift
//  MedLens
//

import SwiftUI

/// "My Medications": every registered medication with its strength and daily times.
/// Opened from the bottle button; slides in from the right. A large round "‹" button
/// (or a swipe from the left edge) goes back.
struct MedicationsPage: View {
    let medications: [Medication]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                backButton

                Text("My Medications")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(medications.enumerated()), id: \.element.id) { index, medication in
                        if index > 0 { Divider() }
                        row(medication)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.96)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color.white)
        // The system back button can't be enlarged, so this page draws its own header.
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .leading) { edgeSwipeToGoBack }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            // Same size and style as the medications button on the home screen.
            Image(systemName: "chevron.left")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: GlassButton.size, height: GlassButton.size)
                .modifier(GlassButtonBackground(shape: Circle()))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    /// Hiding the system bar also turns off its swipe-back, so a swipe right from the
    /// left edge goes back here instead.
    private var edgeSwipeToGoBack: some View {
        Color.clear
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width > 80 { dismiss() }
                    }
            )
            .accessibilityHidden(true)
    }

    private func row(_ medication: Medication) -> some View {
        HStack(spacing: 14) {
            // At accessibility text sizes the picture gives its room to the name.
            if !typeSize.isAccessibilitySize {
                PillImage(medication: medication, size: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                Text(medication.strength)
                    .font(.body)
                    .foregroundStyle(Color(white: 0.35))
                Label(timesText(medication), systemImage: "clock")
                    .font(.body)
                    .foregroundStyle(Color(white: 0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func timesText(_ medication: Medication) -> String {
        medication.doseTimes.sorted()
            .map { $0.date(on: Date()).formatted(date: .omitted, time: .shortened) }
            .joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        MedicationsPage(medications: SampleMedications.all)
    }
}
