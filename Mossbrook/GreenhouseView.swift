import SwiftUI
import UserNotifications

// MARK: - Greenhouse scene

enum GreenhouseRenderer {
    static let ink = VillageRenderer.ink
    static let W = 120
    static let columns: [Int] = [22, 60, 98]
    static let tables: [Int] = [100, 168]

    static func slot(_ i: Int) -> (x: Int, base: Int) {
        (columns[i % 3], tables[min(i / 3, 1)] + 6)
    }

    /// A long potting bench seen from slightly above.
    static func bench(_ p: Painter, top: Int) {
        let left = 3, right = W - 3
        let depth = 9
        for r in -1...depth {
            let inset = max(0, depth - 1 - max(r, 0))
            p.rect(left + inset - 1, top + r, right - left - 2 * inset + 2, 1, ink)
        }
        for r in 0..<depth {
            let inset = depth - 1 - r
            let shade = r % 3 == 0 ? Color(hex: 0xC4956A) : (r % 3 == 1 ? Color(hex: 0xB4855A) : Color(hex: 0xA87A4F))
            p.rect(left + inset, top + r, right - left - 2 * inset, 1, shade)
        }
        for x in stride(from: left + 12, to: right - 6, by: 17) { p.dot(x, top + 4, Color(hex: 0x8E6440)) }
        p.rect(left, top + depth, right - left, 4, Color(hex: 0x8A5C3A))
        p.rect(left, top + depth, right - left, 1, Color(hex: 0x9E6E48))
        p.rect(left - 1, top + depth + 4, right - left + 2, 1, ink)
        for x in [left + 2, W / 2 - 1, right - 5] {
            p.rect(x, top + depth + 5, 3, 11, ink)
            p.rect(x + 1, top + depth + 5, 1, 11, Color(hex: 0x7A5636))
        }
    }

