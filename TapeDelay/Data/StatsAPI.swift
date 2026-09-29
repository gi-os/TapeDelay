import Foundation

/// Minor League Baseball, off MLB's StatsAPI (ESPN publishes no minor-league scoreboard; this is
/// the feed MiLB.com runs on). Traps carried over from BrightSports:
/// - `standings` ignores `sportId`: expand the level through `/leagues?sportId=` and ask by leagueId
/// - a postponed game is `abstractGameState: "Final"`, a suspended one `"Live"`: read the detailed
///   state first
/// - a postponed game with a make-up date is listed twice under one gamePk: keep one per id
///
/// Game ids are `milb-<gamePk>` and team uids `milb:<teamId>`, the same keys the relay uses, so
/// held pushes and the held overlay line up.
enum StatsAPI {
    static let base = "https://statsapi.mlb.com/api/v1"
    typealias J = [String: Any]

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func schedule(_ league: League, from: Date, to: Date) async throws -> [Game] {
        guard let sid = league.sportId else { return [] }
        let doc = try await ESPN.get("\(base)/schedule?sportId=\(sid)&startDate=\(day(from))&endDate=\(day(to))&hydrate=linescore,team")
        var byId: [String: Game] = [:]
        for d in doc["dates"] as? [J] ?? [] {
            for g in d["games"] as? [J] ?? [] {
                guard let game = parse(g, league: league.id) else { continue }
                if let old = byId[game.id], rank(old.state) >= rank(game.state) { continue }
                byId[game.id] = game
            }
        }
        return byId.values.sorted { $0.date < $1.date }
    }

    /// Which duplicate wins: a postponement or a final says more than a bare "scheduled".
    private static func rank(_ s: GameState) -> Int {
        switch s { case .pre: 0; case .live: 1; case .post: 2; case .off: 3 }
    }

    static func parse(_ g: J, league: String) -> Game? {
        guard let pk = g["gamePk"] as? Int,
              let teams = g["teams"] as? J,
              let h = teams["home"] as? J, let a = teams["away"] as? J else { return nil }
        let status = g["status"] as? J ?? [:]
        let detailed = status["detailedState"] as? String ?? ""
        let abstract = status["abstractGameState"] as? String ?? "Preview"
        let ls = g["linescore"] as? J ?? [:]
        var state: GameState = abstract == "Live" ? .live : abstract == "Final" ? .post : .pre
        if ["Postpon", "Suspend", "Delay", "Cancel"].contains(where: { detailed.contains($0) }) { state = .off }
        let inning = ls["currentInning"] as? Int ?? 0
        var detail = detailed
        if state == .live, let half = ls["inningState"] as? String, let ord = ls["currentInningOrdinal"] as? String {
            detail = "\(half) \(ord)"
        } else if state == .post {
            detail = inning > 9 ? "Final/\(inning)" : "Final"
        }
        let innings = ls["innings"] as? [J] ?? []
        func side(_ s: J, _ key: String) -> Side {
            let t = s["team"] as? J ?? [:]
            let id = t["id"] as? Int ?? 0
            let rec = s["leagueRecord"] as? J
            return Side(
                teamId: String(id), uid: "milb:\(id)",
                abbr: t["abbreviation"] as? String ?? "",
                name: t["name"] as? String ?? "",
                short: t["teamName"] as? String ?? t["clubName"] as? String ?? "",
                color: color(id),
                logo: URL(string: "https://midfield.mlbstatic.com/v1/team/\(id)/spots/128"),
                score: state == .pre ? nil : s["score"] as? Int,
                record: rec.map { "\($0["wins"] as? Int ?? 0)-\($0["losses"] as? Int ?? 0)" },
                winner: s["isWinner"] as? Bool ?? false,
                lines: innings.map { i in ((i[key] as? J)?["runs"] as? Int).map(String.init) ?? "-" })
        }
        let off = ls["offense"] as? J ?? [:]
        let sit = state == .live ? Situation(
            possession: nil, downDistance: nil,
            balls: ls["balls"] as? Int, strikes: ls["strikes"] as? Int, outs: ls["outs"] as? Int,
            onFirst: off["first"] != nil, onSecond: off["second"] != nil, onThird: off["third"] != nil,
            lastPlay: nil) : nil
        return Game(id: "milb-\(pk)", league: league,
                    date: ESPN.iso(g["gameDate"] as? String) ?? .distantFuture,
                    state: state, detail: detail, period: inning,
                    home: side(h, "home"), away: side(a, "away"),
                    venue: (g["venue"] as? J)?["name"] as? String, tv: nil, note: nil, situation: sit)
    }

    static func teams(_ league: League) async throws -> [Team] {
        guard let sid = league.sportId else { return [] }
        let year = Calendar.current.component(.year, from: Date())
        let doc = try await ESPN.get("\(base)/teams?sportId=\(sid)&season=\(year)")
        return (doc["teams"] as? [J] ?? []).compactMap { t -> Team? in
            guard let id = t["id"] as? Int else { return nil }
            return Team(uid: "milb:\(id)", teamId: String(id), league: league.id,
                        name: t["name"] as? String ?? "", short: t["teamName"] as? String ?? "",
                        abbr: t["abbreviation"] as? String ?? "", color: color(id),
                        logo: URL(string: "https://midfield.mlbstatic.com/v1/team/\(id)/spots/128"))
        }.sorted { $0.name < $1.name }
    }

    static func standings(_ league: League) async throws -> [StandingsGroup] {
        guard let sid = league.sportId else { return [] }
        let year = Calendar.current.component(.year, from: Date())
        let lg = try await ESPN.get("\(base)/leagues?sportId=\(sid)&season=\(year)")
        let ids = (lg["leagues"] as? [J] ?? []).compactMap { $0["id"] as? Int }.map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return [] }
        let doc = try await ESPN.get("\(base)/standings?leagueId=\(ids)&season=\(year)&hydrate=team,division")
        return (doc["records"] as? [J] ?? []).compactMap { r -> StandingsGroup? in
            let name = ((r["division"] as? J)?["name"] as? String) ?? ((r["league"] as? J)?["name"] as? String) ?? ""
            let rows = (r["teamRecords"] as? [J] ?? []).compactMap { tr -> StandingsRow? in
                guard let t = tr["team"] as? J, let id = t["id"] as? Int else { return nil }
                return StandingsRow(uid: "milb:\(id)", name: t["name"] as? String ?? "",
                                    abbr: t["abbreviation"] as? String ?? "",
                                    logo: URL(string: "https://midfield.mlbstatic.com/v1/team/\(id)/spots/64"),
                                    values: ["\(tr["wins"] as? Int ?? 0)", "\(tr["losses"] as? Int ?? 0)",
                                             tr["winningPercentage"] as? String ?? "–", tr["gamesBack"] as? String ?? "–"])
            }
            return rows.isEmpty ? nil : StandingsGroup(name: name, columns: ["W", "L", "PCT", "GB"], rows: rows)
        }
    }

    /// StatsAPI carries no team colours; a stable pick from a palette of ballpark colours keeps
    /// every club's gradient the same from day to day.
    static func color(_ id: Int) -> String {
        let palette = ["0c2340", "bd3039", "005a9c", "134a8e", "c41e3a", "0e3386", "fd5a1e", "27251f",
                       "004687", "ce1141", "33006f", "005c5c", "e81828", "003831", "ba0021", "002d72"]
        return palette[abs(id) % palette.count]
    }
}
