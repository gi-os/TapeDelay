import SwiftUI
import UIKit

/// Team logos for the Live Activity. A lock-screen card can't download anything while it renders,
/// so every logo ESPN and StatsAPI list is baked into the widget bundle at build time
/// (ci/fetch_logos.py), named by team uid. The App Group copy is a fallback for teams that
/// appear between builds; without either, callers get nil and show the team's letters.
enum LogoStore {
    static let group = "group.com.gios.tapedelay"

    private static var dir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let d = base.appending(path: "logos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func file(_ uid: String) -> URL? {
        guard !uid.isEmpty else { return nil }
        return dir?.appending(path: safeName(uid) + ".png")
    }

    /// The logo baked into the widget at build time (ci/fetch_logos.py), else one the app saved.
    static func image(_ uid: String?) -> UIImage? {
        guard let uid, !uid.isEmpty else { return nil }
        let name = safeName(uid)
        if let u = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Logos")
            ?? Bundle.main.url(forResource: name, withExtension: "png"),
           let img = UIImage(contentsOfFile: u.path) { return img }
        guard let f = file(uid) else { return nil }
        return UIImage(contentsOfFile: f.path)
    }

    static func safeName(_ uid: String) -> String {
        uid.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    static func has(_ uid: String) -> Bool {
        guard let f = file(uid) else { return true }   // no container: nothing to do
        guard let a = try? FileManager.default.attributesOfItem(atPath: f.path),
              let d = a[.modificationDate] as? Date else { return false }
        return d > Date().addingTimeInterval(-14 * 86400)
    }

    /// Download, shrink to 120px (widgets have a tight memory budget) and save.
    static func fetch(uid: String, from url: URL) async {
        guard !has(uid), let f = file(uid),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        let side: CGFloat = 120
        let scale = min(side / max(img.size.width, 1), side / max(img.size.height, 1), 1)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        try? small.pngData()?.write(to: f, options: .atomic)
    }
}

/// A saved logo, or the team's letters.
struct LogoMark: View {
    let uid: String?
    let abbr: String
    var size: CGFloat

    var body: some View {
        if let img = LogoStore.image(uid) {
            Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(abbr).font(.system(size: size * 0.36, weight: .black)).frame(width: size, height: size)
        }
    }
}
