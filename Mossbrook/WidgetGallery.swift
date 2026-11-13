#if DEBUG
import SwiftUI
import WidgetKit

/// Debug-only: every home-screen widget at its real size, so they can be
/// checked without adding them to the home screen.
struct WidgetGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VillageStore.self) private var store
    @State private var focusing = false

    private var entry: MossEntry {
        var snap = WidgetSnapshot.load()
        if snap.habits.isEmpty { snap = .sample }
        if !focusing { snap.phases = [] }
        if focusing && snap.phases.isEmpty {
            let now = Date()
            snap.focusTitle = "Write the essay"
            snap.rounds = 3
            snap.phases = [.init(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(900), onBreak: false, round: 2)]
        }
        return MossEntry(date: .now, snap: snap, phase: snap.phase(at: .now))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Button(focusing ? "Show idle" : "Show focus") { focusing.toggle() }
                        .buttonStyle(PixelButtonStyle(fill: Theme.card, foreground: Theme.ink))
                    Spacer()
                    Button("Break test") { store.debugBreakSoon(); dismiss() }
                        .buttonStyle(PixelButtonStyle(fill: Theme.card, foreground: Theme.ink))
                    Button("Done") { dismiss() }.buttonStyle(PixelButtonStyle(fill: Theme.card, foreground: Theme.ink))
                }
                Button("Add 6 test letters") {
                    for t in ["Call mom", "Buy oat milk", "Finish essay intro", "Pay rent", "Email Sam back", "Water the basil"] {
                        store.addLetter(t, due: nil)
                    }
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.card, foreground: Theme.ink))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 22) {
                Text("TOGETHER HOUSE").font(.pixel(12, .heavy)).foregroundStyle(.white)
                HStack(spacing: 16) {
                    togetherSmall(together(running: true))
                    togetherSmall(together(running: false))
                }
                tile(364, 170) { TogetherWidgetView(fam: .systemMedium, entry: together(running: true)) }
                tile(364, 170) { TogetherWidgetView(fam: .systemMedium, entry: together(running: false)) }
                tile(170, 170, small: { TodayView(fam: .systemSmall, entry: entry) }, scene: .town(entry.snap.lettersLeft))
                tile(364, 170) { TodayView(fam: .systemMedium, entry: entry) }
                tile(364, 382) { TodayView(fam: .systemLarge, entry: entry) }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0x3B4A7A))
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.dark)
    }

    /// A Together House entry: during a session, or waiting for the next one.
    private func together(running: Bool) -> TogetherEntry {
        let now = Date()
        let live = TogetherSchedule.upcoming(after: now, includeRunning: true)
        if running {
            let slot = live.focusing(at: now) ? live : TogetherSchedule.Slot(start: now.addingTimeInterval(-9 * 60))
            return TogetherEntry(date: now, slot: slot, running: true, people: 8)
        }
        let next = live.focusing(at: now) ? live.next : live
        return TogetherEntry(date: now, slot: next, running: false, people: nil)
    }

    private func togetherSmall(_ e: TogetherEntry) -> some View {
        let progress = e.running ? now(e) : 0
        return TogetherWidgetView(fam: .systemSmall, entry: e)
            .padding(14)
            .frame(width: 170, height: 170)
            .background(TogetherScene(running: e.running, progress: progress, grid: 52))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func now(_ e: TogetherEntry) -> Double {
        max(0, min(1, Date().timeIntervalSince(e.slot.start) / e.slot.focusEnd.timeIntervalSince(e.slot.start)))
    }

    private func tile<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(width: w, height: h)
            .background(WP.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func tile<V: View>(_ w: CGFloat, _ h: CGFloat, small: () -> V, scene: PixelScene.Kind) -> some View {
        let kind: PixelScene.Kind = entry.phase.map { .desk(Color(hex: entry.snap.drinkHex), $0.onBreak) } ?? scene
        small()
            .padding(14)
            .frame(width: w, height: h)
            .background(PixelScene(kind: kind, grid: entry.phase == nil ? 52 : 64))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
#endif
