import SwiftUI
import WidgetKit

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
    @State private var reminders = TogetherReminders.shared
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
        /// Walk to the counter, Rosie bakes it, then it's yours to carry to any free table.
        enum Step: Equatable { case walking, preparing(Date), ready }
        let food: Int
        var step: Step
    }
    @FocusState private var typing: Bool
    /// What's highlighted on Rosie's menu before you order.
    @State private var picking = 0
    /// The shared session you're in, or saving a seat for.
    @State private var joinedSlot: TogetherSchedule.Slot?
    /// When the last shared session you were in ended, for the little party.
    @State private var partyAt: Date?
    /// The little "you did it" card after a shared session, with how many people you focused with.
    @State private var result: SessionResult?

    struct SessionResult: Equatable {
        let people: Int
        let minutes: Int
        let total: Int
    }

    enum Tray { case react, menu }

    var body: some View {
        GeometryReader { geo in
            let bar: CGFloat = hall.joined ? 150 : 0
            let topRoom: CGFloat = 50
            let s = max(0.5, min(geo.size.width / CGFloat(TogetherRoom.width), max(geo.size.height - bar - topRoom, 1) / CGFloat(TogetherRoom.height)))
            let oy = Int((topRoom / s).rounded())
            let cols = Int(max(geo.size.width, 1) / s) + 1
            let rows = Int(max(geo.size.height, 1) / s) + 1
            let ox = (cols - TogetherRoom.width) / 2

            TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let scene = people(now: now)
                let drawn = scene.map(\.drawn)
                let quiet = TogetherSchedule.slot(at: timeline.date).focusing(at: timeline.date)
                let party = partyAge(at: timeline.date)
                let busy = rosieBusy(scene)
                let petted = Date().timeIntervalSince(catPetted) < 2.5
                ZStack(alignment: .topLeading) {
                    let phase = store.phase, weather = store.weather
                    PixelCanvas(cols: cols, rows: rows, s: s, frame: now) { p in
                        TogetherRenderer.draw(
                            p, t: now, cols: cols, rows: rows, ox: ox, oy: oy,
                            phase: phase, weather: weather, people: drawn,
                            catHeart: petted, rosieBusy: busy, quiet: quiet, party: party
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        tap(CGPoint(x: value.location.x / s - Double(ox), y: value.location.y / s - Double(oy)), scene: scene)
                    })

                    ForEach(scene, id: \.id) { item in
                        let x = (CGFloat(ox) + item.drawn.centerX) * s
                        let top = (item.drawn.headTop + Double(oy)) * s
                        // Desks sit close together, so seated workers show just the first word of their name.
                        nameTag(item.drawn.seat?.kind == .work ? String(item.name.split(separator: " ").first ?? Substring(item.name)) : item.name, detail: item.crowned ? "×\(item.visitor.row)" : item.detail, mine: item.mine, crowned: item.crowned)
                            .position(x: x, y: top - 3 * s)
                            .zIndex(item.crowned ? 2 : (item.mine ? 1 : 0))
                        if let line = item.say {
                            SpeechBubble(text: line, size: 10)
                                .fixedSize()
                                .position(x: min(max(x, 70), geo.size.width - 70), y: top - 9 * s - 16)
                                .allowsHitTesting(false)
                        }
                    }
                    if TogetherSchedule.slot(at: timeline.date).focusing(at: timeline.date) {
                        Text("Shh… focusing")
                            .font(.pixel(9, .heavy))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .pixelBox(Color(hex: 0xFFE38A), shadow: 1)
                            .position(x: (CGFloat(ox) + 64) * s, y: CGFloat(TogetherRoom.wallBottom + 8 + oy) * s)
                            .allowsHitTesting(false)
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
        #if DEBUG
        .overlay { if ProcessInfo.processInfo.arguments.contains("-hallShareCard") { SessionShareCard(people: 9, minutes: 25, total: 3, look: look, name: savedName) } }
        #endif
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: lastBubble)
        .onAppear {
            if NameRules.problem(savedName) != nil || savedName.isEmpty { savedName = CozyNames.random(); look = Int.random(in: 0..<HallLooks.all.count) }
            draft = savedName
            hall.open()
            syncStatus()
            rosieAt = .now
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-hallJoin") && !hall.joined { comeIn() }
            if args.contains("-hallMenu") { Task { try? await Task.sleep(for: .seconds(2)); picking = 4; tray = .menu } }
            if args.contains("-hallReady") { order = Order(food: 4, step: .ready) }
            if args.contains("-hallResult") { result = SessionResult(people: 9, minutes: 25, total: 3); partyAt = .now }
            if args.contains("-hallSession") { Task { try? await Task.sleep(for: .seconds(1.5)); joinSession() } }
            if args.contains("-hallParty") { Task { while !Task.isCancelled { partyAt = .now; try? await Task.sleep(for: .seconds(5)) } } }
            #endif
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
        .onChange(of: hall.visible.count) {
            TogetherHouseInfo.save(count: hall.visible.count + (hall.joined ? 1 : 0))
            WidgetCenter.shared.reloadTimelines(ofKind: "TogetherWidget")
        }
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

    private func partyAge(at date: Date) -> Double? {
        guard let partyAt else { return nil }
        let age = date.timeIntervalSince(partyAt)
        return age < 4.5 ? age : nil
    }

    /// Rosie looks busy while someone is waiting at the counter for their order.
    private func rosieBusy(_ scene: [Item]) -> Bool {
        scene.contains { item in
            let d = item.drawn
            guard !d.walking, d.seat == nil, item.visitor.food >= 0 else { return false }
            guard abs(d.point.x - TogetherRoom.orderSpot.x) < 3, abs(d.point.y - TogetherRoom.orderSpot.y) < 1 else { return false }
            return item.mine ? order != nil : true
        }
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
        var crowned = false
    }

    /// Who wears the crown: the most shared sessions in a row, at least two.
    private var crownID: String? {
        var all = hall.visible
        if let me = hall.me { all.append(me) }
        guard let top = all.max(by: { ($0.row, $1.id) < ($1.row, $0.id) }), top.row >= 2 else { return nil }
        return top.id
    }

    private var crownHolder: HallVisitor? {
        guard let id = crownID else { return nil }
        return id == hall.me?.id ? hall.me : hall.visible.first { $0.id == id }
    }

    private func people(now: Double) -> [Item] {
        var list = Array(hall.visible.prefix(24))
        if let me = hall.me { list.append(me) }
        var taken: Set<String> = []
        let crown = crownID
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
            // Quiet hours: nobody at a desk pops bubbles while the session runs.
            let hushed = seat?.kind == .work && TogetherSchedule.slot(at: Date()).focusing(at: Date())
            let sayIndex = hushed ? nil : motion.say(v, now: now)
            let emote = sayIndex == nil && !hushed ? motion.emote(v, now: now) : nil
            let seed = v.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
            let heading = TogetherRoom.spot(v.spot)
            let drawn = TogetherRenderer.Person(
                look: v.look, point: place.point, walking: place.walking, left: place.left, seat: seat,
                food: v.food, carrying: seat == nil && heading?.kind == .eat,
                status: v.status, emote: emote?.0, emoteAge: emote?.1 ?? 0,
                seatedFor: motion.seatedFor(v.id, key: seat.map { "\($0.id)-\(v.food)" }, now: now), seed: seed
            )
            let line = sayIndex.flatMap { TogetherEmote.phrases.indices.contains($0) ? TogetherEmote.phrases[$0] : nil }
            return Item(id: v.id, name: mine ? savedName : v.name, detail: detail(v), mine: mine, say: line, drawn: drawn, visitor: v,
                        crowned: v.id == crown)
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
            withAnimation(.snappy) { tray = tray == .react ? nil : .react }
            return
        }
        if TogetherRoom.counter.contains(g) { openMenu(); return }
        if let spot = TogetherRoom.spots.first(where: { $0.hit.contains(g) }) {
            if spot.kind == .eat {
                // Carrying something? This is your table. Otherwise, the menu first.
                if let ready = order, ready.step == .ready {
                    order = nil
                    sit(spot, food: ready.food)
                } else {
                    openMenu()
                }
                return
            }
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
    private func tickSession() {
        let now = Date()
        hall.setRow(store.togetherRow)
        guard let slot = joinedSlot else { refreshLiveCount(); return }
        if store.activeFocus == nil && now >= slot.start && now < slot.focusEnd && myKind == .work {
            startSession(slot)
        }
        refreshLiveCount()
        if now >= slot.focusEnd {
            joinedSlot = nil
            // Only party if you were actually focusing in this session.
            if store.justFinished?.title == LiveFocus.togetherTitle {
                partyAt = now
                withAnimation(.snappy) {
                    result = SessionResult(people: max(1, lastCount), minutes: store.justFinished?.minutes ?? TogetherSchedule.focusMinutes,
                                           total: store.togetherSessions)
                }
                SoundFX.shared.play(.star, volume: 0.7)
                rosie(["Session done! Treats all round 🍪", "Everyone did it! Fresh cookies!", "Lovely work, all of you!"].randomElement()!)
            }
        }
    }

    private func startSession(_ slot: TogetherSchedule.Slot) {
        let left = slot.focusEnd.timeIntervalSinceNow
        guard left > 30 else { return }
        lastCount = 1
        LiveFocus.togetherPeople = max(1, sessionCount(slot) + 1)
        result = nil
        store.startFocus(title: LiveFocus.togetherTitle, drink: .espresso, letterID: nil,
                         minutes: Int((left / 60).rounded(.up)), endingAt: slot.focusEnd)
        syncStatus()
    }

    /// Join the session that's running, or save a desk for the next one.
    private func joinSession() {
        let now = Date()
        let slot = TogetherSchedule.upcoming(after: now, includeRunning: true)
        joinedSlot = slot
        order = nil
        if myKind != .work { go(.work) }
        if slot.focusing(at: now) {
            if store.activeFocus != nil { store.cancelFocusQuietly() }
            startSession(slot)
            rosie("Pull up a chair, the session's on!")
        } else {
            rosie("Seat saved! We start at \(TogetherSchedule.label(slot.start)).")
        }
        SoundFX.shared.play(.open, volume: 0.6)
    }

    /// The head count during your last session, remembered for the result card.
    @State private var lastCount = 1

    /// Keeps the Live Activity and Dynamic Island showing how many people are focusing with you.
    private func refreshLiveCount() {
        let slot = TogetherSchedule.upcoming(after: .now, includeRunning: true)
        guard slot.focusing(at: .now), let f = store.activeFocus, f.title == LiveFocus.togetherTitle else { return }
        let n = sessionCount(slot)
        lastCount = max(lastCount, n)
        if n != LiveFocus.togetherPeople {
            LiveFocus.togetherPeople = n
            LiveFocus.sync(f)
        }
    }

    /// How many people are in the session that's running now (including you).
    private func sessionCount(_ slot: TogetherSchedule.Slot) -> Int {
        let others = hall.visible.filter { $0.status == .focus && abs(($0.until ?? .distantPast).timeIntervalSince(slot.focusEnd)) < 120 }.count
        let mine = store.activeFocus.map { abs($0.end.timeIntervalSince(slot.focusEnd)) < 120 } ?? false
        return others + (mine ? 1 : 0)
    }

    private func tickOrder() {
        tickSession()
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
                current.step = .ready
                withAnimation(.snappy) { order = current }
                rosie(["Here you go, dear!", "Fresh from the oven!", "All yours. Find a cozy table!"].randomElement()!)
                SoundFX.shared.play(.deliver, volume: 0.6)
            }
        case .ready:
            break
        }
    }

    private func openMenu() {
        if let order, order.step != .ready { return }
        withAnimation(.snappy) { tray = .menu }
    }

    /// Carry your snack to the nearest free café table.
    private func sitWithSnack() {
        guard let ready = order, ready.step == .ready else { return }
        order = nil
        go(.eat, food: ready.food)
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

    private func nameTag(_ name: String, detail: String?, mine: Bool, crowned: Bool = false) -> some View {
        HStack(spacing: 3) {
            if crowned { SpriteView(sprite: Self.crown, pixel: 1.5) }
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
        let live: Bool = { if case .ready = hall.phase { return true }; return false }()
        return HStack(spacing: 0) {
            Text("TOGETHER HOUSE")
                .font(.pixel(13, .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Self.pink)
            Rectangle().fill(Theme.ink).frame(width: 2)
            HStack(spacing: 5) {
                Rectangle()
                    .fill(live ? Color(hex: 0x6CC28A) : Theme.muted)
                    .frame(width: 6, height: 6)
                Group {
                    switch hall.phase {
                    case .ready, .idle: Text(n == 0 ? "just the cat" : "\(n) here")
                    case .opening: Text("opening…")
                    case .offline: Text("offline")
                    }
                }
                .font(.pixel(11, .heavy))
                .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 8)
            .background(Theme.card)
            Rectangle().fill(Theme.ink).frame(width: 2)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let slot = TogetherSchedule.upcoming(after: tl.date, includeRunning: true)
                let on = slot.focusing(at: tl.date)
                Text(on ? "FOCUS \(FocusFormat.clock(slot.focusEnd.timeIntervalSince(tl.date)))" : "NEXT \(TogetherSchedule.label(slot.start))")
                    .font(.pixel(11, .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(on ? Color(hex: 0xFFE38A) : Theme.cream)
            }
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
        .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
        .padding(.leading, 14)
        .padding(.top, 8)
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

    private static let pink = Color(hex: 0xF7B7CF)

    /// A little gold crown for whoever has stayed the longest.
    static let crown = Sprite([
        "k.k.k.k",
        "kykykyk",
        "kyyryyk",
        "kyyyyyk",
        "kkkkkkk",
    ], ["k": Color(hex: 0x2B2233), "y": Color(hex: 0xFFD54A), "r": Color(hex: 0xF06A86)])
    private static let rose = Color(hex: 0xC2577A)

    /// Like the café: one card that says what's happening right now, and a small bar for moving around.
    private var controls: some View {
        VStack(spacing: 8) {
            card
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(cardKey)
            HStack(spacing: 6) {
                barButton("laptopcomputer", "Work", on: myKind == .work) { go(.work) }
                barButton("fork.knife", "Snack", on: tray == .menu || myKind == .eat) { tray == .menu ? close() : openMenu() }
                barButton("sofa.fill", "Relax", on: myKind == .relax) { go(.relax) }
                barButton("face.smiling.inverse", "React", on: tray == .react) { withAnimation(.snappy) { tray = tray == .react ? nil : .react } }
            }
        }
        .animation(.snappy, value: cardKey)
    }

    private var myKind: TogetherRoom.Kind? { TogetherRoom.spot(hall.me?.spot ?? "")?.kind }

    /// Changes whenever the card should swap, so it slides instead of jumping.
    private var cardKey: String {
        if result != nil && tray == nil { return "result" }
        if let tray { return "tray-\(tray)" }
        if let order {
            switch order.step {
            case .walking, .preparing: return "baking"
            case .ready: return "ready"
            }
        }
        return "at-\(myKind?.rawValue ?? "floor")-\(store.activeFocus != nil)-\(joinedSlot != nil)"
    }

    private func close() { withAnimation(.snappy) { tray = nil } }

    @ViewBuilder private var card: some View {
        if let result, tray == nil {
            resultCard(result)
        } else if tray == .menu {
            menuCard
        } else if tray == .react {
            reactCard
        } else if let order {
            let food = TogetherFood.item(order.food)
            if order.step == .ready {
                hint(food.sprite, "Your \(food.name.lowercased()) is ready", "Tap a free café table to sit and enjoy it.",
                     button: "Sit anywhere", action: sitWithSnack)
            } else {
                hint(Sprites.rosie, "Rosie is making your \(food.name.lowercased())…", food.blurb + ". Just a moment!") {
                    BakingDots().frame(width: 34)
                }
            }
        } else {
            switch myKind {
            case .work: deskCard
            case .eat:
                let food = TogetherFood.item(hall.me?.food ?? 0)
                hint(food.sprite, "Enjoying your \(food.name.lowercased())", "Take your time. Rosie's always baking.",
                     button: "Back to work") { go(.work) }
            case .relax:
                hint(Sprites.sleepyCat, "The cozy corner", "Rest your eyes for a bit. The cat approves.",
                     button: "Back to work") { go(.work) }
            case nil:
                sessionCard
            }
        }
    }

    /// The café-style card: a sprite, a line or two, and at most one button.
    private func hint<Accessory: View>(_ sprite: Sprite, _ title: String, _ detail: String, button: String? = nil,
                                        action: (() -> Void)? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) -> some View {
        hintCard(sprite, title, detail, button: button, action: action, accessory: accessory)
    }

    /// Same card, with the accessory given as the trailing closure (no button).
    private func hint<Accessory: View>(_ sprite: Sprite, _ title: String, _ detail: String,
                                        @ViewBuilder trailing accessory: () -> Accessory) -> some View {
        hintCard(sprite, title, detail, button: nil, action: nil, accessory: accessory)
    }

    private func hintCard<Accessory: View>(_ sprite: Sprite, _ title: String, _ detail: String, button: String?,
                                            action: (() -> Void)?, accessory: () -> Accessory) -> some View {
        HStack(spacing: 12) {
            SpriteView(sprite: sprite, pixel: 2.5)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.pixel(14, .heavy)).foregroundStyle(Theme.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            accessory()
            if let button, let action {
                Button(button, action: action)
                    .buttonStyle(PixelButtonStyle(fill: Self.pink, hPad: 12))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(12)
        .pixelBox(Theme.card)
    }

    /// Rosie's menu, ordered the way you order at Bea's: pick, then confirm.
    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SpriteView(sprite: Sprites.rosie, pixel: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WHAT CAN I GET YOU?").font(.pixel(11, .heavy)).foregroundStyle(Theme.ink)
                    Text("Everything's on the house ♡").font(.pixel(9, .bold)).foregroundStyle(Self.rose)
                }
                Spacer()
                Button("Not now", action: close)
                    .font(.pixel(11, .heavy))
                    .foregroundStyle(Theme.muted)
                    .frame(minHeight: 32)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(TogetherFood.menu.indices, id: \.self) { i in
                    let item = TogetherFood.menu[i]
                    let on = picking == i
                    Button { picking = i } label: {
                        VStack(spacing: 3) {
                            SpriteView(sprite: item.sprite, pixel: 3)
                                .frame(height: 30)
                            Text(item.name).font(.pixel(10, .heavy)).foregroundStyle(Theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .pixelBox(on ? Color(hex: 0xFFE1EC) : Theme.card, shadow: on ? 2 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button {
                close()
                orderFood(picking)
            } label: {
                Text("Order \(TogetherFood.item(picking).name.lowercased()) · \(TogetherFood.item(picking).blurb.lowercased())")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(fill: Self.pink))
        }
        .padding(12)
        .pixelBox(Theme.card)
    }

    /// Emotes and one-tap lines in one place.
    private var reactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                ForEach(TogetherEmote.all.indices, id: \.self) { i in
                    Button { send(emote: i) } label: {
                        SpriteView(sprite: TogetherEmote.all[i], pixel: 3)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .pixelBox(Theme.card, shadow: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TogetherEmote.names[i])
                }
            }
            FlowRow(spacing: 5) {
                ForEach(TogetherEmote.phrases.indices, id: \.self) { i in
                    Button { send(say: i) } label: {
                        Text(TogetherEmote.phrases[i])
                            .font(.pixel(11, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .pixelBox(Color(hex: 0xFFF6EA), shadow: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .pixelBox(Theme.card)
    }

    /// Your run of back-to-back sessions, and what it takes to wear the crown.
    @ViewBuilder private var streakLine: some View {
        let row = store.togetherRow + 1
        let holder = crownHolder
        HStack(spacing: 5) {
            if holder?.id == hall.me?.id && holder != nil {
                SpriteView(sprite: Self.crown, pixel: 1.5)
                Text("You wear the crown · \(row) in a row").font(.pixel(10, .heavy)).foregroundStyle(Self.rose)
            } else if let holder, holder.row + 1 > row {
                SpriteView(sprite: Self.crown, pixel: 1.5)
                Text("\(holder.row + 1 - row) more in a row to take the crown from \(holder.name)")
                    .font(.pixel(10, .heavy)).foregroundStyle(Self.rose).lineLimit(2)
            } else {
                Text("🔥 Session \(row) in a row · stay for the next to keep it going")
                    .font(.pixel(10, .heavy)).foregroundStyle(Self.rose).lineLimit(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The next few session start times, tap one to get a reminder.
    private func bookingChips(from slot: TogetherSchedule.Slot) -> some View {
        let starts = (0..<4).map { slot.start.addingTimeInterval(Double($0) * TogetherSchedule.length) }
        return HStack(spacing: 5) {
            Image(systemName: "bell.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
            ForEach(starts, id: \.self) { start in
                let on = reminders.isBooked(start)
                Button {
                    reminders.toggle(start)
                    SoundFX.shared.play(on ? .close : .open, volume: 0.6)
                } label: {
                    Text(TogetherSchedule.label(start))
                        .font(.pixel(10, .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .pixelBox(on ? Self.pink : Theme.cream, shadow: on ? 2 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? "Reminder on for \(TogetherSchedule.label(start))" : "Remind me at \(TogetherSchedule.label(start))")
            }
        }
    }

    /// The hook of the house: a shared session at every :00 and :30.
    private var sessionCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let slot = TogetherSchedule.upcoming(after: tl.date, includeRunning: true)
            let running = slot.focusing(at: tl.date)
            let n = sessionCount(slot)
            HStack(spacing: 12) {
                SessionClock(running: running, progress: running ? 1 - slot.focusEnd.timeIntervalSince(tl.date) / TimeInterval(TogetherSchedule.focusMinutes * 60) : 0)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(running ? "Focus session · \(FocusFormat.clock(slot.focusEnd.timeIntervalSince(tl.date))) left"
                                 : "Next session at \(TogetherSchedule.label(slot.start))")
                        .font(.pixel(14, .heavy)).foregroundStyle(Theme.ink).monospacedDigit()
                    Text(running ? (n > 0 ? "\(count(n, "person", plural: "people")) focusing right now. Hop in." : "Be the first at the desks.")
                                 : "Starts in \(FocusFormat.clock(slot.start.timeIntervalSince(tl.date))). 25 min together, then a break.")
                        .font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(running ? "Join" : "Save a seat", action: joinSession)
                    .buttonStyle(PixelButtonStyle(fill: Self.pink, hPad: 12))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(12)
            .overlay(alignment: .bottom) { EmptyView() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if let holder = crownHolder {
                        HStack(spacing: 4) {
                            SpriteView(sprite: Self.crown, pixel: 1.5)
                            Text("\(holder.name) has the crown · \(holder.row) in a row")
                                .font(.pixel(9, .heavy)).foregroundStyle(Self.rose)
                        }
                    }
                    bookingChips(from: running ? slot.next : slot)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            .pixelBox(Theme.card)
        }
    }

    /// Your desk: in a shared session, waiting for one, or free.
    @ViewBuilder private var deskCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let slot = TogetherSchedule.upcoming(after: tl.date, includeRunning: true)
            if let f = store.activeFocus {
                let left = f.end.timeIntervalSince(tl.date)
                let together = abs(f.end.timeIntervalSince(slot.focusEnd)) < 120
                // Together, the bar tracks the shared 25 minutes, so everyone's bar matches.
                let total = together ? slot.focusEnd.timeIntervalSince(slot.start) : f.duration
                let fill = max(0, min(1, left / total))
                let others = max(0, sessionCount(slot) - 1)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(f.onBreak ? "On a break" : (together ? "Focusing together" : "Focusing"))
                            .font(.pixel(14, .heavy)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(FocusFormat.clock(left)).font(.pixel(16, .heavy)).foregroundStyle(Theme.ink).monospacedDigit()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.cream)
                            Rectangle().fill(Color(hex: 0xA9C8F5)).frame(width: g.size.width * (1 - fill))
                        }
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    }
                    .frame(height: 10)
                    Text(together ? (others > 0 ? "\(count(others, "person", plural: "people")) working with you. Rosie's baking for the break." : "You're holding the room. Others can join any time.")
                                  : "Everyone here can see you working.")
                        .font(.pixel(10, .medium)).foregroundStyle(Theme.muted)
                    if together { streakLine }
                }
                .padding(12)
                .pixelBox(Theme.card)
            } else if let waiting = joinedSlot, tl.date < waiting.start {
                hint(HallLooks.sprite(look), "Your seat is saved", "The session starts at \(TogetherSchedule.label(waiting.start)). That's in \(FocusFormat.clock(waiting.start.timeIntervalSince(tl.date))).") {
                    BakingDots().frame(width: 34)
                }
            } else {
                hint(HallLooks.sprite(look), "Your desk",
                     slot.focusing(at: tl.date) ? "A session is on. Join and finish with everyone." : "The next session starts at \(TogetherSchedule.label(slot.start)).",
                     button: slot.focusing(at: tl.date) ? "Join" : "Save a seat", action: joinSession)
            }
        }
    }

    private func barButton(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(label).font(.pixel(10, .heavy))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(on ? Self.pink : Theme.cream)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(x: on ? 1 : 2, y: on ? 1 : 2))
            .offset(x: on ? 1 : 0, y: on ? 1 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Joining

    /// One tap to come in. You're a cozy anonymous name; no typing, no account.
    private var joinCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let slot = TogetherSchedule.upcoming(after: tl.date, includeRunning: true)
            let running = slot.focusing(at: tl.date)
            VStack(alignment: .leading, spacing: 12) {
                if case .offline(let why) = hall.phase {
                    HStack {
                        Text(why).font(.pixel(11, .semibold)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Try again") { hall.retry() }.font(.pixel(11, .heavy)).foregroundStyle(Theme.ink).underline()
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(running ? "A session is on · \(FocusFormat.clock(slot.focusEnd.timeIntervalSince(tl.date))) left"
                                 : "Next session at \(TogetherSchedule.label(slot.start))")
                        .font(.pixel(15, .heavy)).foregroundStyle(Theme.ink).monospacedDigit()
                    Text("Focus alongside real people, anywhere in the world. Everyone's anonymous. Finish together and Rosie bakes you double treats.")
                        .font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    SpriteView(sprite: HallLooks.sprite(look), pixel: 2.5)
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YOU'LL BE").font(.pixel(8, .heavy)).foregroundStyle(Theme.muted)
                        Text(savedName).font(.pixel(14, .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        savedName = CozyNames.random()
                        look = Int.random(in: 0..<HallLooks.all.count)
                        SoundFX.shared.play(.pop, volume: 0.6)
                    } label: {
                        Image(systemName: "dice.fill").font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 40)
                            .pixelBox(Theme.cream, shadow: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New name and look")
                }
                Button(running ? "Come in and join" : "Come in", action: comeIn)
                    .buttonStyle(PixelButtonStyle(fill: Self.pink))
                    .frame(maxWidth: .infinity)
                if !hall.canJoin {
                    Text("You're not signed in to iCloud, so others won't see you. You can still focus with everyone.")
                        .font(.pixel(9, .semibold)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelBox(Theme.cream)
        }
    }

    /// After a shared session: what you did, the bonus, and a card to share.
    private func resultCard(_ r: SessionResult) -> some View {
        let image = SessionShareCard(people: r.people, minutes: r.minutes, total: r.total, look: look, name: savedName).snapshot()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("You did it! 🍪🍪").font(.pixel(15, .heavy)).foregroundStyle(Theme.ink)
                Text(r.people > 1 ? "\(r.minutes) min with \(r.people - 1) \(r.people == 2 ? "other" : "others"). Rosie baked you a bonus treat."
                                  : "\(r.minutes) min of focus. Rosie baked you a bonus treat.")
                    .font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Session #\(r.total) together").font(.pixel(9, .heavy)).foregroundStyle(Self.rose)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Focused together", image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up").font(.pixel(11, .heavy))
                    }
                    .buttonStyle(PixelButtonStyle(fill: Self.pink, hPad: 10))
                }
                Button("Done") { withAnimation(.snappy) { result = nil } }
                    .font(.pixel(11, .heavy)).foregroundStyle(Theme.muted)
            }
            .fixedSize()
        }
        .padding(12)
        .pixelBox(Theme.card)
    }

    private func comeIn() {
        if NameRules.problem(savedName) != nil { savedName = CozyNames.random() }
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

/// Three little pixel dots that hop while Rosie bakes.
struct BakingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(Color(hex: 0xC2577A))
                        .frame(width: 6, height: 6)
                        .offset(y: -abs(sin(t * 6 - Double(i) * 0.7)) * 5)
                }
            }
            .frame(height: 16)
        }
        .accessibilityHidden(true)
    }
}

/// A tiny pixel wall clock: a pie that fills up while a session runs, or two hands while you wait.
struct SessionClock: View {
    let running: Bool
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let n = 16
            let s = min(size.width, size.height) / CGFloat(n)
            let p = Painter(ctx: ctx, s: s)
            let ink = Theme.ink
            let c = 7.5
            for y in 0..<n {
                for x in 0..<n {
                    let dx = Double(x) - c, dy = Double(y) - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d > 7.6 { continue }
                    if d > 6.4 { p.dot(x, y, ink); continue }
                    var a = atan2(dx, -dy) / (2 * .pi)
                    if a < 0 { a += 1 }
                    let filled = running && a <= progress
                    p.dot(x, y, filled ? Color(hex: 0xF7B7CF) : Theme.cream)
                }
            }
            if !running {
                p.rect(7, 3, 2, 5, ink)
                p.rect(8, 7, 4, 2, ink)
            } else {
                p.rect(7, 7, 2, 2, ink)
            }
            for (x, y) in [(7, 1), (7, 13), (1, 7), (13, 7)] { p.rect(x, y, 2, 2, Color(hex: 0xC2577A)) }
        }
        .accessibilityHidden(true)
    }
}

/// The square card people share after a Together House session.
struct SessionShareCard: View {
    let people: Int
    let minutes: Int
    let total: Int
    let look: Int
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            TogetherScene(running: true, progress: 1, grid: 64)
                .frame(width: 300, height: 190)
                .framed()
            VStack(spacing: 4) {
                Text(people > 1 ? "I focused \(minutes) min with \(people - 1) strangers" : "I focused \(minutes) min in the Together House")
                    .font(.pixel(17, .heavy)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text("as \(name) · session #\(total)").font(.pixel(11, .bold)).foregroundStyle(Color(hex: 0xC2577A))
            }
            HStack(spacing: 6) {
                SpriteView(sprite: Sprites.rosie, pixel: 2)
                Text("Workdoro · free on the App Store").font(.pixel(11, .heavy)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .pixelBox(Color(hex: 0xFFE38A), shadow: 2)
        }
        .padding(20)
        .frame(width: 360, height: 360)
        .background(Color(hex: 0xFFE1EC))
        .environment(\.colorScheme, .light)
    }

    @MainActor func snapshot() -> UIImage? {
        let r = ImageRenderer(content: self)
        r.scale = 3
        return r.uiImage
    }
}
