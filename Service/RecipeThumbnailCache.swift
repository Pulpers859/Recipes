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

    /// Keys on a cheap content fingerprint (byte count + a hash of the head and
    /// tail bytes) rather than byte count alone, so replacing a photo with a
    /// different image of identical size doesn't return the stale thumbnail.
    /// The sample hash is O(1)-ish — far cheaper than decoding the full JPEG.
    func thumbnail(for data: Data, recipeID: UUID, maxPixelSize: CGFloat = 700) -> UIImage? {
        let key = cacheKey(for: data, recipeID: recipeID)
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

    private func cacheKey(for data: Data, recipeID: UUID) -> NSString {
        var hasher = Hasher()
        hasher.combine(data.count)
        // Hashing a small head+tail sample distinguishes same-size-but-different
        // images without paying to hash the whole payload on every render. The
        // cache is in-memory only, so Hasher's per-process seed is fine.
        let sampleSize = 1024
        hasher.combine(data.prefix(sampleSize))
        if data.count > sampleSize {
            hasher.combine(data.suffix(sampleSize))
        }
        return "\(recipeID.uuidString)-\(hasher.finalize())" as NSString
    }
}
