import Foundation
import FirebaseStorage
import UIKit

enum PostcardImageUploadError: LocalizedError {
    case unauthenticated
    case missingDownloadURL
    case cropOutOfBounds
    case imageEncodeFailed

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Please sign in before uploading a postcard image."
        case .missingDownloadURL:
            return "Image uploaded, but failed to get a public download URL."
        case .cropOutOfBounds:
            return "Image is too small for postcard crop area. Please select another image."
        case .imageEncodeFailed:
            return "Failed to process image."
        }
    }
}

final class FirebasePostcardImageUploader {
    private let storage = Storage.storage()
    // Fixed crop rectangle requested by product requirement.
    private let requiredCropRect = CGRect(x: 20, y: 20, width: 645, height: 635)

    func cropSnapshotImage(_ image: UIImage) throws -> UIImage {
        let normalized = normalizedImage(image)
        guard let cgImage = normalized.cgImage else {
            throw PostcardImageUploadError.imageEncodeFailed
        }

        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard imageRect.contains(requiredCropRect) else {
            throw PostcardImageUploadError.cropOutOfBounds
        }

        guard let cropped = cgImage.cropping(to: requiredCropRect) else {
            throw PostcardImageUploadError.imageEncodeFailed
        }
        return UIImage(cgImage: cropped)
    }

    func prepareUploadJPEGData(
        from image: UIImage,
        compressionQuality: CGFloat = 0.82
    ) throws -> Data {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw PostcardImageUploadError.imageEncodeFailed
        }
        return data
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

    func deleteUploadedImage(at url: URL) async {
        do {
            try await storage.reference(forURL: url.absoluteString).delete()
        } catch {
            // Best effort cleanup only.
        }
    }

    private func normalizedImage(_ image: UIImage) -> UIImage {
        let pixelWidth = max(1, Int(image.size.width * image.scale))
        let pixelHeight = max(1, Int(image.size.height * image.scale))
        let targetSize = CGSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
