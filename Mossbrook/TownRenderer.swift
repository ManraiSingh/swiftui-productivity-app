import SwiftUI

/// The lower town: the square and fountain, Juniper's greenhouse, Rosie's bakery,
/// the town hall, a windmill, fields and a cottage.
extension VillageRenderer {
    static let greenhouseCenter = (x: 30, base: 224)
    static let bakeryCenter = (x: 180, base: 140)
    static let townHallCenter = (x: 128, base: 140)
    static let fountain = (x: 128, y: 184)

    static func townGround(_ p: Painter, t: Double) {
        townSquare(p)
        farmField(p, t: t)
    }

    static func townSquare(_ p: Painter) {
        // Cobbled square in front of the town hall, joining both streets.
        let cx = fountain.x, cy = fountain.y
        p.rect(cx - 9, 150, 18, 82, Color(hex: 0xB8A98F))
        p.rect(cx - 8, 150, 16, 82, Color(hex: 0xD6CAB0))
        for dy in -17...17 {
            let half = Int((Double(289 - dy * dy)).squareRoot() * 1.6)
            p.rect(cx - half - 1, cy + dy, half * 2 + 2, 1, Color(hex: 0xB8A98F))
        }
        for dy in -16...16 {
            let half = Int((Double(256 - dy * dy)).squareRoot() * 1.6)
            p.rect(cx - half, cy + dy, half * 2, 1, Color(hex: 0xD6CAB0))
        }
        for y in stride(from: 152, to: 230, by: 3) {
            for x in stride(from: cx - 26 + (y % 2) * 2, to: cx + 27, by: 4) {
                let dx = Double(x - cx) / 1.6, dy = Double(y - cy)
                if dx * dx + dy * dy < 250 || abs(x - cx) < 7 { p.dot(x, y, Color(hex: 0xC4B79C)) }
            }
        }
    }

    /// The edge of the woods behind the high street.
    static func backdrop(_ p: Painter, t: Double) {
        for x in stride(from: -4, to: W, by: 9) where !(116...138).contains(x) {
            let y = 70 + noise(x, 7) % 10
            tree(p, x: x, y: y, index: x + 3)
        }
    }

    static let field = (x: 148, y: 244, w: 68, h: 24)

    /// A fenced wheat field: rows of stalks with heads that sway, changing with the season.
    static func farmField(_ p: Painter, t: Double) {
        let fx = field.x, fy = field.y, fw = field.w, fh = field.h
        p.rect(fx - 1, fy - 1, fw + 2, fh + 2, Color(hex: 0x5A3E2B))
        p.rect(fx, fy, fw, fh, Color(hex: 0x8A6A4A))
        for row in stride(from: fy + 3, to: fy + fh, by: 4) {
            p.rect(fx, row + 1, fw, 1, Color(hex: 0x6E5238))
        }
        let (stalk, head, headLight): (UInt32, UInt32, UInt32) = {
            switch season {
            case .winter: return (0xB8A88A, 0xE9EEF2, 0xFFFFFF)
            case .spring: return (0x5E9E58, 0x8CC56C, 0xA6D682)
            case .summer: return (0x9CB04A, 0xD9C25A, 0xF0DC7A)
            case .autumn: return (0xB8902E, 0xE8B83E, 0xF7D77A)
            }
        }()
        for row in stride(from: fy + 3, to: fy + fh, by: 4) {
            for x in stride(from: fx + 1 + (row / 4 % 2), to: fx + fw - 1, by: 2) {
                let wave = sin(t * 1.6 - Double(x) * 0.18 + Double(row) * 0.3)
                let lean = wave > 0.45 ? 1 : (wave < -0.45 ? -1 : 0)
                let h = 4 + noise(x, row) % 2
                p.rect(x, row - h + 2, 1, h - 1, Color(hex: stalk))
                p.dot(x + lean, row - h + 1, Color(hex: head))
                p.dot(x + lean, row - h, Color(hex: headLight))
            }
        }
        // Wooden fence on the near side, with a gate gap.
        let fenceY = fy + fh + 1
        p.rect(fx - 2, fenceY + 1, fw + 4, 1, Color(hex: 0x8A6A4A))
        p.rect(fx - 2, fenceY + 3, fw + 4, 1, Color(hex: 0x8A6A4A))
        for x in stride(from: fx - 2, through: fx + fw + 1, by: 6) where !(fx + 30...fx + 36).contains(x) {
            p.rect(x, fenceY - 1, 2, 6, Color(hex: 0x3A2A1E))
            p.rect(x, fenceY - 1, 1, 6, Color(hex: 0xA8805A))
        }
        // Scarecrow standing in the wheat.
        let sx = fx + 52, sy = fy + 4
        p.rect(sx, sy - 4, 1, 14, Color(hex: 0x6B4A2E))
        p.rect(sx - 5, sy, 11, 1, Color(hex: 0x6B4A2E))
        box(p, sx - 2, sy - 9, 5, 4, Color(hex: 0xF2D9A0))
        p.dot(sx - 1, sy - 8, ink); p.dot(sx + 1, sy - 8, ink)
        p.rect(sx - 4, sy - 11, 9, 2, Color(hex: 0xD9A441))
        p.rect(sx - 2, sy - 12, 5, 1, Color(hex: 0xD9A441))
        box(p, sx - 2, sy - 4, 5, 6, Color(hex: 0xC65F4A))
        p.dot(sx - 5, sy + 1, Color(hex: 0xF2D9A0)); p.dot(sx + 5, sy + 1, Color(hex: 0xF2D9A0))
        // A basket of harvest by the gate.
        box(p, fx + 38, fenceY + 2, 6, 4, Color(hex: 0xB8865A))
        for k in 0..<3 { p.rect(fx + 39 + k * 2, fenceY, 1, 2, Color(hex: head)) }
    }

