import CloudKit
import SwiftUI

/// Someone in the Together House. All anyone shares is a name, a look, where they are and what they're doing.
struct HallVisitor: Identifiable, Equatable {
    enum Status: String { case here, focus, rest }

    let id: String
    var name: String
    var status: Status = .here
    /// When their current focus block or break ends.
    var until: Date?
    var look: Int
    var seen: Date = .now
    /// Where they're standing or heading, in room pixels.
    var x: Double = TogetherRoom.aisle
    var y: Double = TogetherRoom.lanes[2]
    /// The seat they're using ("work2", "eat0", "relax1"), or empty when standing.
    var spot: String = ""
    var food: Int = 0
    var emote: Int = -1
    var emoteAt: Date?
    var say: Int = -1
    var sayAt: Date?
}

/// Presence in the Together House, kept in the app's public iCloud database.
///
/// No account of our own and no server: each phone writes one small record about itself and
/// reads everyone else's every few seconds. Records go stale a minute after the app stops
/// updating them, and are deleted when you leave.
@MainActor @Observable
final class HallService {
    static let shared = HallService()

    enum Phase: Equatable {
        case idle, opening, ready
        case offline(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var others: [HallVisitor] = []
    /// You, once you've come in.
    private(set) var me: HallVisitor?
    /// False when the phone isn't signed in to iCloud: you can look around but not come in.
    private(set) var canJoin = true
    private(set) var hidden: Set<String>

    var joined: Bool { me != nil }

    private var loop: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var lastBeat = Date.distantPast
    private var flagged: Set<String> = []
    /// Screenshot mode, with made-up visitors and no network.
    private var demo = false

    private let container = CKContainer(identifier: "iCloud.com.manraisingh.workdoro")
    private var db: CKDatabase { container.publicCloudDatabase }
    static let visitorType = "HallVisitor"
    static let reportType = "HallReport"
    /// How often to look for everyone else, how often to say you're still here,
    /// and how long before a quiet visitor counts as gone.
    static let poll: TimeInterval = 3
    static let beat: TimeInterval = 20
    static let fresh: TimeInterval = 75
    /// Hidden for everyone once this many different people report the same name.
    static let reportLimit = 2

    private init() {
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hallHidden") ?? [])
    }

    /// One random id per install, so the same phone always reuses the same record.
    var myID: String {
        if let id = UserDefaults.standard.string(forKey: "hallID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "hallID")
        return id
    }

    var visible: [HallVisitor] {
        others.filter { !hidden.contains($0.id) && !flagged.contains($0.id) && NameRules.problem($0.name) == nil }
    }

    // MARK: Coming and going

    func open() {
        guard loop == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-hallDemo") {
            demo = true
            others = Self.sampleVisitors
            phase = .ready
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.2))
                    self?.stirSamples()
                }
            }
            return
        }
        #endif
        phase = .opening
        loop = Task { [weak self] in
            guard let self else { return }
            let account = try? await self.container.accountStatus()
            self.canJoin = account == .available
            while !Task.isCancelled {
                if self.joined, Date().timeIntervalSince(self.lastBeat) > Self.beat { await self.sendBeat() }
                await self.refresh()
                try? await Task.sleep(for: .seconds(Self.poll))
            }
        }
    }

    /// Closing the house. While you're focusing your seat is kept until the block ends,
    /// so other people still see you working with your phone locked.
    func close(keepSeat: Bool) {
        loop?.cancel()
        loop = nil
        if joined && !keepSeat { leave() }
        if !demo { phase = .idle }
    }

    func retry() {
        loop?.cancel()
        loop = nil
        open()
    }

    func join(name: String, look: Int) {
        var v = HallVisitor(id: myID, name: NameRules.clean(name), look: look)
        // Walk in from the door at the bottom of the room.
        v.x = TogetherRoom.aisle
        v.y = TogetherRoom.lanes[2]
        me = v
        push()
    }

    func leave() {
        me = nil
        guard !demo else { return }
        let id = CKRecord.ID(recordName: myID)
        Task { _ = try? await db.deleteRecord(withID: id) }
    }

    /// Delete all data: leave and forget the name, look, id and hidden list.
    func forget() {
        if joined { leave() } else if !demo {
            let id = CKRecord.ID(recordName: myID)
            Task { _ = try? await db.deleteRecord(withID: id) }
        }
        hidden = []
        for key in ["hallID", "hallName", "hallLook", "hallHidden", "hallRulesSeen"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: Doing things

    func walk(to point: CGPoint, spot: String = "", food: Int = 0) {
        guard var v = me else { return }
        v.x = point.x; v.y = point.y; v.spot = spot; v.food = food
        me = v
        push()
    }

    func emote(_ i: Int) {
        guard var v = me else { return }
        v.emote = i; v.emoteAt = .now
        me = v
        push()
    }

    func say(_ i: Int) {
        guard var v = me else { return }
        v.say = i; v.sayAt = .now
        me = v
        push()
    }

    func update(status: HallVisitor.Status, until: Date?) {
        guard var v = me, v.status != status || v.until != until else { return }
        v.status = status; v.until = until
        me = v
        push()
    }

    // MARK: Hiding and reporting

    func hide(_ visitor: HallVisitor) {
        hidden.insert(visitor.id)
        UserDefaults.standard.set(Array(hidden), forKey: "hallHidden")
    }

    func report(_ visitor: HallVisitor) {
        hide(visitor)
        guard !demo else { return }
        let record = CKRecord(recordType: Self.reportType)
        record["target"] = visitor.id
        record["name"] = visitor.name
        Task { _ = try? await db.save(record) }
    }

    // MARK: iCloud

    /// Changes go out together a moment later, so a quick walk-then-sit is one save.
    private func push() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.sendBeat()
        }
    }

    private func sendBeat() async {
        guard let v = me, canJoin, !demo else { return }
        lastBeat = .now
        let record = CKRecord(recordType: Self.visitorType, recordID: CKRecord.ID(recordName: v.id))
        record["name"] = v.name
        record["status"] = v.status.rawValue
        record["until"] = v.until
        record["look"] = v.look
        record["x"] = v.x
        record["y"] = v.y
        record["spot"] = v.spot
        record["food"] = v.food
        record["emote"] = v.emote
        record["emoteAt"] = v.emoteAt
        record["say"] = v.say
        record["sayAt"] = v.sayAt
        // While focusing, the seat stays fresh until the block ends even if the phone is locked.
        record["seen"] = max(Date(), (v.status == .focus ? v.until : nil) ?? .distantPast)
        do {
            _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            if (error as? CKError)?.code == .notAuthenticated { canJoin = false; me = nil }
        }
    }

    private func refresh() async {
        guard !demo else { return }
        let cutoff = Date().addingTimeInterval(-Self.fresh)
        let query = CKQuery(recordType: Self.visitorType, predicate: NSPredicate(format: "seen > %@", cutoff as NSDate))
        let keys = ["name", "status", "until", "look", "seen", "x", "y", "spot", "food", "emote", "emoteAt", "say", "sayAt"]
        do {
            let (results, _) = try await db.records(matching: query, desiredKeys: keys, resultsLimit: 60)
            let mine = myID
            others = results.compactMap { id, result in
                guard id.recordName != mine, let r = try? result.get() else { return nil }
                var v = HallVisitor(id: id.recordName, name: NameRules.clean(r["name"] as? String ?? ""), look: r["look"] as? Int ?? 0)
                v.status = HallVisitor.Status(rawValue: r["status"] as? String ?? "") ?? .here
                v.until = r["until"] as? Date
                v.seen = r["seen"] as? Date ?? .now
                v.x = min(max(r["x"] as? Double ?? v.x, 0), Double(TogetherRoom.width))
                v.y = min(max(r["y"] as? Double ?? v.y, 0), Double(TogetherRoom.height))
                v.spot = r["spot"] as? String ?? ""
                v.food = r["food"] as? Int ?? 0
                v.emote = r["emote"] as? Int ?? -1
                v.emoteAt = r["emoteAt"] as? Date
                v.say = r["say"] as? Int ?? -1
                v.sayAt = r["sayAt"] as? Date
                return v
            }
            .sorted { $0.id < $1.id }
            phase = .ready
            await refreshReports()
        } catch let error as CKError where error.code == .unknownItem {
            // Nobody has ever come in yet, so the record type doesn't exist.
            others = []
            phase = .ready
        } catch let error as CKError where [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(error.code) {
            phase = .offline("Can't reach the house. Check your connection.")
        } catch {
            #if DEBUG
            print("HALL refresh failed:", error)
            #endif
            phase = .offline("The front door is stuck. Try again in a bit.")
        }
    }

    private func refreshReports() async {
        let ids = others.map(\.id)
        guard !ids.isEmpty else { return }
        let query = CKQuery(recordType: Self.reportType, predicate: NSPredicate(format: "target IN %@", ids))
        guard let (results, _) = try? await db.records(matching: query, desiredKeys: ["target"], resultsLimit: 200) else { return }
        var reporters: [String: Set<String>] = [:]
        for (_, result) in results {
            guard let r = try? result.get(), let target = r["target"] as? String else { continue }
            reporters[target, default: []].insert(r.creatorUserRecordID?.recordName ?? UUID().uuidString)
        }
        flagged = Set(reporters.filter { $0.value.count >= Self.reportLimit }.keys)
    }

    #if DEBUG
    static let sampleVisitors: [HallVisitor] = {
        let names = ["Aiko", "Mateo", "Priya", "Lena", "Kofi", "Sam", "Noor", "Jonas", "Mei"]
        let spots = ["work0", "work2", "work4", "eat0", "eat3", "relax0", "relax2", "", ""]
        return names.enumerated().map { i, n in
            var v = HallVisitor(id: "demo\(i)", name: n, look: i * 3 + 1)
            v.spot = spots[i]
            if let spot = TogetherRoom.spot(spots[i]) {
                v.x = spot.stand.x; v.y = spot.stand.y
            } else {
                v.x = i == 7 ? 30 : 100; v.y = i == 7 ? TogetherRoom.lanes[1] : TogetherRoom.lanes[0]
            }
            v.food = i % 5
            v.status = spots[i].hasPrefix("work") ? .focus : (spots[i].hasPrefix("eat") ? .rest : .here)
            v.until = Date().addingTimeInterval(Double(8 + i * 4) * 60)
            return v
        }
    }()

    /// Makes the sample visitors wander, wave and chat, so screenshots feel alive.
    private func stirSamples() {
        guard !others.isEmpty else { return }
        let i = Int.random(in: 0..<others.count)
        var v = others[i]
        switch Int.random(in: 0..<4) {
        case 0: v.emote = Int.random(in: 0..<TogetherEmote.all.count); v.emoteAt = .now
        case 1: v.say = Int.random(in: 0..<TogetherEmote.phrases.count); v.sayAt = .now
        default:
            if v.spot.isEmpty {
                v.x = Double.random(in: 10...118); v.y = TogetherRoom.lanes.randomElement()!
            } else {
                v.emote = Int.random(in: 0..<TogetherEmote.all.count); v.emoteAt = .now
            }
        }
        others[i] = v
    }
    #endif
}

