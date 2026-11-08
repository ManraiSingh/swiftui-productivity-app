import SwiftUI

// MARK: - Room plan

/// The Together House: a cosy café-workroom 128 pixels wide. Snack counter and fireplace
/// along the back wall, work tables, little café tables, and a rug with beanbags at the front.
/// People walk along three lanes joined by an aisle down the middle.
enum TogetherRoom {
    static let width = 128
    static let height = 238
    static let wallBottom = 62
    static let lanes: [Double] = [80, 128, 174]
    static let aisle: Double = 64
    static let speed: Double = 34

    enum Kind: String { case work, eat, relax }

    struct Spot {
        let id: String
        let kind: Kind
        /// Top-left of the seated person's sprite.
        let x: Int
        let y: Int
        let lane: Double
        var stand: CGPoint { CGPoint(x: Double(x + 8), y: lane) }
        var hit: CGRect { CGRect(x: Double(x), y: Double(y), width: 16, height: 22) }
    }

    static let spots: [Spot] = {
        var list: [Spot] = []
        for (i, x) in [10, 26, 42, 70, 86, 102].enumerated() { list.append(Spot(id: "work\(i)", kind: .work, x: x, y: 90, lane: lanes[0])) }
        for (i, x) in [14, 32, 80, 98].enumerated() { list.append(Spot(id: "eat\(i)", kind: .eat, x: x, y: 134, lane: lanes[1])) }
        for (i, x) in [18, 56, 94].enumerated() { list.append(Spot(id: "relax\(i)", kind: .relax, x: x, y: 190, lane: lanes[2])) }
        return list
    }()

    static func spot(_ id: String) -> Spot? { id.isEmpty ? nil : spots.first { $0.id == id } }

    static let counter = CGRect(x: 2, y: 30, width: 46, height: 42)
    /// Where you stand to order from Rosie.
    static let orderSpot = CGPoint(x: 26, y: lanes[0])
    static let fireplace = CGRect(x: 92, y: 24, width: 34, height: 40)
    static let catSpot = CGPoint(x: 64, y: 224)

    /// Any tap on the floor becomes a point on the nearest lane.
    static func snap(_ g: CGPoint) -> CGPoint {
        let y = lanes.min { abs($0 - g.y) < abs($1 - g.y) } ?? lanes[1]
        return CGPoint(x: min(max(g.x, 8), Double(width) - 8), y: y)
    }

    /// Along your lane to the middle aisle, down or up it, then along the new lane.
    static func route(from p: CGPoint, to q: CGPoint) -> [CGPoint] {
        if abs(p.y - q.y) < 1 { return [p, q] }
        var pts = [p]
        if abs(p.x - aisle) > 0.5 { pts.append(CGPoint(x: aisle, y: p.y)) }
        pts.append(CGPoint(x: aisle, y: q.y))
        if abs(q.x - aisle) > 0.5 { pts.append(q) }
        return pts
    }

    /// Where someone is along their route right now.
    static func place(on route: [CGPoint], since start: Double, now: Double) -> (point: CGPoint, walking: Bool, left: Bool) {
        guard route.count > 1 else { return (route.first ?? .zero, false, false) }
        var left = max(0, now - start) * speed
        for i in 1..<route.count {
            let a = route[i - 1], b = route[i]
            let d = hypot(b.x - a.x, b.y - a.y)
            if left < d {
                let k = left / max(d, 0.001)
                return (CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), true, b.x < a.x - 0.1)
            }
            left -= d
        }
        let last = route[route.count - 1], prev = route[route.count - 2]
        return (last, false, last.x < prev.x - 0.1)
    }
}

// MARK: - Emotes and phrases

enum TogetherEmote {
    private static let k = Color(hex: 0x2B2233)
    private static let yellow = Color(hex: 0xFFD54A)
    private static let blush = Color(hex: 0xF49AB0)
    private static let red = Color(hex: 0xF06A86)

    static let all: [Sprite] = [
        // Love
        Sprite([".ddd.ddd.", "dRRRdRRRd", "dRWRRRRRd", "dRRRRRRRd", ".dRRRRRd.", "..dRRRd..", "...dRd...", "....d...."],
               ["d": Color(hex: 0xA8324F), "R": red, "W": .white]),
        // Happy
        Sprite(["..kkkkk..", ".kYYYYYk.", "kYYYYYYYk", "kYkYYYkYk", "kPYYYYYPk", "kYkYYYkYk", ".kYkkkYk.", "..kkkkk.."],
               ["k": k, "Y": yellow, "P": blush]),
        // Haha
        Sprite(["..kkkkk..", ".kYYYYYk.", "kYkkYkkYk", "BYYYYYYYB", "kYkkkkkYk", "kYkRRRkYk", ".kYkkkYk.", "..kkkkk.."],
               ["k": k, "Y": yellow, "B": Color(hex: 0x7EC8F0), "R": red]),
        // Heart eyes
        Sprite(["..kkkkk..", ".kYYYYYk.", "kRRYYYRRk", "kRRYYYRRk", "kYRYYYRYk", "kYkYYYkYk", ".kYkkkYk.", "..kkkkk.."],
               ["k": k, "Y": yellow, "R": red]),
        // Hi! (a waving hand)
        Sprite(["..k.k.k..", ".ksksksk.", ".ksksksk.", "mksssssk.", ".kssssskk", "mksssssks", "..ksssskk", "...kkkk.."],
               ["k": k, "s": Color(hex: 0xF6CFA8), "m": Color(hex: 0xB8C4D6)]),
        // Nice (thumbs up)
        Sprite(["...kk....", "..ksk....", "..ksk....", "kkkssskk.", "kBksssssk", "kBksssssk", "kBksssssk", "kkkkkkkk."],
               ["k": k, "s": Color(hex: 0xF6CFA8), "B": Color(hex: 0x6C8FD8)]),
        // Party
        Sprite(["P.....Y..", "..G..k..P", ".Y..kRk..", "...kRYRk.", "..kRYRk..", ".kRYRk...", "kRRk..G..", "kkk..P..."],
               ["k": k, "R": Color(hex: 0xF4845F), "Y": Color(hex: 0xFFD54A), "P": Color(hex: 0xF49AC1), "G": Color(hex: 0x7FD1B0)]),
        // Sleepy
        Sprite([".....ZZZZ", ".......Z.", "......Z..", ".....ZZZZ", "ZZZ......", "..Z......", ".Z.......", "ZZZ......"],
               ["Z": Color(hex: 0x6C8FD8)]),
        // Coffee
        Sprite(["..w..w...", "...w..w..", ".kkkkkk..", ".kWBBWkk.", ".kWWWWk.k", ".kWHWWkkk", "..kWWk...", "..kkkk..."],
               ["k": k, "W": Color(hex: 0xFFFDF6), "B": Color(hex: 0x8A5A3B), "w": Color(hex: 0xC4C9D2), "H": Color(hex: 0xF49AC1)]),
        // Star
        Sprite(["....k....", "...kGk...", "kkkkGkkkk", "kGGGgGGGk", ".kGGgGGk.", "..kGGGk..", ".kGkkkGk.", ".kk...kk."],
               ["k": Color(hex: 0xB8801E), "G": Color(hex: 0xFFD54A), "g": Color(hex: 0xFFF3B0)]),
        // Sad
        Sprite(["..kkkkk..", ".kYYYYYk.", "kYkYYYkYk", "kBYYYYYYk", "kBYkkkYYk", "kYkYYYkYk", ".kYYYYYk.", "..kkkkk.."],
               ["k": k, "Y": yellow, "B": Color(hex: 0x7EC8F0)]),
        // Music
        Sprite(["...kkkkk", "...kPPPk", "...k...k", "...k...k", ".kkk.kkk", "kPPkkPPk", "kPPkkPPk", ".kk..kk."],
               ["k": Color(hex: 0x5E3A6E), "P": Color(hex: 0xC9A0F0)])
    ]

