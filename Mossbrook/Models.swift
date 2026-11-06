import SwiftUI

/// A task. In Mossbrook, Pip delivers them as letters.
struct Letter: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var due: Date?
    var done = false
    var created = Date()
    var doneAt: Date?
    /// How often this letter comes back once delivered. Nil for a one-off.
    var repeats: RepeatRule?
    /// The next copy made when this one was delivered, so un-delivering can take it back.
    var nextID: UUID?
}

/// How a repeating letter comes back.
enum RepeatRule: String, Codable, CaseIterable, Identifiable, Hashable {
    case daily, weekdays, weekly, monthly
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    var short: String {
        switch self {
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// Saturday or Sunday, whatever the region's calendar says about weekends.
    static func isWeekend(_ d: Date) -> Bool {
        let w = Calendar.current.component(.weekday, from: d)
        return w == 1 || w == 7
    }

    /// The next time after `after`, keeping the time of day (and weekday or date) of `from`.
    func next(from: Date, after: Date = Date()) -> Date {
        let cal = Calendar.current
        var d = from
        repeat {
            switch self {
            case .daily: d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            case .weekdays:
                repeat { d = cal.date(byAdding: .day, value: 1, to: d) ?? d } while Self.isWeekend(d)
            case .weekly: d = cal.date(byAdding: .weekOfYear, value: 1, to: d) ?? d
            case .monthly: d = cal.date(byAdding: .month, value: 1, to: d) ?? d
            }
        } while d <= after
        return d
    }
}

/// A note. In Mossbrook, Mo keeps them as pages of her book.
struct Page: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Plain-text copy of the whole note, kept in sync for titles, search and sharing.
    var text: String
    var created = Date()
    var edited = Date()
    var titleText = ""
    var blocks: [NoteBlock] = []
    var drawing: Data?
    var stickies: [Sticky] = []
    var shapes: [NoteShape] = []
    var paper: PaperStyle = .lined
    var tint: NoteTint = .cream
    var pinned = false
    var folder = ""
    /// Page 2 onwards. Page 1 lives in the fields above, so older notes stay exactly as they were.
    var moreSheets: [NoteSheet] = []

    init(text: String) {
        self.text = text
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        titleText = lines.first ?? ""
        blocks = lines.dropFirst().map { NoteBlock(kind: .text, text: $0) }
        if blocks.isEmpty { blocks = [NoteBlock(kind: .text, text: "")] }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        edited = try c.decodeIfPresent(Date.self, forKey: .edited) ?? Date()
        titleText = try c.decodeIfPresent(String.self, forKey: .titleText) ?? ""
        blocks = try c.decodeIfPresent([NoteBlock].self, forKey: .blocks) ?? []
        drawing = try c.decodeIfPresent(Data.self, forKey: .drawing)
        stickies = try c.decodeIfPresent([Sticky].self, forKey: .stickies) ?? []
        shapes = try c.decodeIfPresent([NoteShape].self, forKey: .shapes) ?? []
        paper = try c.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .lined
        tint = try c.decodeIfPresent(NoteTint.self, forKey: .tint) ?? .cream
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
        moreSheets = try c.decodeIfPresent([NoteSheet].self, forKey: .moreSheets) ?? []
        // Older notes were a single block of text.
        if blocks.isEmpty && titleText.isEmpty {
            let migrated = Page(text: text)
            titleText = migrated.titleText
            blocks = migrated.blocks
        }
    }

    var title: String { titleText.isEmpty ? "Untitled page" : titleText }

    /// Every page of the note, in order. The first one is the note's own fields.
    var sheets: [NoteSheet] {
        get { [NoteSheet(id: id, blocks: blocks, drawing: drawing, stickies: stickies, shapes: shapes)] + moreSheets }
        set {
            guard let first = newValue.first else { return }
            blocks = first.blocks
            drawing = first.drawing
            stickies = first.stickies
            shapes = first.shapes
            moreSheets = Array(newValue.dropFirst())
        }
    }

    var body: String {
        sheets.map { Self.text(of: $0.blocks) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func text(of blocks: [NoteBlock]) -> String {
        blocks.compactMap { b -> String? in
            let blank = b.text.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && [.checklist, .bullet, .numbered].contains(b.kind) { return nil }
            switch b.kind {
            case .divider, .image: return nil
            case .checklist: return (b.checked ? "☑ " : "☐ ") + b.text
            case .bullet: return "• " + b.text
            default: return b.text.isEmpty ? nil : b.text
            }
        }
        .joined(separator: "\n")
    }

    var isEmpty: Bool {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sheets.allSatisfy(\.isEmpty)
    }

    var checklistProgress: (done: Int, total: Int) {
        // Empty rows from a template don't count until something is written in them.
        let items = sheets.flatMap(\.blocks).filter { $0.kind == .checklist && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return (items.filter(\.checked).count, items.count)
    }

    var allStickies: [Sticky] { sheets.flatMap(\.stickies) }
    var hasDrawing: Bool { sheets.contains { $0.drawing != nil } }
    var hasPhoto: Bool { sheets.contains { $0.blocks.contains { $0.kind == .image } } }

    mutating func syncText() {
        let sticky = allStickies.map(\.text).filter { !$0.isEmpty }
        text = ([titleText, body] + sticky).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// One page inside a note: its own writing, drawing, stickies and shapes.
struct NoteSheet: Identifiable, Codable, Hashable {
    var id = UUID()
    var blocks: [NoteBlock] = [NoteBlock(kind: .text)]
    var drawing: Data?
    var stickies: [Sticky] = []
    var shapes: [NoteShape] = []

    var isEmpty: Bool {
        blocks.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.kind != .image && $0.kind != .divider }
            && drawing == nil && stickies.isEmpty && shapes.isEmpty
    }
}

struct NoteBlock: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case text, heading, checklist, bullet, numbered, quote, divider, image
    }

    var id = UUID()
    var kind: Kind
    var text = ""
    var checked = false
    var image: String?
}

struct Sticky: Identifiable, Codable, Hashable {
    var id = UUID()
    var text = ""
    var color = 0
    var x: Double
    var y: Double
    var tilt: Double = 0
}

struct NoteShape: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case rectangle, circle, triangle, star, heart, arrow, line
    }

    var id = UUID()
    var kind: Kind
    var x: Double
    var y: Double
    var w: Double = 90
    var h: Double = 70
    var color = 0
    var filled = false
}

enum PaperStyle: String, Codable, CaseIterable {
    case plain, lined, grid, dots
}

enum NoteTint: String, Codable, CaseIterable {
    case cream, white, pink, mint, sky, lavender
}

/// A daily habit. Juniper grows a plant for each one you keep.
struct Habit: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var doneDays: [String] = []
    var created = Date()
    var auto: HabitAuto = .manual
    var species = 0

