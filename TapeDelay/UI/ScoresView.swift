import SwiftUI

/// Stadium: the scores feed. One hero card for the game that matters most right now, then
/// every other game as a split-colour card. The two teams' colours carry the design; glass is
/// the layer on top (pills, the situation strip, the tab bar).
struct ScoresView: View {
    @Environment(AppModel.self) private var model
    @State private var showDelay = false
    @State private var league: String? = nil
    @Binding var tab: RootView.TabId

    private var shown: [Game] {
        guard let league else { return model.games }
        return model.games.filter { $0.league == league }
    }

    /// Live first, then the next to start, then the latest final.
    private var hero: Game? {
        shown.first { $0.state == .live || $0.state == .off }
            ?? shown.first { $0.state == .pre && $0.date > .now.addingTimeInterval(-3600) }
            ?? shown.last { $0.state == .post }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.follows.isEmpty {
                        empty
                    } else {
                        chips
                        if let h = hero {
                            NavigationLink(value: h) { HeroCard(game: h, delay: model.delay) }.buttonStyle(.plain)
                        }
                        ForEach(Bucket.group(shown.filter { $0.id != hero?.id })) { section in
                            SectionHeader(title: section.bucket.rawValue, count: section.games.count)
                            ForEach(section.games) { g in
                                NavigationLink(value: g) { SplitCard(game: g) }.buttonStyle(.plain)
                            }
                        }
                        if model.games.isEmpty && !model.loading {
                            Text("No games in the next week for your teams.")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 60)
                        }
                        if let e = model.lastError {
                            Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(alignment: .top) { Aurora(colors: auroraColors).ignoresSafeArea() }
            .background(Color.black)
            .navigationTitle("Scores")
            .navigationDestination(for: Game.self) { GameView(game: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDelay = true } label: { DelayRing(delay: model.delay) }
                        .accessibilityLabel(model.delay == 0 ? "Delay: live" : "Delay: \(AppModel.format(model.delay)) behind live")
                }
            }
            .refreshable { await model.refresh() }
            .task(id: model.follows.map(\.uid).joined() + "\(model.delay)") { await loop() }
            .sheet(isPresented: $showDelay) { DelaySheet().presentationDetents([.medium, .large]) }
        }
    }

    private var auroraColors: [Color] {
        if let h = hero { return [Color.team(h.away.color), Color.team(h.home.color)] }
        return model.follows.prefix(2).map { Color.team($0.color) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("My Teams", selected: league == nil) { league = nil }
                    ForEach(model.followedLeagues) { l in
                        chip(l.name, selected: league == l.id) { league = l.id }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .heavy : .semibold))
                .foregroundStyle(selected ? Color.black : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.white.opacity(0.9)).interactive() : .regular.interactive(), in: .capsule)
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
            Image(systemName: "flag.fill").font(.system(size: 56)).foregroundStyle(Theme.flag)
            Text("Scores that wait for your stream").font(.title2.weight(.heavy)).multilineTextAlignment(.center)
            Text("Follow a team, set how far behind live you watch, and every alert shows up when you see the play, not before.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Pick teams") { tab = .teams }
                .buttonStyle(.glassProminent).tint(Theme.flag).foregroundStyle(.black).controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24).padding(.top, 60)
    }
}

// MARK: - pieces

