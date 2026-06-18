import UIKit

/// Downscales and re-encodes photo data before it is persisted so
/// multi-megabyte camera images don't bloat the data store or stall
/// list scrolling when thumbnails are decoded.
enum ImageDataNormalizer {
    /// Returns resized JPEG data, or nil when the input is not a decodable image.
    static func normalizedJPEGData(
        from data: Data,
        maxDimension: CGFloat = 2000,
        compressionQuality: CGFloat = 0.85
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > 0 else { return data }
        let scale = min(1, maxDimension / largestSide)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: compressionQuality) ?? data
    }
}
