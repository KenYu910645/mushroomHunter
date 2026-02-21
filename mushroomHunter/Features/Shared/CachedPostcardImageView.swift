//
//  CachedPostcardImageView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides cache-first postcard image rendering with shared memory+disk cache.
//
import SwiftUI
import UIKit
import CryptoKit

/// Shared cache service for postcard image URLs.
final class PostcardImageCache {
    /// Singleton cache entry point used by postcard views.
    static let shared = PostcardImageCache()

    /// In-memory image cache for instant re-render on repeated views.
    private let memoryCache = NSCache<NSString, UIImage>()
    /// File manager used for disk cache reads/writes.
    private let fileManager = FileManager.default
    /// URL session used for cache-aware network image requests.
    private let session: URLSession
    /// Serial queue used for disk I/O work.
    private let ioQueue = DispatchQueue(label: "com.kenyu.mushroomhunter.postcard-image-cache-io", qos: .utility)
    /// Serial queue used for in-flight request bookkeeping.
    private let stateQueue = DispatchQueue(label: "com.kenyu.mushroomhunter.postcard-image-cache-state")
    /// Completion callback fan-out for URLs currently downloading.
    private var callbacksByURL: [URL: [(UIImage?) -> Void]] = [:]
    /// Cache folder URL under app caches directory.
    private let cacheDirectoryURL: URL
    /// Whether the disk cache directory was created successfully.
    private let isCacheDirectoryReady: Bool
    /// Maximum age for disk-cached image files before eviction.
    private let diskCacheMaxAgeSeconds = AppConfig.Postcard.imageDiskCacheMaxAgeSeconds
    /// Maximum disk cache folder size before prune is triggered.
    private let diskCacheMaxBytes = AppConfig.Postcard.imageDiskCacheMaxBytes
    /// Target ratio used after prune to avoid pruning on every write.
    private let diskCachePruneTargetRatio = AppConfig.Postcard.imageDiskCachePruneTargetRatio

