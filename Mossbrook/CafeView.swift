import SwiftUI

enum FocusFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Café layout

enum CafeLayout {
    struct Table { let left: Int; let top: Int; let w: Int }

    struct Seat {
        let id: Int
        let x: Int
        let top: Int

        /// Where you stand when you walk up behind the chair.
        var aisle: CGPoint { CGPoint(x: Double(x + 8), y: Double(top + 12)) }
        var hitRect: CGRect { CGRect(x: Double(x - 2), y: Double(top - 2), width: 20, height: 28) }
    }

    static let tables: [Table] = [
        Table(left: 26, top: 116, w: 76),
        Table(left: 22, top: 164, w: 30), Table(left: 72, top: 164, w: 30)
    ]

    static let seats: [Seat] = [
        Seat(id: 0, x: 28, top: 100), Seat(id: 1, x: 43, top: 100), Seat(id: 2, x: 58, top: 100),
        Seat(id: 3, x: 73, top: 100), Seat(id: 4, x: 88, top: 100),
        Seat(id: 5, x: 22, top: 148), Seat(id: 6, x: 37, top: 148),
        Seat(id: 7, x: 72, top: 148), Seat(id: 8, x: 87, top: 148)
    ]

    struct Regular {
        let seat: Int
        let sprite: Sprite
        let name: String?
        let base: Int
    }

    static let regulars: [Regular] = [
        Regular(seat: 1, sprite: Sprites.customers[0], name: nil, base: 12),
        Regular(seat: 4, sprite: Sprites.customers[3], name: nil, base: 26),
        Regular(seat: 5, sprite: Sprites.customers[2], name: nil, base: 18)
    ]

    /// Little details that make people look busy.
    static let headphones: Set<Int> = [5]
    static let bookStacks: Set<Int> = [4]

    /// Seat 6 belongs to a customer who comes and goes.
    static let visitorSeat = 6
    static var takenSeats: Set<Int> { Set(regulars.map(\.seat) + [visitorSeat]) }
    static var freeSeats: [Seat] { seats.filter { !takenSeats.contains($0.id) } }

    static let orderSpot = CGPoint(x: 82, y: 92)
    static let door = CGPoint(x: 134, y: 214)
    static let corridors: [Double] = [14, 114]

    /// Routes along the side corridors so nobody walks through tables.
    static func route(from p: CGPoint, to q: CGPoint) -> [CGPoint] {
        if p.y <= 96 && q.y <= 96 { return [p, q] }
        let anchorX = p.y <= 96 ? q.x : p.x
        let c = corridors.min { abs($0 - anchorX) < abs($1 - anchorX) } ?? 114
        var points = [p, CGPoint(x: c, y: p.y), CGPoint(x: c, y: q.y), q]
        points = points.enumerated().filter { i, pt in i == 0 || pt != points[i - 1] }.map(\.1)
        return points
    }

    static let walkLanes: [Double] = [92, 112, 160, 186]

    static func clampToFloor(_ g: CGPoint) -> CGPoint {
        let y = walkLanes.min { abs($0 - g.y) < abs($1 - g.y) } ?? 92
        return CGPoint(x: min(max(g.x, 8), 120), y: y)
    }
}

/// A walk along a series of points at a steady pace.
struct WalkPath {
    var points: [CGPoint]
    var start: Date
    var speed: Double = 30

    init(at point: CGPoint) {
        points = [point]
        start = .distantPast
    }

    init(points: [CGPoint], start: Date = Date(), speed: Double = 30) {
        self.points = points
        self.start = start
        self.speed = speed
    }

    var duration: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } / speed
    }

    var end: CGPoint { points.last ?? .zero }

    func state(at date: Date) -> (point: CGPoint, walking: Bool, facingLeft: Bool) {
        var remaining = date.timeIntervalSince(start) * speed
        guard remaining > 0, points.count > 1 else { return (points.first ?? .zero, false, false) }
        for (a, b) in zip(points, points.dropFirst()) {
            let d = hypot(b.x - a.x, b.y - a.y)
            if remaining <= d, d > 0 {
                let k = remaining / d
                return (CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k), true, b.x < a.x)
            }
            remaining -= d
        }
        let last = points[points.count - 1], prev = points[points.count - 2]
        return (last, false, last.x < prev.x)
    }
}

