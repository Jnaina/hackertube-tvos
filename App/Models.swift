import Foundation

/// One published video. Short keys match the JSON shards produced by backend/publish.py.
struct Video: Codable, Identifiable, Hashable {
    let i: String        // YouTube video id
    let t: String        // title
    let c: String        // channel
    let s: Double        // rank score
    let m: Int           // HN mentions
    let a: Int           // distinct HN authors
    let f: Int           // first HN mention (unix time)
    let h: Int?          // HN story (or item) id
    let d: Int?          // duration in seconds (only with a YouTube API key)
    let p: Int?          // topic id
    let st: String?      // HN thread title (its own submission if it was one)
    let x: String?       // representative HN comment
    let xa: String?      // its author
    let r: [String]?     // related video ids (same HN threads)

    var id: String { i }
    var firstDate: Date { Date(timeIntervalSince1970: TimeInterval(f)) }
    /// YouTube's auto-generated frame from the middle of the video (as in Karpathy's HackerTube).
    var midFrameURL: URL { URL(string: "https://i.ytimg.com/vi/\(i)/hq2.jpg")! }
    var thumbURL: URL { URL(string: "https://i.ytimg.com/vi/\(i)/hqdefault.jpg")! }
    var hd720URL: URL { URL(string: "https://i.ytimg.com/vi/\(i)/hq720.jpg")! }
    var largeThumbURL: URL { URL(string: "https://i.ytimg.com/vi/\(i)/maxresdefault.jpg")! }

    var durationText: String? {
        guard let d, d > 0 else { return nil }
        let h = d / 3600, m = (d % 3600) / 60, s = d % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func == (l: Video, r: Video) -> Bool { l.i == r.i }
    func hash(into hasher: inout Hasher) { hasher.combine(i) }
}

struct MonthRef: Codable, Hashable {
    let m: String   // "2026-10"
    let f: String   // shard path relative to /v1/
    let n: Int
}

struct Manifest: Codable {
    let v: Int
    let generated: Int
    let count: Int
    let topics: String
    let top: String
    let months: [MonthRef]
}

struct Topic: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TopicRoute: Hashable { let topic: Topic }
struct YearRoute: Hashable { let year: String }
