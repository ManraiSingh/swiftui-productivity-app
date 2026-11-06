import SwiftUI

// MARK: - Plants

/// Six kinds of plant. Each habit grows one.
enum PlantSpecies: Int, CaseIterable {
    case sunflower, tulip, monstera, cactus, tomato, lavender

    var name: String {
        ["Sunflower", "Tulip", "Monstera", "Cactus", "Tomato", "Lavender"][rawValue]
    }
}

/// Draws potted plants in a 3/4 view: round pots, shaded leaves, layered depth.
enum PlantRenderer {
    static let ink = Color(hex: 0x2B2233)

    struct Shade {
        let outline: Color
        let dark: Color
        let mid: Color
        let light: Color
    }

    static func greens(_ thirsty: Bool) -> Shade {
        thirsty
            ? Shade(outline: Color(hex: 0x4A4A26), dark: Color(hex: 0x7C7B40), mid: Color(hex: 0x9E9C58), light: Color(hex: 0xC0BD7C))
            : Shade(outline: Color(hex: 0x23412B), dark: Color(hex: 0x3F7A3E), mid: Color(hex: 0x5FA552), light: Color(hex: 0x95D271))
    }

    // MARK: Primitives

    static func ellipse(_ p: Painter, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Color) {
        guard rx > 0.2, ry > 0.2 else { return }
        let y0 = Int((cy - ry).rounded(.down)), y1 = Int((cy + ry).rounded(.up))
        for y in y0...y1 {
            let dy = (Double(y) + 0.5 - cy) / ry
            guard abs(dy) <= 1 else { continue }
            let half = rx * (1 - dy * dy).squareRoot()
            let xa = Int((cx - half).rounded()), xb = Int((cx + half).rounded())
            if xb > xa { p.rect(xa, y, xb - xa, 1, c) }
        }
    }

    static func line(_ p: Painter, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: Color, width: Int = 1) {
        let n = max(1, Int(max(abs(x1 - x0), abs(y1 - y0)).rounded(.up)))
        for i in 0...n {
            let k = Double(i) / Double(n)
            p.rect(Int((x0 + (x1 - x0) * k).rounded(.down)), Int((y0 + (y1 - y0) * k).rounded(.down)), width, width, c)
        }
    }

    /// A lens-shaped leaf growing from (bx, by) toward `angle` (0 = right, -π/2 = up), outlined and lit from above.
    static func leaf(_ p: Painter, _ bx: Double, _ by: Double, angle: Double, length L: Double, width W: Double, shade: Shade, front: Bool, veins: Bool = false) {
        guard L > 1 else { return }
        let dx = cos(angle), dy = sin(angle)
        let px = -dy, py = dx
        let tx = bx + dx * L, ty = by + dy * L
        let minX = Int((min(bx, tx) - W - 2).rounded(.down)), maxX = Int((max(bx, tx) + W + 2).rounded(.up))
        let minY = Int((min(by, ty) - W - 2).rounded(.down)), maxY = Int((max(by, ty) + W + 2).rounded(.up))
        let body = front ? shade.mid : shade.dark
        let lit = front ? shade.light : shade.mid
        for y in minY...maxY {
            for x in minX...maxX {
                let rx = Double(x) + 0.5 - bx, ry = Double(y) + 0.5 - by
                let u = rx * dx + ry * dy
                let v = rx * px + ry * py
                let inner = (u >= 0 && u <= L) ? W * sin(.pi * u / L) : -1
                if inner >= 0 && abs(v) <= inner {
                    var c = (v * py < 0) ? lit : body
                    if abs(v) < 0.55 && u > 1.2 && u < L * 0.86 { c = shade.dark }
                    if veins && front {
                        for f in [0.38, 0.62] where abs(u - (f * L + abs(v) * 0.6)) < 0.5 && abs(v) > 1 { c = shade.dark }
                    }
                    p.dot(x, y, c)
                } else {
                    let ou = u + 0.9
                    let outer = (ou >= 0 && ou <= L + 1.8) ? (W + 1) * sin(.pi * ou / (L + 1.8)) : -1
                    if outer >= 0 && abs(v) <= outer { p.dot(x, y, shade.outline) }
                }
            }
        }
    }

