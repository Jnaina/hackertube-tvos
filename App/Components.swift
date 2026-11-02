import SwiftUI

let hnOrange = Color(red: 1, green: 0.4, blue: 0)

/// Loads the first thumbnail URL that really exists. YouTube answers a missing size with a 404 *and* a grey
/// placeholder image, so the HTTP status has to be checked (AsyncImage would show the placeholder).
@MainActor
final class ThumbLoader: ObservableObject {
    private static let cache = NSCache<NSString, UIImage>()
    @Published var image: UIImage?

    func load(_ urls: [URL]) async {
        let key = urls.first!.absoluteString as NSString
        if let img = Self.cache.object(forKey: key) { image = img; return }
        for url in urls {
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { continue }
            Self.cache.setObject(img, forKey: key)
            image = img
            return
        }
    }
}

/// Mid-video frame for cards (falls back to the uploader's thumbnail); the largest available image for the hero.
struct Thumb: View {
    let video: Video
    var large = false
    @StateObject private var loader = ThumbLoader()

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let img = loader.image { Image(uiImage: img).resizable().aspectRatio(contentMode: .fill) }
        }
        .task(id: video.i) {
            await loader.load(large ? [video.largeThumbURL, video.hd720URL, video.thumbURL] : [video.midFrameURL, video.thumbURL])
        }
    }
}

struct VideoCard: View {
    let video: Video
    var width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: video) {
                Thumb(video: video)
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if let d = video.durationText {
                            Text(d).font(.caption2.monospacedDigit()).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6)).padding(10)
                        }
                    }
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.t).font(.caption).fontWeight(.semibold).lineLimit(2)
                Text("\(video.c) · ").font(.caption2).foregroundStyle(.secondary)
                    + Text("\(video.a) on HN").font(.caption2).foregroundStyle(hnOrange)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

struct Shelf: View {
    let title: String
    let videos: [Video]

    var body: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title3).fontWeight(.bold)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 48) {
                        ForEach(videos) { VideoCard(video: $0) }
                    }
                    .padding(.vertical, 36)
                }
                .scrollClipDisabled()
            }
        }
    }
}

struct VideoGrid: View {
    let videos: [Video]
    private let columns = Array(repeating: GridItem(.fixed(400), spacing: 48, alignment: .top), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 56) {
            ForEach(videos) { VideoCard(video: $0) }
        }
        .padding(.vertical, 30)
    }
}

struct Logo: View {
    var body: some View {
        (Text("Hacker").foregroundStyle(.primary) + Text("Tube").foregroundStyle(hnOrange))
            .font(.system(size: 56, weight: .heavy))
    }
}
