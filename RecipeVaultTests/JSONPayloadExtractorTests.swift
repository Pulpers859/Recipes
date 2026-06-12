import XCTest
@testable import RecipeVault

final class JSONPayloadExtractorTests: XCTestCase {

    private func decode(_ data: Data?) -> Any? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    func testBareJSONObject() {
        let data = JSONPayloadExtractor.extract(from: #"{"title": "Pasta"}"#)
        let obj = decode(data) as? [String: Any]
        XCTAssertEqual(obj?["title"] as? String, "Pasta")
    }

    func testFencedJSON() {
        let raw = """
        Here is the recipe:
        ```json
        {"title": "Soup"}
        ```
        """
        let obj = decode(JSONPayloadExtractor.extract(from: raw)) as? [String: Any]
        XCTAssertEqual(obj?["title"] as? String, "Soup")
    }

    func testProseWrappedObject() {
        let raw = #"Sure! {"title": "Tacos", "servings": 4} Hope that helps."#
        let obj = decode(JSONPayloadExtractor.extract(from: raw)) as? [String: Any]
        XCTAssertEqual(obj?["title"] as? String, "Tacos")
    }

    func testArrayWithLeadingProseIsNotTruncatedToFirstObject() {
        let raw = #"Found two: [{"title": "A"}, {"title": "B"}]"#
        let array = decode(JSONPayloadExtractor.extract(from: raw)) as? [[String: Any]]
        XCTAssertEqual(array?.count, 2)
    }

    func testBracesInsideStringsDoNotBreakBalancing() {
        let raw = #"{"title": "Use a {small} pot"}"#
        let obj = decode(JSONPayloadExtractor.extract(from: raw)) as? [String: Any]
        XCTAssertEqual(obj?["title"] as? String, "Use a {small} pot")
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(JSONPayloadExtractor.extract(from: "no json here at all"))
    }
}
