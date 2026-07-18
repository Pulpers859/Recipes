#!/usr/bin/env python3
"""Fail when the Recipe Vault share-extension contract drifts out of wiring."""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = REPO_ROOT / "Recipes"
PBXPROJ = PROJECT_ROOT / "Recipes.xcodeproj" / "project.pbxproj"
APP_ENTITLEMENTS = PROJECT_ROOT / "Recipes" / "Recipes.entitlements"
EXTENSION_ROOT = PROJECT_ROOT / "RecipeVaultShare"
EXTENSION_ENTITLEMENTS = EXTENSION_ROOT / "RecipeVaultShare.entitlements"
EXTENSION_INFO = EXTENSION_ROOT / "Info.plist"
EXTENSION_CONTROLLER = EXTENSION_ROOT / "ShareViewController.swift"
SHARED_CONTRACT = PROJECT_ROOT / "Recipes" / "Service" / "ShareInboxEnvelope.swift"


def load_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def load_project() -> dict[str, Any]:
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(PBXPROJ)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def configuration_settings(objects: dict[str, Any], target: dict[str, Any]) -> list[dict[str, Any]]:
    configuration_list = objects[target["buildConfigurationList"]]
    return [objects[item]["buildSettings"] for item in configuration_list["buildConfigurations"]]


def main() -> int:
    errors: list[str] = []

    for path in (
        PBXPROJ,
        APP_ENTITLEMENTS,
        EXTENSION_ENTITLEMENTS,
        EXTENSION_INFO,
        EXTENSION_CONTROLLER,
        SHARED_CONTRACT,
    ):
        if not path.is_file():
            errors.append(f"missing required file: {path.relative_to(REPO_ROOT)}")

    if errors:
        return report(errors)

    try:
        project = load_project()
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        return report([f"project.pbxproj is not a readable structured plist: {error}"])

    objects: dict[str, Any] = project["objects"]
    project_object = objects[project["rootObject"]]
    targets = {
        item.get("name"): (identifier, item)
        for identifier, item in objects.items()
        if item.get("isa") == "PBXNativeTarget"
    }

    if "Recipes" not in targets:
        errors.append("Recipes app target is missing")
    if "RecipeVaultShare" not in targets:
        errors.append("RecipeVaultShare target is missing")
    if errors:
        return report(errors)

    app_id, app_target = targets["Recipes"]
    extension_id, extension_target = targets["RecipeVaultShare"]

    if app_id not in project_object.get("targets", []):
        errors.append("Recipes target is detached from the project")
    if extension_id not in project_object.get("targets", []):
        errors.append("RecipeVaultShare target is detached from the project")
    if extension_target.get("productType") != "com.apple.product-type.app-extension":
        errors.append("RecipeVaultShare is not an app-extension product")

    dependency_targets = {
        objects[dependency].get("target")
        for dependency in app_target.get("dependencies", [])
    }
    if extension_id not in dependency_targets:
        errors.append("Recipes does not depend on RecipeVaultShare")

    extension_product = extension_target.get("productReference")
    embedded = False
    for phase_id in app_target.get("buildPhases", []):
        phase = objects[phase_id]
        if phase.get("isa") != "PBXCopyFilesBuildPhase" or str(phase.get("dstSubfolderSpec")) != "13":
            continue
        for build_file_id in phase.get("files", []):
            if objects[build_file_id].get("fileRef") == extension_product:
                embedded = True
    if not embedded:
        errors.append("RecipeVaultShare.appex is not embedded in Recipes.app PlugIns")

    source_paths: set[str] = set()
    for phase_id in extension_target.get("buildPhases", []):
        phase = objects[phase_id]
        if phase.get("isa") != "PBXSourcesBuildPhase":
            continue
        for build_file_id in phase.get("files", []):
            file_ref = objects[objects[build_file_id]["fileRef"]]
            source_paths.add(file_ref.get("path", ""))
    for required_source in ("ShareViewController.swift", "Recipes/Service/ShareInboxEnvelope.swift"):
        if required_source not in source_paths:
            errors.append(f"RecipeVaultShare does not compile {required_source}")

    for settings in configuration_settings(objects, app_target):
        if settings.get("CODE_SIGN_ENTITLEMENTS") != "Recipes/Recipes.entitlements":
            errors.append("Recipes has an incorrect CODE_SIGN_ENTITLEMENTS path")
    for settings in configuration_settings(objects, extension_target):
        if settings.get("CODE_SIGN_ENTITLEMENTS") != "RecipeVaultShare/RecipeVaultShare.entitlements":
            errors.append("RecipeVaultShare has an incorrect CODE_SIGN_ENTITLEMENTS path")
        if settings.get("INFOPLIST_FILE") != "RecipeVaultShare/Info.plist":
            errors.append("RecipeVaultShare has an incorrect INFOPLIST_FILE path")
        if settings.get("PRODUCT_BUNDLE_IDENTIFIER") != "Patrick-App.Recipes.RecipeVaultShare":
            errors.append("RecipeVaultShare bundle identifier is not nested under the app identifier")
        if str(settings.get("APPLICATION_EXTENSION_API_ONLY")) != "YES":
            errors.append("RecipeVaultShare does not enforce extension-safe APIs")

    app_groups = load_plist(APP_ENTITLEMENTS).get("com.apple.security.application-groups", [])
    extension_groups = load_plist(EXTENSION_ENTITLEMENTS).get("com.apple.security.application-groups", [])
    contract_source = SHARED_CONTRACT.read_text(encoding="utf-8")
    identifier_match = re.search(r'appGroupIdentifier\s*=\s*"([^"]+)"', contract_source)
    contract_group = identifier_match.group(1) if identifier_match else None
    if not contract_group:
        errors.append("ShareInbox.appGroupIdentifier is missing")
    elif app_groups != [contract_group] or extension_groups != [contract_group]:
        errors.append("the app, extension, and ShareInbox contract do not use the same App Group")

    info = load_plist(EXTENSION_INFO)
    extension_info = info.get("NSExtension", {})
    if extension_info.get("NSExtensionPointIdentifier") != "com.apple.share-services":
        errors.append("Info.plist does not declare a share-services extension")
    if extension_info.get("NSExtensionPrincipalClass") != "$(PRODUCT_MODULE_NAME).ShareViewController":
        errors.append("Info.plist does not launch ShareViewController")
    activation = extension_info.get("NSExtensionAttributes", {}).get("NSExtensionActivationRule", {})
    expected_activation = {
        "NSExtensionActivationSupportsFileWithMaxCount": 1,
        "NSExtensionActivationSupportsImageWithMaxCount": 1,
        "NSExtensionActivationSupportsText": True,
        "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
    }
    if activation != expected_activation:
        errors.append("Info.plist share activation rules drifted from the supported input contract")

    return report(errors)


def report(errors: list[str]) -> int:
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Share-extension project wiring is valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
