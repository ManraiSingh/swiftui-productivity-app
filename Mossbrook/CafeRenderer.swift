import SwiftUI

/// Draws the inside of Bea's café: a warm room full of people working, and you walking around in it.
enum CafeRenderer {
    static let ink = VillageRenderer.ink
    static let beam = Color(hex: 0x3A2218)
    static let wall = Color(hex: 0x5C3A26)
    static let wallLight = Color(hex: 0x6E4630)
    static let wallDark = Color(hex: 0x4A2C1D)
    static let wood = Color(hex: 0xC07A40)
    static let woodLight = Color(hex: 0xD99456)
    static let woodDark = Color(hex: 0x8A5230)
    static let floor = Color(hex: 0xA9683A)
    static let floorLine = Color(hex: 0x8E5530)
    static let green = Color(hex: 0x5F7F4B)
    static let greenDark = Color(hex: 0x4A6639)
    static let greenLight = Color(hex: 0x78985E)
    static let cream = Color(hex: 0xF4E3B5)

    // MARK: The visitor who drops by, orders, works a while and leaves.

    struct Visitor {
        let point: CGPoint
        let walking: Bool
        let facingLeft: Bool
        let seated: Bool
        let visible: Bool
    }

    private struct Leg { let to: CGPoint; let wait: Double; let seated: Bool }

    private static let visitorLegs: [Leg] = {
        let seat = CafeLayout.seats[CafeLayout.visitorSeat].aisle
        return [
            Leg(to: CGPoint(x: 114, y: 214), wait: 0, seated: false),
            Leg(to: CGPoint(x: 114, y: 92), wait: 0, seated: false),
            Leg(to: CGPoint(x: 96, y: 92), wait: 5, seated: false),
            Leg(to: CGPoint(x: 114, y: 92), wait: 0, seated: false),
            Leg(to: CGPoint(x: 114, y: seat.y), wait: 0, seated: false),
            Leg(to: seat, wait: 26, seated: true),
            Leg(to: CGPoint(x: 114, y: seat.y), wait: 0, seated: false),
            Leg(to: CGPoint(x: 114, y: 214), wait: 0, seated: false),
            Leg(to: CafeLayout.door, wait: 12, seated: false)
        ]
    }()

    private static let visitorCycle: Double = {
        var total = 0.0
        var from = CafeLayout.door
        for leg in visitorLegs {
            total += hypot(leg.to.x - from.x, leg.to.y - from.y) / 26 + leg.wait
            from = leg.to
        }
        return total
    }()

    static func visitor(at t: Double) -> Visitor {
        var time = t.truncatingRemainder(dividingBy: visitorCycle)
        var from = CafeLayout.door
        for (i, leg) in visitorLegs.enumerated() {
            let walk = hypot(leg.to.x - from.x, leg.to.y - from.y) / 26
            if time < walk {
                let k = time / max(walk, 0.001)
                let p = CGPoint(x: from.x + (leg.to.x - from.x) * k, y: from.y + (leg.to.y - from.y) * k)
                return Visitor(point: p, walking: true, facingLeft: leg.to.x < from.x, seated: false, visible: true)
            }
            time -= walk
            if time < leg.wait {
                let last = i == visitorLegs.count - 1
                return Visitor(point: leg.to, walking: false, facingLeft: true, seated: leg.seated, visible: !last)
            }
            time -= leg.wait
            from = leg.to
        }
        return Visitor(point: CafeLayout.door, walking: false, facingLeft: false, seated: false, visible: false)
    }

