import Foundation

/// The Together House runs on one shared clock: a 25 minute focus session starts at every :00 and :30,
/// followed by a 5 minute break. Everyone, everywhere, works at the same time, no server needed.
enum TogetherSchedule {
    static let focusMinutes = 25
    static let breakMinutes = 5
    static var length: TimeInterval { TimeInterval((focusMinutes + breakMinutes) * 60) }

    struct Slot: Equatable {
        /// When this session's focus starts.
        let start: Date
        var focusEnd: Date { start.addingTimeInterval(TimeInterval(TogetherSchedule.focusMinutes * 60)) }
        var end: Date { start.addingTimeInterval(TogetherSchedule.length) }
        var next: Slot { Slot(start: end) }

        func focusing(at date: Date) -> Bool { date >= start && date < focusEnd }
    }

    /// The session that `date` falls in (focus or its break).
    static func slot(at date: Date) -> Slot {
        let t = date.timeIntervalSinceReferenceDate
        // Align to the local wall clock, so sessions start at :00 and :30 wherever you are.
        // For almost every time zone that's the same moment worldwide, so people really do start together.
        let offset = TimeInterval(TimeZone.current.secondsFromGMT(for: date))
        let local = t + offset
        let start = (local / length).rounded(.down) * length - offset
        return Slot(start: Date(timeIntervalSinceReferenceDate: start))
    }

    /// The next focus that hasn't started yet, or the one running now if `includeRunning`.
    static func upcoming(after date: Date, includeRunning: Bool = false) -> Slot {
        let s = slot(at: date)
        if includeRunning && s.focusing(at: date) { return s }
        return date < s.start ? s : s.next
    }

    /// Clock time like "3:30", in the user's 12/24 hour style.
    static func label(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
