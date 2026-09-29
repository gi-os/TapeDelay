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
                        Text(game.date, format: .dateTime.weekday(.wide).month().day()).font(.subheadline.weight(.bold)).opacity(0.8)
                    } else {
                        HStack(spacing: 16) {
                            Text("\(game.away.score ?? 0)").opacity((game.away.score ?? 0) < (game.home.score ?? 0) ? 0.6 : 1)
                            Text("\(game.home.score ?? 0)").opacity((game.home.score ?? 0) < (game.away.score ?? 0) ? 0.6 : 1)
                        }
                        .font(.system(size: 68, weight: .black)).monospacedDigit()
                        .contentTransition(.numericText())
                    }
                    if game.state != .pre {
                        Text(game.detail).font(.subheadline.weight(.heavy)).monospacedDigit()
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

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = game.note { Label(note, systemImage: "trophy.fill") }
            if let v = game.venue { Label(v, systemImage: "mappin.and.ellipse") }
            if let tv = game.tv { Label(tv, systemImage: "tv") }
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
