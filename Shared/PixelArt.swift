import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct Sprite {
    let rows: [[Character]]
    var palette: [Character: Color]

    init(_ rows: [String], _ palette: [Character: Color]) {
        self.rows = rows.map { Array($0) }
        self.palette = palette
    }

    /// The same drawing with some colors swapped, for extra villagers.
    func recolored(_ changes: [Character: Color]) -> Sprite {
        var copy = self
        copy.palette.merge(changes) { _, new in new }
        return copy
    }

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }
}

/// Draws on a low-resolution pixel grid, scaled up.
struct Painter {
    let ctx: GraphicsContext
    let s: CGFloat

    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
        guard w > 0, h > 0 else { return }
        let r = CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s + 0.5, height: CGFloat(h) * s + 0.5)
        ctx.fill(Path(r), with: .color(color))
    }

    /// Many rects filled as one shape, so a see-through colour never doubles up where they overlap.
    func rects(_ list: [(Int, Int, Int, Int)], _ color: Color) {
        var path = Path()
        for (x, y, w, h) in list where w > 0 && h > 0 {
            path.addRect(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: CGFloat(w) * s + 0.5, height: CGFloat(h) * s + 0.5))
        }
        ctx.fill(path, with: .color(color))
    }

    /// The same painter, nudged up or down by some rows.
    func shifted(dy: Int) -> Painter { shifted(dx: 0, dy: dy) }

    func shifted(dx: Int, dy: Int) -> Painter {
        var moved = ctx
        moved.translateBy(x: CGFloat(dx) * s, y: CGFloat(dy) * s)
        return Painter(ctx: moved, s: s)
    }

    func dot(_ x: Int, _ y: Int, _ color: Color) {
        rect(x, y, 1, 1, color)
    }

    func sprite(_ sprite: Sprite, x: Int, y: Int, flip: Bool = false) {
        let width = sprite.width
        for (r, row) in sprite.rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard ch != ".", let color = sprite.palette[ch] else { continue }
                let px = flip ? x + width - 1 - c : x + c
                dot(px, y + r, color)
            }
        }
    }

    /// Draws a sprite mid-step: same body, legs apart on odd frames.
    func walking(_ sprite: Sprite, x: Int, y: Int, flip: Bool, frame: Int) {
        let width = sprite.width
        for (r, row) in sprite.rows.enumerated() where r < 14 || frame % 2 == 0 {
            for (c, ch) in row.enumerated() {
                guard ch != ".", let color = sprite.palette[ch] else { continue }
                dot(flip ? x + width - 1 - c : x + c, y + r, color)
            }
        }
        if frame % 2 == 1, sprite.rows.count > 14 {
            let pantsKey = sprite.rows[14].count > 4 ? sprite.rows[14][4] : "p"
            let pants = sprite.palette[pantsKey] ?? .gray
            let ink = sprite.palette["k"] ?? .black
            for (r, row) in ["..kppk....kppk..", "..kkk......kkk.."].enumerated() {
                for (c, ch) in row.enumerated() where ch != "." {
                    dot(flip ? x + width - 1 - c : x + c, y + 14 + r, ch == "k" ? ink : pants)
                }
            }
        }
    }

    func glow(_ x: Double, _ y: Double, radius: Double, _ color: Color, _ alpha: Double) {
        let center = CGPoint(x: x * s, y: y * s)
        let r = radius * s
        let gradient = Gradient(colors: [color.opacity(alpha), color.opacity(0)])
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r)
        )
    }
}

struct SpriteView: View {
    let sprite: Sprite
    var pixel: CGFloat = 4
    var flip = false

    var body: some View {
        Canvas { ctx, _ in
            Painter(ctx: ctx, s: pixel).sprite(sprite, x: 0, y: 0, flip: flip)
        }
        .frame(width: CGFloat(sprite.width) * pixel, height: CGFloat(sprite.height) * pixel)
        .accessibilityHidden(true)
    }
}

