import SwiftUI

/// La Réplique's identity — a lit prompt-book on a dark stage. Cool, not warm.
enum Theme {
    static let desk = Color(hex: 0x171a22)
    static let deskLight = Color(hex: 0x1f2430)
    static let rule = Color(hex: 0x2b3140)
    static let paper = Color(hex: 0xfbfcfe)
    static let paperShade = Color(hex: 0xeef1f6)
    static let ink = Color(hex: 0x20232c)
    static let inkSoft = Color(hex: 0x5a6273)
    static let inkFaint = Color(hex: 0x8b93a4)
    static let gel = Color(hex: 0x4f7cff)
    static let gelBright = Color(hex: 0x6f97ff)
    static let cyan = Color(hex: 0x12b5d4)
    static let rose = Color(hex: 0xf43f5e)
    static let jade = Color(hex: 0x10b981)
    static let plum = Color(hex: 0x8b5cf6)
    static let amber = Color(hex: 0xd97706)

    /// The cast swatch palette, in assignment order (mirrors the web app).
    static let castSwatches: [String] = [
        "#4f7cff", "#0ea5b7", "#10b981", "#8b5cf6", "#f43f5e",
        "#64748b", "#d97706", "#3f7d5c", "#4f46e5", "#fb7185",
    ]

    static func nextCastColor(used: [String]) -> String {
        castSwatches.first { !used.contains($0) } ?? castSwatches[used.count % castSwatches.count]
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    /// Parse a "#rrggbb" string (falls back to gel).
    init(hexString: String?) {
        let s = (hexString ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if let v = UInt(s, radix: 16), s.count == 6 {
            self.init(hex: v)
        } else {
            self.init(hex: 0x4f7cff)
        }
    }
}
