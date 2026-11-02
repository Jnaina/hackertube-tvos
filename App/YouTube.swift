import UIKit

/// tvOS has no WebKit, so videos can't be embedded: playback is handed to the YouTube app.
enum YouTube {
    static func open(_ id: String, completion: @escaping (Bool) -> Void) {
        let urls = ["youtube://watch/\(id)", "youtube://www.youtube.com/watch?v=\(id)", "https://www.youtube.com/watch?v=\(id)"]
            .compactMap(URL.init(string:))
        attempt(urls[...], completion)
    }

    private static func attempt(_ urls: ArraySlice<URL>, _ completion: @escaping (Bool) -> Void) {
        guard let url = urls.first else { return completion(false) }
        UIApplication.shared.open(url, options: [:]) { ok in
            ok ? completion(true) : attempt(urls.dropFirst(), completion)
        }
    }
}
