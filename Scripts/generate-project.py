#!/usr/bin/env python3
"""Generate the small, dependency-free Xcode wrapper around the Swift package."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
project = root / "Glint.xcodeproj"
project.mkdir(exist_ok=True)

def identifier(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

objects = []
def object_(key, body):
    ident = identifier(key)
    objects.append(f"\t\t{ident} = {{ {body} }};")
    return ident

source_refs, source_builds = [], []
for path in sorted((root / "Sources/Glint").glob("*.swift")):
    rel = path.relative_to(root).as_posix()
    ref = object_(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = SOURCE_ROOT;')
    source_refs.append(ref)
    source_builds.append(object_(rel + "-build", f"isa = PBXBuildFile; fileRef = {ref};"))

assets = object_("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assets_build = object_("assets-build", f"isa = PBXBuildFile; fileRef = {assets};")
notices = object_("notices", 'isa = PBXFileReference; lastKnownFileType = text; path = Resources/ThirdPartyNotices.txt; sourceTree = SOURCE_ROOT;')
notices_build = object_("notices-build", f"isa = PBXBuildFile; fileRef = {notices};")
plist = object_("plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = SOURCE_ROOT;')
product = object_("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Glint.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = object_("products", f"isa = PBXGroup; children = ({product},); name = Products; sourceTree = \"<group>\";")
sources = object_("sources-group", f'isa = PBXGroup; children = ({",".join(source_refs)},); name = App; sourceTree = "<group>";')
resources = object_("resources-group", f'isa = PBXGroup; children = ({assets},{plist},{notices},); name = Resources; sourceTree = "<group>";')
main_group = object_("main-group", f'isa = PBXGroup; children = ({sources},{resources},{products},); sourceTree = "<group>";')
package = object_("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core = object_("core-product", f"isa = XCSwiftPackageProductDependency; package = {package}; productName = GlintCore;")
core_build = object_("core-build", f"isa = PBXBuildFile; productRef = {core};")
source_phase = object_("sources-phase", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(source_builds)},); runOnlyForDeploymentPostprocessing = 0;")
resource_phase = object_("resources-phase", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build},{notices_build},); runOnlyForDeploymentPostprocessing = 0;")
framework_phase = object_("frameworks-phase", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build},); runOnlyForDeploymentPostprocessing = 0;")

project_configs, target_configs = [], []
for name in ("Debug", "Release"):
    debug = name == "Debug"
    project_configs.append(object_("project-" + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
        MACOSX_DEPLOYMENT_TARGET = 26.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; ARCHS = arm64;
        CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;
        SWIFT_OPTIMIZATION_LEVEL = "{'-Onone' if debug else '-O'}";
        SWIFT_COMPILATION_MODE = {'singlefile' if debug else 'wholemodule'};
        DEBUG_INFORMATION_FORMAT = {'dwarf' if debug else '"dwarf-with-dsym"'};
        ENABLE_TESTABILITY = {'YES' if debug else 'NO'};
        SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{'DEBUG ' if debug else ''}$(inherited)";
    }};'''))
    target_configs.append(object_("target-" + name, f'''isa = XCBuildConfiguration; name = {name}; buildSettings = {{
        PRODUCT_NAME = Glint; PRODUCT_BUNDLE_IDENTIFIER = app.glint.viewer;
        INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-";
        ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO;
        LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
        CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;
        COMBINE_HIDPI_IMAGES = YES;
    }};'''))
project_config_list = object_("project-configs", f"isa = XCConfigurationList; buildConfigurations = ({','.join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target_config_list = object_("target-configs", f"isa = XCConfigurationList; buildConfigurations = ({','.join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
target = object_("app-target", f'''isa = PBXNativeTarget; buildConfigurationList = {target_config_list};
    buildPhases = ({source_phase},{framework_phase},{resource_phase},); buildRules = (); dependencies = ();
    name = Glint; packageProductDependencies = ({core},); productName = Glint; productReference = {product};
    productType = "com.apple.product-type.application";''')
project_id = object_("project", f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; }};
    buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en;
    hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {main_group}; packageReferences = ({package},);
    productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);''')
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {project_id};\n}}\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Glint.app" BlueprintName="Glint" ReferencedContainer="container:Glint.xcodeproj"/>'
(schemes / "Glint.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Glint.xcodeproj")
