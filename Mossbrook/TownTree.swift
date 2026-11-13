import SwiftUI

// MARK: - Mayor Barnaby

extension Sprites {
    /// The mayor: a tall top hat, a big white mustache and a smart green coat.
    static let mayor = Sprite([
        "................",
        ".....kkkkkk.....",
        ".....khhhhk.....",
        ".....khhhhk.....",
        ".....kbbbbk.....",
        "...kkkkkkkkkk...",
        "..kwsssssssswk..",
        "..kssksssskssk..",
        "..ksrssssssrsk..",
        "..kswwwwwwwwsk..",
        "...kswwmmwwsk...",
        "....kkkkkkkk....",
        "...kcccyyccck...",
        "..kscccyycccsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": Color(hex: 0x2B2233), "h": Color(hex: 0x3A2A4A), "b": Color(hex: 0xF2C14E),
        "s": Color(hex: 0xF6CFA8), "w": Color(hex: 0xFFF6E5), "r": Color(hex: 0xF0A090),
        "m": Color(hex: 0xC0504A), "c": Color(hex: 0x3E6B48), "y": Color(hex: 0xF2C14E),
        "p": Color(hex: 0x3D3F63)
    ])
}

// MARK: - The Old Oak on the town map

extension VillageRenderer {
    static let oakCenter = (x: 128, base: 140)

    /// The oak stays green all year: (outline, shadow, leaf, light, highlight).
    static let oakGreens = (Color(hex: 0x24452A), Color(hex: 0x3B6E35), Color(hex: 0x4F8A3E), Color(hex: 0x6EAB50), Color(hex: 0x95CB6A))

    /// Draws a lumpy cartoon canopy from overlapping lobes, with seasonal touches on top.
    static func oakCanopy(_ p: Painter, lobes: [(Int, Int, Int)], bottom: Int, seed: Int = 0) {
        let (line, shade, leaf, light, high) = oakGreens
        for (x, y, r) in lobes { circle(p, cx: x, cy: y, r: r + 1, line) }
        for (x, y, r) in lobes { circle(p, cx: x, cy: y, r: r, shade) }
        for (x, y, r) in lobes { circle(p, cx: x - 1, cy: y - max(1, r / 5), r: max(1, r - 2), leaf) }
        // Leafy lighter patches towards the top-left of each lobe.
        for (x, y, r) in lobes {
            let pr = max(2, r * 11 / 20)
            circle(p, cx: x - r / 4, cy: y - r / 3, r: pr, light)
            circle(p, cx: x - r / 3, cy: y - r / 2, r: max(1, pr / 2), high)
        }
        // A darker band underneath, so the canopy feels round and heavy.
        for (x, y, r) in lobes where y + r >= bottom - 3 {
            p.rect(x - r + 2, y + r - 2, max(1, 2 * r - 4), 2, shade)
        }
        for i in 0..<(lobes.count * 9) {
            let (x, y, r) = lobes[i % lobes.count]
            let lx = x + noise(i + seed, 21) % max(1, 2 * r) - r, ly = y + noise(i + seed, 22) % max(1, 2 * r) - r
            let d = Double((lx - x) * (lx - x) + (ly - y) * (ly - y)).squareRoot()
            guard d < Double(r - 1) else { continue }
            p.rect(lx, ly, 2, 1, ly < y ? high : shade)
        }
        // Seasonal accents over the green.
        let accents: [Color]
        switch season {
        case .autumn: accents = [Color(hex: 0xF2A93B), Color(hex: 0xE0703F), Color(hex: 0xF7D774)]
        case .spring: accents = [Color(hex: 0xF7B7CF), Color(hex: 0xFFFFFF)]
        default: accents = []
        }
        if !accents.isEmpty || weather == .petals {
            let cs = accents.isEmpty ? [Color(hex: 0xF7B7CF)] : accents
            for i in 0..<(lobes.count * 2) {
                let (x, y, r) = lobes[i % lobes.count]
                p.rect(x + noise(i + seed, 31) % max(1, 2 * r) - r, y + noise(i + seed, 32) % max(1, r) - r / 2, 1, 1, cs[i % cs.count])
            }
        }
        if weather == .snow || season == .winter {
            for (x, y, r) in lobes { p.rect(x - r / 2, y - r, max(2, r), 2, Color(hex: 0xF4F7FB)) }
        }
    }

