import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TapeDelayWidgets: WidgetBundle {
    var body: some Widget { GameLiveActivity() }
}

/// The scorebug. One per sport, built from the broadcast conventions of each: football's two
/// colour halves, baseball's box, basketball's bar, hockey's stacked rows, soccer's slim bar.
/// Every update is pushed by the relay, already held by the device's delay; nothing here fetches.
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameAttributes.self) { ctx in
            Scorebug(a: ctx.attributes, s: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let a = ctx.attributes, s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { IslandSide(a: a, s: s, home: false) }
                DynamicIslandExpandedRegion(.trailing) { IslandSide(a: a, s: s, home: true) }
                DynamicIslandExpandedRegion(.center) { IslandCenter(a: a, s: s) }
                DynamicIslandExpandedRegion(.bottom) { IslandBottom(a: a, s: s) }
            } compactLeading: {
                if a.sport == "baseball" {
                    MiniDiamond(bases: s.bases ?? [false, false, false], size: 5)
                } else {
                    HStack(spacing: 4) {
                        LogoMark(uid: a.awayUid, abbr: a.awayAbbr, size: 18)
                        Text("\(s.away)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    }
                }
            } compactTrailing: {
                if a.sport == "baseball" {
                    Text("\(s.away)-\(s.home)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                } else {
                    HStack(spacing: 4) {
                        Text("\(s.home)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                        LogoMark(uid: a.homeUid, abbr: a.homeAbbr, size: 18)
                    }
                }
            } minimal: {
                Text("\(s.away)-\(s.home)").font(.system(size: 10, weight: .heavy)).monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .keylineTint(Color(hex: a.homeColor))
        }
    }
}

// MARK: - shared bits

private let flagYellow = Color(red: 1, green: 0.776, blue: 0.125)

private func teamGradient(_ hex: String, reversed: Bool = false) -> LinearGradient {
    let c = Color(hex: hex)
    let colors = [c.mix(with: .black, by: 0.25), c.mix(with: .white, by: 0.08)]
    return LinearGradient(colors: reversed ? colors.reversed() : colors, startPoint: .leading, endPoint: .trailing)
}

private struct Pips: View {
    let filled: Int, total: Int
    var w: CGFloat = 12, h: CGFloat = 3
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i < filled ? Color.white : Color.white.opacity(0.25))
                    .frame(width: w, height: h)
            }
        }
    }
}

private struct HeldTag: View {
    var body: some View {
        Image(systemName: "timer").font(.system(size: 10, weight: .bold)).foregroundStyle(flagYellow)
    }
}

private struct FootLine: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty {
            HStack(spacing: 8) {
                Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                Spacer(minLength: 0)
                HeldTag()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
    }
}

struct MiniDiamond: View {
    let bases: [Bool]
    var size: CGFloat = 9
    var body: some View {
        let b = bases + Array(repeating: false, count: max(0, 3 - bases.count))
        ZStack {
            base(b[1]).offset(y: -size * 0.72)
            base(b[2]).offset(x: -size * 0.72)
            base(b[0]).offset(x: size * 0.72)
        }
        .frame(width: size * 2.6, height: size * 2.3)
    }
    private func base(_ on: Bool) -> some View {
        Rectangle().fill(on ? Color.white : Color.clear)
            .overlay(Rectangle().stroke(.white, lineWidth: 1.4))
            .frame(width: size, height: size).rotationEffect(.degrees(45))
    }
}

private struct Outs: View {
    let n: Int
    var d: CGFloat = 9
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { i in
                Circle().fill(i < n ? Color.white : .clear).overlay(Circle().stroke(.white, lineWidth: 1.5)).frame(width: d, height: d)
            }
        }
    }
}

// MARK: - the scorebug

struct Scorebug: View {
    let a: GameAttributes
    let s: GameAttributes.ContentState

    var body: some View {
        switch a.sport {
        case "football": FootballBug(a: a, s: s)
        case "baseball": BaseballBug(a: a, s: s)
        case "basketball": BasketballBug(a: a, s: s)
        case "hockey": HockeyBug(a: a, s: s)
        default: SoccerBug(a: a, s: s)
        }
    }
}