    init(name: String, auto: HabitAuto = .manual, species: Int = 0) {
        self.name = name
        self.auto = auto
        self.species = species
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        doneDays = try c.decodeIfPresent([String].self, forKey: .doneDays) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        auto = try c.decodeIfPresent(HabitAuto.self, forKey: .auto) ?? .manual
        species = try c.decodeIfPresent(Int.self, forKey: .species) ?? 0
    }

    /// Plants grow with every day you've ever watered them, so missing a day never undoes growth.
    var stage: Int {
        switch doneDays.count {
        case 0: 0
        case 1...2: 1
        case 3...5: 2
        case 6...9: 3
        case 10...14: 4
        case 15...29: 5
        default: 6
        }
    }

    static let stageNames = ["Seed", "Sprout", "Seedling", "Growing", "Budding", "Blooming", "Flourishing"]
    static let nextStageAt = [1, 3, 6, 10, 15, 30]
}

/// A habit can water itself when you do something in Mossbrook.
enum HabitAuto: String, Codable, CaseIterable {
    case manual, focus, page, letter

    var label: String {
        switch self {
        case .manual: "I'll water it myself"
        case .focus: "When I finish a café cup"
        case .page: "When I write a page"
        case .letter: "When I deliver a letter"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "hand.tap.fill"
        case .focus: "cup.and.saucer.fill"
        case .page: "book.fill"
        case .letter: "envelope.fill"
        }
    }
}

/// A focus session at Bea's café.
struct FocusSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var minutes: Int
    var drink: String
    var start = Date()
    var letterID: UUID?
    var seat: Int?
    var breakMinutes = 0
    var rounds = 1
    var round = 1
    var onBreak = false

    /// `start` is when the current work block or break began.
    var phaseMinutes: Int { onBreak ? breakMinutes : minutes }
    var end: Date { start.addingTimeInterval(TimeInterval(phaseMinutes * 60)) }
    var duration: TimeInterval { TimeInterval(phaseMinutes * 60) }
    var totalWorkMinutes: Int { minutes * rounds }

    /// Every phase still to come, starting with the current one.
    var schedule: [(start: Date, end: Date, onBreak: Bool, round: Int)] {
        var list: [(Date, Date, Bool, Int)] = []
        var s = start, br = onBreak, r = round
        while true {
            let len = TimeInterval((br ? breakMinutes : minutes) * 60)
            list.append((s, s.addingTimeInterval(len), br, r))
            s = s.addingTimeInterval(len)
            if br { br = false; r += 1 }
            else if r >= rounds { break }
            else if breakMinutes > 0 { br = true }
            else { r += 1 }
        }
        return list
    }
}

extension FocusSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        minutes = try c.decode(Int.self, forKey: .minutes)
        drink = try c.decode(String.self, forKey: .drink)
        start = try c.decode(Date.self, forKey: .start)
        letterID = try c.decodeIfPresent(UUID.self, forKey: .letterID)
        seat = try c.decodeIfPresent(Int.self, forKey: .seat)
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 1
        onBreak = try c.decodeIfPresent(Bool.self, forKey: .onBreak) ?? false
    }
}

enum Drink: String, CaseIterable, Identifiable {
    #if DEBUG
    case taste
    #endif
    case tea, espresso, latte

    var id: String { rawValue }

    var name: String {
        switch self {
        #if DEBUG
        case .taste: return "Taste test"
        #endif
        case .tea: return "Tea"
        case .espresso: return "Espresso"
        case .latte: return "Latte"
        }
    }

