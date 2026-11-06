import Foundation

/// What the widgets and Live Activity need to know, written by the app into the shared app group.
struct WidgetSnapshot: Codable {
    struct Phase: Codable, Hashable {
        var start: Date
        var end: Date
        var onBreak: Bool
        var round: Int
    }

    struct HabitInfo: Codable, Hashable {
        var name: String
        var streak: Int
        var done: Bool
        var species: Int
        var stage: Int
    }

    var habits: [HabitInfo] = []
    /// 0 day, 1 sunset, 2 night when the app's time-of-day picker is set; nil follows the clock.
    var skyOverride: Int? = nil
    var focusTitle: String?
    var rounds = 1
    var drinkHex: UInt32 = 0x6B4226
    var phases: [Phase] = []
    var letters: [String] = []
    var letterIDs: [String]? = nil
    var lettersLeft = 0
    var streak = 0
    var habitsDone = 0
    var habitsTotal = 0
    var cafeMinutes = 0
    var treats = 0

    static let group = "group.com.manraisingh.workdoro"
    private static let key = "snapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    private static let pendingKey = "pendingDeliveries"

    /// Letters ticked on the widget that the app hasn't delivered yet.
    static var pendingDeliveries: [String] {
        get { UserDefaults(suiteName: group)?.stringArray(forKey: pendingKey) ?? [] }
        set { UserDefaults(suiteName: group)?.set(newValue, forKey: pendingKey) }
    }

    /// Takes a letter off the widget at once and queues it for the app.
    static func markDelivered(_ id: String) {
        var snap = load()
        if let ids = snap.letterIDs, let i = ids.firstIndex(of: id) {
            snap.letterIDs?.remove(at: i)
            if i < snap.letters.count { snap.letters.remove(at: i) }
            snap.lettersLeft = max(0, snap.lettersLeft - 1)
            snap.save()
        }
        if !pendingDeliveries.contains(id) { pendingDeliveries.append(id) }
    }

    func phase(at date: Date) -> Phase? {
        guard focusTitle != nil else { return nil }
        return phases.first { $0.start <= date && date < $0.end }
    }

    static let sample = WidgetSnapshot(
        habits: [
            HabitInfo(name: "Drink water", streak: 6, done: true, species: 1, stage: 4),
            HabitInfo(name: "Read 10 pages", streak: 3, done: false, species: 0, stage: 3),
            HabitInfo(name: "Stretch", streak: 12, done: true, species: 5, stage: 5)
        ],
        focusTitle: nil, letters: ["Call mom", "Finish essay intro", "Buy oat milk"], lettersLeft: 3,
        streak: 4, habitsDone: 2, habitsTotal: 3, cafeMinutes: 120, treats: 6
    )
}
