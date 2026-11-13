import SwiftUI
import WidgetKit

// MARK: - What the app tells the widget about the house

enum TogetherHouseInfo {
    private static let countKey = "houseCount"
    private static let seenKey = "houseSeen"

    /// Saved by the app while the Together House is open, so the widget can say how busy it was.
    static func save(count: Int) {
        let d = UserDefaults(suiteName: WidgetSnapshot.group)
        d?.set(count, forKey: countKey)
        d?.set(Date(), forKey: seenKey)
    }

    /// The last head count, if it's recent enough to still be true-ish.
    static func recentCount(at date: Date) -> Int? {
        let d = UserDefaults(suiteName: WidgetSnapshot.group)
        guard let seen = d?.object(forKey: seenKey) as? Date, date.timeIntervalSince(seen) < 40 * 60 else { return nil }
        let n = d?.integer(forKey: countKey) ?? 0
        return n > 0 ? n : nil
    }
}

// MARK: - Timeline

struct TogetherEntry: TimelineEntry {
    let date: Date
    let slot: TogetherSchedule.Slot
    let running: Bool
    let people: Int?
}

struct TogetherProvider: TimelineProvider {
    func placeholder(in context: Context) -> TogetherEntry { entry(at: .now, preview: true) }

    func getSnapshot(in context: Context, completion: @escaping (TogetherEntry) -> Void) {
        completion(entry(at: .now, preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TogetherEntry>) -> Void) {
        let now = Date()
        var dates: [Date] = [now]
        var slot = TogetherSchedule.slot(at: now)
        // An entry at every session start and every break, for the next 12 hours.
        for _ in 0..<24 {
            for d in [slot.start, slot.focusEnd] where d > now { dates.append(d) }
            slot = slot.next
        }
        completion(Timeline(entries: dates.map { entry(at: $0, preview: false) }, policy: .atEnd))
    }

    private func entry(at date: Date, preview: Bool) -> TogetherEntry {
        let slot = TogetherSchedule.upcoming(after: date, includeRunning: true)
        return TogetherEntry(date: date, slot: slot, running: slot.focusing(at: date),
                             people: preview ? 8 : TogetherHouseInfo.recentCount(at: date))
    }
}

// MARK: - The room, in pixels

/// A little window into the Together House: desks of people working under warm lamps, and the session clock on the wall.
struct TogetherScene: View {
    let running: Bool
    var progress: Double = 0
    var grid = 64
    var date = Date()

    var body: some View {
        Canvas { ctx, size in
            let s = max(size.width, 1) / CGFloat(grid)
            let rows = Int(size.height / s) + 1
            TogetherArt.room(Painter(ctx: ctx, s: s), w: grid, rows: rows, running: running, progress: progress, time: SkyTime.at(date))
        }
        .clipped()
    }
}

enum TogetherArt {
    static let ink = WP.ink

