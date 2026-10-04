import ActivityKit
import AppIntents
import Foundation

/// The league card's buttons: the pill under the scorebug, "‹ NYR" to go back, and ‹ › to page.
///
/// A `LiveActivityIntent` runs in the app's process (woken in the background), not the widget's,
/// so it can reach the relay. The relay builds the grid (every game held to your delay) and
/// keeps sending it while the card shows the league; this only flips the view and shows the
/// relay's answer at once.
struct LeagueIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Show the league"
    static var isDiscoverable = false

    @Parameter(title: "Game") var game: String
    @Parameter(title: "League") var league: Bool
    @Parameter(title: "Step") var step: Int

    init() {}
    init(game: String, league: Bool, step: Int = 0) {
        self.game = game
        self.league = league
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        await LeagueView.show(game: game, league: league, step: step)
        return .result()
    }
}

enum LeagueView {
    static let url = URL(string: "https://sports.gzl.dev/tape/v1/view")!

    static func show(game: String, league: Bool, step: Int) async {
        guard let activity = Activity<GameAttributes>.activities.first(where: { $0.attributes.gameId == game })
        else { return }
        if !league {
            // Going back needs nothing from the relay: show the game now, then tell it.
            var s = activity.content.state
            s.view = nil; s.tiles = nil; s.page = nil; s.pages = nil
            await activity.update(ActivityContent(state: s, staleDate: nil))
        }
        guard let device = UserDefaults.standard.string(forKey: "deviceToken") else { return }
        struct Body: Encodable { let device: String; let game: String; let view: String; let step: Int }
        struct Reply: Decodable { let state: GameAttributes.ContentState }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(Body(device: device, game: game, view: league ? "league" : "game", step: step))
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return }
        if league { await activity.update(ActivityContent(state: reply.state, staleDate: nil)) }
    }
}