    /// The farmer walks the edge of the field, stopping now and then to check the wheat.
    static func farmer(_ p: Painter, t: Double) {
        let left = Double(field.x + 4), right = Double(field.x + field.w - 18)
        let cycle = 24.0
        let ph = t.truncatingRemainder(dividingBy: cycle)
        let x: Double, walking: Bool, facingLeft: Bool
        switch ph {
        case ..<9: x = left + (right - left) * ph / 9; walking = true; facingLeft = false
        case ..<12: x = right; walking = false; facingLeft = false
        case ..<21: x = right - (right - left) * (ph - 12) / 9; walking = true; facingLeft = true
        default: x = left; walking = false; facingLeft = true
        }
        let y = field.y + field.h - 13
        p.rect(Int(x) + 3, y + 15, 10, 2, shadow)
        let frame = walking ? Int(t * 6) % 2 : 0
        let bend = !walking && Int(t * 1.5) % 2 == 0 ? 1 : 0
        p.walking(Sprites.farmer, x: Int(x), y: y + bend, flip: facingLeft, frame: frame)
        // A sickle over the shoulder.
        let hx = facingLeft ? Int(x) + 1 : Int(x) + 14
        p.rect(hx, y + 6 + bend, 1, 5, Color(hex: 0x8A6A4A))
        p.rect(facingLeft ? hx - 2 : hx, y + 5 + bend, 3, 1, Color(hex: 0xC4C9D2))
    }

    static func town(_ p: Painter, t: Double, state: SceneState) {
        farmer(p, t: t)
        let fx = fountain.x, fy = fountain.y
        marketStall(p, x: fx - 46, y: fy - 18, awning: Color(hex: 0x4A6FA5), goods: [0xD9534F, 0xF2C14E, 0x78B86A])
        marketStall(p, x: fx + 30, y: fy - 18, awning: Color(hex: 0x6E8B5E), goods: [0xF49AC1, 0xFFE38A, 0xC9A0F0])
        fountainDraw(p, t: t)
        bench(p, x: fx - 24, y: fy + 14)
        bench(p, x: fx + 14, y: fy + 14)
        pigeons(at(p, (fx - 64, fy - 268)), t: t)
        greenhouse(p, t: t, state: state)
        bakery(p, t: t, state: state)
        windmill(at(p, (220, -148)), t: t)
        townHall(p, t: t)
        noticeBoard(at(p, (66, -200)), t: t)
        cottage(at(p, (120, -292)), t: t)
        studyHall(p, t: t, state: state)
        for (x, y) in [(20, 166), (40, 176), (176, 166), (214, 174), (232, 162)] { flowerBed(p, x: x, y: y) }
    }

    static func flowerBed(_ p: Painter, x: Int, y: Int) {
        box(p, x, y, 14, 5, Color(hex: 0x8A6A4A))
        let colors: [UInt32] = season == .winter ? [0xE9EEF2] : [0xF49AC1, 0xFFE38A, 0xC9A0F0, 0xF4845F]
        for i in 0..<6 {
            let fx = x + 1 + i * 2 + (i % 2)
            p.dot(fx, y + 2, Color(hex: 0x5E9E58))
            p.dot(fx, y + 1, Color(hex: colors[(x + i) % colors.count]))
        }
    }

