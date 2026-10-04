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
        // Scorebug extras, all optional so an older relay's pushes still decode.
        var clock: String?
        var spot: String?
        var redZone: Bool?
        var homeTimeouts: Int?
        var awayTimeouts: Int?
        var pitcher: String?
        var pitcherLine: String?
        var batter: String?
        var batterLine: String?
        var homeHits: Int?
        var awayHits: Int?
        var homeErrors: Int?
        var awayErrors: Int?
        /// Past start time with nothing under way (a hold, a rain delay before first pitch).
        var late: Bool?
        var homeBonus: Bool?
        var awayBonus: Bool?
        var homeFouls: Int?
        var awayFouls: Int?
        // League card (relay `compose()`): the pill, and the grid when this card shows it.
        var leagueName: String?
        var leagueMore: Int?
        var view: String?          // "league" while the card shows the grid
        var page: Int?
        var pages: Int?
        var leagueTitle: String?
        var tiles: [Tile]?

        var showsLeague: Bool { view == "league" && !(tiles ?? []).isEmpty }

        var isFinal: Bool { state == "post" }
        var isLive: Bool { state == "in" }
    }

    /// One game in the league grid: a scorebug in miniature. Short keys: up to 4 ride in every push.
    struct Tile: Codable, Hashable, Identifiable {
        var id: String
        var a: String, h: String         // abbreviations
        var ac: String, hc: String       // colours
        var st: String                   // pre / in / post
        var d: String                    // "▲5", "3RD 14:48", "Q4 4:12", "72'", "FINAL"
        var awayScore: Int?, homeScore: Int?
        var t: Double?                   // start, for games not under way
        var b: Int?                      // bases, bit 0 first .. bit 2 third
        var o: Int?                      // outs
        var n: String?                   // series note
        var tv: String?

        enum CodingKeys: String, CodingKey {
            case id, a, h, ac, hc, st, d, t, b, o, n, tv
            case awayScore = "as", homeScore = "hs"
        }
    }

    var gameId: String
    var sport: String
    var homeAbbr: String
    var awayAbbr: String
    var homeName: String
    var awayName: String
    var homeColor: String
    var awayColor: String
    var homeUid: String?
    var awayUid: String?
    var homeRecord: String?
    var awayRecord: String?
    // Starting-soon card. All optional.
    var startTime: Double?
    var venue: String?
    var watch: String?
    var homeProbable: String?
    var awayProbable: String?
    var homeProbableLine: String?
    var awayProbableLine: String?
    var homeForm: String?
    var awayForm: String?
    /// This device's delay when the card was started, so it can say when the start reaches the stream.
    var delay: Int?

    /// When the start reaches your stream.
    var streamStart: Date? {
        guard let t = startTime, t > 0 else { return nil }
        return Date(timeIntervalSince1970: t + Double(delay ?? 0))
    }
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
