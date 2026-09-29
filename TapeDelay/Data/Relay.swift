import Foundation

/// The BasilNet relay (`relay/tape.py` in gi-os/BrightSports). It sends every alert and Live
/// Activity update late, by this device's delay, and serves games as they stood that long ago.
enum Relay {
    static let base = URL(string: "https://sports.gzl.dev/tape/v1")!

    #if DEBUG
    static let env = "dev"
    #else
    static let env = "prod"
    #endif

    struct Registration: Encodable {
        let token: String
        let env: String
        let delay: Int
        let follows: [String]
        let prefs: [String: Bool]
        let startToken: String?
    }

    static func register(_ r: Registration) async throws {
        try await post("device", r)
    }

    static func activity(device: String, game: String, token: String?) async throws {
        struct A: Encodable { let device: String; let game: String; let token: String? }
        try await post("activity", A(device: device, game: game, token: token))
    }

    private static func post<T: Encodable>(_ path: String, _ body: T) async throws {
        var req = URLRequest(url: base.appending(path: path), timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    /// A relay snapshot (see the relay README): the moving parts of one game.
    struct Snapshot: Decodable {
        struct Side: Decodable { let id: String?; let sc: Int?; let ls: [String]? }
        struct Sit: Decodable {
            let poss: String?; let sdd: String?; let dd: String?
            let b: Int?; let s: Int?; let o: Int?
            let on1: Bool?; let on2: Bool?; let on3: Bool?; let lp: String?
        }
        let id: String?
        let st: String?
        let nm: String?
        let dt: String?
        let p: Int?
        let home: Side?
        let away: Side?
        let sit: Sit?
        let held: Bool?
        /// Seconds this source trails the play (ESPN ~20, MLB's own feed ~2).
        let lag: Double?
    }

    /// The newest thing the relay knows about a game, and when it learned it (for stream sync).
    struct Latest: Decodable { let now: Double; let ts: Double?; let snap: Snapshot? }

    static func latest(id: String) async throws -> Latest {
        var c = URLComponents(url: base.appending(path: "latest"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "id", value: id)]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        return try JSONDecoder().decode(Latest.self, from: data)
    }

    static func delayed(ids: [String], delay: Int) async throws -> [String: Snapshot] {
        guard !ids.isEmpty else { return [:] }
        var c = URLComponents(url: base.appending(path: "delayed"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
                        URLQueryItem(name: "delay", value: String(delay))]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([String: Snapshot].self, from: data)
    }
}

extension Game {
    /// This game as the relay says it stood `delay` seconds ago.
    func holding(_ s: Relay.Snapshot) -> Game {
        var g = self
        g.held = true
        g.masked = false
        if s.held == true || s.st == "pre" {
            g.state = .pre
            g.detail = "Starting soon"
            g.home.score = nil; g.away.score = nil
            g.home.lines = []; g.away.lines = []
            g.home.winner = false; g.away.winner = false
            g.situation = nil
            return g
        }
        let name = (s.nm ?? "").uppercased()
        g.state = s.st == "post" ? .post : s.st == "in" ? .live : .pre
        if ["DELAY", "SUSPEND", "POSTPONE", "CANCEL"].contains(where: { name.contains($0) }) { g.state = .off }
        g.detail = s.dt ?? g.detail
        g.period = s.p ?? g.period
        g.home.score = s.home?.sc ?? g.home.score
        g.away.score = s.away?.sc ?? g.away.score
        g.home.lines = s.home?.ls ?? []
        g.away.lines = s.away?.ls ?? []
        if g.state != .post { g.home.winner = false; g.away.winner = false }
        if let t = s.sit {
            g.situation = Situation(possession: t.poss, downDistance: t.sdd ?? t.dd,
                                    balls: t.b, strikes: t.s, outs: t.o,
                                    onFirst: t.on1 ?? false, onSecond: t.on2 ?? false, onThird: t.on3 ?? false,
                                    lastPlay: t.lp)
        } else {
            g.situation = nil
        }
        return g
    }

    /// No held copy to show: hide what would give the game away.
    func masking() -> Game {
        var g = self
        g.masked = true
        g.home.score = nil; g.away.score = nil
        g.home.lines = []; g.away.lines = []
        g.home.winner = false; g.away.winner = false
        g.situation = nil
        g.detail = state == .post ? "Final · hidden" : "Live · hidden"
        return g
    }
}

/// How far behind live the user is watching. Numbers are typical figures, not promises:
/// every stream drifts, which is why there's a custom slider.
struct DelayPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let seconds: Int
    let note: String

    /// Counted from the play itself (the relay knows how far each feed trails it), so the same
    /// number means the same thing for every sport. Typical figures; streams drift, so sync.
    static let all: [DelayPreset] = [
        DelayPreset(name: "Live", seconds: 0, note: "At the game, or on the radio"),
        DelayPreset(name: "Cable / antenna", seconds: 20, note: "About where ESPN's own feed runs"),
        DelayPreset(name: "YouTube TV", seconds: 45, note: ""),
        DelayPreset(name: "Fubo", seconds: 50, note: ""),
        DelayPreset(name: "Hulu + Live TV", seconds: 55, note: ""),
        DelayPreset(name: "Sling", seconds: 55, note: ""),
        DelayPreset(name: "Peacock / Paramount+", seconds: 60, note: ""),
        DelayPreset(name: "ESPN app / Max", seconds: 60, note: ""),
        DelayPreset(name: "MLB.tv / NBA League Pass", seconds: 65, note: ""),
        DelayPreset(name: "Apple TV (MLS)", seconds: 65, note: ""),
        DelayPreset(name: "Watching later", seconds: 600, note: "Ten minutes behind"),
    ]}