    // MARK: Square

    static func fountainDraw(_ p: Painter, t: Double) {
        let cx = fountain.x, cy = fountain.y
        // Basin.
        for dy in -5...5 {
            let half = Int((Double(25 - dy * dy)).squareRoot() * 2.2)
            p.rect(cx - half - 1, cy + dy, half * 2 + 2, 1, ink)
        }
        for dy in -4...4 {
            let half = Int((Double(16 - dy * dy)).squareRoot() * 2.2)
            p.rect(cx - half, cy + dy, half * 2, 1, Color(hex: 0xBFC5CC))
        }
        for dy in -3...3 {
            let half = Int((Double(9 - dy * dy)).squareRoot() * 2.2)
            p.rect(cx - half, cy + dy, half * 2, 1, weather == .snow ? Color(hex: 0xD8E6F0) : water)
        }
        // Pillar and bowl.
        box(p, cx - 1, cy - 10, 2, 10, Color(hex: 0xBFC5CC))
        box(p, cx - 4, cy - 12, 8, 2, Color(hex: 0xBFC5CC))
        guard weather != .snow else { return }
        // Water arcs.
        for side in [-1.0, 1.0] {
            for i in 0..<8 {
                let k = (t * 1.4 + Double(i) / 8).truncatingRemainder(dividingBy: 1)
                let x = Double(cx) + side * k * 8
                let y = Double(cy - 13) - sin(k * .pi) * 5 + k * 10
                p.dot(Int(x), Int(y), waterLight.opacity(0.95 - k * 0.4))
            }
        }
        p.rect(cx - 1, cy - 15, 2, 3, waterLight)
        let r = Int((t * 3).truncatingRemainder(dividingBy: 4))
        p.rect(cx - 2 - r, cy + 1, 4 + 2 * r, 1, waterLight.opacity(0.7 - Double(r) * 0.15))
    }

    static func marketStall(_ p: Painter, x: Int, y: Int, awning: Color, goods: [UInt32]) {
        p.rect(x + 1, y + 14, 16, 2, shadow)
        box(p, x, y + 7, 16, 6, Color(hex: 0xA87A4F))
        p.rect(x, y + 7, 16, 1, Color(hex: 0xC4956A))
        for (i, c) in goods.enumerated() {
            for j in 0..<2 {
                p.rect(x + 2 + i * 5 + j * 2, y + 5, 2, 2, Color(hex: c))
                p.dot(x + 2 + i * 5 + j * 2, y + 5, Color.white.opacity(0.4))
            }
        }
        p.rect(x + 1, y + 1, 1, 7, Color(hex: 0x6B4A2E))
        p.rect(x + 14, y + 1, 1, 7, Color(hex: 0x6B4A2E))
        p.rect(x - 2, y - 2, 20, 4, ink)
        for i in 0..<18 {
            let c = (i / 3) % 2 == 0 ? awning : Color(hex: 0xFFF6E5)
            p.rect(x - 1 + i, y - 1, 1, 2, c)
            if i % 3 == 1 { p.dot(x - 1 + i, y + 1, c) }
        }
        if weather == .snow { p.rect(x - 1, y - 2, 18, 1, Color(hex: 0xF4F7FB)) }
    }

    static func bench(_ p: Painter, x: Int, y: Int) {
        box(p, x, y, 10, 1, Color(hex: 0xA87A4F))
        box(p, x, y - 3, 10, 1, Color(hex: 0x946A44))
        p.rect(x + 1, y + 2, 1, 2, ink)
        p.rect(x + 8, y + 2, 1, 2, ink)
    }

    static func pigeons(_ p: Painter, t: Double) {
        for i in 0..<3 {
            let hop = Int(t * 2 + Double(i)) % 5 == 0 ? -1 : 0
            let x = 48 + i * 11 + Int(2 * sin(t * 0.3 + Double(i)))
            let y = 279 + (i % 2) * 2 + hop
            let peck = Int(t * 3 + Double(i)) % 4 == 0
            p.rect(x, y, 3, 2, Color(hex: 0x9AA0AE))
            p.dot(x + (peck ? 3 : 2), y - (peck ? 0 : 1), Color(hex: 0x7E8592))
            p.dot(x + 1, y + 2, Color(hex: 0xE8964A))
        }
    }