/// What a hall name may be: short, plain and kind.
enum NameRules {
    static let maxLength = 16

    static func clean(_ raw: String) -> String {
        let allowed = raw.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || " .-_'".unicodeScalars.contains($0) }
        let text = String(String.UnicodeScalarView(allowed))
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return String(text.prefix(maxLength))
    }

    /// Why a name can't be used, or nil if it's fine.
    static func problem(_ raw: String) -> String? {
        let name = clean(raw)
        if name.count < 2 { return "Names need at least 2 letters." }
        let squashed = squash(name)
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { squash(String($0)) }
        if blocked.contains(where: { squashed.contains($0) }) || words.contains(where: blockedWords.contains) || blockedWords.contains(squashed) {
            return "Please pick a kinder name."
        }
        if reserved.contains(where: { squashed.contains($0) }) { return "That name is reserved." }
        return nil
    }

    /// Lowercase letters only, with look-alike digits and symbols turned back into letters.
    private static func squash(_ s: String) -> String {
        let swaps: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i"]
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return String(folded.compactMap { ch in
            if let swap = swaps[ch] { return swap }
            return ch.isLetter ? ch : nil
        })
    }

    private static let reserved = ["admin", "moderator", "workdoro", "official", "apple", "support", "staff"]

    /// Blocked anywhere inside a name.
    private static let blocked = [
        "fuck", "fck", "bitch", "cunt", "pussy", "penis", "vagina", "boob",
        "nude", "naked", "horny", "slut", "whore", "molest", "pedo", "paedo",
        "nigg", "faggot", "tranny", "retard", "chink", "kike", "wetback", "hitler",
        "killyou", "suicide", "bastard", "asshole", "arsehole", "wanker", "twat", "bollock", "milf",
        "jizz", "dildo", "orgasm", "hentai", "onlyfans", "chutiya", "madarchod", "behenchod", "bhenchod",
        "gandu", "bhosdi", "mierda", "pendejo", "salope", "scheisse", "fotze", "cazzo", "stronzo", "caralho"
    ]

    /// Blocked only as a whole word, because they hide inside ordinary names (Dickens, Essex, Kshitij, Fukuda, Nazira).
    private static let blockedWords: Set<String> = [
        "sex", "cum", "anal", "dick", "cock", "tits", "spic", "coon", "paki", "gook", "fag", "dyke", "kkk",
        "kys", "negro", "prick", "lund", "puta", "puto", "hure", "merde", "porra", "cabron", "nigga", "tit",
        "fuk", "shit", "shitty", "bullshit", "porn", "porno", "rape", "rapist", "nazi", "nazis"
    ]
}