/// Two colour halves with the logos at the outer edges, the score in the middle, one line of
/// quarter, clock and down-and-distance, timeout dashes along the bottom.
struct FootballBug: View {
    let a: GameAttributes, s: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    half(a.awayUid, a.awayAbbr, a.awayColor, a.awayRecord, s.awayTimeouts, home: false)
                    half(a.homeUid, a.homeAbbr, a.homeColor, a.homeRecord, s.homeTimeouts, home: true)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 170)
                VStack(spacing: 2) {
                    HStack(spacing: 24) {
                        Text("\(s.away)").opacity(s.away < s.home ? 0.7 : 1)
                        Text("\(s.home)").opacity(s.home < s.away ? 0.7 : 1)
                    }
                    .font(.system(size: 36, weight: .black).italic()).monospacedDigit()
                    .contentTransition(.numericText())
                    HStack(spacing: 10) {
                        Text(s.isFinal ? "FINAL" : s.detail.uppercased()).lineLimit(1)
                        if s.isLive, let d = s.down { Text(d.uppercased()).foregroundStyle(flagYellow).lineLimit(1) }
                    }
                    .font(.system(size: 12, weight: .heavy).italic())
                }
            }
            .frame(height: 80)
            if s.isLive, s.spot != nil || s.redZone == true {
                HStack(spacing: 8) {
                    if let spot = s.spot { Text("Ball on \(spot)").font(.system(size: 12, weight: .bold)) }
                    Spacer(minLength: 0)
                    if s.redZone == true {
                        Text("RED ZONE").font(.system(size: 10, weight: .black)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(red: 0.78, green: 0.06, blue: 0.18), in: .rect(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
            }
            FootLine(text: s.lastPlay)
        }
        .foregroundStyle(.white)
    }

    private func half(_ uid: String?, _ abbr: String, _ color: String, _ rec: String?, _ to: Int?, home: Bool) -> some View {
        ZStack(alignment: home ? .trailing : .leading) {
            teamGradient(color, reversed: home)
            LogoMark(uid: uid, abbr: abbr, size: 64)
                .offset(x: home ? 8 : -8)
                .opacity(0.95)
            VStack(alignment: home ? .trailing : .leading) {
                if let rec, !rec.isEmpty { Text(rec).font(.system(size: 9, weight: .heavy)).opacity(0.85) }
                Spacer()
                if let to { Pips(filled: to, total: 3, w: 14, h: 3) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: home ? .trailing : .leading)
            if s.possession == (home ? "home" : "away") {
                Image(systemName: home ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: 9)).foregroundStyle(flagYellow)
                    .frame(maxWidth: .infinity, alignment: home ? .leading : .trailing)
                    .padding(.horizontal, 58)
            }
        }
        .clipped()
    }
}

/// The box: logo tiles with their scores, then the diamond, outs, inning and count, then
/// pitcher and batter, all in one short card.
struct BaseballBug: View {
    let a: GameAttributes, s: GameAttributes.ContentState
    private let navy = Color(red: 0.106, green: 0.184, blue: 0.369)
    private let rule = Color(red: 0.79, green: 0.82, blue: 0.87)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    row(a.awayUid, a.awayAbbr, a.awayColor, s.away)
                    row(a.homeUid, a.homeAbbr, a.homeColor, s.home)
                }
                .background(rule)
                Rectangle().fill(rule).frame(width: 2)
                HStack(spacing: 12) {
                    if s.isLive {
                        VStack(spacing: 5) {
                            MiniDiamond(bases: s.bases ?? [false, false, false], size: 11)
                            Outs(n: s.outs ?? 0)
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(inning).font(.system(size: 15, weight: .heavy)).monospacedDigit()
                            if let b = s.balls, let st = s.strikes {
                                Text("\(b)-\(st)").font(.system(size: 16, weight: .heavy)).monospacedDigit()
                            }
                        }
                    } else {
                        Text(s.isFinal ? "FINAL" : s.detail.uppercased()).font(.system(size: 14, weight: .heavy))
                    }
                    Spacer(minLength: 0)
                    if s.isLive {
                        VStack(alignment: .leading, spacing: 3) {
                            person("P", s.pitcher, s.pitcherLine)
                            person("AB", s.batter, s.batterLine)
                        }
                        .frame(maxWidth: 130, alignment: .leading)
                    } else if let ah = s.awayHits, let hh = s.homeHits {
                        Text("H \(ah)-\(hh)").font(.system(size: 12, weight: .bold)).opacity(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(navy)
            }
            .frame(height: 66)
            if s.isLive { FootLine(text: s.lastPlay) }
        }
        .foregroundStyle(.white)
    }

    private var inning: String {
        let d = s.detail.lowercased()
        let arrow = d.hasPrefix("bot") || d.hasPrefix("end") ? "▼" : "▲"
        return "\(arrow)\(s.period)"
    }

    private func row(_ uid: String?, _ abbr: String, _ color: String, _ score: Int) -> some View {
        HStack(spacing: 2) {
            LogoMark(uid: uid, abbr: abbr, size: 24)
                .frame(width: 44, height: 32)
                .background(Color(hex: color))
            Text("\(score)").font(.system(size: 20, weight: .heavy)).monospacedDigit()
                .frame(width: 34, height: 32).background(navy)
                .contentTransition(.numericText())
        }
    }

    private func person(_ tag: String, _ name: String?, _ line: String?) -> some View {
        HStack(spacing: 5) {
            Text(tag).opacity(0.6)
            Text((name ?? "—").uppercased()).lineLimit(1)
            Spacer(minLength: 0)
            if let line { Text(line).opacity(0.8).lineLimit(1) }
        }
        .font(.system(size: 10.5, weight: .heavy))
    }
}

