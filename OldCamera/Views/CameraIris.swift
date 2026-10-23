import SwiftUI

/// The iOS 6 camera iris: six dark metal blades that close over the
/// viewfinder when a photo is taken and open again (and open when the camera
/// starts). `aperture` goes from 0 (closed) to 1 (fully open, off screen).
struct CameraIris: View {
    var aperture: CGFloat
    var center: CGPoint

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<CameraIrisBlade.count, id: \.self) { index in
                    CameraIrisBladeView(index: index, aperture: aperture, center: center, size: geometry.size)
                }
                // The blade edges spiral out from the aperture over all blades.
                ForEach(0..<CameraIrisBlade.count, id: \.self) { index in
                    CameraIrisEdge(index: index, aperture: aperture, center: center)
                        .stroke(Color.black.opacity(0.75), lineWidth: 1.2)
                    CameraIrisEdge(index: index, aperture: aperture, center: center)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
                        .offset(x: 0.6, y: 0.6)
                }
            }
        }
        .allowsHitTesting(aperture < 0.98)
        .opacity(aperture >= 0.999 ? 0 : 1)
    }
}

private struct CameraIrisBladeView: View {
    let index: Int
    let aperture: CGFloat
    let center: CGPoint
    let size: CGSize

    var body: some View {
        let blade = CameraIrisBlade(index: index, aperture: aperture, center: center)
        // Blades alternate slightly in tone, like the brushed iOS 6 iris.
        let tone: Double = index.isMultiple(of: 2) ? 0 : 6
        blade
            .fill(
                LinearGradient(
                    oldOS: [
                        OldOSStop(.oldOS(78 + tone, 78 + tone, 82 + tone), 0),
                        OldOSStop(.oldOS(46 + tone, 46 + tone, 50 + tone), 0.55),
                        OldOSStop(.oldOS(28 + tone, 28 + tone, 31 + tone), 1)
                    ],
                    from: blade.gradientStart(in: size),
                    to: blade.gradientEnd(in: size)
                )
            )
    }
}

/// One blade: the half-plane beyond a line tangent to the (hexagonal)
/// aperture, twisted as the iris closes so the blades spiral like a lens.
struct CameraIrisBlade: Shape {
    static let count = 6

    let index: Int
    var aperture: CGFloat
    let center: CGPoint

    var animatableData: CGFloat {
        get { aperture }
        set { aperture = newValue }
    }

    /// Normal direction of the blade's inner edge.
    static func normal(index: Int, aperture: CGFloat) -> CGFloat {
        let base = CGFloat(index) * (2 * .pi / CGFloat(count))
        let twist = (1 - aperture) * (.pi / 5)
        return base + twist
    }

    /// Distance of the inner edge from the centre (0 = closed).
    static func distance(aperture: CGFloat, in rect: CGRect, center: CGPoint) -> CGFloat {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        let farthest = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1000
        return max(aperture, 0) * (farthest + 4)
    }

    func path(in rect: CGRect) -> Path {
        let angle = Self.normal(index: index, aperture: aperture)
        let d = Self.distance(aperture: aperture, in: rect, center: center)
        let n = CGPoint(x: cos(angle), y: sin(angle))
        let t = CGPoint(x: -n.y, y: n.x)
        let far = max(rect.width, rect.height) * 3
        let base = CGPoint(x: center.x + n.x * d, y: center.y + n.y * d)
        var path = Path()
        path.move(to: CGPoint(x: base.x - t.x * far, y: base.y - t.y * far))
        path.addLine(to: CGPoint(x: base.x + t.x * far, y: base.y + t.y * far))
        path.addLine(to: CGPoint(x: base.x + t.x * far + n.x * far, y: base.y + t.y * far + n.y * far))
        path.addLine(to: CGPoint(x: base.x - t.x * far + n.x * far, y: base.y - t.y * far + n.y * far))
        path.closeSubpath()
        return path
    }

    func gradientStart(in size: CGSize) -> UnitPoint {
        let angle = Self.normal(index: index, aperture: aperture)
        return UnitPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)
    }

    func gradientEnd(in size: CGSize) -> UnitPoint {
        let angle = Self.normal(index: index, aperture: aperture)
        return UnitPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)
    }
}

/// The visible inner edge of a blade (from the aperture outwards on one side,
/// where the next blade does not cover it), drawn as a dark line with a fine
/// highlight.
struct CameraIrisEdge: Shape {
    let index: Int
    var aperture: CGFloat
    let center: CGPoint

    var animatableData: CGFloat {
        get { aperture }
        set { aperture = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let angle = CameraIrisBlade.normal(index: index, aperture: aperture)
        let d = CameraIrisBlade.distance(aperture: aperture, in: rect, center: center)
        let n = CGPoint(x: cos(angle), y: sin(angle))
        let t = CGPoint(x: -n.y, y: n.x)
        let far = max(rect.width, rect.height) * 3
        let base = CGPoint(x: center.x + n.x * d, y: center.y + n.y * d)
        // From the hexagon corner shared with the previous blade outwards.
        let half = d * tan(.pi / CGFloat(CameraIrisBlade.count))
        var path = Path()
        path.move(to: CGPoint(x: base.x - t.x * half, y: base.y - t.y * half))
        path.addLine(to: CGPoint(x: base.x + t.x * far, y: base.y + t.y * far))
        return path
    }
}
