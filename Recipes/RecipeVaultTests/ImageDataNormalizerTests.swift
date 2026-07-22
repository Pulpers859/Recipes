import XCTest
import UIKit
@testable import Recipes

@MainActor
final class ImageDataNormalizerTests: XCTestCase {
    func testDownsamplesWithoutExceedingRequestedDimension() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        let sourceData = try XCTUnwrap(source.pngData())

        let normalized = try XCTUnwrap(
            ImageDataNormalizer.normalizedJPEGData(from: sourceData, maxDimension: 600)
        )
        let image = try XCTUnwrap(UIImage(data: normalized))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 600)
    }

    func testRejectsUndecodableData() {
        XCTAssertNil(ImageDataNormalizer.normalizedJPEGData(from: Data("not an image".utf8)))
    }
}
