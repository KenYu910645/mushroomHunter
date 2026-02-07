import Foundation
import FirebaseStorage

final class FirebasePostcardImageUploader {
    private let storage = Storage.storage()

    func uploadPostcardImage(data: Data, ownerId: String?) async throws -> URL {
        let owner = (ownerId?.isEmpty == false) ? ownerId! : "anonymous"
        let filename = UUID().uuidString + ".jpg"
        let ref = storage.reference().child("postcards/\(owner)/\(filename)")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: URLError(.badURL))
                }
            }
        }
    }
}
