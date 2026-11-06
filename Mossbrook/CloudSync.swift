import Foundation

/// Keeps your town in iCloud Drive (the app's own hidden folder), so it follows you to a new
/// iPhone or iPad. Each device writes its copy; when another device's copy changes, the two are
/// merged item by item so nothing is lost.
final class CloudSync: @unchecked Sendable {
    static let shared = CloudSync()

    enum Status: Equatable {
        case off            // not signed in to iCloud
        case starting
        case synced(Date)
        case failed
    }

    private(set) var status: Status = .starting
    var onRemoteChange: ((SaveData) -> Void)?
    var onStatus: ((Status) -> Void)?

    private var folder: URL?
    private var query: NSMetadataQuery?
    private var lastWritten: Data?
    private var pending: Data?

    private static let containerID = "iCloud.com.manraisingh.workdoro"
    private var fileURL: URL? { folder?.appendingPathComponent("workdoro.json") }
    var imagesFolder: URL? { folder?.appendingPathComponent("NoteImages", isDirectory: true) }

    /// Finds the iCloud folder (this can take a moment, so it runs off the main thread).
    func start() {
        guard folder == nil else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else { set(.off); return }
        Task.detached {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID)?
                .appendingPathComponent("Documents", isDirectory: true)
            DispatchQueue.main.async {
                guard let url else { self.set(.off); return }
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: url.appendingPathComponent("NoteImages"), withIntermediateDirectories: true)
                self.folder = url
                self.watch()
                self.readRemote()
                if let pending = self.pending { self.write(pending) }
            }
        }
    }

    /// Saves this device's copy to iCloud.
    func upload(_ data: SaveData) {
        guard let json = try? Self.encoder.encode(data) else { return }
        guard folder != nil else { pending = json; return }
        write(json)
    }

    private func write(_ json: Data) {
        guard let url = fileURL, json != lastWritten else { return }
        lastWritten = json
        pending = nil
        Task.detached {
            var error: NSError?
            var ok = false
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { u in
                ok = (try? json.write(to: u, options: .atomic)) != nil
            }
            DispatchQueue.main.async { self.set(ok && error == nil ? .synced(Date()) : .failed) }
        }
    }

    private func readRemote() {
        guard let url = fileURL else { return }
        Task.detached {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var error: NSError?
            var data: Data?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { u in
                data = try? Data(contentsOf: u)
            }
            DispatchQueue.main.async {
                guard let data, data != self.lastWritten,
                      let remote = try? Self.decoder.decode(SaveData.self, from: data) else {
                    if self.status == .starting { self.set(.synced(Date())) }
                    return
                }
                self.onRemoteChange?(remote)
                self.set(.synced(Date()))
            }
        }
    }

    private func watch() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "workdoro.json")
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
            self?.readRemote()
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            self?.readRemote()
        }
        q.start()
        query = q
    }

    /// Check for changes when the app comes back to the front.
    func refresh() {
        if folder == nil { start() } else { readRemote() }
    }

    private func set(_ s: Status) {
        status = s
        onStatus?(s)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: Merging

    /// Combines this device's data with another device's, item by item.
    static func merge(_ a: SaveData, _ b: SaveData) -> SaveData {
        var m = a
        var deleted = a.deleted
        for (id, at) in b.deleted { deleted[id] = max(at, deleted[id] ?? .distantPast) }
        m.deleted = deleted
        let gone = Set(deleted.keys)

        func mergeByID<T: Identifiable>(_ x: [T], _ y: [T], prefer: (T, T) -> T) -> [T] where T.ID == UUID {
            var out: [UUID: T] = [:]
            var order: [UUID] = []
            for item in x + y {
                if gone.contains(item.id.uuidString) { continue }
                if let have = out[item.id] { out[item.id] = prefer(have, item) } else { out[item.id] = item; order.append(item.id) }
            }
            return order.compactMap { out[$0] }
        }

        m.letters = mergeByID(a.letters, b.letters) { l, r in
            if l.done != r.done { return l.done ? l : r }
            return (l.doneAt ?? l.created) >= (r.doneAt ?? r.created) ? l : r
        }
        m.pages = mergeByID(a.pages, b.pages) { l, r in l.edited >= r.edited ? l : r }
        m.habits = mergeByID(a.habits, b.habits) { l, r in
            var h = l
            h.doneDays = Array(Set(l.doneDays).union(r.doneDays)).sorted()
            return h
        }
        m.seenEvents = Array(Set(a.seenEvents).union(b.seenEvents))
        m.activeDays = Array(Set(a.activeDays).union(b.activeDays))
        m.focusMinutes = max(a.focusMinutes, b.focusMinutes)
        m.focusSessions = max(a.focusSessions, b.focusSessions)
        m.treatsSpent = max(a.treatsSpent, b.treatsSpent)
        for (k, v) in b.friendship { m.friendship[k] = max(v, m.friendship[k] ?? 0) }
        m.letterDay = [a.letterDay, b.letterDay].compactMap { $0 }.max()
        m.activeFocus = a.activeFocus ?? b.activeFocus
        return m
    }
}
