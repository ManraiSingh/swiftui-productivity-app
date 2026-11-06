import SwiftUI
import WidgetKit

// MARK: - Palette

enum WP {
    static let ink = Color(hex: 0x2B2233)
    static let paper = Color(hex: 0xFFF6E5)
    static let card = Color(hex: 0xFFFDF6)
    static let muted = Color(hex: 0x6B5F73)
    static let leaf = Color(hex: 0x6E8B5E)
    static let plum = Color(hex: 0x8E5A8A)
    static let orange = Color(hex: 0xB8612F)
    static let red = Color(hex: 0xC65F4A)
    static let gold = Color(hex: 0xF2C14E)
    static let night = Color(hex: 0x2B2233)
}

enum SkyTime {
    case day, dusk, night

    static var override: SkyTime? {
        switch WidgetSnapshot.load().skyOverride {
        case 0: .day
        case 1: .dusk
        case 2: .night
        default: nil
        }
    }

    static func at(_ date: Date) -> SkyTime {
        if let o = override { return o }
        return switch Calendar.current.component(.hour, from: date) {
        case 6..<17: .day
        case 17..<20: .dusk
        default: .night
        }
    }

    var bands: [UInt32] {
        switch self {
        case .day: [0x9ED6EC, 0xB5E1EF, 0xCDEBEF]
        case .dusk: [0x8E6FA6, 0xE79A86, 0xF6C79A]
        case .night: [0x161B3A, 0x1F2550, 0x2B3166]
        }
    }
}

// MARK: - Pixel scenes

enum Art {
    static let ink = WP.ink

    static func box(_ p: Painter, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ fill: Color) {
        p.rect(x - 1, y - 1, w + 2, h + 2, ink)
        p.rect(x, y, w, h, fill)
    }

    static func disc(_ p: Painter, _ cx: Int, _ cy: Int, _ r: Int, _ c: Color) {
        for dy in -r...r {
            let half = Int((Double(r * r - dy * dy)).squareRoot().rounded())
            p.rect(cx - half, cy + dy, half * 2 + 1, 1, c)
        }
    }

    /// A crescent moon drawn pixel by pixel, so nothing is painted over the glow.
    static func crescent(_ p: Painter, _ cx: Int, _ cy: Int) {
        let r = 3.4, cut = 2.6
        for dy in -4...4 {
            for dx in -4...4 {
                let inMoon = Double(dx * dx + dy * dy) <= r * r
                let inCut = Double((dx - 2) * (dx - 2) + (dy + 1) * (dy + 1)) <= cut * cut
                if inMoon && !inCut { p.dot(cx + dx, cy + dy, Color(hex: 0xF4EBC8)) }
            }
        }
    }

    static func sky(_ p: Painter, w: Int, h: Int, time: SkyTime, seed: Int = 0) {
        let b = time.bands
        p.rect(0, 0, w, h / 3 + 1, Color(hex: b[0]))
        p.rect(0, h / 3, w, h / 3 + 1, Color(hex: b[1]))
        p.rect(0, 2 * h / 3, w, h - 2 * h / 3, Color(hex: b[2]))
        for x in stride(from: 0, to: w, by: 2) {
            p.dot(x, h / 3, Color(hex: b[0]))
            p.dot(x + 1, 2 * h / 3, Color(hex: b[1]))
        }
        switch time {
        case .night:
            for i in 0..<(w / 3) { p.dot(noise(i, 7 + seed) % w, noise(i, 13) % max(h - 2, 1), Color.white.opacity(i % 3 == 0 ? 0.9 : 0.5)) }
            p.glow(Double(w - 12), 8, radius: 8, Color(hex: 0xF4EBC8), 0.35)
            crescent(p, w - 12, 8)
        case .dusk:
            p.glow(Double(w - 14), Double(h - 4), radius: 12, Color(hex: 0xFFB070), 0.7)
            disc(p, w - 14, h - 4, 4, Color(hex: 0xFF9E5E))
        case .day:
            p.glow(Double(w - 12), 8, radius: 9, Color(hex: 0xFFF3B0), 0.6)
            disc(p, w - 12, 8, 3, Color(hex: 0xFFE38A))
            for (cx, cy) in [(8, 6), (30, 11)] {
                p.rect(cx, cy, 11, 2, .white.opacity(0.95))
                p.rect(cx + 2, cy - 2, 6, 2, .white.opacity(0.95))
            }
        }
    }

