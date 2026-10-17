#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
project = root/'Aura/Aura.xcodeproj'
(project/'xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)
objects = {}
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, text):
    objects[uid(name)] = text
    return uid(name)
def ref(name): return uid(name)
def refs(names): return '(' + ', '.join(ref(n) for n in names) + ',)'
def q(s): return '"' + s.replace('"','\\"') + '"'
app_files = sorted((root/'Aura/Aura/App').glob('*.swift')) + sorted((root/'Aura/Aura/Views').glob('*.swift'))
app_files = [p for p in app_files if p.name != 'AppState.swift']
test_files = sorted((root/'Aura/AuraTests').glob('*.swift'))
for category, files in [('app', app_files), ('tests', test_files)]:
    for p in files:
        name = category + '/' + p.name
        path = p.relative_to(root/'Aura').as_posix()
        add(name, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(path)+'; sourceTree = SOURCE_ROOT;}')
        add('build/'+name, '{isa = PBXBuildFile; fileRef = '+ref(name)+';}')
    add(category+'-group', '{isa = PBXGroup; children = '+refs([category+'/'+p.name for p in files])+'; name = '+q('Application' if category=='app' else 'Tests')+'; sourceTree = "<group>";}')
add('license', '{isa = PBXFileReference; lastKnownFileType = text; path = ../LICENSE; sourceTree = SOURCE_ROOT;}')
add('notices', '{isa = PBXFileReference; lastKnownFileType = text; path = ../THIRD_PARTY_NOTICES.md; sourceTree = SOURCE_ROOT;}')
add('license-build', '{isa = PBXBuildFile; fileRef = '+ref('license')+';}')
add('notices-build', '{isa = PBXBuildFile; fileRef = '+ref('notices')+';}')
add('assets', '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Aura/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;}')
add('assets-build', '{isa = PBXBuildFile; fileRef = '+ref('assets')+';}')
add('plist', '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Aura/Resources/Info.plist; sourceTree = SOURCE_ROOT;}')
add('app-product', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = AURA.app; sourceTree = BUILT_PRODUCTS_DIR;}')
add('tests-product', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AuraTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
add('products', '{isa = PBXGroup; children = '+refs(['app-product','tests-product'])+'; name = Products; sourceTree = "<group>";}')
add('main', '{isa = PBXGroup; children = '+refs(['app-group','tests-group','plist','assets','license','notices','products'])+'; sourceTree = "<group>";}')
add('package', '{isa = XCLocalSwiftPackageReference; relativePath = ..;}')
for cat, files in [('app',app_files),('tests',test_files)]:
    add(cat+'-package', '{isa = XCSwiftPackageProductDependency; package = '+ref('package')+'; productName = AuraCore;}')
    add(cat+'-package-build', '{isa = PBXBuildFile; productRef = '+ref(cat+'-package')+';}')
    add(cat+'-sources', '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+refs(['build/'+cat+'/'+p.name for p in files])+'; runOnlyForDeploymentPostprocessing = 0;}')
    add(cat+'-frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+refs([cat+'-package-build'])+'; runOnlyForDeploymentPostprocessing = 0;}')
    add(cat+'-resources', '{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = '+(refs(['license-build','notices-build','assets-build']) if cat=='app' else '()')+'; runOnlyForDeploymentPostprocessing = 0;}')
    for configuration in ['Debug','Release']:
        settings = {
            'PRODUCT_NAME': 'AURA' if cat=='app' else 'AuraTests',
            'PRODUCT_BUNDLE_IDENTIFIER': 'com.evoluere.aura' + ('.tests' if cat=='tests' else ''),
            'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': '-',
            'ENABLE_HARDENED_RUNTIME': 'YES', 'SWIFT_VERSION':'6.0',
            'SWIFT_STRICT_CONCURRENCY':'complete', 'MACOSX_DEPLOYMENT_TARGET':'15.0',
            'ARCHS':'$(ARCHS_STANDARD)', 'ONLY_ACTIVE_ARCH':'YES' if configuration=='Debug' else 'NO', 'SDKROOT':'macosx',
            'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O',
            'ENABLE_TESTABILITY':'YES' if configuration=='Debug' else 'NO',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if configuration=='Debug' else '',
            'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks',
        }
        if cat=='app':
            settings['INFOPLIST_FILE']='Aura/Resources/Info.plist'
            settings['ASSETCATALOG_COMPILER_APPICON_NAME']='AppIcon'
        else: settings['GENERATE_INFOPLIST_FILE']='YES'
        add(cat+'-'+configuration, '{isa = XCBuildConfiguration; buildSettings = {' + ''.join(k+' = '+q(v)+';' for k,v in settings.items()) + '}; name = '+configuration+';}')
    add(cat+'-configs', '{isa = XCConfigurationList; buildConfigurations = '+refs([cat+'-Debug',cat+'-Release'])+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
    add(cat+'-target', '{isa = PBXNativeTarget; buildConfigurationList = '+ref(cat+'-configs')+'; buildPhases = '+refs([cat+'-sources',cat+'-frameworks',cat+'-resources'])+'; buildRules = (); dependencies = (); name = '+('Aura' if cat=='app' else 'AuraTests')+'; packageProductDependencies = '+refs([cat+'-package'])+'; productName = '+('AURA' if cat=='app' else 'AuraTests')+'; productReference = '+ref(cat+'-product')+'; productType = '+q('com.apple.product-type.application' if cat=='app' else 'com.apple.product-type.bundle.unit-test')+';}')
for configuration in ['Debug','Release']:
    add('project-'+configuration, '{isa = XCBuildConfiguration; buildSettings = {CLANG_ENABLE_MODULES = YES; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; ARCHS = "$(ARCHS_STANDARD)"; ONLY_ACTIVE_ARCH = '+('YES' if configuration=='Debug' else 'NO')+'; SWIFT_VERSION = 6.0;}; name = '+configuration+';}')
add('project-configs', '{isa = XCConfigurationList; buildConfigurations = '+refs(['project-Debug','project-Release'])+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
add('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2710;}; buildConfigurationList = '+ref('project-configs')+'; compatibilityVersion = "Xcode 15.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = '+ref('main')+'; packageReferences = '+refs(['package'])+'; productRefGroup = '+ref('products')+'; projectDirPath = ""; projectRoot = ""; targets = '+refs(['app-target','tests-target'])+';}')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n'
text += '\n'.join(k+' = '+v+';' for k,v in objects.items())
text += '\n}; rootObject = '+ref('project')+'; }\n'
(project/'project.pbxproj').write_text(text)
def buildable(cat):
    return '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+ref(cat+'-target')+'" BuildableName="'+('AURA.app' if cat=='app' else 'AuraTests.xctest')+'" BlueprintName="'+('Aura' if cat=='app' else 'AuraTests')+'" ReferencedContainer="container:Aura.xcodeproj"/>'
scheme = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'''+buildable('app')+'''</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">'''+buildable('tests')+'''</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'''+buildable('app')+'''</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'''+buildable('app')+'''</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(project/'xcshareddata/xcschemes/Aura.xcscheme').write_text(scheme)
print('Created', project)