    // MARK: Buildings

    static func greenhouse(_ p: Painter, t: Double, state: SceneState) {
        let cx = greenhouseCenter.x, base = greenhouseCenter.base
        let x0 = cx - 15, w = 30, top = base - 20
        p.rect(x0 + 2, base + 1, w + 2, 2, shadow)
        // Arched glass roof.
        for r in 0..<8 {
            let inset = Int((Double(64 - (8 - r) * (8 - r))).squareRoot().rounded(.down))
            let left = x0 + 8 - inset
            let rowW = w - 2 * (8 - inset)
            p.rect(left - 1, top - 8 + r, rowW + 2, 1, ink)
        }
        for r in 0..<8 {
            let inset = Int((Double(64 - (8 - r) * (8 - r))).squareRoot().rounded(.down))
            let left = x0 + 8 - inset
            let rowW = w - 2 * (8 - inset)
            p.rect(left, top - 8 + r, max(0, rowW), 1, Color(hex: 0xBFE3E8).opacity(0.95))
        }
        // Glass walls.
        box(p, x0, top, w, 20, Color(hex: 0xBFE3E8))
        for x in stride(from: x0 + 5, to: x0 + w, by: 6) { p.rect(x, top - 6, 1, 26, Color(hex: 0x6E8B5E)) }
        p.rect(x0, top + 9, w, 1, Color(hex: 0x6E8B5E))
        // Plants inside: one per habit, green when watered today.
        let total = max(state.habitCount, 0)
        let done = state.habitsDone
        for i in 0..<min(total, 8) {
            let px = x0 + 3 + i * 3 + (i / 4)
            let watered = i < done
            let h = watered ? 7 + (i % 3) : 3
            p.rect(px, top + 18 - h, 1, h, Color(hex: watered ? 0x4C8648 : 0x9AA884))
            p.rect(px - 1, top + 18 - h, 3, 2, Color(hex: watered ? 0x78B86A : 0xB7C29E))
            if watered && i % 2 == 0 { p.dot(px, top + 17 - h, Color(hex: [0xF49AC1, 0xFFE38A, 0xF4845F][i % 3])) }
        }
        if total == 0 {
            for i in 0..<5 { p.rect(x0 + 4 + i * 5, top + 16, 3, 2, Color(hex: 0x8A6A4A)) }
        }
        // Shine and door.
        p.rect(x0 + 2, top + 2, 1, 5, Color.white.opacity(0.7))
        p.rect(x0 + 3, top + 1, 1, 2, Color.white.opacity(0.7))
        carvedSign(p, "HABITS", cx: cx, top: top - 7)
        door(p, x: cx - 3, y: base - 9, w: 6, h: 9, color: Color(hex: 0x6E8B5E))
        p.rect(x0 - 1, base, w + 2, 1, ink)
        // Watering can.
        box(p, x0 + w + 3, base - 4, 4, 3, Color(hex: 0x4A6FA5))
        p.rect(x0 + w + 7, base - 5, 2, 1, Color(hex: 0x4A6FA5))
        if weather == .snow { p.rect(x0 + 4, top - 8, w - 8, 1, Color(hex: 0xF4F7FB)) }
    }

