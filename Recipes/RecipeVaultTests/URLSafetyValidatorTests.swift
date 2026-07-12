import XCTest
@testable import Recipes

/// SSRF blocklist coverage: every spelling of a private/loopback/link-local
/// destination we know about must be refused, and normal recipe sites must
/// pass. DNS rebinding is a documented accepted risk (validation happens on
/// the URL, not the resolved socket address).
final class URLSafetyValidatorTests: XCTestCase {

    private func assertBlocked(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let url = URL(string: raw) else { return }
        XCTAssertNotEqual(URLSafetyValidator.validate(url), .allowed, "ALLOWED hostile URL: \(raw)", file: file, line: line)
    }

    func testLoopbackAndPrivateIPv4Spellings() {
        for raw in [
            "http://localhost/admin", "http://localhost./", "http://LOCALHOST/",
            "http://127.0.0.1:8080/", "http://127.0.0.1./x", "http://127.1/",
            "http://127.000.000.001/", "http://0.0.0.0/",
            "http://2130706433/",      // decimal 127.0.0.1
            "http://0x7f000001/",      // hex
            "http://017700000001/",    // octal
            "http://0177.0.0.1/",      // octal first octet
            "http://10.0.0.5/", "http://172.16.31.5/", "http://192.168.1.1/",
            "http://169.254.169.254/latest/meta-data/",
            "http://192.168.1.1.nip.io@10.0.0.1/",  // userinfo trick: host is 10.0.0.1
        ] {
            assertBlocked(raw)
        }
    }

    func testIPv6Spellings() {
        for raw in [
            "http://[::1]/", "http://[0:0:0:0:0:0:0:1]/",
            "http://[0000:0000:0000:0000:0000:0000:0000:0001]/",
            "http://[::]/", "http://[fe80::1]/", "http://[fc00::1]/",
            "http://[fd12:3456::1]/", "http://[::ffff:127.0.0.1]/",
            "http://[::ffff:10.0.0.1]/", "http://[0:0:0:0:0:ffff:192.168.0.1]/",
        ] {
            assertBlocked(raw)
        }
    }

    func testSchemesOtherThanWebAreInvalid() {
        for raw in ["file:///etc/passwd", "ftp://example.com/x", "javascript:alert(1)"] {
            if let url = URL(string: raw) {
                XCTAssertEqual(URLSafetyValidator.validate(url), .invalid, "accepted scheme: \(raw)")
            }
        }
    }

    func testLegitimateRecipeSitesAllowed() {
        for raw in [
            "https://www.seriouseats.com/the-best-chili-recipe",
            "https://cooking.nytimes.com/recipes/1017089",
            "https://smittenkitchen.com/2019/01/simple-essential-bolognese/",
            "https://www.bbcgoodfood.com/recipes/classic-lasagne-0",
            "https://10.0.0.1:8080@example.com/recipe",  // userinfo is not the host
        ] {
            guard let url = URL(string: raw) else { return XCTFail("bad fixture \(raw)") }
            XCTAssertEqual(URLSafetyValidator.validate(url), .allowed, "BLOCKED legit URL: \(raw)")
        }
    }
}
