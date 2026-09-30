import SwiftUI

/// Outgoing bubble. The rect includes `Metrics.tailWidth` on the trailing side, whether or not the tail is drawn,
/// so grouped bubbles keep their right edges aligned.
struct BubbleShape: Shape {
    var topTrailingRadius = Metrics.bubbleRadius
    var bottomTrailingRadius = Metrics.bubbleRadius
    var hasTail = true

    /// A bubble's shape for where it sits in its group: only the last gets a tail, and bubbles in a run share
    /// smaller corners on their trailing side.
    init(position: BubblePosition) {
        topTrailingRadius = position.isFirstInGroup ? Metrics.bubbleRadius : Metrics.groupedRadius
        bottomTrailingRadius = Metrics.groupedRadius
        hasTail = position.isLastInGroup
    }

    func path(in rect: CGRect) -> Path {
        let r = Metrics.bubbleRadius
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width - Metrics.tailWidth, height: rect.height)
        var path = Path()
        guard hasTail else {
            path.addRoundedRect(in: body, cornerRadii: RectangleCornerRadii(
                topLeading: r, bottomLeading: r, bottomTrailing: bottomTrailingRadius, topTrailing: topTrailingRadius
            ))
            return path
        }

        let (left, top, right, bottom) = (body.minX, body.minY, body.maxX, body.maxY)
        let tr = topTrailingRadius
        // The tail's lower edge curls back up and meets the bottom-trailing corner arc 6pt in from the edge.
        let notchAngle = Angle(radians: acos(10 / r))
        path.move(to: CGPoint(x: left + r, y: top))
        path.addLine(to: CGPoint(x: right - tr, y: top))
        path.addArc(center: CGPoint(x: right - tr, y: top + tr), radius: tr,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: right, y: bottom - 6.5))
        path.addQuadCurve(to: CGPoint(x: right + 5.5, y: bottom), control: CGPoint(x: right + 1.5, y: bottom - 2.5))
        path.addQuadCurve(to: CGPoint(x: right - r + r * cos(notchAngle.radians), y: bottom - r + r * sin(notchAngle.radians)),
                          control: CGPoint(x: right + 0.25, y: bottom - 0.25))
        path.addArc(center: CGPoint(x: right - r, y: bottom - r), radius: r,
                    startAngle: notchAngle, endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addArc(center: CGPoint(x: left + r, y: bottom - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: left, y: top + r))
        path.addArc(center: CGPoint(x: left + r, y: top + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Telegram's double tick, drawn in a 12.5 × 7.5 box. Stroke it at 1.25pt.
struct ReadChecks: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 12.5, sy = rect.height / 7.5
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(0.6, 4.3))
        path.addLine(to: p(3.1, 6.9))
        path.addLine(to: p(8.6, 0.6))
        path.move(to: p(5.7, 6.2))
        path.addLine(to: p(6.4, 6.9))
        path.addLine(to: p(11.9, 0.6))
        return path
    }
}