    static let names = ["Love", "Happy", "Haha", "Adore", "Hi!", "Nice", "Party", "Sleepy", "Coffee", "Star", "Sad", "Music"]

    static let phrases = [
        "Hi there!", "Good luck!", "Let's focus!", "You got this!", "Break time!",
        "Brb!", "Nice work!", "So cozy here", "Yummy!", "Bye bye!"
    ]
}

// MARK: - Rosie's menu

enum TogetherFood {
    private static let k = Color(hex: 0x5A3A2A)

    struct Item { let name: String; let blurb: String; let sprite: Sprite; let color: UInt32 }

    static let menu: [Item] = [
        Item(name: "Cookie", blurb: "Warm & gooey", sprite: Sprite(
            ["..kkkkk..", ".kCCcCCk.", "kCdCCCdCk", "kCCCcCCCk", "kCdCCCCdk", ".kCCCdCk.", "..kkkkk.."],
            ["k": k, "C": Color(hex: 0xE0A458), "c": Color(hex: 0xF2C27A), "d": Color(hex: 0x6B4226)]), color: 0xE0A458),
        Item(name: "Croissant", blurb: "Flaky & buttery", sprite: Sprite(
            ["...kkk...", ".kkCcCkk.", "kCcCcCcCk", "kcCcCcCck", "kCk...kCk", ".k.....k."],
            ["k": k, "C": Color(hex: 0xE8A84A), "c": Color(hex: 0xF7CF7E)]), color: 0xE8A84A),
        Item(name: "Berry cake", blurb: "With a strawberry", sprite: Sprite(
            ["....G....", "...kRk...", "..kRRRk..", "kkkkkkkkk", "kWWWWWWWk", "kPPPPPPPk", "kWWWWWWWk", "kkkkkkkkk"],
            ["k": k, "G": Color(hex: 0x78B86A), "R": Color(hex: 0xE0506A), "W": Color(hex: 0xFFF6E5), "P": Color(hex: 0xF7B7CF)]), color: 0xF7B7CF),
        Item(name: "Ramen", blurb: "Slurpy & warm", sprite: Sprite(
            ["......k.k", ".....k.k.", "kkkkkkkkk", "kYWYEYGYk", "kRRRRRRRk", "kRWRRRWRk", ".kRRRRRk.", "..kkkkk.."],
            ["k": k, "Y": Color(hex: 0xF7D774), "W": Color(hex: 0xFFFDF6), "E": Color(hex: 0xF2A93B), "G": Color(hex: 0x78B86A), "R": Color(hex: 0xD9604E)]), color: 0xD9604E),
        Item(name: "Cocoa", blurb: "Extra marshmallows", sprite: Sprite(
            ["..W.W....", ".kkkkkk..", ".kBWBWkk.", ".kPPPPk.k", ".kPPPPkkk", ".kPHPPk..", "..kkkk..."],
            ["k": k, "W": Color(hex: 0xFFFDF6), "B": Color(hex: 0x8A5A3B), "P": Color(hex: 0xF49AC1), "H": Color(hex: 0xFFFDF6)]), color: 0x8A5A3B),
        Item(name: "Boba tea", blurb: "Chewy pearls", sprite: Sprite(
            ["....kk...", "....k....", "..kkkkkk.", "..kLLLLk.", "..kTTTTk.", "..kTTTTk.", "..kTdTdk.", "..kdTdTk.", "...kkkk.."],
            ["k": k, "L": Color(hex: 0xFFF6E5), "T": Color(hex: 0xD9B48A), "d": Color(hex: 0x3A2218)]), color: 0xD9B48A)
    ]

    static func item(_ i: Int) -> Item { menu[((i % menu.count) + menu.count) % menu.count] }
}

// MARK: - Drawing

enum TogetherRenderer {
    static let ink = VillageRenderer.ink

    struct Person {
        let look: Int
        let point: CGPoint
        let walking: Bool
        let left: Bool
        let seat: TogetherRoom.Spot?
        let food: Int
        /// Heading to a café table with an order in hand.
        let carrying: Bool
        let status: HallVisitor.Status
        let emote: Int?
        /// Seconds since the emote popped up.
        let emoteAge: Double
        /// Seconds since they sat down.
        let seatedFor: Double
        let seed: Int

        /// A happy little hop right after an emote.
        var hop: Int { emote != nil && emoteAge < 0.45 ? Int((sin(emoteAge / 0.45 * .pi) * 3).rounded()) : 0 }
        /// Top of the head, for tags and bubbles.
        var headTop: Double { (seat.map { Double($0.y) + 1 } ?? point.y - 15) - Double(hop) }
        var centerX: Double { seat.map { Double($0.x) + 8 } ?? point.x }
    }

