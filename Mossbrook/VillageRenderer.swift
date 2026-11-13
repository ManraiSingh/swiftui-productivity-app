import SwiftUI

struct SceneState {
    let bikeParts: Int
    let bikeFixed: Bool
    let pages: Int
    let bookDone: Bool
    let delivered: Int
    let openLetters: Int
    let cafeLevel: Int
    let focusing: Bool
    let phase: DayPhase
    let weather: Weather
    let season: Season
    let streak: Int
    let dailyLetter: Bool
    let habitCount: Int
    let habitsDone: Int
    let treats: Int
    /// During the town tour everyone stands still in front of their place.
    let touring: Bool

    init(_ store: VillageStore) {
        touring = store.showTour
        habitCount = store.habits.count
        habitsDone = store.habitsDoneToday
        treats = store.treatsBaked
        weather = store.weather
        season = Season.now()
        streak = store.streak
        dailyLetter = store.hasDailyLetter
        bikeParts = store.bikeParts
        bikeFixed = store.bikeFixed
        pages = store.pagesFound
        bookDone = store.bookDone
        delivered = store.lettersDelivered
        openLetters = store.openLetters.count
        cafeLevel = store.cafeLevel
        focusing = store.isFocusing
        phase = store.phase
    }
}

enum VillageLayout {
    static let width = 256
    static let height = 300
    /// Wild woods around the town, so the world feels like it keeps going.
    static let margin = 64
    /// Forest and an open sunset sky above the town.
    static let topMargin = 0
    static let bottomMargin = 48
    static let worldWidth = width + margin * 2
    static let worldHeight = topMargin + height + bottomMargin

    struct Pose {
        let x: Double
        let y: Double
        let facingLeft: Bool
        let walking: Bool
    }

    /// Villagers stroll between two spots. While you focus, they gather at the café.
    /// Where each villager stands for the town tour, in town art pixels (feet position).
    static func tourSpot(_ villager: VillagerID) -> (x: Double, y: Double) {
        switch villager {
        case .pip: (82, 152)
        case .mo: (34, 152)
        case .bea: (80, 233)
        case .juniper: (30, 233)
        case .rosie: (180, 152)
        }
    }

    static func pose(_ villager: VillagerID, t: Double, state: SceneState) -> Pose {
        if state.touring {
            let s = tourSpot(villager)
            return Pose(x: s.x, y: s.y, facingLeft: false, walking: false)
        }
        if state.focusing && villager == .bea {
            return Pose(x: 80, y: 233, facingLeft: false, walking: false)
        }
        let a: (Double, Double)
        let b: (Double, Double)
        let offset: Double
        switch villager {
        case .pip:
            a = (66, 152)
            b = state.bikeFixed ? (150, 152) : (100, 152)
            offset = 0
        case .mo:
            a = (18, 152)
            b = (54, 152)
            offset = 7
        case .bea:
            a = (68, 233)
            b = (100, 233)
            offset = 3
        case .juniper:
            a = (12, 233)
            b = (46, 233)
            offset = 11
        case .rosie:
            a = (164, 152)
            b = (200, 152)
            offset = 5
        }
        let cycle = 18.0
        let p = (t + offset).truncatingRemainder(dividingBy: cycle)
        let x: Double, y: Double, walking: Bool, left: Bool
        if p < 7 {
            let k = p / 7
            x = a.0 + (b.0 - a.0) * k; y = a.1 + (b.1 - a.1) * k
            walking = true; left = b.0 < a.0
        } else if p < 9 {
            x = b.0; y = b.1; walking = false; left = b.0 < a.0
        } else if p < 16 {
            let k = (p - 9) / 7
            x = b.0 + (a.0 - b.0) * k; y = b.1 + (a.1 - b.1) * k
            walking = true; left = a.0 < b.0
        } else {
            x = a.0; y = a.1; walking = false; left = a.0 < b.0
        }
        return Pose(x: x, y: y, facingLeft: left, walking: walking)
    }
}

enum VillageRenderer {
    static let W = VillageLayout.width
    static let H = VillageLayout.height
    static let groundTop = 62

    static let ink = Color(hex: 0x2B2233)
    static let leafInk = Color(hex: 0x2F4A35)
    static let warm = Color(hex: 0xFFD27A)
    static let grass = Color(hex: 0x8CC56C)
    static let grassDark = Color(hex: 0x73AD5B)
    static let grassLight = Color(hex: 0xA6D682)
    static let water = Color(hex: 0x6FB7DA)
    static let waterDark = Color(hex: 0x5A9FC4)
    static let waterLight = Color(hex: 0xBDE5F4)
    static let dirt = Color(hex: 0xDEC797)
    static let dirtEdge = Color(hex: 0xC9AF7E)
    static let stone = Color(hex: 0xA39686)
    static let wood = Color(hex: 0x7A4E3A)
    static let shadow = Color.black.opacity(0.16)

    struct HouseStyle {
        let wall: Color
        let wallDark: Color
        let roof: Color
        let roofDark: Color
        let roofLight: Color
    }

    // Windows, kept here so night lights land in the same spots.
    static let libraryWindows: [(Int, Int)] = [(15, 89), (34, 89)]
    static let postWindows: [(Int, Int)] = [(81, 93), (99, 93)]
    static let cafeWindows: [(Int, Int)] = [(50, 186), (70, 186)]

    /// Today's weather and season, read by the drawing helpers below.
    static var weather: Weather = .clear
    static var season: Season = .summer
    /// When the town sits inside the wider world, the world draws the sky and hills instead.
    static var openSky = false
    static var transparentSky = true