    /// A chubby, softly tapering trunk that flares into little curled roots, with a highlight,
    /// bark lines and a tiny carved heart. `top` is hidden under the canopy.
    static func cuteTrunk(_ p: Painter, cx: Int, top: Int, base: Int, topW: Int, baseW: Int, heartY: Int? = nil) {
        let bark = Color(hex: 0x9A7150), barkDark = Color(hex: 0x765238), barkLight = Color(hex: 0xC09468)
        let h = base - top
        func width(_ y: Int) -> Int {
            let k = Double(y - top) / Double(max(h, 1))
            let flare = max(0, k - 0.72) / 0.28           // the bottom quarter flares out
            return Int((Double(topW) + Double(baseW - topW) * (k * 0.25 + flare * flare * 0.75)).rounded())
        }
        // Outline first, then the bark, row by row so the edges curve smoothly.
        for y in top...base {
            let w = width(y); p.rect(cx - w / 2 - 1, y, w + 2, 1, ink)
        }
        p.rect(cx - width(base) / 2, base + 1, width(base), 1, ink)
        for y in top...base {
            let w = width(y), x0 = cx - w / 2
            p.rect(x0, y, w, 1, bark)
            p.rect(x0, y, max(1, w / 5), 1, barkLight)                  // lit left edge
            p.rect(x0 + w - max(1, w / 4), y, max(1, w / 4), 1, barkDark) // shaded right edge
        }
        // Little curled roots poking out at the base.
        for (dx, dir) in [(-width(base) / 2 - 2, -1), (width(base) / 2 + 1, 1)] {
            p.rects([(cx + dx, base - 1, 2, 2), (cx + dx + dir, base, 2, 1)], ink)
            p.rect(cx + dx + (dir < 0 ? 1 : 0), base - 1, 1, 1, bark)
        }
        // Soft bark lines.
        for (i, y) in stride(from: top + 4, to: base - 4, by: 5).enumerated() {
            let w = width(y); p.rect(cx - w / 2 + 2 + (i % 2) * (w / 3), y, 1, 3, barkDark)
        }
        if let hy = heartY {
            p.rects([(cx - 2, hy, 1, 1), (cx, hy, 1, 1), (cx - 3, hy + 1, 5, 1), (cx - 2, hy + 2, 3, 1), (cx - 1, hy + 3, 1, 1)], Color(hex: 0xE58A9A))
        }
    }

    static let oakLobes: [(Int, Int, Int)] = [
        (-30, -38, 9), (30, -39, 9), (-16, -36, 10), (0, -35, 11), (16, -36, 10),
        (-22, -48, 12), (-7, -52, 13), (8, -52, 13), (22, -48, 12),
        (-13, -62, 10), (2, -64, 11), (16, -61, 9)
    ]

    static func townTree(_ p: Painter, t: Double) {
        let cx = oakCenter.x, base = oakCenter.base
        let barkDark = Color(hex: 0x6B4E34)

        p.rect(cx - 30, base + 1, 62, 2, shadow)
        cuteTrunk(p, cx: cx, top: base - 34, base: base - 1, topW: 9, baseW: 17, heartY: base - 17)
        oakCanopy(p, lobes: oakLobes.map { (cx + $0.0, base + $0.1, $0.2) }, bottom: base - 25)
        // Lanterns hanging from the canopy's edge.
        for lx in [cx - 24, cx + 24] {
            p.rect(lx, base - 30, 1, 4, ink)
            box(p, lx - 1, base - 26, 3, 4, Color(hex: 0xFFE38A))
        }
        for i in 0..<2 {
            let k = (t * 0.25 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            p.dot(cx - 18 + i * 36 + Int(sin(k * 9) * 3), base - 24 + Int(k * 24), season == .autumn ? Color(hex: 0xF2A93B) : oakGreens.3)
        }
        box(p, cx + 9, base - 4, 13, 3, Color(hex: 0x9A6340))
        p.rect(cx + 10, base - 1, 2, 2, barkDark); p.rect(cx + 19, base - 1, 2, 2, barkDark)
        let bob = Int(t * 1.3) % 5 == 0 ? -1 : 0
        p.sprite(Sprites.mayor, x: cx - 27, y: base - 16 + bob)
    }

    static func oakLights(_ p: Painter, strength: Double) {
        let cx = Double(oakCenter.x), base = Double(oakCenter.base)
        for lx in [cx - 23.5, cx + 24.5] { p.glow(lx, base - 24, radius: 9, warm, 0.6 * strength) }
    }

    /// A thick straight branch drawn as stacked squares.
    static func limb(_ p: Painter, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ w: Int, _ color: Color) {
        let n = max(abs(x1 - x0), abs(y1 - y0))
        for i in 0...n {
            let x = x0 + (x1 - x0) * i / max(n, 1), y = y0 + (y1 - y0) * i / max(n, 1)
            p.rect(x - w / 2 - 1, y - w / 2 - 1, w + 2, w + 2, ink)
        }
        for i in 0...n {
            let x = x0 + (x1 - x0) * i / max(n, 1), y = y0 + (y1 - y0) * i / max(n, 1)
            p.rect(x - w / 2, y - w / 2, w, w, color)
        }
    }
}
