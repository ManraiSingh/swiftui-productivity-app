import SwiftUI

// MARK: - Who's talking

enum MeetingSpeaker: Equatable {
    case mayor, cat, everyone
    case villager(VillagerID)

    var name: String {
        switch self {
        case .mayor: "Mayor Barnaby"
        case .cat: "Biscuit the cat"
        case .everyone: "Everyone"
        case .villager(let v): v.name
        }
    }

    var color: Color {
        switch self {
        case .mayor: Color(hex: 0x3E6B48)
        case .cat: Color(hex: 0xC47A35)
        case .everyone: Theme.red
        case .villager(let v): v.color
        }
    }

    var sprite: Sprite {
        switch self {
        case .mayor: Sprites.mayor
        case .cat: Sprites.cat
        case .everyone: Sprites.mayor
        case .villager(let v): v.sprite
        }
    }
}

struct MeetingLine: Equatable {
    let speaker: MeetingSpeaker
    let text: String
}

/// The meeting's agenda, written from what you've actually done.
enum TownMeeting {
    static func script(_ store: VillageStore) -> [MeetingLine] {
        let week = store.week
        let letters = week.map(\.letters).reduce(0, +)
        let pages = week.map(\.pages).reduce(0, +)
        let total = week.map(\.total).reduce(0, +)
        let best = week.max { $0.total < $1.total }
        var lines: [MeetingLine] = []
        let hello: String = switch store.phase {
        case .day: "Order, order! Welcome to the town meeting under the Old Oak."
        case .dusk: "Good evening, everyone! Gather round the Old Oak."
        case .night: "Lanterns are lit. Let's begin tonight's town meeting!"
        }
        lines.append(.init(speaker: .mayor, text: hello))
        lines.append(.init(speaker: .mayor, text: "First on the agenda: the post. Pip?"))

        if store.bikeFixed {
            lines.append(.init(speaker: .villager(.pip), text: letters > 0 ? "\(count(letters, "letter")) delivered this week, and my bike's all fixed. I'm zooming!" : "My bike's all fixed! Now I just need letters to deliver."))
        } else if letters > 0 {
            lines.append(.init(speaker: .villager(.pip), text: "\(count(letters, "letter")) delivered this week! My bike has \(store.bikeParts) of \(VillageStore.bikeGoal) parts now."))
        } else {
            lines.append(.init(speaker: .villager(.pip), text: store.openLetters.isEmpty ? "No letters yet this week. My bag feels so light!" : "\(count(store.openLetters.count, "letter")) still waiting... my bag is getting heavy!"))
        }

        lines.append(.init(speaker: .villager(.mo), text: pages > 0 ? "The library got \(count(pages, "new page")) this week. What a read!" : "The library's been very quiet. Even one page would cheer me up."))

        lines.append(.init(speaker: .villager(.bea), text: store.focusMinutes > 0 ? "We've brewed \(count(store.focusMinutes, "minute")) of focus at the café so far. Kettle's always on!" : "The kettle's warm, but nobody's sat down for a cup yet."))

        if store.habits.isEmpty {
            lines.append(.init(speaker: .villager(.juniper), text: "The greenhouse is empty! Shall we plant a habit together?"))
        } else {
            let done = store.habitsDoneToday, all = store.habits.count
            lines.append(.init(speaker: .villager(.juniper), text: done == all ? "Every plant is watered today. They're glowing!" : (done == 0 ? "None of the \(count(all, "plant")) are watered yet today. They look so thirsty!" : "\(done) of \(all) plants watered today. The rest look a little thirsty.")))
        }

        lines.append(.init(speaker: .villager(.rosie), text: store.treatsInJar > 0 ? "There \(store.treatsInJar == 1 ? "is" : "are") \(count(store.treatsInJar, "treat")) in your jar. Don't eat them all at once!" : "The ovens are warm. Finish a cup and I'll bake you something."))

        lines.append(.init(speaker: .cat, text: "Mrrp."))
        lines.append(.init(speaker: .mayor, text: "Thank you, Biscuit. Very insightful."))

        if store.streak >= 3 {
            lines.append(.init(speaker: .mayor, text: "A \(store.streak)-day streak! I hereby name you Citizen of the Week!"))
        } else if let best, best.total > 0 {
            lines.append(.init(speaker: .mayor, text: "Your best day was \(best.fullName), with \(count(best.total, "thing")) done. The town is proud of you!"))
        } else if total == 0 {
            lines.append(.init(speaker: .mayor, text: "A quiet week. I propose we believe in you anyway. All in favour?"))
        }
        if total > 0 || store.streak >= 3 {
            lines.append(.init(speaker: .mayor, text: "All in favour of keeping it up?"))
        }
        lines.append(.init(speaker: .everyone, text: "Aye!"))
        lines.append(.init(speaker: .mayor, text: "Meeting adjourned! Same time next week."))
        return lines
    }
}