/// A villager that gently bobs, for headers and dialogue.
struct BobbingSprite: View {
    let sprite: Sprite
    var pixel: CGFloat = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let up = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            SpriteView(sprite: sprite, pixel: pixel)
                .offset(y: up ? -pixel : 0)
        }
        .frame(width: CGFloat(sprite.width) * pixel, height: CGFloat(sprite.height + 1) * pixel, alignment: .bottom)
    }
}

/// Deterministic noise for scattering grass, flowers and stars.
func noise(_ x: Int, _ y: Int) -> Int {
    var v = UInt32(truncatingIfNeeded: x) &* 374_761_393 &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
    v = (v ^ (v >> 13)) &* 1_274_126_177
    return Int((v ^ (v >> 16)) & 0xFFFF)
}

enum Sprites {
    private static let ink = Color(hex: 0x2B2233)
    private static let skin = Color(hex: 0xF6CFA8)
    private static let blush = Color(hex: 0xF0A090)
    private static let mouth = Color(hex: 0xC0605A)

    static let pip = Sprite([
        "................",
        ".....kkkkkk.....",
        "....kcccccck....",
        "...kcccccccck...",
        "..kyyyyyyyyyyk..",
        "..khsssssssshk..",
        "..kssksssskssk..",
        "..ksbssssssbsk..",
        "..kssssmmssssk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kccnccccck...",
        "..kccccnncccck..",
        "..ksccccnnncsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "c": Color(hex: 0x4A6FA5), "y": Color(hex: 0xF2C14E), "h": Color(hex: 0x6B4A2E),
        "s": skin, "b": blush, "m": mouth, "n": Color(hex: 0x8A5A3B), "p": Color(hex: 0x3D3F63)
    ])

    static let mo = Sprite([
        "......kkkk......",
        ".....khhhhk.....",
        "....kkhhhhkk....",
        "...khhhhhhhhk...",
        "..khhhhhhhhhhk..",
        "..khhsssssshhk..",
        "..khgkgssgkghk..",
        "..khsbssssbshk..",
        "..khsssmmssshk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kcccwwccck...",
        "..kccccwwcccck..",
        "..ksccooooccsk..",
        "...kdddkkdddk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "h": Color(hex: 0x5B3A6B), "s": skin, "g": Color(hex: 0xB08D57), "b": blush,
        "m": mouth, "w": Color(hex: 0xFFF6E5), "c": Color(hex: 0x6E8B5E), "o": Color(hex: 0xC65F4A),
        "d": Color(hex: 0x4A3F5C)
    ])

    static let bea = Sprite([
        "......kk........",
        ".....kook.......",
        "....kkookkk.....",
        "...kooooooook...",
        "..kooooooooook..",
        "..koosssssssok..",
        "..kosksssskssok.",
        "..kosbssssbssok.",
        "..koosssmmsssok.",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kgwwwwwwgk...",
        "..kggwwwwwwggk..",
        "..ksgwwccwwgsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "o": Color(hex: 0xD9824A), "s": skin, "b": blush, "m": mouth,
        "g": Color(hex: 0x7FB069), "w": Color(hex: 0xFFF6E5), "c": Color(hex: 0x8A5A3B),
        "p": Color(hex: 0x5A4A6B)
    ])

    static let you = Sprite([
        "................",
        ".....kkkkkk.....",
        "....krrrrrrk....",
        "...krrwrrwrrk...",
        "..krrrrrrrrrrk..",
        "..khsssssssshk..",
        "..kssksssskssk..",
        "..ksbssssssbsk..",
        "..kssssmmssssk..",
        "...kssssssssk...",
        "....kkkkkkkk....",
        "...kggggggggk...",
        "..kggggwwggggk..",
        "..ksggggggggsk..",
        "...kpppkkpppk...",
        "...kkkk..kkkk..."
    ], [
        "k": ink, "r": Color(hex: 0xE07A5F), "w": Color(hex: 0xFFF6E5), "h": Color(hex: 0x6B4A2E),
        "s": skin, "b": blush, "m": mouth, "g": Color(hex: 0x81B29A), "p": Color(hex: 0x3D3F63)
    ])

