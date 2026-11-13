import SwiftUI

/// The wild woods that wrap around Mossbrook: thick forest on both sides and below,
/// with trails that wander off into the trees, waiting for new places to be built.
extension VillageRenderer {
    /// Everything in the woods that stands still. Drawn once into a picture and reused (see `WildsCache`).
    static func wildsBase(_ p: Painter, state: SceneState) {
        weather = state.weather
        season = state.season
        let M = VillageLayout.margin
        let WW = VillageLayout.worldWidth
        let WH = VillageLayout.worldHeight
        let gloomy = weather == .rain || weather == .snow
        let bands: [UInt32]
        switch state.phase {
        case .day where gloomy: bands = [0x9AA8B8, 0xB0BCC8, 0xC6CED6]
        case .dusk where gloomy: bands = [0x7A6E8A, 0x9C8A98, 0xB8A8A8]
        case .day: bands = [0x9ED6EC, 0xB5E1EF, 0xCDEBEF]
        case .dusk: bands = [0x8E6FA6, 0xE79A86, 0xF6C79A]
        case .night: bands = [0x161B3A, 0x1F2550, 0x2B3166]
        }
        // Sky and hills, carried out past the town.
        _ = bands
        for x in 0..<WW {
            let gx = x - M
            let far = 46 + Int(3 * sin(Double(gx) * 0.09) + 2 * sin(Double(gx) * 0.23 + 1))
            p.rect(x, far, 1, 66 - far, Color(hex: 0x8FBF94))
            let near = 54 + Int(2.5 * sin(Double(gx) * 0.13 + 2) + 1.5 * sin(Double(gx) * 0.31))
            p.rect(x, near, 1, 66 - near, Color(hex: 0x7DB37F))
        }
        // Forest floor.
        p.rect(0, groundTop, WW, WH - groundTop, Color(hex: 0x6FA85A))
        for i in 0..<900 {
            let x = noise(i, 41) % WW, y = groundTop + noise(i, 43) % (WH - groundTop)
            p.dot(x, y, i % 11 == 0 ? Color(hex: 0xF49AC1) : Color(hex: 0x5E9450))
        }

        // Trails wandering out of town into the woods.
        let trailY = mainStreet.y + 1
        func trail(from x0: Int, to x1: Int) {
            let step = x1 > x0 ? 1 : -1
            var x = x0
            while x != x1 {
                let d = abs(x - x0)
                let y = trailY + Int(4 * sin(Double(d) * 0.08))
                p.rect(x, y, 1, 6, dirtEdge)
                p.rect(x, y + 1, 1, 4, dirt)
                x += step
            }
        }
        trail(from: M, to: 6)
        trail(from: M + W, to: WW - 6)
        let sx = M + 128
        for y in (H - 8)..<(WH - 4) {
            let x = sx - 3 + Int(3 * sin(Double(y) * 0.12))
            p.rect(x, y, 7, 1, dirtEdge)
            p.rect(x + 1, y, 5, 1, dirt)
        }

        // Dense trees, row by row so they overlap nicely. The trails stay clear.
        var spots: [(Int, Int, Int)] = []
        var i = 0
        for y in stride(from: groundTop - 6, to: WH, by: 7) {
            for x in stride(from: -6 + (y / 7 % 2) * 4, to: WW, by: 8) {
                i += 1
                let jx = x + noise(i, 5) % 4 - 2, jy = y + noise(i, 9) % 3
                let inTown = jx > M - 6 && jx < M + W - 4 && jy < H - 12
                if inTown { continue }
                let onSideTrail = abs(jy + 10 - trailY) < 9 && (jx < M + 2 || jx > M + W - 12)
                let onSouthTrail = jy > H - 20 && abs(jx + 5 - sx) < 9
                if onSideTrail || onSouthTrail { continue }
                spots.append((jx, jy, i))
            }
        }
        for (x, y, k) in spots {
            if noise(k, 71) % 3 == 0 { tree(p, x: x, y: y, index: k) } else { pine(p, x: x, y: y - 3, k: k) }
        }

        signpost(p, x: 14, y: trailY - 12)
        signpost(p, x: WW - 22, y: trailY - 12)
        signpost(p, x: sx + 8, y: WH - 20)

        // The deeper you look, the darker the woods.
        // Smooth gradients (not thin strips) so no seams show between columns.
        let shade = Color(hex: 0x1C3324)
        let fade = Gradient(stops: (0...8).map { i in
            let k = Double(i) / 8
            return .init(color: shade.opacity(0.42 * pow(1 - k, 1.6)), location: k)
        })
        let s = p.s
        let top = CGFloat(groundTop) * s, tall = CGFloat(WH - groundTop) * s, band = CGFloat(M) * s
        p.flush()
        p.ctx.fill(Path(CGRect(x: 0, y: top, width: band, height: tall)),
                   with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: band, y: 0)))
        let right = CGFloat(WW) * s
        p.ctx.fill(Path(CGRect(x: right - band, y: top, width: band, height: tall)),
                   with: .linearGradient(fade, startPoint: CGPoint(x: right, y: 0), endPoint: CGPoint(x: right - band, y: 0)))
        let bm = VillageLayout.bottomMargin
        let bottom = CGFloat(H + bm) * s, bandB = CGFloat(bm) * s
        p.ctx.fill(Path(CGRect(x: 0, y: bottom - bandB, width: right, height: bandB)),
                   with: .linearGradient(fade, startPoint: CGPoint(x: 0, y: bottom), endPoint: CGPoint(x: 0, y: bottom - bandB)))

        switch state.phase {
        case .day: break
        case .dusk:
            tintBelowHills(p, width: WW, offset: M, Color(hex: 0xFF8A55).opacity(0.10))
            tintBelowHills(p, width: WW, offset: M, Color(hex: 0x3A2850).opacity(0.06))
        case .night:
            tintBelowHills(p, width: WW, offset: M, Color(hex: 0x0E1238).opacity(0.48))
        }
    }

    /// The few things in the woods that move: twinkling stars and fireflies at night.
    static func wildsLive(_ p: Painter, t: Double, state: SceneState) {
        guard state.phase == .night else { return }
        let M = VillageLayout.margin
        let WW = VillageLayout.worldWidth
        let WH = VillageLayout.worldHeight
        worldStars(p, t: t, inTown: false)
        do {
            for k in 0..<14 {
                let fx = Double(noise(k, 61) % WW) + 4 * sin(t * 0.7 + Double(k))
                let fy = Double(groundTop + noise(k, 67) % (WH - groundTop)) + 3 * cos(t * 0.9 + Double(k))
                if fx > Double(M) && fx < Double(M + W) && fy < Double(H) { continue }
                p.glow(fx, fy, radius: 3, Color(hex: 0xE8F59A), 0.6)
                p.dot(Int(fx), Int(fy), Color(hex: 0xF4FFC0))
            }
        }
    }

    /// A tall pine, a darker evergreen that gives the woods depth.
    static func pine(_ p: Painter, x: Int, y: Int, k: Int) {
        let main = weather == .snow ? Color(hex: 0x3F6A52) : Color(hex: [0x3E7A4E, 0x45845A, 0x3A6F4A][k % 3])
        let light = Color(hex: 0x5E9E66)
        let dark = Color(hex: 0x2C5A3C)
        p.rect(x + 1, y + 15, 9, 2, shadow)
        p.rect(x + 4, y + 12, 2, 4, Color(hex: 0x6A4630))
        for r in 0..<13 {
            let half = r < 4 ? r / 2 + 1 : (r < 8 ? (r - 3) / 2 + 2 : (r - 7) / 2 + 3)
            p.rect(x + 5 - half - 1, y + r, half * 2 + 2, 1, leafInk)
            p.rect(x + 5 - half, y + r, half * 2, 1, main)
            p.dot(x + 5 - half, y + r, r % 4 == 1 ? light : main)
            p.dot(x + 4 + half, y + r, dark)
        }
        p.rect(x + 4, y - 1, 2, 1, leafInk)
        if weather == .snow {
            p.rect(x + 4, y, 2, 1, Color(hex: 0xF4F7FB))
            p.rect(x + 2, y + 5, 2, 1, Color(hex: 0xF4F7FB))
            p.rect(x + 6, y + 9, 2, 1, Color(hex: 0xF4F7FB))
        }
    }

    /// A little wooden sign with a question mark: something new could go here one day.
    static func signpost(_ p: Painter, x: Int, y: Int) {
        p.rect(x + 2, y + 11, 6, 1, shadow)
        box(p, x + 4, y + 4, 1, 8, wood)
        box(p, x, y, 9, 5, Color(hex: 0xC4956A))
        p.rect(x + 1, y + 1, 7, 1, Color(hex: 0xD9AE82))
        p.rect(x + 3, y + 1, 3, 1, ink)
        p.dot(x + 5, y + 2, ink)
        p.dot(x + 4, y + 3, ink)
    }
}


/// The still part of the woods, drawn once per look (time of day, weather, season) at two
/// pictures-pixels per art pixel and then just scaled up. Pixel art scales up perfectly with
/// nearest-neighbour sampling, so zooming never needs a redraw.
@MainActor
final class WildsCache {
    static let shared = WildsCache()
    private var key = ""
    private var image: CGImage?

    func image(for state: SceneState) -> CGImage? {
        let k = "\(state.phase)-\(state.weather)-\(state.season)"
        if k == key, let image { return image }
        let scale: CGFloat = 2
        let w = CGFloat(VillageLayout.worldWidth), h = CGFloat(VillageLayout.worldHeight)
        let renderer = ImageRenderer(content:
            Canvas { ctx, _ in Painter.batched(ctx, s: scale) { VillageRenderer.wildsBase($0, state: state) } }
                .frame(width: w * scale, height: h * scale)
        )
        renderer.scale = 1
        image = renderer.cgImage
        key = k
        return image
    }
}
