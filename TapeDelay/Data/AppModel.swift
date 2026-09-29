import Foundation
import Observation
import SwiftUI

/// Everything the screens share: follows, the delay, the feed.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: settings (UserDefaults)

    var follows: [Team] { didSet { save(follows, "follows"); pushSettings() } }
    var delay: Int { didSet { UserDefaults.standard.set(delay, forKey: "delay"); pushSettings() } }
    var presetName: String { didSet { UserDefaults.standard.set(presetName, forKey: "preset") } }
    var prefs: Prefs { didSet { save(prefs, "prefs"); pushSettings() } }
    /// Followed teams that stay in the feed but don't notify: no alerts, no Live Activities.
    var muted: Set<String> { didSet { save(Array(muted), "muted"); pushSettings() } }

    struct Prefs: Codable, Hashable {
        var start = true
        var score = true
        var period = true
        var final = true
        var delay = true
        var resume = true
        var everyBasket = false
        var liveActivities = true
        /// With a delay on and no held copy from the relay, hide live scores rather than
        /// show ones that are ahead of the stream.
        var maskWhenUnsure = true

        var wire: [String: Bool] {
            ["start": start, "score": score, "period": period, "final": final, "delay": delay,
             "resume": resume, "everyBasket": everyBasket, "liveActivities": liveActivities]
        }
    }

    // MARK: push identity

    var deviceToken: String? { didSet { UserDefaults.standard.set(deviceToken, forKey: "deviceToken"); pushSettings() } }
    var startToken: String? { didSet { pushSettings() } }
    var relayStatus: String = "Not registered yet"

    // MARK: feed

    var games: [Game] = []
    var loading = false
    var lastError: String?
    var lastRefresh: Date?

    var followedUids: Set<String> { Set(follows.map(\.uid)) }
    var followedLeagues: [League] {
        let ids = Set(follows.map(\.league))
        return League.all.filter { ids.contains($0.id) }
    }

    private init() {
        let d = UserDefaults.standard
        follows = Self.load("follows") ?? []
        delay = d.object(forKey: "delay") as? Int ?? 30
        presetName = d.string(forKey: "preset") ?? "YouTube TV"
        prefs = Self.load("prefs") ?? Prefs()
        muted = Set(Self.load("muted") ?? [String]())
        deviceToken = d.string(forKey: "deviceToken")
    }

    func isFollowed(_ t: Team) -> Bool { follows.contains { $0.uid == t.uid } }

    func isMuted(_ t: Team) -> Bool { muted.contains(t.uid) }
    func toggleMute(_ t: Team) {
        if muted.contains(t.uid) { muted.remove(t.uid) } else { muted.insert(t.uid) }
    }

    func toggle(_ t: Team) {
        if let i = follows.firstIndex(where: { $0.uid == t.uid }) { follows.remove(at: i) }
        else { follows.append(t) }
    }

    // MARK: refresh

    /// Four days back, a week ahead, followed leagues only; then the held overlay.
    func refresh() async {
        guard !follows.isEmpty else { games = []; return }
        loading = true
        defer { loading = false }
        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -4, to: now)!
        let to = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let uids = followedUids
        var all: [Game] = []
        var failed: [String] = []
        await withTaskGroup(of: (String, [Game]?).self) { g in
            for l in followedLeagues {
                g.addTask { (l.name, try? await ESPN.scoreboard(l, from: from, to: to)) }
            }
            for await (name, part) in g {
                if let part { all += part.filter { $0.involves(uids) } } else { failed.append(name) }
            }
        }
        all.sort { $0.date < $1.date }
        // ESPN's scoreboard crest is the light-background one; a followed team has the
        // dark-background crest from the teams endpoint, which reads better on the colour cards.
        let dark = Dictionary(follows.compactMap { t in t.logo.map { (t.uid, $0) } }, uniquingKeysWith: { a, _ in a })
        for i in all.indices {
            if let u = dark[all[i].home.uid] { all[i].home.logo = u }
            if let u = dark[all[i].away.uid] { all[i].away.logo = u }
        }
        games = await hold(all)
        lastRefresh = now
        if prefs.liveActivities {
            let loud = Set(follows.map(\.uid)).subtracting(muted)
            Push.autoStart(games.filter { !$0.masked && $0.involves(loud) })
        }
        lastError = failed.isEmpty ? nil : "Couldn't load \(failed.joined(separator: ", "))"
    }

    /// With a delay on, every game that is or just was live is replaced by the relay's copy
    /// from `delay` seconds ago. No copy (relay down, or a game it never saw live) means the
    /// score is masked, if the user asked for that.
    func hold(_ list: [Game]) async -> [Game] {
        guard delay > 0 else { return list }
        // Start times: a game that just ended started hours ago.
        let recent = Date().addingTimeInterval(-8 * 3600)
        let ids = list.filter { $0.state == .live || $0.state == .off || ($0.state == .post && $0.date > recent) }.map(\.id)
        guard !ids.isEmpty else { return list }
        let snaps = (try? await Relay.delayed(ids: ids, delay: delay)) ?? [:]
        return list.map { g in
            guard ids.contains(g.id) else { return g }
            if let s = snaps[g.id] { return g.holding(s) }
            // The relay keeps every game it saw live for 12 hours, so a final it has no copy
            // of is one it never saw: show it. A live game with no copy is the risky one.
            if g.state == .post { return g }
            return prefs.maskWhenUnsure ? g.masking() : g
        }
    }

    /// One game again, for the detail screen's own refresh.
    func reload(_ game: Game) async -> Game? {
        guard let l = League.byId(game.league) else { return nil }
        let day = game.date
        let list = (try? await ESPN.scoreboard(l, from: day.addingTimeInterval(-86400), to: day.addingTimeInterval(86400))) ?? []
        guard let g = list.first(where: { $0.id == game.id }) else { return nil }
        let held = await hold([g]).first
        if let held, let i = games.firstIndex(where: { $0.id == held.id }) { games[i] = held }
        return held
    }

    // MARK: relay registration

    @ObservationIgnored private var pushTask: Task<Void, Never>?

    /// Debounced: a burst of follow toggles is one request.
    func pushSettings() {
        guard let token = deviceToken else { return }
        pushTask?.cancel()
        let reg = Relay.Registration(token: token, env: Relay.env, delay: delay,
                                     follows: follows.map(\.uid).filter { !muted.contains($0) }, prefs: prefs.wire, startToken: startToken)
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await Relay.register(reg)
                relayStatus = "Registered · \(reg.follows.count) teams · \(Self.format(delay)) behind"
            } catch {
                relayStatus = "Relay unreachable: alerts are paused until it answers"
            }
        }
    }

    nonisolated static func format(_ s: Int) -> String {
        if s == 0 { return "live" }
        if s < 60 { return "\(s)s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60)m \(s % 60)s"
    }

    // MARK: persistence

    private func save<T: Encodable>(_ v: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}

/// The feed's buckets, in BrightSports' order.
enum Bucket: String, CaseIterable {
    case live = "Live", today = "Today", tomorrow = "Tomorrow", upcoming = "Upcoming", recent = "Recent"

    static func of(_ g: Game, now: Date = Date(), cal: Calendar = .current) -> Bucket {
        if g.state == .live || g.state == .off { return .live }
        if g.state == .post { return cal.isDate(g.date, inSameDayAs: now) ? .today : .recent }
        if cal.isDate(g.date, inSameDayAs: now) { return .today }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(g.date, inSameDayAs: t) { return .tomorrow }
        return g.date < now ? .recent : .upcoming
    }

    struct Section: Identifiable {
        var id: String { bucket.rawValue }
        let bucket: Bucket
        let games: [Game]
    }

    static func group(_ games: [Game], now: Date = Date()) -> [Section] {
        let d = Dictionary(grouping: games) { of($0, now: now) }
        return allCases.compactMap { b in
            guard var list = d[b], !list.isEmpty else { return nil }
            if b == .recent { list.sort { $0.date > $1.date } }
            return Section(bucket: b, games: list)
        }
    }
}
