import SwiftUI

struct NotchShape: Shape {
    var topR: CGFloat
    var botR: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topR, botR) }
        set { topR = newValue.first; botR = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: topR, y: topR), control: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: topR, y: r.height - botR))
        p.addQuadCurve(to: CGPoint(x: topR + botR, y: r.height), control: CGPoint(x: topR, y: r.height))
        p.addLine(to: CGPoint(x: r.width - topR - botR, y: r.height))
        p.addQuadCurve(to: CGPoint(x: r.width - topR, y: r.height - botR), control: CGPoint(x: r.width - topR, y: r.height))
        p.addLine(to: CGPoint(x: r.width - topR, y: topR))
        p.addQuadCurve(to: CGPoint(x: r.width, y: 0), control: CGPoint(x: r.width - topR, y: 0))
        p.closeSubpath()
        return p
    }
}
