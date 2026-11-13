import SwiftUI

/// A short opening scene while the town gets ready behind it: a little window onto the sky
/// where Pip trots along with the post, the name, and a pixel loading bar. It starts on the same
/// plum as the system launch screen, so opening the app never flashes white.
struct SplashView: View {
    let phase: DayPhase
    /// Called once the bar is full; the parent fades this view away (the window grows as it goes).
    var done: () -> Void

    @State private var start = Date()
    @State private var leaving = false
    private static let length: Double = 1.35

    private let lines = [
        "Waking up the village…",
        "Pip is sorting the post…",
        "Bea is warming the kettle…",
        "Watering the plants…"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let k = min(1, max(0, t / Self.length))
            ZStack {
                Theme.ink.ignoresSafeArea()
                VStack(spacing: 22) {
                    window(t: t)
                        .frame(width: 236, height: 150)
                        .overlay(Rectangle().strokeBorder(Theme.cream, lineWidth: 3))
                        .background(Rectangle().fill(Color.black.opacity(0.35)).offset(x: 5, y: 5))
                        .scaleEffect(leaving ? 1.6 : (t < 0.25 ? 0.92 + t * 0.32 : 1))
                    Text("Workdoro")
                        .font(.pixel(30, .heavy))
                        .foregroundStyle(Theme.cream)
                        .shadow(color: Color(hex: 0xC65F4A), radius: 0, x: 2, y: 2)
                    VStack(spacing: 10) {
                        bar(k)
                        Text(lines[Int(Date().timeIntervalSince1970 / 60) % lines.count])
                            .font(.pixel(12, .semibold))
                            .foregroundStyle(Theme.cream.opacity(0.75))
                    }
                }
                .opacity(min(1, t * 6))
            }
            .onChange(of: k >= 1) { _, full in
                guard full, !leaving else { return }
                withAnimation(.easeIn(duration: 0.4)) { leaving = true }
                done()
            }
        }
        // Start the clock when the scene is actually on screen, not when the app began loading.
        .onAppear { start = Date() }
        .accessibilityLabel("Workdoro is opening")
    }

    /// Six chunky segments, like the progress bars on the town cards.
    private func bar(_ k: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { i in
                Rectangle()
                    .fill(Double(i) < k * 6 ? Theme.gold : Theme.cream.opacity(0.18))
                    .frame(width: 22, height: 8)
            }
        }
    }

    /// The little view of the sky: stars or clouds, rolling hills, and Pip walking with a letter.
    private func window(t: Double) -> some View {
        let cols = 59, rows = 37
        let phase = phase
        return PixelCanvas(cols: cols, rows: rows, s: 4, frame: t) { p in
            do {
                let sky: [UInt32] = switch phase {
                case .day: [0x8EC9F2, 0xA9D8F5, 0xC4E6F8, 0xDDF1FB]
                case .dusk: [0x6B5CC8, 0x9C78C0, 0xE79A86, 0xF8CDA0]
                case .night: [0x1E1B4B, 0x2A2860, 0x383574, 0x4A4488]
                }
                // Banded pixel sky.
                for (i, c) in sky.enumerated() {
                    p.rect(0, i * rows / 6, cols, rows / 6 + 1, Color(hex: c))
                }
                p.rect(0, 4 * rows / 6, cols, rows, Color(hex: sky[3]))
                if phase == .night {
                    for i in 0..<14 {
                        let x = noise(i, 3) % cols, y = noise(i, 7) % (rows / 2)
                        guard (noise(i, 11) + Int(t * 3)) % 5 != 0 else { continue }
                        p.dot(x, y, .white.opacity(i % 3 == 0 ? 0.95 : 0.6))
                    }
                    p.rect(cols - 12, 4, 4, 4, Color(hex: 0xFFF4C8))
                    p.rect(cols - 11, 4, 3, 3, Color(hex: sky[0]))
                } else {
                    p.rect(cols - 13, 5, 5, 5, Color(hex: phase == .day ? 0xFFE38A : 0xFFB878))
                    for i in 0..<3 {
                        let x = Int((Double(noise(i, 5) % cols) + t * Double(3 + i)).truncatingRemainder(dividingBy: Double(cols + 14))) - 10
                        let y = 4 + i * 6
                        let w = 8 + noise(i, 9) % 5
                        p.rect(x, y, w, 2, .white.opacity(0.92))
                        p.rect(x + 2, y - 1, w / 2, 1, .white.opacity(0.92))
                    }
                }
                // Hills and grass.
                let night = phase == .night
                for x in 0..<cols {
                    let h = Int(4 + 3 * sin(Double(x) * 0.12) + 2 * sin(Double(x) * 0.31 + 1))
                    p.rect(x, rows - 14 - h, 1, h, Color(hex: night ? 0x2E4A3E : 0x6FAE5C))
                }
                p.rect(0, rows - 14, cols, 14, Color(hex: night ? 0x3B5E48 : 0x8CC56C))
                p.rect(0, rows - 14, cols, 1, Color(hex: night ? 0x4E7558 : 0xA6D682))
                for i in 0..<16 {
                    let x = noise(i, 13) % cols, y = rows - 12 + noise(i, 17) % 10
                    p.dot(x, y, Color(hex: [0xFFFFFF, 0xFFE38A, 0xF49AC1][i % 3]).opacity(night ? 0.5 : 0.9))
                }
                // Pip trots across with the post, and loops around.
                let span = Double(cols + 20)
                let x = Int((t * 22).truncatingRemainder(dividingBy: span)) - 18
                let ground = rows - 6
                p.rect(x + 3, ground, 10, 1, Color.black.opacity(0.18))
                let hop = Int(t * 8) % 2
                p.walking(Sprites.pip, x: x, y: ground - 16 - hop, flip: false, frame: Int(t * 8))
                p.sprite(Sprites.envelope, x: x + 13, y: ground - 10 - hop)
                if night {
                    p.glow(Double(x + 8), Double(ground - 8), radius: 14, Color(hex: 0xFFD27A), 0.25)
                }
            }
        }
    }
}
