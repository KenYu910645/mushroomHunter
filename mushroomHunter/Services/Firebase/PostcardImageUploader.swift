//
//  PostcardImageUploader.swift
//  mushroomHunter
//
//  Purpose:
//  - Repository/helper for postcard image crop + Firebase Storage upload flow.
//
//  Related flow:
//  - Postcard create/edit -> choose image -> crop -> upload -> store URL in postcard record.
//
//  Field access legend:
//  [R] Represent Read
//  [X] Represent dont care
//  [W] Represent write
//
//  Storage object (`postcards/{ownerId}/{filename}.jpg`):
//  [R] - `ownerId` path segment: Reads/validates owner id input before upload path creation.
//  [W] - `filename` path segment: Writes generated UUID filename for object key.
//  [W] - `binaryData`: Uploads encoded JPEG bytes to Firebase Storage.
//  [W] - `contentType`: Writes object metadata content type (`image/jpeg`).
//  [R] - `downloadURL`: Reads generated download URL after successful upload.
//  [W] - `delete`: Deletes object by URL during cleanup flow.
//
//  Local image preprocessing contract (not Firestore fields):
//  [R] - `requiredCropRect`: Reads fixed crop area (x:20, y:20, w:645, h:635) for validation/cropping.
//  [W] - `normalizedImage`: Writes normalized bitmap before crop/encode operations.
//
import Foundation
import FirebaseStorage
import UIKit

enum PostcardImageUploadError: LocalizedError {
    case unauthenticated
    case missingDownloadURL
    case invalidSnapshotSize
    case cropOutOfBounds
    case imageEncodeFailed

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Please sign in before uploading a postcard image."
        case .missingDownloadURL:
            return "Image uploaded, but failed to get a public download URL."
        case .invalidSnapshotSize:
            return "Image size error, Please upload postcard snapshot"
        case .cropOutOfBounds:
            return "Image is too small for postcard crop area. Please select another image."
        case .imageEncodeFailed:
            return "Failed to process image."
        }
    }
}

final class PostcardImageUploader {
    private let storage = Storage.storage()
    // Required original snapshot pixel width from Pikmin Bloom export.
    private let requiredSnapshotPixelWidth = 1023
    // Required original snapshot pixel height from Pikmin Bloom export.
    private let requiredSnapshotPixelHeight = 684
    // Fixed crop rectangle requested by product requirement.
    private let requiredCropRect = CGRect(x: 20, y: 20, width: 645, height: 635)
    // Default thumbnail edge size for browse-card rendering.
    private let defaultThumbnailPixelSize = AppConfig.Postcard.thumbnailPixelSize
    // Default thumbnail JPEG compression for smaller transfer size.
    private let defaultThumbnailCompressionQuality = AppConfig.Postcard.thumbnailCompressionQuality

    func cropSnapshotImage(_ image: UIImage) throws -> UIImage { // Handles cropSnapshotImage flow.
        let normalized = normalizedImage(image)
        guard let cgImage = normalized.cgImage else {
            throw PostcardImageUploadError.imageEncodeFailed
        }

        let isSnapshotSizeValid = cgImage.width == requiredSnapshotPixelWidth
            && cgImage.height == requiredSnapshotPixelHeight
        guard isSnapshotSizeValid else {
            throw PostcardImageUploadError.invalidSnapshotSize
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

    func prepareThumbnailJPEGData(
        from image: UIImage,
        edge: CGFloat? = nil,
        compressionQuality: CGFloat? = nil
    ) throws -> Data { // Handles thumbnail generation flow.
        let targetEdge = max(1, Int((edge ?? defaultThumbnailPixelSize).rounded()))
        let thumbnailImage = resizedSquareImage(from: image, edge: targetEdge)
        let quality = compressionQuality ?? defaultThumbnailCompressionQuality
        guard let data = thumbnailImage.jpegData(compressionQuality: quality) else {
            throw PostcardImageUploadError.imageEncodeFailed
        }
        return data
    }

    func uploadPostcardImage(data: Data, ownerId: String?) async throws -> URL { // Handles uploadPostcardImage flow.
        guard let owner = ownerId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !owner.isEmpty else {
            throw PostcardImageUploadError.unauthenticated
        }

        let filename = UUID().uuidString + ".jpg"
        let ref = storage.reference().child("postcards/\(owner)/\(filename)")
        return try await uploadImageData(data: data, ref: ref)
    }

    func uploadPostcardThumbnail(data: Data, ownerId: String?) async throws -> URL { // Handles uploadPostcardThumbnail flow.
        guard let owner = ownerId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !owner.isEmpty else {
            throw PostcardImageUploadError.unauthenticated
        }

        let filename = UUID().uuidString + "_thumb.jpg"
        let ref = storage.reference().child("postcards/\(owner)/\(filename)")
        return try await uploadImageData(data: data, ref: ref)
    }

    private func uploadImageData(data: Data, ref: StorageReference) async throws -> URL {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.cacheControl = "public,max-age=86400"

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

    func deleteUploadedImage(at url: URL) async { // Handles deleteUploadedImage flow.
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

    private func resizedSquareImage(from image: UIImage, edge: Int) -> UIImage {
        let normalized = normalizedImage(image)
        let targetSize = CGSize(width: edge, height: edge)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            let sourceSize = normalized.size
            guard sourceSize.width > 0, sourceSize.height > 0 else {
                normalized.draw(in: CGRect(origin: .zero, size: targetSize))
                return
            }

            let widthRatio = targetSize.width / sourceSize.width
            let heightRatio = targetSize.height / sourceSize.height
            let fillScale = max(widthRatio, heightRatio)
            let scaledWidth = sourceSize.width * fillScale
            let scaledHeight = sourceSize.height * fillScale
            let drawRect = CGRect(
                x: (targetSize.width - scaledWidth) * 0.5,
                y: (targetSize.height - scaledHeight) * 0.5,
                width: scaledWidth,
                height: scaledHeight
            )
            normalized.draw(in: drawRect)
        }
    }
}
