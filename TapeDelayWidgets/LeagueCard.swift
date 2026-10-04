import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The lock screen card: your game's scorebug with one quiet pill ("MLB · 3 more ›"), or, after
/// a tap on it, the league as a 2×2 grid of small scorebugs in the same sport's style. Your game
/// is always the first tile. Everything in it comes from the relay, held to your delay.
struct Card: View {
    let a: GameAttributes
    let s: GameAttributes.ContentState

    var body: some View {
        if s.showsLeague {
            LeagueGrid(a: a, s: s)
        } else {
            VStack(spacing: 0) {
                Scorebug(a: a, s: s)
                if let more = s.leagueMore, more > 0, let name = s.leagueName {
                    HStack {
                        Spacer(minLength: 0)
                        Button(intent: LeagueIntent(game: a.gameId, league: true)) {
                            Text("\(name) · \(more) more ›")
                        }
                        .buttonStyle(QuietPill())
                    }
                    .padding(.horizontal, 10).padding(.bottom, 6).padding(.top, 2)
                }
            }
        }
    }
}

/// Light, not a call to action: small grey text in a faint capsule.
struct QuietPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.9 : 0.62))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.white.opacity(0.08), in: .capsule)
    }
}

struct LeagueGrid: View {
    let a: GameAttributes
    let s: GameAttributes.ContentState

    var body: some View {
        let tiles = s.tiles ?? []
        let page = s.page ?? 0, pages = s.pages ?? 1
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(intent: LeagueIntent(game: a.gameId, league: false)) {
                    Text("‹ \(a.awayAbbr)@\(a.homeAbbr)")
                }
                .buttonStyle(QuietPill())
                Text(s.leagueTitle ?? s.leagueName ?? "")
                    .font(.system(size: 10.5, weight: .bold)).kerning(1.2)
                    .foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if pages > 1 {
                    HStack(spacing: 5) {
                        Button(intent: LeagueIntent(game: a.gameId, league: true, step: -1)) { Image(systemName: "chevron.left") }
                            .buttonStyle(Arrow())
                        HStack(spacing: 3) {
                            ForEach(0..<min(pages, 8), id: \.self) { i in
                                Circle().fill(.white.opacity(i == page ? 1 : 0.25)).frame(width: 4.5, height: 4.5)
                            }
                        }
                        Button(intent: LeagueIntent(game: a.gameId, league: true, step: 1)) { Image(systemName: "chevron.right") }
                            .buttonStyle(Arrow())
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(tiles.prefix(4).enumerated()), id: \.element.id) { i, t in
                    MiniBug(sport: a.sport, t: t)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(i == 0 ? 0.7 : 0), lineWidth: 1.5))
                }
            }
        }
        .padding(10)
        .background(a.sport == "baseball" ? Color(red: 0.04, green: 0.08, blue: 0.19) : .clear)
    }
}

struct Arrow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 20, height: 20)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.08), in: .circle)
    }
}

// MARK: - one tile per sport, each a small copy of that sport's scorebug

