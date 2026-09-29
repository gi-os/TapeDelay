import ActivityKit
import UIKit
import UserNotifications

/// Push identity for the relay: the APNs device token, the Live Activity push-to-start token,
/// and each running activity's update token.
///
/// All three arrive as async streams that can fire while the app is in the background (iOS
/// wakes it briefly after the relay push-starts an activity), so the observers are started at
/// launch, not when a screen appears.
@MainActor
final class Push: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared: Push?

    func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Push.shared = self
        UNUserNotificationCenter.current().delegate = self
        observeActivities()
        Task {
            let s = await UNUserNotificationCenter.current().notificationSettings()
            if s.authorizationStatus == .authorized || s.authorizationStatus == .provisional {
                app.registerForRemoteNotifications()
            }
        }
        return true
    }

    /// Asked once, from onboarding or Settings.
    func requestPermission() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { UIApplication.shared.registerForRemoteNotifications() }
        return ok
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        AppModel.shared.deviceToken = token.map { String(format: "%02x", $0) }.joined()
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppModel.shared.relayStatus = "Push registration failed: \(error.localizedDescription)"
    }

    // Held alerts land while the app is open too: show them as banners.
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

    // MARK: Live Activities

    private func observeActivities() {
        Task {
            for await data in Activity<GameAttributes>.pushToStartTokenUpdates {
                AppModel.shared.startToken = data.map { String(format: "%02x", $0) }.joined()
            }
        }
        Task {
            for await activity in Activity<GameAttributes>.activityUpdates {
                watch(activity)
            }
        }
        for a in Activity<GameAttributes>.activities { watch(a) }
    }

    private var watched = Set<String>()

    private func watch(_ activity: Activity<GameAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        let game = activity.attributes.gameId
        Task {
            for await data in activity.pushTokenUpdates {
                let tok = data.map { String(format: "%02x", $0) }.joined()
                guard let dev = AppModel.shared.deviceToken else { continue }
                try? await Relay.activity(device: dev, game: game, token: tok)
            }
        }
        Task {
            for await state in activity.activityStateUpdates where state == .dismissed || state == .ended {
                if let dev = AppModel.shared.deviceToken { try? await Relay.activity(device: dev, game: game, token: nil) }
            }
        }
    }

    /// Put a game on the lock screen by hand (from the game screen).
    static func startActivity(for g: Game) throws {
        let attrs = GameAttributes(gameId: g.id, sport: g.kind.rawValue,
                                   homeAbbr: g.home.abbr, awayAbbr: g.away.abbr,
                                   homeName: g.home.short, awayName: g.away.short,
                                   homeColor: g.home.color, awayColor: g.away.color,
                                   homeUid: g.home.uid, awayUid: g.away.uid,
                                   homeRecord: g.home.record, awayRecord: g.away.record,
                                   startTime: g.date.timeIntervalSince1970, venue: g.venue,
                                   watch: g.watch.prefix(3).joined(separator: " · "),
                                   homeProbable: g.home.probable, awayProbable: g.away.probable,
                                   homeProbableLine: g.home.probableLine, awayProbableLine: g.away.probableLine,
                                   homeForm: g.home.form, awayForm: g.away.form,
                                   delay: AppModel.shared.delay)
        _ = try Activity.request(attributes: attrs, content: .init(state: state(for: g), staleDate: nil), pushType: .token)
    }

    /// The same fields the relay sends, from the app's own copy of the game.
    static func state(for g: Game) -> GameAttributes.ContentState {
        var st = GameAttributes.ContentState(
            home: g.home.score ?? 0, away: g.away.score ?? 0, detail: g.detail,
            state: g.state == .post ? "post" : g.state == .pre ? "pre" : "in", period: g.period)
        if g.state == .pre, g.date.addingTimeInterval(Double(AppModel.shared.delay) + 60) < Date() { st.late = true }
        if let s = g.situation {
            if let p = s.possession { st.possession = p == g.home.teamId ? "home" : p == g.away.teamId ? "away" : nil }
            st.down = s.downDistance
            st.outs = s.outs; st.balls = s.balls; st.strikes = s.strikes
            st.bases = [s.onFirst, s.onSecond, s.onThird]
            st.lastPlay = s.lastPlay
        }
        return st
    }

    static func activityRunning(_ gameId: String) -> Bool {
        Activity<GameAttributes>.activities.contains { $0.attributes.gameId == gameId && $0.activityState == .active }
    }

    /// Auto-start, the app-side half. The relay push-starts an activity when a followed game
    /// begins; this covers the cases it can't (no push-to-start token yet, notifications
    /// declined, the game already under way when you opened the app). Each game is started at
    /// most once, so an activity you swipe away stays away.
    static func autoStart(_ games: [Game]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let key = "autoStarted"
        var done = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let running = Set(Activity<GameAttributes>.activities.map(\.attributes.gameId))
        let now = Date()
        let delay = Double(AppModel.shared.delay)
        // Live games, and games starting within 15 minutes of reaching your stream.
        let due = games.filter { g in
            g.state == .live || g.state == .off
                || (g.state == .pre && g.date.addingTimeInterval(delay - 15 * 60) <= now && g.date.addingTimeInterval(4 * 3600) > now)
        }
        for g in due where !done.contains(g.id) && !running.contains(g.id) {
            if (try? startActivity(for: g)) != nil { done.insert(g.id) }
        }
        UserDefaults.standard.set(Array(done.suffix(200)), forKey: key)
    }

    static func endActivity(_ gameId: String) async {
        for a in Activity<GameAttributes>.activities where a.attributes.gameId == gameId {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}
