import SwiftUI

/// The Just Chat logo rendered as a SwiftUI `Canvas` drawing, traced from
/// `Resources/JustChatLogo.svg`. Drawn in the SVG's 1024×1024 coordinate space
/// and scaled to the view size, so it renders crisply at menu-bar sizes with no
/// bundled image asset (works in both `swift run` and the `.app` bundle).
struct LogoMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 1024
            var ctx = context
            ctx.scaleBy(x: scale, y: scale)

            // Background rounded plate (gives contrast on both light & dark menu bars).
            let bgRect = CGRect(x: 56, y: 56, width: 912, height: 912)
            let bgPath = RoundedRectangle(cornerRadius: 214, style: .continuous).path(in: bgRect)
            ctx.fill(bgPath, with: .linearGradient(
                Gradient(colors: [
                    Color.justWindowBackground,
                    Color.justChromeBackground
                ]),
                startPoint: CGPoint(x: 160, y: 112),
                endPoint: CGPoint(x: 864, y: 912)
            ))
            ctx.stroke(bgPath, with: .color(Color.justBorderSoft), lineWidth: 3)

            // Chat bubble.
            ctx.fill(Self.bubblePath, with: .color(Color.justForeground))

            // Three dots.
            for center in [CGPoint(x: 402, y: 490), CGPoint(x: 512, y: 490), CGPoint(x: 622, y: 490)] {
                let dotRect = CGRect(x: center.x - 34, y: center.y - 34, width: 68, height: 68)
                ctx.fill(Circle().path(in: dotRect), with: .color(.white))
            }

            // Green sparkles.
            ctx.fill(Self.sparklePath1, with: .color(Color.justSuccess))
            ctx.fill(Self.sparklePath2, with: .color(Color.justSuccess.opacity(0.85)))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static var bubblePath: Path {
        Path { p in
            p.move(to: CGPoint(x: 336, y: 622))
            p.addCurve(to: CGPoint(x: 241, y: 760),
                       control1: CGPoint(x: 324, y: 688), control2: CGPoint(x: 282, y: 734))
            p.addCurve(to: CGPoint(x: 468, y: 660),
                       control1: CGPoint(x: 327, y: 766), control2: CGPoint(x: 411, y: 733))
            p.addLine(to: CGPoint(x: 710, y: 660))
            p.addCurve(to: CGPoint(x: 836, y: 534),
                       control1: CGPoint(x: 782, y: 660), control2: CGPoint(x: 836, y: 606))
            p.addLine(to: CGPoint(x: 836, y: 430))
            p.addCurve(to: CGPoint(x: 710, y: 304),
                       control1: CGPoint(x: 836, y: 358), control2: CGPoint(x: 782, y: 304))
            p.addLine(to: CGPoint(x: 314, y: 304))
            p.addCurve(to: CGPoint(x: 188, y: 430),
                       control1: CGPoint(x: 242, y: 304), control2: CGPoint(x: 188, y: 358))
            p.addLine(to: CGPoint(x: 188, y: 496))
            p.addCurve(to: CGPoint(x: 314, y: 622),
                       control1: CGPoint(x: 188, y: 568), control2: CGPoint(x: 242, y: 622))
            p.addLine(to: CGPoint(x: 336, y: 622))
            p.closeSubpath()
        }
    }

    private static var sparklePath1: Path {
        Path { p in
            p.move(to: CGPoint(x: 760, y: 188))
            p.addLine(to: CGPoint(x: 790, y: 258))
            p.addLine(to: CGPoint(x: 860, y: 288))
            p.addLine(to: CGPoint(x: 790, y: 318))
            p.addLine(to: CGPoint(x: 760, y: 388))
            p.addLine(to: CGPoint(x: 730, y: 318))
            p.addLine(to: CGPoint(x: 660, y: 288))
            p.addLine(to: CGPoint(x: 730, y: 258))
            p.closeSubpath()
        }
    }

    private static var sparklePath2: Path {
        Path { p in
            p.move(to: CGPoint(x: 292, y: 214))
            p.addLine(to: CGPoint(x: 308, y: 252))
            p.addLine(to: CGPoint(x: 346, y: 268))
            p.addLine(to: CGPoint(x: 308, y: 284))
            p.addLine(to: CGPoint(x: 292, y: 322))
            p.addLine(to: CGPoint(x: 276, y: 284))
            p.addLine(to: CGPoint(x: 238, y: 268))
            p.addLine(to: CGPoint(x: 276, y: 252))
            p.closeSubpath()
        }
    }
}