// MARK: - Drawing the meeting

enum MeetingRenderer {
    static let ink = VillageRenderer.ink

    /// Where everyone stands, in scene pixels (x, feet).
    static let seats: [(VillagerID, Int, Int)] = [(.pip, 20, 140), (.mo, 40, 154), (.bea, 64, 162), (.juniper, 88, 154), (.rosie, 108, 140)]
    static let canopy: [(Int, Int, Int)] = [
        (64, 26, 30), (30, 38, 24), (98, 38, 24), (6, 50, 18), (122, 50, 18), (44, 10, 22), (84, 8, 22),
        (64, -6, 24), (14, 16, 18), (114, 16, 18), (-16, 34, 18), (144, 34, 18), (-10, 6, 20), (138, 4, 20)
    ]

    static func draw(_ p0: Painter, t: Double, cols: Int, rows: Int, ox: Int, oy: Int,
                     phase: DayPhase, weather: Weather, season: Season, speaker: MeetingSpeaker?, typing: Bool, chorus: Bool) {
        VillageRenderer.season = season
        VillageRenderer.weather = weather
        let light = VillageRenderer.oakGreens.3
        // Sky across the whole screen.
        let sky: (UInt32, UInt32) = switch phase {
        case .day: (0x9ED6EC, 0xD4EEF2)
        case .dusk: (0x8E6FA6, 0xF6C79A)
        case .night: (0x161B3A, 0x3A3670)
        }
        let horizon = oy + 108
        for y in stride(from: 0, to: max(horizon, 6), by: 6) {
            let k = Double(y) / Double(max(horizon, 1))
            p0.rect(0, y, cols, 6, blend(sky.0, sky.1, k))
        }
        if phase == .night {
            for i in 0..<50 { p0.dot(noise(i, 1) % max(cols, 1), noise(i, 2) % max(horizon, 1), Color(hex: 0xFFF3B0).opacity(Double(noise(i, 3) % 3 + 1) / 3)) }
        }
        // Grass.
        let grass = phase == .night ? Color(hex: 0x3E5A48) : Color(hex: 0x8CC56C)
        let grassDark = phase == .night ? Color(hex: 0x34503E) : Color(hex: 0x73AD5B)
        p0.rect(0, horizon, cols, rows - horizon, grass)
        for i in 0..<220 { p0.dot(noise(i, 5) % max(cols, 1), horizon + noise(i, 6) % max(rows - horizon, 1), grassDark) }
        for i in 0..<40 {
            let c = [0xF49AC1, 0xFFFFFF, 0xFFE38A, 0xC9A0F0][i % 4]
            p0.dot(noise(i, 8) % max(cols, 1), horizon + 4 + noise(i, 9) % max(rows - horizon - 4, 1), Color(hex: UInt32(c)))
        }
        let p = p0.shifted(dx: ox, dy: oy)

        // A chubby trunk; its arms are hidden up inside the canopy.
        VillageRenderer.cuteTrunk(p, cx: 64, top: 56, base: 123, topW: 18, baseW: 34)
        let barkDark = Color(hex: 0x765238)
        // A carved heart, and an owl peeking from the knot hole at night.
        p.rects([(62, 96, 1, 1), (64, 96, 1, 1), (61, 97, 5, 1), (62, 98, 3, 1), (63, 99, 1, 1)], Color(hex: 0xE58A9A))
        VillageRenderer.box(p, 61, 74, 7, 7, barkDark)
        p.rect(62, 75, 5, 5, Color(hex: 0x2E1F24))
        if phase == .night {
            let blink = Int(t * 0.7) % 6 == 0
            p.rect(63, 77, 1, blink ? 1 : 2, Color(hex: 0xFFD54A)); p.rect(65, 77, 1, blink ? 1 : 2, Color(hex: 0xFFD54A))
        }
        // A wide, lumpy canopy like a cartoon oak, extended to fill tall and wide screens.
        var lobes: [(Int, Int, Int)] = [
            (8, 50, 16), (34, 54, 18), (64, 54, 20), (94, 54, 18), (120, 50, 16),
            (-6, 28, 18), (22, 26, 20), (50, 22, 22), (78, 22, 22), (106, 26, 20), (134, 28, 18),
            (10, 2, 22), (40, -2, 24), (72, -4, 24), (102, 0, 22), (132, 4, 20)
        ]
        var extraY = -26
        while extraY > -oy - 26 {
            for x in stride(from: -14, through: 148, by: 30) { lobes.append((x + (extraY / 3) % 13, extraY, 22)) }
            extraY -= 26
        }
        for x in stride(from: -34, to: -ox - 10, by: -30) { lobes.append((x, 40, 18)); lobes.append((x, 14, 22)) }
        for x in stride(from: 162, to: cols - ox + 30, by: 30) { lobes.append((x, 40, 18)); lobes.append((x, 14, 22)) }
        VillageRenderer.oakCanopy(p, lobes: lobes, bottom: 72, seed: 5)

        // Hanging lanterns.
        for (i, (lx, ly)) in [(30, 72), (48, 80), (84, 80)].enumerated() {
            p.rect(lx, 62, 1, ly - 62, ink)
            VillageRenderer.box(p, lx - 2, ly, 5, 6, Color(hex: [0xFFE38A, 0xF7B7CF, 0xFFE38A][i]))
            p.rect(lx - 1, ly + 1, 3, 1, Color.white.opacity(0.6))
            p.glow(Double(lx) + 0.5, Double(ly) + 3, radius: phase == .night ? 16 : 9, Color(hex: 0xFFD27A), phase == .day ? 0.25 : 0.6)
        }
        // The swing, with Biscuit asleep on it.
        let sway = sin(t * 1.4) * 2.5
        let sx = 104 + Int(sway)
        p.rect(100, 62, 1, 42, Color(hex: 0xC9A27A)); p.rect(112, 62, 1, 42, Color(hex: 0xC9A27A))
        VillageRenderer.box(p, sx - 7, 104, 16, 2, Color(hex: 0x9A6340))
        let catTalking = speaker == .cat
        if catTalking {
            p.sprite(Sprites.cat, x: sx - 3, y: 96 - (typing ? Int(abs(sin(t * 9)) * 2) : 0))
        } else {
            p.sprite(Sprites.sleepyCat, x: sx - 6, y: 95 + (Int(t) % 2))
        }

        // Picnic blanket.
        for dy in -14...14 {
            let half = Int((1 - Double(dy * dy) / 196).squareRoot() * 58)
            p.rect(64 - half - 1, 148 + dy, half * 2 + 2, 1, ink)
        }
        for dy in -13...13 {
            let half = Int((1 - Double(dy * dy) / 169).squareRoot() * 56)
            p.rect(64 - half, 148 + dy, half * 2, 1, Color(hex: 0xF7B7CF))
            if (dy + 13) / 4 % 2 == 0 {
                for x in stride(from: 64 - half + ((dy + 13) / 4 % 2) * 4, to: 64 + half, by: 8) { p.rect(x, 148 + dy, 4, 1, Color(hex: 0xFFF6E5)) }
            }
        }
        // Teapot and cupcakes on the blanket.
        VillageRenderer.box(p, 30, 158, 6, 5, Color(hex: 0xFFF6E5)); p.rect(36, 159, 2, 1, ink)
        VillageRenderer.box(p, 96, 160, 4, 3, Color(hex: 0xC69C6D)); p.rect(96, 159, 4, 1, Color(hex: 0xF49AC1))

        // Stump and the mayor.
        VillageRenderer.box(p, 55, 128, 18, 8, Color(hex: 0x8E5A3B))
        VillageRenderer.box(p, 55, 126, 18, 3, Color(hex: 0xD9A877))
        p.rect(59, 127, 10, 1, Color(hex: 0xB8865A))
        let mayorTalk = speaker == .mayor || chorus
        let mhop = mayorTalk && typing ? Int(abs(sin(t * 8)) * 2) : (Int(t * 1.1) % 6 == 0 ? 1 : 0)
        shadow(p, 64, 127)
        p.sprite(Sprites.mayor, x: 56, y: 110 - mhop)
        if mayorTalk && !chorus {
            // A tiny gavel tap.
            let tap = Int(t * 4) % 2 == 0
            VillageRenderer.box(p, 72, tap ? 116 : 118, 4, 2, Color(hex: 0x6B4226))
        }

        // The villagers.
        for (v, x, feet) in seats {
            let talking = speaker == .villager(v) || chorus
            var hop = 0
            if chorus { hop = Int(abs(sin(t * 9 + Double(x))) * 5) }
            else if talking && typing { hop = Int(abs(sin(t * 8)) * 2) }
            else if Int(t * 1.2 + Double(x) / 10) % 5 == 0 { hop = 1 }
            shadow(p, x, feet)
            p.sprite(v.sprite, x: x - 8, y: feet - 16 - hop, flip: x > 64)
            if talking && !chorus { p.rects([(x - 1, feet - 22, 2, 2)], Color.white) }
        }
        if typing, let speaker, speaker != .everyone {
            let head: (Int, Int)
            switch speaker {
            case .mayor: head = (64, 108)
            case .cat: head = (sx + 1, 92)
            case .villager(let v): head = seats.first { $0.0 == v }.map { ($0.1, $0.2 - 18) } ?? (64, 120)
            default: head = (64, 120)
            }
            typingBubble(p, head.0, head.1, t)
        }
        if chorus {
            for i in 0..<10 {
                let k = (t * 0.6 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
                let hx = 10 + (i * 37) % 108
                heart(p, hx + Int(sin(k * 8) * 3), 150 - Int(k * 70), Color(hex: [0xF06A86, 0xF49AC1, 0xFFE38A][i % 3]).opacity(1 - k))
            }
        }

        // Falling leaves or snow.
        for i in 0..<14 {
            let k = (t * 0.12 + Double(i) / 14).truncatingRemainder(dividingBy: 1)
            let x = (noise(i, 41) % 160) - 16 + Int(sin(k * 12 + Double(i)) * 5)
            let y = 40 + Int(k * 140)
            let c: Color = weather == .snow ? Color(hex: 0xF4F7FB) : (season == .spring || weather == .petals ? Color(hex: 0xF7B7CF) : light)
            p.rect(x, y, 2, 1, c)
        }
        if phase == .night {
            for i in 0..<10 {
                let x = 10 + (noise(i, 51) % 110) + Int(sin(t * 0.8 + Double(i)) * 6)
                let y = 90 + (noise(i, 52) % 60) + Int(cos(t * 0.6 + Double(i)) * 4)
                if (Int(t * 2) + i) % 3 != 0 { p.glow(Double(x), Double(y), radius: 3, Color(hex: 0xEFFF9A), 0.8); p.dot(x, y, Color(hex: 0xEFFF9A)) }
            }
            p0.rect(0, 0, cols, rows, Color(hex: 0x0E1238).opacity(0.18))
        }
    }

    /// A little white speech bubble with three bouncing dots, over whoever is typing.
    static func typingBubble(_ p: Painter, _ x: Int, _ y: Int, _ t: Double) {
        let bx = x - 7, by = y - 8
        p.rects([(bx + 1, by - 1, 13, 1), (bx, by, 15, 7), (bx + 1, by + 7, 13, 1)], ink)
        p.rect(bx + 1, by, 13, 7, Color.white)
        p.rects([(x - 1, by + 8, 3, 1), (x, by + 9, 1, 1)], ink)
        for k in 0..<3 {
            let up = Int(t * 6 - Double(k)) % 3 == 0 ? 1 : 0
            p.rect(bx + 3 + k * 4, by + 3 - up, 2, 2, Color(hex: 0x8A8290))
        }
    }

    static func shadow(_ p: Painter, _ x: Int, _ feet: Int) {
        p.rect(x - 5, feet - 1, 10, 2, Color.black.opacity(0.15))
    }

    static func heart(_ p: Painter, _ x: Int, _ y: Int, _ c: Color) {
        p.rects([(x, y, 1, 1), (x + 2, y, 1, 1), (x - 1, y + 1, 5, 1), (x, y + 2, 3, 1), (x + 1, y + 3, 1, 1)], c)
    }

    static func blend(_ a: UInt32, _ b: UInt32, _ k: Double) -> Color {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        let r = ch(a, 16) + (ch(b, 16) - ch(a, 16)) * k
        let g = ch(a, 8) + (ch(b, 8) - ch(a, 8)) * k
        let bl = ch(a, 0) + (ch(b, 0) - ch(a, 0)) * k
        return Color(.sRGB, red: r / 255, green: g / 255, blue: bl / 255)
    }
}

// MARK: - The screen

struct TownMeetingView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var script: [MeetingLine] = []
    /// How many messages have arrived, and whose "typing..." is showing.
    @State private var shown = 0
    @State private var typingIndex: Int?
    @State private var skip = false
    @State private var runID = UUID()
    @State private var showReport = false