    static func draw(_ p: Painter, t: Double, rows: Int, phase: DayPhase, habits: [Habit], watering: (id: UUID, start: Date)?, now: Date) {
        let sky: UInt32
        switch phase {
        case .day: sky = 0xCDEBEF
        case .dusk: sky = 0xF2C7A6
        case .night: sky = 0x2B3166
        }
        // Glass wall with the garden outside.
        p.rect(0, 0, W, rows, Color(hex: sky))
        if phase == .night {
            for i in 0..<16 { p.dot(noise(i, 3) % W, noise(i, 7) % 40, Color.white.opacity(0.8)) }
        } else {
            p.glow(96, 14, radius: 18, Color(hex: 0xFFF3B0), 0.5)
        }
        for x in stride(from: 0, to: W, by: 3) {
            let hgt = 6 + noise(x, 4) % 6
            p.rect(x, 92 - hgt, 3, hgt, Color(hex: phase == .night ? 0x2F4A35 : 0x8CC56C).opacity(0.75))
        }
        let frame = Color(hex: 0x5E7A50)
        for x in stride(from: 0, through: W, by: 20) { p.rect(x, 0, 2, 96, frame) }
        for y in [24, 50] { p.rect(0, y, W, 2, frame) }
        for i in 0..<6 {
            p.rect(i * 20 + 4, 3, 1, 18, Color.white.opacity(0.35))
            p.rect(i * 20 + 5, 28, 1, 16, Color.white.opacity(0.22))
        }
        // Hanging plants.
        for (i, x) in [12, 60, 108].enumerated() {
            p.rect(x, 0, 1, 9, ink)
            _ = PlantRenderer.pot(p, cx: x, base: 16, w: 10, h: 7)
            let g = PlantRenderer.greens(false)
            for v in 0..<5 {
                let a = .pi / 2 + (Double(v) - 2) * 0.35 + sin(t * 0.7 + Double(v + i)) * 0.05
                PlantRenderer.leaf(p, Double(x) + Double(v - 2) * 1.5, 11, angle: a, length: 6 + Double(noise(i, v) % 5), width: 1.8, shade: g, front: v % 2 == 0)
            }
        }
        // Fairy lights along the beam.
        let bulbs: [UInt32] = [0xFFD27A, 0xF49AC1, 0xFFE38A, 0xA6E1F0]
        for (i, x) in stride(from: 3, to: W, by: 7).enumerated() {
            let y = 26 + (i % 2)
            p.dot(x, y - 1, ink)
            p.glow(Double(x) + 0.5, Double(y) + 1, radius: 3.5, Color(hex: bulbs[i % 4]), phase == .day ? 0.3 : 0.7)
            p.rect(x, y, 1, 2, Color(hex: bulbs[i % 4]))
        }
        // Brick knee wall.
        p.rect(0, 94, W, 1, ink)
        for y in stride(from: 95, to: 112, by: 4) {
            p.rect(0, y, W, 4, Color(hex: 0xB86E4A))
            p.rect(0, y + 3, W, 1, Color(hex: 0x9A5A3A))
            for x in stride(from: (y / 4 % 2) * 5, to: W, by: 10) { p.rect(x, y, 1, 3, Color(hex: 0x9A5A3A)) }
        }
        // Tiled floor in perspective.
        p.rect(0, 112, W, rows - 112, Color(hex: 0xD9C4A0))
        p.rect(0, 112, W, 1, ink)
        var y = 112
        var step = 4
        var row = 0
        while y < rows {
            if row % 2 == 0 { p.rect(0, y + 1, W, step - 1, Color(hex: 0xCDB690)) }
            p.rect(0, y + step, W, 1, Color(hex: 0xB8A07A))
            y += step
            step += 2
            row += 1
        }
        for s in stride(from: -10, through: 10, by: 2) {
            for yy in stride(from: 113, to: rows, by: 2) {
                let x = 60 + Double(s) * 6 * Double(yy - 60) / 52
                if x >= 0 && x < Double(W) { p.dot(Int(x), yy, Color(hex: 0xC4AC86)) }
            }
        }
        // Sunbeams.
        if phase != .night {
            for start in [10, 46, 82] {
                for yy in stride(from: 0, to: rows, by: 2) {
                    p.rect(start + yy / 3, yy, 7, 2, Color(hex: 0xFFF3C0).opacity(0.09))
                }
            }
        }

        // Back bench and its plants, then the front bench in front of it.
        for (row, top) in tables.enumerated() {
            if row == 1 {
                // Juniper and her tools, on the floor between the benches.
                let fy = tables[0] + 40
                PlantRenderer.ellipse(p, 18, Double(fy) + 0.5, 9, 2, Color.black.opacity(0.15))
                VillageRenderer.box(p, 10, fy - 9, 14, 9, Color(hex: 0xC9A87A))
                p.rect(10, fy - 9, 14, 2, Color(hex: 0xB08F62))
                p.rect(14, fy - 6, 6, 3, Color(hex: 0x8A6A4A))
                p.rect(15, fy - 5, 4, 1, Color(hex: 0x6E8B5E))
                PlantRenderer.ellipse(p, 38, Double(fy) + 0.5, 6, 1.6, Color.black.opacity(0.15))
                VillageRenderer.box(p, 33, fy - 7, 9, 7, Color(hex: 0x4A6FA5))
                p.rect(34, fy - 6, 3, 5, Color(hex: 0x7A9AD0))
                p.rect(35, fy - 10, 5, 1, ink)
                p.rect(27, fy - 4, 6, 1, Color(hex: 0x4A6FA5))
                p.dot(26, fy - 5, Color(hex: 0x4A6FA5))
                PlantRenderer.ellipse(p, 96, Double(fy) + 0.5, 7, 1.8, Color.black.opacity(0.15))
                p.sprite(Sprites.juniper, x: 88, y: fy - 16 + (Int(t * 1.4) % 2 == 0 ? 0 : -1))
            }
            bench(p, top: top)
            for col in 0..<3 {
                let i = row * 3 + col
                let s = slot(i)
                if i < habits.count {
                    let habit = habits[i]
                    let done = habit.doneDays.contains(VillageStore.dayKey(now))
                    PlantRenderer.draw(
                        p, species: PlantSpecies(rawValue: habit.species % 6) ?? .sunflower,
                        stage: habit.stage, thirsty: !done, x: s.x, base: s.base, t: t, seed: i
                    )
                    if done {
                        let k = (t * 0.7 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1)
                        p.glow(Double(s.x + 9), Double(s.base - 18) - k * 8, radius: 2.5, Color(hex: 0xFFF3B0), 0.7 * (1 - k))
                    }
                } else {
                    PlantRenderer.ellipse(p, Double(s.x) + 2, Double(s.base), 10, 2.4, Color.black.opacity(0.1))
                    PlantRenderer.ellipse(p, Double(s.x), Double(s.base - 11), 9.5, 3.2, Color(hex: 0xC9774A).opacity(0.3))
                }
            }
        }

        // The watering can pours on the plant you just tapped.
        if let watering, let i = habits.firstIndex(where: { $0.id == watering.id }) {
            let age = now.timeIntervalSince(watering.start)
            if age < 1.6 {
                let s = slot(i)
                let cx = s.x + 8, cy = s.base - 40
                VillageRenderer.box(p, cx, cy, 9, 6, Color(hex: 0x4A6FA5))
                p.rect(cx + 1, cy, 3, 1, Color(hex: 0x7A9AD0))
                p.rect(cx + 2, cy - 3, 5, 1, ink)
                p.rect(cx - 5, cy + 4, 5, 1, Color(hex: 0x4A6FA5))
                p.dot(cx - 6, cy + 5, Color(hex: 0x4A6FA5))
                for d in 0..<8 {
                    let k = (age * 2 + Double(d) / 8).truncatingRemainder(dividingBy: 1)
                    p.dot(cx - 6 - d % 3, cy + 6 + Int(k * 24), Color(hex: 0x8FD3F5))
                }
            }
        }
    }
}

