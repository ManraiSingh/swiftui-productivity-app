import Foundation
import UserNotifications

/// "Remind me" for Together House sessions: a gentle nudge a minute before the one you picked.
@Observable
final class TogetherReminders {
    static let shared = TogetherReminders()
    static let prefix = "together-"
    private let key = "togetherBooked"

    /// Start times you've asked to be reminded about.
    private(set) var booked: Set<Date> = []

    private init() {
        let raw = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        booked = Set(raw.map { Date(timeIntervalSinceReferenceDate: $0) }.filter { $0 > .now })
    }

    func isBooked(_ start: Date) -> Bool { booked.contains(start) }

    func toggle(_ start: Date) {
        if booked.contains(start) {
            booked.remove(start)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(start)])
        } else {
            booked.insert(start)
            schedule(start)
        }
        save()
    }

    private func id(_ start: Date) -> String { Self.prefix + String(Int(start.timeIntervalSinceReferenceDate)) }

    private func schedule(_ start: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Together session in 1 minute ☕"
        content.body = "Grab a desk and focus with everyone. Finish together for double treats."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let fire = max(start.addingTimeInterval(-60).timeIntervalSinceNow, 2)
        center.add(UNNotificationRequest(identifier: id(start),
                                         content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false)))
    }

    private func save() {
        booked = booked.filter { $0 > .now }
        UserDefaults.standard.set(booked.map(\.timeIntervalSinceReferenceDate), forKey: key)
    }
}