    /// The room is drawn at `ox` across a canvas `cols` wide: anything wider gets more wall and floor.
    static func draw(_ p: Painter, t: Double, cols: Int, rows: Int, ox: Int, oy: Int, phase: DayPhase, weather: Weather,
                     people: [Person], catHeart: Bool, rosieBusy: Bool) {
        let night = phase != .day
        wings(p, cols: cols, rows: rows, ox: ox, oy: oy, t: t, night: night)
        let r = p.shifted(dx: ox, dy: oy)
        sunlight(r, phase: phase)
        wall(r, t: t, phase: phase, weather: weather)
        counter(r, t: t, busy: rosieBusy)

        let walkers = people.filter { $0.seat == nil }
        func walkersBetween(_ lo: Double, _ hi: Double) {
            for w in walkers.sorted(by: { $0.point.y < $1.point.y }) where w.point.y >= lo && w.point.y < hi { walker(r, w, t: t) }
        }
        walkersBetween(-99, 88)
        workTables(r, people: people, t: t, night: night)
        walkersBetween(88, 134)
        cafeTables(r, people: people, t: t, night: night)
        walkersBetween(134, 180)
        lounge(r, people: people, t: t, catHeart: catHeart)
        walkersBetween(180, 999)

        if night {
            p.rect(0, 0, cols, rows, Color(hex: 0x241638).opacity(phase == .night ? 0.2 : 0.08))
            lights(r, t: t, strength: phase == .night ? 1 : 0.6)
        } else {
            lights(r, t: t, strength: 0.25)
        }
        for person in people {
            if let e = person.emote {
                emoteBubble(r, e, cx: Int(person.centerX), top: Int(person.headTop) - 18, age: person.emoteAge, t: t)
            }
        }
    }

    // MARK: Walls and floor

    static let wallColor = Color(hex: 0xF6E1CF)
    static let floorA = Color(hex: 0xDDA56C)
    static let floorB = Color(hex: 0xD69C62)

    static func wallpaper(_ p: Painter, cols: Int, from y0: Int, to y1: Int, ox: Int) {
        p.rect(0, y0, cols, y1 - y0, wallColor)
        for (row, y) in stride(from: y0 + 3, to: y1 - 1, by: 7).enumerated() {
            for x in stride(from: ((ox % 10) + 10) % 10 + (row % 2) * 5, to: cols, by: 10) {
                p.dot(x, y, Color(hex: 0xF2B8C6))
                p.rects([(x - 1, y, 1, 1), (x + 1, y, 1, 1), (x, y - 1, 1, 1), (x, y + 1, 1, 1)], Color(hex: 0xF7D3D9))
            }
        }
    }

    static func wings(_ p0: Painter, cols: Int, rows: Int, ox: Int, oy: Int, t: Double, night: Bool) {
        let wb = TogetherRoom.wallBottom
        wallpaper(p0, cols: cols, from: 0, to: oy + 44, ox: ox)
        let p = p0.shifted(dx: 0, dy: oy)
        let rows = rows - oy
        // Ceiling beam.
        p.rect(0, 0, cols, 3, Color(hex: 0x7A4E32))
        p.rect(0, 3, cols, 1, ink)
        // Sage wainscoting under a wooden chair rail.
        p.rect(0, 44, cols, wb - 44, Color(hex: 0xA8C9B0))
        p.rect(0, 43, cols, 2, Color(hex: 0xC98B55))
        p.rect(0, 43, cols, 1, Color(hex: 0xE3AA72))
        p.rect(0, 45, cols, 1, ink.opacity(0.35))
        for x in stride(from: ((ox % 12) + 12) % 12 + 2, to: cols, by: 12) {
            p.rect(x, 48, 8, 10, Color(hex: 0x95BB9F))
            p.rect(x, 48, 8, 1, Color(hex: 0x86AB91))
            p.rect(x, 57, 8, 1, Color(hex: 0xBFDCC6))
        }
        p.rect(0, wb - 2, cols, 2, Color(hex: 0x8E5A3B))
        p.rect(0, wb, cols, 1, ink)
        // Floor: planks in two tones with seams and a bit of grain.
        for (i, y) in stride(from: wb + 1, to: rows, by: 7).enumerated() {
            p.rect(0, y, cols, 7, i % 2 == 0 ? floorA : floorB)
            p.rect(0, y + 6, cols, 1, Color(hex: 0xC48A52))
            for x in stride(from: (i % 3) * 13 + ((ox % 39) + 39) % 39, to: cols, by: 39) {
                p.rect(x, y, 1, 6, Color(hex: 0xC48A52))
                p.dot(x + 9, y + 2 + i % 3, Color(hex: 0xCB9258))
                p.dot(x + 24, y + 4 - i % 3, Color(hex: 0xE6B47E))
            }
        }
        // Side decor for wide screens: shelves of plants and books beyond the room.
        var x = ox - 24
        var n = 0
        while x >= 0 {
            sideDecor(p, x: x, kind: n, t: t)
            x -= 30; n += 1
        }
        x = ox + TogetherRoom.width + 6
        n = 1
        while x + 20 <= cols {
            sideDecor(p, x: x, kind: n, t: t)
            x += 30; n += 1
        }
        fairyLights(p, from: 0, to: cols, t: t, night: night)
    }

    static func sideDecor(_ p: Painter, x: Int, kind: Int, t: Double) {
        if kind % 2 == 0 {
            for sy in [20, 36] {
                VillageRenderer.box(p, x, sy, 18, 2, Color(hex: 0x8E5A3B))
                var bx = x + 1
                var i = sy + x
                while bx < x + 15 {
                    let h = 6 + noise(i, 3) % 4
                    p.rect(bx, sy - h, 2, h, Color(hex: [0xC65F4A, 0x4A6FA5, 0xF2C14E, 0x6E8B5E, 0xF49AC1][noise(i, 9) % 5]))
                    bx += 3; i += 1
                }
            }
            p.sprite(Sprites.pottedPlant, x: x + 2, y: 70)
        } else {
            VillageRenderer.box(p, x + 3, 14, 12, 10, Color(hex: 0xBFE3E8))
            p.rect(x + 4, 20, 10, 3, Color(hex: 0x78B86A))
            p.dot(x + 11, 16, Color(hex: 0xFFE38A))
            bigPlant(p, x: x + 2, base: 78)
        }
    }

    static func fairyLights(_ p: Painter, from: Int, to: Int, t: Double, night: Bool) {
        let colors: [UInt32] = [0xF49AC1, 0xFFE38A, 0x9CDCC0, 0xA9C8F5, 0xFFB86B]
        for x in from..<to {
            let y = 6 + Int((sin(Double(x) / 10.5) + 1) * 1.5)
            p.dot(x, y, Color(hex: 0x5A4632))
            if x % 7 == 0 {
                let i = (x / 7) % colors.count
                let on = (Int(t * 1.5) + x / 7) % 6 != 0
                let c = Color(hex: colors[i])
                if night && on { p.glow(Double(x) + 0.5, Double(y) + 2, radius: 4, c, 0.55) }
                p.rect(x, y + 1, 2, 2, on ? c : c.opacity(0.55))
            }
        }
    }

