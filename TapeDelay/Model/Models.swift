import Foundation

/// A league the app carries. Every one of these is on the relay's FastCast feed, so every
/// followed team gets held pushes, not just in-app scores.
struct League: Identifiable, Hashable, Codable {
    let id: String            // "nfl"
    let name: String          // "NFL"
    let sport: String         // ESPN path: "football"
    let slug: String          // ESPN path: "nfl"
    var group: String? = nil  // college: ESPN group filter
    var extras: [String] = [] // cup competitions that reuse this league's team ids (MLS)
    let kind: Sport

    var path: String { "\(sport)/\(slug)" }

    static let all: [League] = [
        League(id: "nfl", name: "NFL", sport: "football", slug: "nfl", kind: .football),
        League(id: "mlb", name: "MLB", sport: "baseball", slug: "mlb", kind: .baseball),
        League(id: "nba", name: "NBA", sport: "basketball", slug: "nba", kind: .basketball),
        League(id: "nhl", name: "NHL", sport: "hockey", slug: "nhl", kind: .hockey),
        League(id: "mls", name: "MLS", sport: "soccer", slug: "usa.1",
               extras: ["concacaf.leagues.cup", "usa.open"], kind: .soccer),
        League(id: "wnba", name: "WNBA", sport: "basketball", slug: "wnba", kind: .basketball),
        League(id: "nwsl", name: "NWSL", sport: "soccer", slug: "usa.nwsl", kind: .soccer),
        League(id: "cfb", name: "College Football", sport: "football", slug: "college-football",
               group: "80", kind: .football),
        League(id: "epl", name: "Premier League", sport: "soccer", slug: "eng.1", kind: .soccer),
        League(id: "ucl", name: "Champions League", sport: "soccer", slug: "uefa.champions", kind: .soccer),
    ]

    static func byId(_ id: String) -> League? { all.first { $0.id == id } }
}

enum Sport: String, Codable, Hashable {
    case football, baseball, basketball, hockey, soccer

    var symbol: String {
        switch self {
        case .football: "football.fill"
        case .baseball: "baseball.fill"
        case .basketball: "basketball.fill"
        case .hockey: "hockey.puck.fill"
        case .soccer: "soccerball"
        }
    }
}

/// A team the user follows. `uid` is ESPN's (`s:20~l:28~t:26`): it's what the relay matches
/// on, and unlike the bare id it can't collide across leagues.
struct Team: Identifiable, Hashable, Codable {
    var id: String { uid }
    let uid: String
    let teamId: String
    let league: String
    let name: String
    let short: String
    let abbr: String
    let color: String
    let logo: URL?
}

enum GameState: String, Codable { case pre, live, post, off }

struct Side: Hashable {
    var teamId: String
    var uid: String
    var abbr: String
    var name: String
    var short: String
    var color: String
    var logo: URL?
    var score: Int?
    var record: String?
    var winner: Bool
    var lines: [String]
}

struct Game: Identifiable, Hashable {
    let id: String
    let league: String
    let date: Date
    var state: GameState
    var detail: String       // "3:24 - 2nd", "Final", "7:05 PM"
    var period: Int
    var home: Side
    var away: Side
    var venue: String?
    var tv: String?
    var note: String?
    var situation: Situation?
    /// True when the score shown is the relay's held copy, behind the live one.
    var held = false
    /// True when the score is being hidden because no held copy was available.
    var masked = false

    func involves(_ uids: Set<String>) -> Bool { uids.contains(home.uid) || uids.contains(away.uid) }
    var kind: Sport { League.byId(league)?.kind ?? .football }
}

struct Situation: Hashable {
    var possession: String?  // team id
    var downDistance: String?
    var balls: Int?
    var strikes: Int?
    var outs: Int?
    var onFirst = false, onSecond = false, onThird = false
    var lastPlay: String?
}

struct StandingsGroup: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let columns: [String]
    let rows: [StandingsRow]
}

struct StandingsRow: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
    let abbr: String
    let logo: URL?
    let values: [String]
}
