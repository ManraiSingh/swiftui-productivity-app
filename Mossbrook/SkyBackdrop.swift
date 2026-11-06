import SwiftUI

/// The open sky above the world, seen when you zoom out. One smooth gradient that lands
/// exactly on the town's own sky colour where the world begins, so there's no seam,
/// with a few pixel stars at night and soft pixel clouds by day.
struct SkyBackdrop: View {
    let phase: DayPhase
    let weather: Weather
    /// Size of one art pixel in points, so stars and clouds match the world.
    let pixel: CGFloat
    /// Where the top of the world sits on screen.
    let horizon: CGFloat
    var paused = false

    private var gloomy: Bool { weather == .rain || weather == .snow }

    /// From the top of the screen down to the hills: one sky, top to horizon.
    private var colors: [UInt32] {
        switch phase {
        case .day where gloomy: [0x7A889A, 0x9AA8B8, 0xB0BCC8, 0xC6CED6]
        case .dusk where gloomy: [0x4E4264, 0x7A6E8A, 0x9C8A98, 0xB8A8A8]
        case .day: [0x5AAED8, 0x9ED6EC, 0xB5E1EF, 0xD4EEF2]
        case .dusk: [0x3E3470, 0x8E6FA6, 0xE79A86, 0xF8CDA0]
        case .night: [0x0A0C20, 0x161B3A, 0x1F2550, 0x2E3568]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: paused)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let p = max(pixel, 1)
                let c = colors
                // The world's hills sit about 50 art pixels below its top edge.
                let hz = max(horizon + 52 * p, 1)
                func stop(_ y: CGFloat) -> CGFloat { min(max(y / hz, 0.001), 0.999) }
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: hz + 2)),
                         with: .linearGradient(Gradient(stops: [
                            .init(color: Color(hex: c[0]), location: 0),
                            .init(color: Color(hex: c[1]), location: stop(horizon)),
                            .init(color: Color(hex: c[2]), location: stop(horizon + 28 * p)),
                            .init(color: Color(hex: c[3]), location: 1)
                         ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: hz)))
                ctx.fill(Path(CGRect(x: 0, y: hz, width: size.width, height: max(size.height - hz, 0))), with: .color(Color(hex: c[3])))
                let h = max(horizon, 1)
                // Forest floor behind the bottom cards.
                ctx.fill(Path(CGRect(x: 0, y: size.height * 0.8, width: size.width, height: size.height * 0.2)),
                         with: .color(Color(hex: 0x1F3426)))

                let cols = Int(size.width / p) + 1
                let rows = max(Int(h / p) - 2, 1)
                if phase == .night {
                    for i in 0..<(cols * rows / 450) {
                        let x = noise(i, 7) % max(cols, 1), y = noise(i, 13) % rows
                        guard (noise(i, 3) + Int(t * 1.5)) % 7 != 0 else { continue }
                        ctx.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p, height: p)),
                                 with: .color(.white.opacity(noise(i, 5) % 3 == 0 ? 0.85 : 0.4)))
                    }
                } else if rows > 12 {
                    let tint: Color = gloomy ? Color(hex: 0xE2E6EC) : (phase == .day ? .white : Color(hex: 0xFFE6D2))
                    for i in 0..<(gloomy ? 6 : 4) {
                        let span = Double(cols + 40)
                        let x = Int((Double(noise(i, 31) % max(cols, 1)) + t * (0.8 + Double(i % 3) * 0.4)).truncatingRemainder(dividingBy: span)) - 20
                        let y = rows * (20 + i * 18) / 100
                        let w = 10 + noise(i, 37) % 10
                        for (dx, dy, cw, ch) in [(0, 0, w, 3), (2, -2, w / 2, 2), (w / 2, -1, w / 3, 1)] {
                            ctx.fill(Path(CGRect(x: CGFloat(x + dx) * p, y: CGFloat(y + dy) * p, width: CGFloat(cw) * p, height: CGFloat(ch) * p)),
                                     with: .color(tint.opacity(0.92)))
                        }
                    }
                }
            }
        }
    }
}
