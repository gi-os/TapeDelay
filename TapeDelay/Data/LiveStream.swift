import Foundation

/// Live games in the app, pushed instead of polled.
///
/// The relay already publishes every change it gets from ESPN's live feed to an ntfy topic per
/// game (`bs-<id>`, the same stream the Light Phone app listens to). While the app is open and a
/// followed game is live, this keeps one streaming HTTP connection to those topics and applies
/// each snapshot as it lands, held on the phone by the delay. At "Live" that means within a
/// second or two of ESPN, instead of the 20 seconds (or more) a scoreboard poll takes.
@MainActor
final class LiveStream {
    static let shared = LiveStream()

    private var ids: Set<String> = []
    private var reader: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    /// Snapshots waiting out the delay, oldest first.
    private var buffer: [(at: Date, snap: Relay.Snapshot)] = []

    private struct Message: Decodable { let event: String; let message: String? }

    /// Stream these games (pass an empty set to stop).
    func watch(_ newIds: Set<String>) {
        guard newIds != ids else { return }
        ids = newIds
        reader?.cancel(); reader = nil
        ticker?.cancel(); ticker = nil
        buffer.removeAll()
        guard !ids.isEmpty else { return }
        let topics = ids.sorted().map { "bs-" + $0 }.joined(separator: ",")
        guard let url = URL(string: "https://sports.gzl.dev/\(topics)/json") else { return }
        reader = Task { [weak self] in
            while !Task.isCancelled {
                var req = URLRequest(url: url, timeoutInterval: 120)   // ntfy keeps it alive every 45s
                req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                if let (bytes, _) = try? await URLSession.shared.bytes(for: req) {
                    do {
                        for try await line in bytes.lines {
                            guard let data = line.data(using: .utf8),
                                  let m = try? JSONDecoder().decode(Message.self, from: data),
                                  m.event == "message", let body = m.message?.data(using: .utf8),
                                  let snap = try? JSONDecoder().decode(Relay.Snapshot.self, from: body) else { continue }
                            self?.receive(snap)
                        }
                    } catch {}
                }
                try? await Task.sleep(for: .seconds(2))   // dropped: reconnect
            }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.flush()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func receive(_ snap: Relay.Snapshot) {
        buffer.append((Date(), snap))
        flush()
    }

    /// Apply everything that has now waited out the delay.
    private func flush() {
        let hold = Double(AppModel.shared.delay)
        let now = Date()
        while let first = buffer.first, first.at.addingTimeInterval(hold) <= now {
            buffer.removeFirst()
            AppModel.shared.apply(first.snap)
        }
    }
}
