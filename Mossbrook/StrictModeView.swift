import SwiftUI

/// Strict mode: the phone turns sideways and it's just you, your desk and a big pixel clock.
struct StrictModeView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var music = LofiPlayer()
    @State private var leftAt: Date?
    @State private var awayNote: String?
    @State private var steppedAway = 0

    var body: some View {
        GeometryReader { geo in
            // The desk is a wide scene. A phone (or an upright iPad) shows it turned sideways;
            // an iPad already held sideways shows it as it is.
            let upright = geo.size.height > geo.size.width
            let size = upright ? CGSize(width: geo.size.height, height: geo.size.width) : geo.size
            StrictDesk(music: music, awayNote: awayNote, exit: exit)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(upright ? 90 : 0))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .background(Color(hex: 0x2A1A12).ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            QuietNotifications.strictModeOn = true
            music.play()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            QuietNotifications.strictModeOn = false
            music.stop()
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background:
                leftAt = Date()
            case .active:
                if let leftAt {
                    steppedAway += 1
                    let minutes = Int(Date().timeIntervalSince(leftAt) / 60)
                    awayNote = minutes > 0
                        ? "You stepped away for \(minutes)m. Bea kept your seat."
                        : "You stepped away. Bea kept your seat."
                    self.leftAt = nil
                    store.resumeFocusIfNeeded()
                }
            default:
                break
            }
        }
        .onChange(of: store.activeFocus?.id) {
            if store.activeFocus == nil { dismiss() }
        }
        .task(id: awayNote) {
            guard awayNote != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            awayNote = nil
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: true)
    }

    private func exit() {
        music.stop()
        dismiss()
    }
}

