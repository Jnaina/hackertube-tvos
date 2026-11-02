import Foundation
import SwiftUI

/// Loads the static HackerTube data set from Cloudflare and keeps it on disk.
///
/// The manifest names one content-hashed file per month. On first launch only the top-500 pack and the last
/// 12 months are fetched; older months follow in the background (or at once when a year is opened).
/// Shard files never change once published, so a cached file is always valid.
@MainActor
final class Catalog: ObservableObject {
    static let base = Config.dataURL

    @Published private(set) var manifest: Manifest?
    @Published private(set) var topics: [Topic] = []
    @Published private(set) var status = "Loading…"
    @Published private(set) var loadedMonths: Set<String> = []
    @Published private(set) var history: [String] = UserDefaults.standard.stringArray(forKey: "history") ?? []

    // Derived lists, rebuilt after each batch of shards.
    @Published private(set) var ranked: [Video] = []
    @Published private(set) var top: [Video] = []
    @Published private(set) var newOnHN: [Video] = []
    @Published private(set) var trending: [Video] = []
    @Published private(set) var topicShelves: [(Topic, [Video])] = []
    @Published private(set) var topicCounts: [Int: Int] = [:]
    @Published private(set) var forYou: [Video] = []

    private(set) var byID: [String: Video] = [:]
    private var shards: [String: [Video]] = [:]     // shard path -> videos
    private var topShard: [Video] = []
    private let dir: URL
    private let session: URLSession