    static func room(_ p: Painter, w: Int, rows: Int, running: Bool, progress: Double, time: SkyTime) {
        let floorY = rows - 12
        // Rosy wallpaper with little dots.
        p.rect(0, 0, w, floorY, Color(hex: 0xF6E1CF))
        for y in stride(from: 3, to: floorY - 8, by: 6) {
            for x in stride(from: (y / 6) % 2 * 3 + 1, to: w, by: 6) { p.dot(x, y, Color(hex: 0xF0C8C8)) }
        }
        // Wainscot.
        p.rect(0, floorY - 9, w, 9, Color(hex: 0xB9D8C2))
        p.rect(0, floorY - 9, w, 1, Color(hex: 0x8EBBA0))

        // Window with the real sky.
        Art.box(p, 4, 7, 18, 16, Color(hex: 0x8A5230))
        let b = time.bands
        p.rect(5, 8, 16, 5, Color(hex: b[0]))
        p.rect(5, 13, 16, 5, Color(hex: b[1]))
        p.rect(5, 18, 16, 4, Color(hex: b[2]))
        if time == .night { for i in 0..<4 { p.dot(6 + (i * 5) % 14, 9 + (i * 3) % 7, .white) } }
        p.rect(12, 8, 2, 14, Color(hex: 0x8A5230))
        p.rect(3, 23, 20, 2, Color(hex: 0xC07A40))
        p.rect(6, 21, 3, 2, Color(hex: 0x6E8B5E)); p.rect(16, 21, 3, 2, Color(hex: 0xF49AC1))

        // The session clock: fills with pink while everyone focuses.
        clock(p, cx: w - 13, cy: 14, running: running, progress: progress)

        // String lights.
        let bulbs: [UInt32] = [0xFFD27A, 0xF49AC1, 0xA6E1F0, 0xFFE38A]
        for (i, x) in stride(from: 2, to: w, by: 6).enumerated() {
            let y = 2 + i % 2
            p.glow(Double(x) + 0.5, Double(y), radius: 2.5, Color(hex: bulbs[i % 4]), 0.6)
            p.dot(x, y, Color(hex: bulbs[i % 4]))
        }

        // Floor.
        for (i, y) in stride(from: floorY, to: rows, by: 3).enumerated() {
            p.rect(0, y, w, 3, Color(hex: i % 2 == 0 ? 0xDDA56C : 0xD69C62))
            p.rect(0, y + 2, w, 1, Color(hex: 0xC48A52))
        }

        // A long desk with three people working at laptops.
        let deskY = floorY - 4
        let folks = [Sprites.customers[0], Sprites.customers[2], Sprites.customers[4]]
        let xs = [6, 24, 42]
        for (i, x) in xs.enumerated() {
            let bob = running ? 0 : (i == 1 ? -1 : 0)
            p.sprite(folks[i % folks.count], x: x, y: deskY - 15 + bob)
        }
        for x in xs {
            p.glow(Double(x + 8), Double(deskY - 3), radius: 7, Color(hex: 0xBFE6FF), running ? 0.35 : 0.15)
            Art.box(p, x + 3, deskY - 5, 10, 5, Color(hex: 0x9AA0AE))
            p.rect(x + 3, deskY - 5, 10, 1, Color(hex: 0xC4C9D2))
            p.rect(x + 7, deskY - 3, 2, 1, Color(hex: 0xF7B7CF))
        }
        Art.box(p, 1, deskY, w - 2, 3, Color(hex: 0xC98B55))
        p.rect(1, deskY, w - 2, 1, Color(hex: 0xE3AA72))
        // Desk lamps.
        for lx in [3, w - 6] {
            p.rect(lx + 1, deskY - 5, 1, 5, Color(hex: 0xC9A050))
            Art.box(p, lx - 1, deskY - 7, 5, 2, Color(hex: 0x3E7A58))
            p.glow(Double(lx) + 1.5, Double(deskY - 4), radius: 8, Color(hex: 0xFFD27A), running ? 0.55 : 0.35)
        }
        // A cocoa and the café cat curled up on the desk end.
        Art.box(p, w - 15, deskY - 5, 4, 5, Color(hex: 0xFFFDF6))
        p.rect(w - 14, deskY - 4, 2, 1, Color(hex: 0x8A5230))
        for i in 0..<2 { p.rect(w - 14 + i, deskY - 8 + i, 1, 2, Color.white.opacity(0.7)) }

        // Quiet hours: the room dims a touch while the session runs.
        if running { p.rect(0, 0, w, rows, Color(hex: 0x1E1430).opacity(0.1)) }
        if time == .night { p.rect(0, 0, w, rows, Color(hex: 0x0E1238).opacity(0.12)) }
    }

    static func clock(_ p: Painter, cx: Int, cy: Int, running: Bool, progress: Double) {
        let r = 7.0
        for y in -8...8 {
            for x in -8...8 {
                let d = (Double(x * x + y * y)).squareRoot()
                if d > r + 0.3 { continue }
                if d > r - 1.1 { p.dot(cx + x, cy + y, ink); continue }
                var a = atan2(Double(x), -Double(y)) / (2 * .pi)
                if a < 0 { a += 1 }
                p.dot(cx + x, cy + y, running && a <= progress ? Color(hex: 0xF7B7CF) : WP.card)
            }
        }
        for (dx, dy) in [(0, -5), (5, 0), (0, 5), (-5, 0)] { p.dot(cx + dx, cy + dy, Color(hex: 0xC2577A)) }
        if running {
            p.rect(cx, cy, 1, 1, ink)
        } else {
            p.rect(cx, cy - 4, 1, 5, ink)
            p.rect(cx, cy, 3, 1, ink)
        }
    }
}

// MARK: - Widget views

struct TogetherWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    var fam: WidgetFamily? = nil
    private var family: WidgetFamily { fam ?? envFamily }
    let entry: TogetherEntry

