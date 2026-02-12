import Foundation
import FirebaseStorage

enum PostcardImageUploadError: LocalizedError {
    case unauthenticated
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Please sign in before uploading a postcard image."
        case .missingDownloadURL:
            return "Image uploaded, but failed to get a public download URL."
        }
    }
}

final class FirebasePostcardImageUploader {
    private let storage = Storage.storage()

    func uploadPostcardImage(data: Data, ownerId: String?) async throws -> URL {
        guard let owner = ownerId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !owner.isEmpty else {
            throw PostcardImageUploadError.unauthenticated
        }

        let filename = UUID().uuidString + ".jpg"
        let ref = storage.reference().child("postcards/\(owner)/\(filename)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)

        // Some buckets can return transient "object does not exist" immediately after upload.
        for attempt in 0..<2 {
            do {
                return try await ref.downloadURL()
            } catch {
                if attempt == 1 { throw error }
                try await Task.sleep(nanoseconds: 600_000_000)
            }
        }

        throw PostcardImageUploadError.missingDownloadURL
    }
}
