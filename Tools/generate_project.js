#!/usr/bin/env node
/**
 * Generates LinguaMate.xcodeproj/project.pbxproj (and project.yml for XcodeGen)
 * straight from the files on disk, so the Xcode project cannot drift from the
 * source tree. Run: node Tools/generate_project.js
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");
const APP_NAME = "LinguaMate";
const TEST_NAME = "LinguaMateTests";
const APP_DIR = path.join(ROOT, APP_NAME);
const TEST_DIR = path.join(ROOT, TEST_NAME);
const BUNDLE_ID = "com.linguamate.app";
const DEPLOYMENT_TARGET = "17.0";

const id = (key) => crypto.createHash("md5").update(key).digest("hex").slice(0, 24).toUpperCase();

function walk(dir, base = dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, entry.name);
    const rel = path.relative(base, full).split(path.sep).join("/");
    if (entry.isDirectory()) {
      if (entry.name.endsWith(".xcassets")) out.push(rel);
      else out.push(...walk(full, base));
    } else {
      out.push(rel);
    }
  }
  return out;
}

function fileType(rel) {
  if (rel.endsWith(".swift")) return "sourcecode.swift";
  if (rel.endsWith(".xcassets")) return "folder.assetcatalog";
  if (rel.endsWith(".xcprivacy")) return "text.xml";
  if (rel.endsWith(".plist")) return "text.plist.xml";
  if (rel.endsWith(".json")) return "text.json";
  if (rel.endsWith(".md")) return "net.daringfireball.markdown";
  if (rel.endsWith(".txt")) return "text";
  return "file";
}

const q = (value) => (/^[A-Za-z0-9_./$+-]+$/.test(value) ? value : `"${value}"`);

// ---------------------------------------------------------------- file sets
const appFiles = walk(APP_DIR);
const appSources = appFiles.filter((f) => f.endsWith(".swift"));
const appResources = appFiles.filter(
  (f) => !f.endsWith(".swift") && !["Info.plist"].includes(path.basename(f))
);
const testFiles = walk(TEST_DIR);
const testSources = testFiles.filter((f) => f.endsWith(".swift"));
const testResources = testFiles.filter((f) => !f.endsWith(".swift"));

function buildTree(scope, rels) {
  const root = { name: scope, relPath: "", dirs: new Map(), files: [] };
  for (const rel of rels) {
    const parts = rel.split("/");
    let node = root;
    for (let i = 0; i < parts.length - 1; i += 1) {
      const name = parts[i];
      if (!node.dirs.has(name)) {
        node.dirs.set(name, {
          name,
          relPath: node.relPath ? `${node.relPath}/${name}` : name,
          dirs: new Map(),
          files: [],
        });
      }
      node = node.dirs.get(name);
    }
    node.files.push({ name: parts[parts.length - 1], rel });
  }
  return root;
}

const appTree = buildTree(APP_NAME, appFiles);
const testTree = buildTree(TEST_NAME, testFiles);

const fileRef = (scope, rel) => id(`file:${scope}:${rel}`);
const buildFile = (target, rel) => id(`build:${target}:${rel}`);
const groupId = (scope, relPath) => id(`group:${scope}:${relPath}`);

// ------------------------------------------------------------------- ids
const ID = {
  project: id("project"),
  mainGroup: id("group:main"),
  productsGroup: id("group:products"),
  appGroup: groupId(APP_NAME, ""),
  testGroup: groupId(TEST_NAME, ""),
  appTarget: id("target:app"),
  testTarget: id("target:test"),
  appProduct: id("product:app"),
  testProduct: id("product:test"),
  appSources: id("phase:app:sources"),
  appResources: id("phase:app:resources"),
  appFrameworks: id("phase:app:frameworks"),
  testSources: id("phase:test:sources"),
  testResources: id("phase:test:resources"),
  testFrameworks: id("phase:test:frameworks"),
  projectConfigs: id("configs:project"),
  appConfigs: id("configs:app"),
  testConfigs: id("configs:test"),
  projectDebug: id("config:project:debug"),
  projectRelease: id("config:project:release"),
  appDebug: id("config:app:debug"),
  appRelease: id("config:app:release"),
  testDebug: id("config:test:debug"),
  testRelease: id("config:test:release"),
  dependency: id("dependency:test"),
  proxy: id("proxy:test"),
};

// ------------------------------------------------------------------ emit
const out = [];
const w = (line = "") => out.push(line);

function emitGroups(node, scope, groupObjectId, comment, pathValue) {
  const childLines = [];
  const groupLines = [];
  for (const file of node.files) {
    childLines.push(`\t\t\t\t${fileRef(scope, file.rel)} /* ${file.name} */,`);
  }
  for (const [, dir] of node.dirs) {
    const childId = groupId(scope, dir.relPath);
    childLines.push(`\t\t\t\t${childId} /* ${dir.name} */,`);
    groupLines.push(...emitGroups(dir, scope, childId, dir.name, dir.name));
  }
  w(`\t\t${groupObjectId} /* ${comment} */ = {`);
  w("\t\t\tisa = PBXGroup;");
  w("\t\t\tchildren = (");
  for (const line of childLines) w(line);
  w("\t\t\t);");
  if (pathValue) w(`\t\t\tpath = ${q(pathValue)};`);
  w('\t\t\tsourceTree = "<group>";');
  w("\t\t};");
  w();
  return groupLines;
}

function fileRefLine(scope, rel) {
  return `\t\t${fileRef(scope, rel)} /* ${path.basename(rel)} */ = {isa = PBXFileReference; lastKnownFileType = ${fileType(
    rel
  )}; path = ${q(path.basename(rel))}; sourceTree = "<group>"; };`;
}

w("// !$*UTF8*$!");
w("{");
w("\tarchiveVersion = 1;");
w("\tclasses = {");
w("\t};");
w("\tobjectVersion = 56;");
w("\tobjects = {");
w();

// PBXBuildFile
w("/* Begin PBXBuildFile section */");
for (const rel of appSources) {
  w(
    `\t\t${buildFile("app", rel)} /* ${path.basename(rel)} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileRef(
      APP_NAME,
      rel
    )} /* ${path.basename(rel)} */; };`
  );
}
for (const rel of appResources) {
  w(
    `\t\t${buildFile("app", rel)} /* ${path.basename(rel)} in Resources */ = {isa = PBXBuildFile; fileRef = ${fileRef(
      APP_NAME,
      rel
    )} /* ${path.basename(rel)} */; };`
  );
}
for (const rel of testSources) {
  w(
    `\t\t${buildFile("test", rel)} /* ${path.basename(rel)} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileRef(
      TEST_NAME,
      rel
    )} /* ${path.basename(rel)} */; };`
  );
}
for (const rel of testResources) {
  w(
    `\t\t${buildFile("test", rel)} /* ${path.basename(rel)} in Resources */ = {isa = PBXBuildFile; fileRef = ${fileRef(
      TEST_NAME,
      rel
    )} /* ${path.basename(rel)} */; };`
  );
}
w("/* End PBXBuildFile section */");
w();

// PBXContainerItemProxy
w("/* Begin PBXContainerItemProxy section */");
w(`\t\t${ID.proxy} /* PBXContainerItemProxy */ = {`);
w("\t\t\tisa = PBXContainerItemProxy;");
w(`\t\t\tcontainerPortal = ${ID.project} /* Project object */;`);
w("\t\t\tproxyType = 1;");
w(`\t\t\tremoteGlobalIDString = ${ID.appTarget};`);
w(`\t\t\tremoteInfo = ${APP_NAME};`);
w("\t\t};");
w("/* End PBXContainerItemProxy section */");
w();

// PBXFileReference
w("/* Begin PBXFileReference section */");
w(
  `\t\t${ID.appProduct} /* ${APP_NAME}.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ${APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; };`
);
w(
  `\t\t${ID.testProduct} /* ${TEST_NAME}.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ${TEST_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; };`
);
for (const rel of appFiles) w(fileRefLine(APP_NAME, rel));
for (const rel of testFiles) w(fileRefLine(TEST_NAME, rel));
w("/* End PBXFileReference section */");
w();

// PBXFrameworksBuildPhase
w("/* Begin PBXFrameworksBuildPhase section */");
for (const [phaseId, name] of [
  [ID.appFrameworks, APP_NAME],
  [ID.testFrameworks, TEST_NAME],
]) {
  w(`\t\t${phaseId} /* Frameworks */ = {`);
  w("\t\t\tisa = PBXFrameworksBuildPhase;");
  w("\t\t\tbuildActionMask = 2147483647;");
  w("\t\t\tfiles = (");
  w("\t\t\t);");
  w("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
  w("\t\t};");
  w();
}
w("/* End PBXFrameworksBuildPhase section */");
w();

// PBXGroup
w("/* Begin PBXGroup section */");
w(`\t\t${ID.mainGroup} = {`);
w("\t\t\tisa = PBXGroup;");
w("\t\t\tchildren = (");
w(`\t\t\t\t${ID.appGroup} /* ${APP_NAME} */,`);
w(`\t\t\t\t${ID.testGroup} /* ${TEST_NAME} */,`);
w(`\t\t\t\t${ID.productsGroup} /* Products */,`);
w("\t\t\t);");
w('\t\t\tsourceTree = "<group>";');
w("\t\t};");
w();
w(`\t\t${ID.productsGroup} /* Products */ = {`);
w("\t\t\tisa = PBXGroup;");
w("\t\t\tchildren = (");
w(`\t\t\t\t${ID.appProduct} /* ${APP_NAME}.app */,`);
w(`\t\t\t\t${ID.testProduct} /* ${TEST_NAME}.xctest */,`);
w("\t\t\t);");
w("\t\t\tname = Products;");
w('\t\t\tsourceTree = "<group>";');
w("\t\t};");
w();
emitGroups(appTree, APP_NAME, ID.appGroup, APP_NAME, APP_NAME);
emitGroups(testTree, TEST_NAME, ID.testGroup, TEST_NAME, TEST_NAME);
w("/* End PBXGroup section */");
w();

// PBXNativeTarget
w("/* Begin PBXNativeTarget section */");
w(`\t\t${ID.appTarget} /* ${APP_NAME} */ = {`);
w("\t\t\tisa = PBXNativeTarget;");
w(`\t\t\tbuildConfigurationList = ${ID.appConfigs} /* Build configuration list for PBXNativeTarget "${APP_NAME}" */;`);
w("\t\t\tbuildPhases = (");
w(`\t\t\t\t${ID.appSources} /* Sources */,`);
w(`\t\t\t\t${ID.appFrameworks} /* Frameworks */,`);
w(`\t\t\t\t${ID.appResources} /* Resources */,`);
w("\t\t\t);");
w("\t\t\tbuildRules = (");
w("\t\t\t);");
w("\t\t\tdependencies = (");
w("\t\t\t);");
w(`\t\t\tname = ${APP_NAME};`);
w(`\t\t\tproductName = ${APP_NAME};`);
w(`\t\t\tproductReference = ${ID.appProduct} /* ${APP_NAME}.app */;`);
w('\t\t\tproductType = "com.apple.product-type.application";');
w("\t\t};");
w();
w(`\t\t${ID.testTarget} /* ${TEST_NAME} */ = {`);
w("\t\t\tisa = PBXNativeTarget;");
w(
  `\t\t\tbuildConfigurationList = ${ID.testConfigs} /* Build configuration list for PBXNativeTarget "${TEST_NAME}" */;`
);
w("\t\t\tbuildPhases = (");
w(`\t\t\t\t${ID.testSources} /* Sources */,`);
w(`\t\t\t\t${ID.testFrameworks} /* Frameworks */,`);
w(`\t\t\t\t${ID.testResources} /* Resources */,`);
w("\t\t\t);");
w("\t\t\tbuildRules = (");
w("\t\t\t);");
w("\t\t\tdependencies = (");
w(`\t\t\t\t${ID.dependency} /* PBXTargetDependency */,`);
w("\t\t\t);");
w(`\t\t\tname = ${TEST_NAME};`);
w(`\t\t\tproductName = ${TEST_NAME};`);
w(`\t\t\tproductReference = ${ID.testProduct} /* ${TEST_NAME}.xctest */;`);
w('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";');
w("\t\t};");
w("/* End PBXNativeTarget section */");
w();

// PBXProject
w("/* Begin PBXProject section */");
w(`\t\t${ID.project} /* Project object */ = {`);
w("\t\t\tisa = PBXProject;");
w("\t\t\tattributes = {");
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;");
w("\t\t\t\tLastSwiftUpdateCheck = 1500;");
w("\t\t\t\tLastUpgradeCheck = 1500;");
w("\t\t\t\tTargetAttributes = {");
w(`\t\t\t\t\t${ID.appTarget} = {`);
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;");
w("\t\t\t\t\t};");
w(`\t\t\t\t\t${ID.testTarget} = {`);
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;");
w(`\t\t\t\t\t\tTestTargetID = ${ID.appTarget};`);
w("\t\t\t\t\t};");
w("\t\t\t\t};");
w("\t\t\t};");
w(`\t\t\tbuildConfigurationList = ${ID.projectConfigs} /* Build configuration list for PBXProject "LinguaMate" */;`);
w('\t\t\tcompatibilityVersion = "Xcode 14.0";');
w("\t\t\tdevelopmentRegion = en;");
w("\t\t\thasScannedForEncodings = 0;");
w("\t\t\tknownRegions = (");
w("\t\t\t\ten,");
w("\t\t\t\tBase,");
w("\t\t\t\t\"zh-Hans\",");
w("\t\t\t);");
w(`\t\t\tmainGroup = ${ID.mainGroup};`);
w(`\t\t\tproductRefGroup = ${ID.productsGroup} /* Products */;`);
w('\t\t\tprojectDirPath = "";');
w('\t\t\tprojectRoot = "";');
w("\t\t\ttargets = (");
w(`\t\t\t\t${ID.appTarget} /* ${APP_NAME} */,`);
w(`\t\t\t\t${ID.testTarget} /* ${TEST_NAME} */,`);
w("\t\t\t);");
w("\t\t};");
w("/* End PBXProject section */");
w();

// PBXResourcesBuildPhase
w("/* Begin PBXResourcesBuildPhase section */");
for (const [phaseId, files, target] of [
  [ID.appResources, appResources, "app"],
  [ID.testResources, testResources, "test"],
]) {
  w(`\t\t${phaseId} /* Resources */ = {`);
  w("\t\t\tisa = PBXResourcesBuildPhase;");
  w("\t\t\tbuildActionMask = 2147483647;");
  w("\t\t\tfiles = (");
  for (const rel of files) {
    w(
      `\t\t\t\t${buildFile(target, rel)} /* ${path.basename(rel)} in Resources */,`
    );
  }
  w("\t\t\t);");
  w("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
  w("\t\t};");
  w();
}
w("/* End PBXResourcesBuildPhase section */");
w();

// PBXSourcesBuildPhase
w("/* Begin PBXSourcesBuildPhase section */");
for (const [phaseId, files, target] of [
  [ID.appSources, appSources, "app"],
  [ID.testSources, testSources, "test"],
]) {
  w(`\t\t${phaseId} /* Sources */ = {`);
  w("\t\t\tisa = PBXSourcesBuildPhase;");
  w("\t\t\tbuildActionMask = 2147483647;");
  w("\t\t\tfiles = (");
  for (const rel of files) {
    w(`\t\t\t\t${buildFile(target, rel)} /* ${path.basename(rel)} in Sources */,`);
  }
  w("\t\t\t);");
  w("\t\t\trunOnlyForDeploymentPostprocessing = 0;");
  w("\t\t};");
  w();
}
w("/* End PBXSourcesBuildPhase section */");
w();

// PBXTargetDependency
w("/* Begin PBXTargetDependency section */");
w(`\t\t${ID.dependency} /* PBXTargetDependency */ = {`);
w("\t\t\tisa = PBXTargetDependency;");
w(`\t\t\ttarget = ${ID.appTarget} /* ${APP_NAME} */;`);
w(`\t\t\ttargetProxy = ${ID.proxy} /* PBXContainerItemProxy */;`);
w("\t\t};");
w("/* End PBXTargetDependency section */");
w();

// XCBuildConfiguration
const sharedWarnings = {
  ALWAYS_SEARCH_USER_PATHS: "NO",
  CLANG_ANALYZER_NONNULL: "YES",
  CLANG_ENABLE_MODULES: "YES",
  CLANG_ENABLE_OBJC_ARC: "YES",
  CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING: "YES",
  CLANG_WARN_BOOL_CONVERSION: "YES",
  CLANG_WARN_COMMA: "YES",
  CLANG_WARN_CONSTANT_CONVERSION: "YES",
  CLANG_WARN_DOCUMENTATION_COMMENTS: "YES",
  CLANG_WARN_EMPTY_BODY: "YES",
  CLANG_WARN_ENUM_CONVERSION: "YES",
  CLANG_WARN_INFINITE_RECURSION: "YES",
  CLANG_WARN_INT_CONVERSION: "YES",
  CLANG_WARN_UNREACHABLE_CODE: "YES",
  COPY_PHASE_STRIP: "NO",
  ENABLE_STRICT_OBJC_MSGSEND: "YES",
  ENABLE_USER_SCRIPT_SANDBOXING: "YES",
  GCC_C_LANGUAGE_STANDARD: "gnu17",
  GCC_NO_COMMON_BLOCKS: "YES",
  GCC_WARN_64_TO_32_BIT_CONVERSION: "YES",
  GCC_WARN_ABOUT_RETURN_TYPE: "YES",
  GCC_WARN_UNDECLARED_SELECTOR: "YES",
  GCC_WARN_UNINITIALIZED_AUTOS: "YES",
  GCC_WARN_UNUSED_FUNCTION: "YES",
  GCC_WARN_UNUSED_VARIABLE: "YES",
  IPHONEOS_DEPLOYMENT_TARGET: DEPLOYMENT_TARGET,
  MTL_FAST_MATH: "YES",
  SDKROOT: "iphoneos",
};

function settingsBlock(settings, indent) {
  const entries = Object.entries(settings).sort(([a], [b]) => a.localeCompare(b));
  const lines = [];
  lines.push(`${indent}buildSettings = {`);
  for (const [key, value] of entries) {
    if (Array.isArray(value)) {
      lines.push(`${indent}\t${key} = (`);
      for (const item of value) lines.push(`${indent}\t\t${q(item)},`);
      lines.push(`${indent}\t);`);
    } else {
      lines.push(`${indent}\t${key} = ${q(value)};`);
    }
  }
  lines.push(`${indent}};`);
  return lines;
}

w("/* Begin XCBuildConfiguration section */");
for (const [configId, name, settings] of [
  [
    ID.projectDebug,
    "Debug",
    {
      ...sharedWarnings,
      DEBUG_INFORMATION_FORMAT: "dwarf",
      ENABLE_TESTABILITY: "YES",
      GCC_DYNAMIC_NO_PIC: "NO",
      GCC_OPTIMIZATION_LEVEL: "0",
      GCC_PREPROCESSOR_DEFINITIONS: ["DEBUG=1", "$(inherited)"],
      MTL_ENABLE_DEBUG_INFO: "INCLUDE_SOURCE",
      ONLY_ACTIVE_ARCH: "YES",
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: "DEBUG $(inherited)",
      SWIFT_OPTIMIZATION_LEVEL: "-Onone",
    },
  ],
  [
    ID.projectRelease,
    "Release",
    {
      ...sharedWarnings,
      DEBUG_INFORMATION_FORMAT: "dwarf-with-dsym",
      ENABLE_NS_ASSERTIONS: "NO",
      MTL_ENABLE_DEBUG_INFO: "NO",
      SWIFT_COMPILATION_MODE: "wholemodule",
      VALIDATE_PRODUCT: "YES",
    },
  ],
  [
    ID.appDebug,
    "Debug",
    {
      ASSETCATALOG_COMPILER_APPICON_NAME: "AppIcon",
      ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: "AccentColor",
      CODE_SIGN_STYLE: "Automatic",
      CURRENT_PROJECT_VERSION: "1",
      ENABLE_PREVIEWS: "YES",
      GENERATE_INFOPLIST_FILE: "NO",
      INFOPLIST_FILE: `${APP_NAME}/Info.plist`,
      IPHONEOS_DEPLOYMENT_TARGET: DEPLOYMENT_TARGET,
      LD_RUNPATH_SEARCH_PATHS: ["$(inherited)", "@executable_path/Frameworks"],
      MARKETING_VERSION: "1.0",
      PRODUCT_BUNDLE_IDENTIFIER: BUNDLE_ID,
      PRODUCT_NAME: "$(TARGET_NAME)",
      SWIFT_EMIT_LOC_STRINGS: "YES",
      SWIFT_VERSION: "5.0",
      TARGETED_DEVICE_FAMILY: "1,2",
    },
  ],
  [
    ID.appRelease,
    "Release",
    {
      ASSETCATALOG_COMPILER_APPICON_NAME: "AppIcon",
      ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: "AccentColor",
      CODE_SIGN_STYLE: "Automatic",
      CURRENT_PROJECT_VERSION: "1",
      ENABLE_PREVIEWS: "YES",
      GENERATE_INFOPLIST_FILE: "NO",
      INFOPLIST_FILE: `${APP_NAME}/Info.plist`,
      IPHONEOS_DEPLOYMENT_TARGET: DEPLOYMENT_TARGET,
      LD_RUNPATH_SEARCH_PATHS: ["$(inherited)", "@executable_path/Frameworks"],
      MARKETING_VERSION: "1.0",
      PRODUCT_BUNDLE_IDENTIFIER: BUNDLE_ID,
      PRODUCT_NAME: "$(TARGET_NAME)",
      SWIFT_EMIT_LOC_STRINGS: "YES",
      SWIFT_VERSION: "5.0",
      TARGETED_DEVICE_FAMILY: "1,2",
    },
  ],
  [
    ID.testDebug,
    "Debug",
    {
      BUNDLE_LOADER: "$(TEST_HOST)",
      CODE_SIGN_STYLE: "Automatic",
      CURRENT_PROJECT_VERSION: "1",
      GENERATE_INFOPLIST_FILE: "YES",
      IPHONEOS_DEPLOYMENT_TARGET: DEPLOYMENT_TARGET,
      MARKETING_VERSION: "1.0",
      PRODUCT_BUNDLE_IDENTIFIER: `${BUNDLE_ID}.tests`,
      PRODUCT_NAME: "$(TARGET_NAME)",
      SWIFT_EMIT_LOC_STRINGS: "NO",
      SWIFT_VERSION: "5.0",
      TARGETED_DEVICE_FAMILY: "1,2",
      TEST_HOST: `$(BUILT_PRODUCTS_DIR)/${APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/${APP_NAME}`,
    },
  ],
  [
    ID.testRelease,
    "Release",
    {
      BUNDLE_LOADER: "$(TEST_HOST)",
      CODE_SIGN_STYLE: "Automatic",
      CURRENT_PROJECT_VERSION: "1",
      GENERATE_INFOPLIST_FILE: "YES",
      IPHONEOS_DEPLOYMENT_TARGET: DEPLOYMENT_TARGET,
      MARKETING_VERSION: "1.0",
      PRODUCT_BUNDLE_IDENTIFIER: `${BUNDLE_ID}.tests`,
      PRODUCT_NAME: "$(TARGET_NAME)",
      SWIFT_EMIT_LOC_STRINGS: "NO",
      SWIFT_VERSION: "5.0",
      TARGETED_DEVICE_FAMILY: "1,2",
      TEST_HOST: `$(BUILT_PRODUCTS_DIR)/${APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/${APP_NAME}`,
    },
  ],
]) {
  w(`\t\t${configId} /* ${name} */ = {`);
  w("\t\t\tisa = XCBuildConfiguration;");
  for (const line of settingsBlock(settings, "\t\t\t")) w(line);
  w(`\t\t\tname = ${name};`);
  w("\t\t};");
  w();
}
w("/* End XCBuildConfiguration section */");
w();

// XCConfigurationList
w("/* Begin XCConfigurationList section */");
for (const [listId, label, debugId, releaseId] of [
  [ID.projectConfigs, 'PBXProject "LinguaMate"', ID.projectDebug, ID.projectRelease],
  [ID.appConfigs, `PBXNativeTarget "${APP_NAME}"`, ID.appDebug, ID.appRelease],
  [ID.testConfigs, `PBXNativeTarget "${TEST_NAME}"`, ID.testDebug, ID.testRelease],
]) {
  w(`\t\t${listId} /* Build configuration list for ${label} */ = {`);
  w("\t\t\tisa = XCConfigurationList;");
  w("\t\t\tbuildConfigurations = (");
  w(`\t\t\t\t${debugId} /* Debug */,`);
  w(`\t\t\t\t${releaseId} /* Release */,`);
  w("\t\t\t);");
  w("\t\t\tdefaultConfigurationIsVisible = 0;");
  w("\t\t\tdefaultConfigurationName = Release;");
  w("\t\t};");
  w();
}
w("/* End XCConfigurationList section */");
w();

w("\t};");
w(`\trootObject = ${ID.project} /* Project object */;`);
w("}");

// ------------------------------------------------------------------- write
const projectDir = path.join(ROOT, `${APP_NAME}.xcodeproj`);
fs.mkdirSync(projectDir, { recursive: true });
fs.writeFileSync(path.join(projectDir, "project.pbxproj"), out.join("\n") + "\n", "utf8");

// Shared scheme so `xcodebuild -scheme LinguaMate` works out of the box.
const schemeDir = path.join(projectDir, "xcshareddata", "xcschemes");
fs.mkdirSync(schemeDir, { recursive: true });
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${ID.appTarget}"
               BuildableName = "${APP_NAME}.app"
               BlueprintName = "${APP_NAME}"
               ReferencedContainer = "container:${APP_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${ID.testTarget}"
               BuildableName = "${TEST_NAME}.xctest"
               BlueprintName = "${TEST_NAME}"
               ReferencedContainer = "container:${APP_NAME}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${ID.appTarget}"
            BuildableName = "${APP_NAME}.app"
            BlueprintName = "${APP_NAME}"
            ReferencedContainer = "container:${APP_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${ID.appTarget}"
            BuildableName = "${APP_NAME}.app"
            BlueprintName = "${APP_NAME}"
            ReferencedContainer = "container:${APP_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
`;
fs.writeFileSync(path.join(schemeDir, `${APP_NAME}.xcscheme`), scheme, "utf8");

// XcodeGen alternative (brew install xcodegen && xcodegen generate)
const yml = `name: ${APP_NAME}
options:
  bundleIdPrefix: com.linguamate
  deploymentTarget:
    iOS: "${DEPLOYMENT_TARGET}"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
targets:
  ${APP_NAME}:
    type: application
    platform: iOS
    sources:
      - path: ${APP_NAME}
    info:
      path: ${APP_NAME}/Info.plist
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID}
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        GENERATE_INFOPLIST_FILE: NO
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        TARGETED_DEVICE_FAMILY: "1,2"
  ${TEST_NAME}:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: ${TEST_NAME}
    dependencies:
      - target: ${APP_NAME}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID}.tests
        GENERATE_INFOPLIST_FILE: YES
`;
fs.writeFileSync(path.join(ROOT, "project.yml"), yml, "utf8");

console.log(`project.pbxproj written: ${appSources.length} app sources, ${appResources.length} app resources, ${testSources.length} test sources`);
console.log(`scheme written: ${APP_NAME}.xcscheme (test target included)`);