    /// Initializes cache storage and request session defaults.
    private init() {
        memoryCache.countLimit = AppConfig.Postcard.imageMemoryCacheEntryLimit

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.requestCachePolicy = .returnCacheDataElseLoad
        sessionConfiguration.timeoutIntervalForRequest = 20
        sessionConfiguration.timeoutIntervalForResource = 30
        session = URLSession(configuration: sessionConfiguration)

        let rootCacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectoryURL = rootCacheDirectory.appendingPathComponent("PostcardImageCache", isDirectory: true)

        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            isCacheDirectoryReady = true
            ioQueue.async { [weak self] in
                self?.pruneDiskCacheIfNeeded(isForcedByCapacity: true)
            }
        } catch {
            isCacheDirectoryReady = false
        }
    }

    /// Loads an image by URL with memory -> disk -> network fallback.
    /// - Parameter url: Postcard image URL string parsed as URL.
    /// - Returns: Cached or downloaded image, or nil when unavailable.
    func loadImage(from url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loadImage(from: url) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// Callback-based image loader used by async bridge and dedupe logic.
    /// - Parameters:
    ///   - url: Image URL to load.
    ///   - completion: Callback invoked on main queue with loaded image or nil.
    private func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = url.absoluteString as NSString
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            completion(cachedImage)
            return
        }

        stateQueue.async { [weak self] in
            guard let self else { return }

            if self.callbacksByURL[url] != nil {
                self.callbacksByURL[url]?.append(completion)
                return
            }

            self.callbacksByURL[url] = [completion]

            self.ioQueue.async { [weak self] in
                guard let self else { return }

                if let diskImage = self.loadImageFromDisk(url: url) {
                    self.memoryCache.setObject(diskImage, forKey: cacheKey)
                    self.finishCallbacks(for: url, image: diskImage)
                    return
                }

                self.fetchImageFromNetwork(url: url)
            }
        }
    }

    /// Completes all waiting callbacks for one URL request.
    /// - Parameters:
    ///   - url: Requested URL key.
    ///   - image: Result image payload for all listeners.
    private func finishCallbacks(for url: URL, image: UIImage?) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let callbacks = self.callbacksByURL.removeValue(forKey: url) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { callback in
                    callback(image)
                }
            }
        }
    }

    /// Performs network fetch and persists response into memory and disk caches.
    /// - Parameter url: Image URL to request.
    private func fetchImageFromNetwork(url: URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }

            guard let data, let image = UIImage(data: data) else {
                self.finishCallbacks(for: url, image: nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                let isHTTPStatusSuccessful = (200...299).contains(httpResponse.statusCode)
                guard isHTTPStatusSuccessful else {
                    self.finishCallbacks(for: url, image: nil)
                    return
                }
            }

            self.memoryCache.setObject(image, forKey: url.absoluteString as NSString)
            self.saveImageDataToDisk(data: data, url: url)
            self.finishCallbacks(for: url, image: image)
        }.resume()
    }

    /// Reads one cached image from disk when not expired.
    /// - Parameter url: Image URL cache key.
    /// - Returns: Decoded image from disk cache, or nil.
    private func loadImageFromDisk(url: URL) -> UIImage? {
        guard isCacheDirectoryReady else { return nil }
        let fileURL = diskFileURL(for: url)

        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let modifiedAt = attrs[.modificationDate] as? Date {
                let isEntryExpired = Date().timeIntervalSince(modifiedAt) > diskCacheMaxAgeSeconds
                if isEntryExpired {
                    try? fileManager.removeItem(at: fileURL)
                    return nil
                }
            }

            let data = try Data(contentsOf: fileURL)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// Writes downloaded image bytes into disk cache.
    /// - Parameters:
    ///   - data: Raw image data from network.
    ///   - url: Image URL cache key.
    private func saveImageDataToDisk(data: Data, url: URL) {
        guard isCacheDirectoryReady else { return }
        let fileURL = diskFileURL(for: url)
        do {
            try data.write(to: fileURL, options: [.atomic])
            pruneDiskCacheIfNeeded(isForcedByCapacity: false)
        } catch {
            // Best effort cache write.
        }
    }

    /// Prunes disk cache by expiration and total bytes threshold.
    /// - Parameter isForcedByCapacity: `true` to run size pruning regardless of current size read.
    private func pruneDiskCacheIfNeeded(isForcedByCapacity: Bool) {
        guard isCacheDirectoryReady else { return }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var fileRecords: [(url: URL, modifiedAt: Date, byteSize: Int)] = []
        fileRecords.reserveCapacity(contents.count)
        let now = Date()

        for fileURL in contents {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            let isRegularFile = values.isRegularFile ?? false
            guard isRegularFile else { continue }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            let byteSize = values.fileSize ?? 0
            let isEntryExpired = now.timeIntervalSince(modifiedAt) > diskCacheMaxAgeSeconds
            if isEntryExpired {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            fileRecords.append((fileURL, modifiedAt, byteSize))
        }

        let totalBytes = fileRecords.reduce(0) { partialResult, record in
            partialResult + record.byteSize
        }
        let isOverDiskLimit = totalBytes > diskCacheMaxBytes
        guard isForcedByCapacity || isOverDiskLimit else { return }

        let pruneTargetBytes = Int(Double(diskCacheMaxBytes) * diskCachePruneTargetRatio)
        var currentBytes = totalBytes
        let sortedOldestFirst = fileRecords.sorted { lhs, rhs in
            lhs.modifiedAt < rhs.modifiedAt
        }

        for record in sortedOldestFirst where currentBytes > pruneTargetBytes {
            try? fileManager.removeItem(at: record.url)
            currentBytes -= record.byteSize
        }
    }

    /// Returns the deterministic cache file path for one image URL.
    /// - Parameter url: URL to hash as filename.
    /// - Returns: File path in cache directory.
    private func diskFileURL(for url: URL) -> URL {
        let cacheKey = cacheKeyForURL(url)
        return cacheDirectoryURL.appendingPathComponent(cacheKey).appendingPathExtension("img")
    }

    /// Creates a stable SHA256 key for URL-based cache files.
    /// - Parameter url: URL to hash.
    /// - Returns: Lowercase hex string.
    private func cacheKeyForURL(_ url: URL) -> String {
        let inputData = Data(url.absoluteString.utf8)
        let digest = SHA256.hash(data: inputData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// View wrapper that renders postcard images using `PostcardImageCache`.
struct CachedPostcardImageView: View {
    /// Remote image URL used as cache key and fetch source.
    let imageURL: URL
    /// SF Symbol shown when image load fails.
    let fallbackSystemImageName: String
    /// Font used by fallback icon.
    let fallbackIconFont: Font

    /// Decoded image currently shown in the UI.
    @State private var renderedImage: UIImage?
    /// Indicates whether the image load request is currently running.
    @State private var isImageLoading: Bool = false
    /// Indicates whether the most recent load attempt failed.
    @State private var isImageLoadFailed: Bool = false

    /// Cache-backed postcard image rendering.
    var body: some View {
        Group {
            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFill()
            } else if isImageLoading {
                ProgressView()
            } else {
                Image(systemName: fallbackSystemImageName)
                    .font(fallbackIconFont)
                    .foregroundStyle(.secondary)
                    .opacity(isImageLoadFailed ? 1 : 0.75)
            }
        }
        .task(id: imageURL.absoluteString) {
            await loadImage()
        }
    }

    /// Executes cache-first image loading for current URL.
    private func loadImage() async {
        guard renderedImage == nil else { return }
        isImageLoading = true
        isImageLoadFailed = false

        let image = await PostcardImageCache.shared.loadImage(from: imageURL)
        renderedImage = image
        isImageLoadFailed = image == nil
        isImageLoading = false
    }
}
