import SwiftUI

struct LeagueChips: View {
    let leagues: [League]
    @Binding var selected: String
    /// Leads with a "My Teams" chip that selects `StandingsView.mine`.
    var mine = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if mine { chip(StandingsView.mine, "My Teams", "star.fill") }
                    ForEach(leagues) { l in chip(l.id, l.name, l.kind.symbol) }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }

    private func chip(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { withAnimation(.snappy) { selected = id } } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(selected == id ? .regular.tint(Theme.accent.opacity(0.45)).interactive() : .regular.interactive(),
                     in: .capsule)
    }
}

/// Teams: every club as a tile in its own colours, which drift slowly. Followed teams sit on
/// top with a bell each: a muted team stays in your feed but never notifies.
struct TeamsView: View {
    @Environment(AppModel.self) private var model
    @State private var league = League.all[0].id
    @State private var teams: [String: [Team]] = [:]
    @State private var query = ""
    @State private var failed = false

    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !model.follows.isEmpty && query.isEmpty {
                            SectionHeader(title: "Following", count: model.follows.count)
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(model.follows) { team in TeamTile(team: team, time: t, followed: true) }
                            }
                        }
                        LeagueChips(leagues: League.all, selected: $league).padding(.horizontal, -16)
                        if let list = teams[league] {
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(filtered(list)) { team in TeamTile(team: team, time: t, followed: model.isFollowed(team)) }
                            }
                        } else if failed {
                            Button("Couldn't load teams. Try again") { Task { await load() } }
                                .buttonStyle(.glass).frame(maxWidth: .infinity)
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(40)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.black)
            .searchable(text: $query, prompt: "Search \(League.byId(league)?.name ?? "teams")")
            .navigationTitle("Teams")
            .task(id: league) { await load() }
        }
    }

    private func filtered(_ list: [Team]) -> [Team] {
        guard !query.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.abbr.localizedCaseInsensitiveContains(query) }
    }

    private func load() async {
        guard teams[league] == nil, let l = League.byId(league) else { return }
        failed = false
        do { teams[league] = try await ESPN.teams(l) } catch { failed = true }
    }
}

/// One club. Tap the star to follow; followed tiles get a bell to mute or unmute alerts.
struct TeamTile: View {
    @Environment(AppModel.self) private var model
    let team: Team
    let time: Double
    let followed: Bool

    var body: some View {
        let muted = model.isMuted(team)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Crest(url: team.logo, abbr: team.abbr, size: 36, on: LogoContrast.darken(team.color, by: 0.25))
                    .frame(width: 50, height: 50)
                    .background(.black.opacity(0.25), in: .circle)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                Spacer()
                VStack(spacing: 6) {
                    iconButton(followed ? "star.fill" : "star", label: followed ? "Unfollow \(team.name)" : "Follow \(team.name)",
                               tint: followed ? Theme.flag : .white) { withAnimation(.snappy) { model.toggle(team) } }
                    if followed {
                        iconButton(muted ? "bell.slash.fill" : "bell.fill",
                                   label: muted ? "Unmute \(team.name)" : "Mute \(team.name)",
                                   tint: muted ? .white.opacity(0.6) : .white) { withAnimation(.snappy) { model.toggleMute(team) } }
                    }
                }
            }
            Spacer(minLength: 10)
            Text(team.short.isEmpty ? team.name : team.short)
                .font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
            HStack {
                Text(League.byId(team.league)?.name ?? "").font(.caption2.weight(.semibold))
                if followed && muted { Text("· muted").font(.caption2.weight(.semibold)) }
            }
            .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(height: 132)
        .background { Drift(a: team.color, b: team.alt ?? team.color, time: time, seed: team.uid.hashValue) }
        .clipShape(.rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(followed ? 0.35 : 0.1), lineWidth: followed ? 1.5 : 1))
        .opacity(followed && muted ? 0.7 : 1)
    }

    private func iconButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// A team's two colours in a 3×3 mesh whose inner points wander on slow sine paths, each
/// team on its own phase so a grid of them never moves in lockstep.
struct Drift: View {
    let a: String, b: String
    let time: Double
    let seed: Int

    var body: some View {
        let c1 = Color.team(a)
        let c2 = b.lowercased() == a.lowercased() || b.lowercased() == "ffffff" || b.lowercased() == "000000"
            ? c1.mix(with: .white, by: 0.3) : Color.team(b)
        let p = Double(abs(seed % 1000)) / 1000 * .pi * 2
        let s = Float(sin(time * 0.35 + p)), c = Float(cos(time * 0.27 + p * 1.3))
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5 + 0.2 * s, 0], [1, 0],
            [0, 0.5 + 0.2 * c], [0.5 + 0.18 * c, 0.5 + 0.18 * s], [1, 0.5 - 0.2 * s],
            [0, 1], [0.5 - 0.2 * c, 1], [1, 1],
        ], colors: [
            c1, c1.mix(with: c2, by: 0.4), c2.mix(with: .black, by: 0.2),
            c1.mix(with: .black, by: 0.15), c2, c1.mix(with: c2, by: 0.6),
            c1.mix(with: .black, by: 0.45), c2.mix(with: .black, by: 0.35), c1.mix(with: .black, by: 0.5),
        ], smoothsColors: true)
    }
}

