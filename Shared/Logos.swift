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

/// A saved logo, or the team's letters. `on` is the colour behind it: a logo that would vanish
/// into it is drawn in white.
struct LogoMark: View {
    let uid: String?
    let abbr: String
    var size: CGFloat
    var on: String? = nil

    var body: some View {
        if let img = LogoStore.image(uid) {
            if let on, LogoContrast.blends(img, on: on, key: uid ?? abbr) {
                Image(uiImage: img).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.white).frame(width: size, height: size)
            } else {
                Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
            }
        } else {
            Text(abbr).font(.system(size: size * 0.36, weight: .black)).minimumScaleFactor(0.5)
                .frame(width: size, height: size)
        }
    }
}

/// Some logos are drawn in their own team colour (a navy crest for a navy team), so on the
/// team-colour backgrounds they vanish. This measures how much of a logo sits close to the colour
/// behind it and, past a threshold, the logo is drawn as a white silhouette instead.
enum LogoContrast {
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// `hex` mixed toward black, the way the dark discs sit over a team colour.
    static func darken(_ hex: String, by f: Double) -> String {
        guard let (r, g, b) = rgb(hex) else { return hex }
        let c = { (x: Double) in String(format: "%02x", Int((x * (1 - f)) * 255)) }
        return c(r) + c(g) + c(b)
    }

    static func blends(_ img: UIImage, on bg: String, key: String) -> Bool {
        let k = key + "|" + bg
        if let hit = cache[k] { return hit }
        guard let (br, bgc, bb) = rgb(bg), let cg = img.cgImage else { return false }
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return false }
        var opaque = 0, close = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.5 else { continue }
            opaque += 1
            let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
            let d = ((r - br) * (r - br) * 0.3 + (g - bgc) * (g - bgc) * 0.59 + (b - bb) * (b - bb) * 0.11).squareRoot()
            if d < 0.16 { close += 1 }
        }
        let result = opaque > 0 && Double(close) / Double(opaque) > 0.45
        cache[k] = result
        return result
    }
}
