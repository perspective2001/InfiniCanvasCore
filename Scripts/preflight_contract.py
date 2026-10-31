#!/usr/bin/env python3
"""Fast, dependency-free guard for the permanent InfiniCanvas iPad app contract.

Run before spending macOS runner minutes. This does not replace Apple compilation,
simulator tests, or actual iPad acceptance testing.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUNDLE = "com.perspective2001.infini-canvas.native"
EXPECTED_IOS = "17.5"


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def capture(text: str, pattern: str, label: str) -> str:
    match = re.search(pattern, text)
    if match is None:
        raise SystemExit(f"FAIL: missing {label}")
    return match.group(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


core = source("Package.swift")
manifest = source("IntegrationHost/InfiniCanvasPermanent.swiftpm/Package.swift")
entry = source("IntegrationHost/InfiniCanvasPermanent.swiftpm/Sources/InfiniCanvasApp.swift")
project = source("IntegrationHost/project.yml")

platform_pattern = r'platforms:\s*\[\.iOS\("([^"]+)"\)\]'
core_ios = capture(core, platform_pattern, "core iOS deployment target")
host_ios = capture(manifest, platform_pattern, "Playgrounds iOS deployment target")
xcode_ios = capture(project, r"IPHONEOS_DEPLOYMENT_TARGET:\s*['\"]?([0-9.]+)", "Xcode host deployment target")
require(core_ios == host_ios == xcode_ios == EXPECTED_IOS,
        f"iOS target drift: core={core_ios}, playground={host_ios}, Xcode={xcode_ios}")
host_bundle = capture(manifest, r'bundleIdentifier:\s*"([^"]+)"', "Playgrounds bundle identifier")
xcode_bundle = capture(project, r"PRODUCT_BUNDLE_IDENTIFIER:\s*([^\s]+)", "Xcode bundle identifier")
require(host_bundle == xcode_bundle == EXPECTED_BUNDLE,
        f"App identity drift: Playgrounds={host_bundle}, Xcode={xcode_bundle}")
require("import AppleProductTypes" in manifest and ".iOSApplication(" in manifest,
        "Playgrounds host must stay a native iOS application")
require('name: "InfiniCanvasCore"' in core and '.library(name: "InfiniCanvasCore"' in core,
        "The public Swift package/library product was changed")
require('path: "../.."' in manifest,
        "CI host must test local pull-request source, never an older remote tag")
require("import InfiniCanvasCore" in entry and "@main" in entry and "InfiniCanvasRootView()" in entry,
        "Actual app entry point no longer starts the core root view")
require("InfiniCanvasPermanent.swiftpm/Sources/InfiniCanvasApp.swift" in project,
        "Xcode application target must compile the same Playgrounds entry point")
require("CODE_SIGNING_ALLOWED: 'NO'" in project,
        "CI-only Xcode host must never attempt to sign/install an app")

swift_paths = list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "Tests").rglob("*.swift"))
for path in swift_paths:
    text = path.read_text(encoding="utf-8")
    require(not re.search(r"^(<<<<<<< |=======\s*$|>>>>>>> )", text, re.MULTILINE),
            f"Unresolved merge conflict in {path.relative_to(ROOT)}")

print(f"PASS: stable bundle {EXPECTED_BUNDLE}, matching iOS {EXPECTED_IOS}, "
      "real local app host and clean Swift sources")
