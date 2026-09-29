import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TapeDelayWidgets: WidgetBundle {
    var body: some Widget { GameLiveActivity() }
}

/// Lock screen and Dynamic Island. Every update is pushed by the relay, already held by the
/// device's delay; nothing here fetches.
struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameAttributes.self) { ctx in
            LockScreen(a: ctx.attributes, s: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let a = ctx.attributes, s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamScore(abbr: a.awayAbbr, score: s.away, color: a.awayColor, has: s.possession == "away", sport: a.sport)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamScore(abbr: a.homeAbbr, score: s.home, color: a.homeColor, has: s.possession == "home", sport: a.sport)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.detail).font(.caption.weight(.semibold).monospacedDigit()).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Extra(sport: a.sport, s: s)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Text(a.awayAbbr).font(.caption2.weight(.bold)).foregroundStyle(Color(hex: a.awayColor).mix(with: .white, by: 0.4))
                    Text("\(s.away)").font(.caption.weight(.heavy).monospacedDigit())
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(s.home)").font(.caption.weight(.heavy).monospacedDigit())
                    Text(a.homeAbbr).font(.caption2.weight(.bold)).foregroundStyle(Color(hex: a.homeColor).mix(with: .white, by: 0.4))
                }
            } minimal: {
                Text("\(s.away)-\(s.home)").font(.caption2.weight(.heavy).monospacedDigit())
            }
            .keylineTint(Color(hex: a.homeColor))
        }
    }
}

private struct LockScreen: View {
    let a: GameAttributes
    let s: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TeamScore(abbr: a.awayAbbr, score: s.away, color: a.awayColor, has: s.possession == "away", sport: a.sport, big: true)
                Spacer()
                VStack(spacing: 2) {
                    Text(s.detail).font(.caption.weight(.semibold).monospacedDigit())
                    if s.isFinal { Text("FINAL").font(.caption2.weight(.heavy)).foregroundStyle(.secondary) }
                }
                Spacer()
                TeamScore(abbr: a.homeAbbr, score: s.home, color: a.homeColor, has: s.possession == "home", sport: a.sport, big: true)
            }
            Extra(sport: a.sport, s: s)
        }
        .padding(16)
    }
}

private struct TeamScore: View {
    let abbr: String
    let score: Int
    let color: String
    let has: Bool
    let sport: String
    var big = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: color).mix(with: .white, by: 0.2)).frame(width: 4, height: big ? 30 : 22)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(abbr).font((big ? Font.subheadline : .caption).weight(.bold))
                    if has { Circle().fill(.orange).frame(width: 5, height: 5) }
                }
                Text("\(score)").font(.system(size: big ? 30 : 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct Extra: View {
    let sport: String
    let s: GameAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if sport == "baseball", let bases = s.bases {
                MiniBases(on: bases)
                if let o = s.outs { Text("\(o) out").font(.caption2) }
                if let b = s.balls, let st = s.strikes { Text("\(b)-\(st)").font(.caption2.monospacedDigit()) }
            } else if sport == "football", let d = s.down {
                Text(d).font(.caption2.weight(.semibold))
            }
            if let lp = s.lastPlay {
                Text(lp).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "timer").font(.caption2).foregroundStyle(.orange)
        }
    }
}

private struct MiniBases: View {
    let on: [Bool]
    var body: some View {
        let b = on + Array(repeating: false, count: max(0, 3 - on.count))
        ZStack {
            d(b[1]).offset(y: -5)
            d(b[2]).offset(x: -5)
            d(b[0]).offset(x: 5)
        }
        .frame(width: 18, height: 16)
    }
    private func d(_ x: Bool) -> some View {
        Rectangle().fill(x ? Color.orange : Color.white.opacity(0.25)).frame(width: 6, height: 6).rotationEffect(.degrees(45))
    }
}