/// The bar: each half holds the logo, abbreviation, score and timeouts; the clock sits between.
struct BasketballBug: View {
    let a: GameAttributes, s: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                half(a.awayUid, a.awayAbbr, a.awayColor, s.away, s.awayTimeouts, home: false)
                VStack(spacing: 1) {
                    Text(periodLabel).font(.system(size: 10, weight: .heavy)).opacity(0.7)
                    Text(s.isFinal ? "FINAL" : (s.clock ?? s.detail)).font(.system(size: 14, weight: .black)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: 62).frame(maxHeight: .infinity).background(Color(white: 0.06))
                half(a.homeUid, a.homeAbbr, a.homeColor, s.home, s.homeTimeouts, home: true)
            }
            .frame(height: 62)
            FootLine(text: s.lastPlay)
        }
        .foregroundStyle(.white)
    }

    private var periodLabel: String { s.isFinal ? "" : s.period > 4 ? "OT" : "Q\(max(1, s.period))" }

    private func half(_ uid: String?, _ abbr: String, _ color: String, _ score: Int, _ to: Int?, home: Bool) -> some View {
        let leading = s.possession == (home ? "home" : "away")
        let items = HStack(spacing: 6) {
            LogoMark(uid: uid, abbr: abbr, size: 30)
            VStack(alignment: home ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(abbr).font(.system(size: 13, weight: .black))
                    if leading { Circle().fill(flagYellow).frame(width: 5, height: 5) }
                }
                if let to { Pips(filled: to, total: 7, w: 4, h: 3) }
            }
            Spacer(minLength: 0)
            Text("\(score)").font(.system(size: 26, weight: .black)).monospacedDigit().contentTransition(.numericText())
        }
        return items
            .environment(\.layoutDirection, home ? .rightToLeft : .leftToRight)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(teamGradient(color, reversed: home))
    }
}

/// Stacked rows (logo, name, score) with the period and clock at the side.
struct HockeyBug: View {
    let a: GameAttributes, s: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 1) {
                    row(a.awayUid, a.awayAbbr, a.awayName, a.awayColor, s.away)
                    row(a.homeUid, a.homeAbbr, a.homeName, a.homeColor, s.home)
                }
                .background(Color.white.opacity(0.08))
                VStack(spacing: 1) {
                    Text(s.isFinal ? "FINAL" : periodLabel).font(.system(size: 11, weight: .heavy)).opacity(0.75)
                    if !s.isFinal {
                        Text(s.clock ?? "").font(.system(size: 18, weight: .black)).monospacedDigit()
                    }
                }
                .frame(width: 72).frame(maxHeight: .infinity).background(Color(white: 0.06))
            }
            .frame(height: 70)
            FootLine(text: s.lastPlay)
        }
        .foregroundStyle(.white)
    }

    private var periodLabel: String {
        switch s.period { case 1: "1ST"; case 2: "2ND"; case 3: "3RD"; case 0: s.detail.uppercased(); default: "OT" }
    }

    private func row(_ uid: String?, _ abbr: String, _ name: String, _ color: String, _ score: Int) -> some View {
        HStack(spacing: 10) {
            LogoMark(uid: uid, abbr: abbr, size: 26)
                .frame(width: 50, height: 34)
                .background(Color(hex: color))
            Text(name).font(.system(size: 13, weight: .bold)).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(score)").font(.system(size: 22, weight: .black)).monospacedDigit()
                .padding(.trailing, 12).contentTransition(.numericText())
        }
        .frame(height: 34)
    }
}