    private var finished: Bool { !script.isEmpty && shown >= script.count && typingIndex == nil }
    private var current: MeetingLine? {
        if let i = typingIndex { return script[i] }
        return shown > 0 ? script[shown - 1] : nil
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 600
            let s = max(0.5, wide ? min(geo.size.width / 150, geo.size.height / 300) : geo.size.width / 128)
            let cols = Int(max(geo.size.width, 1) / s) + 1
            let rows = Int(max(geo.size.height, 1) / s) + 1
            let cardRows = Int((wide ? 330 : 300) / s)
            let oy = rows - cardRows - 168
            let ox = (cols - 128) / 2

            TimelineView(.animation(minimumInterval: 1.0 / 15)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let phase = store.phase, weather = store.weather, season = Season.now()
                let speaker = current?.speaker, typing = typingIndex != nil
                let chorus = typingIndex == nil && current?.speaker == .everyone
                PixelCanvas(cols: cols, rows: rows, s: s, frame: t) { p in
                    MeetingRenderer.draw(
                        p, t: t, cols: cols, rows: rows, ox: ox, oy: oy,
                        phase: phase, weather: weather, season: season,
                        speaker: speaker, typing: typing, chorus: chorus
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { skip = true }
            .overlay(alignment: .bottom) {
                chat
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 12)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 12))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color(hex: 0x3E5A48).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Text("TOWN MEETING")
                .font(.pixel(14, .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .pixelBox(Theme.gold, shadow: 2)
                .padding(.leading, 16).padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .pixelBox(Theme.card, shadow: 2)
            }
            .accessibilityLabel("Back to the village")
            .padding(.trailing, 16).padding(.top, 6)
        }
        .environment(\.colorScheme, .light)
        .sensoryFeedback(.selection, trigger: shown)
        .sheet(isPresented: $showReport) { TownReportView() }
        .task(id: runID) { await play() }
    }

    // MARK: Playing the chat

    private func play() async {
        script = TownMeeting.script(store)
        shown = 0; typingIndex = nil
        for i in script.indices {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.2)) { typingIndex = i }
            await wait(min(1.5, 0.55 + Double(script[i].text.count) * 0.016))
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { typingIndex = nil; shown = i + 1 }
            // A soft chime as each message lands; the town's "Aye!" gets a little sparkle instead.
            SoundFX.shared.play(script[i].speaker == .everyone ? .sparkle : .message, volume: 0.55)
            await wait(min(2.8, 1.1 + Double(script[i].text.count) * 0.028))
        }
    }

    /// Waits, unless the player taps to hurry things along.
    private func wait(_ seconds: Double) async {
        skip = false
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !skip && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    // MARK: The chat panel

    private var chat: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0x5FBF6A)).frame(width: 8, height: 8)
                Text("TOWN CHAT").font(.pixel(11, .heavy)).foregroundStyle(Theme.ink)
                Text("· 7 here").font(.pixel(10, .bold)).foregroundStyle(Theme.muted)
                Spacer()
                Button { showReport = true } label: {
                    Label("Full report", systemImage: "doc.text.fill")
                        .font(.pixel(11, .heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.gold)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(max(0, shown - 3)..<shown, id: \.self) { i in
                    MessageRow(line: script[i], latest: i == shown - 1 && typingIndex == nil)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.85, anchor: .bottomLeading)),
                            removal: .opacity))
                }
                if let i = typingIndex {
                    TypingRow(speaker: script[i].speaker).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200, alignment: .bottomLeading)
            .clipped()
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25)))
            if finished {
                HStack(spacing: 8) {
                    Button("Full report") { showReport = true }.buttonStyle(PixelButtonStyle(hPad: 12))
                    Button("Again") { runID = UUID() }.buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 12))
                    Button("Back to town") { dismiss() }.buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 12))
                }
                .font(.pixel(13, .heavy))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap anywhere to skip ahead")
                    .font(.pixel(9, .bold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(12)
        .pixelBox(Theme.cream)
        // Tapping the chat itself hurries things along too (its buttons still work as buttons).
        .contentShape(Rectangle())
        .onTapGesture { skip = true }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: finished)
    }
}