    var minutes: Int {
        switch self {
        #if DEBUG
        case .taste: return 1
        #endif
        case .tea: return 15
        case .espresso: return 25
        case .latte: return 50
        }
    }

    var color: Color {
        switch self {
        #if DEBUG
        case .taste: return Color(hex: 0xB9A9C9)
        #endif
        case .tea: return Color(hex: 0x9CB86A)
        case .espresso: return Color(hex: 0x6B4226)
        case .latte: return Color(hex: 0xC69C6D)
        }
    }
}

struct SaveData: Codable {
    var letters: [Letter] = []
    var pages: [Page] = []
    var seenEvents: [String] = []
    var activeFocus: FocusSession?
    var focusMinutes = 0
    var focusSessions = 0
    var activeDays: [String] = []
    var letterDay: String?
    var habits: [Habit] = []
    var treatsSpent = 0
    var friendship: [String: Int] = [:]
    /// Ids of letters, notes and habits you deleted, with when, so iCloud doesn't bring them back.
    var deleted: [String: Date] = [:]

    init(letters: [Letter], pages: [Page], seenEvents: [String], activeFocus: FocusSession?, focusMinutes: Int, focusSessions: Int, activeDays: [String], letterDay: String?, habits: [Habit]) {
        self.habits = habits
        self.letters = letters
        self.pages = pages
        self.seenEvents = seenEvents
        self.activeFocus = activeFocus
        self.focusMinutes = focusMinutes
        self.focusSessions = focusSessions
        self.activeDays = activeDays
        self.letterDay = letterDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        letters = try c.decodeIfPresent([Letter].self, forKey: .letters) ?? []
        pages = try c.decodeIfPresent([Page].self, forKey: .pages) ?? []
        seenEvents = try c.decodeIfPresent([String].self, forKey: .seenEvents) ?? []
        activeFocus = try c.decodeIfPresent(FocusSession.self, forKey: .activeFocus)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        focusSessions = try c.decodeIfPresent(Int.self, forKey: .focusSessions) ?? 0
        activeDays = try c.decodeIfPresent([String].self, forKey: .activeDays) ?? []
        letterDay = try c.decodeIfPresent(String.self, forKey: .letterDay)
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        treatsSpent = try c.decodeIfPresent(Int.self, forKey: .treatsSpent) ?? 0
        friendship = try c.decodeIfPresent([String: Int].self, forKey: .friendship) ?? [:]
        deleted = try c.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
    }
}

enum VillagerID: String, Identifiable, CaseIterable {
    case pip, mo, bea, juniper, rosie
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pip: "Pip"
        case .mo: "Mo"
        case .bea: "Bea"
        case .juniper: "Juniper"
        case .rosie: "Rosie"
        }
    }

    var role: String {
        switch self {
        case .pip: "The postman"
        case .mo: "The librarian"
        case .bea: "The barista"
        case .juniper: "The gardener"
        case .rosie: "The baker"
        }
    }

    var sprite: Sprite {
        switch self {
        case .pip: Sprites.pip
        case .mo: Sprites.mo
        case .bea: Sprites.bea
        case .juniper: Sprites.juniper
        case .rosie: Sprites.rosie
        }
    }

    var color: Color {
        switch self {
        case .pip: Theme.pipBlue
        case .mo: Theme.moPlum
        case .bea: Theme.beaOrange
        case .juniper: Theme.leaf
        case .rosie: Color(hex: 0xC2577A)
        }
    }
}

enum Season {
    case spring, summer, autumn, winter

    static func now() -> Season {
        switch Calendar.current.component(.month, from: Date()) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}

/// Each day rolls its own weather, shaped by the real season.
enum Weather: String, CaseIterable, Identifiable {
    case clear, rain, snow, petals, leaves
    var id: String { rawValue }

    static func today() -> Weather {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let roll = noise(day, 99) % 100
        switch Season.now() {
        case .winter: return roll < 45 ? .snow : (roll < 60 ? .rain : .clear)
        case .spring: return roll < 25 ? .rain : (roll < 70 ? .petals : .clear)
        case .summer: return roll < 20 ? .rain : .clear
        case .autumn: return roll < 30 ? .rain : (roll < 80 ? .leaves : .clear)
        }
    }

    var label: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rainy"
        case .snow: "Snowy"
        case .petals: "Blossoms"
        case .leaves: "Breezy"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "sun.max.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "snowflake"
        case .petals: "camera.macro"
        case .leaves: "leaf.fill"
        }
    }
}

enum DayPhase: CaseIterable {
    case day, dusk, night

    static func now() -> DayPhase {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }

    var symbol: String {
        switch self {
        case .day: "sun.max.fill"
        case .dusk: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }
}

enum BikePart: Int, CaseIterable {
    case frontWheel = 1, backWheel, chain, seat, handlebars, bell

    var name: String {
        switch self {
        case .frontWheel: "front wheel"
        case .backWheel: "back wheel"
        case .chain: "chain"
        case .seat: "seat"
        case .handlebars: "handlebars"
        case .bell: "bell"
        }
    }
}
