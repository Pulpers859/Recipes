import XCTest
@testable import Recipes

/// Scored regression gate over the golden import corpus in
/// `RecipeVaultTests/GoldenCorpus`. Each case folder holds `input.txt` (raw
/// document text; split cases delimit pages with `<<<PAGE>>>` lines) and
/// `expected.json` — hand-authored ground truth for what SHOULD be extracted,
/// not a transcript of what the parser currently produces.
///
/// The baselines below are the MEASURED performance of the current heuristics,
/// not aspirations: a change that drops any aggregate below its baseline fails
/// CI, while an improvement should raise the baseline in the same commit (to
/// just under the new measurement). Some cases intentionally document known
/// weaknesses (numbered/bulleted ingredient lists, traditional-cookbook
/// splitting) so future fixes are visible as score increases.
@MainActor
final class GoldenCorpusTests: XCTestCase {

    // MARK: - Baselines (measured 2026-07-17; see header for the update rule)
    //
    // Measured: ingredient F1 0.8500, step F1 0.9844, title 1.0, amount 1.0
    // (60 pairs), split 0.875. The gap to 1.0 is deliberate documentation of
    // current weaknesses: numbered ingredient lists (m04) and bulleted lists
    // (m13) parse badly, "1 28-oz can …" size qualifiers pollute names
    // (m06/m08), page furniture leaks into steps (m02), and traditional
    // cookbooks without macro/calorie/serving keywords don't split (s06).
    // F1 baselines carry a hair of slack for cross-platform float rounding.

    private static let ingredientF1Baseline = 0.8499
    private static let stepF1Baseline = 0.9843
    private static let titleAccuracyBaseline = 1.0
    private static let amountAccuracyBaseline = 1.0
    private static let splitAccuracyBaseline = 0.875

    // MARK: - Corpus loading

    private struct ExpectedIngredient: Decodable {
        let name: String
        let amount: Double?
        let unit: String?
    }

    private struct ExpectedCase: Decodable {
        let kind: String
        let title: String?
        let ingredients: [ExpectedIngredient]?
        let steps: [String]?
        let expectedChunkCount: Int?
        let chunkMarkers: [String]?
    }

    private struct CorpusCase {
        let name: String
        let input: String
        let expected: ExpectedCase
    }

    private static func corpusDirectory() -> URL {
        let testFileDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Windows-harness layout: the generator copies the corpus right next
        // to this file.
        let sibling = testFileDirectory.appendingPathComponent("GoldenCorpus", isDirectory: true)
        if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        // Repo layout: the corpus deliberately lives OUTSIDE the
        // file-synchronized RecipeVaultTests folder (at Recipes/GoldenCorpus).
        // Synchronized groups copy resource files flat into the test bundle,
        // so 24 files all named input.txt break the build with "Multiple
        // commands produce" if the corpus sits inside the target.
        return testFileDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("GoldenCorpus", isDirectory: true)
    }

    private static func loadCorpus() throws -> [CorpusCase] {
        let root = corpusDirectory()
        let caseDirs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try caseDirs.map { dir in
            let input = try String(contentsOf: dir.appendingPathComponent("input.txt"), encoding: .utf8)
            let expectedData = try Data(contentsOf: dir.appendingPathComponent("expected.json"))
            let expected = try JSONDecoder().decode(ExpectedCase.self, from: expectedData)
            return CorpusCase(name: dir.lastPathComponent, input: input, expected: expected)
        }
    }

    // MARK: - Normalization and metrics

