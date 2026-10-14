//
//  ScanArrow.swift
//  MedLens
//

import SwiftUI

/// Hand-drawn style arrow that curls down from under "Scan Label", makes a small loop,
/// and sweeps right toward the camera button. It draws itself in when it appears, then
/// nudges toward the button every few seconds. With Reduce Motion it is simply shown.
struct ScanArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var isNudged = false

    var body: some View {
        ScanArrowShape()
            .trim(from: 0, to: reduceMotion ? 1 : progress)
            .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .offset(x: isNudged ? 4 : 0, y: isNudged ? 1 : 0)
            .task {
                guard !reduceMotion else { return }
                // Start once the hint has faded in.
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(.easeInOut(duration: 0.9)) { progress = 1 }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.25)) { isNudged = true }
                    try? await Task.sleep(for: .seconds(0.25))
                    withAnimation(.easeInOut(duration: 0.35)) { isNudged = false }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The arrow's path, drawn in one continuous stroke (line, loop, sweep, then the head)
/// so trimming it looks like a pen drawing it.
struct ScanArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        // Down the left side from under the text.
        path.move(to: point(0.55, 0.02))
        path.addCurve(to: point(0.12, 0.50), control1: point(0.25, 0.04), control2: point(0.02, 0.36))
        // Small loop.
        path.addCurve(to: point(0.52, 0.42), control1: point(0.20, 0.64), control2: point(0.62, 0.56))
        path.addCurve(to: point(0.30, 0.52), control1: point(0.44, 0.30), control2: point(0.26, 0.38))
        // Sweep down and right to the tip.
        let tip = point(0.96, 0.84)
        let lastControl = point(0.66, 0.86)
        path.addCurve(to: tip, control1: point(0.34, 0.74), control2: lastControl)

        // Arrowhead: two short strokes angled back from the tip.
        let angle = atan2(tip.y - lastControl.y, tip.x - lastControl.x)
        let headLength: CGFloat = 11
        for side in [-1.0, 1.0] {
            let wing = angle + .pi + side * 0.6
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x + cos(wing) * headLength, y: tip.y + sin(wing) * headLength))
        }
        return path
    }
}
