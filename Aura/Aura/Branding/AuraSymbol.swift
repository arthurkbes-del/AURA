// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// Project-native vector interpretation of the Product Owner's icon concept.
/// No pixels from the reference artwork are copied into this path.
public enum AuraSymbol {
    public static func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
        }
        path.move(to: point(1, 50))
        path.addCurve(to: point(13, 41), control1: point(7, 51), control2: point(8, 41))
        path.addCurve(to: point(24, 65), control1: point(19, 40), control2: point(18, 65))
        path.addCurve(to: point(40, 10), control1: point(31, 66), control2: point(33, 10))
        path.addCurve(to: point(57, 90), control1: point(49, 10), control2: point(48, 90))
        path.addCurve(to: point(74, 32), control1: point(66, 90), control2: point(66, 32))
        path.addCurve(to: point(88, 54), control1: point(82, 31), control2: point(80, 57))
        path.addCurve(to: point(99, 50), control1: point(93, 51), control2: point(94, 50))
        return path
    }
}
