import Foundation
import UIKit

// MARK: - Webcam Image Cache

/// High-performance memory + disk cache for webcam images
/// Features: request deduplication, thumbnail downsampling, stale-while-revalidate
final class WebcamImageCache {
    static let shared = WebcamImageCache()

    // Memory cache (fast access)
    private let memoryCache = NSCache<NSString, CachedImage>()

    // In-flight request deduplication to avoid duplicate network calls
    private var inFlightRequests: [String: Task<CachedImageResult?, Never>] = [:]
    private let requestLock = NSLock()

    // Dedicated URLSession with connection pooling
    private let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = TimeInterval(AppConstants.Timeout.webcam)
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    // Disk cache directory
    private let diskCacheURL: URL

    // Cache version - increment to invalidate old cache on app update
    private static let cacheVersion = 2

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = cacheDir.appendingPathComponent("WebcamImages_v\(Self.cacheVersion)", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = AppConstants.CacheLimits.webcamMemoryCount
        memoryCache.totalCostLimit = AppConstants.CacheLimits.webcamMemoryBytes

        // Clean old cache versions
        Task {
            await cleanOldCacheVersions()
            await cleanOldDiskCache()
        }
    }

    /// Remove old cache version directories
    private func cleanOldCacheVersions() async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        guard let contents = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }

        for url in contents {
            let name = url.lastPathComponent
            // Remove old WebcamImages directories (without version or old versions)
            if name.hasPrefix("WebcamImages") && name != "WebcamImages_v\(Self.cacheVersion)" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Public API

    /// Load full-size image with caching (for detail view)
    func loadImage(from urlString: String, isHistory: Bool = false) async -> CachedImageResult? {
        let cacheKey = cacheKey(for: urlString)
        let ttl: TimeInterval = isHistory ? 3600 : 60

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString),
           !cached.isExpired(ttl: ttl) {
            return CachedImageResult(data: cached.data, size: cached.size, timestamp: cached.timestamp, fromCache: true)
        }

        // Check disk cache
        if let cached = loadFromDisk(key: cacheKey, ttl: ttl) {
            memoryCache.setObject(cached, forKey: cacheKey as NSString, cost: cached.data.count)
            return CachedImageResult(data: cached.data, size: cached.size, timestamp: cached.timestamp, fromCache: true)
        }

        // Fetch with deduplication
        return await fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: false)
    }

    /// Load thumbnail for map markers - optimized for speed
    func loadThumbnail(from urlString: String) async -> Data? {
        let result = await loadThumbnailWithTimestamp(from: urlString)
        return result?.data
    }

    /// Load thumbnail with timestamp info for map markers
    func loadThumbnailWithTimestamp(from urlString: String) async -> (data: Data, timestamp: Date?)? {
        let cacheKey = cacheKey(for: urlString)
        let ttl: TimeInterval = AppConstants.CacheTTL.webcamThumbnail

        // Fast path: check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            // Return immediately, refresh in background if stale
            if cached.isExpired(ttl: ttl) {
                Task(priority: .background) {
                    _ = await self.fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: true)
                }
            }
            return (cached.data, cached.timestamp)
        }

        // Check disk cache
        if let cached = loadFromDisk(key: cacheKey, ttl: 86400) {
            memoryCache.setObject(cached, forKey: cacheKey as NSString, cost: cached.data.count)
            if cached.isExpired(ttl: ttl) {
                Task(priority: .background) {
                    _ = await self.fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: true)
                }
            }
            return (cached.data, cached.timestamp)
        }

        // Fetch with deduplication and downsampling
        if let result = await fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: true) {
            return (result.data, result.timestamp)
        }
        return nil
    }

    /// Prefetch thumbnails for visible webcams
    func prefetchImages(for webcams: [Webcam]) {
        Task(priority: .utility) {
            let prefetchList = Array(webcams.prefix(AppConstants.CacheLimits.webcamPrefetchCount))
            let batchSize = AppConstants.CacheLimits.webcamPrefetchBatchSize

            for batch in stride(from: 0, to: prefetchList.count, by: batchSize) {
                let end = min(batch + batchSize, prefetchList.count)
                await withTaskGroup(of: Void.self) { group in
                    for webcam in prefetchList[batch..<end] {
                        group.addTask {
                            let url = WebcamService.shared.thumbnailImageUrl(for: webcam)
                            _ = await self.loadThumbnail(from: url)
                        }
                    }
                }
            }
        }
    }

    /// Force refresh (bypass cache)
    func forceRefresh(urlString: String) async -> CachedImageResult? {
        let cacheKey = cacheKey(for: urlString)
        memoryCache.removeObject(forKey: cacheKey as NSString)
        removeFromDisk(key: cacheKey)
        return await fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: false)
    }

    /// Fetch fresh thumbnail from network (keeps existing cache intact if fetch fails)
    func fetchFreshThumbnail(from urlString: String) async -> (data: Data, timestamp: Date?)? {
        let cacheKey = cacheKey(for: urlString)
        guard let result = await fetchDeduplicated(urlString: urlString, cacheKey: cacheKey, downsample: true) else { return nil }
        return (result.data, result.timestamp)
    }

    /// Clear all caches
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: - Private Methods

    private func cacheKey(for urlString: String) -> String {
        var cleanUrl = urlString
        // Remove cache buster parameters
        if let range = cleanUrl.range(of: "&_=") {
            cleanUrl = String(cleanUrl[..<range.lowerBound])
        }
        // Use SHA256 hash for collision-resistant keys
        guard let data = cleanUrl.data(using: .utf8) else {
            return String(urlString.hashValue)
        }
        // Simple hash: XOR all bytes in groups to create a unique fingerprint
        var hash: [UInt8] = Array(repeating: 0, count: 32)
        for (i, byte) in data.enumerated() {
            hash[i % 32] ^= byte
            hash[(i + 7) % 32] = hash[(i + 7) % 32] &+ byte
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Deduplicated fetch - prevents multiple simultaneous requests for the same URL
    private func fetchDeduplicated(urlString: String, cacheKey: String, downsample: Bool) async -> CachedImageResult? {
        // Check if request is already in-flight
        requestLock.lock()
        if let existingTask = inFlightRequests[cacheKey] {
            requestLock.unlock()
            return await existingTask.value
        }

        // Create new task
        let task = Task<CachedImageResult?, Never> {
            await self.fetchAndCache(urlString: urlString, cacheKey: cacheKey, downsample: downsample)
        }
        inFlightRequests[cacheKey] = task
        requestLock.unlock()

        // Wait for result
        let result = await task.value

        // Clean up
        requestLock.lock()
        inFlightRequests.removeValue(forKey: cacheKey)
        requestLock.unlock()

        return result
    }

    private func fetchAndCache(urlString: String, cacheKey: String, downsample: Bool) async -> CachedImageResult? {
        guard let url = URL(string: urlString) else { return nil }

        // Use shorter timeout for thumbnails (map markers)
        let timeout = downsample ? AppConstants.Timeout.webcamThumbnail : AppConstants.Timeout.webcam

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            // Always fetch from network, not URLSession cache (we have our own cache)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await imageSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Downsample if needed (for thumbnails)
            let finalData: Data
            let finalSize: CGSize
            if downsample, let downsampled = Self.downsample(data: data) {
                finalData = downsampled
                finalSize = CGSize(width: 400, height: 300) // Approximate
            } else if let uiImage = UIImage(data: data) {
                finalData = data
                finalSize = uiImage.size
            } else {
                return nil
            }

            // Parse timestamp header
            var timestamp: Date? = nil
            if let timestampStr = httpResponse.value(forHTTPHeaderField: "X-Image-Timestamp"),
               let ts = Double(timestampStr) {
                timestamp = Date(timeIntervalSince1970: ts)
            }

            // Cache the processed image
            let cached = CachedImage(data: finalData, size: finalSize, timestamp: timestamp, fetchedAt: Date())
            memoryCache.setObject(cached, forKey: cacheKey as NSString, cost: finalData.count)
            saveToDisk(cached: cached, key: cacheKey)

            return CachedImageResult(data: finalData, size: finalSize, timestamp: timestamp, fromCache: false)
        } catch {
            return nil
        }
    }

    // MARK: - Image Downsampling

    static func downsample(data: Data, maxDimension: CGFloat = 400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }

    // MARK: - Disk Cache

    private func diskPath(for key: String) -> URL {
        let safeKey = String(key.prefix(80)).replacingOccurrences(of: "/", with: "_")
        return diskCacheURL.appendingPathComponent(safeKey)
    }

    private func saveToDisk(cached: CachedImage, key: String) {
        let path = diskPath(for: key)
        do {
            let encoded = try JSONEncoder().encode(cached)
            try encoded.write(to: path)
        } catch {
            // Ignore disk write errors
        }
    }

    private func loadFromDisk(key: String, ttl: TimeInterval) -> CachedImage? {
        let path = diskPath(for: key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        do {
            let data = try Data(contentsOf: path)
            let cached = try JSONDecoder().decode(CachedImage.self, from: data)

            if cached.isExpired(ttl: ttl) {
                try? FileManager.default.removeItem(at: path)
                return nil
            }
            return cached
        } catch {
            return nil
        }
    }

    private func removeFromDisk(key: String) {
        let path = diskPath(for: key)
        try? FileManager.default.removeItem(at: path)
    }

    private func cleanOldDiskCache() async {
        let maxAge: TimeInterval = 24 * 3600

        guard let files = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        for fileURL in files {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let creationDate = attributes[.creationDate] as? Date else {
                continue
            }

            if Date().timeIntervalSince(creationDate) > maxAge {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Cache Models

final class CachedImage: NSObject, Codable {
    let data: Data
    let width: CGFloat
    let height: CGFloat
    let timestamp: Date?
    let fetchedAt: Date

    var size: CGSize { CGSize(width: width, height: height) }

    init(data: Data, size: CGSize, timestamp: Date?, fetchedAt: Date) {
        self.data = data
        self.width = size.width
        self.height = size.height
        self.timestamp = timestamp
        self.fetchedAt = fetchedAt
    }

    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) > ttl
    }

    // Codable
    enum CodingKeys: String, CodingKey {
        case data, width, height, timestamp, fetchedAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(Data.self, forKey: .data)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}

struct CachedImageResult {
    let data: Data
    let size: CGSize
    let timestamp: Date?
    let fromCache: Bool

    var isPanoramic: Bool {
        size.width > size.height * 2
    }
}
