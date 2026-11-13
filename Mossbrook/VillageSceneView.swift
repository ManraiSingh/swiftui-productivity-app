import SwiftUI

/// The village, drawn edge to edge. Width sets the pixel size; the bottom simply runs off-screen on shorter phones.
struct VillageSceneView: View {
    @Environment(VillageStore.self) private var store
    var onTap: (VillagerID) -> Void
    var onTapCafe: () -> Void
    var onMailbox: () -> Void
    var onTownHall: () -> Void
    var onStudyHall: () -> Void = {}
    /// True while another screen covers the town, so it stops animating where nobody can see it.
    var paused = false
    @State private var effects: [VillageEffect] = []

    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, 1) / CGFloat(VillageLayout.worldWidth)
            let townW = CGFloat(VillageLayout.width) * s
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let state = SceneState(store)
                let live = effects.filter { t - $0.start < 3.2 }
                ZStack(alignment: .topLeading) {
                // The whole world, woods and town, drawn into one small bitmap each frame and shown
                // as a single picture: far lighter for the phone than thousands of separate shapes.
                let woods = WildsCache.shared.image(for: state)
                let base = TownBaseCache.shared.image(for: state)
                PixelCanvas(cols: VillageLayout.worldWidth, rows: VillageLayout.worldHeight, s: s, k: 2, frame: t) { p in
                    if let woods { p.picture(woods, x: 0, y: 0, w: VillageLayout.worldWidth, h: VillageLayout.worldHeight) }
                    if state.phase == .night { VillageRenderer.wildsLive(p, t: t, state: state) }
                    let m = VillageLayout.margin, top = VillageLayout.topMargin
                    p.clipped(x: m, y: top, w: VillageLayout.width, h: VillageLayout.height) { p in
                        let town = p.shifted(dx: m, dy: top)
                        VillageRenderer.drawSky(town, t: t, state: state, effects: live)
                        if let base { town.picture(base, x: 0, y: 0, w: VillageLayout.width, h: VillageLayout.height) }
                        VillageRenderer.drawLive(town, t: t, state: state, effects: live)
                    }
                }
                .frame(width: geo.size.width, height: CGFloat(VillageLayout.worldHeight) * s)
                .allowsHitTesting(false)

                ZStack(alignment: .topLeading) {
                    Color.clear
                    .frame(width: townW, height: CGFloat(VillageLayout.height) * s)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        poke(CGPoint(x: value.location.x / s, y: value.location.y / s), phase: state.phase)
                    })
                    .accessibilityLabel("The village of Workdoro")

                    hotspot(x: 34, y: 124, w: 38, h: 32, s: s, label: "Go to Mo's library") { onTap(.mo) }
                    hotspot(x: 82, y: 124, w: 36, h: 32, s: s, label: "Go to Pip's post office") { onTap(.pip) }
                    hotspot(x: 80, y: 210, w: 40, h: 30, s: s, label: "Go to Bea's café", action: onTapCafe)
                    hotspot(x: 65, y: 134, w: 12, h: 14, s: s, label: store.hasDailyLetter ? "Open today's letter" : "Read today's letter again", sound: .page, action: onMailbox)
                    hotspot(x: 30, y: 210, w: 36, h: 32, s: s, label: "Go to Juniper's greenhouse") { onTap(.juniper) }
                    hotspot(x: 180, y: 124, w: 34, h: 32, s: s, label: "Go to Rosie's bakery") { onTap(.rosie) }
                    hotspot(x: 128, y: 104, w: 60, h: 70, s: s, label: "Visit the Old Oak for a town meeting", action: onTownHall)
                    hotspot(x: 196, y: 210, w: 40, h: 34, s: s, label: "Go to the Together House", action: onStudyHall)
                    hotspot(x: 161, y: 185, w: 16, h: 18, s: s, label: "Read the notice board: town meeting", action: onTownHall)

                    ForEach(VillagerID.allCases) { villager in
                        let pose = VillageLayout.pose(villager, t: t, state: state)
                        hotspot(x: pose.x, y: pose.y - 8, w: 20, h: 22, s: s, label: "Talk to \(villager.name)", sound: nil) {
                            if villager == .pip && store.bikeFixed { SoundFX.shared.play(.bikeBell) } else { SoundFX.shared.voice(of: villager) }
                            onTap(villager)
                        }
                    }

                    ForEach(live) { effect in
                        if case .quack(let duck) = effect.kind, t - effect.start < 1.4 {
                            let pos = VillageRenderer.duckPosition(duck, t: t)
                            SpeechBubble(text: "Quack!", size: 10)
                                .fixedSize()
                                .position(x: pos.x * s, y: (pos.y - 10) * s)
                                .allowsHitTesting(false)
                        }
                    }