    static func bakery(_ p: Painter, t: Double, state: SceneState) {
        let style = HouseStyle(
            wall: Color(hex: 0xFBE6D4), wallDark: Color(hex: 0xEDD0B8),
            roof: Color(hex: 0xC2577A), roofDark: Color(hex: 0xA2445F), roofLight: Color(hex: 0xDB7C9A)
        )
        let cx = bakeryCenter.x, base = bakeryCenter.base
        box(p, cx + 6, base - 34, 4, 7, Color(hex: 0xA8796A))
        house(p, cx: cx, base: base, w: 28, wallH: 17, roofRows: 9, style: style)
        carvedSign(p, "TREATS", cx: cx, top: base - 25)
        // Chimney smoke, warm and sweet.
        for i in 0..<4 {
            let k = (t * 0.4 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
            let size = 1 + Int(k * 2)
            p.rect(cx + 7 + Int(sin(k * 6) * 2), base - 36 - Int(k * 14), size, size, Color.white.opacity(0.8 * (1 - k)))
        }
        // Striped awning and window display.
        p.rect(cx - 13, base - 13, 26, 3, ink)
        for x in (cx - 12)..<(cx + 12) {
            let c = ((x - cx + 12) / 2) % 2 == 0 ? Color(hex: 0xC2577A) : Color(hex: 0xFFF6E5)
            p.rect(x, base - 12, 1, 2, c)
        }
        box(p, cx - 11, base - 9, 7, 6, Color(hex: 0xFFE2A8))
        p.rect(cx - 10, base - 5, 2, 1, Color(hex: 0xC69C6D))
        p.rect(cx - 7, base - 5, 2, 1, Color(hex: 0xE8A0B0))
        box(p, cx + 4, base - 9, 7, 6, Color(hex: 0xFFE2A8))
        p.rect(cx + 5, base - 5, 2, 1, Color(hex: 0xF2C14E))
        p.rect(cx + 8, base - 5, 2, 1, Color(hex: 0xC69C6D))
        door(p, x: cx - 2, y: base - 9, w: 5, h: 9, color: Color(hex: 0x8E5A3B))
        if state.treats > 0 {
            p.glow(Double(cx), Double(base - 6), radius: 10, Color(hex: 0xFFD27A), 0.25)
        }
    }

    static func townHall(_ p: Painter, t: Double) {
        let cx = townHallCenter.x, base = townHallCenter.base
        let w = 40, x0 = cx - w / 2, top = base - 22
        p.rect(x0 + 2, base + 1, w + 2, 2, shadow)
        // Pediment.
        for r in 0..<8 {
            let rowW = 8 + r * 5
            p.rect(cx - rowW / 2 - 1, top - 9 + r, rowW + 2, 1, ink)
        }
        for r in 0..<8 {
            let rowW = 8 + r * 5
            p.rect(cx - rowW / 2, top - 9 + r, rowW, 1, Color(hex: 0xE8E2D4))
        }
        box(p, cx - 4, top - 6, 8, 4, Color(hex: 0xF2C14E))
        p.dot(cx, top - 4, ink)
        // Walls and columns.
        box(p, x0, top, w, 22, Color(hex: 0xF1EBDD))
        p.rect(x0 - 2, top - 1, w + 4, 2, Color(hex: 0xC9C0AC))
        for x in stride(from: x0 + 3, to: x0 + w - 2, by: 7) {
            p.rect(x, top + 1, 3, 19, Color(hex: 0xDAD2BF))
            p.rect(x, top + 1, 1, 19, Color.white.opacity(0.5))
        }
        carvedSign(p, "MY WEEK", cx: cx, top: top + 1)
        door(p, x: cx - 4, y: base - 12, w: 8, h: 12, color: Color(hex: 0x6B4A2E))
        p.rect(x0 - 2, base - 1, w + 4, 1, Color(hex: 0xA39686))
        p.rect(x0 - 3, base, w + 6, 2, Color(hex: 0xC9C0AC))
        p.rect(x0 - 3, base + 2, w + 6, 1, ink)
        // Flag on top.
        p.rect(cx, top - 18, 1, 9, ink)
        let wave = Int(t * 3) % 2
        p.rect(cx + 1, top - 18 + wave, 6, 3, Color(hex: 0xC65F4A))
        p.rect(cx + 1, top - 17 + wave, 6, 1, Color(hex: 0xF2C14E))
        if weather == .snow { p.rect(cx - 18, top - 2, 36, 1, Color(hex: 0xF4F7FB)) }
    }

    static func noticeBoard(_ p: Painter, t: Double) {
        let x = 88, y = 378
        p.rect(x + 2, y + 10, 1, 8, ink)
        p.rect(x + 11, y + 10, 1, 8, ink)
        box(p, x, y, 14, 10, Color(hex: 0xA87A4F))
        let notes: [UInt32] = [0xFFF6E5, 0xFFE38A, 0xF7B7CF, 0xBFE3E8]
        for (i, c) in notes.enumerated() {
            p.rect(x + 1 + (i % 2) * 7, y + 1 + (i / 2) * 5, 5, 4, Color(hex: c))
            p.dot(x + 3 + (i % 2) * 7, y + 1 + (i / 2) * 5, Color(hex: 0xC65F4A))
        }
        let k = (t * 1.2).truncatingRemainder(dividingBy: 1)
        p.dot(x + 13, y - 2 - Int(k * 3), Color(hex: 0xFFF3B0).opacity(1 - k))
    }

    static func windmill(_ p: Painter, t: Double) {
        let cx = 14, base = 372
        p.rect(cx - 6, base + 1, 14, 2, shadow)
        // Tapered tower.
        for r in 0..<26 {
            let half = 4 + r / 5
            p.rect(cx - half - 1, base - 26 + r, half * 2 + 2, 1, ink)
            p.rect(cx - half, base - 26 + r, half * 2, 1, r % 4 == 0 ? Color(hex: 0xD6C29E) : Color(hex: 0xEADAB9))
        }
        box(p, cx - 2, base - 7, 4, 7, Color(hex: 0x6B4A2E))
        box(p, cx - 1, base - 18, 2, 3, Color(hex: 0x9AA0AE))
        for r in 0..<5 { p.rect(cx - 5 + r, base - 31 + r, 10 - 2 * r, 1, Color(hex: 0x8E5A3B)) }
        // Spinning sails.
        let hubX = Double(cx), hubY = Double(base - 25)
        let angle = t * 0.9
        for blade in 0..<4 {
            let a = angle + Double(blade) * .pi / 2
            for step in 2..<13 {
                let x = hubX + cos(a) * Double(step)
                let y = hubY + sin(a) * Double(step)
                p.dot(Int(x.rounded()), Int(y.rounded()), ink)
                if step > 4 {
                    let sx = x + cos(a + .pi / 2) * 2
                    let sy = y + sin(a + .pi / 2) * 2
                    p.dot(Int(sx.rounded()), Int(sy.rounded()), Color(hex: 0xFFF6E5))
                    p.dot(Int(((x + sx) / 2).rounded()), Int(((y + sy) / 2).rounded()), Color(hex: 0xFFF6E5))
                }
            }
        }
        box(p, cx - 1, base - 26, 2, 2, Color(hex: 0x6B4A2E))
    }

    static func cottage(_ p: Painter, t: Double) {
        let style = HouseStyle(
            wall: Color(hex: 0xEFE3CC), wallDark: Color(hex: 0xDDCDAF),
            roof: Color(hex: 0x8E6B4A), roofDark: Color(hex: 0x74563A), roofLight: Color(hex: 0xA8845E)
        )
        house(p, cx: 102, base: 432, w: 18, wallH: 11, roofRows: 6, style: style)
        window(p, x: 96, y: 424, w: 4, h: 4, glass: Color(hex: 0xFFE2A8), shutter: nil)
        door(p, x: 103, y: 425, w: 4, h: 7, color: Color(hex: 0x6B4A2E))
        p.rect(91, 433, 22, 1, Color(hex: 0xC9A27A))
        for x in stride(from: 91, to: 113, by: 3) { p.rect(x, 430, 1, 3, Color(hex: 0xC9A27A)) }
    }

    static func townLights(_ p: Painter, strength: Double, state: SceneState) {
        p.glow(Double(bakeryCenter.x) - 7.5, Double(bakeryCenter.base) - 6, radius: 9, warm, 0.5 * strength)
        p.glow(Double(bakeryCenter.x) + 7.5, Double(bakeryCenter.base) - 6, radius: 9, warm, 0.5 * strength)
        p.glow(Double(greenhouseCenter.x), Double(greenhouseCenter.base) - 10, radius: 16, Color(hex: 0xC8F0C0), 0.35 * strength)
        p.glow(Double(townHallCenter.x), Double(townHallCenter.base) - 6, radius: 12, warm, 0.4 * strength)
        p.glow(220, 134, radius: 6, warm, 0.5 * strength)
        studyHallLights(p, strength: strength)
        // Lanterns by the bakery, town hall and greenhouse doors.
        porchLantern(p, x: bakeryCenter.x + 5, y: bakeryCenter.base - 10, t: 0, strength: strength)
        porchLantern(p, x: townHallCenter.x + 6, y: townHallCenter.base - 13, t: 0, strength: strength)
        porchLantern(p, x: greenhouseCenter.x + 5, y: greenhouseCenter.base - 10, t: 0, strength: strength)
        for (x, y) in townLamps {
            p.glow(Double(x) + 0.5, Double(y) - 1.5, radius: 12, warm, 0.45 * strength)
            p.dot(x, y - 2, warm)
        }
    }

    static let townLamps: [(Int, Int)] = []

    static func townLampPosts(_ p: Painter) {
        for (x, y) in townLamps {
            p.rect(x + 1, y + 10, 3, 1, shadow)
            box(p, x, y, 1, 10, Color(hex: 0x3D3F63))
            box(p, x - 1, y - 3, 3, 3, Color(hex: 0x3D3F63))
            p.dot(x, y - 2, Color(hex: 0xE8D8A8))
        }
    }
}
