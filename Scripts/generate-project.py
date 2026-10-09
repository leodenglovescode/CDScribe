#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the checked-in Xcode project without third-party generators."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
objects = []
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def obj(name, value):
    key = uid(name); objects.append(f'{key} = {{ {value} }};'); return key
def quoted(value): return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
files = sorted((root/'Sources/CDScribeApp').glob('*.swift'))
refs = []; buildfiles = []
for file in files:
    relative = str(file.relative_to(root))
    ref = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(relative)}; sourceTree = "<group>";')
    refs.append(ref); buildfiles.append(obj(relative+'build', f'isa = PBXBuildFile; fileRef = {ref};'))
plist = obj('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = "<group>";')
icon = obj('icon', 'isa = PBXFileReference; lastKnownFileType = image.icns; path = Resources/AppIcon.icns; sourceTree = "<group>";')
iconbuild = obj('iconbuild', f'isa = PBXBuildFile; fileRef = {icon};')
app = obj('app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CDScribe.app; sourceTree = BUILT_PRODUCTS_DIR;')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
product = obj('product', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = CDScribeCore;')
framework = obj('framework', f'isa = PBXBuildFile; productRef = {product};')
sources = obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(buildfiles)+'); runOnlyForDeploymentPostprocessing = 0;')
resources = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({iconbuild}); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework}); runOnlyForDeploymentPostprocessing = 0;')
products = obj('products', f'isa = PBXGroup; children = ({app}); name = Products; sourceTree = "<group>";')
group = obj('group', 'isa = PBXGroup; children = ('+', '.join(refs+[plist,icon,products])+'); sourceTree = "<group>";')
def config(name, release, appconfig):
    settings = {'SDKROOT':'macosx', 'MACOSX_DEPLOYMENT_TARGET':'15.0', 'SWIFT_VERSION':'6.0', 'ARCHS':'arm64', 'CLANG_ENABLE_MODULES':'YES', 'SWIFT_STRICT_CONCURRENCY':'complete'}
    if appconfig:
        settings.update({'PRODUCT_NAME':'CDScribe', 'PRODUCT_BUNDLE_IDENTIFIER':'io.github.leodenglovescode.CDScribe', 'INFOPLIST_FILE':'Resources/Info.plist', 'CODE_SIGN_STYLE':'Automatic', 'CODE_SIGN_IDENTITY':'-', 'ENABLE_APP_SANDBOX':'NO', 'ENABLE_HARDENED_RUNTIME':'NO', 'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks', 'GENERATE_INFOPLIST_FILE':'NO'})
    if release: settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-O', 'DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
    else: settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG', 'ENABLE_TESTABILITY':'YES', 'ONLY_ACTIVE_ARCH':'YES'})
    return obj(name, 'isa = XCBuildConfiguration; buildSettings = {' + ' '.join(f'{key} = {quoted(value)};' for key,value in settings.items()) + '}; name = '+ ('Release' if release else 'Debug') + ';')
projectconfigs = [config('projectDebug',False,False),config('projectRelease',True,False)]
targetconfigs = [config('appDebug',False,True),config('appRelease',True,True)]
def configs(name, ids): return obj(name, 'isa = XCConfigurationList; buildConfigurations = ('+', '.join(ids)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pcl = configs('projectconfigs',projectconfigs); tcl = configs('targetconfigs',targetconfigs)
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tcl}; buildPhases = ({sources}, {frameworks}, {resources}); buildRules = (); dependencies = (); name = CDScribe; packageProductDependencies = ({product}); productName = CDScribe; productReference = {app}; productType = "com.apple.product-type.application";')
project = obj('project', f'isa = PBXProject; attributes = {{ LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; }}; buildConfigurationList = {pcl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}); targets = ({target});')
folder = root/'CDScribe.xcodeproj'; (folder/'xcshareddata/xcschemes').mkdir(parents=True,exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+project+'; }\n')
(folder/'xcshareddata/xcschemes/CDScribe.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CDScribe.app" BlueprintName="CDScribe" ReferencedContainer="container:CDScribe.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CDScribe.app" BlueprintName="CDScribe" ReferencedContainer="container:CDScribe.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CDScribe.app" BlueprintName="CDScribe" ReferencedContainer="container:CDScribe.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
