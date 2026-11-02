import Foundation

/// Where the app reads its data. Point this at your own backend if you run one.
enum Config {
    static let dataURL = URL(string: "https://hackernews.jagular.io/v1/")!
}