/// The two leading colours, blurred into the top of the screen.
struct Aurora: View {
    var colors: [Color]
    var body: some View {
        ZStack {
            if let a = colors.first {
                Ellipse().fill(a).frame(width: 420, height: 440).blur(radius: 90).offset(x: -150, y: -200).opacity(0.85)
            }
            if colors.count > 1 {
                Ellipse().fill(colors[1]).frame(width: 420, height: 440).blur(radius: 100).offset(x: 150, y: -190).opacity(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 420, alignment: .top)
        .animation(.easeInOut(duration: 0.8), value: colors.map(\.description))
    }
}

struct DelayRing: View {
    var delay: Int
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 3)
            Circle().trim(from: 0, to: min(1, max(0.04, Double(delay) / 120)))
                .stroke(Theme.flag, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(delay == 0 ? "LIVE" : delay >= 60 ? "\(delay / 60)m" : "\(delay)")
                .font(.system(size: delay == 0 ? 9 : 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(delay == 0 ? Theme.live : Theme.flag)
                .contentTransition(.numericText())
        }
        .frame(width: 34, height: 34)
    }
}

/// Away colour on the left, home on the right, blended through a 3×3 mesh so the two meet in
/// a soft, slightly bent seam instead of a straight line. Corners sink toward black for depth.
struct Split: View {
    let away: String, home: String
    var strength: Double = 1

    var body: some View {
        let a = Color.team(away), h = Color.team(home)
        let mid = a.mix(with: h, by: 0.5)
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.5], [0.45, 0.55], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                a.mix(with: .white, by: 0.08), mid.mix(with: a, by: 0.3), h.mix(with: .white, by: 0.06),
                a, mid, h,
                a.mix(with: .black, by: 0.35), mid.mix(with: .black, by: 0.3), h.mix(with: .black, by: 0.35),
            ], smoothsColors: true)
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 280)
        }
        .opacity(strength)
    }
}

struct TeamDisc: View {
    let side: Side
    var size: CGFloat
    var body: some View {
        Crest(url: side.logo, abbr: side.abbr, size: size * 0.72, on: LogoContrast.darken(side.color, by: 0.26))
            .frame(width: size, height: size)
            .background(.black.opacity(0.26), in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
    }
}

struct Pill: View {
    let text: String
    var dot: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(text).font(.caption.weight(.heavy)).monospacedDigit()
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

struct HeroCard: View {
    let game: Game
    let delay: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                statusPill
                Spacer()
                if !game.watch.isEmpty { Pill(text: game.watch.prefix(2).joined(separator: " · ")) }
            }
            .padding([.horizontal, .top], 16)

            HStack(alignment: .center) {
                team(game.away, possession: game.situation?.possession == game.away.teamId)
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    if game.masked {
                        Image(systemName: "eye.slash").font(.system(size: 40, weight: .bold))
                    } else if game.state == .pre {
                        Text(game.date, format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .black)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(game.date, format: .dateTime.weekday(.wide))
                            .font(.subheadline.weight(.bold)).opacity(0.8)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            score(game.away, against: game.home)
                            score(game.home, against: game.away)
                        }
                        .font(.system(size: 62, weight: .black))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        Text(game.detail).font(.subheadline.weight(.heavy)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                team(game.home, possession: game.situation?.possession == game.home.teamId)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)

            if game.state == .live || game.state == .off {
                strip.padding(12)
            } else if let note = game.note ?? game.venue {
                Text(note).font(.footnote.weight(.semibold)).opacity(0.8).padding(.bottom, 18)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background(Split(away: game.away.color, home: game.home.color))
        .clipShape(.rect(cornerRadius: 34))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 14)
        .contentShape(.rect(cornerRadius: 34))
    }

    @ViewBuilder private var statusPill: some View {
        switch game.state {
        case .live where game.held: Pill(text: "HELD \(AppModel.format(delay))", dot: Theme.flag)
        case .live: Pill(text: "LIVE", dot: Theme.live)
        case .off: Pill(text: game.detail.uppercased(), dot: Theme.flag)
        case .post: Pill(text: "FINAL")
        case .pre: Pill(text: game.date.formatted(.dateTime.weekday(.abbreviated).month().day()).uppercased())
        }
    }

    private func team(_ s: Side, possession: Bool) -> some View {
        VStack(spacing: 7) {
            TeamDisc(side: s, size: 76)
            HStack(spacing: 4) {
                Text(s.short).font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                if possession { Circle().fill(Theme.flag).frame(width: 6, height: 6) }
            }
            if let r = s.record { Text(r).font(.caption2.weight(.semibold)).opacity(0.7) }
        }
        .frame(width: 104)
    }

    private func score(_ s: Side, against o: Side) -> some View {
        let trailing = (s.score ?? 0) < (o.score ?? 0)
        return Text("\(s.score ?? 0)").opacity(trailing ? 0.6 : 1)
    }