    /// Bea moves between the register and the espresso machine.
    static func baristaX(at date: Date, brewing: Bool) -> Double {
        if brewing { return 46 }
        let p = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 20)
        switch p {
        case ..<6: return 92
        case ..<9: return 92 - (p - 6) / 3 * 34
        case ..<14: return 58
        case ..<17: return 58 + (p - 14) / 3 * 34
        default: return 92
        }
    }

    // MARK: Drawing

    static func draw(
        _ p: Painter, t: Double, rows: Int, phase: DayPhase, level: Int,
        you: (point: CGPoint, walking: Bool, facingLeft: Bool), scene: CafeScene,
        fill: Double, visitor: Visitor, beaX: Double, onBreak: Bool = false, eating: Bool = false, breakT: Double = 0
    ) {
        room(p, t: t, rows: rows, phase: phase)
        counter(p, t: t, beaX: beaX, brewing: scene.mode == .brewing)

        // Everything on the floor is drawn back to front.
        var items: [(Double, () -> Void)] = []
        for table in CafeLayout.tables {
            items.append((Double(table.top + 9), { self.table(p, table) }))
        }
        for regular in CafeLayout.regulars {
            if let seat = CafeLayout.seats.first(where: { $0.id == regular.seat }) {
                items.append((Double(seat.top + 15), { seated(p, sprite: regular.sprite, seat: seat, t: t) }))
                items.append((Double(seat.top + 26), { laptopAndCup(p, seat: seat, t: t, mug: nil) }))
            }
        }
        let vSeat = CafeLayout.seats[CafeLayout.visitorSeat]
        if visitor.seated {
            items.append((Double(vSeat.top + 15), { seated(p, sprite: Sprites.customers[5], seat: vSeat, t: t) }))
            items.append((Double(vSeat.top + 26), { laptopAndCup(p, seat: vSeat, t: t, mug: nil) }))
        } else {
            items.append((Double(vSeat.top + 15), { emptyChair(p, seat: vSeat) }))
            if visitor.visible {
                items.append((visitor.point.y, { walker(p, Sprites.customers[5], at: visitor.point, walking: visitor.walking, facingLeft: visitor.facingLeft, t: t, cup: nil) }))
            }
        }
        for seat in CafeLayout.freeSeats where !(scene.mode == .seated && scene.seatID == seat.id) {
            items.append((Double(seat.top + 15), { emptyChair(p, seat: seat) }))
        }
        if scene.mode == .seated && onBreak, let id = scene.seatID, let seat = CafeLayout.seats.first(where: { $0.id == id }) {
            items.append((Double(seat.top + 15), { emptyChair(p, seat: seat) }))
            items.append((Double(seat.top + 26), { laptopAndCup(p, seat: seat, t: t, mug: (scene.drink.color, fill)) }))
            let tour = breakTour(seat, elapsed: breakT)
            items.append((tour.point.y, { walker(p, Sprites.you, at: tour.point, walking: tour.walking, facingLeft: tour.facingLeft, t: t, cup: eating ? Color(hex: 0xD99456) : nil) }))
        } else if scene.mode == .seated, let id = scene.seatID, let seat = CafeLayout.seats.first(where: { $0.id == id }) {
            items.append((Double(seat.top + 15), { seated(p, sprite: Sprites.you, seat: seat, t: t) }))
            items.append((Double(seat.top + 26), { laptopAndCup(p, seat: seat, t: t, mug: (scene.drink.color, fill)) }))
        } else {
            let cup: Color? = scene.mode == .holding ? scene.drink.color : nil
            items.append((you.point.y, { walker(p, Sprites.you, at: you.point, walking: you.walking, facingLeft: you.facingLeft, t: t, cup: cup) }))
        }
        // Lounge: one long couch with someone curled up reading.
        items.append((214, { couch(p, t: t) }))
        items.append((222, { coffeeTable(p, t: t) }))
        if level >= 3 {
            items.append((225, { p.sprite(Sprites.sleepyCat, x: 90, y: 214 + (Int(t) % 4 == 0 ? -1 : 0)) }))
        }
        // Green library lamps on the long table.
        items.append((127, {
            for x in [27, 101] {
                p.glow(Double(x) + 2, 112, radius: 12, Color(hex: 0xFFE2A0), 0.4)
                p.rect(x + 1, 112, 3, 1, Color(hex: 0xD9A441))
                p.rect(x + 2, 108, 1, 4, Color(hex: 0xD9A441))
                VillageRenderer.box(p, x, 106, 5, 2, Color(hex: 0x2F6B4A))
                p.rect(x, 108, 5, 1, Color(hex: 0xFFE38A))
            }
        }))
        for item in items.sorted(by: { $0.0 < $1.0 }) { item.1() }

        // Glowing markers on free seats when you're holding your drink.
        if scene.mode == .holding {
            let bounce = Int(t * 3) % 2
            for seat in CafeLayout.freeSeats {
                p.glow(Double(seat.x + 8), Double(seat.top + 10), radius: 9, Color(hex: 0xFFE38A), 0.45)
                let ax = seat.x + 6, ay = seat.top - 4 + bounce
                p.rect(ax - 1, ay - 1, 6, 3, ink)
                p.rect(ax, ay, 4, 1, Color(hex: 0xF2C14E))
                p.rect(ax + 1, ay + 1, 2, 1, Color(hex: 0xF2C14E))
                p.dot(ax + 1, ay + 2, ink); p.dot(ax + 2, ay + 2, ink)
            }
        }

        // Light.
        if phase == .night { p.rect(0, 0, 128, rows, Color(hex: 0x1A1033).opacity(0.2)) }
        if phase == .dusk { p.rect(0, 0, 128, rows, Color(hex: 0xFF8A40).opacity(0.05)) }
        stringLights(p, t: t, phase: phase)
        p.rect(0, 0, 2, rows, Color.black.opacity(0.15))
        p.rect(126, 0, 2, rows, Color.black.opacity(0.15))
    }

    // MARK: Room

    static func room(_ p: Painter, t: Double, rows: Int, phase: DayPhase) {
        let box = VillageRenderer.box
        p.rect(0, 0, 128, 82, wall)
        for x in stride(from: 0, to: 128, by: 12) {
            p.rect(x, 10, 1, 72, wallDark)
            p.rect(x + 1, 10, 1, 72, wallLight)
        }
        p.rect(0, 0, 128, 9, beam)
        p.rect(0, 9, 128, 1, ink)

        // Window.
        let bands: [UInt32]
        switch phase {
        case .day: bands = [0xF7C978, 0xFBDC96, 0xFDEBB8, 0xFFF4D2]
        case .dusk: bands = [0xD9734A, 0xEE9A58, 0xF6C27A, 0xFADB9C]
        case .night: bands = [0x1E2347, 0x262B55, 0x2F3563, 0x3A3F70]
        }
        let wx = 3, wy = 15, ww = 30, wh = 56
        p.rect(wx - 2, wy - 2, ww + 4, wh + 4, ink)
        for (i, c) in bands.enumerated() { p.rect(wx, wy + i * wh / 4, ww, wh / 4 + 1, Color(hex: c)) }
        if phase == .night {
            for i in 0..<8 { p.dot(wx + 2 + noise(i, 3) % (ww - 4), wy + 2 + noise(i, 5) % 28, Color.white.opacity(0.9)) }
            VillageRenderer.circle(p, cx: wx + 21, cy: wy + 10, r: 3, Color(hex: 0xF4EBC8))
        } else {
            let sun = phase == .day ? Color(hex: 0xFFF6DA) : Color(hex: 0xFFD08A)
            p.glow(Double(wx + 18), Double(wy + 36), radius: 18, sun, 0.8)
            VillageRenderer.circle(p, cx: wx + 18, cy: wy + 36, r: 4, sun)
        }
        let roofs = phase == .night ? Color(hex: 0x2A2440) : Color(hex: 0xB86E40)
        p.rect(wx, wy + wh - 9, ww, 9, roofs)
        p.rect(wx + 3, wy + wh - 13, 8, 4, roofs)
        p.rect(wx + 17, wy + wh - 12, 9, 3, roofs)
        for x in [wx + 9, wx + 19] { p.rect(x, wy, 2, wh, woodDark); p.rect(x, wy, 1, wh, ink) }
        p.rect(wx, wy + 26, ww, 2, woodDark)
        box(p, wx - 1, wy + wh, ww + 2, 2, wood, ink)

        // Sign and boards.
        box(p, 40, 18, 86, 11, cream, woodDark)
        p.rect(41, 19, 84, 1, Color.white.opacity(0.5))
        box(p, 40, 31, 42, 16, green, woodDark)
        p.rect(41, 32, 40, 1, greenLight)
        box(p, 87, 33, 39, 12, green, woodDark)
        for (i, y) in [36, 39, 42].enumerated() {
            p.rect(90, y, 20 - i * 4, 1, cream.opacity(0.6))
            p.rect(114, y, 8, 1, cream.opacity(0.6))
        }

        // Floor and sunbeams.
        p.rect(0, 80, 128, rows - 80, floor)
        p.rect(0, 80, 128, 1, ink)
        for y in stride(from: 86, to: rows, by: 6) {
            p.rect(0, y, 128, 1, floorLine)
            for x in stride(from: (y / 6 % 2) * 16, to: 128, by: 32) { p.rect(x, y - 5, 1, 5, floorLine) }
        }
        if phase != .night {
            let beamColor = Color(hex: 0xFFE2A0).opacity(phase == .day ? 0.12 : 0.15)
            for start in [6, 18] {
                for y in stride(from: wy + 10, to: rows, by: 2) {
                    p.rect(start + (y - wy) / 2, y, 7, 2, beamColor)
                }
            }
        }

        // Doorway on the right, with warm light spilling in.
        p.rect(121, 196, 7, 24, ink)
        p.rect(122, 197, 6, 22, phase == .night ? Color(hex: 0x2F3563) : Color(hex: 0xFBE3A8))
        p.rect(112, 218, 14, 3, Color(hex: 0x6E8B5E))
        p.glow(122, 208, radius: 14, Color(hex: 0xFFE2A0), phase == .night ? 0.1 : 0.3)

        bookshelf(p, x: 0, top: 96, h: 104)
        plant(p, x: 0, y: 84)
        queueRope(p)
        lounge(p, t: t)
    }

    static func bookshelf(_ p: Painter, x: Int, top: Int, h: Int) {
        p.rect(x, top - 1, 7, h + 2, ink)
        p.rect(x, top, 6, h, woodDark)
        let colors: [UInt32] = [0xC65F4A, 0x4A6FA5, 0xF2C14E, 0x6E8B5E, 0x8E5A8A, 0xE8A0B0, 0xD9824A]
        for shelf in stride(from: top + 2, to: top + h - 4, by: 10) {
            for i in 0..<5 {
                let height = 5 + noise(shelf, i) % 3
                p.rect(x + i, shelf + 8 - height, 1, height, Color(hex: colors[(shelf / 10 + i) % colors.count]))
            }
            p.rect(x, shelf + 8, 6, 1, wood)
        }
    }

    static func queueRope(_ p: Painter) {
        for x in [98, 110] {
            VillageRenderer.box(p, x, 84, 2, 8, Color(hex: 0xD9A441))
            p.rect(x - 1, 91, 4, 1, ink)
        }
        for x in 100..<110 { p.dot(x, 86 + (abs(x - 105) < 3 ? 1 : 0), Color(hex: 0xA94E3C)) }
    }

    /// A cozy corner at the bottom: a rug and a floor lamp; the couch and table are drawn with the people.
    static func lounge(_ base: Painter, t: Double) {
        let p = base.shifted(dy: -8)
        VillageRenderer.box(p, 30, 214, 78, 20, Color(hex: 0x8E3B32))
        p.rect(33, 217, 72, 14, Color(hex: 0xB5563E))
        p.rect(36, 220, 66, 8, Color(hex: 0x8E3B32))
        for x in stride(from: 38, to: 102, by: 5) { p.dot(x, 224, Color(hex: 0xF2C14E)) }
        for x in stride(from: 31, to: 108, by: 3) { p.dot(x, 234, Color(hex: 0xF4E3B5)) }
        // Floor lamp.
        p.rect(101, 196, 1, 26, ink)
        p.rect(99, 222, 5, 1, ink)
        VillageRenderer.box(p, 97, 191, 9, 4, Color(hex: 0xF4E3B5))
        p.rect(97, 194, 9, 1, Color(hex: 0xD8C390))
        p.glow(101.5, 198, radius: 14, Color(hex: 0xFFD27A), 0.45)
    }

    static func couch(_ base: Painter, t: Double) {
        let p = base.shifted(dy: -8)
        let fabric = Color(hex: 0x5F7F4B), fabricLight = Color(hex: 0x78985E), fabricDark = Color(hex: 0x4A6639)
        // Back and cushions.
        VillageRenderer.box(p, 36, 200, 56, 12, fabric)
        p.rect(36, 200, 56, 2, fabricLight)
        for x in [54, 73] { p.rect(x, 202, 1, 10, fabricDark) }
        // Someone curled up with a book on the left cushion.
        let bob = Int(t * 0.8) % 5 == 0 ? -1 : 0
        p.sprite(Sprites.customers[3].recolored(["g": Color(hex: 0xF2C14E)]), x: 38, y: 198 + bob)
        // Seat and arms in front of them.
        VillageRenderer.box(p, 36, 212, 56, 6, fabricLight)
        for x in [54, 73] { p.rect(x, 212, 1, 6, fabric) }
        VillageRenderer.box(p, 32, 204, 5, 15, fabric)
        VillageRenderer.box(p, 91, 204, 5, 15, fabric)
        p.rect(32, 204, 5, 1, fabricLight)
        p.rect(91, 204, 5, 1, fabricLight)
        p.rect(34, 220, 2, 2, ink)
        p.rect(92, 220, 2, 2, ink)
        // Her open book.
        VillageRenderer.box(p, 41, 210, 4, 4, Color(hex: 0xFFFDF6))
        VillageRenderer.box(p, 46, 210, 4, 4, Color(hex: 0xFFFDF6))
        p.rect(45, 210, 1, 4, Color(hex: 0xC65F4A))
        // A throw pillow and a blanket.
        VillageRenderer.box(p, 80, 207, 6, 5, Color(hex: 0xE8A0B0))
        p.rect(62, 212, 10, 2, Color(hex: 0xD9824A))
    }

    static func coffeeTable(_ base: Painter, t: Double) {
        let p = base.shifted(dy: -8)
        VillageRenderer.box(p, 48, 224, 32, 3, Color(hex: 0xC07A40))
        p.rect(48, 224, 32, 1, Color(hex: 0xD99456))
        p.rect(50, 228, 2, 3, ink)
        p.rect(76, 228, 2, 3, ink)
        VillageRenderer.box(p, 53, 221, 4, 3, Color(hex: 0xFFFDF6))
        p.rect(53, 221, 4, 1, Color(hex: 0x6B4226))
        steam(p, x: 54, y: 219, t: t)
        VillageRenderer.box(p, 70, 220, 4, 4, Color(hex: 0x9A5A3A))
        p.rect(69, 216, 6, 4, Color(hex: 0x5E9E58))
        VillageRenderer.box(p, 60, 222, 6, 2, Color(hex: 0x4A6FA5))
    }

    static func stringLights(_ p: Painter, t: Double, phase: DayPhase) {
        let colors: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A]
        for (i, x) in stride(from: 4, to: 126, by: 6).enumerated() {
            let y = 10 + (i % 2)
            let c = Color(hex: colors[i % colors.count])
            p.dot(x, y, ink)
            let twinkle = (Int(t * 2) + i) % 7 == 0 ? 0.35 : 0.6
            p.glow(Double(x) + 0.5, Double(y) + 1.5, radius: 3, c, phase == .day ? twinkle * 0.6 : twinkle)
            p.rect(x, y + 1, 1, 2, c)
        }
    }

    static func counter(_ p: Painter, t: Double, beaX: Double, brewing: Bool) {
        let box = VillageRenderer.box
        // Bea first, so the counter hides her legs.
        let bob = Int(t * 3) % 2 == 0 ? 0 : -1
        p.sprite(Sprites.bea, x: Int(beaX), y: 46 + bob, flip: beaX < 70)

        box(p, 42, 50, 13, 12, Color(hex: 0xB9BEC8), ink)
        p.rect(43, 51, 11, 2, Color(hex: 0xE3E6EC))
        p.rect(45, 54, 7, 2, Color(hex: 0x3D3F45))
        p.rect(47, 57, 2, 2, ink)
        for i in 0..<3 { box(p, 43 + i * 4, 46, 3, 3, Color.white, ink) }
        if brewing || Int(t * 2) % 4 == 0 {
            for i in 0..<3 {
                let k = (t * 0.8 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                p.rect(48 + i - 1, 49 - Int(k * 8), 1, 2, Color.white.opacity(0.8 * (1 - k)))
            }
        }
        box(p, 104, 54, 21, 8, Color(hex: 0xF6E2B8).opacity(0.9), ink)
        p.glow(114, 58, radius: 7, Color(hex: 0xFFE2A0), 0.5)
        for (i, c) in [0xE8A0B0, 0xC69C6D, 0xF2C14E].enumerated() {
            p.rect(106 + i * 6, 58, 4, 3, Color(hex: UInt32(c)))
            p.rect(106 + i * 6, 58, 4, 1, Color.white.opacity(0.7))
        }
        box(p, 92, 56, 8, 6, Color(hex: 0x3D3F45), ink)
        p.rect(93, 57, 6, 2, Color(hex: 0x9CD3A0))

        p.rect(38, 62, 90, 4, ink)
        p.rect(38, 62, 90, 3, wood)
        p.rect(38, 62, 90, 1, woodLight)
        box(p, 40, 66, 88, 14, green, ink)
        for x in stride(from: 44, to: 128, by: 5) {
            p.rect(x, 67, 1, 13, greenDark)
            p.rect(x + 1, 67, 1, 13, greenLight)
        }
        // Pick-up mat.
        box(p, 64, 63, 12, 1, Color(hex: 0x3D3F45), ink)
    }

    // MARK: Furniture and people

    static func table(_ p: Painter, _ t: CafeLayout.Table) {
        let left = t.left, top = t.top, w = t.w
        p.rect(left + 4, top + 19, w + 2, 2, Color.black.opacity(0.16))
        p.rect(left - 1, top - 1, w + 7, 8, ink)
        for r in 0..<6 { p.rect(left + r, top + r, w, 1, r % 2 == 0 ? wood : woodLight) }
        p.rect(left + 6, top + 6, w, 3, woodDark)
        p.rect(left + 6, top + 9, w, 1, ink)
        p.rect(left + 8, top + 10, 2, 9, woodDark)
        p.rect(left + w + 2, top + 10, 2, 9, woodDark)
        p.rect(left + 2, top + 6, 2, 10, Color(hex: 0x6E3F22))
    }

    static func chair(_ p: Painter, x: Int, top: Int) {
        p.rect(x + 1, top + 4, 2, 15, ink)
        p.rect(x + 13, top + 4, 2, 15, ink)
        p.rect(x + 2, top + 5, 1, 13, woodDark)
        p.rect(x + 13, top + 5, 1, 13, woodDark)
        p.rect(x + 1, top + 3, 14, 2, ink)
        p.rect(x + 2, top + 4, 12, 1, wood)
        for sx in [5, 8, 11] { p.rect(x + sx, top + 5, 1, 8, woodDark) }
    }

    // MARK: Breaks

    enum Talk: Equatable {
        case none, bea
        case seat(Int)
    }

    struct Tour {
        let point: CGPoint
        let walking: Bool
        let facingLeft: Bool
        let talk: Talk
        let talkTime: Double
        let stop: Int
        let lap: Int
    }

    /// Where you can stand to chat with someone at a table.
    static func standPoint(_ seat: CafeLayout.Seat) -> CGPoint {
        CGPoint(x: Double(seat.x + 8), y: seat.top < 140 ? 141 : 189)
    }

    /// The stops on a break: Bea at the counter, then a few people at their tables.
    static func breakStops(_ home: CafeLayout.Seat) -> [(CGPoint, Talk, Double)] {
        var stops: [(CGPoint, Talk, Double)] = [(CafeLayout.orderSpot, .bea, 10)]
        let strangers = CafeLayout.regulars.compactMap { r in CafeLayout.seats.first { $0.id == r.seat } }
            .filter { $0.id != home.id }
        for seat in strangers.prefix(3) { stops.append((standPoint(seat), .seat(seat.id), 10)) }
        stops.append((home.aisle, .none, 3))
        return stops
    }

    /// Where you are `elapsed` seconds into your break, wandering from stop to stop.
    static func breakTour(_ home: CafeLayout.Seat, elapsed: Double) -> Tour {
        let stops = breakStops(home)
        let speed = 24.0
        var legs: [(path: [CGPoint], walk: Double, dwell: Double, talk: Talk, index: Int)] = []
        var from = home.aisle
        for (i, stop) in stops.enumerated() {
            let path = CafeLayout.route(from: from, to: stop.0)
            let length = zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            legs.append((path, length / speed, stop.2, stop.1, i))
            from = stop.0
        }
        let cycle = legs.reduce(0) { $0 + $1.walk + $1.dwell }
        let lap = Int(elapsed / max(cycle, 1))
        var time = elapsed.truncatingRemainder(dividingBy: max(cycle, 1))
        for leg in legs {
            if time < leg.walk {
                var remaining = time * speed
                for (a, b) in zip(leg.path, leg.path.dropFirst()) {
                    let d = hypot(b.x - a.x, b.y - a.y)
                    if remaining <= d, d > 0 {
                        let k = remaining / d
                        return Tour(point: CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), walking: true, facingLeft: b.x < a.x, talk: .none, talkTime: 0, stop: leg.index, lap: lap)
                    }
                    remaining -= d
                }
            }
            time -= leg.walk
            if time < leg.dwell {
                let end = leg.path.last ?? home.aisle
                var faceLeft = false
                if case .seat(let id) = leg.talk, let s = CafeLayout.seats.first(where: { $0.id == id }) { faceLeft = Double(s.x + 8) < end.x }
                return Tour(point: end, walking: false, facingLeft: faceLeft, talk: leg.talk, talkTime: time, stop: leg.index, lap: lap)
            }
            time -= leg.dwell
        }
        return Tour(point: home.aisle, walking: false, facingLeft: false, talk: .none, talkTime: 0, stop: 0, lap: lap)
    }

    private static let beaChats: [(String, String)] = [
        ("How's your day, Bea?", "Busy, but the good kind!"),
        ("Could I get a refill?", "Coming right up!"),
        ("Something smells amazing.", "Rosie's cinnamon buns!"),
        ("Do you ever take a break?", "Only when the kettle does.")
    ]

    private static let strangerChats: [(String, String)] = [
        ("Hi! How's your day going?", "Pretty good, thanks!"),
        ("What are you working on?", "A big report. Almost there."),
        ("Nice headphones!", "Thanks! Lo-fi all day."),
        ("Long day?", "Long, but this café helps."),
        ("Is that a good book?", "So good I keep re-reading."),
        ("Mind if I say hi?", "Of course! Nice to meet you."),
        ("Any plans for tonight?", "Soup and an early night.")
    ]

    /// What's being said at the current stop.
    static func breakChat(_ tour: Tour) -> (you: String?, them: String?) {
        guard tour.talk != .none else { return (nil, nil) }
        let line: (String, String)
        if tour.talk == .bea {
            line = beaChats[tour.lap % beaChats.count]
        } else {
            line = strangerChats[(tour.lap * 3 + tour.stop) % strangerChats.count]
        }
        let t = tour.talkTime
        return (t < 6 ? line.0 : nil, t > 3.5 ? line.1 : nil)
    }

    static func emptyChair(_ p: Painter, seat: CafeLayout.Seat) {
        chair(p, x: seat.x, top: seat.top)
    }

    static func seated(_ p: Painter, sprite: Sprite, seat: CafeLayout.Seat, t: Double) {
        chair(p, x: seat.x, top: seat.top)
        let bob = Int(t * 1.3 + Double(seat.id) * 0.7) % 4 == 0 ? -1 : 0
        let y = seat.top + 3 + bob
        p.sprite(sprite, x: seat.x, y: y)
        if CafeLayout.headphones.contains(seat.id) {
            let band = [Color(hex: 0x2B2233), Color(hex: 0xC65F4A), Color(hex: 0x4A6FA5), Color(hex: 0xF2C14E)][seat.id % 4]
            p.rect(seat.x + 3, y, 10, 1, ink)
            p.rect(seat.x + 2, y + 1, 1, 2, ink)
            p.rect(seat.x + 13, y + 1, 1, 2, ink)
            VillageRenderer.box(p, seat.x + 1, y + 5, 2, 3, band)
            VillageRenderer.box(p, seat.x + 13, y + 5, 2, 3, band)
        }
    }

    /// A laptop (seen from behind), typing hands and a drink on the table.
    static func laptopAndCup(_ p: Painter, seat: CafeLayout.Seat, t: Double, mug: (Color, Double)?) {
        let x = seat.x, y = seat.top
        p.glow(Double(x + 8), Double(y + 10), radius: 6, Color(hex: 0xBFE6FF), 0.3)
        VillageRenderer.box(p, x + 3, y + 12, 10, 6, Color(hex: 0x9AA0AE))
        p.rect(x + 3, y + 12, 10, 1, Color(hex: 0xC4C9D2))
        p.dot(x + 8, y + 15, Color(hex: 0x78B86A))
        p.rect(x + 2, y + 18, 12, 1, Color(hex: 0x6B6F7A))
        if CafeLayout.bookStacks.contains(seat.id) {
            let colors: [UInt32] = [0xC65F4A, 0x4A6FA5, 0xF2C14E]
            for (i, c) in colors.enumerated() {
                VillageRenderer.box(p, x - 1 + (i % 2), y + 18 - i * 2, 5, 1, Color(hex: c))
            }
        }
        let typing = Int(t * 6 + Double(seat.id)) % 2 == 0
        p.dot(x + 2, y + 17 + (typing ? 0 : -1), Color(hex: 0xF6CFA8))
        p.dot(x + 13, y + 17 + (typing ? -1 : 0), Color(hex: 0xF6CFA8))
        if let mug {
            p.cup(x: x + 9, y: y + 16, w: 4, h: 5, coffee: mug.0, fill: mug.1)
            if mug.1 > 0.02 { steam(p, x: x + 11, y: y + 14, t: t) }
        } else {
            VillageRenderer.box(p, x + 10, y + 19, 4, 2, Color(hex: 0xFFFDF6))
            p.rect(x + 10, y + 19, 4, 1, Color(hex: 0x6B4226))
            if (seat.id + Int(t / 4)) % 3 != 0 { steam(p, x: x + 11, y: y + 17, t: t + Double(seat.id)) }
        }
    }

    static func walker(_ p: Painter, _ sprite: Sprite, at point: CGPoint, walking: Bool, facingLeft: Bool, t: Double, cup: Color?) {
        let x = Int(point.x) - 8, y = Int(point.y) - 16
        p.rect(x + 3, Int(point.y) - 1, 10, 2, Color.black.opacity(0.18))
        let frame = walking ? Int(t * 7) % 2 : 0
        p.walking(sprite, x: x, y: y + (walking && frame == 1 ? -1 : 0), flip: facingLeft, frame: frame)
        if let cup {
            let cx = facingLeft ? x - 2 : x + 13
            VillageRenderer.box(p, cx, y + 10, 4, 4, Color(hex: 0xFFFDF6))
            p.rect(cx, y + 10, 4, 1, cup)
            steam(p, x: cx + 1, y: y + 8, t: t)
        }
    }

    static func steam(_ p: Painter, x: Int, y: Int, t: Double) {
        for i in 0..<2 {
            let k = (t * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let sx = x + Int((sin(k * 7 + Double(i)) * 1.2).rounded())
            p.rect(sx, y - Int(k * 7), 1, 2, Color.white.opacity(0.8 * (1 - k)))
        }
    }

    static func plant(_ p: Painter, x: Int, y: Int) {
        p.sprite(Sprites.pottedPlant, x: x - 2, y: y - 3)
    }
}