    static func tree(_ p: Painter, x: Int, y: Int, autumn: Bool) {
        let leafInk = Color(hex: 0x2F4A35)
        let main = autumn ? Color(hex: 0xD9824A) : Color(hex: 0x5E9E58)
        let light = autumn ? Color(hex: 0xE8A25A) : Color(hex: 0x78B86A)
        let dark = autumn ? Color(hex: 0xB0582F) : Color(hex: 0x4C8648)
        p.rect(x + 4, y + 8, 2, 6, Color(hex: 0x7A5236))
        for c in [(x + 1, y + 2, 8, 6), (x + 2, y, 6, 9), (x, y + 3, 10, 4)] { p.rect(c.0 - 1, c.1 - 1, c.2 + 2, c.3 + 2, leafInk) }
        for c in [(x + 1, y + 2, 8, 6), (x + 2, y, 6, 9), (x, y + 3, 10, 4)] { p.rect(c.0, c.1, c.2, c.3, main) }
        p.rect(x + 2, y + 1, 3, 2, light)
        p.rect(x + 1, y + 7, 8, 1, dark)
    }

    /// One little shop on the high street.
    static func shop(_ p: Painter, x: Int, base: Int, w: Int, wall: UInt32, roof: UInt32, roofDark: UInt32, door: UInt32, awning: UInt32?, chimney: Bool, time: SkyTime) {
        let wallH = 15
        p.rect(x + 1, base, w, 1, Color.black.opacity(0.18))
        // Roof.
        let roofRows = 8
        for r in 0..<roofRows {
            let rw = 8 + r * (w - 4) / (roofRows - 1)
            let rx = x + (w - rw) / 2
            p.rect(rx - 1, base - wallH - roofRows + r, rw + 2, 1, ink)
            p.rect(rx, base - wallH - roofRows + r, rw, 1, Color(hex: r % 3 == 2 ? roofDark : roof))
        }
        if chimney {
            let top = base - wallH - roofRows - 3
            box(p, x + w - 7, top, 3, 5, Color(hex: 0xA8796A))
            for i in 0..<3 { p.rect(x + w - 6 + i % 2, top - 3 - i * 3, 2 - i / 2, 2 - i / 2, Color.white.opacity(0.55 - Double(i) * 0.15)) }
        }
        box(p, x, base - wallH, w, wallH, Color(hex: wall))
        p.rect(x, base - wallH, w, 1, Color.black.opacity(0.12))
        // Windows, lit after dark.
        let lit = time != .day
        let glass = lit ? Color(hex: 0xFFD27A) : Color(hex: 0xA6D1E6)
        for wx in [x + 2, x + w - 7] {
            if lit { p.glow(Double(wx) + 2.5, Double(base - 9), radius: 5, Color(hex: 0xFFD27A), 0.55) }
            box(p, wx, base - 11, 5, 4, glass)
            p.rect(wx + 2, base - 11, 1, 4, ink.opacity(0.5))
            p.rect(wx, base - 6, 5, 1, Color(hex: 0x6E8B5E))
            p.dot(wx + 1, base - 7, Color(hex: 0xF49AC1))
            p.dot(wx + 3, base - 7, Color(hex: 0xFFE38A))
        }
        // Awning.
        if let awning {
            for i in 0..<w {
                p.rect(x + i, base - 14, 1, 2, i / 2 % 2 == 0 ? Color(hex: awning) : Color(hex: 0xFFF6E5))
            }
            for i in stride(from: 0, to: w, by: 2) { p.dot(x + i, base - 12, Color(hex: awning)) }
        }
        // Door.
        box(p, x + w / 2 - 2, base - 7, 4, 7, Color(hex: door))
        p.dot(x + w / 2 + 1, base - 4, WP.gold)
    }

    static func lamp(_ p: Painter, x: Int, base: Int, time: SkyTime) {
        p.rect(x, base - 8, 1, 8, ink)
        if time != .day { p.glow(Double(x) + 0.5, Double(base - 9), radius: 6, Color(hex: 0xFFD27A), 0.6) }
        box(p, x, base - 10, 1, 2, time == .day ? Color(hex: 0xEADAB9) : Color(hex: 0xFFE38A))
    }

