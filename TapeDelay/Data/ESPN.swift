import Foundation

/// ESPN's keyless site API, parsed loosely: the same document shape covers every team sport,
/// but fields come and go per league, so nothing here is a strict Decodable.
///
/// Traps carried over from BrightSports (see its README):
/// - timestamps have no seconds (`2026-07-29T16:10Z`)
/// - `teams?groups=` ignores the group, so college rosters come from the standings tree
/// - a rain delay is `state: "in"` with a `STATUS_*_DELAY` name; postponed is `post`
/// - `limit=200` truncates a fortnight of MLB; ask for 1000
enum ESPN {
    static let site = "https://site.api.espn.com/apis/site/v2/sports"
    static let standingsBase = "https://site.api.espn.com/apis/v2/sports"

    typealias J = [String: Any]

    static func get(_ url: String) async throws -> J {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw URLError(.badServerResponse) }
        return (try JSONSerialization.jsonObject(with: data)) as? J ?? [:]
    }

    // MARK: scoreboard

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    static func scoreboard(_ league: League, from: Date, to: Date) async throws -> [Game] {
        var paths = [league.slug] + league.extras
        paths = Array(Set(paths))
        var out: [Game] = []
        try await withThrowingTaskGroup(of: [Game].self) { g in
            for slug in paths {
                g.addTask {
                    var url = "\(site)/\(league.sport)/\(slug)/scoreboard?limit=1000&dates=\(dayString(from))-\(dayString(to))"
                    if let grp = league.group { url += "&groups=\(grp)" }
                    do { return parseScoreboard(try await get(url), league: league.id) }
                    catch { if slug == league.slug { throw error } else { return [] } }
                }
            }
            for try await part in g { out += part }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
    }

    static func parseScoreboard(_ doc: J, league: String) -> [Game] {
        (doc["events"] as? [J] ?? []).compactMap { parseEvent($0, league: league) }
    }

    static func parseEvent(_ ev: J, league: String) -> Game? {
        guard let id = ev["id"] as? String,
              let comp = (ev["competitions"] as? [J])?.first,
              let comps = comp["competitors"] as? [J], comps.count == 2 else { return nil }
        let status = comp["status"] as? J ?? ev["status"] as? J ?? [:]
        let type = status["type"] as? J ?? [:]
        let name = (type["name"] as? String ?? "").uppercased()
        let rawState = type["state"] as? String ?? "pre"
        var state: GameState = rawState == "in" ? .live : rawState == "post" ? .post : .pre
        if ["DELAY", "SUSPEND", "POSTPONE", "CANCEL"].contains(where: { name.contains($0) }) { state = .off }
        let sides = comps.map(parseSide)
        guard let home = zip(comps, sides).first(where: { ($0.0["homeAway"] as? String) == "home" })?.1,
              let away = zip(comps, sides).first(where: { ($0.0["homeAway"] as? String) == "away" })?.1
        else { return nil }
        let tv = (comp["broadcasts"] as? [J])?.flatMap { $0["names"] as? [String] ?? [] }.first
        let note = ((comp["notes"] as? [J])?.first?["headline"] as? String)
            ?? ((ev["notes"] as? [J])?.first?["headline"] as? String)
        return Game(
            id: id, league: league,
            date: iso(ev["date"] as? String) ?? .distantFuture,
            state: state,
            detail: type["shortDetail"] as? String ?? type["detail"] as? String ?? "",
            period: status["period"] as? Int ?? 0,
            home: home, away: away,
            venue: (comp["venue"] as? J)?["fullName"] as? String,
            tv: tv, note: note,
            situation: parseSituation(comp["situation"] as? J))
    }

    static func parseSide(_ c: J) -> Side {
        let t = c["team"] as? J ?? [:]
        let logo = (t["logo"] as? String) ?? ((t["logos"] as? [J])?.first?["href"] as? String)
        let lines = (c["linescores"] as? [J] ?? []).map { l -> String in
            if let s = l["displayValue"] as? String { return s }
            if let v = l["value"] as? Double { return String(Int(v)) }
            return "-"
        }
        return Side(
            teamId: t["id"] as? String ?? "",
            uid: t["uid"] as? String ?? "",
            abbr: t["abbreviation"] as? String ?? "",
            name: t["displayName"] as? String ?? t["name"] as? String ?? "",
            short: t["shortDisplayName"] as? String ?? t["name"] as? String ?? "",
            color: t["color"] as? String ?? "888888",
            logo: logo.flatMap(URL.init(string:)),
            score: score(c["score"]),
            record: (c["records"] as? [J])?.first?["summary"] as? String,
            winner: c["winner"] as? Bool ?? false,
            lines: lines)
    }

    static func score(_ v: Any?) -> Int? {
        switch v {
        case let s as String: return Double(s).map { Int($0) }
        case let d as Double: return Int(d)
        case let i as Int: return i
        case let j as J: return score(j["value"] ?? j["displayValue"])
        default: return nil
        }
    }

    static func parseSituation(_ s: J?) -> Situation? {
        guard let s else { return nil }
        return Situation(
            possession: s["possession"] as? String,
            downDistance: s["shortDownDistanceText"] as? String ?? s["downDistanceText"] as? String,
            balls: s["balls"] as? Int, strikes: s["strikes"] as? Int, outs: s["outs"] as? Int,
            onFirst: s["onFirst"] as? Bool ?? false, onSecond: s["onSecond"] as? Bool ?? false,
            onThird: s["onThird"] as? Bool ?? false,
            lastPlay: (s["lastPlay"] as? J)?["text"] as? String)
    }

    /// ESPN omits seconds; ISO8601DateFormatter rejects that, so try both shapes.
    static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let a = ISO8601DateFormatter()
        if let d = a.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    // MARK: teams

    static func teams(_ league: League) async throws -> [Team] {
        if league.group != nil {
            // `teams?groups=` is ignored; the standings tree carries full team objects.
            return try await standings(league).flatMap(\.rows).map {
                Team(uid: $0.uid, teamId: $0.uid.components(separatedBy: "t:").last ?? "", league: league.id,
                     name: $0.name, short: $0.name, abbr: $0.abbr, color: "888888", logo: $0.logo)
            }.uniqued()
        }
        let doc = try await get("\(site)/\(league.path)/teams?limit=1000")
        let raw = ((doc["sports"] as? [J])?.first?["leagues"] as? [J])?.first?["teams"] as? [J] ?? []
        return raw.compactMap { w -> Team? in
            guard let t = w["team"] as? J, let uid = t["uid"] as? String, let id = t["id"] as? String else { return nil }
            let logos = t["logos"] as? [J] ?? []
            let dark = logos.first { ($0["rel"] as? [String] ?? []).contains("dark") } ?? logos.first
            return Team(uid: uid, teamId: id, league: league.id,
                        name: t["displayName"] as? String ?? "",
                        short: t["shortDisplayName"] as? String ?? t["name"] as? String ?? "",
                        abbr: t["abbreviation"] as? String ?? "",
                        color: t["color"] as? String ?? "888888",
                        logo: (dark?["href"] as? String).flatMap(URL.init(string:)))
        }.sorted { $0.name < $1.name }
    }

    // MARK: standings

    static func standings(_ league: League) async throws -> [StandingsGroup] {
        var url = "\(standingsBase)/\(league.path)/standings?level=3"
        if let g = league.group { url += "&group=\(g)" }
        return parseStandings(try await get(url), kind: league.kind)
    }

    /// Walks the `children` tree to every node that carries `standings.entries`; nesting
    /// depth differs per league, so never index it.
    static func parseStandings(_ doc: J, kind: Sport) -> [StandingsGroup] {
        var out: [StandingsGroup] = []
        func walk(_ n: J) {
            if let st = n["standings"] as? J, let entries = st["entries"] as? [J], !entries.isEmpty {
                let cols = columns(kind)
                let rows = entries.compactMap { e -> StandingsRow? in
                    guard let t = e["team"] as? J, let uid = t["uid"] as? String else { return nil }
                    let stats = e["stats"] as? [J] ?? []
                    func v(_ key: String) -> String {
                        stats.first { ($0["name"] as? String) == key || ($0["type"] as? String) == key }?["displayValue"] as? String ?? "–"
                    }
                    let logo = ((t["logos"] as? [J])?.first?["href"] as? String).flatMap(URL.init(string:))
                    return StandingsRow(uid: uid, name: t["displayName"] as? String ?? "",
                                        abbr: t["abbreviation"] as? String ?? "", logo: logo,
                                        values: cols.map { v($0.key) })
                }
                out.append(StandingsGroup(name: n["name"] as? String ?? "", columns: cols.map(\.label), rows: rows))
            }
            for c in n["children"] as? [J] ?? [] { walk(c) }
        }
        walk(doc)
        return out
    }

    static func columns(_ kind: Sport) -> [(key: String, label: String)] {
        switch kind {
        case .soccer: [("gamesPlayed", "GP"), ("wins", "W"), ("ties", "D"), ("losses", "L"), ("pointDifferential", "GD"), ("points", "PTS")]
        case .hockey: [("wins", "W"), ("losses", "L"), ("otLosses", "OTL"), ("points", "PTS")]
        case .football: [("wins", "W"), ("losses", "L"), ("ties", "T"), ("winPercent", "PCT")]
        case .baseball, .basketball: [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB")]
        }
    }
}

extension Array where Element == Team {
    func uniqued() -> [Team] {
        var seen = Set<String>()
        return filter { seen.insert($0.uid).inserted }.sorted { $0.name < $1.name }
    }
}
