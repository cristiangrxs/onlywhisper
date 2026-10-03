import AppKit
import SwiftUI

enum BrandPalette {
    static let ink = Color(red: 18 / 255, green: 18 / 255, blue: 28 / 255)
    static let lavender = Color(red: 184 / 255, green: 171 / 255, blue: 1)
    static let mint = Color(red: 94 / 255, green: 242 / 255, blue: 200 / 255)
    static let gradient = LinearGradient(
        colors: [lavender, mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The OnlyWhisper mark: one soft wave that reads as a W.
struct BrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 44
        let scaleY = rect.height / 30
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 10) * scaleX, y: rect.minY + (y - 17.5) * scaleY)
        }

        var path = Path()
        path.move(to: point(14, 22))
        path.addCurve(to: point(22.5, 43), control1: point(16, 34), control2: point(19, 43))
        path.addCurve(to: point(32, 28), control1: point(27, 43), control2: point(29, 28))
        path.addCurve(to: point(41.5, 43), control1: point(35, 28), control2: point(37, 43))
        path.addCurve(to: point(50, 22), control1: point(45, 43), control2: point(48, 34))
        return path
    }
}

struct BrandIcon: View {
    var size: CGFloat = 28

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 14 / 64, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(BrandPalette.ink)
            BrandMark()
                .stroke(
                    BrandPalette.gradient,
                    style: StrokeStyle(lineWidth: size * 7 / 64, lineCap: .round, lineJoin: .round)
                )
                .padding(.horizontal, size * 10 / 64)
                .padding(.vertical, size * 14 / 64)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

enum BrandArtwork {
    /// Template image for the menu bar. macOS tints it for light and dark menu bars.
    static let menuBar: NSImage = {
        let size = NSSize(width: 20, height: 14)
        let image = NSImage(size: size, flipped: true) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1.2)
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: inset.minX + (x - 10) / 44 * inset.width,
                    y: inset.minY + (y - 17.5) / 30 * inset.height
                )
            }
            path.move(to: point(14, 22))
            path.curve(to: point(22.5, 43), controlPoint1: point(16, 34), controlPoint2: point(19, 43))
            path.curve(to: point(32, 28), controlPoint1: point(27, 43), controlPoint2: point(29, 28))
            path.curve(to: point(41.5, 43), controlPoint1: point(35, 28), controlPoint2: point(37, 43))
            path.curve(to: point(50, 22), controlPoint1: point(45, 43), controlPoint2: point(48, 34))
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