    /// Mossbrook's high street: the post office, the café, the library and the bakery.
    static func town(_ p: Painter, w: Int, rows: Int, letters: Int, time: SkyTime) {
        let base = rows - 11
        let horizon = base - 22
        sky(p, w: w, h: horizon + 6, time: time)
        for x in 0..<w {
            let far = horizon - 1 + Int(2.5 * sin(Double(x) * 0.13 + 1))
            p.rect(x, far, 1, base - far, Color(hex: time == .night ? 0x3E5A4C : 0x8FBF94))
            let near = horizon + 5 + Int(2 * sin(Double(x) * 0.21))
            p.rect(x, near, 1, base - near, Color(hex: time == .night ? 0x4E7448 : 0x78B86A))
        }
        // Clock tower peeking over the roofs.
        let tx = w / 2 - 2
        box(p, tx, horizon - 6, 5, 14, Color(hex: 0xC9C2B5))
        p.rect(tx - 1, horizon - 8, 7, 2, Color(hex: 0x8E5A8A))
        p.rect(tx, horizon - 9, 5, 1, Color(hex: 0x8E5A8A))
        box(p, tx + 1, horizon - 4, 3, 3, Color(hex: 0xFFFDF6))
        p.dot(tx + 2, horizon - 3, ink)
        let autumn = [9, 10, 11].contains(Calendar.current.component(.month, from: Date()))

        struct Spec { let wall, roof, dark, door: UInt32; let awning: UInt32?; let chimney: Bool }
        let specs = [
            Spec(wall: 0xEADAB9, roof: 0x4A6FA5, dark: 0x3A5A8A, door: 0x4A6FA5, awning: nil, chimney: false),
            Spec(wall: 0xF3E3C3, roof: 0xC65F4A, dark: 0xA44C3A, door: 0x7A4E3A, awning: 0xC65F4A, chimney: true),
            Spec(wall: 0xE8D5B0, roof: 0x8E5A8A, dark: 0x74476F, door: 0x5C3A5A, awning: nil, chimney: false),
            Spec(wall: 0xFBE3E8, roof: 0xC2577A, dark: 0xA0456A, door: 0x8A5230, awning: 0xC2577A, chimney: true),
        ]
        let hw = 22, gap = 5
        var x = 2, k = 0
        while x < w {
            if k > 0 { tree(p, x: x - gap - 3, y: base - 24, autumn: autumn) }
            x += hw + gap; k += 1
        }
        x = 2; k = 0
        while x < w {
            let sp = specs[k % specs.count]
            shop(p, x: x, base: base, w: hw, wall: sp.wall, roof: sp.roof, roofDark: sp.dark, door: sp.door, awning: sp.awning, chimney: sp.chimney, time: time)
            if x + hw + 2 < w { lamp(p, x: x + hw + 2, base: base, time: time) }
            x += hw + gap; k += 1
        }
        // A little bird on the post office roof.
        p.rect(2 + hw / 2 + 3, base - 25, 2, 1, Color(hex: 0x5C3A26))
        p.dot(2 + hw / 2 + 3, base - 26, Color(hex: 0x5C3A26))
        p.dot(2 + hw / 2 + 2, base - 26, Color(hex: 0xF2C14E))
        // Sidewalk and cobbled street.
        p.rect(0, base, w, 1, ink)
        p.rect(0, base + 1, w, 2, Color(hex: 0xD9C4A0))
        p.rect(0, base + 3, w, rows - base - 3, Color(hex: time == .night ? 0x8A7D6E : 0xB8A58A))
        for i in 0..<(w * 2) {
            let cx = (i * 5 + (i / (w / 5) % 2) * 2) % w
            let cy = base + 4 + (i / max(w / 5, 1)) * 2
            if cy < rows { p.rect(cx, cy, 3, 1, Color(hex: time == .night ? 0x7A6E60 : 0xA8957A)) }
        }
        // Mailbox by the post office, flag up when letters are waiting.
        let mx = 2 + hw - 3
        p.rect(mx + 1, base - 4, 1, 5, ink)
        box(p, mx - 1, base - 7, 5, 3, Color(hex: 0xD9534F))
        if letters > 0 {
            p.rect(mx + 4, base - 9, 1, 4, ink)
            p.rect(mx + 4, base - 9, 3, 2, WP.gold)
        }
        // You strolling with a coffee, and the café cat.
        let yx = min(2 + hw + gap + hw - 6, w - 17)
        p.rect(yx + 3, base + 3, 10, 1, Color.black.opacity(0.15))
        p.sprite(Sprites.plainYou, x: yx, y: base - 13)
        p.rect(yx + 13, base - 7, 1, 4, Color(hex: 0x4C8648))
        p.rect(yx + 14, base - 8, 1, 3, Color(hex: 0x4C8648))
        p.dot(yx + 12, base - 9, Color(hex: 0xF49AC1))
        p.dot(yx + 13, base - 10, Color(hex: 0xFFE38A))
        p.dot(yx + 14, base - 9, Color(hex: 0xF49AC1))
        p.dot(yx + 15, base - 10, Color(hex: 0xE07A5F))
        p.dot(yx + 13, base - 8, Color(hex: 0xC2577A))
        if time == .night { p.rect(0, 0, w, rows, Color(hex: 0x0E1238).opacity(0.2)) }
    }