if !state.touring {
                    let speaker = VillagerID.allCases[Int(t / 5) % VillagerID.allCases.count]
                    let pose = VillageLayout.pose(speaker, t: t, state: state)
                    SpeechBubble(text: Chatter.line(for: speaker, store, t: t))
                        .fixedSize()
                        .position(
                            x: min(max(pose.x * s, 85), townW - 85),
                            y: (pose.y - 22) * s
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: townW, height: CGFloat(VillageLayout.height) * s, alignment: .topLeading)
                .offset(x: CGFloat(VillageLayout.margin) * s, y: CGFloat(VillageLayout.topMargin) * s)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: effects.count)
    }

    private func hotspot(x: Double, y: Double, w: Double, h: Double, s: CGFloat, label: String, sound: SoundFX.Sound? = .open, action: @escaping () -> Void) -> some View {
        Button {
            if let sound { SoundFX.shared.play(sound) }
            action()
        } label: {
            Color.clear
                .frame(width: w * s, height: h * s)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .position(x: x * s, y: y * s)
    }

    /// Tapping the scenery: ducks quack, trees drop an apple, the night sky gives you a shooting star.
    private func poke(_ g: CGPoint, phase: DayPhase) {
        let now = Date().timeIntervalSinceReferenceDate
        effects.removeAll { now - $0.start > 3.2 }
        for i in 0..<2 {
            let d = VillageRenderer.duckPosition(i, t: now)
            if hypot(d.x - g.x, d.y - g.y) < 7 {
                effects.append(VillageEffect(kind: .quack(duck: i), start: now)); SoundFX.shared.play(.quack)
                return
            }
        }
        for (i, spot) in VillageRenderer.treeSpots.enumerated() {
            let rect = CGRect(x: Double(spot.0 - 1), y: Double(spot.1 - 1), width: 12, height: 15)
            if rect.contains(g) {
                effects.append(VillageEffect(kind: .shake(tree: i), start: now)); SoundFX.shared.play(.apple)
                return
            }
        }
        if g.y < 44 && phase == .night {
            effects.append(VillageEffect(kind: .star(x: g.x + 10, y: g.y - 4), start: now)); SoundFX.shared.play(.star)
        }
    }
}

/// A wooden signboard over a building, saying what you do there.
struct TownSign: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let x: Double
    let y: Double

    static let all: [TownSign] = [
        TownSign(id: "library", title: "LIBRARY", detail: "Notes & pages", symbol: "book.fill", x: 34, y: 106),
        TownSign(id: "post", title: "POST OFFICE", detail: "Tasks & reminders", symbol: "envelope.fill", x: 82, y: 109),
        TownSign(id: "oak", title: "OLD OAK", detail: "Town meeting", symbol: "tree.fill", x: 128, y: 112),
        TownSign(id: "bakery", title: "BAKERY", detail: "Treats & rewards", symbol: "birthday.cake.fill", x: 180, y: 110),
        TownSign(id: "greenhouse", title: "GREENHOUSE", detail: "Daily habits", symbol: "leaf.fill", x: 30, y: 191),
        TownSign(id: "cafe", title: "CAFÉ", detail: "Focus sessions", symbol: "cup.and.saucer.fill", x: 80, y: 193),
        TownSign(id: "together", title: "TOGETHER HOUSE", detail: "Hang out with the world", symbol: "globe.europe.africa.fill", x: 196, y: 181)
    ]
}

struct TownSignView: View {
    let sign: TownSign

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: sign.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFE38A))
            VStack(alignment: .leading, spacing: 0) {
                Text(sign.title)
                    .font(.pixel(9, .heavy))
                    .foregroundStyle(Color(hex: 0xFFF6E5))
                Text(sign.detail)
                    .font(.pixel(8, .semibold))
                    .foregroundStyle(Color(hex: 0xF2D9B5))
            }
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(hex: 0x7A4E3A))
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x9A6A4E)).frame(height: 1.5) }
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
        .background(Rectangle().fill(Color.black.opacity(0.25)).offset(x: 2, y: 2))
        .accessibilityElement(children: .combine)
    }
}

