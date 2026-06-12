import UIKit
import ImageIO

/// Decodes and downsamples recipe card thumbnails once instead of decoding
/// the full stored JPEG on every list render. At a few hundred recipes with
/// photos, full-size decodes during scroll are the first thing that hurts.
final class RecipeThumbnailCache {
    static let shared = RecipeThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 400
    }

    /// `data.count` in the key is a cheap change-detector: replacing a photo
    /// virtually always changes the byte count, and a stale thumbnail for one
    /// render pass is an acceptable worst case.
    func thumbnail(for data: Data, recipeID: UUID, maxPixelSize: CGFloat = 700) -> UIImage? {
        let key = "\(recipeID.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }
}
