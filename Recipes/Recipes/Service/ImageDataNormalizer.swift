import UIKit
import ImageIO

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
        guard maxDimension.isFinite, maxDimension > 0,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }

        let pixelWidth = width.doubleValue
        let pixelHeight = height.doubleValue
        guard pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= 50_000, pixelHeight <= 50_000,
              pixelWidth * pixelHeight <= 120_000_000
        else { return nil }

        // ImageIO creates the thumbnail while decoding, avoiding a full-size
        // bitmap allocation for high-resolution or malicious compressed files.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension.rounded(.up)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let resized = UIImage(cgImage: thumbnail)
        guard let resizedData = resized.jpegData(compressionQuality: compressionQuality) else { return nil }
        // When the source was already within bounds, avoid replacing it with
        // a larger, double-compressed JPEG. A source above the bound must use
        // the thumbnail even when its original encoding happened to be tiny.
        let wasDownsampled = max(pixelWidth, pixelHeight) > Double(maxDimension)
        return wasDownsampled || resizedData.count < data.count ? resizedData : data
    }
}