struct MiniBug: View {
    let sport: String
    let t: GameAttributes.Tile

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch sport {
                case "baseball": baseball
                case "football": football
                case "basketball": basketball
                case "hockey": hockey
                default: soccer
                }
            }
            .frame(height: 38)
            HStack {
                Text(t.n ?? "").lineLimit(1)
                Spacer(minLength: 4)
                Text(t.tv ?? "").lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 6).frame(height: 13)
        }
        .background(sport == "baseball" ? Color(red: 0.055, green: 0.10, blue: 0.20) : Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 11))
    }

    private var live: Bool { t.st != "pre" }
    private func score(_ v: Int?) -> String { live ? "\(v ?? 0)" : "" }

    /// "▲5", "FINAL", or the start time for a game not under way on your stream.
    @ViewBuilder private func status(_ size: CGFloat) -> some View {
        if t.st == "pre", let ts = t.t, ts > 0 {
            Text(Date(timeIntervalSince1970: ts), style: .time).font(.system(size: size, weight: .heavy))
                .lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(t.d).font(.system(size: size, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func grad(_ hex: String, _ trailing: Bool) -> LinearGradient {
        let c = Color(hex: hex)
        let cs = [c, c.mix(with: .black, by: 0.3)]
        return LinearGradient(colors: trailing ? cs.reversed() : cs, startPoint: .leading, endPoint: .trailing)
    }

    // Baseball: the box. Team tiles and runs on grey rules, the diamond and inning beside.
    private var baseball: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1.5) {
                boxRow(t.a, t.ac, score(t.awayScore))
                boxRow(t.h, t.hc, score(t.homeScore))
            }
            .background(Color(red: 0.79, green: 0.82, blue: 0.87))
            VStack(spacing: 1) {
                if t.st == "in", let b = t.b {
                    MiniDiamond(bases: [b & 1 != 0, b & 2 != 0, b & 4 != 0], size: 5)
                }
                status(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.106, green: 0.184, blue: 0.369))
        }
    }

    private func boxRow(_ ab: String, _ hex: String, _ sc: String) -> some View {
        HStack(spacing: 1.5) {
            Text(ab).font(.system(size: 10.5, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 34, height: 18.25).background(Color(hex: hex))
            Text(sc).font(.system(size: 12, weight: .heavy)).monospacedDigit()
                .frame(width: 20, height: 18.25).background(Color(red: 0.106, green: 0.184, blue: 0.369))
        }
    }

    // Football: two colour halves, the team behind each in big faded letters, scores in italics.
    private var football: some View {
        ZStack {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    grad(t.ac, false)
                    Text(t.a).font(.system(size: 26, weight: .black)).opacity(0.35).offset(x: -3).lineLimit(1)
                }
                ZStack(alignment: .trailing) {
                    grad(t.hc, true)
                    Text(t.h).font(.system(size: 26, weight: .black)).opacity(0.35).offset(x: 3).lineLimit(1)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 80)
            VStack(spacing: 0) {
                if live {
                    HStack(spacing: 10) { Text(score(t.awayScore)); Text(score(t.homeScore)) }
                        .font(.system(size: 17, weight: .black).italic()).monospacedDigit()
                }
                status(9).italic()
            }
        }
        .clipped()
    }

    // Basketball: the bar. Team gradients either side, quarter and clock in the dark middle.
    private var basketball: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Text(t.a).font(.system(size: 10.5, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(score(t.awayScore)).font(.system(size: 15, weight: .black)).monospacedDigit()
            }
            .padding(.horizontal, 5).frame(maxHeight: .infinity).background(grad(t.ac, false))
            status(9).frame(width: 40).frame(maxHeight: .infinity).background(Color(white: 0.055))
            HStack(spacing: 3) {
                Text(score(t.homeScore)).font(.system(size: 15, weight: .black)).monospacedDigit()
                Spacer(minLength: 0)
                Text(t.h).font(.system(size: 10.5, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 5).frame(maxHeight: .infinity).background(grad(t.hc, true))
        }
    }

    // Hockey: stacked rows, a colour block and the score for each, the period on the right.
    private var hockey: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                hockeyRow(t.a, t.ac, score(t.awayScore))
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                hockeyRow(t.h, t.hc, score(t.homeScore))
            }
            status(9).multilineTextAlignment(.center)
                .frame(width: 44).frame(maxHeight: .infinity).background(Color(white: 0.055))
        }
    }

    private func hockeyRow(_ ab: String, _ hex: String, _ sc: String) -> some View {
        HStack(spacing: 0) {
            Text(ab).font(.system(size: 9.5, weight: .black)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 34).frame(maxHeight: .infinity).background(Color(hex: hex))
            Spacer(minLength: 0)
            Text(sc).font(.system(size: 13, weight: .black)).monospacedDigit().padding(.trailing, 8)
        }
    }

    // Soccer: the slim bar. Minute in black, colour stripes, the light score bar between.
    private var soccer: some View {
        HStack(spacing: 0) {
            status(10).padding(.horizontal, 5).frame(maxHeight: .infinity).background(.black)
            Rectangle().fill(Color(hex: t.ac)).frame(width: 4)
            HStack(spacing: 3) {
                Text(t.a).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(score(t.awayScore)).monospacedDigit()
                Rectangle().fill(Color(white: 0.07)).frame(width: 1.5, height: live ? 14 : 0)
                Text(score(t.homeScore)).monospacedDigit()
                Spacer(minLength: 0)
                Text(t.h).lineLimit(1).minimumScaleFactor(0.6)
            }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.07))
            .padding(.horizontal, 4).frame(maxHeight: .infinity)
            .background(Color(red: 0.85, green: 0.85, blue: 0.86))
            Rectangle().fill(Color(hex: t.hc)).frame(width: 4)
        }
        .frame(height: 24).frame(maxHeight: .infinity)
    }
}
