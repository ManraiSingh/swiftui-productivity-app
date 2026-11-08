#if DEBUG
import Foundation

/// Debug-only check of the iCloud merge: run with the launch argument -mergeSelfTest.
enum MergeSelfTest {
    static func run() {
        var a = SaveData(letters: [], pages: [], seenEvents: ["intro"], activeFocus: nil, focusMinutes: 50, focusSessions: 2, activeDays: ["2026-11-01"], letterDay: nil, habits: [])
        var b = a
        // Phone writes a letter; iPad writes a different one.
        let l1 = Letter(title: "From phone"), l2 = Letter(title: "From iPad")
        a.letters = [l1]; b.letters = [l2]
        // Same note edited on both; iPad's edit is newer.
        var p = Page(text: "Old"); p.edited = Date(timeIntervalSince1970: 1000)
        var pNew = p; pNew.text = "Newer"; pNew.edited = Date(timeIntervalSince1970: 2000)
        a.pages = [p]; b.pages = [pNew]
        // Same habit watered on different days.
        var h = Habit(name: "Read"); h.doneDays = ["2026-11-01"]
        var h2 = h; h2.doneDays = ["2026-11-02"]
        a.habits = [h]; b.habits = [h2]
        // A note deleted on the iPad must not come back from the phone.
        let gone = Page(text: "Delete me")
        a.pages.append(gone)
        b.deleted[gone.id.uuidString] = Date()
        b.focusMinutes = 75

        let m = CloudSync.merge(a, b)
        let checks: [(String, Bool)] = [
            ("both letters kept", Set(m.letters.map(\.title)) == ["From phone", "From iPad"]),
            ("newest note edit wins", m.pages.first(where: { $0.id == p.id })?.text == "Newer"),
            ("deleted note stays deleted", !m.pages.contains { $0.id == gone.id }),
            ("habit days combined", Set(m.habits.first?.doneDays ?? []) == ["2026-11-01", "2026-11-02"]),
            ("focus minutes kept", m.focusMinutes == 75),
            ("merge is symmetric", Set(CloudSync.merge(b, a).letters.map(\.id)) == Set(m.letters.map(\.id)))
        ]
        for (name, ok) in checks { NSLog("MERGETEST %@ %@", ok ? "PASS" : "FAIL", name) }

        // Notes with more than one page.
        var book = Page(text: "Trip\nDay one")
        var second = NoteSheet(); second.blocks = [NoteBlock(kind: .text, text: "Day two")]
        book.moreSheets = [second]
        book.syncText()
        let roundTrip = (try? JSONEncoder().encode(book)).flatMap { try? JSONDecoder().decode(Page.self, from: $0) }
        let oldJSON = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Old note","titleText":"Old note","blocks":[]}"#
        let oldNote = try? JSONDecoder().decode(Page.self, from: Data(oldJSON.utf8))
        var reordered = book; reordered.sheets = Array(book.sheets.reversed())
        let pageChecks: [(String, Bool)] = [
            ("extra pages are saved", roundTrip?.moreSheets.first?.blocks.first?.text == "Day two"),
            ("search sees every page", book.text.contains("Day two")),
            ("old notes open with one page", oldNote?.sheets.count == 1),
            ("pages can be reordered", reordered.blocks.first?.text == "Day two" && reordered.moreSheets.count == 1),
            ("a page with writing is not empty", !book.isEmpty)
        ]
        for (name, ok) in pageChecks { NSLog("MERGETEST %@ %@", ok ? "PASS" : "FAIL", name) }

        // Repeating letters.
        let cal = Calendar.current
        let p1 = Capture.parse("gym every monday 7am")
        let p2 = Capture.parse("water plants daily")
        let p3 = Capture.parse("standup every weekday 10am")
        let p4 = Capture.parse("pay rent every month")
        let p5 = Capture.parse("call mom friday 6pm")
        let fri = cal.nextDate(after: Date(), matching: DateComponents(hour: 17, weekday: 6), matchingPolicy: .nextTime)!
        let nextWeekday = RepeatRule.weekdays.next(from: fri, after: fri)
        let rchecks: [(String, Bool)] = [
            ("every monday -> weekly, Monday 7:00", p1.repeats == .weekly && p1.title == "gym" && p1.due.map { cal.component(.weekday, from: $0) == 2 && cal.component(.hour, from: $0) == 7 } == true),
            ("daily -> daily", p2.repeats == .daily && p2.title == "water plants"),
            ("every weekday -> weekdays at 10", p3.repeats == .weekdays && p3.title == "standup" && p3.due.map { cal.component(.hour, from: $0) == 10 } == true),
            ("every month -> monthly", p4.repeats == .monthly && p4.title == "pay rent"),
            ("one-off stays one-off", p5.repeats == nil && p5.title == "call mom"),
            ("weekday after Friday is Monday", cal.component(.weekday, from: nextWeekday) == 2),
            ("weekly keeps the time", cal.component(.hour, from: RepeatRule.weekly.next(from: fri)) == 17)
        ]
        for (name, ok) in rchecks { NSLog("MERGETEST %@ %@", ok ? "PASS" : "FAIL", name) }

        // Study hall names.
        let nchecks: [(String, Bool)] = [
            ("ordinary names pass", ["Manrai", "Aiko", "Tomás", "Kshitij", "Dickens", "Nazira", "Mei Ling"].allSatisfy { NameRules.problem($0) == nil }),
            ("rude names blocked", ["fuck", "F u c k", "sh1t head", "b1tch", "nazi"].allSatisfy { NameRules.problem($0) != nil }),
            ("reserved names blocked", NameRules.problem("Workdoro Admin") != nil),
            ("names are trimmed and capped", NameRules.clean("  Ana   <b>Lee</b>!!  ") == "Ana bLeeb" && NameRules.clean(String(repeating: "a", count: 40)).count == 16),
            ("one letter is too short", NameRules.problem("A") != nil)
        ]
        for (name, ok) in nchecks { NSLog("MERGETEST %@ %@", ok ? "PASS" : "FAIL", name) }
    }
}
#endif