/// One message in the town chat, iMessage style: a face, a name and a rounded bubble.
private struct MessageRow: View {
    let line: MeetingLine
    let latest: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Avatar(speaker: line.speaker)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.speaker.name)
                    .font(.pixel(10, .heavy))
                    .foregroundStyle(line.speaker.color)
                Text(line.text)
                    .font(.pixel(14, .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(bubbleColor, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16).strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1.5))
            }
            Spacer(minLength: 24)
        }
        .opacity(latest ? 1 : 0.8)
        .accessibilityElement(children: .combine)
    }

    private var bubbleColor: Color {
        switch line.speaker {
        case .mayor: Color(hex: 0xE4F2DA)
        case .everyone: Color(hex: 0xFFE1EA)
        case .cat: Color(hex: 0xFFEBD6)
        case .villager: .white
        }
    }
}

private struct TypingRow: View {
    let speaker: MeetingSpeaker

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Avatar(speaker: speaker)
            VStack(alignment: .leading, spacing: 3) {
                Text(speaker == .everyone ? "Everyone is typing…" : "\(speaker.name) is typing…")
                    .font(.pixel(10, .heavy))
                    .foregroundStyle(Theme.muted)
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { k in
                            Circle().fill(Theme.muted)
                                .frame(width: 7, height: 7)
                                .offset(y: -3 * max(0, sin(t * 7 - Double(k) * 0.8)))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16).strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1.5))
                }
            }
            Spacer()
        }
        .accessibilityLabel(speaker == .everyone ? "Everyone is typing" : "\(speaker.name) is typing")
    }
}

