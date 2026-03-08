import SwiftUI

/// A minimal 40x20pt sparkline using catmull-rom interpolation.
/// Shows a 7-day trend line with no axes — just a smooth curve.
struct SparklineView: View {
    let dataPoints: [Double]
    var lineColor: Color = PerchTheme.accent.opacity(0.6)
    var lineWidth: CGFloat = 1.5

    var body: some View {
        if dataPoints.count >= 2 {
            GeometryReader { geometry in
                sparklinePath(in: geometry.size)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 40, height: 20)
        }
    }

    /// Builds a catmull-rom spline path through the normalized data points.
    private func sparklinePath(in size: CGSize) -> Path {
        guard let lo = dataPoints.min(), let hi = dataPoints.max() else {
            return Path()
        }

        let range = hi - lo
        let points: [CGPoint] = dataPoints.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(dataPoints.count - 1)
            let normalizedY: CGFloat = range > 0
                ? CGFloat((value - lo) / range)
                : 0.5
            let y = size.height * (1 - normalizedY) // flip Y axis
            return CGPoint(x: x, y: y)
        }

        return catmullRomPath(through: points)
    }

    /// Creates a smooth catmull-rom spline through the given points.
    /// Alpha = 0.5 (centripetal) for well-behaved curves without loops.
    private func catmullRomPath(through points: [CGPoint], alpha: CGFloat = 0.5) -> Path {
        guard points.count >= 2 else { return Path() }

        var path = Path()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[min(i + 1, points.count - 1)]
            let p3 = points[min(i + 2, points.count - 1)]

            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            let d3 = distance(p2, p3)

            let d1a = pow(d1, alpha)
            let d2a = pow(d2, alpha)
            let d3a = pow(d3, alpha)

            // Control point 1
            var cp1 = p1
            if d1a > 1e-6 && d2a > 1e-6 {
                let b1x = d2a * d2a * p0.x - d1a * d1a * p2.x + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.x
                let b1y = d2a * d2a * p0.y - d1a * d1a * p2.y + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.y
                let denom = 3 * d1a * (d1a + d2a)
                cp1 = CGPoint(x: b1x / denom, y: b1y / denom)
            }

            // Control point 2
            var cp2 = p2
            if d3a > 1e-6 && d2a > 1e-6 {
                let b2x = d2a * d2a * p3.x - d3a * d3a * p1.x + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.x
                let b2y = d2a * d2a * p3.y - d3a * d3a * p1.y + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.y
                let denom = 3 * d3a * (d3a + d2a)
                cp2 = CGPoint(x: b2x / denom, y: b2y / denom)
            }

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        return path
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        SparklineView(dataPoints: [72, 74, 71, 73, 75, 74, 76])
        SparklineView(dataPoints: [82.0, 81.5, 81.3, 81.0, 80.8, 80.5, 80.2], lineColor: PerchTheme.success.opacity(0.6))
        SparklineView(dataPoints: [1200, 1800, 1500, 2100, 1900, 2200, 1850], lineColor: PerchTheme.error.opacity(0.6))
    }
    .padding()
    .background(PerchTheme.cardBackground)
}
