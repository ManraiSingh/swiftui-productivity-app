import ActivityKit
import Foundation
import WidgetKit

/// Keeps the Live Activity in step with the current focus session.
enum LiveFocus {
    /// The title the Together House gives its shared sessions.
    static let togetherTitle = "Together House"
    /// Who's focusing in your Together House session right now, kept fresh by the house.
    static var togetherPeople = 0

    static func drinkHex(_ raw: String) -> UInt32 {
        ["tea": 0x9CB86A, "espresso": 0x6B4226, "latte": 0xC69C6D, "taste": 0xB9A9C9][raw] ?? 0x6B4226
    }

    static func sync(_ session: FocusSession?) {
        Task {
            let running = Activity<FocusActivityAttributes>.activities
            guard let s = session else {
                for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            let state = FocusActivityAttributes.ContentState(
                title: s.title, start: s.start, end: s.end, onBreak: s.onBreak,
                round: s.round, rounds: s.rounds, drinkHex: drinkHex(s.drink),
                together: s.title == togetherTitle ? true : nil,
                people: s.title == togetherTitle ? togetherPeople : nil
            )
            let content = ActivityContent(state: state, staleDate: s.end.addingTimeInterval(120))
            if let activity = running.first {
                await activity.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                _ = try? Activity.request(attributes: FocusActivityAttributes(name: "focus"), content: content)
            }
        }
    }

    /// Refreshes what the home and lock screen widgets show.
    static func publish(_ store: VillageStore) {
        var snap = WidgetSnapshot()
        if let s = store.activeFocus {
            snap.focusTitle = s.title
            snap.rounds = s.rounds
            snap.drinkHex = drinkHex(s.drink)
            snap.phases = s.schedule.map { .init(start: $0.start, end: $0.end, onBreak: $0.onBreak, round: $0.round) }
        }
        let pending = Set(WidgetSnapshot.pendingDeliveries)
        let open = store.openLetters.filter { !pending.contains($0.id.uuidString) }
        snap.letters = open.prefix(8).map(\.title)
        snap.letterIDs = open.prefix(8).map(\.id.uuidString)
        snap.lettersLeft = open.count
        snap.streak = store.streak
        snap.skyOverride = store.phaseOverride.map { DayPhase.allCases.firstIndex(of: $0)! }
        snap.habits = store.habits.map { h in
            WidgetSnapshot.HabitInfo(
                name: h.name, streak: store.habitStreak(h), done: h.doneDays.contains(VillageStore.dayKey()),
                species: h.species, stage: h.stage
            )
        }
        snap.habitsDone = store.habitsDoneToday
        snap.habitsTotal = store.habits.count
        snap.cafeMinutes = store.focusMinutes
        snap.treats = store.treatsInJar
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