private struct Avatar: View {
    let speaker: MeetingSpeaker

    var body: some View {
        Group {
            if speaker == .everyone {
                ZStack {
                    SpriteView(sprite: VillagerID.pip.sprite, pixel: 1.4).offset(x: -10, y: 3)
                    SpriteView(sprite: VillagerID.rosie.sprite, pixel: 1.4).offset(x: 10, y: 3)
                    SpriteView(sprite: VillagerID.bea.sprite, pixel: 1.7).offset(y: -1)
                }
            } else {
                SpriteView(sprite: speaker.sprite, pixel: 2.2)
            }
        }
        .frame(width: 40, height: 40)
        .clipped()
        .background(speaker.color.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 1.5))
    }
}

// MARK: - The full report

struct TownReportView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let week = store.week
        let maxTotal = max(week.map(\.total).max() ?? 0, 1)
        let letters = week.map(\.letters).reduce(0, +)
        let pages = week.map(\.pages).reduce(0, +)
        let habits = week.map(\.habits).reduce(0, +)
        let best = week.max { $0.total < $1.total }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    SpriteView(sprite: Sprites.mayor, pixel: 3)
                        .padding(6)
                        .pixelBox(Color(hex: 0xE4F2DA), shadow: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("THE MAYOR'S REPORT").font(.pixel(11)).foregroundStyle(Theme.muted)
                        Text("This week in Workdoro").font(.pixel(21, .heavy)).foregroundStyle(Theme.ink)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(week) { day in dayBar(day, maxTotal) }
                    }
                    .frame(height: 150, alignment: .bottom)
                    HStack(spacing: 14) {
                        legend(Theme.pipBlue, "Letters"); legend(Theme.moPlum, "Pages"); legend(Theme.leaf, "Habits")
                    }
                }
                .padding(16)
                .pixelBox(Theme.card)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stat("\(letters)", letters == 1 ? "letter delivered" : "letters delivered", Theme.pipBlue, VillagerID.pip.sprite)
                    stat("\(pages)", pages == 1 ? "page written" : "pages written", Theme.moPlum, VillagerID.mo.sprite)
                    stat("\(habits)", habits == 1 ? "habit kept" : "habits kept", Theme.leaf, VillagerID.juniper.sprite)
                    stat("\(store.focusMinutes)m", "focus at the café", Theme.beaOrange, VillagerID.bea.sprite)
                    stat("\(store.streak)", "day streak", Theme.red, Sprites.flame)
                    stat("\(store.treatsInJar)", "treats in the jar", Color(hex: 0xC2577A), VillagerID.rosie.sprite)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TOWN PROGRESS").font(.pixel(11)).foregroundStyle(Theme.muted)
                    progress("Pip's bike", store.bikeParts, VillageStore.bikeGoal, Theme.pipBlue)
                    progress("Mo's book", min(store.pages.count, VillageStore.bookGoal), VillageStore.bookGoal, Theme.moPlum)
                    progress("Café regulars", min(store.focusMinutes, VillageStore.cafeGoal) * 10 / VillageStore.cafeGoal, 10, Theme.beaOrange, detail: "\(min(store.focusMinutes, VillageStore.cafeGoal))/\(VillageStore.cafeGoal) min")
                }
                .padding(16)
                .pixelBox(Theme.card)

                Text(bestLine(best))
                    .font(.pixel(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pixelBox(Color(hex: 0xFFFBEF))
                Text("Signed, Mayor Barnaby")
                    .font(.pixel(12, .heavy).italic())
                    .foregroundStyle(Color(hex: 0x3E6B48))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .padding(.top, 8)
        }
        .background(Theme.paper)
        .presentationDragIndicator(.visible)
    }

    private func dayBar(_ day: VillageStore.DayReport, _ maxTotal: Int) -> some View {
        let h = CGFloat(day.total) / CGFloat(maxTotal) * 110
        let n = CGFloat(max(day.total, 1))
        let isToday = day.id == VillageStore.dayKey()
        return VStack(spacing: 6) {
            Text(day.total > 0 ? "\(day.total)" : "").font(.pixel(10, .heavy)).foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                Rectangle().fill(Theme.leaf).frame(height: h * CGFloat(day.habits) / n)
                Rectangle().fill(Theme.moPlum).frame(height: h * CGFloat(day.pages) / n)
                Rectangle().fill(Theme.pipBlue).frame(height: h * CGFloat(day.letters) / n)
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(h, 4), alignment: .bottom)
            .background(day.total == 0 ? Theme.empty : Color.clear)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
            Text(day.label).font(.pixel(11, .heavy)).foregroundStyle(isToday ? Theme.red : Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.label): \(count(day.letters, "letter")), \(count(day.pages, "page")), \(count(day.habits, "habit"))")
    }

    private func bestLine(_ best: VillageStore.DayReport?) -> String {
        guard let best, best.total > 0 else { return "A quiet week so far. Deliver a letter or water a plant and this report fills right up." }
        return "Best day this week: \(best.fullName), with \(count(best.total, "thing")) done. Splendid work!"
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 10, height: 10).overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            Text(text).font(.pixel(10, .heavy)).foregroundStyle(Theme.muted)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color, _ sprite: Sprite) -> some View {
        HStack(alignment: .center, spacing: 10) {
            SpriteView(sprite: sprite, pixel: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.pixel(24, .heavy)).foregroundStyle(color)
                Text(label).font(.pixel(10, .heavy)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(Theme.card)
        .accessibilityElement(children: .combine)
    }

    private func progress(_ title: String, _ value: Int, _ goal: Int, _ color: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.pixel(12, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                Text(detail ?? "\(value)/\(goal)").font(.pixel(11, .heavy)).foregroundStyle(Theme.muted)
            }
            PixelProgress(value: value, total: goal, color: color)
        }
        .accessibilityElement(children: .combine)
    }
}