    /// A cosy shelf for when every letter is delivered: lights, a plant, tied-up letters, tea and a napping cat.
    static func rest(_ p: Painter, w: Int, rows: Int) {
        let shelf = rows - 4
        // Fairy lights draped across the top.
        let bulbs: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A, 0xB8E0A0]
        for x in 0..<w {
            let y = 2 + Int((2.2 * sin(Double(x) / Double(w) * .pi * 3)).magnitude.rounded())
            p.dot(x, y, ink.opacity(0.35))
            if x % 6 == 3 {
                let c = Color(hex: bulbs[(x / 6) % bulbs.count])
                p.glow(Double(x) + 0.5, Double(y + 2), radius: 3, c, 0.55)
                p.rect(x, y + 1, 1, 2, c)
            }
        }
        // Shelf.
        p.rect(0, shelf, w, 1, ink)
        p.rect(0, shelf + 1, w, 2, Color(hex: 0xC4956A))
        p.rect(0, shelf + 1, w, 1, Color(hex: 0xD9AE82))
        p.rect(0, shelf + 3, w, 1, ink.opacity(0.5))
        // Plant.
        p.sprite(Sprites.pottedPlant, x: 0, y: shelf - 16)
        // A little stack of books.
        let lx = 19
        for (k, c) in [(0, 0x8E5A8A), (1, 0x4A6FA5), (2, 0xE8A25A)] {
            let bw = 12 - k * 2
            box(p, lx + k, shelf - 3 - k * 3, bw, 2, Color(hex: UInt32(c)))
            p.rect(lx + k + 1, shelf - 3 - k * 3, bw - 2, 1, Color.white.opacity(0.25))
        }
        // Tea with steam.
        let mx = lx + 15
        box(p, mx, shelf - 6, 6, 6, Color(hex: 0xFFFDF6))
        p.rect(mx + 1, shelf - 5, 4, 1, Color(hex: 0xB07A4A))
        p.rect(mx + 7, shelf - 5, 1, 3, ink)
        p.dot(mx + 6, shelf - 5, ink)
        p.dot(mx + 6, shelf - 2, ink)
        for i in 0..<3 {
            p.rect(mx + 1 + (i % 2) * 2, shelf - 9 - i * 2, 1, 2, Color(hex: 0x9C8FA6).opacity(0.6 - Double(i) * 0.15))
        }
        // Napping cat.
        if w > mx + 24 { p.sprite(Sprites.sleepyCat, x: w - 17, y: shelf - 9) }
        p.dot(w - 4, shelf - 13, ink.opacity(0.5))
        p.rect(w - 3, shelf - 15, 2, 1, ink.opacity(0.4))
    }

    /// You at your desk in the café, deep in work, or up for a break.
    static func desk(_ p: Painter, w: Int, rows: Int, drink: Color, onBreak: Bool, time: SkyTime) {
        p.rect(0, 0, w, rows, Color(hex: 0x5C3A26))
        for x in stride(from: 0, to: w, by: 8) {
            p.rect(x, 0, 1, rows, Color(hex: 0x4A2C1D))
            p.rect(x + 1, 0, 1, rows, Color(hex: 0x6E4630))
        }
        // Window.
        p.rect(3, 6, 20, 22, ink)
        let b = time.bands
        p.rect(4, 7, 18, 7, Color(hex: b[0]))
        p.rect(4, 14, 18, 7, Color(hex: b[1]))
        p.rect(4, 21, 18, 6, Color(hex: b[2]))
        if time == .night { for i in 0..<6 { p.dot(5 + noise(i, 2) % 16, 8 + noise(i, 4) % 10, .white) } }
        p.rect(4, 23, 18, 4, Color(hex: 0x4E5A6E))
        p.rect(12, 7, 2, 20, Color(hex: 0x8A5230))
        p.rect(4, 16, 18, 1, Color(hex: 0x8A5230))
        p.rect(2, 28, 22, 2, Color(hex: 0xC07A40))
        // String lights.
        let bulbs: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A]
        for (i, x) in stride(from: 2, to: w, by: 6).enumerated() {
            let y = 2 + i % 2
            p.glow(Double(x) + 0.5, Double(y), radius: 2.5, Color(hex: bulbs[i % 4]), 0.6)
            p.dot(x, y, Color(hex: bulbs[i % 4]))
        }
        // Shelf with books and a plant.
        p.rect(w - 22, 18, 20, 2, Color(hex: 0x8A5230))
        for (i, c) in [0xC65F4A, 0x4A6FA5, 0xF2C14E, 0x6E8B5E].enumerated() { p.rect(w - 21 + i * 2, 12, 2, 6, Color(hex: UInt32(c))) }
        p.sprite(Sprites.pottedPlant, x: w - 14, y: 3)

        let desk = rows - 10
        if onBreak {
            let big = Painter(ctx: p.ctx, s: p.s * 2)
            big.shifted(dx: 12, dy: (desk - 31) / 2).sprite(Sprites.plainYou, x: 0, y: 0)
            box(p, 51, desk - 12, 4, 4, Color(hex: 0xE07A5F))
            p.rect(51, desk - 12, 4, 1, drink)
            p.rect(55, desk - 11, 1, 2, ink)
            for i in 0..<2 { p.rect(52 + i * 2, desk - 16 + i, 1, 2, Color.white.opacity(0.6)) }
            box(p, 8, desk - 2, 18, 2, Color(hex: 0x9AA0AE))
        } else {
            let cx = w / 2 - 4
            p.glow(Double(cx), Double(desk - 10), radius: 14, Color(hex: 0xBFE6FF), 0.35)
            let big = Painter(ctx: p.ctx, s: p.s * 2)
            big.shifted(dx: (cx - 16) / 2, dy: (desk - 28) / 2).sprite(Sprites.plainYou, x: 0, y: 0)
            box(p, cx - 9, desk - 10, 18, 10, Color(hex: 0x9AA0AE))
            p.rect(cx - 9, desk - 10, 18, 1, Color(hex: 0xC4C9D2))
            p.rect(cx - 1, desk - 6, 2, 2, Color(hex: 0x78B86A))
            p.rect(cx - 12, desk - 2, 3, 2, Color(hex: 0xF6CFA8))
            p.rect(cx + 9, desk - 2, 3, 2, Color(hex: 0xF6CFA8))
        }
        p.rect(0, desk, w, 1, ink)
        p.rect(0, desk + 1, w, 3, Color(hex: 0xC07A40))
        p.rect(0, desk + 1, w, 1, Color(hex: 0xD99456))
        p.rect(0, desk + 4, w, rows - desk - 4, Color(hex: 0x8A5230))
        // Mug and the café cat on a stack of books.
        let mx = w - 22
        box(p, mx, desk - 6, 5, 6, Color(hex: 0xFFFDF6))
        p.rect(mx + 1, desk - 5, 3, 2, drink)
        p.rect(mx + 6, desk - 4, 1, 3, ink)
        for i in 0..<2 { p.rect(mx + 1 + i * 2, desk - 10 + i, 1, 2, Color.white.opacity(0.7)) }
        for (i, c) in [0xC65F4A, 0x4A6FA5].enumerated() { box(p, w - 14, desk - 2 - i * 2, 12, 1, Color(hex: UInt32(c))) }
        p.sprite(Sprites.sleepyCat, x: w - 15, y: desk - 13)
    }
}