    /// Light from the window falling across the floor.
    static func sunlight(_ p: Painter, phase: DayPhase) {
        let color: Color = switch phase {
        case .day: Color.white.opacity(0.13)
        case .dusk: Color(hex: 0xFFB070).opacity(0.14)
        case .night: Color(hex: 0x9FB4FF).opacity(0.08)
        }
        var list: [(Int, Int, Int, Int)] = []
        for y in 63..<112 { list.append((48 + (y - 62) / 2, y, 30, 1)) }
        p.rects(list, color)
    }

    static func wall(_ p: Painter, t: Double, phase: DayPhase, weather: Weather) {
        window(p, t: t, phase: phase, weather: weather)
        chalkboard(p)
        fireplace(p, t: t)
        hangingPlant(p, x: 84, t: t)
        bigPlant(p, x: 77, base: 72)
    }

    static func hangingPlant(_ p: Painter, x: Int, t: Double) {
        p.rect(x + 3, 4, 1, 8, Color(hex: 0x8E6B4A))
        VillageRenderer.box(p, x, 12, 7, 4, Color(hex: 0xF2EADF))
        p.rect(x, 13, 7, 1, Color(hex: 0xF2A7B8))
        let sway = Int(sin(t * 1.2) * 1.2)
        let leaf = Color(hex: 0x6FB06A), dark = Color(hex: 0x4C8648)
        p.rects([(x - 1, 11, 9, 2), (x - 2, 16, 2, 3), (x + 7, 16, 2, 4)], leaf)
        for i in 0..<5 {
            p.dot(x - 2 + sway, 19 + i * 2, i % 2 == 0 ? leaf : dark)
            p.dot(x + 8 + sway, 20 + i * 2, i % 2 == 0 ? dark : leaf)
        }
    }

    static func window(_ p: Painter, t: Double, phase: DayPhase, weather: Weather) {
        let x = 50, top = 12, w = 28, h = 30
        let sky: (UInt32, UInt32) = switch phase {
        case .day: weather == .rain ? (0x9AA8B8, 0xBCC6D0) : (0x9ED6EC, 0xD4EEF2)
        case .dusk: (0x8E6FA6, 0xF6C79A)
        case .night: (0x161B3A, 0x2E3466)
        }
        VillageRenderer.box(p, x, top, w, h, Color(hex: sky.0))
        p.rect(x, top + h / 2, w, h / 2, Color(hex: sky.1))
        // Distant hills.
        p.rects([(x, top + h - 6, w, 6), (x + 4, top + h - 8, 10, 2), (x + 17, top + h - 9, 8, 3)], Color(hex: phase == .night ? 0x2A3A4A : 0x9CCB8A))
        for (dx, dy) in [(0, 0), (1, 0), (0, 1), (w - 1, 0), (w - 2, 0), (w - 1, 1)] { p.dot(x + dx, top + dy, wallColor) }
        if phase == .night {
            for i in 0..<6 where (Int(t) + i) % 4 != 0 { p.dot(x + 3 + (i * 9) % 22, top + 3 + (i * 5) % 12, Color(hex: 0xFFF3B0)) }
            VillageRenderer.circle(p, cx: x + 21, cy: top + 6, r: 2, Color(hex: 0xFFF3B0))
        } else {
            let drift = Int(t * 1.5) % (w + 10) - 6
            p.rects([(x + drift, top + 6, 7, 2), (x + drift + 2, top + 5, 3, 1)], Color.white.opacity(0.85))
        }
        if weather == .rain {
            for i in 0..<6 {
                let k = (t * 1.4 + Double(i) * 0.31).truncatingRemainder(dividingBy: 1)
                p.rect(x + 2 + i * 4, top + 2 + Int(k * Double(h - 5)), 1, 2, Color.white.opacity(0.55))
            }
        }
        p.rect(x + w / 2, top, 1, h, Color(hex: 0xB8865A))
        p.rect(x, top + 14, w, 1, Color(hex: 0xB8865A))
        // Curtains with tie-backs.
        for cx in [x - 5, x + w + 1] {
            p.rects([(cx, top - 2, 4, 26), (cx + (cx < x ? 1 : 0), top + 24, 3, 8)], Color(hex: 0xF2A7B8))
            p.rect(cx + (cx < x ? 3 : 0), top - 2, 1, 26, Color(hex: 0xE08AA0))
            p.rect(cx, top + 22, 4, 1, Color(hex: 0xF2C14E))
        }
        p.rect(x - 6, top - 3, w + 12, 1, Color(hex: 0x8E5A3B))
        VillageRenderer.box(p, x - 2, top + h, w + 4, 2, Color(hex: 0xD9A877))
        for (i, px) in [x + 3, x + 12, x + 21].enumerated() {
            VillageRenderer.box(p, px, top + h - 4, 4, 3, Color(hex: 0xC9774A))
            let leaf: UInt32 = [0x78B86A, 0x9CCB7A, 0xF49AC1][i]
            p.rects([(px, top + h - 7, 4, 2), (px + 1, top + h - 8, 2, 1)], Color(hex: leaf))
        }
    }

    static func chalkboard(_ p: Painter) {
        let x = 6, y = 10
        VillageRenderer.box(p, x - 1, y - 1, 32, 22, Color(hex: 0x8E5A3B))
        p.rect(x, y, 30, 20, Color(hex: 0x3E5A4A))
        var cx = x + 8
        for ch in "MENU" {
            guard let glyph = VillageRenderer.carvedGlyphs[ch] else { continue }
            for (r, row) in glyph.enumerated() { for (c, b) in row.enumerated() where b == "1" { p.dot(cx + c, y + 2 + r, Color.white.opacity(0.9)) } }
            cx += glyph[0].count + 1
        }
        // Chalk doodles of the menu: a cake slice, a mug and a cookie, with prices.
        p.sprite(TogetherFood.menu[2].sprite.chalk, x: x + 2, y: y + 10)
        p.sprite(TogetherFood.menu[4].sprite.chalk, x: x + 11, y: y + 11)
        p.sprite(TogetherFood.menu[0].sprite.chalk, x: x + 20, y: y + 11)
        p.dot(x + 1, y + 3, Color(hex: 0xF49AC1)); p.dot(x + 27, y + 4, Color(hex: 0xFFE38A))
    }