    /// Situation plus the tape: the game so far, the stretch you haven't seen yet, then live.
    private var strip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(situationText).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if let lp = game.situation?.lastPlay, game.kind != .football {
                    Text(lp).font(.caption).opacity(0.75).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let progress = min(0.97, max(0.05, gameProgress))
                let heldW = delay == 0 ? 0 : max(8, w * 0.08)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85)).frame(width: max(0, w * progress - heldW))
                    Capsule().fill(Theme.flag).frame(width: heldW).offset(x: max(0, w * progress - heldW))
                    Circle().fill(Theme.live).frame(width: 12, height: 12)
                        .shadow(color: Theme.live, radius: 6)
                        .offset(x: w * progress - 6)
                }
            }
            .frame(height: 6)
            HStack {
                Text(game.kind == .baseball ? "FIRST PITCH" : "START")
                Spacer()
                Text(delay == 0 ? "LIVE" : "YOU · \(AppModel.format(delay)) · LIVE")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced)).opacity(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassEffect(.regular.tint(.black.opacity(0.2)), in: .rect(cornerRadius: 22))
    }

    private var situationText: String {
        guard let s = game.situation else { return game.detail }
        switch game.kind {
        case .football: return s.downDistance ?? game.detail
        case .baseball:
            var t = s.outs.map { "\($0) out" } ?? ""
            if let b = s.balls, let st = s.strikes { t += " · \(b)-\(st)" }
            return t.isEmpty ? game.detail : t
        default: return game.detail
        }
    }

    /// Rough share of regulation played, from the period number.
    private var gameProgress: Double {
        let periods: Double = switch game.kind {
        case .baseball: 9
        case .hockey: 3
        case .soccer: 2
        default: 4
        }
        return (Double(max(1, game.period)) - 0.5) / periods
    }
}

struct SplitCard: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            TeamDisc(side: game.away, size: 46)
            if showScores { score(game.away, against: game.home) }
            VStack(spacing: 4) {
                status
                if game.state == .live, game.kind == .baseball, let s = game.situation {
                    Bases(on: [s.onFirst, s.onSecond, s.onThird], size: 7)
                    if let o = s.outs { Text(countLine(outs: o, s)).font(.caption2).monospacedDigit().opacity(0.8) }
                } else if game.state == .live, let dd = game.situation?.downDistance {
                    Text(dd).font(.caption2.weight(.semibold)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.6)
                } else if game.state == .pre, !game.watch.isEmpty {
                    Text(game.watch.prefix(2).joined(separator: " · ")).font(.caption2).opacity(0.75)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            if showScores { score(game.home, against: game.away) }
            TeamDisc(side: game.home, size: 46)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: game.state == .pre ? 84 : 100)
        .background(Split(away: game.away.color, home: game.home.color, strength: game.state == .pre ? 0.55 : 1))
        .clipShape(.rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.1), lineWidth: 1))
        .contentShape(.rect(cornerRadius: 28))
    }

    private var showScores: Bool { game.state != .pre && !game.masked }

    private func countLine(outs: Int, _ s: Situation) -> String {
        if let b = s.balls, let st = s.strikes { return "\(outs) out · \(b)-\(st)" }
        return "\(outs) out"
    }

    private func score(_ s: Side, against o: Side) -> some View {
        let trailing = (s.score ?? 0) < (o.score ?? 0)
        return Text("\(s.score ?? 0)")
            .font(.system(size: 36, weight: .black)).monospacedDigit()
            .opacity(trailing ? 0.55 : 1)
            .contentTransition(.numericText())
    }

    @ViewBuilder private var status: some View {
        switch game.state {
        case .live:
            HStack(spacing: 4) {
                Circle().fill(game.held ? Theme.flag : Theme.live).frame(width: 6, height: 6)
                Text(game.detail).font(.caption.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
        case .off:
            Label(game.detail, systemImage: "pause.fill").font(.caption.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.6)
        case .post:
            if game.masked { Image(systemName: "eye.slash") }
            Text(game.detail.isEmpty ? "Final" : game.detail).font(.caption.weight(.heavy)).opacity(0.85)
        case .pre:
            Text(game.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                .font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Quick delay switcher from the ring; the full controls live in Settings.
struct DelaySheet: View {
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
