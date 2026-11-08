import SwiftUI

// MARK: - Looks

enum HallLooks {
    static let all: [Sprite] = [Sprites.you] + Sprites.customers + [Sprites.fern, Sprites.olli, Sprites.farmer]
    static func sprite(_ look: Int) -> Sprite { all[((look % all.count) + all.count) % all.count] }
}

/// Smooth walking for everyone: when someone's spot changes, they walk there from wherever they are.
final class RoomMotion {
    struct Track { var route: [CGPoint]; var start: Double }
    private var tracks: [String: Track] = [:]
    /// When each emote and line was first seen here, so it shows for the same time on every phone.
    private var seenEmote: [String: (Date, Double)] = [:]
    private var seenSay: [String: (Date, Double)] = [:]

    func place(_ id: String, target: CGPoint, now: Double) -> (point: CGPoint, walking: Bool, left: Bool) {
        if var track = tracks[id] {
            if track.route.last != target {
                let here = TogetherRoom.place(on: track.route, since: track.start, now: now).point
                track = Track(route: TogetherRoom.route(from: here, to: target), start: now)
                tracks[id] = track
            }
            return TogetherRoom.place(on: track.route, since: track.start, now: now)
        }
        tracks[id] = Track(route: [target], start: now)
        return (target, false, false)
    }

    private var seatedSince: [String: (String, Double)] = [:]

    func emote(_ v: HallVisitor, now: Double) -> (Int, Double)? {
        bubble(v.id, at: v.emoteAt, index: v.emote, store: &seenEmote, now: now, lasts: 3.5)
    }

    func say(_ v: HallVisitor, now: Double) -> Int? {
        bubble(v.id, at: v.sayAt, index: v.say, store: &seenSay, now: now, lasts: 5)?.0
    }

    /// How long someone has been in their current seat with their current order.
    func seatedFor(_ id: String, key: String?, now: Double) -> Double {
        guard let key else { seatedSince[id] = nil; return 0 }
        if seatedSince[id]?.0 != key { seatedSince[id] = (key, now) }
        return now - (seatedSince[id]?.1 ?? now)
    }

    /// True once someone has stopped at `target`.
    func arrived(_ id: String, at target: CGPoint, now: Double) -> Bool {
        guard let track = tracks[id], track.route.last == target else { return false }
        return !TogetherRoom.place(on: track.route, since: track.start, now: now).walking
    }

    private func bubble(_ id: String, at: Date?, index: Int, store: inout [String: (Date, Double)], now: Double, lasts: Double) -> (Int, Double)? {
        guard let at, index >= 0, Date().timeIntervalSince(at) < 40 else { return nil }
        if store[id]?.0 != at { store[id] = (at, now) }
        guard let first = store[id]?.1, now - first < lasts else { return nil }
        return (index, now - first)
    }
}

// MARK: - The screen

