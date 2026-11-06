import Foundation
import Observation
import UserNotifications

@Observable
final class VillageStore {
    static let bikeGoal = BikePart.allCases.count
    static let bookGoal = 10
    static let cafeGoal = 300

    private(set) var letters: [Letter] = []
    private(set) var pages: [Page] = []
    private(set) var seenEvents: Set<String> = []
    private(set) var activeFocus: FocusSession?
    private(set) var focusMinutes = 0
    private(set) var focusSessions = 0
    private(set) var activeDays: Set<String> = []
    private(set) var letterDay: String?
    var weatherOverride: Weather?
    private(set) var habits: [Habit] = []
    var justFinished: FocusSession?

    var pendingEvent: StoryEvent?
    var toast: Toast?
    var phaseOverride: DayPhase? {
        didSet {
            UserDefaults.standard.set(phaseOverride.map { DayPhase.allCases.firstIndex(of: $0)! } ?? -1, forKey: "phaseOverride")
            LiveFocus.publish(self)
        }
    }

    private static func savedPhaseOverride() -> DayPhase? {
        guard UserDefaults.standard.object(forKey: "phaseOverride") != nil else { return nil }
        let i = UserDefaults.standard.integer(forKey: "phaseOverride")
        return DayPhase.allCases.indices.contains(i) ? DayPhase.allCases[i] : nil
    }

    struct Toast: Equatable {
        let id = UUID()
        let speaker: VillagerID
        let text: String
    }

    init() {
        load()
        CloudSync.shared.onRemoteChange = { [weak self] remote in self?.applyRemote(remote) }
        CloudSync.shared.onStatus = { [weak self] st in self?.cloudStatus = st }
        CloudSync.shared.start()
        phaseOverride = Self.savedPhaseOverride()
    }

    // MARK: Progress

