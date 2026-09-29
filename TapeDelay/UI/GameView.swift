import SwiftUI

struct GameView: View {
    @Environment(AppModel.self) private var model
    @State var game: Game
    @State private var activityOn = false
    @State private var activityError: String?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 14) {
                    header
                    if !game.home.lines.isEmpty && !game.masked { linescore }
                    if game.state == .live, let s = game.situation { situation(s) }
                    info
                    activityButton
                }
                .padding(16)
            }
        }
        .background(Backdrop(colors: [Color.team(game.away.color), Color.team(game.home.color)]))
        .navigationTitle("\(game.away.abbr) at \(game.home.abbr)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: game.id) {
            activityOn = Push.activityRunning(game.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(game.state == .live ? 15 : 90))
                if let g = await model.reload(game) { withAnimation { game = g } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                team(game.away)
                Spacer()
                VStack(spacing: 4) {
                    if game.masked {
                        Image(systemName: "eye.slash").font(.largeTitle).foregroundStyle(.secondary)
                    } else if game.state == .pre {
                        Text(game.date, format: .dateTime.hour().minute()).font(.title.weight(.bold))
                        Text(game.date, format: .dateTime.weekday(.wide).month().day()).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(game.away.score ?? 0)  –  \(game.home.score ?? 0)")
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    Text(game.detail).font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(game.state == .live ? (game.held ? Theme.held : Theme.live) : .secondary)
                }
                Spacer()
                team(game.home)
            }
            if game.held && game.state == .live {
                Label("Held \(AppModel.format(model.delay)) to match your stream", systemImage: "timer")
                    .font(.caption).foregroundStyle(Theme.held)
            } else if game.masked {
                Text("Hidden: the relay has no held copy of this game right now, so the live score would be ahead of your stream.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func team(_ s: Side) -> some View {
        VStack(spacing: 6) {
            Crest(url: s.logo, abbr: s.abbr, size: 56)
            Text(s.short).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let r = s.record { Text(r).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(width: 96)
    }

    private var linescore: some View {
        let n = max(game.home.lines.count, game.away.lines.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("").frame(width: 44)
                    ForEach(0..<n, id: \.self) { i in Text("\(i + 1)").foregroundStyle(.secondary) }
                    Text(game.kind == .baseball ? "R" : "T").bold()
                }
                ForEach([game.away, game.home], id: \.uid) { s in
                    GridRow {
                        Text(s.abbr).bold().frame(width: 44, alignment: .leading)
                        ForEach(0..<n, id: \.self) { i in Text(i < s.lines.count ? s.lines[i] : "") }
                        Text("\(s.score ?? 0)").bold()
                    }
                }
            }
            .font(.callout.monospacedDigit())
            .padding(16)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func situation(_ s: Situation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if game.kind == .baseball {
                    Bases(on: [s.onFirst, s.onSecond, s.onThird], size: 14)
                    VStack(alignment: .leading) {
                        if let b = s.balls, let st = s.strikes { Text("\(b)-\(st)").font(.title3.bold().monospacedDigit()) }
                        if let o = s.outs { Text("\(o) out").font(.caption).foregroundStyle(.secondary) }
                    }
                } else if let dd = s.downDistance {
                    Image(systemName: "football.fill").foregroundStyle(Theme.accent)
                    Text(dd).font(.headline)
                }
                Spacer()
            }
            if let lp = s.lastPlay {
                Text(lp).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = game.note { Label(note, systemImage: "trophy") }
            if let v = game.venue { Label(v, systemImage: "mappin.and.ellipse") }
            if let tv = game.tv { Label(tv, systemImage: "tv") }
            Label(game.date.formatted(date: .complete, time: .shortened), systemImage: "calendar")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder private var activityButton: some View {
        if game.state != .post {
            VStack(spacing: 6) {
                Button {
                    Task {
                        if activityOn {
                            await Push.endActivity(game.id)
                            activityOn = false
                        } else {
                            do { try Push.startActivity(for: game); activityOn = true; activityError = nil }
                            catch { activityError = error.localizedDescription }
                        }
                    }
                } label: {
                    Label(activityOn ? "Remove from lock screen" : "Follow on lock screen",
                          systemImage: activityOn ? "xmark.circle" : "platter.filled.bottom.iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(activityOn ? .gray : Theme.accent)
                .controlSize(.large)
                if let e = activityError { Text(e).font(.caption).foregroundStyle(.secondary) }
                Text("Updates arrive \(AppModel.format(model.delay)) late, like your alerts.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