// MARK: - Greenhouse screen

struct GreenhouseView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var watering: (id: UUID, start: Date)?
    @State private var showAdd = false
    @State private var historyFor: UUID?
    @AppStorage("habitReminder") private var reminder = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: 0x2F4A35).ignoresSafeArea()
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let s = max(geo.size.width, 1) / CGFloat(GreenhouseRenderer.W)
                    let rows = Int(max(geo.size.height, 1) / s) + 2
                    TimelineView(.animation(minimumInterval: 1.0 / 15)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        ZStack(alignment: .topLeading) {
                            Canvas { ctx, _ in
                                GreenhouseRenderer.draw(
                                    Painter(ctx: ctx, s: s), t: t, rows: rows, phase: store.phase,
                                    habits: store.habits, watering: watering, now: tl.date
                                )
                            }
                            slots(s: s)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)

                bottomCard
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
            .accessibilityLabel("Back to the village")
            .padding(.trailing, 18)
            .padding(.top, 8)
        }
        .villageOverlays()
        // The glass shows the real sky: light text on it at night, dark text by day.
        .environment(\.colorScheme, .light)
        .preferredColorScheme(store.phase == .night ? .dark : .light)
        .sheet(isPresented: $showAdd) { PlantHabitSheet() }
        .sheet(item: Binding(get: { historyFor.map(IDBox.init) }, set: { historyFor = $0?.id })) { box in
            HabitHistoryView(habitID: box.id)
        }
        .sensoryFeedback(.success, trigger: store.habitsDoneToday)
        .onChange(of: reminder) { scheduleReminder() }
    }

    @ViewBuilder
    private func slots(s: CGFloat) -> some View {
        ForEach(0..<VillageStore.maxHabits, id: \.self) { i in
            let slot = GreenhouseRenderer.slot(i)
            if i < store.habits.count {
                let habit = store.habits[i]
                let done = habit.doneDays.contains(VillageStore.dayKey())
                Button {
                    water(habit)
                } label: {
                    Color.clear.frame(width: 34 * s, height: 50 * s).contentShape(Rectangle())
                }
                .contextMenu {
                    Button { historyFor = habit.id } label: { Label("History", systemImage: "calendar") }
                    if done {
                        Button { store.toggleHabit(habit) } label: { Label("Undo today", systemImage: "arrow.uturn.backward") }
                    }
                    Button(role: .destructive) { store.deleteHabit(habit) } label: { Label("Remove plant", systemImage: "trash") }
                }
                .accessibilityLabel("\(habit.name), \(Habit.stageNames[habit.stage]), \(done ? "watered today" : "needs water")")
                .position(x: CGFloat(slot.x) * s, y: CGFloat(slot.base - 24) * s)

                Button { historyFor = habit.id } label: {
                    PlantTag(habit: habit, done: done, streak: store.habitStreak(habit))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(habit.name) history")
                .position(x: CGFloat(slot.x) * s, y: CGFloat(slot.base + 6) * s)
            } else if i == store.habits.count {
                Button { showAdd = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 14, weight: .heavy))
                        Text("Plant").font(.pixel(10, .heavy))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(width: 20 * s, height: 12 * s)
                    .pixelBox(Theme.card.opacity(0.92), shadow: 2)
                }
                .accessibilityLabel("Plant a new habit")
                .position(x: CGFloat(slot.x) * s, y: CGFloat(slot.base - 16) * s)
            }
        }
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SpriteView(sprite: Sprites.juniper, pixel: 2)
                Text("WATERED TODAY")
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(store.habitsDoneToday)/\(store.habits.count)")
                    .font(.pixel(12, .heavy))
                    .foregroundStyle(Theme.leaf)
            }
            PixelProgress(value: store.habitsDoneToday, total: max(store.habits.count, 1), color: Theme.leaf, cellHeight: 10)
            Text(store.habits.isEmpty
                 ? "Plant a habit and it becomes a real plant. Water it each day you do it."
                 : "Tap a plant to water it. Plants grow with every day you water them, and missing a day never undoes their growth.")
                .font(.pixel(11, .medium))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    showAdd = true
                } label: {
                    Label("Plant a habit", systemImage: "leaf.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.leaf, foreground: Theme.cream))
                .disabled(store.habits.count >= VillageStore.maxHabits)
                Toggle(isOn: $reminder) {
                    Text("8 PM\nreminder").font(.pixel(10, .heavy)).foregroundStyle(Theme.ink)
                }
                .toggleStyle(.switch)
                .tint(Theme.leaf)
                .fixedSize()
            }
        }
        .padding(14)
        .pixelBox(Theme.card)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .padding(.top, 8)
        .background(Color(hex: 0xD9C4A0))
    }

    private func water(_ habit: Habit) {
        guard !habit.doneDays.contains(VillageStore.dayKey()) else {
            store.toast = VillageStore.Toast(speaker: .juniper, text: "\(habit.name) is already watered today!")
            return
        }
        watering = (habit.id, Date())
        store.toggleHabit(habit)
    }

    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["habit-reminder"])
        guard reminder else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Juniper: the plants are thirsty"
        content.body = "Water today's habits before bed so they keep growing."
        content.sound = .default
        var when = DateComponents()
        when.hour = 20
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: "habit-reminder", content: content, trigger: trigger))
    }
}