/// The sideways scene, laid out on a 160-wide pixel grid.
struct StrictDesk: View {
    @Environment(VillageStore.self) private var store
    @AppStorage("strictTipSeen") private var tipSeen = false
    @AppStorage("strictIntroSeen") private var introSeen = false
    @AppStorage(StrictActivity.storageKey) private var activityRaw = StrictActivity.laptop.rawValue
    private var activity: StrictActivity { StrictActivity(rawValue: activityRaw) ?? .laptop }
    let music: LofiPlayer
    let awayNote: String?
    let exit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, 1) / 160
            let allRows = Int(max(geo.size.height, 1) / s) + 2
            // A phone shows about 75 rows. Squarer screens (iPad) get the scene centred, with more wall
            // above and desk below, instead of one huge empty desk.
            // Taller screens (iPad) keep the phone's layout at the bottom and get more wall above it.
            let lift = max(0, allRows - 76)
            let rows = allRows - lift
            let oy = CGFloat(lift) * s
            TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let session = store.activeFocus
                let remaining = session.map { $0.end.timeIntervalSince(now) } ?? 0
                let fill = session.map { max(0, min(1, remaining / $0.duration)) } ?? 0
                let drink = session.flatMap { Drink(rawValue: $0.drink) } ?? .espresso

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        if lift > 0 {
                            StrictRenderer.upperWall(Painter(ctx: ctx, s: s), t: t, height: lift + 1, phase: store.phase)
                        }
                        StrictRenderer.draw(
                            Painter(ctx: ctx, s: s).shifted(dy: lift), t: t, rows: rows, phase: store.phase,
                            remaining: remaining, fill: fill, drink: drink, headphones: music.isPlaying,
                            activity: activity
                        )
                    }
                    .accessibilityLabel("You, \(activity.doing) at your desk. \(count(Int(max(0, remaining) / 60), "minute")) left.")

                    if introSeen {
                        // Pinned by its bottom-left corner, so the list can open upwards over the desk.
                        ActivityPicker(selection: $activityRaw, compact: true)
                            .fixedSize()
                            .frame(width: 60 * s, height: 60 * s, alignment: .bottomLeading)
                            .position(x: 37 * s, y: 38.5 * s + oy)
                            .transition(.opacity)
                    }

                    controls(session: session, s: s)
                        .frame(width: 56 * s, alignment: .leading)
                        .position(x: 128 * s, y: 58 * s + oy)

                    Text("STRICT MODE")
                        .font(.pixel(10, .heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .pixelBox(Theme.gold, shadow: 2)
                        .position(x: 128 * s, y: 4.5 * s + oy)

                    if let awayNote {
                        Text(awayNote)
                            .font(.pixel(12, .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(10)
                            .pixelBox(Theme.card)
                            .position(x: 52 * s, y: 8 * s + oy)
                            .transition(.opacity)
                    }

                    if !introSeen {
                        StrictIntro(selection: $activityRaw) {
                            withAnimation(.snappy) {
                                introSeen = true
                                tipSeen = true
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func controls(session: FocusSession?, s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session?.title ?? "Quiet work")
                .font(.pixel(14, .heavy))
                .foregroundStyle(Color(hex: 0xFFF6DD))
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    music.toggle()
                } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 0))
                .accessibilityLabel(music.isPlaying ? "Pause music" : "Play music")
                Button {
                    music.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 0))
                .accessibilityLabel("Next music")
                VStack(alignment: .leading, spacing: 0) {
                    Text("NOW PLAYING")
                        .font(.pixel(8, .heavy))
                        .foregroundStyle(Color(hex: 0xF4E3B5).opacity(0.7))
                    Text(music.trackName)
                        .font(.pixel(11, .heavy))
                        .foregroundStyle(Color(hex: 0xF4E3B5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HoldButton(title: "Hold to exit", action: exit)
        }
    }
}

/// A button you have to hold down, so leaving is a choice and not an accident.
struct HoldButton: View {
    let title: String
    var duration: Double = 1.5
    let action: () -> Void
    @State private var hold: Double = 0

    var body: some View {
        Text(title)
            .font(.pixel(12, .heavy))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.red)
                        Rectangle().fill(Color(hex: 0x8E2E2B)).frame(width: geo.size.width * hold)
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(x: 3, y: 3))
            .onLongPressGesture(minimumDuration: duration) {
                hold = 0
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: duration) : .easeOut(duration: 0.2)) {
                    hold = pressing ? 1 : 0
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityAction { action() }
    }
}

enum StrictRenderer {
    static let ink = VillageRenderer.ink

    /// You, facing out, at your desk.
    static let frontYou = Sprite([
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
        "k": VillageRenderer.ink, "r": Color(hex: 0xE07A5F), "R": Color(hex: 0xC4614A), "w": Color(hex: 0xFFF6E5),
        "h": Color(hex: 0x6B4A2E), "s": Color(hex: 0xF6CFA8), "b": Color(hex: 0xF0A090), "m": Color(hex: 0xC0605A),
        "e": VillageRenderer.ink, "g": Color(hex: 0x81B29A)
    ])

    static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "1", "0", "0", "0", "1", "0"]
    ]

    static func draw(
        _ p: Painter, t: Double, rows: Int, phase: DayPhase,
        remaining: TimeInterval, fill: Double, drink: Drink, headphones: Bool,
        activity: StrictActivity = .laptop
    ) {
        func box(_ p: Painter, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ fill: Color, _ outline: Color = ink) {
            VillageRenderer.box(p, x, y, w, h, fill, outline: outline)
        }
        let wall = Color(hex: 0x4A2C1D), wallLight = Color(hex: 0x5C3A26)
        let wood = Color(hex: 0xC07A40), woodLight = Color(hex: 0xD99456), woodDark = Color(hex: 0x8A5230)

        // Wall and string lights.
        p.rect(0, 0, 160, rows, wall)
        for x in stride(from: 0, to: 160, by: 10) { p.rect(x, 0, 1, 56, wallLight) }
        let colors: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A]
        for (i, x) in stride(from: 3, to: 158, by: 7).enumerated() {
            let y = 2 + (i % 2)
            p.dot(x, y - 1, ink)
            p.glow(Double(x) + 0.5, Double(y) + 1, radius: 3, Color(hex: colors[i % 4]), 0.55)
            p.rect(x, y, 1, 2, Color(hex: colors[i % 4]))
        }

        // Rainy window behind you.
        let night = phase == .night
        let sky = night ? Color(hex: 0x1E2347) : (phase == .dusk ? Color(hex: 0x6E5A8A) : Color(hex: 0x7F95B0))
        p.rect(6, 7, 44, 38, ink)
        p.rect(7, 8, 42, 36, sky)
        p.rect(7, 34, 42, 10, night ? Color(hex: 0x2A2440) : Color(hex: 0x4E5A6E))
        for i in 0..<9 {
            let wx = 8 + noise(i, 9) % 38
            let wy = 35 + noise(i, 11) % 7
            p.rect(wx, wy, 2, 1, Color(hex: 0xFFD27A).opacity((Int(t) + i) % 6 == 0 ? 0.4 : 0.9))
        }
        for i in 0..<16 {
            let speed = 22 + Double(noise(i, 3) % 12)
            let x = 7 + noise(i, 5) % 42
            let y = 8 + Int((t * speed + Double(noise(i, 7) % 36))).quotientAndRemainder(dividingBy: 36).remainder
            p.rect(x, y, 1, 3, Color(hex: 0xBFD8F0).opacity(0.55))
        }
        p.rect(27, 8, 2, 36, woodDark)
        p.rect(7, 25, 42, 1, woodDark)
        box(p, 5, 45, 46, 2, wood, ink)

        // Bookshelf.
        p.rect(70, 6, 26, 48, ink)
        p.rect(71, 7, 24, 46, woodDark)
        let books: [UInt32] = [0xC65F4A, 0x4A6FA5, 0xF2C14E, 0x6E8B5E, 0x8E5A8A, 0xE8A0B0, 0xD9824A]
        for shelf in stride(from: 8, to: 50, by: 11) {
            var x = 72
            var i = shelf
            while x < 92 {
                let w = 2 + noise(i, 1) % 2
                let h = 6 + noise(i, 2) % 3
                p.rect(x, shelf + 9 - h, w, h, Color(hex: books[i % books.count]))
                x += w + 1
                i += 1
            }
            p.rect(71, shelf + 9, 24, 2, wood)
        }

        // The big clock on the right.
        box(p, 100, 10, 56, 28, Color(hex: 0x1C2420), woodDark)
        p.rect(99, 9, 58, 1, woodLight)
        let clockText = FocusFormat.clock(remaining)
        let on = Color(hex: 0xFFB347)
        let ghost = Color(hex: 0x2E3A30)
        let blinkOff = Int(t * 2) % 2 == 1
        var cx = 102
        for ch in clockText {
            guard let glyph = glyphs[ch] else { continue }
            for (r, row) in glyph.enumerated() {
                for (c, bit) in row.enumerated() {
                    let lit = bit == "1" && !(ch == ":" && blinkOff)
                    p.rect(cx + c * 2, 14 + r * 2, 2, 2, lit ? on : ghost)
                }
            }
            cx += (glyph[0].count + 1) * 2
        }
        p.glow(128, 21, radius: 26, on, 0.18)
        p.rect(103, 31, 50, 3, ghost)
        p.rect(103, 31, Int(50 * (1 - fill)), 3, Color(hex: 0x9CD3A0))
        p.rect(104, 38, 4, 3, ink)
        p.rect(148, 38, 4, 3, ink)

        // You, facing out.
        let breathe = Int(t * 0.9) % 3 == 0 ? -1 : 0
        let x0 = 30, y0 = 12 + breathe
        drawBig(p, frontYou, x: x0, y: y0, scale: 2)
        if Int(t * 10) % 41 == 0 {
            for ex in [14, 30] {
                p.rect(x0 + ex, y0 + 16, 4, 4, Color(hex: 0xF6CFA8))
                p.rect(x0 + ex, y0 + 18, 4, 1, ink)
            }
        }
        if headphones {
            p.rect(x0 + 6, y0 - 2, 36, 2, ink)
            p.rect(x0 + 4, y0, 2, 12, ink)
            p.rect(x0 + 42, y0, 2, 12, ink)
            box(p, x0 + 3, y0 + 12, 5, 9, Color(hex: 0xF2C14E))
            box(p, x0 + 40, y0 + 12, 5, 9, Color(hex: 0xF2C14E))
            p.rect(x0 + 4, y0 + 13, 2, 3, Color.white.opacity(0.4))
            p.rect(x0 + 41, y0 + 13, 2, 3, Color.white.opacity(0.4))
        }

        // A plant keeping you company.
        p.sprite(Sprites.pottedPlant, x: 8, y: 39)

        // Desk.
        p.rect(0, 54, 160, 1, ink)
        p.rect(0, 55, 160, 3, wood)
        p.rect(0, 55, 160, 1, woodLight)
        p.rect(0, 58, 160, rows - 58, woodDark)
        p.rect(0, 58, 160, 1, ink)
        for x in stride(from: 10, to: 160, by: 26) { p.rect(x, 60, 1, rows - 60, Color(hex: 0x7A4A2A)) }

        // Whatever you're working on: laptop, book, journal, sketchbook or knitting.
        StrictRenderer.activity(p, activity, x0: x0, y0: y0, t: t, progress: 1 - fill)

        // Your mug, draining.
        p.cup(x: 80, y: 44, w: 7, h: 9, coffee: drink.color, fill: fill)
        if fill > 0.02 {
            for i in 0..<3 {
                let k = (t * 0.6 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let sx = 82 + i * 2 + Int((sin(k * 7 + Double(i)) * 1.5).rounded())
                p.rect(sx, 42 - Int(k * 10), 1, 2, Color.white.opacity(0.8 * (1 - k)))
            }
        }

        // Books under the clock, with a sleeping cat on top.
        let stack: [UInt32] = [0xC65F4A, 0x4A6FA5, 0xF2C14E]
        for (i, c) in stack.enumerated() { box(p, 143 + (i % 2), 52 - i * 2, 13, 1, Color(hex: c)) }
        let catBreath = Int(t * 0.8) % 2 == 0 ? 0 : -1
        p.sprite(Sprites.sleepyCat, x: 142, y: 38 + catBreath)
        let z = Int(t * 1.5) % 4
        if z < 3 {
            p.rect(152 + z, 35 - z * 2, 2, 1, Color.white.opacity(0.8 - Double(z) * 0.2))
            p.rect(152 + z, 37 - z * 2, 2, 1, Color.white.opacity(0.8 - Double(z) * 0.2))
            p.dot(153 + z, 36 - z * 2, Color.white.opacity(0.8 - Double(z) * 0.2))
        }

        if night { p.rect(0, 0, 160, rows, Color(hex: 0x1A1033).opacity(0.15)) }
    }

    static func drawBig(_ p: Painter, _ sprite: Sprite, x: Int, y: Int, scale: Int) {
        for (r, row) in sprite.rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard ch != ".", let color = sprite.palette[ch] else { continue }
                p.rect(x + c * scale, y + r * scale, scale, scale, color)
            }
        }
    }
}