struct PixelScene: View {
    enum Kind {
        case town(Int)
        case rest
        case desk(Color, Bool)
    }

    let kind: Kind
    var grid = 64
    var date = Date()

    var body: some View {
        Canvas { ctx, size in
            let s = max(size.width, 1) / CGFloat(grid)
            let rows = Int(size.height / s) + 1
            let p = Painter(ctx: ctx, s: s)
            let time = SkyTime.at(date)
            switch kind {
            case .town(let letters): Art.town(p, w: grid, rows: rows, letters: letters, time: time)
            case .rest: Art.rest(p, w: grid, rows: rows)
            case .desk(let drink, let onBreak): Art.desk(p, w: grid, rows: rows, drink: drink, onBreak: onBreak, time: time)
            }
        }
        // Keep houses and trees inside the picture frame.
        .clipped()
    }
}

// MARK: - Little pixel UI

struct PixelIcon: View {
    let sprite: Sprite
    var size: CGFloat = 1.5
    var body: some View { SpriteView(sprite: sprite, pixel: size) }
}

struct Framed: ViewModifier {
    var fill: Color = WP.card
    func body(content: Content) -> some View {
        content
            .background(fill)
            .overlay(Rectangle().strokeBorder(WP.ink, lineWidth: 2))
            .background(Rectangle().fill(WP.ink).offset(x: 2, y: 2))
    }
}

