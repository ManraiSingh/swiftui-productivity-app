import SwiftUI

/// A habit's story: its streaks and a month calendar of every day it was watered.
/// Tap a past day to fill in one you forgot.
struct HabitHistoryView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habitID: UUID
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start

    private var habit: Habit? { store.habits.first { $0.id == habitID } }
    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                if let habit {
                    VStack(alignment: .leading, spacing: 18) {
                        header(habit)
                        stats(habit)
                        calendar(habit)
                        Text("Tap a past day to mark one you forgot. Future days can't be watered yet.")
                            .font(.pixel(11, .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(20)
                }
            }
            .background(Theme.paper)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(.pixel(15, .heavy)) } }
        }
        .sensoryFeedback(.selection, trigger: habit?.doneDays.count ?? 0)
    }

    private func header(_ h: Habit) -> some View {
        HStack(spacing: 12) {
            Canvas { ctx, size in
                let s = size.width / 36
                PlantRenderer.draw(Painter(ctx: ctx, s: s), species: PlantSpecies(rawValue: h.species % 6) ?? .sunflower,
                                   stage: h.stage, thirsty: false, x: 18, base: 44, t: 0, seed: 1)
            }
            .frame(width: 64, height: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(h.name).font(.pixel(22, .heavy)).foregroundStyle(Theme.ink)
                Text(Habit.stageNames[h.stage].uppercased()).font(.pixel(11, .heavy)).foregroundStyle(Theme.leaf)
                Text("Planted \(h.created.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private func stats(_ h: Habit) -> some View {
        let monthDays = h.doneDays.filter { $0.hasPrefix(String(VillageStore.dayKey(Date()).prefix(7))) }.count
        let dayOfMonth = cal.component(.day, from: Date())
        return HStack(spacing: 10) {
            stat("\(store.habitStreak(h))", "current", flame: true)
            stat("\(store.bestStreak(h))", "best")
            stat("\(Set(h.doneDays).count)", "total days")
            stat("\(Int((Double(monthDays) / Double(max(dayOfMonth, 1)) * 100).rounded()))%", "this month")
        }
    }

    private func stat(_ value: String, _ label: String, flame: Bool = false) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                if flame { SpriteView(sprite: Sprites.flame, pixel: 1.6) }
                Text(value).font(.pixel(18, .heavy)).foregroundStyle(flame ? Theme.red : Theme.ink)
            }
            Text(label.uppercased()).font(.pixel(9, .heavy)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .pixelBox(Theme.card, shadow: 2)
    }

    private func calendar(_ h: Habit) -> some View {
        let done = Set(h.doneDays)
        let first = month
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        // Monday-first grid.
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) }
        let canGoForward = first < cal.dateInterval(of: .month, for: Date())!.start

        return VStack(spacing: 10) {
            HStack {
                arrow("chevron.left", enabled: true) { month = cal.date(byAdding: .month, value: -1, to: month)! }
                Spacer()
                Text(first.formatted(.dateTime.month(.wide).year())).font(.pixel(15, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                arrow("chevron.right", enabled: canGoForward) { month = cal.date(byAdding: .month, value: 1, to: month)! }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.pixel(10, .heavy)).foregroundStyle(Theme.muted)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        dayCell(day, watered: done.contains(VillageStore.dayKey(day)), h: h)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(14)
        .pixelBox(Theme.card)
    }

    private func dayCell(_ day: Date, watered: Bool, h: Habit) -> some View {
        let future = cal.startOfDay(for: day) > Date()
        let today = cal.isDateInToday(day)
        return Button { store.toggleHabitDay(h, day: day) } label: {
            ZStack {
                Rectangle().fill(watered ? Theme.leaf : (future ? Color.clear : Theme.paper))
                if watered { SpriteView(sprite: Sprites.leafIcon, pixel: 1.4).opacity(0.35) }
                Text("\(cal.component(.day, from: day))")
                    .font(.pixel(12, .heavy))
                    .foregroundStyle(watered ? Theme.cream : (future ? Theme.muted.opacity(0.4) : Theme.ink))
            }
            .frame(height: 38)
            .overlay(Rectangle().strokeBorder(today ? Theme.gold : Theme.ink.opacity(future ? 0.1 : 0.25), lineWidth: today ? 3 : 1))
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(watered ? "watered" : "not watered")")
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .heavy))
                .foregroundStyle(enabled ? Theme.ink : Theme.muted.opacity(0.3))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
