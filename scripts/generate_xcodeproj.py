#!/usr/bin/env python3
"""Write QuantTerminal.xcodeproj from the files under App/QuantTerminal.

Xcode keeps working with the project normally (add files from Xcode as usual); this script only
exists to rebuild it reproducibly without extra tools. Object ids are derived from names, so the
output is stable. Run from the repository root:  python3 scripts/generate_xcodeproj.py
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "App" / "QuantTerminal"
PROJECT = ROOT / "QuantTerminal.xcodeproj"


def oid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def file_type(path: Path) -> str:
    return {
        ".swift": "sourcecode.swift",
        ".plist": "text.plist.xml",
        ".entitlements": "text.plist.entitlements",
        ".xcassets": "folder.assetcatalog",
    }[path.suffix]


def main() -> None:
    swift = sorted(p for p in APP.rglob("*.swift"))
    others = [APP / "Info.plist", APP / "QuantTerminal.entitlements", APP / "Assets.xcassets"]
    objects: list[str] = []

    def add(text: str) -> None:
        objects.append(text)

    # file references and build files
    groups: dict[Path, list[str]] = {}
    for path in [*swift, *others]:
        rel = path.relative_to(APP)
        ref = oid(f"ref:{rel}")
        add(f'\t\t{ref} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = '
            f'{file_type(path)}; path = "{path.name}"; sourceTree = "<group>"; }};')
        groups.setdefault(rel.parent, []).append(f"{ref} /* {path.name} */")
    for path in swift:
        rel = path.relative_to(APP)
        add(f'\t\t{oid(f"build:{rel}")} /* {path.name} in Sources */ = {{isa = PBXBuildFile; '
            f'fileRef = {oid(f"ref:{rel}")} /* {path.name} */; }};')
    add(f'\t\t{oid("build:Assets")} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; '
        f'fileRef = {oid("ref:Assets.xcassets")} /* Assets.xcassets */; }};')
    add(f'\t\t{oid("build:QuantKit")} /* QuantKit in Frameworks */ = {{isa = PBXBuildFile; '
        f'productRef = {oid("product:QuantKit")} /* QuantKit */; }};')
    add(f'\t\t{oid("ref:app")} /* QuantTerminal.app */ = {{isa = PBXFileReference; '
        f'explicitFileType = wrapper.application; includeInIndex = 0; path = QuantTerminal.app; '
        f'sourceTree = BUILT_PRODUCTS_DIR; }};')
    add(f'\t\t{oid("ref:QuantKitFolder")} /* QuantKit */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = wrapper; path = QuantKit; sourceTree = "<group>"; }};')

    # groups: App/QuantTerminal[/Views]
    views = Path("Views")
    add(f'\t\t{oid("group:Views")} /* Views */ = {{isa = PBXGroup; children = ('
        + "".join(f"\n\t\t\t\t{c}," for c in groups.get(views, []))
        + '\n\t\t\t); path = Views; sourceTree = "<group>"; };')
    add(f'\t\t{oid("group:QuantTerminal")} /* QuantTerminal */ = {{isa = PBXGroup; children = ('
        + "".join(f"\n\t\t\t\t{c}," for c in groups.get(Path("."), []))
        + f'\n\t\t\t\t{oid("group:Views")} /* Views */,'
        + '\n\t\t\t); path = QuantTerminal; sourceTree = "<group>"; };')
    add(f'\t\t{oid("group:App")} /* App */ = {{isa = PBXGroup; children = ('
        f'\n\t\t\t\t{oid("group:QuantTerminal")} /* QuantTerminal */,'
        '\n\t\t\t); path = App; sourceTree = "<group>"; };')
    add(f'\t\t{oid("group:Products")} /* Products */ = {{isa = PBXGroup; children = ('
        f'\n\t\t\t\t{oid("ref:app")} /* QuantTerminal.app */,'
        '\n\t\t\t); name = Products; sourceTree = "<group>"; };')
    add(f'\t\t{oid("group:main")} = {{isa = PBXGroup; children = ('
        f'\n\t\t\t\t{oid("ref:QuantKitFolder")} /* QuantKit */,'
        f'\n\t\t\t\t{oid("group:App")} /* App */,'
        f'\n\t\t\t\t{oid("group:Products")} /* Products */,'
        '\n\t\t\t); sourceTree = "<group>"; };')

    # build phases
    add(f'\t\t{oid("phase:Sources")} /* Sources */ = {{isa = PBXSourcesBuildPhase; '
        f'buildActionMask = 2147483647; files = ('
        + "".join(f'\n\t\t\t\t{oid(f"build:{p.relative_to(APP)}")} /* {p.name} in Sources */,'
                  for p in swift)
        + '\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; };')
    add(f'\t\t{oid("phase:Frameworks")} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; '
        f'buildActionMask = 2147483647; files = (\n\t\t\t\t{oid("build:QuantKit")} '
        f'/* QuantKit in Frameworks */,\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};')
    add(f'\t\t{oid("phase:Resources")} /* Resources */ = {{isa = PBXResourcesBuildPhase; '
        f'buildActionMask = 2147483647; files = (\n\t\t\t\t{oid("build:Assets")} '
        f'/* Assets.xcassets in Resources */,\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};')

    # build settings
    common_project = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_ENTITLEMENTS": "App/QuantTerminal/QuantTerminal.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "App/QuantTerminal/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "MARKETING_VERSION": "0.1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.quant.terminal",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    debug_extra = {"DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES",
                   "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "ENABLE_TESTABILITY": "YES",
                   "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                   "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")'}
    release_extra = {"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "VALIDATE_PRODUCT": "YES",
                     "SWIFT_COMPILATION_MODE": "wholemodule", "ENABLE_NS_ASSERTIONS": "NO"}

    def config(key: str, name: str, settings: dict[str, str]) -> None:
        body = "".join(f"\n\t\t\t\t{k} = {v};" for k, v in sorted(settings.items()))
        add(f"\t\t{oid(key)} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{"
            f"{body}\n\t\t\t}}; name = {name}; }};")

    config("cfg:project:Debug", "Debug", {**common_project, **debug_extra})
    config("cfg:project:Release", "Release", {**common_project, **release_extra})
    config("cfg:target:Debug", "Debug", target_settings)
    config("cfg:target:Release", "Release", target_settings)
    for owner in ("project", "target"):
        add(f'\t\t{oid(f"list:{owner}")} /* Build configuration list */ = {{isa = '
            f'XCConfigurationList; buildConfigurations = (\n\t\t\t\t{oid(f"cfg:{owner}:Debug")} '
            f'/* Debug */,\n\t\t\t\t{oid(f"cfg:{owner}:Release")} /* Release */,\n\t\t\t); '
            f'defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')

    add(f'\t\t{oid("target")} /* QuantTerminal */ = {{isa = PBXNativeTarget; buildConfigurationList '
        f'= {oid("list:target")} /* Build configuration list */; buildPhases = (\n\t\t\t\t'
        f'{oid("phase:Sources")} /* Sources */,\n\t\t\t\t{oid("phase:Frameworks")} /* Frameworks */,'
        f'\n\t\t\t\t{oid("phase:Resources")} /* Resources */,\n\t\t\t); buildRules = (); '
        f'dependencies = (); name = QuantTerminal; packageProductDependencies = (\n\t\t\t\t'
        f'{oid("product:QuantKit")} /* QuantKit */,\n\t\t\t); productName = QuantTerminal; '
        f'productReference = {oid("ref:app")} /* QuantTerminal.app */; productType = '
        f'"com.apple.product-type.application"; }};')
    add(f'\t\t{oid("package:QuantKit")} /* XCLocalSwiftPackageReference "QuantKit" */ = {{isa = '
        f'XCLocalSwiftPackageReference; relativePath = QuantKit; }};')
    add(f'\t\t{oid("product:QuantKit")} /* QuantKit */ = {{isa = XCSwiftPackageProductDependency; '
        f'package = {oid("package:QuantKit")} /* XCLocalSwiftPackageReference "QuantKit" */; '
        f'productName = QuantKit; }};')
    add(f'\t\t{oid("project")} /* Project object */ = {{isa = PBXProject; attributes = {{'
        f'BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1500; '
        f'LastUpgradeCheck = 1500; }}; buildConfigurationList = {oid("list:project")} '
        f'/* Build configuration list */; compatibilityVersion = "Xcode 15.0"; '
        f'developmentRegion = es; hasScannedForEncodings = 0; knownRegions = (es, en, Base); '
        f'mainGroup = {oid("group:main")}; packageReferences = (\n\t\t\t\t'
        f'{oid("package:QuantKit")} /* XCLocalSwiftPackageReference "QuantKit" */,\n\t\t\t); '
        f'productRefGroup = {oid("group:Products")} /* Products */; projectDirPath = ""; '
        f'projectRoot = ""; targets = (\n\t\t\t\t{oid("target")} /* QuantTerminal */,\n\t\t\t); }};')

    pbxproj = (
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n"
        "\tobjects = {\n" + "\n".join(objects) + "\n\t};\n"
        f"\trootObject = {oid('project')} /* Project object */;\n}}\n"
    )
    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(pbxproj, encoding="utf-8")
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
        '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n', encoding="utf-8")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    target = oid("target")
    buildable = (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = '
                 f'"{target}" BuildableName = "QuantTerminal.app" BlueprintName = "QuantTerminal" '
                 f'ReferencedContainer = "container:QuantTerminal.xcodeproj"></BuildableReference>')
    (schemes / "QuantTerminal.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {buildable}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "QuantKitTests" BuildableName = "QuantKitTests" BlueprintName = "QuantKitTests" ReferencedContainer = "container:QuantKit"></BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {buildable}
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
''', encoding="utf-8")
    print(f"wrote {PROJECT} ({len(swift)} Swift files)")


if __name__ == "__main__":
    main()