    static func fireplace(_ p: Painter, t: Double) {
        let x = 94, top = 30, w = 30, base = 62
        VillageRenderer.box(p, x - 2, top - 3, w + 4, 3, Color(hex: 0x8E5A3B))
        p.rect(x - 2, top - 3, w + 4, 1, Color(hex: 0xB8865A))
        for (i, cx) in [x + 3, x + 6].enumerated() {
            VillageRenderer.box(p, cx, top - 8 + i, 2, 4 - i, Color(hex: 0xFFF6E5))
            let f = Int(t * 6 + Double(i)) % 2
            p.dot(cx + f % 2, top - 10 + i, Color(hex: 0xFFB55A))
        }
        VillageRenderer.box(p, x + 12, top - 10, 7, 6, Color(hex: 0xE8D5F0))
        p.rect(x + 13, top - 7, 5, 2, Color(hex: 0x9CCB7A))
        VillageRenderer.box(p, x + 23, top - 8, 3, 4, Color(hex: 0x6E9B83))
        p.rect(x + 22, top - 11, 5, 3, Color(hex: 0x78B86A))
        VillageRenderer.box(p, x, top, w, base - top, Color(hex: 0xC27A5C))
        for (r, y) in stride(from: top + 2, to: base, by: 3).enumerated() {
            p.rect(x, y, w, 1, Color(hex: 0xA9614A))
            for bx in stride(from: x + (r % 2) * 3, to: x + w, by: 6) { p.rect(bx, y - 2, 1, 2, Color(hex: 0xA9614A)) }
        }
        let fx = x + 7, fy = top + 10, fw = 16, fh = base - top - 10
        p.rect(fx - 1, fy - 1, fw + 2, fh + 1, ink)
        p.rect(fx, fy, fw, fh, Color(hex: 0x2E1F24))
        p.glow(Double(fx + fw / 2), Double(base - 6), radius: 14, Color(hex: 0xFF9A3C), 0.55)
        for i in 0..<5 {
            let flick = Int(t * 8 + Double(i) * 1.7) % 3
            let fhgt = 5 + (i % 2) * 3 + flick
            let bx = fx + 2 + i * 3
            p.rect(bx, base - 3 - fhgt, 2, fhgt, Color(hex: 0xF4845F))
            p.rect(bx, base - 3 - fhgt + 2, 2, max(1, fhgt - 4), Color(hex: 0xFFC94A))
            p.dot(bx + (flick % 2), base - 4 - fhgt, Color(hex: 0xFFE38A))
        }
        p.rect(fx + 1, base - 3, fw - 2, 2, Color(hex: 0x6B4226))
        for i in 0..<2 {
            let k = (t * 0.7 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            p.dot(fx + 5 + i * 6 + Int(sin(k * 9) * 2), base - 10 - Int(k * 10), Color(hex: 0xFFC94A).opacity(1 - k))
        }
        p.rect(x - 2, base - 1, w + 4, 2, Color(hex: 0x9A8A80))
        // A little stack of logs.
        p.rects([(x + w + 1, base - 5, 3, 2), (x + w + 1, base - 3, 3, 2)], Color(hex: 0x8A5A3B))
    }

    static func bigPlant(_ p: Painter, x: Int, base: Int) {
        let leaves: [(Int, Int, Int, Int)] = [(4, -26, 6, 4), (0, -22, 6, 4), (8, -21, 6, 5), (2, -17, 5, 4), (9, -15, 5, 4), (5, -12, 4, 3)]
        p.rects(leaves.map { (x + $0.0 - 1, base + $0.1 - 1, $0.2 + 2, $0.3 + 2) }, Color(hex: 0x2F4A35))
        p.rects(leaves.map { (x + $0.0, base + $0.1, $0.2, $0.3) }, Color(hex: 0x5E9E5A))
        p.rects(leaves.map { (x + $0.0 + 1, base + $0.1, 2, 1) }, Color(hex: 0x8FCB7A))
        p.rect(x + 7, base - 12, 1, 6, Color(hex: 0x3E6B48))
        VillageRenderer.box(p, x + 3, base - 6, 10, 6, Color(hex: 0xE8C9A8))
        p.rect(x + 3, base - 6, 10, 1, Color(hex: 0xF6E2C8))
        p.rect(x + 4, base - 3, 8, 1, Color(hex: 0xF2A7B8))
    }

    // MARK: The counter

    static func counter(_ p: Painter, t: Double, busy: Bool) {
        // Rosie bustles about when someone is ordering.
        let bob = busy ? (Int(t * 6) % 2 == 0 ? -1 : 0) : (Int(t * 1.1) % 6 == 0 ? -1 : 0)
        p.sprite(Sprites.rosie, x: 17, y: 38 + bob, flip: busy && Int(t * 2) % 2 == 0)
        if busy {
            for i in 0..<3 {
                let k = (t * 1.3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                p.dot(18 + i * 6, 36 - Int(k * 8), Color(hex: [0xFFE38A, 0xF49AC1, 0xFFFFFF][i]).opacity(1 - k))
            }
        }
        // Espresso machine.
        VillageRenderer.box(p, 4, 40, 9, 10, Color(hex: 0xC4C9D2))
        p.rect(4, 40, 9, 2, Color(hex: 0xE3E6EC))
        p.rect(6, 45, 5, 2, Color(hex: 0x6B6F7A))
        p.dot(11, 43, Color(hex: 0xE0506A))
        CafeRenderer.steam(p, x: 8, y: 38, t: t)
        // Glass case of pastries.
        VillageRenderer.box(p, 33, 42, 13, 8, Color(hex: 0xE8F4F2).opacity(0.9))
        p.rect(33, 46, 13, 1, Color(hex: 0xC9DCD8))
        p.rects([(34, 44, 3, 2), (39, 44, 3, 2)], Color(hex: 0xF7B7CF))
        p.rects([(43, 44, 2, 2), (35, 48, 3, 2), (41, 48, 3, 2)], Color(hex: 0xE8A84A))
        p.dot(35, 43, Color(hex: 0xE0506A)); p.dot(40, 43, Color(hex: 0xE0506A))
        p.rect(34, 42, 2, 1, Color.white.opacity(0.8))
        // Counter top, bell and the mint front.
        VillageRenderer.box(p, 2, 50, 47, 3, Color(hex: 0xD9A877))
        p.rect(2, 50, 47, 1, Color(hex: 0xF0C896))
        p.rects([(27, 48, 4, 2), (28, 47, 2, 1)], Color(hex: 0xF2C14E))
        VillageRenderer.box(p, 3, 54, 45, 16, Color(hex: 0x9CCFB8))
        for x in stride(from: 6, to: 46, by: 10) {
            p.rect(x, 57, 7, 10, Color(hex: 0x8AC2A8))
            p.rect(x, 57, 7, 1, Color(hex: 0xB8E3CF))
        }
        p.rect(3, 69, 45, 1, Color(hex: 0x6E9B83))
        p.rect(4, 71, 45, 2, Color.black.opacity(0.12))
        // "Order here" sign with a heart.
        VillageRenderer.box(p, 18, 58, 14, 7, Color(hex: 0xFFF6E5))
        p.rects([(22, 60, 2, 1), (25, 60, 2, 1), (22, 61, 5, 1), (23, 62, 3, 1), (24, 63, 1, 1)], Color(hex: 0xE0506A))
    }

    // MARK: Furniture

    /// A wooden spindle-back chair, seen from the front.
    static func woodChair(_ p: Painter, x: Int, y: Int, wood: UInt32) {
        let c = Color(hex: wood)
        p.rects([(x + 3, y, 10, 4), (x + 2, y + 1, 3, 12), (x + 11, y + 1, 3, 12)], ink)
        p.rects([(x + 4, y + 1, 8, 2), (x + 3, y + 2, 1, 10), (x + 12, y + 2, 1, 10)], c)
        p.rect(x + 4, y + 1, 8, 1, Color.white.opacity(0.3))
        p.rects([(x + 6, y + 4, 1, 8), (x + 9, y + 4, 1, 8)], Color(hex: 0x6B4226))
    }

    /// A round-backed café chair.
    static func cafeChair(_ p: Painter, x: Int, y: Int, color: UInt32) {
        VillageRenderer.circle(p, cx: x + 8, cy: y + 6, r: 6, ink)
        VillageRenderer.circle(p, cx: x + 8, cy: y + 6, r: 5, Color(hex: color))
        VillageRenderer.circle(p, cx: x + 8, cy: y + 6, r: 3, floorA)
        p.rects([(x + 4, y + 2, 3, 1)], Color.white.opacity(0.45))
        p.rects([(x + 2, y + 10, 2, 4), (x + 12, y + 10, 2, 4)], ink)
    }

    static func ellipse(_ p: Painter, cx: Int, cy: Int, rx: Double, ry: Double, _ color: Color) {
        let h = Int(ry)
        var list: [(Int, Int, Int, Int)] = []
        for dy in -h...h {
            let half = Int((rx * (1 - Double(dy * dy) / max(ry * ry, 0.01)).squareRoot()).rounded())
            list.append((cx - half, cy + dy, half * 2 + 1, 1))
        }
        p.rects(list, color)
    }

    static func workTables(_ p: Painter, people: [Person], t: Double, night: Bool) {
        let seats = TogetherRoom.spots.filter { $0.kind == .work }
        for (i, s) in seats.enumerated() { woodChair(p, x: s.x, y: s.y - 1, wood: [0xB97D4B, 0xA9703F][i % 2]) }
        for person in people { if let s = person.seat, s.kind == .work { seated(p, person, t: t) } }
        for left in [4, 66] {
            let top = 103, w = 58
            p.rect(left + 2, top + 14, w, 2, Color.black.opacity(0.13))
            VillageRenderer.box(p, left, top, w, 4, Color(hex: 0xC98B55))
            p.rect(left, top, w, 1, Color(hex: 0xE3AA72))
            VillageRenderer.box(p, left + 1, top + 5, w - 2, 5, Color(hex: 0x9A6340))
            p.rect(left + 1, top + 5, w - 2, 1, Color(hex: 0xB07448))
            for lx in [left + 2, left + w - 5] { VillageRenderer.box(p, lx, top + 10, 3, 4, Color(hex: 0x7A4E32)) }
        }
        // Little green desk lamps at the ends of the tables.
        for lx in [5, 120] {
            p.rect(lx + 1, 97, 1, 6, Color(hex: 0xC9A050))
            VillageRenderer.box(p, lx - 1, 95, 5, 2, Color(hex: 0x3E7A58))
            p.rect(lx, 97, 3, 1, Color(hex: 0xFFE38A))
            if night { p.glow(Double(lx) + 1.5, 100, radius: 9, Color(hex: 0xFFD27A), 0.5) }
        }
        for person in people { if let s = person.seat, s.kind == .work { workThings(p, person, s, t: t) } }
    }

    static func cafeTables(_ p: Painter, people: [Person], t: Double, night: Bool) {
        let seats = TogetherRoom.spots.filter { $0.kind == .eat }
        for (i, s) in seats.enumerated() { cafeChair(p, x: s.x, y: s.y - 1, color: [0xF2A7B8, 0x9CCFB8][i % 2]) }
        for person in people { if let s = person.seat, s.kind == .eat { seated(p, person, t: t) } }
        for cx in [31, 97] {
            let top = 149
            p.rect(cx - 15, top + 14, 32, 2, Color.black.opacity(0.13))
            VillageRenderer.box(p, cx - 17, top, 35, 3, Color(hex: 0xFFF6E5))
            p.rect(cx - 17, top, 35, 1, Color.white)
            // Scalloped tablecloth edge.
            for x in stride(from: cx - 17, to: cx + 18, by: 3) { p.rects([(x, top + 3, 2, 1)], Color(hex: 0xF7B7CF)) }
            VillageRenderer.box(p, cx, top + 5, 1, 7, Color(hex: 0x5A4632))
            VillageRenderer.box(p, cx - 4, top + 12, 9, 1, Color(hex: 0x5A4632))
            // A candle in a jar.
            VillageRenderer.box(p, cx, top - 3, 2, 3, Color(hex: 0xFFE2A8).opacity(0.9))
            p.dot(cx + Int(t * 5) % 2, top - 4, Color(hex: 0xFFB55A))
            if night { p.glow(Double(cx) + 1, Double(top - 3), radius: 10, Color(hex: 0xFFC46A), 0.5) }
        }
        for person in people { if let s = person.seat, s.kind == .eat { eatThings(p, person, s, t: t) } }
    }

    static func lounge(_ p: Painter, people: [Person], t: Double, catHeart: Bool) {
        // A round rug with a fringe.
        let cx = 64, cy = 210
        ellipse(p, cx: cx, cy: cy, rx: 53, ry: 17, Color(hex: 0x9A4A3E))
        ellipse(p, cx: cx, cy: cy, rx: 51, ry: 15.5, Color(hex: 0xD9785A))
        ellipse(p, cx: cx, cy: cy, rx: 42, ry: 11.5, Color(hex: 0xE89A6A))
        ellipse(p, cx: cx, cy: cy, rx: 40, ry: 10, Color(hex: 0xD9785A))
        for dy in stride(from: -8, through: 8, by: 4) {
            let half = Int((1 - Double(dy * dy) / 100).squareRoot() * 34)
            for x in stride(from: cx - half, to: cx + half, by: 6) { p.dot(x + (dy / 4 % 2) * 3, cy + dy, Color(hex: 0xFFE2A8)) }
        }
        for x in [cx - 54, cx + 53] { p.rects([(x, cy - 3, 1, 1), (x, cy, 1, 1), (x, cy + 3, 1, 1)], Color(hex: 0xFFE2A8)) }
        // Floor lamp and a corner plant.
        p.rect(119, 186, 1, 30, Color(hex: 0x5A4632))
        VillageRenderer.box(p, 115, 182, 9, 5, Color(hex: 0xFFE2A8))
        p.rect(115, 186, 9, 1, Color(hex: 0xF2C14E))
        VillageRenderer.box(p, 116, 215, 7, 1, Color(hex: 0x5A4632))
        p.sprite(Sprites.pottedPlant, x: -2, y: 176)
        let bags: [(UInt32, UInt32)] = [(0xE8B84A, 0xF6D27A), (0x9CBF8A, 0xBFDBA8), (0xC9A0F0, 0xDEC2F7)]
        let seats = TogetherRoom.spots.filter { $0.kind == .relax }
        for (i, s) in seats.enumerated() {
            ellipse(p, cx: s.x + 8, cy: s.y + 9, rx: 9, ry: 7, ink)
            ellipse(p, cx: s.x + 8, cy: s.y + 9, rx: 8, ry: 6, Color(hex: bags[i].0))
            p.rect(s.x + 3, s.y + 4, 4, 1, Color(hex: bags[i].1))
        }
        for person in people { if let s = person.seat, s.kind == .relax { seated(p, person, t: t) } }
        for (i, s) in seats.enumerated() {
            ellipse(p, cx: s.x + 8, cy: s.y + 17, rx: 11, ry: 5, ink)
            ellipse(p, cx: s.x + 8, cy: s.y + 17, rx: 10, ry: 4, Color(hex: bags[i].0))
            p.rect(s.x + 1, s.y + 14, 6, 1, Color(hex: bags[i].1))
        }
        for person in people { if let s = person.seat, s.kind == .relax { relaxThings(p, person, s, t: t) } }
        // Coffee table with a teapot and a board game.
        VillageRenderer.box(p, 50, 213, 28, 3, Color(hex: 0xB97D4B))
        p.rects([(52, 216, 2, 4), (74, 216, 2, 4)], Color(hex: 0x7A4E32))
        VillageRenderer.box(p, 53, 209, 6, 4, Color(hex: 0xFFF6E5))
        p.rect(52, 210, 1, 2, ink); p.rect(59, 210, 2, 1, ink)
        p.dot(55, 210, Color(hex: 0xF49AC1))
        VillageRenderer.box(p, 63, 211, 10, 2, Color(hex: 0x4A6FA5))
        p.dot(65, 211, Color(hex: 0xF2C14E)); p.dot(69, 212, Color(hex: 0xE0506A))
        // The house cat, asleep on the rug.
        let breathe = Int(t * 0.8) % 2
        p.sprite(Sprites.sleepyCat, x: Int(TogetherRoom.catSpot.x) - 7, y: Int(TogetherRoom.catSpot.y) - 9 + breathe)
        if catHeart { emoteBubble(p, 0, cx: Int(TogetherRoom.catSpot.x), top: Int(TogetherRoom.catSpot.y) - 22, age: 1, t: t) }
        else if Int(t / 3) % 3 == 0 { p.dot(Int(TogetherRoom.catSpot.x) + 6, Int(TogetherRoom.catSpot.y) - 12 - Int(t) % 3, Color(hex: 0x6C8FD8)) }
    }

    // MARK: People

    static func seated(_ p: Painter, _ person: Person, t: Double) {
        guard let s = person.seat else { return }
        let bob = Int(t * 1.2 + Double(person.seed) * 0.9) % 5 == 0 ? -1 : 0
        p.sprite(HallLooks.sprite(person.look), x: s.x, y: s.y + bob - person.hop + (s.kind == .relax ? 1 : 0))
    }

    static func walker(_ p: Painter, _ person: Person, t: Double) {
        let at = CGPoint(x: person.point.x, y: person.point.y - Double(person.hop))
        CafeRenderer.walker(p, HallLooks.sprite(person.look), at: at, walking: person.walking, facingLeft: person.left, t: t + Double(person.seed), cup: nil)
        if person.carrying {
            // A little tray with the order on it, held out in front.
            let x = Int(at.x) - 4, y = Int(at.y) - 4
            p.rect(x - 1, y + 1, 10, 1, ink)
            p.rect(x, y, 8, 1, Color(hex: 0xFFFDF6))
            let food = TogetherFood.item(person.food)
            p.rects([(x + 2, y - 3, 4, 3)], Color(hex: food.color))
            p.rect(x + 2, y - 3, 4, 1, Color.white.opacity(0.35))
        }
    }

    static func workThings(_ p: Painter, _ person: Person, _ s: TogetherRoom.Spot, t: Double) {
        let x = s.x, top = 103
        if person.status == .rest {
            VillageRenderer.box(p, x + 10, top - 4, 4, 4, Color(hex: 0xFFFDF6))
            p.rect(x + 10, top - 4, 4, 1, Color(hex: 0x6B4226))
            CafeRenderer.steam(p, x: x + 11, y: top - 6, t: t + Double(person.seed))
            return
        }
        if person.seed % 3 == 1 {
            VillageRenderer.box(p, x + 2, top - 2, 12, 2, Color(hex: 0xFFFDF6))
            p.rect(x + 8, top - 2, 1, 2, Color(hex: 0xD6C6AA))
            if Int(t / 3 + Double(person.seed)) % 4 == 0 { p.rect(x + 9, top - 4, 3, 2, Color(hex: 0xFFFDF6)) }
        } else {
            let lid: UInt32 = [0xC4C9D2, 0xF7B7CF, 0xBFE3E8][person.seed % 3]
            p.glow(Double(x + 8), Double(top - 3), radius: 6, Color(hex: 0xBFE6FF), 0.3)
            VillageRenderer.box(p, x + 3, top - 4, 10, 4, Color(hex: lid))
            p.dot(x + 8, top - 2, Color.white)
        }
        let typing = Int(t * 5 + Double(person.seed)) % 2 == 0
        p.dot(x + 2, top - 1 + (typing ? 0 : -1), Color(hex: 0xF6CFA8))
        p.dot(x + 13, top - 1 + (typing ? -1 : 0), Color(hex: 0xF6CFA8))
    }

    /// The order on a plate, getting eaten bit by bit.
    static func eatThings(_ p: Painter, _ person: Person, _ s: TogetherRoom.Spot, t: Double) {
        let top = 149
        let px = s.x + 2
        // The plate sits on the front of the table, below the face.
        VillageRenderer.box(p, px, top + 2, 12, 1, Color.white)
        let food = TogetherFood.item(person.food).sprite
        let left = person.seatedFor
        let fx = s.x + 8 - food.width / 2, fy = top + 2 - food.height
        if left < 35 {
            p.sprite(food, x: fx, y: fy)
        } else if left < 70 {
            // Half eaten: the right side is gone, with crumbs.
            var bitten = food
            bitten = bitten.trimmedRight(food.width / 2 - 1)
            p.sprite(bitten, x: fx, y: fy)
            p.rects([(fx + food.width - 2, top + 1, 1, 1), (fx + food.width, top + 1, 1, 1)], Color(hex: TogetherFood.item(person.food).color))
        } else {
            p.rects([(px + 3, top + 1, 1, 1), (px + 6, top + 1, 1, 1), (px + 8, top + 1, 1, 1)], Color(hex: TogetherFood.item(person.food).color))
        }
        // A hand comes up for a bite now and then.
        if left < 70, Int(t / 2.5 + Double(person.seed)) % 4 == 1 { p.rect(s.x + 12, s.y + 9, 2, 2, Color(hex: 0xF6CFA8)) }
    }

    static func relaxThings(_ p: Painter, _ person: Person, _ s: TogetherRoom.Spot, t: Double) {
        if person.seed % 2 == 0 {
            VillageRenderer.box(p, s.x + 11, s.y + 10, 3, 3, Color(hex: 0xFFFDF6))
            CafeRenderer.steam(p, x: s.x + 12, y: s.y + 8, t: t + Double(person.seed))
        } else {
            VillageRenderer.box(p, s.x + 3, s.y + 10, 9, 3, Color(hex: [0xC65F4A, 0x4A6FA5, 0x6E8B5E][person.seed % 3]))
            p.rect(s.x + 7, s.y + 10, 1, 3, Color(hex: 0xFFF6E5))
        }
    }

    /// A rounded bubble with a pixel emote, popping up above someone's head.
    static func emoteBubble(_ p: Painter, _ i: Int, cx: Int, top: Int, age: Double, t: Double) {
        guard TogetherEmote.all.indices.contains(i) else { return }
        if age < 0.1 {
            // Pop: a small puff first.
            p.rects([(cx - 2, top + 8, 5, 3), (cx - 1, top + 7, 3, 5)], Color.white)
            return
        }
        let bob = Int(t * 3) % 2
        let x = cx - 7, y = top - bob, w = 15, h = 12
        p.rects([(x + 1, y - 1, w - 2, 1), (x, y, w, h), (x + 1, y + h, w - 2, 1)], ink)
        p.rects([(x + 1, y, w - 2, h), (x + 2, y - 0, w - 4, 1)], Color(hex: 0xFFFDF6))
        p.rect(x + 2, y + 1, 3, 1, Color.white)
        p.rects([(cx - 2, y + h + 1, 4, 1), (cx - 1, y + h + 2, 2, 1)], ink)
        p.rect(cx - 1, y + h, 2, 1, Color(hex: 0xFFFDF6))
        let sprite = TogetherEmote.all[i]
        p.sprite(sprite, x: x + (w - sprite.width) / 2, y: y + (h - sprite.height) / 2 + 1)
        // Extra flourishes: floating hearts for love, confetti for a party.
        switch i {
        case 0, 3:
            for j in 0..<2 {
                let k = ((age - 0.1) * 0.7 + Double(j) * 0.5).truncatingRemainder(dividingBy: 1)
                let hx = x + (j == 0 ? -2 : w + 1) + Int(sin(k * 6) * 1.5), hy = y + 4 - Int(k * 10)
                p.rects([(hx, hy, 1, 1), (hx + 2, hy, 1, 1), (hx, hy + 1, 3, 1), (hx + 1, hy + 2, 1, 1)], Color(hex: 0xF06A86).opacity(1 - k))
            }
        case 6:
            for j in 0..<6 {
                let k = ((age - 0.1) * 0.9 + Double(j) / 6).truncatingRemainder(dividingBy: 1)
                let c: UInt32 = [0xF49AC1, 0xFFD54A, 0x7FD1B0, 0xA9C8F5][j % 4]
                p.dot(x - 3 + (j * 4) % (w + 6), y - 3 + Int(k * 18), Color(hex: c).opacity(1 - k))
            }
        default: break
        }
    }

    static func lights(_ p: Painter, t: Double, strength: Double) {
        for lx in [34, 94] { p.glow(Double(lx) + 0.5, 100, radius: 26, Color(hex: 0xFFD27A), 0.22 * strength) }
        p.glow(119.5, 186, radius: 20, Color(hex: 0xFFD27A), 0.45 * strength)
        let flick = 0.85 + 0.15 * sin(t * 9)
        p.glow(109, 64, radius: 30, Color(hex: 0xFF9A3C), 0.3 * strength * flick)
    }
}

extension Sprite {
    /// The same drawing in white chalk, for the menu board.
    var chalk: Sprite {
        var copy = self
        for key in copy.palette.keys { copy.palette[key] = key == "k" ? Color.white.opacity(0.8) : Color.white.opacity(0.18) }
        return copy
    }

    /// The drawing with some columns taken off the right, like a bite.
    func trimmedRight(_ n: Int) -> Sprite {
        let rowsText = rows.map { row -> String in
            let keep = max(0, row.count - n)
            return String(row.prefix(keep))
        }
        return Sprite(rowsText, palette)
    }
}