    /// A round terracotta pot seen from slightly above. Returns the centre of the soil.
    static func pot(_ p: Painter, cx: Int, base: Int, w: Int = 16, h: Int = 12) -> (x: Double, y: Double) {
        let top = base - h
        let c = Double(cx)
        ellipse(p, c + 2.5, Double(base) + 0.5, Double(w) / 2 + 3, 2.4, Color.black.opacity(0.2))
        for y in (top + 2)...base {
            let k = Double(y - top) / Double(h)
            var half = Double(w) / 2 - k * 2.2
            if y >= base - 1 { half -= Double(y - base + 2) * 0.9 }
            let xa = Int((c - half).rounded()), xb = Int((c + half).rounded())
            let wpx = max(xb - xa, 1)
            p.rect(xa - 1, y, wpx + 2, 1, ink)
            p.rect(xa, y, wpx, 1, Color(hex: 0xC9774A))
            p.rect(xa, y, max(1, wpx / 4), 1, Color(hex: 0xE59D70))
            p.rect(xa + max(1, wpx / 4), y, 1, 1, Color(hex: 0xF0B48A))
            p.rect(xb - max(1, wpx / 3), y, max(1, wpx / 3), 1, Color(hex: 0xA65E3B))
        }
        p.rect(cx - w / 2 + 3, base + 1, w - 6, 1, ink)
        p.rect(cx - w / 2 + 1, top + 4, w - 2, 1, Color(hex: 0x8E4E30).opacity(0.55))
        ellipse(p, c, Double(top) + 1.5, Double(w) / 2 + 1.6, 3.4, ink)
        ellipse(p, c, Double(top) + 1.5, Double(w) / 2 + 0.6, 2.6, Color(hex: 0xE59D70))
        ellipse(p, c, Double(top) + 1.3, Double(w) / 2 - 1.2, 1.7, Color(hex: 0x5A3E2B))
        ellipse(p, c, Double(top) + 0.9, Double(w) / 2 - 2.2, 0.9, Color(hex: 0x3E2A1E))
        return (c, Double(top) + 1.5)
    }

    static let growth: [Double] = [0, 0.34, 0.48, 0.62, 0.76, 0.9, 1.0]

    // MARK: Plants