    init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("HackerTube")
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("s"), withIntermediateDirectories: true)
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        session = URLSession(configuration: cfg)
        loadFromDisk()     // cached data first, before any refresh can start
    }

    // MARK: Loading

    private var lastCheck: Date?
    private var refreshing = false

    func start() async {
        await refreshIfStale(maxAge: 0)
    }

    /// Called at launch and whenever the app comes back to the foreground (tvOS keeps suspended apps alive for
    /// days). Only checks again if the last check is older than `maxAge`; costs one small manifest request,
    /// plus only the month files whose content changed.
    func refreshIfStale(maxAge: TimeInterval = 30 * 60) async {
        guard !refreshing, lastCheck.map({ Date().timeIntervalSince($0) >= maxAge }) ?? true else { return }
        refreshing = true
        defer { refreshing = false }
        await refresh()
        await loadMonths(manifest?.months ?? [])
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let man = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
        apply(manifest: man)
        for rel in [man.topics, man.top] + man.months.map(\.f) { _ = cachedShard(rel) }
        rebuild()
    }

    func refresh() async {
        do {
            let (data, _) = try await session.data(from: Self.base.appendingPathComponent("manifest.json"))
            let man = try JSONDecoder().decode(Manifest.self, from: data)
            try data.write(to: dir.appendingPathComponent("manifest.json"))
            apply(manifest: man)
            _ = try await shard(man.topics)
            _ = try await shard(man.top)
            await loadMonths(Array(man.months.prefix(12)))
            pruneDisk(keeping: Set([man.topics, man.top] + man.months.map(\.f)))
            lastCheck = Date()
            status = ""
        } catch {
            status = manifest == nil ? "Can't reach \(Self.base.host ?? "the data server")" : ""
        }
    }

    func loadYear(_ year: String) async {
        await loadMonths(manifest?.months.filter { $0.m.hasPrefix(year) } ?? [])
    }

    private func loadMonths(_ months: [MonthRef]) async {
        var changed = false
        for ref in months where !loadedMonths.contains(ref.m) || shards[ref.f] == nil {
            if (try? await shard(ref.f)) != nil { loadedMonths.insert(ref.m); changed = true }
        }
        if changed { rebuild() }
    }

    private func apply(manifest man: Manifest) {
        manifest = man
        let live = Set(man.months.map(\.f))
        shards = shards.filter { live.contains($0.key) }      // superseded month files
        loadedMonths = Set(man.months.filter { shards[$0.f] != nil }.map(\.m))
    }

    /// A shard from disk, or downloaded and saved. Decodes into the right store by its name.
    private func shard(_ rel: String) async throws -> Bool {
        if cachedShard(rel) { return true }
        let (data, resp) = try await session.data(from: Self.base.appendingPathComponent(rel))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try decode(rel, data)
        try data.write(to: dir.appendingPathComponent(rel))
        return true
    }

    private func cachedShard(_ rel: String) -> Bool {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(rel)) else { return false }
        return (try? decode(rel, data)) != nil
    }

    private func decode(_ rel: String, _ data: Data) throws {
        let name = (rel as NSString).lastPathComponent
        if name.hasPrefix("topics.") {
            topics = try JSONDecoder().decode([Topic].self, from: data)
        } else if name.hasPrefix("top.") {
            topShard = try JSONDecoder().decode([Video].self, from: data)
            if manifest?.top == rel { rebuild() }
        } else {
            shards[rel] = try JSONDecoder().decode([Video].self, from: data)
        }
    }

    private func pruneDisk(keeping live: Set<String>) {
        let sdir = dir.appendingPathComponent("s")
        for f in (try? FileManager.default.contentsOfDirectory(atPath: sdir.path)) ?? [] where !live.contains("s/\(f)") {
            try? FileManager.default.removeItem(at: sdir.appendingPathComponent(f))
        }
    }

    // MARK: Derived lists

    private func rebuild() {
        var all = [String: Video]()
        for v in topShard { all[v.i] = v }
        for list in shards.values { for v in list { all[v.i] = v } }
        byID = all
        ranked = all.values.sorted { $0.s > $1.s }
        top = Array(topShard.prefix(40))
        let now = Int(Date().timeIntervalSince1970)
        newOnHN = Array(ranked.filter { $0.f > now - 30 * 86400 }.sorted { $0.f > $1.f }.prefix(40))
        trending = Array(ranked.filter { $0.f > now - 365 * 86400 }.prefix(40))
        var counts = [Int: Int](), perTopic = [Int: [Video]]()
        for v in ranked {
            guard let p = v.p else { continue }
            counts[p, default: 0] += 1
            if perTopic[p, default: []].count < 30 { perTopic[p, default: []].append(v) }
        }
        topicCounts = counts
        topicShelves = topics.filter { counts[$0.id, default: 0] >= 8 && $0.name != "Other" }
            .sorted { counts[$0.id, default: 0] > counts[$1.id, default: 0] }
            .map { ($0, perTopic[$0.id] ?? []) }
        rebuildForYou()
    }

    /// On-device recommendations: topic affinity from watch history plus videos from the same HN threads.
    private func rebuildForYou() {
        let watched = history.compactMap { byID[$0] }
        guard !watched.isEmpty else { forYou = []; return }
        let seen = Set(history)
        var affinity = [Int: Double]()
        for (n, v) in watched.prefix(50).enumerated() { if let p = v.p { affinity[p, default: 0] += 1 / Double(n + 1).squareRoot() } }
        let maxA = affinity.values.max() ?? 1
        let relatedIDs = Set(watched.prefix(10).flatMap { $0.r ?? [] })
        let picks = ranked.prefix(6000).filter { !seen.contains($0.i) }.map { v -> (Video, Double) in
            var w = v.s * (1 + 1.5 * (affinity[v.p ?? -1] ?? 0) / maxA)
            if relatedIDs.contains(v.i) { w += 25 }
            return (v, w)
        }
        forYou = picks.sorted { $0.1 > $1.1 }.prefix(40).map(\.0)
    }

    func videos(topic: Int) -> [Video] { ranked.filter { $0.p == topic } }

    func videos(year: String) -> [Video] {
        let cal = Calendar(identifier: .gregorian)
        return ranked.filter { String(cal.component(.year, from: $0.firstDate)) == year }
    }

    func related(to v: Video) -> [Video] {
        var out = (v.r ?? []).compactMap { byID[$0] }
        if let p = v.p {
            let have = Set(out.map(\.i) + [v.i])
            out += ranked.lazy.filter { $0.p == p && !have.contains($0.i) }.prefix(max(0, 24 - out.count))
        }
        return out
    }

    func search(_ q: String) -> [Video] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return Array(ranked.lazy.filter {
            $0.t.localizedCaseInsensitiveContains(q) || $0.c.localizedCaseInsensitiveContains(q)
                || ($0.st?.localizedCaseInsensitiveContains(q) ?? false)
        }.prefix(200))
    }

    var years: [(String, Int)] {
        var counts = [String: Int]()
        for m in manifest?.months ?? [] { counts[String(m.m.prefix(4)), default: 0] += m.n }
        return counts.sorted { $0.key > $1.key }
    }

    func topicName(_ id: Int?) -> String? { id.flatMap { id in topics.first { $0.id == id }?.name } }

    // MARK: History

    func markWatched(_ v: Video) {
        history.removeAll { $0 == v.i }
        history.insert(v.i, at: 0)
        if history.count > 500 { history.removeLast(history.count - 500) }
        UserDefaults.standard.set(history, forKey: "history")
        rebuildForYou()
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: "history")
        rebuildForYou()
    }
}
