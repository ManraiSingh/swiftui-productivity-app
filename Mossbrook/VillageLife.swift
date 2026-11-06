import SwiftUI

/// Something that happened because you tapped the village.
struct VillageEffect: Identifiable {
    enum Kind {
        case quack(duck: Int)
        case shake(tree: Int)
        case star(x: Double, y: Double)
    }

    let id = UUID()
    let kind: Kind
    let start: Double
}

/// Little bits of life around the village: birds, a balloon, fish, butterflies, weather and stars.
extension VillageRenderer {
    static func duckPosition(_ i: Int, t: Double) -> CGPoint {
        let (dx, dy) = (Double(lakeOff.0), Double(lakeOff.1))
        return i == 0
            ? CGPoint(x: 10 + 4 * sin(t * 0.25) + 4 + dx, y: 210 + dy)
            : CGPoint(x: 22 + 3 * sin(t * 0.2 + 2) + 4 + dx, y: 217 + dy)
    }

    // MARK: Sky

    static func skyLife(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect]) {
        let night = state.phase == .night
        let gloomy = weather == .rain || weather == .snow

        // A hot-air balloon drifts across now and then.
        let balloonCycle = t.truncatingRemainder(dividingBy: 150)
        if !night && !gloomy && balloonCycle < 75 {
            let bx = Int(-16 + balloonCycle * Double(W + 32) / 75)
            let by = 14 + Int(2 * sin(t * 0.5))
            p.rect(bx + 1, by + 9, 1, 4, ink)
            p.rect(bx + 7, by + 9, 1, 4, ink)
            box(p, bx + 2, by + 13, 5, 3, Color(hex: 0xA8796A))
            for dy in -6...6 {
                let half = Int((Double(36 - dy * dy)).squareRoot().rounded())
                p.rect(bx + 4 - half - 1, by + 3 + dy, half * 2 + 3, 1, ink)
            }
            for dy in -5...5 {
                let half = Int((Double(30 - dy * dy)).squareRoot().rounded())
                for x in (bx + 4 - half)...(bx + 4 + half) {
                    let stripe = ((x - bx + 8) / 2) % 2 == 0
                    p.dot(x, by + 3 + dy, stripe ? Color(hex: 0xD9534F) : Color(hex: 0xFFF6E5))
                }
            }
            p.rect(bx + 2, by - 1, 2, 2, Color.white.opacity(0.5))
        }

        // A little flock of birds.
        let flockCycle = t.truncatingRemainder(dividingBy: 26)
        if !night && weather != .rain && flockCycle < 13 {
            let fx = Int(Double(W + 12) - flockCycle * Double(W + 30) / 13)
            let flap = Int(t * 6) % 2 == 0
            for (i, off) in [(0, 0), (5, -3), (5, 3), (10, -6), (10, 6)].enumerated() {
                let x = fx + off.0
                let y = 18 + off.1 + Int(2 * sin(t + Double(i)))
                let c = Color(hex: 0x3A3550)
                if flap {
                    p.dot(x - 1, y - 1, c); p.dot(x, y, c); p.dot(x + 1, y - 1, c)
                } else {
                    p.dot(x - 1, y, c); p.dot(x, y, c); p.dot(x + 1, y, c)
                }
            }
        }
    }

    static func nightLife(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect]) {
        guard state.phase == .night, weather != .rain else { return }
        // A shooting star every so often.
        let cycle = t.truncatingRemainder(dividingBy: 14)
        if cycle < 0.9 {
            let n = Int(t / 14)
            shootingStar(p, x: Double(30 + noise(n, 3) % (W - 40)), y: Double(4 + noise(n, 5) % 16), k: cycle / 0.9)
        }
        for e in effects {
            if case .star(let x, let y) = e.kind, t - e.start < 1 {
                shootingStar(p, x: x, y: y, k: (t - e.start))
            }
        }
    }

    static func shootingStar(_ p: Painter, x: Double, y: Double, k: Double) {
        let headX = x - k * 30
        let headY = y + k * 14
        for i in 0..<8 {
            let tx = Int(headX + Double(i) * 2)
            let ty = Int(headY - Double(i) * 0.9)
            p.dot(tx, ty, Color.white.opacity((1 - Double(i) / 8) * (1 - k * 0.6)))
        }
        p.glow(headX, headY, radius: 3, .white, 0.7 * (1 - k))
    }

    // MARK: Lake

    static func lakeLife(_ p: Painter, t: Double, effects: [VillageEffect]) {
        // A fish jumps.
        let cycle = t.truncatingRemainder(dividingBy: 9)
        let n = Int(t / 9)
        let fx = 6 + noise(n, 11) % 22
        if cycle < 0.9 {
            let k = cycle / 0.9
            let y = 214 - Int(sin(k * .pi) * 8)
            let x = fx + Int(k * 6)
            p.rect(x, y, 3, 2, Color(hex: 0xF2A65A))
            p.dot(x + 3, y + (k < 0.5 ? 1 : 0), Color(hex: 0xF2A65A))
            p.dot(x, y, ink)
        } else if cycle < 2 {
            let r = Int((cycle - 0.9) * 4)
            p.rect(fx + 6 - r, 214, 2 * r + 2, 1, waterLight.opacity(1 - (cycle - 0.9)))
        }

        for e in effects {
            if case .quack(let duck) = e.kind, t - e.start < 1.4 {
                let abs = duckPosition(duck, t: t)
                let pos = CGPoint(x: abs.x - Double(lakeOff.0), y: abs.y - Double(lakeOff.1))
                let r = Int((t - e.start) * 6)
                p.rect(Int(pos.x) - 3 - r, Int(pos.y) + 3, 6 + 2 * r, 1, waterLight.opacity(1 - (t - e.start) / 1.4))
            }
        }
    }

    // MARK: Ground

    static func groundLife(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect]) {
        // Butterflies over the garden on calm days.
        if state.phase == .day && (weather == .clear || weather == .petals || weather == .leaves) {
            for i in 0..<2 {
                let x = 18 + 10 * sin(t * 0.6 + Double(i) * 3) + 4 * sin(t * 1.7 + Double(i))
                let y = 237 + 5 * sin(t * 0.9 + Double(i) * 2)
                let wing = Int(t * 8 + Double(i)) % 2 == 0
                let c = i == 0 ? Color(hex: 0xFFE38A) : Color(hex: 0xFFFFFF)
                p.dot(Int(x), Int(y), ink)
                if wing {
                    p.dot(Int(x) - 1, Int(y) - 1, c); p.dot(Int(x) + 1, Int(y) - 1, c)
                } else {
                    p.dot(Int(x) - 1, Int(y), c); p.dot(Int(x) + 1, Int(y), c)
                }
            }
        }

        // Apples tumble out of a tree you tapped.
        for e in effects {
            guard case .shake(let index) = e.kind, index < treeSpots.count else { continue }
            let age = t - e.start
            guard age < 3 else { continue }
            let spot = treeSpots[index]
            let fall = min(1, age / 0.5)
            let x = spot.0 + 3 + (noise(index, 2) % 4)
            let y = spot.1 + 4 + Int(fall * fall * 9) - (fall >= 1 && age < 0.7 ? 1 : 0)
            let fade = age > 2.4 ? (3 - age) / 0.6 : 1
            let color = season == .autumn ? Color(hex: 0xD9824A) : Color(hex: 0xD9534F)
            p.rect(x, y, 2, 2, color.opacity(fade))
            p.dot(x + 1, y - 1, Color(hex: 0x5E9E58).opacity(fade))
        }
    }

    static func mailboxSparkle(_ p: Painter, t: Double, state: SceneState) {
        guard state.dailyLetter else { return }
        let k = (t * 1.2).truncatingRemainder(dividingBy: 1)
        let c = Color(hex: 0xFFF3B0).opacity(1 - k)
        let x = 73 + (Int(t * 1.2) % 2) * 4, y = 93 - Int(k * 3)
        p.dot(x, y, c); p.dot(x - 1, y, c.opacity(0.6)); p.dot(x + 1, y, c.opacity(0.6))
        p.dot(x, y - 1, c.opacity(0.6)); p.dot(x, y + 1, c.opacity(0.6))
        p.glow(Double(x), Double(y), radius: 3, Color(hex: 0xFFE38A), 0.5 * (1 - k))
    }

    // MARK: Weather

    static func weatherParticles(_ p: Painter, t: Double) {
        switch weather {
        case .clear:
            break
        case .rain:
            for i in 0..<130 {
                let speed = 110 + Double(noise(i, 1) % 40)
                let y = Int((Double(noise(i, 2) % H) + t * speed).truncatingRemainder(dividingBy: Double(H)))
                let x = (noise(i, 3) % (W + 20)) - Int(Double(y) * 0.15) + 10
                p.rect(x, y, 1, 3, Color(hex: 0xC8DCF0).opacity(0.55))
            }
            for i in 0..<10 {
                let k = (t * 0.8 + Double(i) * 0.1).truncatingRemainder(dividingBy: 1)
                let x = 8 + noise(i, 21) % (W - 16)
                let y = groundTop + 30 + noise(i, 23) % 200
                let r = Int(k * 3)
                p.rect(x - r, y, 2 * r + 1, 1, Color(hex: 0xC8DCF0).opacity(0.5 * (1 - k)))
            }
        case .snow:
            for i in 0..<140 {
                let speed = 8 + Double(noise(i, 1) % 10)
                let y = Int((Double(noise(i, 2) % H) + t * speed).truncatingRemainder(dividingBy: Double(H)))
                let x = noise(i, 3) % W + Int(3 * sin(t * 0.8 + Double(i)))
                let big = i % 4 == 0
                p.rect(x, y, big ? 2 : 1, big ? 2 : 1, Color.white.opacity(0.9))
            }
        case .petals, .leaves:
            let colors: [UInt32] = weather == .petals
                ? [0xF7B7CF, 0xF49AC1, 0xFFE4EE]
                : [0xD9824A, 0xE8A25A, 0xC65F4A, 0xD9A441]
            for i in 0..<54 {
                let speed = 10 + Double(noise(i, 1) % 8)
                let y = Int((Double(noise(i, 2) % H) + t * speed).truncatingRemainder(dividingBy: Double(H)))
                let drift = (t * 6 + Double(noise(i, 4) % W)).truncatingRemainder(dividingBy: Double(W + 20))
                let x = Int(drift) - 10 + Int(4 * sin(t * 1.3 + Double(i)))
                let c = Color(hex: colors[i % colors.count])
                let flip = Int(t * 3 + Double(i)) % 2 == 0
                p.rect(x, y, flip ? 2 : 1, flip ? 1 : 2, c)
            }
        }
    }
}