    static func draw(_ p: Painter, species: PlantSpecies, stage: Int, thirsty: Bool, x: Int, base: Int, t: Double, seed: Int) {
        let soil = pot(p, cx: x, base: base)
        let sx = soil.x, sy = soil.y
        let stage = min(max(stage, 0), 6)
        guard stage > 0 else {
            ellipse(p, sx, sy - 0.5, 2.6, 1.3, Color(hex: 0x7A5636))
            p.dot(Int(sx), Int(sy) - 1, Color(hex: 0xC9A27A))
            p.dot(Int(sx) + 3, Int(sy) - 6, Color(hex: 0x6B4A2E))
            p.rect(Int(sx) + 3, Int(sy) - 5, 1, 5, Color(hex: 0x8A6A4A))
            p.rect(Int(sx) + 1, Int(sy) - 8, 5, 3, Color(hex: 0xF6E7C8))
            return
        }
        let g = greens(thirsty)
        let m = growth[stage]
        let sway = sin(t * 1.1 + Double(seed) * 1.7) * 0.05
        let droop = thirsty ? 0.3 : 0.0
        func bend(_ a: Double) -> Double { a + sway + droop * (a > -.pi / 2 ? 1 : -1) }

        switch species {
        case .monstera:
            let n = 2 + stage
            for i in 0..<n {
                let k = Double(i) / Double(max(n - 1, 1))
                let a = bend(-.pi / 2 + (k - 0.5) * 2.4)
                let stemL = (5 + 11 * m) * (0.8 + 0.2 * Double(noise(seed, i) % 3))
                let ex = sx + cos(a) * stemL, ey = sy - 1 + sin(a) * stemL
                line(p, sx, sy - 1, ex, ey, g.dark)
                leaf(p, ex, ey, angle: a + (k - 0.5) * 0.5, length: 6 + 9 * m, width: 3 + 3.5 * m, shade: g, front: i % 2 == 1 || i == n / 2, veins: stage >= 3)
            }

        case .sunflower:
            let H = 6 + 26 * m
            let topX = sx + sin(sway * 3) * 2 + (thirsty ? 2 : 0)
            let topY = sy - H
            line(p, sx, sy, topX, topY, g.outline, width: 2)
            line(p, sx + 0.5, sy, topX + 0.5, topY, g.dark)
            let pairs = max(1, min(stage, 4))
            for j in 0..<pairs {
                let f = 0.2 + 0.6 * Double(j) / Double(max(pairs, 1))
                let lx = sx + (topX - sx) * f, ly = sy - H * f
                let len = (5 + 6 * m) * (1.1 - f * 0.4)
                leaf(p, lx, ly, angle: bend(-.pi + 0.45), length: len, width: 2.3 + 2.2 * m, shade: g, front: j % 2 == 0)
                leaf(p, lx, ly, angle: bend(-0.45), length: len, width: 2.3 + 2.2 * m, shade: g, front: j % 2 == 1)
            }
            if stage == 4 {
                ellipse(p, topX, topY - 1.5, 3.2, 3.6, g.outline)
                ellipse(p, topX, topY - 1.5, 2.3, 2.8, g.mid)
                p.dot(Int(topX) - 1, Int(topY) - 3, g.light)
            } else if stage >= 5 {
                let r = stage == 6 ? 7.0 : 5.5
                let yellow = thirsty ? Color(hex: 0xD8C060) : Color(hex: 0xF7C93E)
                let gold = thirsty ? Color(hex: 0xB8A048) : Color(hex: 0xE0A21E)
                for k in 0..<12 {
                    let a = Double(k) / 12 * 2 * .pi
                    let pxp = topX + cos(a) * r * 0.78, pyp = topY - r * 0.6 + sin(a) * r * 0.66
                    ellipse(p, pxp, pyp, 2.4, 1.9, Color(hex: 0x9A6A1E))
                    ellipse(p, pxp, pyp, 1.7, 1.3, k % 2 == 0 ? yellow : gold)
                }
                ellipse(p, topX, topY - r * 0.6, r * 0.55, r * 0.5, Color(hex: 0x4A2A14))
                ellipse(p, topX, topY - r * 0.6, r * 0.45, r * 0.4, Color(hex: 0x6B3F1F))
                for d in 0..<5 { p.dot(Int(topX) - 2 + noise(seed, d) % 4, Int(topY - r * 0.6) - 1 + noise(d, seed) % 3, Color(hex: 0x9A6A3A)) }
            }

        case .tulip:
            let blades = 2 + min(stage, 3)
            for i in 0..<blades {
                let side = i % 2 == 0 ? -1.0 : 1.0
                let a = bend(-.pi / 2 + side * (0.25 + 0.2 * Double(i / 2)))
                leaf(p, sx + side, sy - 1, angle: a, length: 6 + 13 * m, width: 1.5 + 1.3 * m, shade: g, front: i >= 2)
            }
            let flowers = stage == 6 ? [(-4.0, 0.85), (0.0, 1.0), (4.0, 0.78)] : [(0.0, 1.0)]
            for (dx, hf) in flowers {
                let fx = sx + dx + sway * 10, fy = sy - (8 + 20 * m) * hf
                line(p, sx + dx * 0.3, sy - 1, fx, fy, g.dark)
                if stage == 4 {
                    ellipse(p, fx, fy - 2, 2.4, 3.2, g.outline)
                    ellipse(p, fx, fy - 2, 1.6, 2.4, Color(hex: 0xC9D98A))
                    p.dot(Int(fx), Int(fy) - 4, Color(hex: 0xF2668B))
                } else if stage >= 5 {
                    let petal = thirsty ? Color(hex: 0xD49AA9) : Color(hex: 0xF2668B)
                    let petalLight = thirsty ? Color(hex: 0xE6BCC6) : Color(hex: 0xF9A3BA)
                    let petalDark = thirsty ? Color(hex: 0xB07C8A) : Color(hex: 0xC2406A)
                    ellipse(p, fx, fy - 3, 4.2, 4.8, ink)
                    ellipse(p, fx, fy - 3, 3.3, 3.9, petal)
                    ellipse(p, fx - 1.2, fy - 3.5, 1.3, 2.4, petalLight)
                    ellipse(p, fx + 2, fy - 2.5, 1, 2.2, petalDark)
                    for tip in [-2, 0, 2] {
                        p.dot(Int(fx) + tip, Int(fy) - 8, ink)
                        p.dot(Int(fx) + tip, Int(fy) - 7, tip == 0 ? petalLight : petal)
                    }
                }
            }

        case .cactus:
            let h = 4 + 20 * m
            let w = 4.5 + 6 * m
            let lean = thirsty ? 1.0 : 0.0
            func column(_ cx: Double, _ bottom: Double, _ height: Double, _ width: Double) {
                let topY = Int((bottom - height).rounded())
                for y in topY...Int(bottom) {
                    let fromTop = Double(y - topY)
                    let half = width / 2 * (fromTop < 2.5 ? (0.55 + fromTop * 0.18) : 1)
                    let xshift = lean * (bottom - Double(y)) / max(height, 1)
                    let xa = Int((cx - half + xshift).rounded()), xb = Int((cx + half + xshift).rounded())
                    let wpx = max(xb - xa, 1)
                    p.rect(xa - 1, y, wpx + 2, 1, g.outline)
                    p.rect(xa, y, wpx, 1, g.mid)
                    p.rect(xa, y, max(1, wpx / 3), 1, g.light)
                    p.rect(xb - max(1, wpx / 3), y, max(1, wpx / 3), 1, g.dark)
                    if wpx >= 5 { p.dot(xa + wpx / 2, y, g.dark) }
                    if (y - topY) % 3 == 1 && wpx >= 4 {
                        p.dot(xa + 1, y, Color.white.opacity(0.85))
                        p.dot(xb - 2, y, Color.white.opacity(0.7))
                    }
                }
                p.rect(Int(cx - width / 2 * 0.55), topY - 1, max(1, Int(width * 0.55)), 1, g.outline)
            }
            if stage >= 3 {
                column(sx - w / 2 - 2, sy - h * 0.35, 4 + 5 * m, 3.4)
                p.rect(Int(sx - w / 2 - 2), Int(sy - h * 0.35), Int(w / 2) + 2, 2, g.mid)
            }
            if stage >= 4 {
                column(sx + w / 2 + 2, sy - h * 0.5, 3 + 4 * m, 3)
                p.rect(Int(sx), Int(sy - h * 0.5), Int(w / 2) + 2, 2, g.dark)
            }
            column(sx, sy, h, w)
            if stage >= 5 {
                let flowers = stage == 6 ? [-1.5, 1.5] : [0.0]
                for f in flowers {
                    let fx = sx + f + lean, fy = sy - h - 1
                    ellipse(p, fx, fy, 2.8, 1.9, ink)
                    ellipse(p, fx, fy, 2.1, 1.3, thirsty ? Color(hex: 0xD9A7BA) : Color(hex: 0xF57FA8))
                    p.dot(Int(fx), Int(fy), Color(hex: 0xFFE38A))
                }
            }

        case .tomato:
            let H = 6 + 20 * m
            line(p, sx + 4, sy, sx + 4, sy - H - 3, Color(hex: 0x6B4A2E))
            line(p, sx + 5, sy, sx + 5, sy - H - 3, Color(hex: 0x8A6A4A))
            line(p, sx, sy, sx + sway * 8, sy - H, g.dark)
            let n = 3 + stage * 2
            for i in 0..<n {
                let k = Double(i) / Double(max(n - 1, 1))
                let hy = sy - H * (0.3 + 0.7 * Double(noise(seed + i, 5) % 10) / 10)
                let a = bend(-.pi + k * .pi + (Double(noise(i, seed) % 5) - 2) * 0.1)
                leaf(p, sx + sway * 6, hy, angle: a, length: 4 + 4.5 * m, width: 2 + 1.6 * m, shade: g, front: i % 3 != 0)
            }
            if stage >= 5 {
                for (j, spot) in [(-4.0, 0.45), (3.0, 0.62), (-1.0, 0.78), (5.0, 0.35)].enumerated() where j < (stage == 6 ? 4 : 3) {
                    let fx = sx + spot.0, fy = sy - H * spot.1
                    if stage == 5 {
                        ellipse(p, fx, fy, 1.6, 1.6, Color(hex: 0x5E7A2E))
                        ellipse(p, fx, fy, 1.1, 1.1, Color(hex: 0x9CC75A))
                    } else {
                        ellipse(p, fx, fy, 2.6, 2.4, Color(hex: 0x7A1E18))
                        ellipse(p, fx, fy, 2, 1.8, thirsty ? Color(hex: 0xB86A5A) : Color(hex: 0xE0473A))
                        p.dot(Int(fx) - 1, Int(fy) - 1, Color(hex: 0xFF9C8A))
                        p.dot(Int(fx), Int(fy) - 2, g.dark)
                    }
                }
            } else if stage == 4 {
                for (dx, f) in [(-3.0, 0.5), (3.0, 0.7)] { p.dot(Int(sx + dx), Int(sy - H * f), Color(hex: 0xFFE38A)) }
            }

        case .lavender:
            let blue = Shade(outline: g.outline, dark: Color(hex: 0x5E7A5A), mid: Color(hex: 0x86A27E), light: Color(hex: 0xB3C9A6))
            for i in 0..<4 {
                let side = i % 2 == 0 ? -1.0 : 1.0
                leaf(p, sx, sy - 1, angle: bend(-.pi / 2 + side * (0.6 + 0.3 * Double(i / 2))), length: 4 + 4 * m, width: 1.1, shade: thirsty ? g : blue, front: i >= 2)
            }
            let stems = 3 + stage
            for i in 0..<stems {
                let k = Double(i) / Double(max(stems - 1, 1))
                let a = bend(-.pi / 2 + (k - 0.5) * 0.9)
                let L = (6 + 18 * m) * (0.82 + 0.18 * Double(noise(seed, i + 3) % 3) / 2)
                let ex = sx + cos(a) * L, ey = sy - 1 + sin(a) * L
                line(p, sx, sy - 1, ex, ey, Color(hex: 0x6E8B5E))
                if stage >= 4 {
                    let spike = stage == 4 ? 3 : 6
                    for s in 0..<spike {
                        let f = 1 - Double(s) / Double(L)
                        let qx = sx + cos(a) * L * f, qy = sy - 1 + sin(a) * L * f
                        let c = s % 2 == 0 ? (thirsty ? Color(hex: 0xA99BBF) : Color(hex: 0x8E6CCB)) : (thirsty ? Color(hex: 0xC4B8D6) : Color(hex: 0xB89BE6))
                        p.rect(Int(qx) - 1, Int(qy), 3, 1, c)
                        p.dot(Int(qx) - 1, Int(qy), Color(hex: 0x6A4E9A))
                    }
                } else {
                    p.dot(Int(ex), Int(ey), Color(hex: 0x9CC75A))
                }
            }
        }
    }
}