extension View {
    func framed(_ fill: Color = WP.card) -> some View { modifier(Framed(fill: fill)) }
}

struct Chip: View {
    let icon: Sprite?
    let text: String
    var tint = WP.ink
    var fill = WP.card

    var body: some View {
        HStack(spacing: 4) {
            if let icon { PixelIcon(sprite: icon, size: 1.3) }
            Text(text).font(.cozy(10, .heavy)).foregroundStyle(tint).lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .framed(fill)
    }
}

struct StreakBadge: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 2) {
            PixelIcon(sprite: Sprites.flame, size: 1.2)
            Text("\(streak)").font(.cozy(11, .heavy)).foregroundStyle(streak > 0 ? WP.red : WP.muted)
        }
    }
}

struct HabitRowW: View {
    let habit: WidgetSnapshot.HabitInfo
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Rectangle().fill(habit.done ? WP.leaf : WP.card)
                    .overlay(Rectangle().strokeBorder(WP.ink, lineWidth: 1.5))
                if habit.done { PixelIcon(sprite: Sprites.leafIcon, size: 1) }
            }
            .frame(width: 13, height: 13)
            Text(habit.name)
                .font(.cozy(11, .semibold))
                .foregroundStyle(WP.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            StreakBadge(streak: habit.streak)
        }
    }
}

struct LetterRowW: View {
    let title: String
    var id: String? = nil
    var size: CGFloat = 11