/// You, inside the café: where you are, what you're doing, what you're holding.
@Observable
final class CafeScene {
    enum Mode: Equatable { case idle, ordering, brewing, holding, seated }

    var mode: Mode = .idle
    var path: WalkPath
    var seatID: Int?
    var drink: Drink = .espresso
    var title = ""
    var letterID: UUID?
    var brewStart: Date?
    var eatingUntil: Date?
    var workMinutes = 25
    var breakMinutes = 0
    var rounds = 1
    private var arrival: Task<Void, Never>?

    init(seat: Int?) {
        if let seat, let s = CafeLayout.seats.first(where: { $0.id == seat }) {
            seatID = seat
            mode = .seated
            path = WalkPath(at: s.aisle)
        } else {
            path = WalkPath(points: [CafeLayout.door, CGPoint(x: 114, y: 214), CGPoint(x: 114, y: 186)])
        }
    }

    var isHoldingDrink: Bool { mode == .holding }

    func position(at date: Date) -> (point: CGPoint, walking: Bool, facingLeft: Bool) {
        path.state(at: date)
    }

    func walk(to target: CGPoint, then action: (() -> Void)? = nil) {
        let from = path.state(at: Date()).point
        path = WalkPath(points: CafeLayout.route(from: from, to: target))
        arrival?.cancel()
        let wait = path.duration
        arrival = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, self != nil else { return }
            action?()
        }
    }

    func standUp() {
        if let id = seatID, let s = CafeLayout.seats.first(where: { $0.id == id }) {
            path = WalkPath(at: s.aisle)
        }
        seatID = nil
        mode = .idle
    }
}

// MARK: - Café screen

/// Bea's café: walk in, order at the counter, take a seat and focus until the cup is empty.
struct CafeView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scene = CafeScene(seat: nil)
    @State private var loaded = false
    @State private var showStrict = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: 0x3A2218).ignoresSafeArea()
            if let finished = store.justFinished, store.activeFocus == nil {
                FocusDoneView(session: finished, again: {
                    store.justFinished = nil
                    scene.standUp()
                }, close: { dismiss() })
            } else {
                CafeFloor(scene: scene, openStrict: { showStrict = true })
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .pixelBox(Theme.card, shadow: 2)
            }
            .accessibilityLabel(store.isFocusing ? "Back to the village. Your session keeps going." : "Leave the café")
            .padding(.trailing, 18)
            .padding(.top, 8)
        }
        .villageOverlays()
        // The café is always dim: light status bar text on top, while everything inside keeps its own colours.
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showStrict) {
            StrictModeView()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let session = store.activeFocus {
                scene = CafeScene(seat: session.seat ?? 2)
                scene.drink = Drink(rawValue: session.drink) ?? .espresso
            }
        }
        .onChange(of: store.activeFocus?.id) {
            if store.activeFocus == nil, scene.mode == .seated, store.justFinished == nil {
                scene.standUp()
            }
        }
    }
}

