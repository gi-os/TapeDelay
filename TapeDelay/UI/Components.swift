import SwiftUI
import UIKit

enum Theme {
    static let flag = Color(red: 1.0, green: 0.776, blue: 0.125)   // penalty-flag yellow, the icon
    static let accent = flag
    static let live = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let held = flag
    static let mono = Font.system(.body, design: .monospaced)
}

/// The backdrop every screen sits on. Liquid Glass needs something behind it to bend, so the
/// followed teams' colours are blurred into a slow field.
struct Backdrop: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            Color.black
            ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { i, c in
                Circle()
                    .fill(c.opacity(0.55))
                    .frame(width: 420, height: 420)
                    .blur(radius: 120)
                    .offset(x: [-140, 160, -80, 120][i], y: [-260, -60, 220, 380][i])
            }
        }
        .ignoresSafeArea()
    }
}

/// A team logo from ESPN. `on` is the colour it sits on; a logo drawn in that same colour (a navy
/// crest on navy) is shown as a white silhouette so it doesn't disappear.
struct Crest: View {
    let url: URL?
    var abbr: String = ""
    var size: CGFloat = 28
    var on: String? = nil
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if let on, LogoContrast.blends(image, on: on, key: url?.absoluteString ?? abbr) {
                    Image(uiImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(.white)
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Text(abbr.prefix(4))
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url else { return }
            image = await LogoLoader.shared.image(url)
        }
    }
}

/// In-memory logo cache over URLSession's disk cache.
actor LogoLoader {
    static let shared = LogoLoader()
    private var memo: [URL: UIImage] = [:]

    func image(_ url: URL) async -> UIImage? {
        if let hit = memo[url] { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let img = UIImage(data: data) else { return nil }
        memo[url] = img
        return img
    }
}

/// "30s behind" — the thing this app is for, always on screen.
struct DelayPill: View {
    @Environment(AppModel.self) private var model
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: model.delay == 0 ? "dot.radiowaves.left.and.right" : "timer")
                    .symbolEffect(.pulse, options: .repeating, isActive: model.games.contains { $0.state == .live })
                Text(model.delay == 0 ? "Live" : "\(AppModel.format(model.delay)) behind")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .contentTransition(.numericText())
                if model.delay > 0 {
                    Text(model.presetName).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(model.delay == 0 ? Theme.live.opacity(0.25) : Theme.held.opacity(0.22)).interactive(), in: .capsule)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.bold)).tracking(1.2)
                .foregroundStyle(title == "Live" ? Theme.live : .secondary)
            if let count { Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary) }
            Spacer()
        }
        .padding(.horizontal, 6).padding(.top, 14)
    }
}

/// Bases as a small diamond: first on the right, like the field seen from home.
struct Bases: View {
    var on: [Bool]
    var size: CGFloat = 9

    var body: some View {
        let b = on + Array(repeating: false, count: max(0, 3 - on.count))
        ZStack {
            base(b[1]).offset(y: -size * 0.75)
            base(b[2]).offset(x: -size * 0.75)
            base(b[0]).offset(x: size * 0.75)
        }
        .frame(width: size * 2.6, height: size * 2.2)
    }

    private func base(_ occupied: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(occupied ? Theme.held : Color.white.opacity(0.18))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
    }
}