    var lettersDelivered: Int { letters.filter(\.done).count }
    var bikeParts: Int { min(lettersDelivered, Self.bikeGoal) }
    var bikeFixed: Bool { bikeParts >= Self.bikeGoal }
    var pagesFound: Int { min(pages.count, Self.bookGoal) }
    var bookDone: Bool { pagesFound >= Self.bookGoal }
    var phase: DayPhase { phaseOverride ?? DayPhase.now() }
    var isFocusing: Bool { activeFocus != nil }
    var weather: Weather { weatherOverride ?? Weather.today() }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }

    /// Days in a row with something done: a task, a page or a cup of focus.
    var streak: Int {
        let cal = Calendar.current
        var day = Date()
        if !activeDays.contains(Self.dayKey(day)) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while activeDays.contains(Self.dayKey(day)) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    var hasDailyLetter: Bool { letterDay != Self.dayKey() }

    // MARK: Habits

    var habitsDoneToday: Int { habits.filter { $0.doneDays.contains(Self.dayKey()) }.count }

    static let maxHabits = 6

    func addHabit(_ name: String, auto: HabitAuto = .manual, species: Int? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, habits.count < Self.maxHabits else { return }
        habits.append(Habit(name: trimmed, auto: auto, species: species ?? habits.count % 6))
        save()
        toast = Toast(speaker: .juniper, text: "A new seed in the soil! Water it every day you do it.")
    }

    /// Waters every habit linked to something you just did in the app.
    func autoWater(_ kind: HabitAuto) {
        let key = Self.dayKey()
        var changed = false
        for i in habits.indices where habits[i].auto == kind && !habits[i].doneDays.contains(key) {
            habits[i].doneDays.append(key)
            changed = true
        }
        if changed { save() }
    }

    func toggleHabit(_ habit: Habit) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = Self.dayKey()
        if habits[i].doneDays.contains(key) {
            habits[i].doneDays.removeAll { $0 == key }
            save()
        } else {
            habits[i].doneDays.append(key)
            save()
            markActive()
            toast = Toast(speaker: .juniper, text: habitsDoneToday == habits.count ? "Every plant is watered today!" : "Watered! It's growing.")
        }
    }

    /// Mark or unmark a past day from the habit's calendar (for days you forgot to water).
    func toggleHabitDay(_ habit: Habit, day: Date) {
        guard let i = habits.firstIndex(where: { $0.id == habit.id }),
              Calendar.current.startOfDay(for: day) <= Date() else { return }
        let key = Self.dayKey(day)
        if habits[i].doneDays.contains(key) {
            habits[i].doneDays.removeAll { $0 == key }
        } else {
            habits[i].doneDays.append(key)
        }
        save()
    }

    /// The longest run of days in a row this habit was done.
    func bestStreak(_ habit: Habit) -> Int {
        let cal = Calendar.current
        let days = Set(habit.doneDays)
        var best = 0
        for key in days {
            guard let d = Self.dayFormatter.date(from: key),
                  let prev = cal.date(byAdding: .day, value: -1, to: d),
                  !days.contains(Self.dayKey(prev)) else { continue }
            var n = 0, cur = d
            while days.contains(Self.dayKey(cur)) {
                n += 1
                cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur
            }
            best = max(best, n)
        }
        return best
    }

    func deleteHabit(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        deleted[habit.id.uuidString] = Date()
        save()
    }

    func habitStreak(_ habit: Habit) -> Int {
        let cal = Calendar.current
        var day = Date()
        if !habit.doneDays.contains(Self.dayKey(day)) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while habit.doneDays.contains(Self.dayKey(day)) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return n
    }

    // MARK: Bakery

    /// Rosie bakes one treat for every cup you finish and every letter you deliver.
    var treatsBaked: Int { focusSessions + lettersDelivered }
    private(set) var treatsSpent = 0
    private(set) var friendship: [String: Int] = [:]
    /// Deleted ids, so iCloud never brings them back from another device.
    private(set) var deleted: [String: Date] = [:]
    var cloudStatus: CloudSync.Status = .starting
    var treatsInJar: Int { max(0, treatsBaked - treatsSpent) }
    static let streakSaveCost = 3

    /// Eat a treat. On a café break it's a cozy snack.
    @discardableResult
    func eatTreat() -> Bool {
        guard treatsInJar > 0 else {
            toast = Toast(speaker: .rosie, text: "The jar's empty! Finish a cup and I'll bake more.")
            return false
        }
        treatsSpent += 1
        save()
        let treat = Treat.allCases.filter { treatsBaked >= $0.unlockAt }.randomElement() ?? .croissant
        toast = Toast(speaker: .rosie, text: "Mmm, a \(treat.name.lowercased())! Break well spent.")
        return true
    }

    /// Give a treat to a villager. Friends get closer, and they say thanks.
    func giftTreat(to villager: VillagerID) {
        guard treatsInJar > 0 else {
            toast = Toast(speaker: .rosie, text: "The jar's empty! Finish a cup and I'll bake more.")
            return
        }
        treatsSpent += 1
        friendship[villager.rawValue, default: 0] += 1
        save()
        let thanks: [VillagerID: String] = [
            .pip: "For me?! I'll eat it on my rounds!",
            .mo: "A treat between chapters. Perfect.",
            .bea: "Pairs perfectly with an espresso!",
            .juniper: "The plants and I thank you!",
            .rosie: "Eating my own baking... don't tell anyone."
        ]
        toast = Toast(speaker: villager, text: thanks[villager] ?? "Thank you!")
    }

    func hearts(_ villager: VillagerID) -> Int { min(5, ((friendship[villager.rawValue] ?? 0) + 1) / 2) }

    /// Missed yesterday? Spend treats and the day still counts.
    var canSaveStreak: Bool {
        let cal = Calendar.current
        guard let y = cal.date(byAdding: .day, value: -1, to: Date()),
              let y2 = cal.date(byAdding: .day, value: -2, to: Date()) else { return false }
        return !activeDays.contains(Self.dayKey(y)) && activeDays.contains(Self.dayKey(y2)) && treatsInJar >= Self.streakSaveCost
    }

    func saveStreak() {
        guard canSaveStreak, let y = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        treatsSpent += Self.streakSaveCost
        activeDays.insert(Self.dayKey(y))
        save()
        toast = Toast(speaker: .rosie, text: "Saved! Your streak is \(count(streak, "day")) and counting.")
    }

    // MARK: Weekly report

    struct DayReport: Identifiable {
        let id: String
        let label: String
        let fullName: String
        let letters: Int
        let pages: Int
        let habits: Int
        var total: Int { letters + pages + habits }
    }

    var week: [DayReport] {
        let cal = Calendar.current
        return (0..<7).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: Date()) ?? Date()
            let key = Self.dayKey(date)
            return DayReport(
                id: key,
                label: String(date.formatted(.dateTime.weekday(.narrow))),
                fullName: cal.isDateInToday(date) ? "today" : date.formatted(.dateTime.weekday(.wide)),
                letters: letters.filter { $0.doneAt.map { Self.dayKey($0) } == key }.count,
                pages: pages.filter { Self.dayKey($0.created) == key }.count,
                habits: habits.filter { $0.doneDays.contains(key) }.count
            )
        }
    }

    func openDailyLetter() {
        letterDay = Self.dayKey()
        save()
    }

    private func markActive() {
        let key = Self.dayKey()
        if !activeDays.contains(key) {
            activeDays.insert(key)
            save()
        }
    }

    /// 0 closed, 1 open, 2 regulars, 3 full house.
    var cafeLevel: Int {
        if focusSessions == 0 { return 0 }
        if focusMinutes < 100 { return 1 }
        if focusMinutes < Self.cafeGoal { return 2 }
        return 3
    }

    var openLetters: [Letter] {
        letters.filter { !$0.done }.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.created > b.created
            }
        }
    }

    var deliveredLetters: [Letter] {
        letters.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    var sortedPages: [Page] {
        pages.sorted { $0.edited > $1.edited }
    }

    // MARK: Letters

    func addLetter(_ title: String, due: Date?, repeats: RepeatRule? = nil) {
        var due = due
        if let repeats, due == nil {
            // A repeating letter needs a when: start it today at 9 AM (or the next time that fits).
            let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            due = nine > Date() && !(repeats == .weekdays && RepeatRule.isWeekend(nine)) ? nine : repeats.next(from: nine)
        }
        var letter = Letter(title: title, due: due)
        letter.repeats = repeats
        letters.append(letter)
        save()
        if due != nil {
            requestNotifications()
            schedule(letter)
        }
        toast = Toast(speaker: .pip, text: repeats == nil ? "Got it! I'll deliver that one." : "Got it! I'll bring this one \(repeats!.label.lowercased()).")
        checkStory()
    }

    func deliver(_ letter: Letter) {
        guard let i = letters.firstIndex(where: { $0.id == letter.id }), !letters[i].done else { return }
        // A repeating letter's next copy appears right where the old one was; ignore a quick
        // double tap so next week's isn't ticked off by accident.
        if letters[i].repeats != nil, Date().timeIntervalSince(letters[i].created) < 1.5 { return }
        let before = bikeParts
        letters[i].done = true
        letters[i].doneAt = Date()
        // Repeating letters come straight back for next time.
        if let rule = letters[i].repeats {
            var next = Letter(title: letters[i].title, due: rule.next(from: letters[i].due ?? Date()))
            next.repeats = rule
            letters[i].nextID = next.id
            letters.append(next)
            schedule(next)
        }
        save()
        markActive()
        autoWater(.letter)
        cancelNotification(letter.id)
        if bikeParts > before, let part = BikePart(rawValue: bikeParts) {
            toast = Toast(speaker: .pip, text: "Delivered! And look, I found my \(part.name)!")
        } else {
            toast = Toast(speaker: .pip, text: "Delivered! Thank you, friend.")
        }
        checkStory()
    }

    func undeliver(_ letter: Letter) {
        guard let i = letters.firstIndex(where: { $0.id == letter.id }) else { return }
        letters[i].done = false
        letters[i].doneAt = nil
        // Take back the next copy if it hasn't been delivered yet.
        if let nid = letters[i].nextID, let j = letters.firstIndex(where: { $0.id == nid }), !letters[j].done {
            cancelNotification(nid)
            letters.remove(at: j)
            deleted[nid.uuidString] = Date()
        }
        if let k = letters.firstIndex(where: { $0.id == letter.id }) { letters[k].nextID = nil }
        save()
        schedule(letters[i])
    }

    /// Change how often a letter repeats (nil makes it a one-off).
    func setRepeat(_ letter: Letter, _ rule: RepeatRule?) {
        guard let i = letters.firstIndex(where: { $0.id == letter.id }) else { return }
        letters[i].repeats = rule
        if rule != nil && letters[i].due == nil {
            letters[i].due = rule!.next(from: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date(), after: Date())
            schedule(letters[i])
        }
        save()
    }

    func deleteLetter(_ letter: Letter) {
        letters.removeAll { $0.id == letter.id }
        deleted[letter.id.uuidString] = Date()
        cancelNotification(letter.id)
        save()
    }

    // MARK: Pages

    func addPage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let before = pagesFound
        pages.append(Page(text: trimmed))
        save()
        markActive()
        autoWater(.page)
        if pagesFound > before {
            toast = Toast(speaker: .mo, text: "Page \(pagesFound) of my book. It's coming back!")
        } else {
            toast = Toast(speaker: .mo, text: "Another lovely page for the library.")
        }
        checkStory()
    }

    /// Saves a note from the editor. A brand-new note counts as a page for Mo's book.
    func savePage(_ page: Page) {
        var page = page
        page.syncText()
        if let i = pages.firstIndex(where: { $0.id == page.id }) {
            if page.isEmpty {
                pages.remove(at: i)
                deleted[page.id.uuidString] = Date()
            } else {
                page.edited = Date()
                pages[i] = page
            }
            save()
            return
        }
        guard !page.isEmpty else { return }
        let before = pagesFound
        page.edited = Date()
        pages.append(page)
        save()
        markActive()
        autoWater(.page)
        toast = pagesFound > before
            ? Toast(speaker: .mo, text: "Page \(pagesFound) of my book. It's coming back!")
            : Toast(speaker: .mo, text: "Another lovely page for the library.")
        checkStory()
    }

    func togglePin(_ page: Page) {
        guard let i = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[i].pinned.toggle()
        save()
    }

    func duplicatePage(_ page: Page) {
        var copy = page
        copy.id = UUID()
        copy.titleText = page.title + " copy"
        copy.created = Date()
        copy.edited = Date()
        copy.pinned = false
        copy.syncText()
        pages.append(copy)
        save()
    }

    var folders: [String] {
        Array(Set(pages.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    func deletePage(_ page: Page) {
        pages.removeAll { $0.id == page.id }
        deleted[page.id.uuidString] = Date()
        save()
    }

    // MARK: Focus

    func startFocus(title: String, drink: Drink, letterID: UUID?, seat: Int? = nil, minutes: Int? = nil, breakMinutes: Int = 0, rounds: Int = 1) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var session = FocusSession(
            title: trimmed.isEmpty ? "Quiet work" : trimmed, minutes: max(1, minutes ?? drink.minutes),
            drink: drink.rawValue, letterID: letterID, seat: seat
        )
        session.breakMinutes = max(0, breakMinutes)
        session.rounds = max(1, rounds)
        activeFocus = session
        justFinished = nil
        save()
        requestNotifications()
        scheduleAlarms(session)
        LiveFocus.sync(session)
    }

    /// One notification, with the alarm chime, for the end of every work block and break.
    private func scheduleAlarms(_ session: FocusSession) {
        cancelAlarms(session)
        let center = UNUserNotificationCenter.current()
        let phases = session.schedule
        for (k, phase) in phases.enumerated() {
            let wait = phase.end.timeIntervalSinceNow
            guard wait > 1 else { continue }
            let content = UNMutableNotificationContent()
            let last = k == phases.count - 1
            if last {
                content.title = "Bea: last sip!"
                content.body = "\(session.title) is done. \(count(session.totalWorkMinutes, "minute")) of focus."
            } else if phase.onBreak {
                content.title = "Break's over"
                content.body = "Round \(phase.round + 1) of \(session.rounds): back to \(session.title)."
            } else {
                content.title = "Time for a break"
                content.body = "\(count(session.breakMinutes, "minute")). Wander the café and say hi."
            }
            content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.wav"))
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(session.id.uuidString)-\(k)", content: content, trigger: trigger))
        }
    }

    private func cancelAlarms(_ session: FocusSession) {
        let ids = [session.id.uuidString] + (0..<(session.rounds * 2 + 2)).map { "\(session.id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Moves the session through work blocks and breaks, catching up on any that ended while away.
    func advanceFocus(now: Date = Date()) {
        var changed = false
        var rang = false
        while let s = activeFocus, s.end <= now {
            changed = true
            let at = s.end
            let fresh = now.timeIntervalSince(at) < 8
            if s.onBreak {
                var next = s
                next.onBreak = false
                next.round += 1
                next.start = at
                activeFocus = next
                if fresh {
                    toast = Toast(speaker: .bea, text: "Break's over! Round \(next.round) of \(next.rounds).")
                    rang = true
                }
            } else {
                focusMinutes += s.minutes
                focusSessions += 1
                if s.round < s.rounds {
                    var next = s
                    if s.breakMinutes > 0 { next.onBreak = true } else { next.round += 1 }
                    next.start = at
                    activeFocus = next
                    if fresh {
                        toast = Toast(speaker: .bea, text: next.onBreak ? "Break time! Come say hi." : "Round \(next.round) of \(next.rounds)!")
                        rang = true
                    }
                } else {
                    activeFocus = nil
                    justFinished = s
                    save()
                    markActive()
                    autoWater(.focus)
                    if fresh { rang = true }
                    if let id = s.letterID, let letter = letters.first(where: { $0.id == id }), !letter.done {
                        deliver(letter)
                    } else {
                        toast = Toast(speaker: .bea, text: "Last sip! +\(count(s.totalWorkMinutes, "minute")) of focus.")
                        checkStory()
                    }
                }
            }
        }
        guard changed else { return }
        save()
        LiveFocus.sync(activeFocus)
        if rang { FocusAlarm.play() }
    }

    func completeFocus() { advanceFocus() }

    func skipBreak() {
        guard var s = activeFocus, s.onBreak else { return }
        s.onBreak = false
        s.round += 1
        s.start = Date()
        activeFocus = s
        save()
        scheduleAlarms(s)
        LiveFocus.sync(s)
    }

    func cancelFocus() {
        guard let session = activeFocus else { return }
        activeFocus = nil
        save()
        cancelAlarms(session)
        LiveFocus.sync(nil)
        toast = Toast(speaker: .bea, text: "No worries. Your seat will be here.")
    }

    /// Delivers the letters you ticked on the home screen widget.
    func applyWidgetDeliveries() {
        let ids = WidgetSnapshot.pendingDeliveries
        guard !ids.isEmpty else { return }
        WidgetSnapshot.pendingDeliveries = []
        for id in ids {
            if let letter = letters.first(where: { $0.id.uuidString == id }), !letter.done { deliver(letter) }
        }
        save()
    }

    func resumeFocusIfNeeded() {
        advanceFocus()
    }

    // MARK: Story

    func checkStory() {
        guard pendingEvent == nil else { return }
        if let next = Story.events.first(where: { !seenEvents.contains($0.id) && $0.isReady(self) }) {
            // New players go straight into the town tour, no story scene first.
            if next.id == "intro" {
                seenEvents.insert("intro")
                save()
                if !tourDone { showTour = true }
                return
            }
            pendingEvent = next
        }
    }

    /// The guided walk around town after the intro.
    var showTour = false
    var tourDone: Bool {
        get { UserDefaults.standard.bool(forKey: "tourDone") }
        set { UserDefaults.standard.set(newValue, forKey: "tourDone") }
    }

    func replayTour() {
        tourDone = false
        showTour = true
    }

    func finishTour() {
        tourDone = true
        showTour = false
        // The tour already introduced Bea's café.
        seenEvents.insert("bea-intro")
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.checkStory() }
    }

    func finishEvent() {
        if let event = pendingEvent {
            seenEvents.insert(event.id)
            save()
            if event.id == "intro" && !tourDone {
                pendingEvent = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, !self.tourDone else { return }
                    self.showTour = true
                }
                return
            }
        }
        pendingEvent = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkStory()
        }
    }

    // MARK: Notifications

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func schedule(_ letter: Letter) {
        guard let due = letter.due, due > Date(), !letter.done else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pip has a letter for you"
        content.body = letter.title
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: letter.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    // MARK: Your data

    /// A readable copy of everything: tasks, notes, habits and focus history.
    func exportFile() -> URL? {
        let data = snapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let json = try? encoder.encode(data) else { return nil }
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Workdoro-backup-\(day).json")
        try? json.write(to: url, options: .atomic)
        return url
    }

    /// Wipes everything and starts a fresh town, including the tour.
    func deleteAllData() {
        cancelAlarmsForReset()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        LiveFocus.sync(nil)
        let now = Date()
        for id in letters.map(\.id) + pages.map(\.id) + habits.map(\.id) { deleted[id.uuidString] = now }
        letters = []; pages = []; seenEvents = []; activeFocus = nil
        focusMinutes = 0; focusSessions = 0; activeDays = []; letterDay = nil
        habits = []; treatsSpent = 0; friendship = [:]
        justFinished = nil; pendingEvent = nil; toast = nil
        for key in ["tourDone", "phaseOverride", "habitReminder", "strictIntroSeen", "strictTipSeen", StrictActivity.storageKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // The backup and any put-aside copies go too, so "delete all" really means all.
        let docs = fileURL.deletingLastPathComponent()
        if let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("mossbrook.backup") || f.lastPathComponent.hasPrefix("mossbrook-unreadable") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        phaseOverride = nil
        weatherOverride = nil
        if let folder = try? FileManager.default.contentsOfDirectory(at: NoteImages.folder, includingPropertiesForKeys: nil) {
            folder.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        WidgetSnapshot.pendingDeliveries = []
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkStory() }
    }

    private func cancelAlarmsForReset() {
        if let s = activeFocus { cancelAlarms(s) }
    }

    // MARK: Saving

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mossbrook.json")
    }

    /// A copy of the last save that read back fine, kept so one bad write can never wipe the town.
    private var backupURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("mossbrook.backup.json") }

    private func load() {
        let decoder = JSONDecoder()
        var saved: SaveData?
        if let data = try? Data(contentsOf: fileURL) {
            saved = try? decoder.decode(SaveData.self, from: data)
            if saved == nil {
                // Never overwrite a file we couldn't read: put it aside and fall back to the backup.
                let stamp = Int(Date().timeIntervalSince1970)
                let aside = fileURL.deletingLastPathComponent().appendingPathComponent("mossbrook-unreadable-\(stamp).json")
                try? FileManager.default.moveItem(at: fileURL, to: aside)
            } else {
                // It read back fine, so it becomes the backup for this launch.
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
        }
        if saved == nil, let data = try? Data(contentsOf: backupURL) {
            saved = try? decoder.decode(SaveData.self, from: data)
        }
        guard let saved else { return }
        letters = saved.letters
        pages = saved.pages
        seenEvents = Set(saved.seenEvents)
        activeFocus = saved.activeFocus
        focusMinutes = saved.focusMinutes
        focusSessions = saved.focusSessions
        activeDays = Set(saved.activeDays)
        letterDay = saved.letterDay
        habits = saved.habits
        treatsSpent = saved.treatsSpent
        friendship = saved.friendship
        deleted = saved.deleted
        // Count days from work done before the streak existed.
        for letter in letters { if let done = letter.doneAt { activeDays.insert(Self.dayKey(done)) } }
        for page in pages { activeDays.insert(Self.dayKey(page.created)) }
    }

    private func snapshot() -> SaveData {
        var data = SaveData(
            letters: letters, pages: pages, seenEvents: Array(seenEvents),
            activeFocus: activeFocus, focusMinutes: focusMinutes, focusSessions: focusSessions,
            activeDays: Array(activeDays), letterDay: letterDay, habits: habits
        )
        data.treatsSpent = treatsSpent
        data.friendship = friendship
        data.deleted = deleted
        return data
    }

    private func save() {
        let data = snapshot()
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
        CloudSync.shared.upload(data)
        LiveFocus.publish(self)
    }

    /// Another device changed the town: fold its changes in.
    private func applyRemote(_ remote: SaveData) {
        let merged = CloudSync.merge(snapshot(), remote)
        letters = merged.letters
        pages = merged.pages
        seenEvents = Set(merged.seenEvents)
        activeFocus = merged.activeFocus
        focusMinutes = merged.focusMinutes
        focusSessions = merged.focusSessions
        activeDays = Set(merged.activeDays)
        letterDay = merged.letterDay
        habits = merged.habits
        treatsSpent = merged.treatsSpent
        friendship = merged.friendship
        deleted = merged.deleted
        NoteImages.syncWithCloud()
        save()
    }
}

#if DEBUG
extension VillageStore {
    /// Starts a 1-minute session that is 5 seconds from its break, to test the café break walk.
    func debugBreakSoon() {
        startFocus(title: "Break test", drink: .latte, letterID: nil, minutes: 1, breakMinutes: 2, rounds: 2)
        activeFocus?.start = Date().addingTimeInterval(-55)
        save()
    }
}
#endif