    var body: some View {
        if let id {
            Button(intent: DeliverLetterIntent(letterID: id)) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 7) {
            Rectangle().fill(WP.card)
                .overlay(Rectangle().strokeBorder(WP.ink.opacity(0.75), lineWidth: 1.2))
                .frame(width: 11, height: 11)
            Text(title)
                .font(.cozy(size, .medium))
                .foregroundStyle(WP.ink.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: size + 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Timeline

struct MossEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
    let phase: WidgetSnapshot.Phase?
}

struct MossProvider: TimelineProvider {
    func placeholder(in context: Context) -> MossEntry {
        MossEntry(date: .now, snap: .sample, phase: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MossEntry) -> Void) {
        let loaded = WidgetSnapshot.load()
        let snap = context.isPreview && loaded.habits.isEmpty && loaded.letters.isEmpty ? WidgetSnapshot.sample : loaded
        completion(MossEntry(date: .now, snap: snap, phase: snap.phase(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MossEntry>) -> Void) {
        let snap = WidgetSnapshot.load()
        let now = Date()
        let cal = Calendar.current
        var dates: Set<Date> = [now]
        // A fresh entry at the top of every hour, so the sky turns from night to morning on time.
        if let hour = cal.dateInterval(of: .hour, for: now)?.start {
            for h in 1...24 { if let d = cal.date(byAdding: .hour, value: h, to: hour) { dates.insert(d) } }
        }
        let horizon = now.addingTimeInterval(24 * 3600)
        for p in snap.phases {
            if p.start > now && p.start < horizon { dates.insert(p.start) }
            if p.end > now && p.end < horizon { dates.insert(p.end) }
        }
        let entries = dates.sorted().map { MossEntry(date: $0, snap: snap, phase: snap.phase(at: $0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Focus (shared by both widgets)

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var fam: WidgetFamily? = nil
    private var family: WidgetFamily { fam ?? envFamily }
    let entry: MossEntry
    let phase: WidgetSnapshot.Phase

    private var snap: WidgetSnapshot { entry.snap }
    private var range: ClosedRange<Date> { phase.start...max(phase.end, phase.start.addingTimeInterval(1)) }
    private var label: String {
        let r = snap.rounds > 1 ? " · \(phase.round)/\(snap.rounds)" : ""
        return (phase.onBreak ? "BREAK" : "FOCUSING") + r
    }

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge: large
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timerInterval: range, countsDown: true)
                    .font(.cozy(18, .heavy))
                    .foregroundStyle(WP.ink)
                    .monospacedDigit()
                    .frame(width: 62, alignment: .leading)
                Text(phase.onBreak ? "BREAK" : (snap.rounds > 1 ? "\(phase.round)/\(snap.rounds)" : "FOCUS"))
                    .font(.cozy(8, .heavy))
                    .foregroundStyle(phase.onBreak ? WP.leaf : WP.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .framed(WP.paper)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            PixelScene(kind: .desk(Color(hex: snap.drinkHex), phase.onBreak), date: entry.date)
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            PixelScene(kind: .desk(Color(hex: snap.drinkHex), phase.onBreak), date: entry.date)
                .aspectRatio(1, contentMode: .fit)
                .framed()
            VStack(alignment: .leading, spacing: 5) {
                Chip(icon: Sprites.cupIcon, text: label, tint: phase.onBreak ? WP.leaf : WP.orange)
                Text(phase.onBreak ? "Wander, sip, say hi" : (snap.focusTitle ?? "Quiet work"))
                    .font(.cozy(13, .heavy))
                    .foregroundStyle(WP.ink)
                    .lineLimit(2)
                Text(timerInterval: range, countsDown: true)
                    .font(.cozy(26, .heavy))
                    .foregroundStyle(WP.ink)
                    .monospacedDigit()
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(phase.onBreak ? WP.leaf : WP.orange)
                if snap.rounds > 1 { roundDots }
            }
        }
        .containerBackground(WP.paper, for: .widget)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelScene(kind: .desk(Color(hex: snap.drinkHex), phase.onBreak), grid: 72, date: entry.date)
                .frame(height: 230)
                .framed()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Chip(icon: Sprites.cupIcon, text: label, tint: phase.onBreak ? WP.leaf : WP.orange)
                    Text(phase.onBreak ? "Wander, sip, say hi" : (snap.focusTitle ?? "Quiet work"))
                        .font(.cozy(15, .heavy))
                        .foregroundStyle(WP.ink)
                        .lineLimit(1)
                    if snap.rounds > 1 { roundDots }
                }
                Spacer()
                Text(timerInterval: range, countsDown: true)
                    .font(.cozy(30, .heavy))
                    .foregroundStyle(WP.ink)
                    .monospacedDigit()
                    .frame(width: 120, alignment: .trailing)
            }
            ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(phase.onBreak ? WP.leaf : WP.orange)
        }
        .containerBackground(WP.paper, for: .widget)
    }

    private var roundDots: some View {
        HStack(spacing: 3) {
            ForEach(1...max(snap.rounds, 1), id: \.self) { r in
                Rectangle()
                    .fill(r < phase.round || (r == phase.round && phase.onBreak) ? WP.orange : (r == phase.round ? WP.gold : WP.card))
                    .frame(width: 10, height: 6)
                    .overlay(Rectangle().strokeBorder(WP.ink, lineWidth: 1))
            }
        }
    }
}

// MARK: - Main widget: the town, your letters, your café time, your habit streaks

struct TodayView: View {
    @Environment(\.widgetFamily) private var envFamily
    var fam: WidgetFamily? = nil
    private var family: WidgetFamily { fam ?? envFamily }
    let entry: MossEntry
    private var snap: WidgetSnapshot { entry.snap }
    private var streaks: [WidgetSnapshot.HabitInfo] { snap.habits.sorted { $0.streak > $1.streak } }

    var body: some View {
        if let phase = entry.phase {
            if family.isHome {
                FocusWidgetView(fam: family, entry: entry, phase: phase)
            } else {
                lockFocus(phase)
            }
        } else {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            case .accessoryRectangular: rectangular
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    private var dayTitle: String {
        var part: String
        switch Calendar.current.component(.hour, from: entry.date) {
        case 5..<12: part = "MORNING"
        case 12..<17: part = "AFTERNOON"
        case 17..<21: part = "EVENING"
        default: part = "NIGHT"
        }
        switch SkyTime.override {
        case .day?: part = "AFTERNOON"
        case .dusk?: part = "EVENING"
        case .night?: part = "NIGHT"
        case nil: break
        }
        return entry.date.formatted(.dateTime.weekday(.wide)) + " " + part.lowercased()
    }

    private func streakChip(_ h: WidgetSnapshot.HabitInfo) -> some View {
        HStack(spacing: 4) {
            PixelIcon(sprite: Sprites.flame, size: 1.2)
            Text("\(h.streak)").font(.cozy(10, .heavy)).foregroundStyle(WP.red)
            Text(h.name).font(.cozy(9, .semibold)).foregroundStyle(WP.ink).lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .framed()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let best = streaks.first { streakChip(best) } else { Chip(icon: nil, text: dayTitle) }
            Spacer()
            Group {
                if let first = snap.letters.first {
                    LetterRowW(title: first, id: snap.letterIDs?.first, size: 10)
                } else {
                    HStack(spacing: 5) {
                        PixelIcon(sprite: Sprites.envelope, size: 1.2)
                        Text("All delivered").font(.cozy(10, .heavy)).foregroundStyle(WP.ink)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .framed(WP.paper)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { PixelScene(kind: .town(snap.lettersLeft), grid: 52, date: entry.date) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(dayTitle.components(separatedBy: " ").first ?? "").foregroundStyle(WP.ink)
                + Text(" " + (dayTitle.components(separatedBy: " ").last ?? "")).foregroundStyle(WP.muted.opacity(0.7)))
                .font(.story(16))
            Spacer()
            if snap.lettersLeft > 0 {
                Text("\(snap.lettersLeft) left").font(.cozy(10, .semibold)).foregroundStyle(Color(hex: 0x4A6FA5))
            }
        }
    }

    private func taskList(_ n: Int, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            if snap.letters.isEmpty { caughtUp }
            ForEach(Array(snap.letters.prefix(n).enumerated()), id: \.offset) { i, t in
                LetterRowW(title: t, id: snap.letterIDs?[safe: i])
            }
        }
    }

    /// When the satchel is empty, Pip leans in with a little note that changes through the day.
    private var caughtUp: some View {
        let notes = [
            "Satchel's empty. Off to feed the ducks!",
            "Every letter delivered. Go do something nice.",
            "Quiet route today. I like those.",
            "All done! I'm taking the long way home.",
            "Nothing to carry. My shoulders thank you.",
            "Not a single letter left. Tea time?"
        ]
        let hour = Calendar.current.component(.hour, from: entry.date)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: entry.date) ?? 0
        let note = notes[(hour / 3 + day) % notes.count]
        return HStack(alignment: .bottom, spacing: 3) {
            SpriteView(sprite: Sprites.pip, pixel: 2.2)
            Text(note)
                .font(.cozy(10, .medium))
                .foregroundStyle(WP.ink.opacity(0.8))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 2, bottomTrailingRadius: 10, topTrailingRadius: 10)
                        .fill(Color(hex: 0xF1E3C8))
                )
                .padding(.bottom, 22)
        }
        .padding(.top, 2)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            PixelScene(kind: .town(snap.lettersLeft), grid: 52, date: entry.date)
                .aspectRatio(1, contentMode: .fit)
                .framed()
            VStack(alignment: .leading, spacing: 8) {
                header
                taskList(3, spacing: 6)
                Spacer(minLength: 0)
                if let best = streaks.first { streakChip(best) }
            }
        }
        .containerBackground(WP.paper, for: .widget)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelScene(kind: .town(snap.lettersLeft), grid: 112, date: entry.date)
                .frame(height: 170)
                .framed()
            header
            taskList(4, spacing: 8)
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                if let best = streaks.first { streakChip(best) }
                Spacer()
                HStack(spacing: 4) {
                    PixelIcon(sprite: Sprites.cupIcon, size: 1.1)
                    Text("\(snap.cafeMinutes) min at the café").font(.cozy(9, .heavy)).foregroundStyle(WP.muted)
                }
            }
        }
        .containerBackground(WP.paper, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("NEXT LETTER").font(.system(size: 10, weight: .heavy, design: .monospaced))
            Text(snap.letters.first ?? "All delivered").font(.system(size: 14, weight: .semibold)).lineLimit(1)
            if let best = streaks.first {
                Text("\(best.name) · \(best.streak)-day streak").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "envelope.fill").font(.system(size: 11))
                Text("\(snap.lettersLeft)").font(.system(size: 18, weight: .bold, design: .rounded))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Text(streaks.first.map { "\($0.name) · \($0.streak)-day streak" } ?? (snap.letters.first.map { "Next: \($0)" } ?? "No letters today"))
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func lockFocus(_ phase: WidgetSnapshot.Phase) -> some View {
        let range = phase.start...max(phase.end, phase.start.addingTimeInterval(1))
        switch family {
        case .accessoryCircular:
            ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: {
                Image(systemName: phase.onBreak ? "cup.and.saucer.fill" : "laptopcomputer")
            }
            .progressViewStyle(.circular)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            Text(timerInterval: range, countsDown: true).containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.onBreak ? "ON A BREAK" : (snap.focusTitle ?? "FOCUS").uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                Text(timerInterval: range, countsDown: true).font(.system(size: 20, weight: .bold, design: .monospaced))
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Font {
    /// Soft rounded type for the widgets.
    static func cozy(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size + 1, weight: weight, design: .rounded)
    }

    /// A little storybook serif for headings.
    static func story(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension WidgetFamily {
    var isHome: Bool { [.systemSmall, .systemMedium, .systemLarge].contains(self) }
}

