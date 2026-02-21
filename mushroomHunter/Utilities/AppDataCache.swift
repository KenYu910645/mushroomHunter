//
//  AppDataCache.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared app-level cache for Codable payloads (memory + disk).
//
import Foundation
import CryptoKit

/// Codable wrapper that stores payload plus cache write timestamp.
struct CachedPayload<Value: Codable>: Codable {
    /// Timestamp when this payload was written into cache.
    let cachedAt: Date
    /// Cached business payload value.
    let value: Value
}

/// Shared actor that manages app-level data cache reads and writes.
actor AppDataCache {
    /// Shared singleton entry point.
    static let shared = AppDataCache()

    /// In-memory raw data cache keyed by logical cache key.
    private var memoryDataByKey: [String: Data] = [:]
    /// File manager used for disk cache operations.
    private let fileManager = FileManager.default
    /// Root cache directory under app caches folder.
    private let rootDirectoryURL: URL
    /// Flag that indicates whether root cache directory exists and is writable.
    private let isRootDirectoryReady: Bool

    /// Initializes cache root directory location.
    init() {
        let fallbackRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let cachesRootURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fallbackRootURL
        rootDirectoryURL = cachesRootURL.appendingPathComponent("AppDataCache", isDirectory: true)
        do {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
            isRootDirectoryReady = true
        } catch {
            isRootDirectoryReady = false
        }
    }

    /// Loads one cached payload from memory or disk.
    /// - Parameters:
    ///   - key: Logical cache key.
    ///   - type: Decoding target type.
    /// - Returns: Cached wrapper, or `nil` when missing/invalid.
    func load<Value: Codable>(key: String, as type: Value.Type) async -> CachedPayload<Value>? {
        if let memoryData = memoryDataByKey[key] {
            if let decodedPayload = await decodePayload(data: memoryData, as: type) {
                return decodedPayload
            }
            memoryDataByKey.removeValue(forKey: key)
        }

        guard isRootDirectoryReady else { return nil }
        let targetFileURL = fileURL(for: key)
        guard fileManager.fileExists(atPath: targetFileURL.path) else { return nil }

        do {
            let diskData = try Data(contentsOf: targetFileURL)
            guard let decodedPayload = await decodePayload(data: diskData, as: type) else {
                try? fileManager.removeItem(at: targetFileURL)
                return nil
            }
            memoryDataByKey[key] = diskData
            return decodedPayload
        } catch {
            return nil
        }
    }

    /// Saves one payload into memory and disk caches.
    /// - Parameters:
    ///   - value: Payload value to persist.
    ///   - key: Logical cache key.
    func save<Value: Codable>(_ value: Value, key: String) async {
        let wrappedPayload = CachedPayload(cachedAt: Date(), value: value)
        let encodedData: Data
        do {
            encodedData = try await MainActor.run {
                try JSONEncoder().encode(wrappedPayload)
            }
        } catch {
            return
        }

        memoryDataByKey[key] = encodedData
        guard isRootDirectoryReady else { return }

        let targetFileURL = fileURL(for: key)
        do {
            try encodedData.write(to: targetFileURL, options: [.atomic])
        } catch {
            // Best-effort cache write.
        }
    }

    /// Removes one cached payload from memory and disk.
    /// - Parameter key: Logical cache key to delete.
    func remove(key: String) {
        memoryDataByKey.removeValue(forKey: key)
        guard isRootDirectoryReady else { return }
        let targetFileURL = fileURL(for: key)
        try? fileManager.removeItem(at: targetFileURL)
    }

    /// Decodes cached envelope from raw JSON bytes.
    /// - Parameters:
    ///   - data: Raw cache data.
    ///   - type: Payload decoding type.
    /// - Returns: Decoded payload wrapper or `nil`.
    private func decodePayload<Value: Codable>(data: Data, as type: Value.Type) async -> CachedPayload<Value>? {
        try? await MainActor.run {
            try JSONDecoder().decode(CachedPayload<Value>.self, from: data)
        }
    }

    /// Creates deterministic file URL for one logical key.
    /// - Parameter key: Logical cache key.
    /// - Returns: Disk path under root cache directory.
    private func fileURL(for key: String) -> URL {
        let hashedKey = hash(key: key)
        return rootDirectoryURL.appendingPathComponent(hashedKey).appendingPathExtension("json")
    }

    /// Hashes one key to an ASCII-safe filename.
    /// - Parameter key: Raw logical key.
    /// - Returns: SHA256 lowercase hex digest.
    private func hash(key: String) -> String {
        let inputData = Data(key.utf8)
        let digest = SHA256.hash(data: inputData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
