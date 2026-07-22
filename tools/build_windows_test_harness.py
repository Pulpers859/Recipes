#!/usr/bin/env python3
"""Build and run Recipe Vault's pure-logic unit tests on Windows (no Xcode).

Generates a SwiftPM package from preprocessed copies of the app's
pure-Foundation sources plus the RecipeVaultTests suite, then (with --run)
invokes `swift test` using the local Swift for Windows toolchain.

What "preprocessed" means (mirrors what the app can't take to Windows):
- SwiftData/SwiftUI/UIKit/PDFKit/Vision/Combine/CoreSpotlight imports removed
- @Model / @Attribute(...) / @Relationship(...) / @MainActor annotations removed
- members typed Color/UIImage and functions touching ModelContext /
  FetchDescriptor removed (brace-balanced)
- RecipeExportService's UIKit PDF-renderer section removed
- URLSafetyValidator is extracted out of URLRecipeScraperService.swift
  (the rest of that file needs Combine, unavailable on Windows)

Views and SwiftData persistence remain compile-unverified on this machine —
that is what the GitHub Actions macOS workflow is for. This harness proves
the logic layer (parsers, planners, exporters, heuristics) in under a second.

Usage:
    python tools/build_windows_test_harness.py --run
    python tools/build_windows_test_harness.py --out C:\\somewhere  # generate only
"""

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[1]
APP = REPO / "Recipes" / "Recipes"
TESTS = REPO / "Recipes" / "RecipeVaultTests"

# These tests exercise app-only frameworks or services intentionally excluded
# from the Foundation-only Windows package. GitHub's macOS/Xcode job runs them.
XCODE_ONLY_TESTS = {
    "ImageDataNormalizerTests.swift",
    "URLRecipeScraperServiceTests.swift",
}

SWIFT_ROOT = pathlib.Path(
    os.environ.get(
        "RECIPES_SWIFT_ROOT",
        r"C:\Users\Patrick's Computer\AppData\Local\Programs\Swift",
    )
)
SWIFT_VERSION_DIR = os.environ.get("RECIPES_SWIFT_VERSION", "6.3.1")

STRIP_IMPORTS = [
    "SwiftData", "SwiftUI", "UIKit", "PDFKit", "Vision", "Combine",
    "CoreSpotlight", "CryptoKit",
]

# Copied verbatim (already pure Foundation).
VERBATIM_SOURCES = [
    "Service/IngredientLineParser.swift",
    "Service/RecipeSchemaNormalizer.swift",
    "Service/JSONPayloadExtractor.swift",
    "Service/AIParsedRecipe.swift",
    "Service/RecipeTextHeuristics.swift",
    "Service/ShareInboxEnvelope.swift",
    "Service/ShareInboxService.swift",
]

# Copied with preprocessing; the listed header regexes get their whole
# brace-balanced block removed.
PREPROCESSED_SOURCES = {
    "Models/Recipe.swift": [r"var color: Color"],
    "Models/MealPlan.swift": [],
    "Models/PantryItem.swift": [],
    "Service/ShoppingListService.swift": [],
    "Service/MealPlanningService.swift": [],
    "Service/RecipeExportService.swift": [
        r"static func exportAsPDFCookbook",
        r"private static func drawTitlePage",
        r"private static func drawTableOfContents",
        r"private static func drawRecipePage",
    ],
}

PACKAGE_SWIFT = """\
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Recipes",
    targets: [
        .target(name: "Recipes", path: "Sources/Recipes"),
        .testTarget(name: "RecipesTests", dependencies: ["Recipes"], path: "Tests/RecipesTests"),
    ]
)
"""


def remove_brace_block(source: str, header_pattern: str) -> str:
    """Remove the smallest brace-balanced block whose header matches
    `header_pattern`, including contiguous preceding comment lines."""
    match = re.search(header_pattern, source)
    if not match:
        raise SystemExit(f"pattern not found: {header_pattern}")
    line_start = source.rfind("\n", 0, match.start()) + 1
    # Swallow doc comments directly above the block.
    while True:
        prev_start = source.rfind("\n", 0, max(line_start - 1, 0)) + 1
        prev_line = source[prev_start:line_start].strip()
        if prev_line.startswith("//") or prev_line.startswith("///"):
            line_start = prev_start
        else:
            break
    brace_open = source.find("{", match.end() - 1)
    if brace_open == -1:
        raise SystemExit(f"no opening brace after: {header_pattern}")
    depth = 0
    index = brace_open
    while index < len(source):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
        index += 1
    end = source.find("\n", index) + 1 or len(source)
    return source[:line_start] + source[end:]


def remove_model_context_functions(source: str) -> str:
    """Remove every function whose signature (which may span lines) mentions
    ModelContext or FetchDescriptor — those APIs don't exist on Windows."""
    while True:
        removed = False
        for match in re.finditer(
            r"^[ \t]*(?:@\w+[ \t]+)?(?:public |private |internal |static |nonisolated |final )*func \w+",
            source,
            flags=re.M,
        ):
            body_brace = source.find("{", match.end())
            if body_brace == -1:
                continue
            signature = source[match.start():body_brace]
            if "ModelContext" not in signature and "FetchDescriptor" not in signature:
                continue
            line_start = match.start()
            # Swallow doc comments and standalone attributes directly above.
            while True:
                prev_start = source.rfind("\n", 0, max(line_start - 1, 0)) + 1
                prev_line = source[prev_start:line_start].strip()
                if prev_line.startswith("//") or prev_line.startswith("///") or prev_line.startswith("@"):
                    line_start = prev_start
                else:
                    break
            depth = 0
            index = body_brace
            while index < len(source):
                if source[index] == "{":
                    depth += 1
                elif source[index] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                index += 1
            end = source.find("\n", index) + 1 or len(source)
            source = source[:line_start] + source[end:]
            removed = True
            break
        if not removed:
            return source