/// The little wooden tag under each pot.
struct PlantTag: View {
    let habit: Habit
    let done: Bool
    let streak: Int

    var body: some View {
        VStack(spacing: 1) {
            Text(habit.name)
                .font(.pixel(10, .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(Habit.stageNames[habit.stage])
                    .font(.pixel(8, .heavy))
                    .foregroundStyle(Theme.leaf)
                if streak > 0 {
                    HStack(spacing: 1) {
                        SpriteView(sprite: Sprites.flame, pixel: 1)
                        Text("\(streak)").font(.pixel(8, .heavy)).foregroundStyle(Theme.red)
                    }
                }
                if habit.auto != .manual {
                    Image(systemName: habit.auto.symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: 118)
        .background(done ? Color(hex: 0xEAF6DC) : Color(hex: 0xF6EBD3))
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
    }
}

/// Choosing a new habit: its name, its plant, and how it gets watered.
struct PlantHabitSheet: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var species = 0
    @State private var auto: HabitAuto = .manual
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Plant a habit")
                    .font(.pixel(22, .heavy))
                    .foregroundStyle(Theme.ink)
                TextField("e.g. drink water, read 10 pages", text: $name)
                    .font(.pixel(15, .medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .pixelBox(Theme.card, shadow: 2)
                    .focused($nameFocused)
                    .submitLabel(.done)

                Text("CHOOSE A PLANT")
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(PlantSpecies.allCases, id: \.rawValue) { kind in
                        let on = species == kind.rawValue
                        Button { species = kind.rawValue } label: {
                            VStack(spacing: 4) {
                                TimelineView(.periodic(from: .now, by: 0.2)) { tl in
                                    Canvas { ctx, size in
                                        let s = size.width / 44
                                        PlantRenderer.draw(Painter(ctx: ctx, s: s), species: kind, stage: 6, thirsty: false, x: 22, base: 62, t: tl.date.timeIntervalSinceReferenceDate, seed: kind.rawValue)
                                    }
                                }
                                .frame(width: 60, height: 90)
                                Text(kind.name).font(.pixel(11, .heavy)).foregroundStyle(Theme.ink)
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .pixelBox(on ? Color(hex: 0xEAF6DC) : Theme.card, shadow: on ? 3 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }

                Text("HOW IT GETS WATERED")
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                ForEach(HabitAuto.allCases, id: \.self) { option in
                    let on = auto == option
                    Button { auto = option } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol).frame(width: 22)
                            Text(option.label).font(.pixel(13, .semibold))
                            Spacer()
                            Image(systemName: on ? "largecircle.fill.circle" : "circle")
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .pixelBox(on ? Color(hex: 0xEAF6DC) : Theme.card, shadow: on ? 2 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }

                Button {
                    store.addHabit(name, auto: auto, species: species)
                    dismiss()
                } label: {
                    Text("Plant it").frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.leaf, foreground: Theme.cream))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(22)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .presentationDragIndicator(.visible)
        .task {
            // Ready to type as soon as the sheet is up.
            try? await Task.sleep(for: .milliseconds(450))
            nameFocused = true
        }
    }
}

/// Lets a plain id drive `.sheet(item:)`.
struct IDBox: Identifiable { let id: UUID }