    static let fern = mo.recolored(["h": Color(hex: 0x3E6B48), "c": Color(hex: 0xE0A458), "o": Color(hex: 0x4A6FA5)])
    static let olli = pip.recolored(["c": Color(hex: 0x8E5A8A), "y": Color(hex: 0xFFF6E5), "h": Color(hex: 0x2B2233), "n": Color(hex: 0xC65F4A)])

    static let juniper = mo.recolored([
        "h": Color(hex: 0x6B4A2E), "c": Color(hex: 0x6E8B5E), "o": Color(hex: 0xF2C14E),
        "w": Color(hex: 0xC9A27A), "g": Color(hex: 0xF6CFA8), "d": Color(hex: 0x5A4A3B)
    ])

    static let rosie = bea.recolored([
        "o": Color(hex: 0xFFF6E5), "g": Color(hex: 0xC2577A), "c": Color(hex: 0xE8A0B0), "p": Color(hex: 0x6B4A5E)
    ])

    static let farmer = you.recolored([
        "r": Color(hex: 0xE8C46A), "w": Color(hex: 0xC9A050), "g": Color(hex: 0x5B7FB0), "h": Color(hex: 0x8A5A3B)
    ])

    // Café customers.
    static let customers: [Sprite] = [
        you.recolored(["r": Color(hex: 0x4A6FA5), "g": Color(hex: 0xC65F4A)]),
        mo.recolored(["h": Color(hex: 0x2B2233), "c": Color(hex: 0x4A6FA5), "o": Color(hex: 0xF2C14E), "s": Color(hex: 0x8D5A3B)]),
        pip.recolored(["c": Color(hex: 0x6E8B5E), "y": Color(hex: 0xF2C14E)]),
        bea.recolored(["o": Color(hex: 0x3A2A20), "g": Color(hex: 0x8E5A8A), "w": Color(hex: 0xE9D6F0), "s": Color(hex: 0xC68B5E)]),
        you.recolored(["r": Color(hex: 0x2B2233), "g": Color(hex: 0xF2C14E), "s": Color(hex: 0xC68B5E)]),
        mo.recolored(["h": Color(hex: 0xC9773F), "c": Color(hex: 0x6B5F73), "o": Color(hex: 0xE8A0B0)])
    ]

    /// A sleeping tabby, curled into a loaf.
    static let sleepyCat = Sprite([
        "..k....k......",
        ".kok..kok.....",
        ".kooookoook...",
        "koooooooooook.",
        "kokkoooookkok.",
        "koowwnnwwoook.",
        ".koooooooookkk",
        ".ksoosoosookok",
        "..kkkkkkkkkkk."
    ], ["k": ink, "o": Color(hex: 0xE8A25A), "s": Color(hex: 0xC47A35), "w": Color(hex: 0xFFF6E5), "n": Color(hex: 0xF49AC1)])

    /// A trailing pothos in a terracotta pot.
    static let pottedPlant = Sprite([
        "......gg......",
        ".....gGGg.....",
        "..gg.gGGg.gg..",
        ".gGGg.gg.gGGg.",
        ".gGGgg..ggGGg.",
        "..gg.gGGg.gg..",
        "....ggGGgg....",
        ".gg..gGGg..gg.",
        "gGGg..gg..gGGg",
        ".gg..kkkk..gg.",
        "..kkkrrrrkkk..",
        "..krrrrrrrrk..",
        "...krRrrrrk...",
        "...krrrrrrk..g",
        "....kkkkkk..gG"
    ], ["k": ink, "g": Color(hex: 0x78B86A), "G": Color(hex: 0x4C8648), "r": Color(hex: 0xC9774A), "R": Color(hex: 0xE09468)])