def preprocess(source: str, remove_blocks: list[str]) -> str:
    for module in STRIP_IMPORTS:
        source = re.sub(rf"^import {module}\s*\n", "", source, flags=re.M)
    source = re.sub(r"^\s*@Model\s*\n", "", source, flags=re.M)
    source = re.sub(r"@Attribute\([^)]*\)\s*", "", source)
    source = re.sub(r"@Relationship\([^)]*\)\s*", "", source)
    source = re.sub(r"^\s*@MainActor\s*\n", "", source, flags=re.M)
    source = re.sub(r"@MainActor\s+", "", source)
    for pattern in remove_blocks:
        source = remove_brace_block(source, pattern)
    source = remove_model_context_functions(source)
    return source


def extract_url_safety_validator() -> str:
    scraper = (APP / "Service" / "URLRecipeScraperService.swift").read_text(encoding="utf-8")
    match = re.search(r"^(?:nonisolated )?enum URLSafetyValidator", scraper, flags=re.M)
    if not match:
        raise SystemExit("URLSafetyValidator not found in URLRecipeScraperService.swift")
    start = scraper.rfind("\n", 0, match.start()) + 1
    # Include preceding doc comments.
    while True:
        prev_start = scraper.rfind("\n", 0, max(start - 1, 0)) + 1
        prev_line = scraper[prev_start:start].strip()
        if prev_line.startswith("//") or prev_line.startswith("///"):
            start = prev_start
        else:
            break
    brace_open = scraper.find("{", match.end())
    depth = 0
    index = brace_open
    while index < len(scraper):
        if scraper[index] == "{":
            depth += 1
        elif scraper[index] == "}":
            depth -= 1
            if depth == 0:
                break
        index += 1
    block = scraper[start : index + 1]
    return "import Foundation\n\n" + block + "\n"


def generate(out_dir: pathlib.Path) -> None:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    sources_dir = out_dir / "Sources" / "Recipes"
    tests_dir = out_dir / "Tests" / "RecipesTests"
    sources_dir.mkdir(parents=True)
    tests_dir.mkdir(parents=True)

    (out_dir / "Package.swift").write_text(PACKAGE_SWIFT, encoding="utf-8")

    for rel in VERBATIM_SOURCES:
        source = (APP / rel).read_text(encoding="utf-8")
        source = preprocess(source, [])  # imports/@MainActor still stripped
        (sources_dir / pathlib.Path(rel).name).write_text(source, encoding="utf-8")

    for rel, blocks in PREPROCESSED_SOURCES.items():
        source = (APP / rel).read_text(encoding="utf-8")
        source = preprocess(source, blocks)
        (sources_dir / pathlib.Path(rel).name).write_text(source, encoding="utf-8")

    (sources_dir / "URLSafetyValidator.swift").write_text(
        extract_url_safety_validator(), encoding="utf-8"
    )

    for test_file in sorted(TESTS.glob("*.swift")):
        if test_file.name in XCODE_ONLY_TESTS:
            continue
        source = test_file.read_text(encoding="utf-8")
        source = re.sub(r"^\s*@MainActor\s*\n", "", source, flags=re.M)
        source = re.sub(r"@MainActor\s+", "", source)
        (tests_dir / test_file.name).write_text(source, encoding="utf-8")

    # The corpus lives outside the synchronized test folder in the repo (see
    # GoldenCorpusTests.corpusDirectory()); copy it next to the tests here.
    corpus = REPO / "Recipes" / "GoldenCorpus"
    if corpus.exists():
        shutil.copytree(corpus, tests_dir / "GoldenCorpus")

    print(f"generated harness package at {out_dir}")


def run_tests(out_dir: pathlib.Path) -> int:
    toolchain_bin = SWIFT_ROOT / "Toolchains" / f"{SWIFT_VERSION_DIR}+Asserts" / "usr" / "bin"
    runtime_bin = SWIFT_ROOT / "Runtimes" / SWIFT_VERSION_DIR / "usr" / "bin"
    sdk = SWIFT_ROOT / "Platforms" / SWIFT_VERSION_DIR / "Windows.platform" / "Developer" / "SDKs" / "Windows.sdk"
    msvc_root = pathlib.Path(r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC")
    msvc_bins = sorted(msvc_root.glob("*/bin/Hostx64/x64")) if msvc_root.exists() else []

    env = os.environ.copy()
    env["SDKROOT"] = str(sdk)
    prefix = [str(toolchain_bin), str(runtime_bin)] + [str(b) for b in msvc_bins]
    env["PATH"] = os.pathsep.join(prefix + [env.get("PATH", "")])

    return subprocess.call(
        [str(toolchain_bin / "swift.exe"), "test", "--package-path", str(out_dir)],
        env=env,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path,
                        default=pathlib.Path(tempfile.gettempdir()) / "recipes-win-harness")
    parser.add_argument("--run", action="store_true", help="run swift test after generating")
    args = parser.parse_args()

    generate(args.out)
    if args.run:
        sys.exit(run_tests(args.out))


if __name__ == "__main__":
    main()
