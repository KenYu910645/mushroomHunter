import Foundation
import FirebaseStorage
import UIKit

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

    func prepareUploadJPEGData(
        from image: UIImage,
        maxLongEdge: CGFloat = 640,
        compressionQuality: CGFloat = 0.82
    ) -> Data? {
        let normalized = resizedImageIfNeeded(image, maxLongEdge: maxLongEdge)
        return normalized.jpegData(compressionQuality: compressionQuality)
    }

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

    private func resizedImageIfNeeded(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }

        let scaleRatio = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: max(1, floor(pixelWidth * scaleRatio)),
            height: max(1, floor(pixelHeight * scaleRatio))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