    private var focusRange: ClosedRange<Date> { entry.slot.start...entry.slot.focusEnd }
    private var waitRange: ClosedRange<Date> { entry.date...max(entry.slot.start, entry.date.addingTimeInterval(1)) }
    private var progress: Double {
        guard entry.running else { return 0 }
        return max(0, min(1, entry.date.timeIntervalSince(entry.slot.start) / entry.slot.focusEnd.timeIntervalSince(entry.slot.start)))
    }
    private var pink: Color { Color(hex: 0xF7B7CF) }
    private var rose: Color { Color(hex: 0xC2577A) }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
        .widgetURL(URL(string: "workdoro://together"))
    }

    private var countdown: some View {
        Text(timerInterval: entry.running ? focusRange : waitRange, countsDown: true)
            .monospacedDigit()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Chip(icon: nil, text: entry.running ? "FOCUS TOGETHER" : "TOGETHER HOUSE", tint: entry.running ? rose : WP.ink, fill: entry.running ? Color(hex: 0xFFF1F6) : WP.card)
            Spacer()
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.running ? "ENDS IN" : "NEXT AT \(TogetherSchedule.label(entry.slot.start))")
                    .font(.cozy(8, .heavy)).foregroundStyle(entry.running ? rose : WP.muted)
                countdown
                    .font(.cozy(18, .heavy))
                    .foregroundStyle(WP.ink)
                    .frame(width: 70, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .framed(WP.paper)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            TogetherScene(running: entry.running, progress: progress, grid: 52, date: entry.date)
        }
    }

    private var medium: some View {
        HStack(spacing: 12) {
            TogetherScene(running: entry.running, progress: progress, date: entry.date)
                .aspectRatio(1, contentMode: .fit)
                .framed()
            VStack(alignment: .leading, spacing: 5) {
                Chip(icon: nil, text: entry.running ? "FOCUSING NOW" : "NEXT SESSION", tint: entry.running ? rose : WP.ink,
                     fill: entry.running ? Color(hex: 0xFFF1F6) : WP.card)
                Text(entry.running ? "Work alongside real people" : "Save a seat at \(TogetherSchedule.label(entry.slot.start))")
                    .font(.cozy(13, .heavy))
                    .foregroundStyle(WP.ink)
                    .lineLimit(2)
                countdown
                    .font(.cozy(26, .heavy))
                    .foregroundStyle(WP.ink)
                if entry.running {
                    ProgressView(timerInterval: focusRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(pink)
                }
                if let n = entry.people {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color(hex: 0x6CC28A)).frame(width: 5, height: 5)
                        Text("\(n) in the house").font(.cozy(10, .heavy)).foregroundStyle(WP.muted)
                    }
                } else if !entry.running {
                    Text("25 min focus · 5 min break").font(.cozy(10, .semibold)).foregroundStyle(WP.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WP.paper, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.running ? "FOCUS TOGETHER" : "TOGETHER HOUSE")
                .font(.cozy(10, .heavy))
            HStack(spacing: 4) {
                Text(entry.running ? "ends in" : "next at \(TogetherSchedule.label(entry.slot.start)) ·")
                    .font(.cozy(12, .semibold))
                countdown.font(.cozy(14, .heavy))
            }
            if entry.running {
                ProgressView(timerInterval: focusRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Text(entry.running ? "Focusing together · ends \(TogetherSchedule.label(entry.slot.focusEnd))" : "Together session at \(TogetherSchedule.label(entry.slot.start))")
            .containerBackground(.clear, for: .widget)
    }
}
