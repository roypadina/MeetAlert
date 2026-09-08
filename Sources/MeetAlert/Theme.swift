import AppKit
import SwiftUI

/// One dynamic colour from a light/dark pair — same mechanism the system uses for semantic colours,
/// so every Color below flips with the appearance automatically (no @Environment plumbing).
private func dyn(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
}

/// Alert-panel look: one signal hue per urgency, ink base over material, rounded instrument type.
/// Values only — no layout, no behaviour. Contrast noted per colour; all pairs ≥ 4.9:1.
enum Theme {
    /// Panel base tint over .regularMaterial. Navy-ink, not neutral black.
    static let ink = dyn(light: NSColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.45),
                         dark: NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 0.55))

    /// Urgency signal hues. Dark variants are bright (used on dark ink); light variants are deep
    /// (used on near-white). Text placed ON a signal fill uses `onSignal`.
    static let calm = dyn(light: NSColor(red: 0.00, green: 0.48, blue: 0.60, alpha: 1),   // #007A99  4.9:1 on white
                          dark: NSColor(red: 0.24, green: 0.88, blue: 1.00, alpha: 1))    // #3DE1FF 12.4:1 on ink
    static let imminent = dyn(light: NSColor(red: 0.60, green: 0.36, blue: 0.00, alpha: 1), // #9A5B00  5.9:1 on white
                              dark: NSColor(red: 1.00, green: 0.70, blue: 0.14, alpha: 1))  // #FFB224 10.1:1 on ink
    static let started = dyn(light: NSColor(red: 0.77, green: 0.12, blue: 0.09, alpha: 1),  // #C41E17  6.1:1 on white
                             dark: NSColor(red: 1.00, green: 0.35, blue: 0.31, alpha: 1))   // #FF5A4E  5.5:1 on ink
    /// Ink text on the bright dark-mode fills (≥6.5:1), white on the deep light-mode fills (≥4.9:1).
    static let onSignal = dyn(light: .white, dark: NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1))

    static let panelRadius: CGFloat = 20  // continuous
    static let rimWidth: CGFloat = 4      // left signal bar
    static let strokeWidth: CGFloat = 1   // hairline edge (2 under Increase Contrast)

    static let title = Font.system(size: 17, weight: .semibold)                    // meeting title, 2 lines max
    static let meta = Font.system(size: 13, weight: .regular)                      // time range, provider
    static let state = Font.system(size: 12, weight: .semibold, design: .rounded)  // "Starting in", "Started"
    static let countdown = Font.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
    static let unit = Font.system(size: 12, weight: .medium, design: .rounded)     // "min" / "sec" / "min late"
    static let button = Font.system(size: 13, weight: .semibold)
    static let calendarTag = Font.system(size: 12, weight: .medium)  // calendar name next to its colour dot
}

extension NSColor {
    /// "#RRGGBB" (or "RRGGBB") → colour. Returns nil on anything else, so a hand-edited config
    /// with a bad value falls back to the calendar's own colour instead of rendering black.
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    /// Round-trip partner of init(hex:) — what Settings writes into config.calendarColors.
    var hexString: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}
