import AppKit
import SwiftUI

/// Design tokens for Just Chat.
///
/// Colors are dark-mode aware via `NSColor(name:dynamicProvider:)` so they adapt
/// to `@Environment(\.colorScheme)` automatically — no asset catalog required.
/// Light/dark values are lifted from the OpenDesign reference
/// (`design/opendesign/index.html` `:root` and dark variants).
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let pill: CGFloat = 980
}

private extension NSColor {
    /// Returns a dynamic color that resolves to `light` in light appearances and
    /// `dark` in dark appearances.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua
            ]) != nil
            return isDark ? dark : light
        }
    }

    convenience init(hex: String) {
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        self.init(
            srgbRed: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private func dynamicColor(light: String, dark: String) -> Color {
    Color(nsColor: NSColor.dynamic(light: NSColor(hex: light), dark: NSColor(hex: dark)))
}

extension Color {
    /// Brand accent. `#0071E3` light / `#0A84FF` dark.
    static let justAccent = dynamicColor(light: "0071E3", dark: "0A84FF")
    /// A slightly lighter accent for gradient ends and hovers.
    static let justAccentLight = dynamicColor(light: "3395F0", dark: "409CFF")
    /// Foreground for content placed on top of the accent.
    static let justAccentOn = Color.white

    static let justWindowBackground = dynamicColor(light: "FFFFFF", dark: "1C1C1E")
    static let justChromeBackground = dynamicColor(light: "F5F5F7", dark: "2C2C2E")
    static let justSidebarBackground = dynamicColor(light: "F5F5F7", dark: "242426")
    static let justControlBackground = dynamicColor(light: "FFFFFF", dark: "2C2C2E")
    static let justInputBackground = dynamicColor(light: "F5F5F7", dark: "1C1C1E")

    static let justBorder = dynamicColor(light: "D2D2D7", dark: "48484A")
    static let justBorderSoft = dynamicColor(light: "E8E8ED", dark: "3A3A3C")

    static let justForeground = dynamicColor(light: "1D1D1F", dark: "F5F5F7")
    static let justMuted = dynamicColor(light: "6E6E73", dark: "8E8E93")
    static let justMeta = dynamicColor(light: "86868B", dark: "636366")

    /// Tinted surface for user-side message bubbles.
    static let justUserBubble = dynamicColor(light: "EAF3FE", dark: "1E3A5F")

    /// Semantic helpers kept for clarity at call sites.
    static let justSuccess = dynamicColor(light: "16A34A", dark: "30D158")
    static let justDanger = dynamicColor(light: "DC2626", dark: "FF453A")

    // MARK: Code surfaces & syntax-highlight tokens
    /// Background of fenced code blocks.
    static let justCodeBackground = dynamicColor(light: "F6F6F8", dark: "161617")
    /// Default text color inside code blocks.
    static let justCodeForeground = dynamicColor(light: "1D1D1F", dark: "E6E6E6")
    /// Comments — muted.
    static let justCodeComment = dynamicColor(light: "6E6E73", dark: "8E8E93")
    /// String literals — green.
    static let justCodeString = dynamicColor(light: "0A7C43", dark: "34C759")
    /// Keywords — purple/pink.
    static let justCodeKeyword = dynamicColor(light: "A8269C", dark: "FF7AB2")
    /// Numeric literals — orange.
    static let justCodeNumber = dynamicColor(light: "B4510A", dark: "FFB340")
    /// Type / class names — blue.
    static let justCodeType = dynamicColor(light: "0A6BED", dark: "6AA9FF")
}

extension LinearGradient {
    /// Accent → lighter accent, used for avatars and primary CTAs to add depth.
    static var justAccent: LinearGradient {
        LinearGradient(
            colors: [Color.justAccent, Color.justAccentLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension AppearanceMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

// MARK: - Shadows

private struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(scheme == .dark ? 0.40 : 0.06),
            radius: scheme == .dark ? 5 : 4,
            x: 0,
            y: scheme == .dark ? 2 : 1
        )
    }
}

private struct RaisedShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(
            color: .black.opacity(scheme == .dark ? 0.50 : 0.10),
            radius: scheme == .dark ? 14 : 12,
            x: 0,
            y: scheme == .dark ? 6 : 6
        )
    }
}

extension View {
    /// Subtle elevation for cards and bubbles.
    func cardShadow() -> some View { modifier(CardShadow()) }

    /// Stronger elevation for floating surfaces (composer, panels).
    func raisedShadow() -> some View { modifier(RaisedShadow()) }

    /// Suppress SwiftUI's keyboard-focus halo on mouse-first controls.
    func suppressFocusRing() -> some View {
        focusable(false)
            .focusEffectDisabled()
    }

    /// Thin hairline border in the soft border token.
    func softBorder(radius: CGFloat = Radius.md, lineWidth: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: lineWidth)
        )
    }
}

// MARK: - Hover surface

private struct HoverSurface: ViewModifier {
    var radius: CGFloat = 10
    var opacity: Double = 0.7
    @State private var hovered = false
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.justControlBackground.opacity(hovered ? opacity : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.justBorderSoft.opacity(hovered ? 1 : 0), lineWidth: 1)
            )
            .onHover { isHovering in
                hovered = isHovering
                if isHovering, !cursorPushed {
                    NSCursor.pointingHand.push()
                    cursorPushed = true
                } else if !isHovering, cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

extension View {
    /// Soft control-surface highlight on hover, used behind icon buttons and rows.
    func hoverSurface(radius: CGFloat = 10, opacity: Double = 0.7) -> some View {
        modifier(HoverSurface(radius: radius, opacity: opacity))
            .suppressFocusRing()
    }
}

// MARK: - Shared card surface

/// Reusable glass card: frosted material over the control surface, hairline
/// border, and a subtle shadow. Used by the main window, agent editor, and
/// settings panes so card styling never diverges.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var radius: CGFloat = Radius.md
    var material: Material = .regular
    var padded: Bool = true

    var body: some View {
        Group {
            if padded {
                content.padding(20)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(material)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .cardShadow()
    }
}
