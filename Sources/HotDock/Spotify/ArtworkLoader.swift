import AppKit

/// Fetches album art from the URL Spotify hands us.
///
/// This is the only network request HotDock ever makes, and only while the mini player is
/// switched on. Images are held in memory for the session and never written to disk, and the
/// cache is capped so a long listening session cannot grow it without bound.
final class ArtworkLoader: ObservableObject {

    @Published private(set) var image: NSImage?

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []
    private var currentURL: String?
    private var task: URLSessionDataTask?
    private let limit = 24

    func load(_ urlString: String?) {
        guard let urlString, !urlString.isEmpty else {
            currentURL = nil
            image = nil
            return
        }
        guard urlString != currentURL else { return }
        currentURL = urlString

        if let cached = cache[urlString] {
            image = cached
            return
        }
        image = nil

        guard let url = URL(string: urlString), url.scheme == "https" else { return }
        task?.cancel()
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let loaded = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.currentURL == urlString else { return }
                self.store(loaded, for: urlString)
                self.image = loaded
            }
        }
        task?.resume()
    }

    private func store(_ image: NSImage, for key: String) {
        if cache[key] == nil { order.append(key) }
        cache[key] = image
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
