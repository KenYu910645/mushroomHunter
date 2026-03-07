//
//  RoomCache.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared Mushroom cache for Codable payloads (memory + disk).
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

/// Shared actor that manages Mushroom cache reads and writes.
actor RoomCache {
    /// Shared singleton entry point.
    static let shared = RoomCache()

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
        rootDirectoryURL = cachesRootURL.appendingPathComponent("RoomCache", isDirectory: true)
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

/// Shared dirty-bit store used to force backend refresh when cached datasets are invalidated.
actor CacheDirtyBitStore {
    /// Singleton entry point used by feature view models and push-event handlers.
    static let shared = CacheDirtyBitStore()

    /// UserDefaults key used to persist dirty-key set across app relaunches.
    private let dirtyKeysStorageKey: String = "mh.cache.dirty.keys.v1"
    /// UserDefaults bridge used for dirty-key persistence.
    private let defaults = UserDefaults.standard
    /// Current dirty keys tracked in memory for fast lookups.
    private var dirtyKeys: Set<String>

    /// Initializes in-memory dirty keys from persisted storage.
    init() {
        let storedDirtyKeys = defaults.stringArray(forKey: dirtyKeysStorageKey) ?? []
        dirtyKeys = Set(storedDirtyKeys)
    }

    /// Marks one logical cache key as dirty.
    /// - Parameter key: Namespaced dirty key to set.
    func markDirty(key: String) {
        dirtyKeys.insert(key)
        persistDirtyKeys()
    }

    /// Clears one logical cache key dirty flag.
    /// - Parameter key: Namespaced dirty key to clear.
    func clearDirty(key: String) {
        dirtyKeys.remove(key)
        persistDirtyKeys()
    }

    /// Checks whether one logical cache key is dirty.
    /// - Parameter key: Namespaced dirty key to query.
    /// - Returns: `true` when key currently requires forced backend refresh.
    func isDirty(key: String) -> Bool {
        dirtyKeys.contains(key)
    }

    /// Marks mushroom browse dataset as dirty.
    func markMushroomBrowseDirty() {
        markDirty(key: mushroomBrowseDirtyKey)
    }

    /// Clears mushroom browse dataset dirty flag.
    func clearMushroomBrowseDirty() {
        clearDirty(key: mushroomBrowseDirtyKey)
    }

    /// Checks mushroom browse dataset dirty status.
    /// - Returns: `true` when mushroom browse should bypass cache and fetch backend.
    func isMushroomBrowseDirty() -> Bool {
        isDirty(key: mushroomBrowseDirtyKey)
    }

    /// Marks one mushroom room-detail dataset as dirty.
    /// - Parameter roomId: Room id whose detail cache must be refreshed.
    func markMushroomRoomDirty(roomId: String) {
        markDirty(key: mushroomRoomDirtyKey(roomId: roomId))
    }

    /// Clears one mushroom room-detail dirty flag.
    /// - Parameter roomId: Room id whose detail cache dirty flag should be removed.
    func clearMushroomRoomDirty(roomId: String) {
        clearDirty(key: mushroomRoomDirtyKey(roomId: roomId))
    }

    /// Checks one mushroom room-detail dirty flag.
    /// - Parameter roomId: Room id to query.
    /// - Returns: `true` when room detail should force backend refresh.
    func isMushroomRoomDirty(roomId: String) -> Bool {
        isDirty(key: mushroomRoomDirtyKey(roomId: roomId))
    }

    /// Marks postcard browse dataset as dirty.
    func markPostcardBrowseDirty() {
        markDirty(key: postcardBrowseDirtyKey)
    }

    /// Clears postcard browse dataset dirty flag.
    func clearPostcardBrowseDirty() {
        clearDirty(key: postcardBrowseDirtyKey)
    }

    /// Checks postcard browse dataset dirty status.
    /// - Returns: `true` when postcard browse should force backend refresh.
    func isPostcardBrowseDirty() -> Bool {
        isDirty(key: postcardBrowseDirtyKey)
    }

    /// Marks one postcard-detail dataset as dirty.
    /// - Parameter postcardId: Postcard id whose detail should force backend refresh.
    func markPostcardDetailDirty(postcardId: String) {
        markDirty(key: postcardDetailDirtyKey(postcardId: postcardId))
    }

    /// Clears one postcard-detail dirty flag.
    /// - Parameter postcardId: Postcard id whose detail dirty flag should be removed.
    func clearPostcardDetailDirty(postcardId: String) {
        clearDirty(key: postcardDetailDirtyKey(postcardId: postcardId))
    }

    /// Checks one postcard-detail dirty flag.
    /// - Parameter postcardId: Postcard id to query.
    /// - Returns: `true` when postcard detail should bypass stale state and refetch.
    func isPostcardDetailDirty(postcardId: String) -> Bool {
        isDirty(key: postcardDetailDirtyKey(postcardId: postcardId))
    }

    /// Persists in-memory dirty keys into UserDefaults.
    private func persistDirtyKeys() {
        defaults.set(Array(dirtyKeys), forKey: dirtyKeysStorageKey)
    }

    /// Stable dirty key for mushroom browse listings.
    private var mushroomBrowseDirtyKey: String {
        "dirty.mushroom.browse.listings.v1"
    }

    /// Stable dirty key for one mushroom room detail.
    /// - Parameter roomId: Room id namespace suffix.
    /// - Returns: Dirty key string.
    private func mushroomRoomDirtyKey(roomId: String) -> String {
        "dirty.mushroom.room.detail.\(roomId)"
    }

    /// Stable dirty key for postcard browse listings.
    private var postcardBrowseDirtyKey: String {
        "dirty.postcard.browse.listings.v1"
    }

    /// Stable dirty key for one postcard detail.
    /// - Parameter postcardId: Postcard id namespace suffix.
    /// - Returns: Dirty key string.
    private func postcardDetailDirtyKey(postcardId: String) -> String {
        "dirty.postcard.detail.\(postcardId)"
    }
}
