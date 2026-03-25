import Foundation
import Network

/// Monitors network connectivity and manages offline caching for critical data.
@MainActor
final class OfflineCacheService: ObservableObject {

    static let shared = OfflineCacheService()

    @Published var isOnline = true
    @Published var lastSyncDate: Date?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.tgcal.network-monitor")

    private init() {
        startMonitoring()
        loadLastSyncDate()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Cache Operations

    /// Caches layover tips for offline access.
    func cacheLayoverTips(_ tips: [LayoverTip], airportCode: String) {
        let key = "layover_tips_\(airportCode.uppercased())"
        saveToCache(tips, key: key)
    }

    func cachedLayoverTips(airportCode: String) -> [LayoverTip]? {
        let key = "layover_tips_\(airportCode.uppercased())"
        return loadFromCache(key: key)
    }

    /// Caches crew channels for offline browsing.
    func cacheChannels(_ channels: [CrewChannel]) {
        saveToCache(channels, key: "crew_channels")
    }

    func cachedChannels() -> [CrewChannel]? {
        loadFromCache(key: "crew_channels")
    }

    /// Caches channel messages for offline reading.
    func cacheMessages(_ messages: [CrewChannelMessage], channelId: UUID) {
        let key = "channel_messages_\(channelId.uuidString)"
        saveToCache(messages, key: key)
    }

    func cachedMessages(channelId: UUID) -> [CrewChannelMessage]? {
        let key = "channel_messages_\(channelId.uuidString)"
        return loadFromCache(key: key)
    }

    /// Caches swap listings for offline viewing.
    func cacheSwapListings(_ listings: [SwapListing]) {
        saveToCache(listings, key: "swap_listings")
    }

    func cachedSwapListings() -> [SwapListing]? {
        loadFromCache(key: "swap_listings")
    }

    /// Records the last successful sync time.
    func recordSync() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "tgcal_last_sync")
    }

    var lastSyncText: String {
        guard let lastSyncDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncDate, relativeTo: Date())
    }

    // MARK: - Generic Cache Helpers

    private func saveToCache<T: Encodable>(_ value: T, key: String) {
        do {
            let url = try cacheFileURL(key: key)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private func loadFromCache<T: Decodable>(key: String) -> T? {
        do {
            let url = try cacheFileURL(key: key)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func cacheFileURL(key: String) throws -> URL {
        let cacheDir = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = cacheDir.appendingPathComponent("TGCal", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: "tgcal_last_sync") as? Date
    }

    /// Clears all cached data.
    func clearCache() {
        do {
            let cacheDir = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let directory = cacheDir.appendingPathComponent("TGCal", isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            return
        }
    }
}