/// The slim bar: a running minute in a black block, colour strips at each end, the score.
struct SoccerBug: View {
    let a: GameAttributes, s: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(minute).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 10).frame(maxHeight: .infinity).background(.black)
                Rectangle().fill(Color(hex: a.awayColor)).frame(width: 10)
                HStack(spacing: 0) {
                    side(a.awayUid, a.awayAbbr, s.away, home: false)
                    Rectangle().fill(Color.black.opacity(0.8)).frame(width: 1.5).padding(.vertical, 8)
                    side(a.homeUid, a.homeAbbr, s.home, home: true)
                }
                .background(Color(white: 0.86))
                .foregroundStyle(Color(white: 0.07))
                Rectangle().fill(Color(hex: a.homeColor)).frame(width: 10)
            }
            .frame(height: 46)
            FootLine(text: s.lastPlay)
        }
        .foregroundStyle(.white)
    }

    private var minute: String {
        if s.isFinal { return "FT" }
        if let c = s.clock, !c.isEmpty { return c }
        return s.detail
    }

    private func side(_ uid: String?, _ abbr: String, _ score: Int, home: Bool) -> some View {
        HStack(spacing: 6) {
            LogoMark(uid: uid, abbr: abbr, size: 22)
            Text(abbr).font(.system(size: 16, weight: .bold))
            Spacer(minLength: 0)
            Text("\(score)").font(.system(size: 18, weight: .bold)).monospacedDigit().contentTransition(.numericText())
        }
        .environment(\.layoutDirection, home ? .rightToLeft : .leftToRight)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dynamic Island, expanded

private struct IslandSide: View {
    let a: GameAttributes, s: GameAttributes.ContentState
    let home: Bool
    var body: some View {
        HStack(spacing: 6) {
            if home { Text("\(s.home)").font(.system(size: 28, weight: .black)).monospacedDigit() }
            LogoMark(uid: home ? a.homeUid : a.awayUid, abbr: home ? a.homeAbbr : a.awayAbbr, size: 30)
            if !home { Text("\(s.away)").font(.system(size: 28, weight: .black)).monospacedDigit() }
        }
        .contentTransition(.numericText())
        .padding(.horizontal, 4)
    }
}

private struct IslandCenter: View {
    let a: GameAttributes, s: GameAttributes.ContentState
    var body: some View {
        VStack(spacing: 2) {
            Text(s.isFinal ? "FINAL" : s.detail).font(.system(size: 12, weight: .heavy)).monospacedDigit().lineLimit(1)
            if a.sport == "football", s.isLive, let d = s.down {
                Text(d).font(.system(size: 11, weight: .heavy)).foregroundStyle(flagYellow).lineLimit(1)
            }
        }
    }
}

private struct IslandBottom: View {
    let a: GameAttributes, s: GameAttributes.ContentState
    var body: some View {
        HStack(spacing: 10) {
            if a.sport == "baseball", s.isLive {
                MiniDiamond(bases: s.bases ?? [false, false, false], size: 8)
                Outs(n: s.outs ?? 0, d: 7)
                if let b = s.balls, let st = s.strikes { Text("\(b)-\(st)").font(.system(size: 12, weight: .heavy)).monospacedDigit() }
            } else if a.sport == "football", s.isLive, let spot = s.spot {
                Text("Ball on \(spot)").font(.system(size: 11, weight: .bold))
            }
            if let lp = s.lastPlay {
                Text(lp).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HeldTag()
        }
    }
}