/// Standings for any league, or "My Teams": the groups holding your teams from every league
/// you follow, stacked, so the NBA and NHL are one scroll from the NFL.
struct StandingsView: View {
    static let mine = "mine"

    @Environment(AppModel.self) private var model
    @State private var league = StandingsView.mine
    @State private var groups: [String: [StandingsGroup]] = [:]
    @State private var failed = false

    /// Every league, the ones you follow first.
    private var leagues: [League] {
        let mine = model.followedLeagues
        return mine + League.all.filter { l in !mine.contains(l) }
    }

    private var selectedName: String { league == Self.mine ? "My Teams" : League.byId(league)?.name ?? "League" }
    private var selectedSymbol: String { league == Self.mine ? "star.fill" : League.byId(league)?.kind.symbol ?? "list.number" }

    /// The leagues the selected chip covers.
    private var shown: [League] {
        league == Self.mine ? model.followedLeagues : League.byId(league).map { [$0] } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // In the content, as on Teams: pinned as a top inset they were lost under the
                    // iPhone Duo's side bars, which left the tab stuck on the first league.
                    LeagueChips(leagues: leagues, selected: $league, mine: !model.followedLeagues.isEmpty)
                        .scrollClipDisabled()
                        .padding(.horizontal, -16)
                    GlassEffectContainer(spacing: 12) {
                        LazyVStack(spacing: 12) { tables }
                    }
                }
                .padding(16)
            }
            .background(Backdrop(colors: model.follows.map { Color.team($0.color) }))
            .navigationTitle("Standings")
            // Also a menu in the nav bar: on the folded Duo the chip row got clipped under the
            // top bar, and this button stays put however the screen is laid out.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("League", selection: $league) {
                            if !model.followedLeagues.isEmpty { Label("My Teams", systemImage: "star.fill").tag(Self.mine) }
                            ForEach(leagues) { l in Label(l.name, systemImage: l.kind.symbol).tag(l.id) }
                        }
                    } label: {
                        Label(selectedName, systemImage: selectedSymbol).labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("League: \(selectedName)")
                }
            }
            .onAppear {
                if league == Self.mine ? model.followedLeagues.isEmpty : League.byId(league) == nil { league = leagues[0].id }
            }
            .task(id: league) { await load() }
            .refreshable {
                for l in shown { groups[l.id] = nil }
                await load()
            }
        }
    }

    @ViewBuilder private var tables: some View {
        if league == Self.mine {
            ForEach(model.followedLeagues) { l in
                if let gs = groups[l.id] {
                    let yours = gs.filter { g in g.rows.contains { model.followedUids.contains($0.uid) } }
                    ForEach(yours.isEmpty ? gs : yours) { g in table(g, league: l) }
                }
            }
        } else if let gs = groups[league] {
            ForEach(gs) { g in table(g) }
        }
        if shown.contains(where: { groups[$0.id] == nil }) {
            if failed {
                Text("Couldn't load standings.").foregroundStyle(.secondary).padding(.top, 40)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
    }

    /// `league` labels the table when leagues are mixed ("NBA · Eastern Conference").
    private func table(_ g: StandingsGroup, league: League? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let league {
                Label(g.name.isEmpty ? league.name : "\(league.name) · \(g.name)", systemImage: league.kind.symbol)
                    .font(.headline).padding(.bottom, 4)
            } else {
                Text(g.name).font(.headline).padding(.bottom, 4)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    Text("").gridCellColumns(2)
                    ForEach(g.columns, id: \.self) { Text($0).font(.caption2.weight(.bold)).foregroundStyle(.secondary).gridColumnAlignment(.trailing) }
                }
                ForEach(g.rows) { r in
                    let mine = model.followedUids.contains(r.uid)
                    GridRow {
                        Crest(url: r.logo, abbr: r.abbr, size: 20, on: "1c1c1e")
                        Text(r.abbr).font(.callout.weight(mine ? .heavy : .medium))
                            .foregroundStyle(mine ? Theme.accent : .primary)
                        ForEach(Array(r.values.enumerated()), id: \.offset) { _, v in
                            Text(v).font(.callout.monospacedDigit()).gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    /// Every league the chip covers that isn't loaded yet, side by side.
    private func load() async {
        failed = false
        await withTaskGroup(of: (String, [StandingsGroup]?).self) { tg in
            for l in shown where groups[l.id] == nil {
                tg.addTask { (l.id, try? await ESPN.standings(l)) }
            }
            for await (id, gs) in tg {
                if let gs { groups[id] = gs } else { failed = true }
            }
        }
    }
}
