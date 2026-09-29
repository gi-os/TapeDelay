import SwiftUI

struct LeagueChips: View {
    let leagues: [League]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(leagues) { l in
                        Button { withAnimation(.snappy) { selected = l.id } } label: {
                            Label(l.name, systemImage: l.kind.symbol)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected == l.id ? .regular.tint(Theme.accent.opacity(0.45)).interactive() : .regular.interactive(),
                                     in: .capsule)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
    }
}

struct TeamsView: View {
    @Environment(AppModel.self) private var model
    @State private var league = League.all[0].id
    @State private var teams: [String: [Team]] = [:]
    @State private var query = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if !model.follows.isEmpty && query.isEmpty {
                    Section("Following") {
                        ForEach(model.follows) { t in row(t) }
                            .onDelete { model.follows.remove(atOffsets: $0) }
                    }
                }
                Section(League.byId(league)?.name ?? "") {
                    if let list = teams[league] {
                        ForEach(filtered(list)) { t in row(t) }
                    } else if failed {
                        Button("Couldn't load teams. Try again") { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Backdrop(colors: model.follows.map { Color.team($0.color) }))
            .safeAreaInset(edge: .top, spacing: 0) { LeagueChips(leagues: League.all, selected: $league) }
            .searchable(text: $query, prompt: "Search teams")
            .navigationTitle("Teams")
            .task(id: league) { await load() }
        }
    }

    private func filtered(_ list: [Team]) -> [Team] {
        guard !query.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.abbr.localizedCaseInsensitiveContains(query) }
    }

    private func row(_ t: Team) -> some View {
        Button { withAnimation { model.toggle(t) } } label: {
            HStack(spacing: 12) {
                Crest(url: t.logo, abbr: t.abbr, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).foregroundStyle(.primary)
                    Text(League.byId(t.league)?.name ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: model.isFollowed(t) ? "star.fill" : "star")
                    .foregroundStyle(model.isFollowed(t) ? Theme.accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func load() async {
        guard teams[league] == nil, let l = League.byId(league) else { return }
        failed = false
        do { teams[league] = try await ESPN.teams(l) } catch { failed = true }
    }
}

struct StandingsView: View {
    @Environment(AppModel.self) private var model
    @State private var league = ""
    @State private var groups: [String: [StandingsGroup]] = [:]
    @State private var failed = false

    private var leagues: [League] { model.followedLeagues.isEmpty ? League.all : model.followedLeagues }

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 12) {
                    LazyVStack(spacing: 12) {
                        if let gs = groups[league] {
                            ForEach(gs) { g in table(g) }
                        } else if failed {
                            Text("Couldn't load standings.").foregroundStyle(.secondary).padding(.top, 40)
                        } else {
                            ProgressView().padding(.top, 60)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Backdrop(colors: model.follows.map { Color.team($0.color) }))
            .safeAreaInset(edge: .top, spacing: 0) { LeagueChips(leagues: leagues, selected: $league) }
            .navigationTitle("Standings")
            .onAppear { if league.isEmpty || !leagues.contains(where: { $0.id == league }) { league = leagues[0].id } }
            .task(id: league) { await load() }
            .refreshable { groups[league] = nil; await load() }
        }
    }

    private func table(_ g: StandingsGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(g.name).font(.headline).padding(.bottom, 4)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                GridRow {
                    Text("").gridCellColumns(2)
                    ForEach(g.columns, id: \.self) { Text($0).font(.caption2.weight(.bold)).foregroundStyle(.secondary).gridColumnAlignment(.trailing) }
                }
                ForEach(g.rows) { r in
                    let mine = model.followedUids.contains(r.uid)
                    GridRow {
                        Crest(url: r.logo, abbr: r.abbr, size: 20)
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

    private func load() async {
        guard !league.isEmpty, groups[league] == nil, let l = League.byId(league) else { return }
        failed = false
        do { groups[league] = try await ESPN.standings(l) } catch { failed = true }
    }
}