    /// You, facing out, at a desk.
    /// You exactly as in town, without the blush, for zoomed-in widget scenes.
    static let plainYou = you.recolored(["b": skin])

    static let deskYou = Sprite([
        "........kkkkkkkk........",
        "......kkrrrrrrrrkk......",
        ".....krrwrrrrrrwrrk.....",
        "....krrrrrrwwrrrrrrk....",
        "....krrrrrrrrrrrrrrk....",
        "...kRRRRRRRRRRRRRRRRk...",
        "...khhsssssssssssshhk...",
        "...khsssssssssssssshk...",
        "...ksssseesssseessssk...",
        "...kssssewsssswessssk...",
        "...ksbbssssssssssbbsk...",
        "...ksssssssmmsssssssk...",
        "....kssssssssssssssk....",
        ".....kkkkkkkkkkkkkk.....",
        "....kgggwggggggwgggk....",
        "...kggggwggggggwggggk...",
        "..kggggggggggggggggggk..",
        ".kggggggggggggggggggggk.",
        ".kggggggggggggggggggggk.",
        ".kggggggggggggggggggggk.",
        ".kkkkkkkkkkkkkkkkkkkkkk."
    ], [
        "k": ink, "r": Color(hex: 0xE07A5F), "R": Color(hex: 0xC4614A), "w": Color(hex: 0xFFF6E5),
        "h": Color(hex: 0x6B4A2E), "s": skin, "b": blush, "m": mouth, "e": ink, "g": Color(hex: 0x81B29A)
    ])

    static let flame = Sprite([
        "...k...",
        "..kok..",
        "..koyk.",
        ".koyyok",
        "koyyyok",
        "koywyok",
        "koywyok",
        ".kooyk.",
        "..kkk.."
    ], ["k": ink, "o": Color(hex: 0xE8543A), "y": Color(hex: 0xF7A43C), "w": Color(hex: 0xFFE38A)])

    static let cupIcon = Sprite([
        "kkkkkkk..",
        "kcccccckk",
        "kwwwwwk.k",
        "kwwwwwkkk",
        "kwwwwwk..",
        ".kwwwk...",
        "..kkk...."
    ], ["k": ink, "c": Color(hex: 0x6B4226), "w": Color(hex: 0xFFFDF6)])

    static let leafIcon = Sprite([
        "....kkk",
        "..kkggk",
        ".kgglgk",
        "kgglggk",
        "kglggk.",
        "kkggk..",
        "k.kk..."
    ], ["k": ink, "g": Color(hex: 0x6FB25E), "l": Color(hex: 0x3E6E3A)])

    static let cat = Sprite([
        "k...k...",
        "kokok...",
        "koooo...",
        "kokok..k",
        ".kooookk",
        ".koooook",
        ".kkkkkk."
    ], ["k": ink, "o": Color(hex: 0xE8A25A)])

    static let duck = Sprite([
        "...kk...",
        "..kwwk..",
        "..kwkwo.",
        "kkwwwk..",
        "kwwwwwk.",
        ".kkkkk.."
    ], ["k": ink, "w": Color(hex: 0xF8F4EA), "o": Color(hex: 0xE8964A)])

    static let envelope = Sprite([
        "kkkkkkkkkk",
        "kwkwwwwkwk",
        "kwwkwwkwwk",
        "kwwwkkwwwk",
        "kwwwwwwwwk",
        "kwwwwwwrrk",
        "kkkkkkkkkk"
    ], ["k": ink, "w": Color(hex: 0xFFFDF6), "r": Color(hex: 0xC65F4A)])

    static let page = Sprite([
        "kkkkkkk.",
        "kwwwwwkk",
        "kwllllwk",
        "kwwwwwwk",
        "kwllllwk",
        "kwwwwwwk",
        "kwlllwwk",
        "kkkkkkkk"
    ], ["k": ink, "w": Color(hex: 0xFFFDF6), "l": Color(hex: 0xB9A9C9)])
}