struct CafeFloor: View {
    @Environment(VillageStore.self) private var store
    @Bindable var scene: CafeScene
    let openStrict: () -> Void

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, 1) / 128
            let rows = Int(max(geo.size.height, 1) / s) + 2
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let now = timeline.date
                let t = now.timeIntervalSinceReferenceDate
                let you = scene.position(at: now)
                let session = store.activeFocus
                let remaining = session.map { $0.end.timeIntervalSince(now) } ?? 0
                let fill = session.map { max(0, min(1, remaining / $0.duration)) } ?? 1
                let elapsed = session.map { max(0, Int(($0.duration - remaining) / 60)) } ?? 0
                let visitor = CafeRenderer.visitor(at: t)
                let bea = CafeRenderer.baristaX(at: now, brewing: scene.mode == .brewing)

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        CafeRenderer.draw(
                            Painter(ctx: ctx, s: s), t: t, rows: rows, phase: store.phase, level: store.cafeLevel,
                            you: you, scene: scene, fill: fill, visitor: visitor, beaX: bea,
                            onBreak: session?.onBreak ?? false, eating: (scene.eatingUntil ?? .distantPast) > now,
                            breakT: session.map { now.timeIntervalSince($0.start) } ?? 0
                        )
                    }

                    Text("WORKDORO CAFÉ")
                        .font(.pixel(13, .heavy))
                        .foregroundStyle(Color(hex: 0x4A2C1D))
                        .position(x: 84 * s, y: 25 * s)
                        .allowsHitTesting(false)

                    boardText(session: session, remaining: remaining)
                        .position(x: 61 * s, y: 39 * s)
                        .allowsHitTesting(false)

                    ForEach(CafeLayout.regulars, id: \.seat) { regular in
                        if let seat = CafeLayout.seats.first(where: { $0.id == regular.seat }) {
                            let minutes = regular.base + Int(t / 60) % 90
                            SeatBubble(text: regular.name.map { "\($0) · \(minutes)m" } ?? "\(minutes)m", highlight: false)
                                .fixedSize()
                                .position(x: CGFloat(seat.x + 8) * s, y: CGFloat(seat.top - 1 - (seat.id % 2) * 7) * s)
                                .allowsHitTesting(false)
                        }
                    }

                    if let session, session.onBreak, let seat = CafeLayout.seats.first(where: { $0.id == scene.seatID }) {
                        let tour = CafeRenderer.breakTour(seat, elapsed: now.timeIntervalSince(session.start))
                        let chat = CafeRenderer.breakChat(tour)
                        SeatBubble(text: chat.you ?? (tour.walking ? "YOU · on a break" : "YOU"), highlight: true)
                            .fixedSize()
                            .position(x: min(max(tour.point.x * s, 80), geo.size.width - 80), y: (tour.point.y - 21) * s)
                            .allowsHitTesting(false)
                        if let reply = chat.them {
                            switch tour.talk {
                            case .bea:
                                beaBubble(reply, bea: bea, s: s, width: geo.size.width)
                            case .seat(let id):
                                if let friend = CafeLayout.seats.first(where: { $0.id == id }) {
                                    SpeechBubble(text: reply, size: 10)
                                        .fixedSize()
                                        .position(x: min(max(Double(friend.x + 8) * s, 80), geo.size.width - 80), y: CGFloat(friend.top - 12) * s)
                                        .allowsHitTesting(false)
                                }
                            case .none:
                                EmptyView()
                            }
                        }
                    } else {
                        youBubble(elapsed: elapsed)
                            .fixedSize()
                            .position(x: you.point.x * s, y: (scene.mode == .seated ? youSeatTop() - 1 : you.point.y - 19) * s)
                            .allowsHitTesting(false)
                    }

                    beaBubble(beaLine(t: t), bea: bea, s: s, width: geo.size.width)
                        .opacity(scene.mode == .seated ? 0 : 1)
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    handleTap(CGPoint(x: value.location.x / s, y: value.location.y / s))
                })
            }
            .overlay(alignment: .bottom) {
                CafeHUD(scene: scene, goOrder: goOrder, sitAnywhere: sitAnywhere, openStrict: openStrict)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            .overlay(alignment: .topLeading) {
                Text("CAFÉ · \(store.focusMinutes)/\(VillageStore.cafeGoal) MIN")
                    .font(.pixel(10, .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .pixelBox(Theme.gold, shadow: 2)
                    .padding(.leading, 16)
                    .padding(.top, 64)
            }
        }
        .ignoresSafeArea(edges: .top)

    }

    @ViewBuilder
    private func boardText(session: FocusSession?, remaining: TimeInterval) -> some View {
        VStack(spacing: 2) {
            if let session {
                Text(session.onBreak ? "BREAK" : (session.rounds > 1 ? "ROUND \(session.round)/\(session.rounds)" : (Drink(rawValue: session.drink) ?? .espresso).name.uppercased()))
                    .font(.pixel(9, .heavy))
                    .foregroundStyle(Color(hex: 0xF4E3B5).opacity(0.8))
                Text(FocusFormat.clock(remaining))
                    .font(.pixel(22, .heavy))
                    .foregroundStyle(Color(hex: 0xFFF6DD))
                    .monospacedDigit()
            } else {
                Text("TODAY")
                    .font(.pixel(9, .heavy))
                    .foregroundStyle(Color(hex: 0xF4E3B5).opacity(0.8))
                Text("Tea 15\nEspresso 25\nLatte 50")
                    .font(.pixel(9, .bold))
                    .foregroundStyle(Color(hex: 0xFFF6DD))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func youBubble(elapsed: Int) -> some View {
        let text: String
        switch scene.mode {
        case .seated: text = "YOU · \(elapsed)m"
        case .holding: text = "YOU · \(scene.drink.name)"
        default: text = "YOU"
        }
        return SeatBubble(text: text, highlight: true)
    }

    private func youSeatTop() -> Double {
        guard let seat = CafeLayout.seats.first(where: { $0.id == scene.seatID }) else { return 104 }
        return Double(seat.top - (seat.id % 2) * 7)
    }

    /// Bea's speech bubble, sitting just above her head with its tail pointing at her.
    private func beaBubble(_ text: String, bea: Double, s: CGFloat, width: CGFloat) -> some View {
        let headX = (bea + 8) * s
        return SpeechBubble(text: text, size: 10)
            .fixedSize()
            .alignmentGuide(.bottom) { $0[.bottom] }
            .frame(width: 0, height: 0, alignment: .bottom)
            .position(x: min(max(headX, 80), width - 80), y: 45 * s)
            .allowsHitTesting(false)
    }

    private func beaLine(t: Double) -> String {
        switch scene.mode {
        case .ordering: return "What can I get you?"
        case .brewing: return "One \(scene.drink.name.lowercased()), coming up!"
        case .holding: return "Grab any free seat!"
        case .seated: return ["Shh, deep work.", "Refills are free.", "You're doing great."][Int(t / 6) % 3]
        case .idle: return ["Order at the counter!", "Kettle's on!", "Welcome in!"][Int(t / 6) % 3]
        }
    }

    // MARK: Moving around

    private func handleTap(_ g: CGPoint) {
        switch scene.mode {
        case .seated, .brewing:
            return
        case .ordering:
            scene.mode = .idle
        case .holding:
            if let seat = CafeLayout.freeSeats.first(where: { $0.hitRect.contains(g) }) {
                sit(seat)
            } else {
                scene.walk(to: CafeLayout.clampToFloor(g))
            }
        case .idle:
            if g.y < 96 && g.x > 36 {
                goOrder()
            } else {
                scene.walk(to: CafeLayout.clampToFloor(g))
            }
        }
    }

    private func goOrder() {
        scene.walk(to: CafeLayout.orderSpot) { [scene] in
            withAnimation(.snappy) { scene.mode = .ordering }
        }
    }

    private func sitAnywhere() {
        let here = scene.position(at: Date()).point
        let seat = CafeLayout.freeSeats.min { hypot($0.aisle.x - here.x, $0.aisle.y - here.y) < hypot($1.aisle.x - here.x, $1.aisle.y - here.y) }
        if let seat { sit(seat) }
    }

    private func sit(_ seat: CafeLayout.Seat) {
        scene.walk(to: seat.aisle) { [scene, store] in
            withAnimation(.snappy) {
                scene.seatID = seat.id
                scene.mode = .seated
            }
            store.startFocus(
                title: scene.title, drink: scene.drink, letterID: scene.letterID, seat: seat.id,
                minutes: scene.workMinutes, breakMinutes: scene.breakMinutes, rounds: scene.rounds
            )
        }
    }
}

// MARK: - Bottom card

struct CafeHUD: View {
    @Environment(VillageStore.self) private var store
    @Bindable var scene: CafeScene
    let goOrder: () -> Void
    let sitAnywhere: () -> Void
    let openStrict: () -> Void

    var body: some View {
        Group {
            switch scene.mode {
            case .seated:
                if let session = store.activeFocus {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let fill = max(0, min(1, session.end.timeIntervalSince(tl.date) / session.duration))
                        if session.onBreak {
                            BreakCard(session: session, remaining: session.end.timeIntervalSince(tl.date)) {
                                if store.eatTreat() { scene.eatingUntil = Date().addingTimeInterval(4) }
                            }
                        } else {
                            FocusCard(
                                title: session.rounds > 1 ? "\(session.title) · \(session.round)/\(session.rounds)" : session.title,
                                fill: fill, leave: { store.cancelFocus() }, strict: openStrict
                            )
                        }
                    }
                }
            case .ordering:
                OrderCard(scene: scene)
            case .brewing:
                hint(title: "Bea is making your \(scene.drink.name.lowercased())…", detail: "Steam, beans, a little foam.")
            case .holding:
                hint(title: "Your \(scene.drink.name.lowercased()) is ready", detail: "Tap any free seat (the glowing ones).", button: "Sit anywhere", action: sitAnywhere)
            case .idle:
                hint(title: "Welcome to the café", detail: "Tap the counter to order, or tap the floor to walk around.", button: "Order", action: goOrder)
            }
        }
        .animation(.snappy, value: scene.mode)
    }

    private func hint(title: String, detail: String, button: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            SpriteView(sprite: Sprites.bea, pixel: 2.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.pixel(15, .heavy))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.pixel(11, .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let button, let action {
                Button(button, action: action)
                    .buttonStyle(PixelButtonStyle(fill: Theme.beaOrange, foreground: Theme.cream, hPad: 12))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(14)
        .pixelBox(Theme.card)
    }
}

struct OrderCard: View {
    @Environment(VillageStore.self) private var store
    @Bindable var scene: CafeScene
    @State private var custom = ""
    @State private var letterID: UUID?
    @State private var drink: Drink = .espresso
    @State private var work = 25
    @State private var rest = 0
    @State private var rounds = 1

    private let presets: [(String, Int, Int, Int)] = [("25/5", 25, 5, 4), ("50/5", 50, 5, 2), ("50/10", 50, 10, 2), ("90/15", 90, 15, 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHAT ARE YOU WORKING ON?")
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Not now") { scene.mode = .idle }
                    .font(.pixel(11, .heavy))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 32)
            }
            if !store.openLetters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.openLetters.prefix(5)) { letter in
                            let selected = letterID == letter.id
                            Button {
                                letterID = selected ? nil : letter.id
                                if !selected { custom = "" }
                            } label: {
                                Text(letter.title)
                                    .font(.pixel(12, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .pixelBox(selected ? Color(hex: 0xFFF1C9) : Theme.card, shadow: selected ? 2 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
            TextField("", text: $custom, prompt: Text("e.g. finish my essay").foregroundStyle(Theme.muted))
                .font(.pixel(14, .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .pixelBox(Theme.card, shadow: 1)
                .onChange(of: custom) { if !custom.isEmpty { letterID = nil } }

            HStack(spacing: 8) {
                ForEach(Drink.allCases) { option in
                    let selected = drink == option
                    Button {
                        drink = option
                        work = option.minutes
                    } label: {
                        VStack(spacing: 2) {
                            CupIcon(color: option.color, fill: 1).frame(width: 24, height: 20)
                            Text(option.name)
                                .font(.pixel(10, .heavy))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(option.minutes)m")
                                .font(.pixel(9, .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .pixelBox(selected ? Color(hex: 0xFFF1C9) : Theme.card, shadow: selected ? 2 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { preset in
                        let on = work == preset.1 && rest == preset.2 && rounds == preset.3
                        Button {
                            work = preset.1; rest = preset.2; rounds = preset.3
                        } label: {
                            Text(preset.0)
                                .font(.pixel(11, .heavy))
                                .foregroundStyle(on ? Theme.cream : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .pixelBox(on ? Theme.beaOrange : Theme.card, shadow: on ? 2 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    stepper("WORK", "\(work)m", minus: { work = max(5, work - 5) }, plus: { work = min(180, work + 5) })
                    stepper("BREAK", rest == 0 ? "off" : "\(rest)m", minus: { rest = max(0, rest - 5) }, plus: { rest = min(30, rest + 5) })
                    stepper("ROUNDS", "×\(rounds)", minus: { rounds = max(1, rounds - 1) }, plus: { rounds = min(6, rounds + 1) })
                }
            }

            Button {
                order()
            } label: {
                Text(rounds > 1 ? "Order · \(rounds)×\(work)m\(rest > 0 ? " + \(rest)m breaks" : "")" : "Order \(drink.name.lowercased()) · \(work)m")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(fill: Theme.beaOrange, foreground: Theme.cream))
        }
        .padding(14)
        .pixelBox(Theme.card)
    }

    private func stepper(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.pixel(8, .heavy)).foregroundStyle(Theme.muted)
            HStack(spacing: 0) {
                Button(action: minus) { Image(systemName: "minus").font(.system(size: 10, weight: .heavy)).frame(width: 26, height: 30) }
                    .accessibilityLabel("Less \(label.lowercased())")
                Text(value).font(.pixel(12, .heavy)).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
                Button(action: plus) { Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).frame(width: 26, height: 30) }
                    .accessibilityLabel("More \(label.lowercased())")
            }
            .foregroundStyle(Theme.ink)
            .pixelBox(Theme.card, shadow: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func order() {
        scene.workMinutes = work
        scene.breakMinutes = rest
        scene.rounds = rounds
        if let letterID, let letter = store.letters.first(where: { $0.id == letterID }) {
            scene.title = letter.title
        } else {
            scene.title = custom
        }
        scene.letterID = letterID
        scene.drink = drink
        scene.brewStart = Date()
        withAnimation(.snappy) { scene.mode = .brewing }
        Task { @MainActor [scene, store] in
            try? await Task.sleep(for: .seconds(2.6))
            guard scene.mode == .brewing else { return }
            withAnimation(.snappy) { scene.mode = .holding }
            store.toast = VillageStore.Toast(speaker: .bea, text: "Your \(scene.drink.name.lowercased()) is ready! Pick a seat.")
        }
    }
}

/// The card at the bottom of the café during a break.
struct BreakCard: View {
    @Environment(VillageStore.self) private var store
    let session: FocusSession
    let remaining: TimeInterval
    let eat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BREAK · ROUND \(session.round) OF \(session.rounds) DONE")
                        .font(.pixel(10))
                        .foregroundStyle(Theme.muted)
                    Text("Wander, sip, say hi.")
                        .font(.pixel(16, .heavy))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Text(FocusFormat.clock(remaining))
                    .font(.pixel(24, .heavy))
                    .foregroundStyle(Theme.leaf)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Button(action: eat) {
                    Label("Have a treat (\(store.treatsInJar))", systemImage: "birthday.cake.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(fill: Color(hex: 0xC2577A), foreground: Theme.cream, hPad: 8))
                Button {
                    store.skipBreak()
                } label: {
                    Text("Skip break").frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 8))
            }
        }
        .padding(14)
        .pixelBox(Color(hex: 0xEAF6DC))
    }
}

/// The small card at the bottom of the café while you focus.
struct FocusCard: View {
    let title: String
    let fill: Double
    let leave: () -> Void
    var strict: (() -> Void)? = nil
    @State private var hold: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.empty)
                    Rectangle().fill(Theme.leaf).frame(width: geo.size.width * (1 - fill))
                }
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            }
            .frame(height: 12)
            .accessibilityLabel("\(Int((1 - fill) * 100)) percent done")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUSING ON")
                        .font(.pixel(10))
                        .foregroundStyle(Theme.muted)
                    Text(title)
                        .font(.pixel(16, .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let strict {
                    Button(action: strict) {
                        VStack(spacing: 1) {
                            Image(systemName: "rectangle.landscape.rotate")
                                .font(.system(size: 15, weight: .heavy))
                            Text("STRICT")
                                .font(.pixel(8, .heavy))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(width: 52, height: 44)
                    }
                    .buttonStyle(PixelButtonStyle(fill: Theme.gold, hPad: 0))
                    .accessibilityLabel("Strict mode")
                }
                Text("Hold to leave")
                    .font(.pixel(13, .heavy))
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
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
                    .onLongPressGesture(minimumDuration: 1.2) {
                        hold = 0
                        leave()
                    } onPressingChanged: { pressing in
                        withAnimation(pressing ? .linear(duration: 1.2) : .easeOut(duration: 0.2)) {
                            hold = pressing ? 1 : 0
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Leave the café early")
                    .accessibilityAction { leave() }
            }
        }
        .padding(14)
        .pixelBox(Theme.card)
    }
}

struct FocusDoneView: View {
    @Environment(VillageStore.self) private var store
    let session: FocusSession
    let again: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                BobbingSprite(sprite: Sprites.bea, pixel: 7)
                Text("Last sip!")
                    .font(.pixel(34, .heavy))
                    .foregroundStyle(Theme.beaOrange)
                Text("+\(count(session.totalWorkMinutes, "minute")) on\n\(session.title)")
                    .font(.pixel(16, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if session.letterID != nil {
                    Text("Pip delivered that letter for you.")
                        .font(.pixel(13, .medium))
                        .foregroundStyle(Theme.pipBlue)
                }
                Text("\(count(store.focusMinutes, "minute")) in the café so far")
                    .font(.pixel(12, .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                VStack(spacing: 14) {
                    Button(action: again) {
                        Text("Another cup").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(fill: Theme.beaOrange, foreground: Theme.cream))
                    Button {
                        store.justFinished = nil
                        close()
                    } label: {
                        Text("Back to the village").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(fill: Theme.card))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }
}

/// A little pixel cup, used on the drink menu.
struct CupIcon: View {
    let color: Color
    let fill: Double

    var body: some View {
        Canvas { ctx, size in
            let s = floor(min(size.width / 12, size.height / 11))
            Painter(ctx: ctx, s: s).cup(x: 0, y: 1, w: 8, h: 8, coffee: color, fill: fill)
        }
        .accessibilityHidden(true)
    }
}

extension Painter {
    /// A mug with a handle; the drink level follows `fill` from 0 to 1.
    func cup(x: Int, y: Int, w: Int, h: Int, coffee: Color, fill: Double) {
        let ink = VillageRenderer.ink
        rect(x, y, w + 2, h + 2, ink)
        rect(x + 1, y + 1, w, h, Color(hex: 0xFFFDF6))
        rect(x + 1, y + 1, w, 1, Color(hex: 0xE6DCCB))
        let inner = max(1, h - 3)
        let level = Int((Double(inner) * fill).rounded())
        if level > 0 {
            rect(x + 2, y + h - 1 - level, w - 2, level, coffee)
            rect(x + 2, y + h - 1 - level, w - 2, 1, Color.white.opacity(0.35))
        }
        rect(x + w - 1, y + 2, 1, h - 2, Color(hex: 0xE6DCCB))
        rect(x + w + 2, y + 2, 2, 1, ink)
        rect(x + w + 3, y + 2, 1, 4, ink)
        rect(x + w + 2, y + 5, 2, 1, ink)
    }
}

/// A tiny label above someone's head in the café.
struct SeatBubble: View {
    let text: String
    let highlight: Bool

    var body: some View {
        Text(text)
            .font(.pixel(9, .heavy))
            .foregroundStyle(highlight ? Theme.cream : Theme.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(highlight ? Theme.beaOrange : Color(hex: 0xF4E3B5))
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
    }
}