    static func draw(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect] = []) {
        drawSky(p, t: t, state: state, effects: effects)
        drawBase(p, state: state)
        drawLive(p, t: t, state: state, effects: effects)
    }

    /// One night sky of stars across the whole world, so zooming out shows no seam where the town ends.
    /// The town draws the stars above it (in town pixels); the woods draw the rest (in world pixels).
    static func worldStars(_ p: Painter, t: Double, inTown: Bool) {
        let M = VillageLayout.margin
        let WW = VillageLayout.worldWidth
        // Same density as the town always had: 28 stars per 256 pixels.
        let count = 28 * WW / W
        for i in 0..<count {
            let x = noise(i, 7) % WW
            let insideTown = (M..<(M + W)).contains(x)
            guard insideTown == inTown else { continue }
            let y = noise(i, 13) % 40
            guard (noise(i, 3) + Int(t * 2)) % 6 != 0 else { continue }
            p.dot(inTown ? x - M : x, y, Color.white.opacity(noise(i, 5) % 2 == 0 ? 0.9 : 0.5))
        }
    }

    /// Sun, moon, stars, clouds and the balloon: the bits behind the hills.
    static func drawSky(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect] = []) {
        weather = state.weather
        season = state.season
        guard !openSky else { return }
        sky(p, t: t, phase: state.phase)
        skyLife(p, t: t, state: state, effects: effects)
    }

    /// Hills, grass, paths, the square and the trees behind the high street. None of it moves,
    /// so the app draws it once into a picture (`TownBaseCache`) instead of every frame.
    static func drawBase(_ p: Painter, state: SceneState) {
        weather = state.weather
        season = state.season
        if !openSky { hills(p) }
        clockTower(at(p, clockOff))
        ground(p, t: 0)
        if weather == .snow { p.rect(0, groundTop, W, H - groundTop, Color.white.opacity(0.45)) }
        backdrop(p, t: 0)
        paths(p)
        townSquare(p)
    }

    /// Everything that moves or changes with your progress, drawn every frame on top of the base.
    static func drawLive(_ p: Painter, t: Double, state: SceneState, effects: [VillageEffect] = []) {
        weather = state.weather
        season = state.season
        farmField(p, t: t)
        lake(at(p, lakeOff), t: t)
        lakeLife(at(p, lakeOff), t: t, effects: effects)
        garden(at(p, gardenOff), t: t, streak: state.streak)
        library(at(p, libOff), t: t, state: state)
        postOffice(at(p, postOff), state: state)
        mailboxSparkle(at(p, postOff), t: t, state: state)
        town(p, t: t, state: state)
        cafe(at(p, cafeOff), t: t, state: state)
        trees(p, t: t, effects: effects)
        lamps(p)
        villagers(p, t: t, state: state)
        groundLife(p, t: t, state: state, effects: effects)
        if weather == .rain { p.rect(0, 0, W, H, Color(hex: 0x4A5A78).opacity(0.16)) }

        switch state.phase {
        case .day:
            break
        case .dusk:
            tintBelowHills(p, width: W, offset: 0, Color(hex: 0xFF8A55).opacity(0.10))
            tintBelowHills(p, width: W, offset: 0, Color(hex: 0x3A2850).opacity(0.06))
            lights(p, t: t, state: state, strength: 0.6)
            townLights(p, strength: 0.6, state: state)
            villagersOnTop(p, t: t, state: state, tints: [(0xFF8A55, 0.10), (0x3A2850, 0.06)])
        case .night:
            tintBelowHills(p, width: W, offset: 0, Color(hex: 0x0E1238).opacity(0.48))
            lights(p, t: t, state: state, strength: 1)
            townLights(p, strength: 1, state: state)
            villagersOnTop(p, t: t, state: state, tints: [(0x0E1238, 0.48)])
            if weather != .rain && weather != .snow { fireflies(p, t: t) }
        }
        weatherParticles(p, t: t)
        if !openSky { nightLife(p, t: t, state: state, effects: effects) }
    }

    // MARK: Town plan
    // Each older building keeps its own drawing and is moved into place on the wide map.
    static let libOff = (7, 38)
    static let postOff = (-10, 34)
    static let cafeOff = (16, 28)
    static let lakeOff = (64, 48)
    static let gardenOff = (-22, 119)
    static let clockOff = (63, 0)
    static let mainStreet = (y: 146, h: 8)
    static let southLane = (y: 228, h: 6)

    static func at(_ p: Painter, _ off: (Int, Int)) -> Painter { p.shifted(dx: off.0, dy: off.1) }

    // MARK: Helpers

    static let carvedGlyphs: [Character: [String]] = [
        "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
        "C": ["011", "100", "100", "100", "011"], "E": ["111", "100", "110", "100", "111"],
        "F": ["111", "100", "110", "100", "100"], "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
        "I": ["111", "010", "010", "010", "111"], "K": ["101", "101", "110", "101", "101"],
        "M": ["10001", "11011", "10101", "10001", "10001"], "N": ["1001", "1101", "1011", "1001", "1001"],
        "O": ["010", "101", "101", "101", "010"], "R": ["110", "101", "110", "101", "101"],
        "S": ["111", "100", "111", "001", "111"], "T": ["111", "010", "010", "010", "010"],
        "U": ["101", "101", "101", "101", "111"], "W": ["10001", "10001", "10101", "11011", "10001"],
        "Y": ["101", "101", "010", "010", "010"]
    ]

    /// A wooden plank nailed to the roof, with the words carved into it.
    static func carvedSign(_ p: Painter, _ text: String, cx: Int, top: Int) {
        let width = text.reduce(0) { $0 + ($1 == " " ? 2 : (carvedGlyphs[$1]?.first?.count ?? 3) + 1) } - 1
        let w = width + 6
        let x0 = cx - w / 2
        // A sign never changes, so it's built once as a little picture and reused every frame.
        p.sprite(carvedSignSprite(text, w: w, parity: x0 & 1), x: x0 - 1, y: top - 1)
    }

    nonisolated(unsafe) private static var signSprites: [String: Sprite] = [:]
    private static let signLock = NSLock()

    /// The carved wooden sign as a sprite: ink border, wood with a light top and dark bottom edge,
    /// a little grain, two nails, and the letters cut in (a light lip under a dark groove).
    private static func carvedSignSprite(_ text: String, w: Int, parity: Int) -> Sprite {
        let key = "\(text)|\(parity)"
        signLock.lock(); defer { signLock.unlock() }
        if let hit = signSprites[key] { return hit }
        // Grid covers the ink border: (w + 2) × 9, origin one pixel up-left of the wood.
        var g = Array(repeating: Array(repeating: Character("k"), count: w + 2), count: 9)
        func set(_ x: Int, _ y: Int, _ c: Character) {
            let gx = x + 1, gy = y + 1
            guard gy >= 0, gy < g.count, gx >= 0, gx < g[0].count else { return }
            g[gy][gx] = c
        }
        for y in 0..<7 { for x in 0..<w { set(x, y, "b") } }
        for x in 0..<w { set(x, 0, "l"); set(x, 6, "d") }
        // Grain, at the same spots as before (it depended on the sign's absolute x).
        for gx in stride(from: 2, to: w - 2, by: 7) { set(gx, 3 + ((gx + parity) % 2), "g") }
        set(1, 3, "n"); set(w - 2, 3, "n")
        var x = 3
        for ch in text {
            guard let glyph = carvedGlyphs[ch] else { x += 2; continue }
            for (r, row) in glyph.enumerated() { for (c, bit) in row.enumerated() where bit == "1" { set(x + c, 2 + r, "h") } }
            for (r, row) in glyph.enumerated() { for (c, bit) in row.enumerated() where bit == "1" { set(x + c, 1 + r, "c") } }
            x += glyph[0].count + 1
        }
        let sprite = Sprite(g.map { String($0) }, [
            "k": ink, "b": Color(hex: 0xB8865A), "l": Color(hex: 0xD9A877), "d": Color(hex: 0x9A6A44),
            "g": Color(hex: 0xA77A50), "n": Color(hex: 0x6B4A2E), "h": Color(hex: 0xCC9C6C), "c": Color(hex: 0x2E1A12)
        ])
        signSprites[key] = sprite
        return sprite
    }

    /// A filled rectangle with a 1-pixel ink outline, the backbone of the pixel look.
    static func box(_ p: Painter, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ fill: Color, outline: Color = ink) {
        p.rect(x - 1, y - 1, w + 2, h + 2, outline)
        p.rect(x, y, w, h, fill)
    }

    static func circle(_ p: Painter, cx: Int, cy: Int, r: Int, _ color: Color) {
        for dy in -r...r {
            let half = Int((Double(r * r - dy * dy)).squareRoot().rounded())
            p.rect(cx - half, cy + dy, half * 2 + 1, 1, color)
        }
    }

    /// A cozy front-facing house: outlined walls with planks, a shingled roof with overhang, and a soft shadow.
    static func house(_ p: Painter, cx: Int, base: Int, w: Int, wallH: Int, roofRows: Int, style: HouseStyle) {
        let x0 = cx - w / 2
        let wallTop = base - wallH
        let eaveW = w + 6
        let topW = max(4, eaveW - 2 * (roofRows - 1))
        let roofTop = wallTop - roofRows

        // Shadow falls down and to the right.
        p.rect(x0 + 2, base + 1, w + 2, 2, shadow)
        p.rect(x0 + w + 1, wallTop + 2, 2, wallH, shadow)

        // Walls.
        box(p, x0, wallTop, w, wallH, style.wall)
        for y in stride(from: wallTop + 4, to: base - 2, by: 3) {
            p.rect(x0, y, w, 1, style.wallDark)
        }
        p.rect(x0, wallTop, w, 2, style.wallDark)
        p.rect(x0 + w - 2, wallTop, 2, wallH, style.wallDark.opacity(0.6))
        p.rect(x0 - 1, base - 2, w + 2, 2, stone)
        p.rect(x0 - 1, base, w + 2, 1, ink)

        // Roof: outline pass, then shingles.
        for r in 0..<roofRows {
            let rowW = topW + 2 * r
            p.rect(cx - rowW / 2 - 1, roofTop + r, rowW + 2, 1, ink)
        }
        p.rect(cx - topW / 2, roofTop - 1, topW, 1, ink)
        p.rect(cx - eaveW / 2 - 1, wallTop, eaveW + 2, 1, ink)
        for r in 0..<roofRows {
            let rowW = topW + 2 * r
            let left = cx - rowW / 2
            let band = r % 3 == 2
            p.rect(left, roofTop + r, rowW, 1, band ? style.roofDark : style.roof)
            if !band {
                for x in stride(from: left + (r % 2) * 2 + 1, to: left + rowW - 1, by: 4) {
                    p.dot(x, roofTop + r, style.roofDark)
                }
            }
        }
        p.rect(cx - topW / 2, roofTop, topW, 1, style.roofLight)
        p.rect(cx - topW / 2 + 1, roofTop + 1, 3, 1, style.roofLight)
        if weather == .snow {
            p.rect(cx - topW / 2, roofTop, topW, 2, Color(hex: 0xF4F7FB))
            for r in stride(from: 3, to: roofRows, by: 3) {
                let rowW = topW + 2 * r
                for x in stride(from: cx - rowW / 2 + 1, to: cx + rowW / 2, by: 3) {
                    p.dot(x, roofTop + r, Color(hex: 0xF4F7FB))
                }
            }
            p.rect(cx - eaveW / 2, wallTop - 1, eaveW, 1, Color(hex: 0xF4F7FB))
        }
    }

    static func window(_ p: Painter, x: Int, y: Int, w: Int = 6, h: Int = 5, glass: Color, shutter: Color?, flowers: Bool = false) {
        if let shutter {
            box(p, x - 3, y, 2, h, shutter)
            box(p, x + w + 1, y, 2, h, shutter)
        }
        box(p, x, y, w, h, glass)
        p.rect(x + w / 2, y, 1, h, ink)
        p.rect(x, y + h / 2, w, 1, ink)
        p.dot(x + 1, y + 1, Color.white.opacity(0.55))
        if flowers {
            box(p, x - 1, y + h + 1, w + 2, 1, Color(hex: 0x8A5A3B))
            for i in 0..<(w + 2) where i % 2 == 0 {
                p.dot(x - 1 + i, y + h, i % 4 == 0 ? Color(hex: 0xF49AC1) : Color(hex: 0xFFE38A))
            }
        }
    }

    static func door(_ p: Painter, x: Int, y: Int, w: Int, h: Int, color: Color) {
        box(p, x, y, w, h, color)
        p.rect(x, y, w, 1, ink)
        p.dot(x, y + 1, ink)
        p.dot(x + w - 1, y + 1, ink)
        p.rect(x + w / 2, y + 2, 1, h - 2, color.opacity(0.6))
        p.dot(x + w - 2, y + h / 2 + 1, Color(hex: 0xF2C14E))
        p.rect(x - 1, y + h, w + 2, 1, stone)
    }

    // MARK: Sky and land

    static func sky(_ p: Painter, t: Double, phase: DayPhase) {
        let gloomy = weather == .rain || weather == .snow
        let bands: [UInt32]
        switch phase {
        case .day where gloomy: bands = [0x9AA8B8, 0xB0BCC8, 0xC6CED6]
        case .dusk where gloomy: bands = [0x7A6E8A, 0x9C8A98, 0xB8A8A8]
        case .day: bands = [0x9ED6EC, 0xB5E1EF, 0xCDEBEF]
        case .dusk: bands = [0x8E6FA6, 0xE79A86, 0xF6C79A]
        case .night: bands = [0x161B3A, 0x1F2550, 0x2B3166]
        }
        // The app paints one smooth sky behind the whole world, so the town only adds sun, moon, stars and clouds.
        if !transparentSky {
            p.rect(0, 0, W, 20, Color(hex: bands[0]))
            p.rect(0, 20, W, 18, Color(hex: bands[1]))
            p.rect(0, 38, W, 26, Color(hex: bands[2]))
            for x in stride(from: 0, to: W, by: 2) {
                p.dot(x, 20, Color(hex: bands[0]))
                p.dot(x + 1, 38, Color(hex: bands[1]))
            }
        }

        switch phase {
        case .day where gloomy, .dusk where gloomy:
            break
        case .day:
            p.glow(206, 30, radius: 12, Color(hex: 0xFFF3B0), 0.6)
            circle(p, cx: 206, cy: 30, r: 4, Color(hex: 0xFFE38A))
        case .dusk:
            p.glow(202, 44, radius: 16, Color(hex: 0xFFB070), 0.7)
            circle(p, cx: 202, cy: 44, r: 5, Color(hex: 0xFF9E5E))
        case .night:
            // The town's share of the one star field that spans the whole world.
            worldStars(p, t: t, inTown: true)
            p.glow(204, 30, radius: 10, Color(hex: 0xF4EBC8), 0.35)
            circle(p, cx: 204, cy: 30, r: 4, Color(hex: 0xF4EBC8))
            circle(p, cx: 206, cy: 28, r: 3, Color(hex: 0x161B3A))
        }

        if phase != .night {
            let tint = gloomy ? Color(hex: 0xE2E6EC).opacity(0.95) : (phase == .day ? Color.white.opacity(0.95) : Color(hex: 0xFFE6D2).opacity(0.9))
            for i in 0..<(gloomy ? 9 : 5) {
                let speed = 1.2 + Double(i) * 0.5
                let base = Double(i * 52)
                let x = Int((base + t * speed).truncatingRemainder(dividingBy: Double(W + 42))) - 24
                let y = 22 + i * 6
                p.rect(x, y, 12, 3, tint)
                p.rect(x + 2, y - 2, 6, 2, tint)
                p.rect(x + 7, y - 1, 3, 1, tint)
            }
        }
    }

    /// Tints the land only (from the hilltops down), so the sky behind stays one clean gradient.
    static func tintBelowHills(_ p: Painter, width: Int, offset: Int, _ color: Color) {
        let bottom = VillageLayout.worldHeight
        let columns = (0..<width).map { x -> (Int, Int, Int, Int) in
            let gx = x - offset
            let far = 46 + Int(3 * sin(Double(gx) * 0.09) + 2 * sin(Double(gx) * 0.23 + 1))
            return (x, far, 1, bottom - far)
        }
        p.rects(columns, color)
    }

    static func hills(_ p: Painter) {
        for x in 0..<W {
            let far = 46 + Int(3 * sin(Double(x) * 0.09) + 2 * sin(Double(x) * 0.23 + 1))
            p.rect(x, far, 1, 66 - far, Color(hex: 0x8FBF94))
            let near = 54 + Int(2.5 * sin(Double(x) * 0.13 + 2) + 1.5 * sin(Double(x) * 0.31))
            p.rect(x, near, 1, 66 - near, Color(hex: 0x7DB37F))
        }
    }

    static func clockTower(_ p: Painter) {
        let stoneLight = Color(hex: 0xCDC3B6)
        let stoneDark = Color(hex: 0xB5AA9C)
        p.rect(60, 70, 14, 2, shadow)
        box(p, 59, 40, 12, 30, stoneLight)
        for y in stride(from: 43, to: 68, by: 4) {
            p.rect(59, y, 12, 1, stoneDark)
            p.dot(62 + (y / 4 % 2) * 4, y + 2, stoneDark)
        }
        p.rect(69, 40, 2, 30, stoneDark)
        for i in 0..<9 {
            let w = 16 - 2 * i
            p.rect(65 - w / 2 - 1, 39 - i, w + 2, 1, ink)
        }
        for i in 0..<8 {
            let w = 16 - 2 * i
            p.rect(65 - w / 2, 39 - i, w, 1, i % 2 == 0 ? Color(hex: 0x5A4B6B) : Color(hex: 0x6A5A7C))
        }
        p.rect(64, 27, 2, 4, ink)
        circle(p, cx: 65, cy: 47, r: 4, ink)
        circle(p, cx: 65, cy: 47, r: 3, Color(hex: 0xFFF6E5))
        p.rect(65, 45, 1, 2, ink)
        p.rect(65, 47, 2, 1, ink)
        box(p, 63, 62, 4, 8, Color(hex: 0x5A4B6B))
        box(p, 64, 55, 2, 3, Color(hex: 0x5A4B6B))
    }

    static func ground(_ p: Painter, t: Double) {
        p.rect(0, groundTop, W, H - groundTop, grass)
        for y in stride(from: groundTop + 1, to: H, by: 2) {
            for x in stride(from: 0, to: W, by: 2) {
                let n = noise(x, y)
                if n % 13 == 0 {
                    p.dot(x, y, grassDark)
                    p.dot(x, y - 1, grassDark)
                } else if n % 19 == 0 {
                    p.dot(x, y, grassLight)
                } else if n % 97 == 0 {
                    let petals = n % 3 == 0 ? Color(hex: 0xF49AC1) : (n % 3 == 1 ? Color(hex: 0xFFE38A) : Color.white)
                    let sway = (Int(t) + n) % 4 == 0 ? 1 : 0
                    p.dot(x + sway, y - 1, petals)
                    p.dot(x, y, Color(hex: 0x5E9E58))
                }
            }
        }
    }

    static func river(_ p: Painter, t: Double) {
        p.rect(115, groundTop, 12, H - groundTop, water)
        p.rect(114, groundTop, 1, H - groundTop, leafInk)
        p.rect(127, groundTop, 1, H - groundTop, leafInk)
        p.rect(115, groundTop, 1, H - groundTop, waterDark)
        for i in 0..<20 {
            let y = groundTop + (i * 13 + Int(t * 5)) % (H - groundTop)
            p.rect(117 + (i % 3) * 3, y, 2, 1, waterLight)
        }
    }

    /// Streets: a main street with the north row facing it, and a garden lane in front of the south row.
    static func paths(_ p: Painter) {
        var segments: [(Int, Int, Int, Int)] = [
            (0, mainStreet.y, W, mainStreet.h),
            (0, southLane.y, W, southLane.h),
            (4, 154, 6, 74),
            (246, 154, 6, 74)
        ]
        for cx in [34, 82, 180, 222] { segments.append((cx - 3, 139, 7, 8)) }
        for s in segments { p.rect(s.0 - 1, s.1 - 1, s.2 + 2, s.3 + 2, dirtEdge) }
        for s in segments { p.rect(s.0, s.1, s.2, s.3, dirt) }
        for i in 0..<160 {
            let s = segments[i % 4]
            p.dot(s.0 + noise(i, 41) % s.2, s.1 + noise(i, 43) % s.3, dirtEdge)
        }
        for x in stride(from: 2, to: W, by: 5) {
            p.dot(x, mainStreet.y + 2, Color(hex: 0xCDB585))
            p.dot(x + 2, mainStreet.y + 5, Color(hex: 0xCDB585))
        }
    }

    static func lake(_ p: Painter, t: Double) {
        let cx = 20.0, cy = 214.0, rx = 18.0, ry = 10.0
        for y in Int(cy - ry - 2)...Int(cy + ry + 2) {
            let dy = (Double(y) - cy) / (ry + 2)
            guard abs(dy) <= 1 else { continue }
            let half = Int((rx + 2) * (1 - dy * dy).squareRoot())
            p.rect(Int(cx) - half, y, half * 2, 1, leafInk)
        }
        for y in Int(cy - ry - 1)...Int(cy + ry + 1) {
            let dy = (Double(y) - cy) / (ry + 1)
            guard abs(dy) <= 1 else { continue }
            let half = Int((rx + 1) * (1 - dy * dy).squareRoot())
            p.rect(Int(cx) - half, y, half * 2, 1, Color(hex: 0xD9C79A))
        }
        for y in Int(cy - ry)...Int(cy + ry) {
            let dy = (Double(y) - cy) / ry
            guard abs(dy) <= 1 else { continue }
            let half = Int(rx * (1 - dy * dy).squareRoot())
            p.rect(Int(cx) - half, y, half * 2, 1, y < Int(cy - ry + 3) ? waterDark : water)
        }
        for i in 0..<6 {
            let phase = (t * 0.4 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let x = 6 + noise(i, 77) % 26
            let y = 208 + noise(i, 79) % 10
            if phase < 0.7 { p.rect(x, y, 3, 1, waterLight.opacity(1 - phase)) }
        }
        p.sprite(Sprites.duck, x: 10 + Int(4 * sin(t * 0.25)), y: 207, flip: cos(t * 0.25) < 0)
        p.sprite(Sprites.duck, x: 22 + Int(3 * sin(t * 0.2 + 2)), y: 214, flip: cos(t * 0.2 + 2) < 0)
        p.rect(36, 207, 1, 6, Color(hex: 0x6FA85A))
        p.dot(36, 206, Color(hex: 0x8A5A3B))
        p.dot(39, 209, Color(hex: 0x8A5A3B))
        p.rect(39, 210, 1, 5, Color(hex: 0x6FA85A))
    }

    /// Juniper's garden: each day of your streak, another flower blooms.
    static func garden(_ p: Painter, t: Double, streak: Int) {
        box(p, 30, 124, 22, 12, Color(hex: 0x8A6A4A))
        for row in stride(from: 126, to: 136, by: 3) {
            p.rect(30, row, 22, 1, Color(hex: 0x76583C))
        }
        let blooms = min(streak, 15)
        let petals: [UInt32] = [0xF49AC1, 0xFFE38A, 0xFFFFFF, 0xC9A0F0, 0xF4845F]
        for i in 0..<15 {
            let x = 32 + (i % 5) * 4
            let y = 127 + (i / 5) * 3
            if i < blooms {
                let sway = (Int(t * 1.5) + i) % 6 == 0 ? 1 : 0
                p.rect(x, y - 1, 1, 2, Color(hex: 0x5E9E58))
                let c = Color(hex: petals[i % petals.count])
                p.dot(x - 1 + sway, y - 2, c); p.dot(x + 1 + sway, y - 2, c)
                p.dot(x + sway, y - 3, c); p.dot(x + sway, y - 1, c)
                p.dot(x + sway, y - 2, Color(hex: 0xF2C14E))
            } else {
                p.dot(x, y, Color(hex: 0x6FA85A))
                p.dot(x, y - 1, Color(hex: 0x5E9E58))
            }
        }
        for x in stride(from: 28, through: 54, by: 3) {
            box(p, x, 121, 1, 3, Color(hex: 0xC9A27A))
        }
        p.rect(28, 122, 27, 1, Color(hex: 0xC9A27A))
    }

    // MARK: Buildings

    static func library(_ p: Painter, t: Double, state: SceneState) {
        let style = HouseStyle(
            wall: Color(hex: 0xEADAB9), wallDark: Color(hex: 0xD6C29E),
            roof: Color(hex: 0x8E5A8A), roofDark: Color(hex: 0x74476F), roofLight: Color(hex: 0xAA7CA6)
        )
        box(p, 34, 66, 4, 9, Color(hex: 0xA8796A))
        box(p, 33, 65, 6, 1, Color(hex: 0x7A5C55))
        house(p, cx: 27, base: 102, w: 30, wallH: 18, roofRows: 11, style: style)
        carvedSign(p, "NOTES", cx: 27, top: 75)

        if state.pages > 0 {
            for i in 0..<4 {
                let k = (t * 0.35 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                let x = 35 + Int(sin(k * 6 + Double(i)) * 2 + k * 5)
                let y = 62 - Int(k * 16)
                let size = 2 + Int(k * 2)
                p.rect(x, y, size, size, Color.white.opacity(0.75 * (1 - k)))
            }
        }

        let glass = state.pages > 0 ? Color(hex: 0xA6D1E6) : Color(hex: 0x9AA0AE)
        for (i, w) in libraryWindows.enumerated() {
            window(p, x: w.0, y: w.1, glass: glass, shutter: Color(hex: 0x6E8B5E), flowers: state.pages >= 3)
            books(p, x: w.0, y: w.1, count: i == 0 ? min(state.pages, 4) : max(0, state.pages - 4), start: i * 4)
        }
        door(p, x: 24, y: 93, w: 6, h: 9, color: wood)
        box(p, 24, 89, 6, 2, Color(hex: 0xF6E7C8))
        p.dot(26, 89, Color(hex: 0xC65F4A)); p.dot(27, 89, Color(hex: 0x4A6FA5))

        for y in stride(from: 87, to: 100, by: 3) {
            p.dot(12, y, Color(hex: 0x5E9E58))
            p.dot(13, y + 1, Color(hex: 0x78B86A))
        }
        if state.pages == 0 {
            let web = Color.white.opacity(0.7)
            p.dot(25, 94, web); p.dot(26, 95, web); p.dot(27, 94, web)
        }
        if state.bookDone { garland(p, from: 10, to: 44, y: 84) }
    }

    static let spineColors: [Color] = [Color(hex: 0xC65F4A), Color(hex: 0x4A6FA5), Color(hex: 0xF2C14E), Color(hex: 0x6E8B5E), Color(hex: 0x8E5A8A)]

    static func books(_ p: Painter, x: Int, y: Int, count: Int, start: Int) {
        let slots = [0, 1, 4, 5]
        for i in 0..<min(count, slots.count) {
            p.rect(x + slots[i], y + 3, 1, 2, spineColors[(i + start) % spineColors.count])
        }
    }

    static func garland(_ p: Painter, from: Int, to: Int, y: Int) {
        for (i, x) in stride(from: from, to: to, by: 4).enumerated() {
            let dy = i % 2
            p.dot(x, y + dy, ink)
            p.rect(x, y + dy + 1, 2, 2, spineColors[i % spineColors.count])
        }
    }

    static func postOffice(_ p: Painter, state: SceneState) {
        let style = HouseStyle(
            wall: Color(hex: 0xF3E6C9), wallDark: Color(hex: 0xE0CDA8),
            roof: Color(hex: 0x4A6FA5), roofDark: Color(hex: 0x3B5C8C), roofLight: Color(hex: 0x6E93C8)
        )
        house(p, cx: 92, base: 106, w: 28, wallH: 17, roofRows: 10, style: style)
        carvedSign(p, "TASKS", cx: 92, top: 80)
        let glass = state.delivered > 0 ? Color(hex: 0xA6D1E6) : Color(hex: 0x9AA0AE)
        for w in postWindows {
            window(p, x: w.0, y: w.1, glass: glass, shutter: Color(hex: 0xC65F4A), flowers: state.delivered >= 3)
        }
        door(p, x: 89, y: 97, w: 6, h: 9, color: Color(hex: 0x5B6E9C))
        box(p, 88, 92, 8, 3, Color(hex: 0xF6E7C8))
        p.rect(90, 93, 4, 1, Color.white)
        p.dot(90, 92, ink); p.dot(93, 92, ink)

        p.rect(74, 101, 1, 6, ink)
        box(p, 72, 97, 5, 4, Color(hex: 0xD9534F))
        p.rect(73, 99, 3, 1, Color(hex: 0x8E2E2B))
        if state.openLetters > 0 || state.dailyLetter {
            p.rect(78, 96, 1, 4, ink)
            p.rect(78, 96, 2, 2, Color(hex: 0xF2C14E))
        }

        if state.bikeFixed {
            garland(p, from: 77, to: 108, y: 89)
        } else {
            bike(p, x: 99, y: 108, parts: state.bikeParts)
        }
    }

    static func cafe(_ p: Painter, t: Double, state: SceneState) {
        let open = state.cafeLevel > 0
        let style = HouseStyle(
            wall: Color(hex: 0xF6E3CF), wallDark: Color(hex: 0xE5CDB4),
            roof: open ? Color(hex: 0xB5563E) : Color(hex: 0x9A7468),
            roofDark: open ? Color(hex: 0x96432F) : Color(hex: 0x7E5E55),
            roofLight: open ? Color(hex: 0xD27A5E) : Color(hex: 0xB38F84)
        )
        box(p, 72, 160, 4, 8, Color(hex: 0xA8796A))
        box(p, 71, 159, 6, 1, Color(hex: 0x7A5C55))
        house(p, cx: 64, base: 196, w: 34, wallH: 18, roofRows: 9, style: style)
        carvedSign(p, "CAFE", cx: 64, top: 169)

        if open || state.focusing {
            for i in 0..<4 {
                let k = (t * 0.45 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                let x = 73 + Int(sin(k * 6 + Double(i)) * 2 + k * 4)
                let y = 156 - Int(k * 14)
                let size = 1 + Int(k * 2)
                p.rect(x, y, size, size, Color.white.opacity(0.8 * (1 - k)))
            }
        }


        // Striped awning.
        let red = open ? Color(hex: 0xD9534F) : Color(hex: 0xB9A9A0)
        let cream = open ? Color(hex: 0xFFF6E5) : Color(hex: 0xD8CFC6)
        p.rect(46, 179, 37, 4, ink)
        for x in 47..<82 {
            let stripe = ((x - 47) / 3) % 2 == 0 ? red : cream
            p.rect(x, 180, 1, 2, stripe)
            if (x - 47) % 3 == 1 { p.dot(x, 182, stripe) }
        }

        let glass = open ? Color(hex: 0xFFE2A8) : Color(hex: 0x9AA0AE)
        for w in cafeWindows {
            window(p, x: w.0, y: w.1, w: 8, h: 6, glass: glass, shutter: nil, flowers: state.cafeLevel >= 3)
            if !open {
                p.rect(w.0 - 1, w.1 + 1, 10, 1, Color(hex: 0xA87A4F))
                p.rect(w.0 - 1, w.1 + 4, 10, 1, Color(hex: 0xA87A4F))
            }
        }
        door(p, x: 61, y: 186, w: 7, h: 10, color: Color(hex: 0x8E5A3B))
        box(p, 62, 188, 5, 2, open ? Color(hex: 0x6E8B5E) : Color(hex: 0xC65F4A))

        if open {
            box(p, 40, 189, 5, 6, Color(hex: 0x3D3F45))
            p.rect(41, 190, 3, 1, Color.white.opacity(0.8))
            p.rect(41, 192, 2, 1, Color.white.opacity(0.6))
            p.dot(40, 196, ink); p.dot(44, 196, ink)
        }
        if state.cafeLevel >= 2 {
            table(p, x: 46, y: 200)
            table(p, x: 77, y: 200)
        }
        if state.cafeLevel >= 3 {
            p.sprite(Sprites.cat, x: 83, y: 189)
            box(p, 36, 197, 3, 3, Color(hex: 0xA8796A))
            p.rect(36, 195, 3, 2, Color(hex: 0x5E9E58))
            p.dot(37, 194, Color(hex: 0xF49AC1))
        }
    }

    static func table(_ p: Painter, x: Int, y: Int) {
        p.rect(x, y + 4, 6, 1, shadow)
        box(p, x, y, 6, 1, Color(hex: 0xA87A4F))
        p.rect(x + 2, y + 2, 2, 3, ink)
        box(p, x - 3, y + 2, 1, 2, Color(hex: 0xC65F4A))
        box(p, x + 8, y + 2, 1, 2, Color(hex: 0xC65F4A))
        p.dot(x + 1, y - 1, Color.white)
        p.dot(x + 4, y - 1, Color.white)
    }

    static let wheelRing: [(Int, Int)] = [(-1, -3), (0, -3), (1, -3), (-2, -2), (2, -2), (-3, -1), (3, -1), (-3, 0), (3, 0), (-3, 1), (3, 1), (-2, 2), (2, 2), (-1, 3), (0, 3), (1, 3)]

    /// Pip's bike, drawn from however many parts have been found.
    static func bike(_ p: Painter, x: Int, y: Int, parts: Int) {
        let frameColor = parts >= 3 ? Color(hex: 0xC65F4A) : Color(hex: 0x9C6B5A)
        let framePixels: [(Int, Int)] = [(4, 7), (5, 7), (6, 7), (7, 7), (7, 6), (7, 5), (6, 4), (7, 4), (8, 4), (9, 4), (10, 4), (9, 5), (8, 6), (10, 3), (11, 5), (11, 6), (12, 7)]
        for (dx, dy) in framePixels { p.dot(x + dx, y + dy, frameColor) }
        if parts >= 1 {
            for (dx, dy) in wheelRing { p.dot(x + 12 + dx, y + 7 + dy, ink) }
            p.dot(x + 12, y + 7, Color(hex: 0x8A8A9A))
        }
        if parts >= 2 {
            for (dx, dy) in wheelRing { p.dot(x + 3 + dx, y + 7 + dy, ink) }
            p.dot(x + 3, y + 7, Color(hex: 0x8A8A9A))
        }
        if parts >= 3 {
            for dx in 3...7 { p.dot(x + dx, y + 8, Color(hex: 0x8A8A9A)) }
        }
        if parts >= 4 {
            p.rect(x + 5, y + 2, 3, 1, Color(hex: 0x6B4A2E))
            p.dot(x + 6, y + 3, ink)
        }
        if parts >= 5 {
            p.dot(x + 10, y + 2, ink); p.dot(x + 11, y + 1, ink); p.dot(x + 12, y + 1, ink)
        }
        if parts >= 6 {
            p.dot(x + 12, y + 2, Color(hex: 0xF2C14E))
        }
    }

    static func bridge(_ p: Painter, fixed: Bool) {
        if fixed {
            p.rect(113, 139, 16, 10, ink)
            for x in stride(from: 114, to: 128, by: 2) {
                p.rect(x, 140, 1, 8, Color(hex: 0xA87A4F))
                p.rect(x + 1, 140, 1, 8, Color(hex: 0x946A44))
            }
            box(p, 113, 136, 1, 4, Color(hex: 0x6B4A2E))
            box(p, 127, 136, 1, 4, Color(hex: 0x6B4A2E))
        } else {
            box(p, 112, 139, 2, 8, Color(hex: 0x6B4A2E))
            box(p, 127, 139, 1, 8, Color(hex: 0x6B4A2E))
            p.rect(116, 144, 3, 1, Color(hex: 0x946A44))
            p.rect(107, 150, 1, 5, ink)
            box(p, 104, 147, 7, 3, Color(hex: 0xA87A4F))
            p.dot(106, 148, ink); p.dot(108, 148, ink)
        }
    }

    static func tree(_ p: Painter, x baseX: Int, y: Int, shake: Int = 0, index: Int = 0) {
        let x = baseX + shake
        p.rect(baseX + 1, y + 12, 10, 2, shadow)
        box(p, baseX + 4, y + 8, 2, 5, Color(hex: 0x7A5236), outline: leafInk)
        let main: UInt32, light: UInt32, dark: UInt32
        switch season {
        case .autumn: (main, light, dark) = index % 3 == 0 ? (0xD9A441, 0xF2C14E, 0xB07A2A) : (0xD9824A, 0xE8A25A, 0xB0582F)
        case .winter: (main, light, dark) = (0x4C7A5A, 0x6A9A72, 0x3A624A)
        default: (main, light, dark) = (0x5E9E58, 0x78B86A, 0x4C8648)
        }
        let canopy = [(x + 1, y + 2, 8, 6), (x + 2, y, 6, 9), (x, y + 3, 10, 4)]
        for c in canopy { p.rect(c.0 - 1, c.1 - 1, c.2 + 2, c.3 + 2, leafInk) }
        for c in canopy { p.rect(c.0, c.1, c.2, c.3, Color(hex: main)) }
        p.rect(x + 2, y + 1, 3, 2, Color(hex: light))
        p.rect(x + 1, y + 3, 2, 1, Color(hex: light))
        p.rect(x + 1, y + 7, 8, 1, Color(hex: dark))
        p.rect(x + 7, y + 4, 2, 3, Color(hex: dark))
        if season == .spring {
            for k in 0..<5 { p.dot(x + 1 + noise(index, k) % 8, y + 1 + noise(k, index) % 6, Color(hex: 0xF7B7CF)) }
        }
        if weather == .snow {
            p.rect(x + 2, y, 6, 1, Color(hex: 0xF4F7FB))
            p.rect(x + 1, y + 2, 2, 1, Color(hex: 0xF4F7FB))
            p.rect(x + 7, y + 2, 2, 1, Color(hex: 0xF4F7FB))
        }
    }

    static func bush(_ p: Painter, x: Int, y: Int) {
        p.rect(x - 1, y - 1, 7, 5, leafInk)
        p.rect(x, y, 5, 3, Color(hex: 0x5E9E58))
        p.dot(x + 1, y, Color(hex: 0x78B86A))
        p.dot(x + 3, y + 1, Color(hex: 0xF49AC1))
    }

    static let treeSpots: [(Int, Int)] = [
        (1, 118), (238, 116), (246, 128), (158, 108),
        (2, 198), (160, 202), (103, 198),
        (36, 244), (48, 266), (110, 250), (124, 262), (138, 248), (220, 248), (236, 262),
        (6, 270), (24, 278), (112, 278), (130, 282), (204, 288), (240, 282), (60, 282)
    ]

    static func trees(_ p: Painter, t: Double, effects: [VillageEffect]) {
        for (i, spot) in treeSpots.enumerated() {
            var shake = 0
            for e in effects {
                if case .shake(let index) = e.kind, index == i, t - e.start < 0.6 {
                    shake = Int(t * 30) % 2 == 0 ? 1 : -1
                }
            }
            tree(p, x: spot.0, y: spot.1, shake: shake, index: i)
        }
        for (x, y) in [(54, 136), (100, 136), (152, 136), (200, 136), (60, 222), (100, 222), (170, 222), (40, 286), (180, 290)] {
            bush(p, x: x, y: y)
        }
    }

    static let lampSpots: [(Int, Int)] = [(59, 132), (157, 132), (205, 132), (103, 214), (219, 214)]

    static func lamps(_ p: Painter) {
        for (x, y) in lampSpots {
            p.rect(x + 1, y + 10, 3, 1, shadow)
            box(p, x, y, 1, 10, Color(hex: 0x3D3F63))
            box(p, x - 1, y - 3, 3, 3, Color(hex: 0x3D3F63))
            p.dot(x, y - 2, Color(hex: 0xE8D8A8))
        }
    }

    /// Redraws the villagers above the night window lights and lanterns, shaded to match the evening,
    /// so a glowing window never covers someone's head.
    static func villagersOnTop(_ p: Painter, t: Double, state: SceneState, tints: [(UInt32, Double)]) {
        p.tintedLayer(width: W, height: H, tints: tints.map { Color(hex: $0.0).opacity($0.1) }) { q in
            villagers(q, t: t, state: state)
        }
    }

    static func villagers(_ p: Painter, t: Double, state: SceneState) {
        let poses = VillagerID.allCases.map { ($0, VillageLayout.pose($0, t: t, state: state)) }
            .sorted { $0.1.y < $1.1.y }
        for (v, pose) in poses {
            let idleBob = state.focusing && Int(t * 1.5 + Double(v.rawValue.count)) % 2 == 0
            let bob = (pose.walking && Int(t * 6) % 2 == 0) || idleBob ? -1 : 0
            let x = Int(pose.x) - 8
            let y = Int(pose.y) - 16 + bob
            p.rect(x + 4, Int(pose.y) - 1, 8, 1, shadow)
            p.sprite(v.sprite, x: x, y: y, flip: pose.facingLeft)
            if weather == .rain || weather == .snow {
                umbrella(p, v, x: x, y: y, flip: pose.facingLeft, t: t, walking: pose.walking)
            }
        }
    }

    /// Each villager's own umbrella: (canopy, stripe or pattern, trim).
    static func umbrellaColors(_ v: VillagerID) -> (Color, Color, Color) {
        switch v {
        case .pip: (Color(hex: 0x4A6FA5), Color(hex: 0xF2C14E), Color(hex: 0x34507C))      // postal blue, gold stripes
        case .mo: (Color(hex: 0x8E5A8A), Color(hex: 0xFFF3B0), Color(hex: 0x6A3F66))       // plum with little stars
        case .bea: (Color(hex: 0xF2A07A), Color(hex: 0xFFF6E5), Color(hex: 0xC4704C))      // café awning stripes
        case .juniper: (Color(hex: 0x78B86A), Color(hex: 0xC9E8A8), Color(hex: 0x4C8648)) // leafy green, a leaf on top
        case .rosie: (Color(hex: 0xF49AC1), Color(hex: 0xFFFFFF), Color(hex: 0xC2577A))    // strawberry pink, polka dots
        }
    }

    /// A cute dome umbrella held over the head, with scalloped edges and a pattern per villager.
    static func umbrella(_ p: Painter, _ v: VillagerID, x: Int, y: Int, flip: Bool, t: Double, walking: Bool) {
        let (main, accent, trim) = umbrellaColors(v)
        let tilt = walking ? (flip ? 1 : -1) : 0
        let cx = flip ? x + 5 : x + 11, top = y - 5
        // Handle held at the side, ending in the hand with a little hook.
        let hx = flip ? x + 2 : x + 14
        p.rect(hx, top + 6, 1, 11, ink)
        p.rect(hx + (flip ? 1 : -1), top + 16, 1, 1, ink)
        p.rect(hx + (flip ? 1 : -1), top + 15, 1, 1, Color(hex: 0xF6CFA8))
        // Canopy rows: half-widths from the tip down.
        let rows = [1, 4, 6, 8, 9]
        for (r, hw) in rows.enumerated() {
            let ox = cx + tilt * (rows.count - r) / 3
            p.rect(ox - hw - 1, top + r - 1, hw * 2 + 3, 1, ink)
            p.rect(ox - hw - 1, top + r, hw * 2 + 3, 1, ink)
        }
        for (r, hw) in rows.enumerated() where r > 0 {
            let ox = cx + tilt * (rows.count - r) / 3
            p.rect(ox - hw, top + r, hw * 2 + 1, 1, main)
        }
        // Scalloped bottom edge.
        let ox = cx
        for k in stride(from: -9, through: 9, by: 3) {
            p.rect(ox + k - 1, top + 5, 2, 1, ink)
            p.rect(ox + k - 1 + 1, top + 5, 1, 1, trim)
        }
        // Patterns.
        switch v {
        case .pip, .bea:
            for k in stride(from: -6, through: 6, by: 4) { p.rect(ox + k, top + 2, 1, 3, accent) }
        case .mo:
            p.dot(ox - 4, top + 3, accent); p.dot(ox + 3, top + 2, accent); p.dot(ox + 6, top + 4, accent); p.dot(ox - 1, top + 4, accent)
        case .rosie:
            p.dot(ox - 5, top + 3, accent); p.dot(ox - 1, top + 2, accent); p.dot(ox + 3, top + 4, accent); p.dot(ox + 6, top + 3, accent)
        case .juniper:
            p.rect(ox - 6, top + 3, 13, 1, accent)
            p.rect(cx + 1, top - 2, 2, 1, Color(hex: 0x78B86A)); p.dot(cx + 2, top - 3, Color(hex: 0x4C8648))
        }
        p.rect(ox - 5, top + 1, 3, 1, Color.white.opacity(0.45))
        p.rect(min(cx, hx), top + 5, abs(hx - cx) + 1, 1, ink)
        p.dot(cx, top - 1, ink)
        if weather == .snow {
            p.rect(ox - 4, top, 9, 1, Color(hex: 0xF4F7FB))
            p.rect(ox - 6, top + 1, 3, 1, Color(hex: 0xF4F7FB)); p.rect(ox + 4, top + 1, 3, 1, Color(hex: 0xF4F7FB))
        } else {
            // Raindrops bouncing off.
            let k = (t * 3 + Double(x)).truncatingRemainder(dividingBy: 1)
            p.dot(ox - 9 - Int(k * 2), top + 4 + Int(k * 3), Color(hex: 0xBDE5F4).opacity(1 - k))
            p.dot(ox + 9 + Int(k * 2), top + 4 + Int(k * 3), Color(hex: 0xBDE5F4).opacity(1 - k))
        }
    }

    // MARK: Lights

    static func lights(_ p: Painter, t: Double, state: SceneState, strength: Double) {
        for (x, y) in lampSpots {
            p.glow(Double(x) + 0.5, Double(y) - 1.5, radius: 12, warm, 0.45 * strength)
            p.dot(x, y - 2, warm)
        }
        let lp = at(p, libOff), pp = at(p, postOff), cp = at(p, cafeOff)
        // Every shop keeps a light on at night; a building you've used glows brighter.
        let dim = Color(hex: 0xF6C46A)
        func litWindows(_ q: Painter, _ ws: [(Int, Int)], w: Int = 6, h: Int = 5, bright: Bool) {
            for win in ws {
                q.glow(Double(win.0) + Double(w) / 2, Double(win.1) + Double(h) / 2, radius: bright ? 12 : 9, warm, (bright ? 0.5 : 0.35) * strength)
                window(q, x: win.0, y: win.1, w: w, h: h, glass: bright ? warm : dim, shutter: nil)
            }
        }
        litWindows(lp, libraryWindows, bright: state.pages > 0)
        litWindows(pp, postWindows, bright: state.delivered > 0)
        litWindows(cp, cafeWindows, w: 8, h: 6, bright: state.cafeLevel > 0 || state.focusing)
        porchLantern(lp, x: 31, y: 92, t: t, strength: strength)
        porchLantern(pp, x: 96, y: 96, t: t, strength: strength)
        porchLantern(cp, x: 69, y: 185, t: t, strength: strength)
        if state.pages > 0 {
            for (i, w) in libraryWindows.enumerated() {
                lp.glow(Double(w.0) + 3, Double(w.1) + 2.5, radius: 10, warm, 0.4 * strength)
                window(lp, x: w.0, y: w.1, glass: warm, shutter: nil)
                books(lp, x: w.0, y: w.1, count: i == 0 ? min(state.pages, 4) : max(0, state.pages - 4), start: i * 4)
            }
        }
        if state.delivered > 0 {
            for w in postWindows {
                pp.glow(Double(w.0) + 3, Double(w.1) + 2.5, radius: 10, warm, 0.4 * strength)
                window(pp, x: w.0, y: w.1, glass: warm, shutter: nil)
            }
        }
        if state.cafeLevel > 0 || state.focusing {
            for w in cafeWindows {
                cp.glow(Double(w.0) + 4, Double(w.1) + 3, radius: 12, warm, 0.5 * strength)
                window(cp, x: w.0, y: w.1, w: 8, h: 6, glass: warm, shutter: nil)
            }
        }
        if state.bookDone { glowGarland(lp, from: 10, to: 44, y: 84, strength: strength) }
        if state.bikeFixed { glowGarland(pp, from: 77, to: 108, y: 89, strength: strength) }
    }

    /// A small hanging lantern beside a door, with a soft flicker.
    static func porchLantern(_ p: Painter, x: Int, y: Int, t: Double, strength: Double) {
        let flicker = 0.85 + 0.15 * sin(t * 7 + Double(x))
        p.glow(Double(x) + 1, Double(y) + 3, radius: 8, Color(hex: 0xFFB55A), 0.55 * strength * flicker)
        p.rect(x, y, 2, 1, ink)
        p.rect(x - 1, y + 1, 4, 4, ink)
        p.rect(x, y + 2, 2, 2, Color(hex: 0xFFE38A))
    }

    static func glowGarland(_ p: Painter, from: Int, to: Int, y: Int, strength: Double) {
        for (i, x) in stride(from: from, to: to, by: 4).enumerated() {
            let color = spineColors[i % spineColors.count]
            p.glow(Double(x) + 1, Double(y + i % 2) + 2, radius: 3.5, color, 0.6 * strength)
            p.rect(x, y + i % 2 + 1, 2, 2, color)
        }
    }

    static func fireflies(_ p: Painter, t: Double) {
        for i in 0..<24 {
            let bx = Double(noise(i, 61) % (W - 8)) + 4
            let by = Double(noise(i, 67) % 150) + 130
            let x = bx + 4 * sin(t * 0.7 + Double(i))
            let y = by + 3 * cos(t * 0.9 + Double(i) * 2)
            if (Int(t * 3) + i) % 5 != 0 {
                p.glow(x, y, radius: 2.5, Color(hex: 0xE8FF8A), 0.6)
                p.dot(Int(x), Int(y), Color(hex: 0xF4FFB0))
            }
        }
    }
}


/// The still part of the town, drawn once per weather and season (see `WildsCache`).
@MainActor
final class TownBaseCache {
    static let shared = TownBaseCache()
    private var key = ""
    private var image: CGImage?

    func image(for state: SceneState) -> CGImage? {
        let k = "\(state.weather)-\(state.season)"
        if k == key, let image { return image }
        let scale: CGFloat = 2
        let w = CGFloat(VillageLayout.width), h = CGFloat(VillageLayout.height)
        let renderer = ImageRenderer(content:
            Canvas { ctx, _ in Painter.batched(ctx, s: scale) { VillageRenderer.drawBase($0, state: state) } }
                .frame(width: w * scale, height: h * scale)
        )
        renderer.scale = 1
        image = renderer.cgImage
        key = k
        return image
    }
}