struct StudyHallView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var hall = HallService.shared
    @State private var motion = RoomMotion()
    @AppStorage("hallName") private var savedName = ""
    @AppStorage("hallLook") private var look = 0
    @AppStorage("hallRulesSeen") private var rulesSeen = false
    @State private var draft = ""
    @State private var picked: HallVisitor?
    @State private var tray: Tray?
    @State private var lastBubble = Date.distantPast
    @State private var catPetted = Date.distantPast
    @State private var rosieLine = "Welcome in!"
    @State private var rosieAt = Date()
    /// Your order: walking to the counter, then Rosie makes it, then you carry it to a table.
    @State private var order: Order?

    struct Order: Equatable {
        enum Step: Equatable { case walking, preparing(Date) }
        let food: Int
        var step: Step
    }
    @FocusState private var typing: Bool

    enum Tray { case emote, say, eat }

    var body: some View {
        GeometryReader { geo in
            let bar: CGFloat = hall.joined ? 116 : 0
            let topRoom: CGFloat = 50
            let s = max(0.5, min(geo.size.width / CGFloat(TogetherRoom.width), max(geo.size.height - bar - topRoom, 1) / CGFloat(TogetherRoom.height)))
            let oy = Int((topRoom / s).rounded())
            let cols = Int(max(geo.size.width, 1) / s) + 1
            let rows = Int(max(geo.size.height, 1) / s) + 1
            let ox = (cols - TogetherRoom.width) / 2

            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let scene = people(now: now)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        TogetherRenderer.draw(
                            Painter(ctx: ctx, s: s), t: now, cols: cols, rows: rows, ox: ox, oy: oy,
                            phase: store.phase, weather: store.weather, people: scene.map(\.drawn),
                            catHeart: Date().timeIntervalSince(catPetted) < 2.5,
                            rosieBusy: scene.contains { !$0.drawn.walking && $0.drawn.seat == nil && abs($0.drawn.point.x - TogetherRoom.orderSpot.x) < 3 && abs($0.drawn.point.y - TogetherRoom.orderSpot.y) < 1 && $0.visitor.food >= 0 && ($0.mine ? order != nil : true) }
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        tap(CGPoint(x: value.location.x / s - Double(ox), y: value.location.y / s - Double(oy)), scene: scene)
                    })

                    ForEach(scene, id: \.id) { item in
                        let x = (CGFloat(ox) + item.drawn.centerX) * s
                        let top = (item.drawn.headTop + Double(oy)) * s
                        nameTag(item.name, detail: item.detail, mine: item.mine)
                            .position(x: x, y: top - 3 * s)
                        if let line = item.say {
                            SpeechBubble(text: line, size: 10)
                                .fixedSize()
                                .position(x: min(max(x, 70), geo.size.width - 70), y: top - 9 * s - 16)
                                .allowsHitTesting(false)
                        }
                    }
                    if timeline.date.timeIntervalSince(rosieAt) < 4 {
                        SpeechBubble(text: rosieLine, size: 10)
                            .fixedSize()
                            .position(x: max((CGFloat(ox) + 25) * s, 70), y: CGFloat(30 + oy) * s)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .topLeading) { header }
            .overlay(alignment: .bottom) {
                Group {
                    if hall.joined { controls } else { joinCard }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 12)
                .padding(.bottom, bottomInset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color(hex: 0x3A2218).ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay { if !rulesSeen { rules } }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: lastBubble)
        .onAppear {
            draft = savedName
            hall.open()
            syncStatus()
            rosieAt = .now
        }
        .task {
            // Rosie calls out now and then.
            let lines = ["Fresh cookies!", "Cocoa's hot!", "Take a break, dear", "Cake just came out!"]
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(28))
                rosie(lines[i % lines.count])
                i += 1
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                tickOrder()
            }
        }
        .onDisappear { hall.close(keepSeat: store.activeFocus.map { !$0.onBreak } ?? false) }
        .onChange(of: focusKey) { syncStatus() }
        .confirmationDialog(picked?.name ?? "", isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } }), titleVisibility: .visible) {
            if let person = picked {
                if hall.joined {
                    Button("Wave at \(person.name)") { send(emote: 2) }
                    Button("Cheer them on") { send(say: 3) }
                }
                Button("Hide \(person.name)") { hall.hide(person) }
                Button("Report name", role: .destructive) { hall.report(person) }
            }
        } message: {
            Text("Hiding only affects you. Reporting also hides them, and names reported by several people are hidden for everyone.")
        }
    }

    /// The home indicator area, read from the window because this screen ignores the bottom safe area.
    private var bottomInset: CGFloat {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return max(window?.safeAreaInsets.bottom ?? 0, 12) + 4
    }

    private func rosie(_ line: String) {
        rosieLine = line
        rosieAt = .now
    }

    // MARK: Who's in the room

    struct Item {
        let id: String
        let name: String
        let detail: String?
        let mine: Bool
        let say: String?
        let drawn: TogetherRenderer.Person
        let visitor: HallVisitor
    }

    private func people(now: Double) -> [Item] {
        var list = Array(hall.visible.prefix(24))
        if let me = hall.me { list.append(me) }
        var taken: Set<String> = []
        return list.enumerated().map { i, v in
            let target = CGPoint(x: v.x, y: v.y)
            let place = motion.place(v.id, target: target, now: now)
            var seat: TogetherRoom.Spot?
            if let spot = TogetherRoom.spot(v.spot), !place.walking, !taken.contains(spot.id),
               abs(place.point.x - spot.stand.x) < 1, abs(place.point.y - spot.stand.y) < 1 {
                seat = spot
                taken.insert(spot.id)
            }
            let mine = v.id == hall.me?.id
            let sayIndex = motion.say(v, now: now)
            let emote = sayIndex == nil ? motion.emote(v, now: now) : nil
            let seed = v.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
            let heading = TogetherRoom.spot(v.spot)
            let drawn = TogetherRenderer.Person(
                look: v.look, point: place.point, walking: place.walking, left: place.left, seat: seat,
                food: v.food, carrying: seat == nil && heading?.kind == .eat,
                status: v.status, emote: emote?.0, emoteAge: emote?.1 ?? 0,
                seatedFor: motion.seatedFor(v.id, key: seat.map { "\($0.id)-\(v.food)" }, now: now), seed: seed
            )
            let line = sayIndex.flatMap { TogetherEmote.phrases.indices.contains($0) ? TogetherEmote.phrases[$0] : nil }
            return Item(id: v.id, name: mine ? savedName : v.name, detail: detail(v), mine: mine, say: line, drawn: drawn, visitor: v)
        }
    }

    private func detail(_ v: HallVisitor) -> String? {
        if v.status == .focus, let until = v.until, until > .now { return "\(max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up))))m" }
        if v.status == .rest && TogetherRoom.spot(v.spot)?.kind != .eat { return "break" }
        return nil
    }

    // MARK: Tapping the room

    private func tap(_ g: CGPoint, scene: [Item]) {
        if hypot(g.x - TogetherRoom.catSpot.x, g.y - (TogetherRoom.catSpot.y - 4)) < 9 {
            catPetted = .now
            lastBubble = .now
            return
        }
        if let item = scene.first(where: { !$0.mine && hitRect($0.drawn).contains(g) }) {
            picked = item.visitor
            return
        }
        guard hall.joined else { return }
        if let item = scene.first(where: { $0.mine }), hitRect(item.drawn).contains(g) {
            withAnimation(.snappy) { tray = tray == .emote ? nil : .emote }
            return
        }
        if TogetherRoom.counter.contains(g) { withAnimation(.snappy) { tray = .eat }; return }
        if let spot = TogetherRoom.spots.first(where: { $0.hit.contains(g) }) {
            if spot.kind == .eat { withAnimation(.snappy) { tray = .eat }; return }
            order = nil
            sit(spot)
            return
        }
        guard g.y > Double(TogetherRoom.wallBottom) else { return }
        withAnimation(.snappy) { tray = nil }
        order = nil
        hall.walk(to: TogetherRoom.snap(g))
    }

    private func hitRect(_ p: TogetherRenderer.Person) -> CGRect {
        CGRect(x: p.centerX - 9, y: p.headTop - 2, width: 18, height: 22)
    }

    private var takenSpots: Set<String> { Set(hall.visible.map(\.spot).filter { !$0.isEmpty }) }

    private func sit(_ spot: TogetherRoom.Spot, food: Int = 0) {
        guard !takenSpots.contains(spot.id) else { return }
        withAnimation(.snappy) { tray = nil }
        hall.walk(to: spot.stand, spot: spot.id, food: food)
    }

    /// Ordering: walk up to the counter, Rosie makes it, then carry it to a free café table.
    private func orderFood(_ food: Int) {
        withAnimation(.snappy) { tray = nil }
        order = Order(food: food, step: .walking)
        hall.walk(to: TogetherRoom.orderSpot, spot: "", food: food)
    }

    /// Runs a few times a second to move your order along.
    private func tickOrder() {
        guard var current = order, let me = hall.me else { return }
        let now = Date.timeIntervalSinceReferenceDate
        switch current.step {
        case .walking:
            if motion.arrived(me.id, at: TogetherRoom.orderSpot, now: now) {
                current.step = .preparing(.now)
                order = current
                let name = TogetherFood.item(current.food).name.lowercased()
                rosie(["One \(name), coming up!", "Ooh, \(name)! Good pick", "\(TogetherFood.item(current.food).name)? Just a sec!"].randomElement()!)
            }
        case .preparing(let since):
            if Date().timeIntervalSince(since) > 2.4 {
                order = nil
                rosie(["Here you go, dear!", "Enjoy!", "Fresh from the oven!"].randomElement()!)
                go(.eat, food: current.food)
            }
        }
    }

    private func go(_ kind: TogetherRoom.Kind, food: Int = 0) {
        if kind != .eat { order = nil }
        if let mine = hall.me, TogetherRoom.spot(mine.spot)?.kind == kind {
            if kind == .eat { hall.walk(to: CGPoint(x: mine.x, y: mine.y), spot: mine.spot, food: food) }
            withAnimation(.snappy) { tray = nil }
            return
        }
        let me = CGPoint(x: hall.me?.x ?? 64, y: hall.me?.y ?? 128)
        let free = TogetherRoom.spots.filter { $0.kind == kind && !takenSpots.contains($0.id) }
            .min { hypot($0.stand.x - me.x, $0.stand.y - me.y) < hypot($1.stand.x - me.x, $1.stand.y - me.y) }
        if let free { sit(free, food: food) }
    }

    private func send(emote i: Int) {
        guard Date().timeIntervalSince(lastBubble) > 1.2 else { return }
        lastBubble = .now
        hall.emote(i)
        withAnimation(.snappy) { tray = nil }
    }

    private func send(say i: Int) {
        guard Date().timeIntervalSince(lastBubble) > 1.2 else { return }
        lastBubble = .now
        hall.say(i)
        withAnimation(.snappy) { tray = nil }
    }

    // MARK: Focus

    private var myStatus: (HallVisitor.Status, Date?) {
        guard let f = store.activeFocus else { return (.here, nil) }
        return (f.onBreak ? .rest : .focus, f.end)
    }

    private var focusKey: String {
        guard let f = store.activeFocus else { return "none" }
        return "\(f.id)-\(f.round)-\(f.onBreak)"
    }

    private func syncStatus() {
        let (status, until) = myStatus
        hall.update(status: status, until: until)
    }

    // MARK: Pieces

    private func nameTag(_ name: String, detail: String?, mine: Bool) -> some View {
        HStack(spacing: 3) {
            Text(name).font(.pixel(9, .heavy)).foregroundStyle(Theme.ink)
            if let detail { Text(detail).font(.pixel(8, .bold)).foregroundStyle(Theme.muted) }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(mine ? Theme.gold : Theme.card)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
        .allowsHitTesting(false)
    }

    private var header: some View {
        let n = hall.visible.count + (hall.joined ? 1 : 0)
        return VStack(alignment: .leading, spacing: 4) {
            Text("TOGETHER HOUSE")
                .font(.pixel(14, .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .pixelBox(Color(hex: 0xF7B7CF), shadow: 2)
            Group {
                switch hall.phase {
                case .ready, .idle: Text(n == 0 ? "Just the cat for now" : count(n, "person", plural: "people") + " here right now")
                case .opening: Text("Opening the door…")
                case .offline: Text("Can't reach the house")
                }
            }
            .font(.pixel(10, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .pixelBox(Theme.card, shadow: 2)
        }
        .padding(.leading, 14)
        .padding(.top, 6)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .pixelBox(Theme.card, shadow: 2)
        }
        .accessibilityLabel("Back to the village")
        .padding(.trailing, 16)
        .padding(.top, 6)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            if let tray {
                trayView(tray).transition(.move(edge: .bottom).combined(with: .opacity))
            } else if TogetherRoom.spot(hall.me?.spot ?? "")?.kind == .work {
                focusStrip
            }
            HStack(spacing: 8) {
                actionButton("laptopcomputer", "Work", color: Color(hex: 0xA9C8F5)) { go(.work) }
                actionButton("fork.knife", "Eat", color: Color(hex: 0xF7B7CF), on: tray == .eat) { toggle(.eat) }
                actionButton("sofa.fill", "Relax", color: Color(hex: 0x9CCFB8)) { go(.relax) }
                actionButton("face.smiling.inverse", "Emote", color: Theme.gold, on: tray == .emote) { toggle(.emote) }
                actionButton("text.bubble.fill", "Say", color: Color(hex: 0xE8D5F0), on: tray == .say) { toggle(.say) }
            }
        }
    }

    private func toggle(_ t: Tray) {
        withAnimation(.snappy) { tray = tray == t ? nil : t }
    }

    private func actionButton(_ symbol: String, _ label: String, color: Color, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                Text(label).font(.pixel(9, .heavy))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(on ? color.opacity(0.6) : color)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(x: on ? 1 : 3, y: on ? 1 : 3))
            .offset(x: on ? 2 : 0, y: on ? 2 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func trayView(_ tray: Tray) -> some View {
        Group {
            switch tray {
            case .emote:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(TogetherEmote.all.indices, id: \.self) { i in
                        Button { send(emote: i) } label: {
                            VStack(spacing: 2) {
                                SpriteView(sprite: TogetherEmote.all[i], pixel: 3)
                                    .frame(height: 27)
                                Text(TogetherEmote.names[i]).font(.pixel(7, .heavy)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.card)
                            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TogetherEmote.names[i])
                    }
                }
            case .say:
                FlowRow(spacing: 6) {
                    ForEach(TogetherEmote.phrases.indices, id: \.self) { i in
                        Button { send(say: i) } label: {
                            Text(TogetherEmote.phrases[i])
                                .font(.pixel(11, .bold)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Theme.card)
                                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .eat:
                VStack(spacing: 6) {
                    HStack {
                        Text("ROSIE'S MENU").font(.pixel(12, .heavy)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("on the house ♡").font(.pixel(9, .bold)).foregroundStyle(Color(hex: 0xC2577A))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: 0xF7B7CF))
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(TogetherFood.menu.indices, id: \.self) { i in
                            let item = TogetherFood.menu[i]
                            Button { orderFood(i) } label: {
                                HStack(spacing: 6) {
                                    SpriteView(sprite: item.sprite, pixel: 3)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name).font(.pixel(10, .heavy)).foregroundStyle(Theme.ink)
                                        Text(item.blurb).font(.pixel(7, .semibold)).foregroundStyle(Theme.muted)
                                    }
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Theme.card)
                                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Order \(item.name)")
                        }
                    }
                }
            }
        }
        .padding(8)
        .pixelBox(Theme.cream, shadow: 2)
    }

    @ViewBuilder private var focusStrip: some View {
        HStack(spacing: 8) {
            if let f = store.activeFocus {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text(f.onBreak ? "Break · \(FocusFormat.clock(f.end.timeIntervalSince(tl.date)))" : "Focusing · \(FocusFormat.clock(f.end.timeIntervalSince(tl.date)))")
                        .font(.pixel(13, .heavy)).foregroundStyle(Theme.ink).monospacedDigit()
                }
                Spacer()
            } else {
                Text("Focus:").font(.pixel(12, .heavy)).foregroundStyle(Theme.ink)
                Button("25 min") { store.startFocus(title: "Together House", drink: .espresso, letterID: nil) }
                    .buttonStyle(PixelButtonStyle(hPad: 10))
                Button("50 min") { store.startFocus(title: "Together House", drink: .latte, letterID: nil) }
                    .buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 10))
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .pixelBox(Theme.cream, shadow: 2)
    }

    // MARK: Joining

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .offline(let why) = hall.phase {
                HStack {
                    Text(why).font(.pixel(11, .semibold)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Try again") { hall.retry() }.font(.pixel(11, .heavy)).foregroundStyle(Theme.ink).underline()
                }
            }
            Text("Come in, grab a snack, find a seat. Real people from around the world hang out and work here.")
                .font(.pixel(11, .semibold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { look -= 1 } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .heavy)) }
                    .accessibilityLabel("Previous look")
                SpriteView(sprite: HallLooks.sprite(look), pixel: 2.5)
                Button { look += 1 } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)) }
                    .accessibilityLabel("Next look")
                TextField("Your name", text: $draft)
                    .font(.pixel(14, .bold))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($typing)
                    .onSubmit(comeIn)
                    .onChange(of: draft) { if draft.count > NameRules.maxLength { draft = String(draft.prefix(NameRules.maxLength)) } }
                    .padding(.horizontal, 8)
                    .frame(height: 40)
                    .background(Theme.card)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            }
            .foregroundStyle(Theme.ink)
            if !hall.canJoin {
                Text("Sign in to iCloud in Settings to come in. You can still peek inside.")
                    .font(.pixel(10, .semibold)).foregroundStyle(Theme.red)
            } else if !draft.isEmpty, let problem = NameRules.problem(draft) {
                Text(problem).font(.pixel(10, .semibold)).foregroundStyle(Theme.red)
            }
            Button("Come in", action: comeIn)
                .buttonStyle(PixelButtonStyle(fill: Color(hex: 0xF7B7CF)))
                .disabled(!hall.canJoin || NameRules.problem(draft) != nil)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(Theme.cream)
    }

    private func comeIn() {
        guard hall.canJoin, NameRules.problem(draft) == nil else { return }
        savedName = NameRules.clean(draft)
        typing = false
        hall.join(name: savedName, look: look)
        syncStatus()
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            send(say: 0)
        }
    }

    private var rules: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to the Together House").font(.pixel(16, .heavy)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 8) {
                    rule("globe.europe.africa.fill", "Everyone here is a real person, somewhere in the world, right now.")
                    rule("figure.walk", "Tap the floor to walk. Tap a seat to work, eat or relax. Tap yourself to emote.")
                    rule("text.bubble.fill", "Say hi with one-tap messages. No typing to each other and no private chat.")
                    rule("heart.fill", "Be kind. Rude names are blocked, and you can hide or report anyone by tapping them.")
                }
                HStack(spacing: 4) {
                    Text("By coming in you agree to the")
                    Button("Terms of Use") { openURL(URL(string: "https://manraisingh.github.io/swiftui-productivity-app/terms.html")!) }
                        .underline()
                }
                .font(.pixel(10, .semibold))
                .foregroundStyle(Theme.muted)
                Button("Let's go") { rulesSeen = true }
                    .buttonStyle(PixelButtonStyle(fill: Color(hex: 0xF7B7CF)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18)
            .frame(maxWidth: 420)
            .pixelBox(Theme.cream)
            .padding(24)
        }
    }

    private func rule(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xE0708A)).frame(width: 18)
            Text(text).font(.pixel(11, .semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
