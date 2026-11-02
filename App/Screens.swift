import SwiftUI

struct ContentView: View {
    @EnvironmentObject var catalog: Catalog
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")   // `-tab N` launch argument

    var body: some View {
        TabView(selection: $tab) {
            Browse { HomeView() }.tabItem { Text("Home") }.tag(0)
            Browse { TopicsView() }.tabItem { Text("Topics") }.tag(1)
            Browse { YearsView() }.tabItem { Text("Years") }.tag(2)
            Browse { SearchView() }.tabItem { Text("Search") }.tag(3)
            Browse { HistoryView() }.tabItem { Text("History") }.tag(4)
        }
    }
}

/// A navigation stack with the shared destinations.
struct Browse<Root: View>: View {
    @ViewBuilder let root: () -> Root
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Video.self) { VideoDetailView(video: $0) }
                .navigationDestination(for: TopicRoute.self) { TopicView(topic: $0.topic) }
                .navigationDestination(for: YearRoute.self) { YearView(year: $0.year) }
        }
        .onAppear {
            // `-open <videoId>` launch argument: jump straight to a video page (used for testing).
            if path.isEmpty, let id = UserDefaults.standard.string(forKey: "open"), let v = catalogVideo(id) { path.append(v) }
        }
    }
    @EnvironmentObject private var catalog: Catalog
    private func catalogVideo(_ id: String) -> Video? { catalog.byID[id] }
}

struct HomeView: View {
    @EnvironmentObject var catalog: Catalog

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .lastTextBaseline, spacing: 30) {
                    Logo()
                    if let m = catalog.manifest {
                        Text("\(m.count.formatted()) videos recommended in Hacker News comments")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !catalog.status.isEmpty { Text(catalog.status).font(.callout).foregroundStyle(.secondary) }
                }
                Shelf(title: "For You", videos: catalog.forYou)
                Shelf(title: "Top of All Time", videos: catalog.top)
                Shelf(title: "New on Hacker News", videos: catalog.newOnHN)
                Shelf(title: "Popular This Year", videos: catalog.trending)
                ForEach(catalog.topicShelves, id: \.0.id) { topic, videos in
                    Shelf(title: topic.name, videos: videos)
                }
            }
        }
    }
}

struct TopicsView: View {
    @EnvironmentObject var catalog: Catalog
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(catalog.topics.filter { catalog.topicCounts[$0.id, default: 0] > 0 }) { t in
                    NavigationLink(value: TopicRoute(topic: t)) {
                        VStack(spacing: 8) {
                            Text(t.name).font(.headline).multilineTextAlignment(.center)
                            Text("\(catalog.topicCounts[t.id, default: 0].formatted()) videos").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.vertical, 30)
        }
        .navigationTitle("Topics")
    }
}

struct TopicView: View {
    @EnvironmentObject var catalog: Catalog
    let topic: Topic
    var body: some View {
        ScrollView { VideoGrid(videos: Array(catalog.videos(topic: topic.id).prefix(400))) }
            .navigationTitle(topic.name)
    }
}

struct YearsView: View {
    @EnvironmentObject var catalog: Catalog
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(catalog.years, id: \.0) { year, n in
                    NavigationLink(value: YearRoute(year: year)) {
                        VStack(spacing: 6) {
                            Text(year).font(.title2).fontWeight(.bold)
                            Text("\(n.formatted()) videos").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.vertical, 30)
        }
        .navigationTitle("First shared on HN in…")
    }
}

struct YearView: View {
    @EnvironmentObject var catalog: Catalog
    let year: String
    var body: some View {
        ScrollView { VideoGrid(videos: Array(catalog.videos(year: year).prefix(400))) }
            .navigationTitle(year)
            .task { await catalog.loadYear(year) }
    }
}

struct SearchView: View {
    @EnvironmentObject var catalog: Catalog
    @State private var query = ""
    var body: some View {
        ScrollView { VideoGrid(videos: catalog.search(query)) }
            .searchable(text: $query, prompt: "Titles, channels, HN threads")
    }
}

struct HistoryView: View {
    @EnvironmentObject var catalog: Catalog
    var body: some View {
        ScrollView {
            if catalog.history.isEmpty {
                Text("Videos you play appear here, and shape the For You row on Home.")
                    .foregroundStyle(.secondary).padding(.top, 200)
            } else {
                VideoGrid(videos: catalog.history.compactMap { catalog.byID[$0] })
                Button("Clear History", role: .destructive) { catalog.clearHistory() }.padding(.bottom, 40)
            }
        }
        .navigationTitle("History")
    }
}

struct VideoDetailView: View {
    @EnvironmentObject var catalog: Catalog
    let video: Video
    @State private var openFailed = false
    @FocusState private var playFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .top, spacing: 60) {
                    Thumb(video: video, large: true)
                        .frame(width: 860, height: 484).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 18) {
                        Text(video.t).font(.title2).fontWeight(.bold).lineLimit(3)
                        Text([video.c, video.durationText, catalog.topicName(video.p)].compactMap { $0 }.joined(separator: "  ·  "))
                            .font(.callout).foregroundStyle(.secondary)
                        Label("Shared by \(video.a) \(video.a == 1 ? "person" : "people") on Hacker News", systemImage: "person.2.fill")
                            .foregroundStyle(hnOrange)
                        Text("First mentioned \(video.firstDate.formatted(.dateTime.month(.wide).year()))")
                            .font(.callout).foregroundStyle(.secondary)
                        if let st = video.st { Text("On HN: \(st)").font(.callout).lineLimit(2) }
                        Button {
                            YouTube.open(video.i) { ok in
                                openFailed = !ok
                                if ok { catalog.markWatched(video) }
                            }
                        } label: {
                            Label("Play on YouTube", systemImage: "play.fill").padding(.horizontal, 20)
                        }
                        .focused($playFocused)
                        .padding(.top, 10)
                        if openFailed {
                            Text("Couldn't open the YouTube app. Install it from the App Store.").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                if let x = video.x {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("“\(x)”").font(.body).italic()
                        if let xa = video.xa { Text("— \(xa) on Hacker News").font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18))
                }
                Shelf(title: "Related", videos: catalog.related(to: video))
            }
        }
        .onAppear {
            playFocused = true
            // `-autoplay 1` with `-open <id>`: press Play automatically (used to test the YouTube hand-off on device).
            if UserDefaults.standard.bool(forKey: "autoplay") {
                YouTube.open(video.i) { ok in NSLog("HackerTube autoplay open %@ -> %d", video.i, ok ? 1 : 0) }
            }
        }
    }
}
