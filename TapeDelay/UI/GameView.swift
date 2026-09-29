import SwiftUI

/// Stadium: the game. The teams' split colours fill the top of the screen behind a big score;
/// everything below is glass panels over black.
struct GameView: View {
    @Environment(AppModel.self) private var model
    @State var game: Game
    @State private var activityOn = false
    @State private var activityError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if game.state == .live, let s = game.situation { situation(s) }
                        if !game.home.lines.isEmpty && !game.masked { linescore }
                        probables
                        watchPanel
                        info
                    }
                }
                activityButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(alignment: .top) {
            ZStack(alignment: .bottom) {
                Split(away: game.away.color, home: game.home.color)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 200)
            }
            .frame(height: 470)
            .ignoresSafeArea()
        }
        .background(Color.black)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if game.held && game.state == .live {
                    Pill(text: "HELD \(AppModel.format(model.delay))", dot: Theme.flag)
                } else if game.state == .live {
                    Pill(text: "LIVE", dot: Theme.live)
                }
            }
        }
        .task(id: game.id) {
            activityOn = Push.activityRunning(game.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(game.state == .live ? 15 : 90))
                if let g = await model.reload(game) { withAnimation { game = g } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                team(game.away)
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    if game.masked {
                        Image(systemName: "eye.slash").font(.system(size: 44, weight: .bold))
                    } else if game.state == .pre {
                        Text(game.date, format: .dateTime.hour().minute()).font(.system(size: 38, weight: .black))
                            .lineLimit(1).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
                        Text(game.date, format: .dateTime.weekday(.wide).month().day()).font(.subheadline.weight(.bold)).opacity(0.8)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        HStack(spacing: 16) {
                            Text("\(game.away.score ?? 0)").opacity((game.away.score ?? 0) < (game.home.score ?? 0) ? 0.6 : 1)
                            Text("\(game.home.score ?? 0)").opacity((game.home.score ?? 0) < (game.away.score ?? 0) ? 0.6 : 1)
                        }
                        .font(.system(size: 68, weight: .black)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    }
                    if game.state != .pre {
                        Text(game.detail).font(.subheadline.weight(.heavy)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                team(game.home)
            }
            if game.masked {
                Text("Hidden: the relay has no held copy of this game right now, so the live score would be ahead of your stream.")
                    .font(.caption).multilineTextAlignment(.center).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 24).padding(.bottom, 20)
    }

    private func team(_ s: Side) -> some View {
        VStack(spacing: 8) {
            TeamDisc(side: s, size: 86)
            Text(s.short).font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
            if let r = s.record { Text(r).font(.caption.weight(.semibold)).opacity(0.7) }
        }
        .frame(width: 110)
    }

    private var linescore: some View {
        let n = max(game.home.lines.count, game.away.lines.count)
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("").frame(width: 44)
                    ForEach(0..<n, id: \.self) { i in Text("\(i + 1)").foregroundStyle(.secondary) }
                    Text(game.kind == .baseball ? "R" : "T").fontWeight(.black)
                }
                ForEach([game.away, game.home], id: \.uid) { s in
                    GridRow {
                        Text(s.abbr).fontWeight(.heavy).frame(width: 44, alignment: .leading)
                        ForEach(0..<n, id: \.self) { i in Text(i < s.lines.count ? s.lines[i] : "") }
                        Text("\(s.score ?? 0)").fontWeight(.black)
                    }
                }
            }
            .font(.callout.monospacedDigit())
            .padding(16)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func situation(_ s: Situation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if game.kind == .baseball {
                    Bases(on: [s.onFirst, s.onSecond, s.onThird], size: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        if let b = s.balls, let st = s.strikes { Text("\(b)-\(st)").font(.title2.weight(.black).monospacedDigit()) }
                        if let o = s.outs { Text("\(o) out").font(.subheadline).foregroundStyle(.secondary) }
                    }
                } else if let dd = s.downDistance {
                    Text(dd).font(.title3.weight(.black))
                    Spacer()
                    if let p = s.possession {
                        let side = p == game.home.teamId ? game.home : game.away
                        Text("\(side.abbr) ball").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let lp = s.lastPlay { Text(lp).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    /// Where to watch: every channel and stream ESPN lists, national first.
    @ViewBuilder private var watchPanel: some View {
        if !game.watch.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Where to watch", systemImage: "tv").font(.headline)
                FlowChips(items: game.watch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    /// Starting pitchers or goalies, before the game.
    @ViewBuilder private var probables: some View {
        if game.state == .pre, game.home.probable != nil || game.away.probable != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(game.kind == .baseball ? "Probable pitchers" : "Probable goalies").font(.headline)
                ForEach([game.away, game.home], id: \.uid) { s in
                    HStack {
                        Text(s.abbr).fontWeight(.heavy).frame(width: 48, alignment: .leading)
                        Text(s.probable ?? "TBD").lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        if let l = s.probableLine { Text(l).monospacedDigit().foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = game.note { Label(note, systemImage: "trophy.fill") }
            if let v = game.venue { Label(v, systemImage: "mappin.and.ellipse") }
            Label(game.date.formatted(date: .complete, time: .shortened), systemImage: "calendar")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    @ViewBuilder private var activityButton: some View {
        if game.state != .post {
            VStack(spacing: 8) {
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
                    Label(activityOn ? "Remove from lock screen" : "Put on lock screen",
                          systemImage: activityOn ? "xmark.circle.fill" : "platter.filled.bottom.iphone")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(activityOn ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(activityOn ? Color.gray : Theme.flag)
                .controlSize(.extraLarge)
                if let e = activityError { Text(e).font(.caption).foregroundStyle(.secondary) }
                Text(model.delay == 0 ? "Updates arrive live." : "Updates arrive \(AppModel.format(model.delay)) late, like your alerts.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }
}

/// Channel names as wrapping glass chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { n in
                Text(n).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

/// Left-to-right, wrapping to a new line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, w), height: y + row)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX && x + s.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}
