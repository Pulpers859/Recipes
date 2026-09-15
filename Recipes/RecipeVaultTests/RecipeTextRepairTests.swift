import XCTest
@testable import Recipes

/// Covers `RecipeTextHeuristics.repairExtractedText`, which undoes the
/// character corruption PDF extraction produces for subsetted fonts.
///
/// Every string here is taken from a real failed import of a macro-style
/// cookbook PDF, where the `fl` ligature arrived as `!`, `/` as `%`, and `:`
/// as `&`.
final class RecipeTextRepairTests: XCTestCase {

    // MARK: - Corruption Is Repaired

    func testFractionSlashesAreRestored() {
        let repaired = RecipeTextHeuristics.repairExtractedText("1 1%3 CUP FAT-FREE HALF AND HALF")
        XCTAssertEqual(repaired, "1 1/3 CUP FAT-FREE HALF AND HALF")
    }

    func testRatiosBetweenDigitsAreRestored() {
        // "93%7" is 93/7 lean ground beef, not a percentage.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("20OZ GROUND BEEF (93%7)"),
            "20OZ GROUND BEEF (93/7)"
        )
    }

    func testSlashBetweenWordsIsRestored() {
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("2 TBSP GARLIC SALT%PEPPER"),
            "2 TBSP GARLIC SALT/PEPPER"
        )
    }

    func testLabelColonsAreRestored() {
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("MACROS& 43C 13F 38P PER SERVING"),
            "MACROS: 43C 13F 38P PER SERVING"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("SERVINGS& 6\nPREP& 30 MINUTES"),
            "SERVINGS: 6\nPREP: 30 MINUTES"
        )
    }

    func testLabelColonsCorruptedToPercentAreRestored() {
        // The other corruption family: some files render ':' as '%' rather
        // than '&'.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("MACROS% 43C 13F 38P"),
            "MACROS: 43C 13F 38P"
        )
        // A page can end on its heading, same as the ampersand rule allows.
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("MACROS%"), "MACROS:")
    }

    func testPercentEncodingIsNotMistakenForASlash() {
        // "caf%C3%A9" has a letter on both sides of the first '%' and would
        // otherwise be mangled.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("from caf%C3%A9 kitchen"),
            "from caf%C3%A9 kitchen"
        )
    }

    func testHexVetoDoesNotSwallowOrdinaryIngredientWords() {
        // The veto needs a DIGIT in the pair. Vetoing on any two hex
        // characters would also block these, since B/E/A/C/D/F are hex —
        // and food words beginning with them are far commoner here than URLs.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("CHICKEN%BEEF"),
            "CHICKEN/BEEF"
        )
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("RICE%BEANS"), "RICE/BEANS")
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("SALT%BACON"), "SALT/BACON")
    }

    func testUppercaseLigatureKeepsItsCase() {
        // The source document writes ingredients in caps, so "!OUR" has to
        // become "FLOUR" rather than "flOUR".
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("1%2 CUP !OUR"), "1/2 CUP FLOUR")
    }

    // MARK: - Rule Ordering

    func testLigatureRepairRunsBeforeTheSlashRules() {
        // This is the ONE ordering dependency in the rule list, and the reason
        // it is documented. The ligature rules are the only ones that produce
        // letters, and the '%' rules key on a letter after the percent. A
        // token carrying both corruptions — expected, since one font subset
        // produced both — only resolves if the ligature is restored first.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("2 TBSP salt%!our"),
            "2 TBSP salt/flour"
        )
    }

    func testRepairIsIdempotent() {
        // Running twice must equal running once. Two things break this if
        // changed: reordering the ligature rules after the '%' rules, and
        // letting a doubled "!" match the ligature guard (which made
        // "!!a" -> "!fla" -> "flfla"). Both shapes are sampled below.
        let samples = [
            "2 TBSP salt%!our",
            "1 1%3 CUP FAT-FREE HALF AND HALF",
            "MACROS& 43C\nSERVINGS& 6",
            "150G 2% PLAIN GREEK YOGURT",
            "from caf%C3%A9 kitchen",
            "Add queso over rice and enjoy!",
            "1%2 CUP !OUR",
            "!!a",
            "Wow!!great",
            "WOW!!!Amazing",
            "SERVES 4!ENJOY",
            "MACROS&43C"
        ]
        for sample in samples {
            let once = RecipeTextHeuristics.repairExtractedText(sample)
            let twice = RecipeTextHeuristics.repairExtractedText(once)
            XCTAssertEqual(once, twice, "repair is not idempotent for \(sample)")
        }
    }

    func testFlLigatureIsRestored() {
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Add 2 Tbsp !our and stir"),
            "Add 2 Tbsp flour and stir"
        )
    }

    // MARK: - Legitimate Text Survives

    func testRealPercentagesAreNotTouched() {
        // The guard that matters: a percentage is followed by a space or the
        // end of a word, never by another digit.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("150G 2% PLAIN GREEK YOGURT"),
            "150G 2% PLAIN GREEK YOGURT"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("93% lean beef"),
            "93% lean beef"
        )
    }

    func testRealAmpersandsAreNotTouched() {
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("GARLIC POWDER & SALT TO TASTE"),
            "GARLIC POWDER & SALT TO TASTE"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("QUESO CHICKEN & RICE"),
            "QUESO CHICKEN & RICE"
        )
        // A letter on BOTH sides is a name, not a corrupted colon.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("M&M cookies"),
            "M&M cookies"
        )
    }

    func testRealExclamationsAreNotTouched() {
        // "enjoy!" is the one real exclamation in the source file, and it sits
        // three lines from a corrupted "!our".
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Add queso over rice and enjoy!"),
            "Add queso over rice and enjoy!"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Enjoy! Serve warm."),
            "Enjoy! Serve warm."
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Wow!great"),
            "Wow!great"
        )
        // A doubled exclamation is emphasis, not a ligature. The second "!"
        // has no letter before it, so only excluding "!" too keeps these
        // intact — and this is what made the whole pass non-idempotent.
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("Wow!!great"), "Wow!!great")
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Delicious!!Enjoy"),
            "Delicious!!Enjoy"
        )
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("WOW!!!Amazing"), "WOW!!!Amazing")
    }

    func testYieldLinesAreNotMistakenForLigatures() {
        // A yield line that lost its space is the realistic false positive,
        // and every shape of it has a digit before the "!". An earlier
        // version guarded only against Title case, so the all-caps and
        // lowercase forms — the ones this document family actually uses —
        // still corrupted.
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Serves 4!Enjoy your meal"),
            "Serves 4!Enjoy your meal"
        )
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText("SERVES 4!ENJOY"), "SERVES 4!ENJOY")
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Makes 12!store in fridge"),
            "Makes 12!store in fridge"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText("Yield 8!servings"),
            "Yield 8!servings"
        )
    }

    func testCleanTextIsUnchanged() {
        let clean = "2 cups flour\n1/2 tsp salt\nMACROS: 43C\nSalt & pepper to taste"
        XCTAssertEqual(RecipeTextHeuristics.repairExtractedText(clean), clean)
    }

    // MARK: - The Regression This Exists For

    func testRepairLetsBoundaryDetectionFindRecipeStarts() {
        // The real failure: `splitIntoRecipeChunks` keys on "MACROS:" to find
        // where a recipe begins. With colons corrupted to "&", no page scored
        // as a recipe start, so a three-recipe cookbook imported as ONE
        // merged recipe.
        // Comfortably over the 100-character floor `splitIntoRecipeChunks`
        // uses to discard cover and contents pages.
        let page = """
        Ingredients
        • 1 LB FROZEN MEDIUM SHRIMP, DEVEINED WITH TAILS OFF
        • 10OZ FARFALLE PASTA (UNCOOKED)
        • 2 TBSP BUTTER
        • 1 GARLIC CLOVE, MINCED
        MACROS& 43C 13F 38P PER SERVING
        CALORIES& 444 PER SERVING
        SERVINGS& 6
        """
        let repairedChunks = RecipeTextHeuristics.splitIntoRecipeChunks(
            pageTexts: [page, page, page].map(RecipeTextHeuristics.repairExtractedText)
        )
        XCTAssertEqual(repairedChunks.count, 3, "repaired pages split into three recipes")
    }

    func testBoundaryDetectionToleratesSpaceDroppedCorruptedLabels() {
        // The shape repair deliberately leaves alone: with no whitespace after
        // the glyph there isn't enough signal to call it a colon, so
        // "MACROS&43C" survives the repair pass untouched. Boundary detection
        // has to cope on its own, which is what the raw glyphs in
        // `recipeStartSupportRegexes` are for. This is the only coverage that
        // backstop has — the repair can't produce this input.
        let page = """
        Ingredients
        • 1 LB FROZEN MEDIUM SHRIMP, DEVEINED WITH TAILS OFF
        • 10OZ FARFALLE PASTA (UNCOOKED)
        • 2 TBSP BUTTER
        MACROS&43C 13F 38P
        CALORIES&444
        SERVINGS&6
        """
        XCTAssertEqual(
            RecipeTextHeuristics.repairExtractedText(page),
            page,
            "precondition: repair leaves the space-dropped form alone"
        )
        XCTAssertEqual(
            RecipeTextHeuristics.splitIntoRecipeChunks(pageTexts: [page, page, page]).count,
            3,
            "the support patterns must recognise the raw corrupted glyph"
        )
    }
}
