import ActivityKit
import SwiftUI

/// One game on the lock screen and in the Dynamic Island.
///
/// The relay starts and updates these by push, so the JSON keys here are a wire format:
/// they must match `attributes()` and `content_state()` in `relay/tape.py` exactly.
/// The type name is on the wire too (`"attributes-type": "GameAttributes"`).
struct GameAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var home: Int
        var away: Int
        var detail: String
        var state: String          // pre / in / post
        var period: Int
        var possession: String?    // "home" / "away"
        var down: String?
        var outs: Int?
        var balls: Int?
        var strikes: Int?
        var bases: [Bool]?
        var lastPlay: String?

        var isFinal: Bool { state == "post" }
    }

    var gameId: String
    var sport: String
    var homeAbbr: String
    var awayAbbr: String
    var homeName: String
    var awayName: String
    var homeColor: String
    var awayColor: String
}

extension Color {
    /// ESPN team colours come as bare hex ("002244").
    init(hex: String, fallback: Color = .gray) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = fallback; return }
        self = Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    /// Team colours are often near-black; lift those so they read on a dark glass card.
    static func team(_ hex: String) -> Color {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .gray }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        if lum < 0.18 { return Color(hex: s).mix(with: .white, by: 0.35) }
        return Color(hex: s)
    }
}