    /// Display-equivalence normalization: case, surrounding whitespace, list
    /// bullets, and a trailing period never change what the user reads.
    private func normalized(_ text: String) -> String {
        var t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = t.first, "-•*– ".contains(first) {
            t.removeFirst()
        }
        if t.hasSuffix(".") { t.removeLast() }
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func normalizedUnit(_ unit: String) -> String {
        var u = unit.lowercased().trimmingCharacters(in: .whitespaces)
        if u.hasSuffix("s"), u.count > 2 { u.removeLast() }
        return u
    }

    /// Multiset F1 over normalized strings. Both sides empty is a perfect 1.
    private func f1(predicted: [String], expected: [String]) -> Double {
        if predicted.isEmpty && expected.isEmpty { return 1 }
        var remaining: [String: Int] = [:]
        for e in expected { remaining[e, default: 0] += 1 }
        var truePositives = 0
        for p in predicted where (remaining[p] ?? 0) > 0 {
            truePositives += 1
            remaining[p]! -= 1
        }
        let precision = predicted.isEmpty ? 0 : Double(truePositives) / Double(predicted.count)
        let recall = expected.isEmpty ? 0 : Double(truePositives) / Double(expected.count)
        guard precision + recall > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    // MARK: - The gate

    func testGoldenCorpusMeetsBaselines() throws {
        let corpus = try Self.loadCorpus()
        let manualCases = corpus.filter { $0.expected.kind == "manual" }
        let splitCases = corpus.filter { $0.expected.kind == "split" }

        // Guard against the corpus silently shrinking (deleted/unreadable
        // folders would otherwise inflate the averages).
        XCTAssertGreaterThanOrEqual(corpus.count, 24, "golden corpus lost cases")
        XCTAssertGreaterThanOrEqual(manualCases.count, 16)
        XCTAssertGreaterThanOrEqual(splitCases.count, 8)

        var ingredientF1s: [Double] = []
        var stepF1s: [Double] = []
        var titleHits = 0
        var amountPairs = 0
        var amountCorrect = 0
        var report: [String] = []

        for corpusCase in manualCases {
            let expected = corpusCase.expected
            let recipe = RecipeTextHeuristics.manualParse(text: corpusCase.input, pdfData: nil)

            let predictedNames = recipe.ingredients.map { normalized($0.name) }
            let expectedNames = (expected.ingredients ?? []).map { normalized($0.name) }
            let ingredientScore = f1(predicted: predictedNames, expected: expectedNames)
            ingredientF1s.append(ingredientScore)

            let predictedSteps = recipe.steps.sorted { $0.order < $1.order }.map { normalized($0.instruction) }
            let expectedSteps = (expected.steps ?? []).map { normalized($0) }
            let stepScore = f1(predicted: predictedSteps, expected: expectedSteps)
            stepF1s.append(stepScore)

            let titleHit = recipe.title == (expected.title ?? "")
            if titleHit { titleHits += 1 }

            // Amount/unit accuracy over name-matched pairs that declare an
            // expected amount — isolates quantity parsing from recall.
            var pool = recipe.ingredients
            for expectedIngredient in expected.ingredients ?? [] where expectedIngredient.amount != nil {
                guard let matchIndex = pool.firstIndex(where: { normalized($0.name) == normalized(expectedIngredient.name) }) else {
                    continue
                }
                let match = pool.remove(at: matchIndex)
                amountPairs += 1
                let amountOK = abs(match.amount - (expectedIngredient.amount ?? 0)) < 0.01
                let unitOK = expectedIngredient.unit.map { normalizedUnit(match.unit) == normalizedUnit($0) } ?? true
                if amountOK && unitOK { amountCorrect += 1 }
            }

            report.append(String(
                format: "%@  ingF1=%.2f stepF1=%.2f title=%@",
                corpusCase.name.padding(toLength: 36, withPad: " ", startingAt: 0),
                ingredientScore, stepScore, titleHit ? "ok" : "MISS"
            ))
        }

        var splitHits = 0
        for corpusCase in splitCases {
            let pages = corpusCase.input.components(separatedBy: "<<<PAGE>>>")
                .map { $0.trimmingCharacters(in: .newlines) }
            let chunks = RecipeTextHeuristics.splitIntoRecipeChunks(pageTexts: pages)
            let expectedCount = corpusCase.expected.expectedChunkCount ?? -1
            let markers = corpusCase.expected.chunkMarkers ?? []
            let countOK = chunks.count == expectedCount
            let markersOK = countOK && zip(chunks, markers).allSatisfy { chunk, marker in
                chunk.contains(marker)
            }
            if countOK && markersOK { splitHits += 1 }
            report.append(String(
                format: "%@  chunks=%d (want %d) %@",
                corpusCase.name.padding(toLength: 36, withPad: " ", startingAt: 0),
                chunks.count, expectedCount, (countOK && markersOK) ? "ok" : "MISS"
            ))
        }

        let ingredientF1 = ingredientF1s.reduce(0, +) / Double(ingredientF1s.count)
        let stepF1 = stepF1s.reduce(0, +) / Double(stepF1s.count)
        let titleAccuracy = Double(titleHits) / Double(manualCases.count)
        let amountAccuracy = amountPairs == 0 ? 1 : Double(amountCorrect) / Double(amountPairs)
        let splitAccuracy = Double(splitHits) / Double(splitCases.count)

        let summary = String(
            format: """
            golden corpus (%d manual, %d split):
              ingredient F1   %.4f (baseline %.4f)
              step F1         %.4f (baseline %.4f)
              title accuracy  %.4f (baseline %.4f)
              amount accuracy %.4f (baseline %.4f, %d pairs)
              split accuracy  %.4f (baseline %.4f)
            """,
            manualCases.count, splitCases.count,
            ingredientF1, Self.ingredientF1Baseline,
            stepF1, Self.stepF1Baseline,
            titleAccuracy, Self.titleAccuracyBaseline,
            amountAccuracy, Self.amountAccuracyBaseline, amountPairs,
            splitAccuracy, Self.splitAccuracyBaseline
        )
        print(summary)
        print(report.joined(separator: "\n"))

        let context = "\n\(summary)\n\(report.joined(separator: "\n"))"
        XCTAssertGreaterThanOrEqual(ingredientF1, Self.ingredientF1Baseline, "ingredient F1 regressed\(context)")
        XCTAssertGreaterThanOrEqual(stepF1, Self.stepF1Baseline, "step F1 regressed\(context)")
        XCTAssertGreaterThanOrEqual(titleAccuracy, Self.titleAccuracyBaseline, "title accuracy regressed\(context)")
        XCTAssertGreaterThanOrEqual(amountAccuracy, Self.amountAccuracyBaseline, "amount accuracy regressed\(context)")
        XCTAssertGreaterThanOrEqual(splitAccuracy, Self.splitAccuracyBaseline, "split accuracy regressed\(context)")
    }
}