extension StrictRenderer {
    /// Extra wall above the desk on taller screens: a beam with lights, a shelf of plants and
    /// books, and two little framed pictures, so the room fills the screen.
    static func upperWall(_ p: Painter, t: Double, height: Int, phase: DayPhase) {
        let wall = Color(hex: 0x4A2C1D), wallLight = Color(hex: 0x5C3A26)
        let wood = Color(hex: 0xC07A40), woodDark = Color(hex: 0x8A5230)
        p.rect(0, 0, 160, height, wall)
        for x in stride(from: 0, to: 160, by: 10) { p.rect(x, 0, 1, height, wallLight) }
        // Beam with fairy lights.
        p.rect(0, 0, 160, 4, Color(hex: 0x3A2218))
        p.rect(0, 4, 160, 1, ink)
        let colors: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A]
        for (i, x) in stride(from: 4, to: 158, by: 8).enumerated() {
            let y = 6 + (i % 2)
            p.dot(x, y - 1, ink)
            p.glow(Double(x) + 0.5, Double(y) + 1, radius: 3, Color(hex: colors[i % 4]), 0.5)
            p.rect(x, y, 1, 2, Color(hex: colors[i % 4]))
        }
        guard height > 26 else { return }
        let mid = min(height - 10, max(16, height / 2 + 2))
        // Framed pictures: a little sunset and a little mountain.
        let frames: [(Int, UInt32, UInt32)] = [(16, 0xF2A65A, 0x6E8B5E), (132, 0x8FB4E8, 0xE8E3D4)]
        for (fx, sky, land) in frames {
            VillageRenderer.box(p, fx, mid - 13, 14, 10, Color(hex: sky), outline: woodDark)
            p.rect(fx, mid - 7, 14, 4, Color(hex: land))
            p.rect(fx + 4, mid - 10, 3, 3, Color(hex: 0xFFF3C0))
        }
        // A long shelf with plants, books and a mug.
        let sy = mid
        p.rect(40, sy, 80, 2, wood)
        p.rect(40, sy + 2, 80, 1, ink)
        for x in [46, 112] { p.rect(x, sy + 3, 2, 3, woodDark) }
        p.sprite(Sprites.pottedPlant, x: 44, y: sy - 11)
        p.sprite(Sprites.pottedPlant, x: 104, y: sy - 11)
        let books: [UInt32] = [0xC65F4A, 0x4A6FA5, 0xF2C14E, 0x6E8B5E, 0x8E5A8A]
        for (i, c) in books.enumerated() {
            let h = 7 + noise(i, 3) % 3
            p.rect(62 + i * 3, sy - h, 2, h, Color(hex: c))
        }
        VillageRenderer.box(p, 84, sy - 6, 5, 6, Color(hex: 0xFFFDF6))
        p.rect(85, sy - 5, 3, 2, Color(hex: 0x9CB86A))
        VillageRenderer.box(p, 93, sy - 9, 6, 9, Color(hex: 0xE8A0B0))
        if phase == .night { p.rect(0, 0, 160, height, Color(hex: 0x1A1033).opacity(0.15)) }
    }
}
