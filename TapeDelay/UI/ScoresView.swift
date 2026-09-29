import SwiftUI

struct ScoresView: View {
    @Environment(AppModel.self) private var model
    @State private var showDelay = false
    @Binding var tab: RootView.TabId

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.follows.isEmpty {
                    empty
                } else {
                    GlassEffectContainer(spacing: 10) {
                        LazyVStack(spacing: 10) {
                            ForEach(Bucket.group(model.games)) { section in
                                SectionHeader(title: section.bucket.rawValue, count: section.games.count)
                                ForEach(section.games) { g in
                                    NavigationLink(value: g) { GameCard(game: g) }
                                        .buttonStyle(.plain)
                                }
                            }
                            if model.games.isEmpty && !model.loading {
                                Text("No games in the next week for your teams.")
                                    .foregroundStyle(.secondary).padding(.top, 60)
                            }
                            if let e = model.lastError {
                                Label(e, systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Backdrop(colors: model.follows.map { Color.team($0.color) }))
            .navigationTitle("Scores")
            .navigationDestination(for: Game.self) { GameView(game: $0) }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack { Spacer(); DelayPill { showDelay = true }; Spacer() }.padding(.bottom, 6)
            }
            .refreshable { await model.refresh() }
            .task(id: model.follows.map(\.uid).joined() + "\(model.delay)") { await loop() }
            .sheet(isPresented: $showDelay) { DelaySheet().presentationDetents([.medium, .large]) }
        }
    }

    /// 20s while something's live (the held copy moves as the stream does), 2 min otherwise.
    private func loop() async {
        while !Task.isCancelled {
            await model.refresh()
            let live = model.games.contains { $0.state == .live || $0.state == .off }
            try? await Task.sleep(for: .seconds(live ? 20 : 120))
        }
    }

    private var empty: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.accent)
            Text("Scores that wait for your stream").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("Follow a team, set how far behind live you watch, and every alert shows up when you see the play, not before.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Pick teams") { tab = .teams }
                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
        }
        .padding(32).padding(.top, 60)
    }
}

struct GameCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                status
                Spacer()
                if let note = game.note, !note.isEmpty {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else if let tv = game.tv, game.state == .pre {
                    Text(tv).font(.caption2).foregroundStyle(.secondary)
                }
            }
            row(game.away, other: game.home, possession: game.situation?.possession == game.away.teamId)
            row(game.home, other: game.away, possession: game.situation?.possession == game.home.teamId)
            if game.state == .live, let s = game.situation, let extra = situationLine(s) {
                HStack(spacing: 8) {
                    if game.kind == .baseball { Bases(on: [s.onFirst, s.onSecond, s.onThird], size: 7) }
                    Text(extra).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
    }

    private var tint: Color {
        switch game.state {
        case .live: return Theme.live.opacity(0.10)
        case .off: return Theme.held.opacity(0.10)
        default: return .clear
        }
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(game.held ? Theme.held : Theme.live).frame(width: 7, height: 7)
                Text(game.detail).font(.caption.weight(.semibold).monospacedDigit())
                if game.held { Text("HELD").font(.caption2.weight(.heavy)).foregroundStyle(Theme.held) }
            }
        case .off:
            Label(game.detail, systemImage: "pause.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.held)
        case .post:
            Text(game.detail.isEmpty ? "Final" : game.detail)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .pre:
            Text(game.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func row(_ s: Side, other: Side, possession: Bool) -> some View {
        let lost = game.state == .post && !game.masked && (s.score ?? 0) < (other.score ?? 0)
        return HStack(spacing: 10) {
            Crest(url: s.logo, abbr: s.abbr, size: 26)
            Text(s.short).font(.body.weight(.medium)).lineLimit(1)
            if possession { Image(systemName: game.kind.symbol).font(.caption2).foregroundStyle(Theme.accent) }
            if let r = s.record, game.state == .pre { Text(r).font(.caption).foregroundStyle(.tertiary) }
            Spacer()
            if game.masked {
                Image(systemName: "eye.slash").foregroundStyle(.tertiary)
            } else if let sc = s.score, game.state != .pre {
                Text("\(sc)").font(.title3.weight(.bold).monospacedDigit()).contentTransition(.numericText())
            }
        }
        .opacity(lost ? 0.5 : 1)
    }

    private func situationLine(_ s: Situation) -> String? {
        switch game.kind {
        case .baseball:
            guard let o = s.outs else { return nil }
            var t = "\(o) out"
            if let b = s.balls, let st = s.strikes { t += " · \(b)-\(st)" }
            return t
        case .football: return s.downDistance
        default: return nil
        }
    }
}

/// Quick delay switcher from the pill; the full controls live in Settings.
struct DelaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DelayControls()
                .navigationTitle("How far behind?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
    }
}
