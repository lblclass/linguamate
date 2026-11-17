#!/usr/bin/env node
/**
 * Static verifier for the LinguaMate project.
 *
 * Checks the things that can be checked without Xcode: Xcode project
 * integrity, source/reference consistency, plist completeness, asset
 * validity, and per-file Swift hygiene (balanced delimiters, imports, no
 * leftover placeholders).
 *
 * Run: node Tools/verify_project.js
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const APP = "LinguaMate";
const TESTS = "LinguaMateTests";

const problems = [];
const notes = [];
const fail = (message) => problems.push(message);
const note = (message) => notes.push(message);

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel), "utf8");
}
function exists(rel) {
  return fs.existsSync(path.join(ROOT, rel));
}
function walk(dir, base = dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, base));
    else out.push(path.relative(base, full).split(path.sep).join("/"));
  }
  return out;
}

// ------------------------------------------------------------------ 1. project
const pbxPath = `${APP}.xcodeproj/project.pbxproj`;
if (!exists(pbxPath)) {
  fail(`${pbxPath} is missing`);
} else {
  const pbx = read(pbxPath);
  const uuidRe = /\b[0-9A-F]{24}\b/g;
  const allUuids = pbx.match(uuidRe) || [];
  const defined = new Set();
  for (const line of pbx.split("\n")) {
    const match = line.match(/^\s*([0-9A-F]{24})\s*(?:\/\*.*?\*\/\s*)?=/);
    if (match) defined.add(match[1]);
  }
  const referenced = new Set(allUuids);
  const dangling = [...referenced].filter((id) => !defined.has(id));
  if (dangling.length) fail(`project.pbxproj references ${dangling.length} undefined object ids: ${dangling.slice(0, 5).join(", ")}`);

  const required = {
    PBXProject: 1,
    PBXNativeTarget: 2,
    XCConfigurationList: 3,
    PBXGroup: 3,
    PBXBuildFile: 20,
    PBXFileReference: 20,
    PBXSourcesBuildPhase: 2,
    PBXResourcesBuildPhase: 2,
    PBXFrameworksBuildPhase: 2,
    XCBuildConfiguration: 6,
    PBXTargetDependency: 1,
    PBXContainerItemProxy: 1,
  };
  for (const [isa, minimum] of Object.entries(required)) {
    const count = (pbx.match(new RegExp(`isa = ${isa};`, "g")) || []).length;
    if (count < minimum) fail(`project.pbxproj has ${count} ${isa} objects, expected at least ${minimum}`);
  }

  const rootMatch = pbx.match(/rootObject = ([0-9A-F]{24})/);
  if (!rootMatch || !defined.has(rootMatch[1])) fail("project.pbxproj rootObject is missing or undefined");

  const braceBalance = (pbx.match(/\{/g) || []).length - (pbx.match(/\}/g) || []).length;
  const parenBalance = (pbx.match(/\(/g) || []).length - (pbx.match(/\)/g) || []).length;
  if (braceBalance !== 0) fail(`project.pbxproj braces unbalanced by ${braceBalance}`);
  if (parenBalance !== 0) fail(`project.pbxproj parentheses unbalanced by ${parenBalance}`);
  for (const token of ["objectVersion = 56;", 'compatibilityVersion = "Xcode 14.0";', "productType = \"com.apple.product-type.application\"", "com.apple.product-type.bundle.unit-test", "TEST_HOST", "INFOPLIST_FILE", "AppIcon"]) {
    if (!pbx.includes(token)) fail(`project.pbxproj is missing required build setting/token: ${token}`);
  }
  if (pbx.includes("\r")) fail("project.pbxproj contains CRLF line endings");

  // every source file on disk must be compiled by its target
  const appSwift = walk(path.join(ROOT, APP)).filter((f) => f.endsWith(".swift"));
  const testSwift = walk(path.join(ROOT, TESTS)).filter((f) => f.endsWith(".swift"));
  const appTargetEnd = pbx.indexOf("/* End PBXSourcesBuildPhase section */");
  const appSourcesSection = pbx.slice(pbx.indexOf("/* Begin PBXSourcesBuildPhase section */"), appTargetEnd);
  const appResourcesSection = pbx.slice(
    pbx.indexOf("/* Begin PBXResourcesBuildPhase section */"),
    pbx.indexOf("/* End PBXResourcesBuildPhase section */")
  );
  for (const file of [...appSwift, ...testSwift]) {
    if (!appSourcesSection.includes(path.basename(file))) {
      fail(`${file} is not in any Sources build phase`);
    }
  }
  if (!appResourcesSection.includes("Assets.xcassets")) {
    fail("Assets.xcassets is not in the app Resources build phase");
  }
  if (appResourcesSection.includes("Info.plist")) {
    fail("Info.plist must not be copied into the bundle");
  }
  note(`project.pbxproj: ${appSwift.length} app + ${testSwift.length} test Swift files wired in`);
}

// ------------------------------------------------------------------ 2. plists
const infoPlist = `${APP}/Info.plist`;
if (!exists(infoPlist)) {
  fail(`${infoPlist} is missing`);
} else {
  const plist = read(infoPlist);
  for (const key of ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "CFBundleShortVersionString", "UILaunchScreen"]) {
    if (!plist.includes(key)) fail(`Info.plist is missing ${key}`);
  }
  const openTags = (plist.match(/<dict>/g) || []).length;
  const closeTags = (plist.match(/<\/dict>/g) || []).length;
  if (openTags !== closeTags) fail("Info.plist <dict> tags are unbalanced");
}

const privacy = `${APP}/PrivacyInfo.xcprivacy`;
if (!exists(privacy)) {
  fail(`${privacy} is missing`);
} else {
  const text = read(privacy);
  for (const token of ["NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1", "NSPrivacyTracking"]) {
    if (!text.includes(token)) fail(`PrivacyInfo.xcprivacy is missing ${token}`);
  }
}

// ------------------------------------------------------------------ 3. assets
const iconPath = `${APP}/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`;
if (!exists(iconPath)) {
  fail(`${iconPath} is missing`);
} else {
  const buffer = fs.readFileSync(path.join(ROOT, iconPath));
  const signature = buffer.slice(0, 8).toString("hex");
  if (signature !== "89504e470d0a1a0a") fail("app icon is not a PNG file");
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  const colorType = buffer[25];
  if (width !== 1024 || height !== 1024) fail(`app icon is ${width}x${height}, must be 1024x1024 (App Store requirement)`);
  if (colorType !== 2) fail(`app icon colour type is ${colorType}, iOS requires 2 (truecolour, no alpha)`);
  note(`app icon: ${width}x${height}, colour type ${colorType}, ${Math.round(buffer.length / 1024)} KB`);
}

// ------------------------------------------------------------------ 4. swift
function stripSwiftLiterals(source) {
  let out = "";
  let index = 0;
  let inLineComment = false;
  let inBlockComment = false;
  let inString = false;
  let inMultilineString = false;
  while (index < source.length) {
    const char = source[index];
    const next = source[index + 1];
    if (inLineComment) {
      if (char === "\n") {
        inLineComment = false;
        out += char;
      }
      index += 1;
      continue;
    }
    if (inBlockComment) {
      if (char === "*" && next === "/") {
        inBlockComment = false;
        index += 2;
        continue;
      }
      index += 1;
      continue;
    }
    if (inMultilineString) {
      if (source.startsWith('"""', index)) {
        inMultilineString = false;
        index += 3;
        continue;
      }
      index += 1;
      continue;
    }
    if (inString) {
      if (char === "\\") {
        index += 2;
        continue;
      }
      if (char === '"') inString = false;
      index += 1;
      continue;
    }
    if (char === "/" && next === "/") {
      inLineComment = true;
      index += 2;
      continue;
    }
    if (char === "/" && next === "*") {
      inBlockComment = true;
      index += 2;
      continue;
    }
    if (source.startsWith('"""', index)) {
      inMultilineString = true;
      index += 3;
      continue;
    }
    if (char === '"') {
      inString = true;
      index += 1;
      continue;
    }
    out += char;
    index += 1;
  }
  return out;
}

const swiftFiles = [
  ...walk(path.join(ROOT, APP)).filter((f) => f.endsWith(".swift")).map((f) => `${APP}/${f}`),
  ...walk(path.join(ROOT, TESTS)).filter((f) => f.endsWith(".swift")).map((f) => `${TESTS}/${f}`),
];

const declaredTypes = new Set();
const usedTypes = new Set();
const annotatedTypes = new Set();

for (const rel of swiftFiles) {
  const source = read(rel);
  const code = stripSwiftLiterals(source);

  for (const [open, close, label] of [["{", "}", "braces"], ["(", ")", "parentheses"], ["[", "]", "brackets"]]) {
    const delta = (code.match(new RegExp(`\\${open}`, "g")) || []).length - (code.match(new RegExp(`\\${close}`, "g")) || []).length;
    if (delta !== 0) fail(`${rel}: ${label} unbalanced by ${delta}`);
  }
  if (source.includes("\r")) fail(`${rel}: contains CRLF line endings`);
  if (source.includes("\t")) fail(`${rel}: contains tab characters`);
  if (/\b(TODO|FIXME|XXX|lorem ipsum)\b/i.test(source)) fail(`${rel}: contains a placeholder marker`);

  const importMatch = source.match(/^import\s+\w+/m);
  if (!importMatch) fail(`${rel}: has no import statement`);

  for (const match of code.matchAll(/\b(?:struct|class|enum|protocol|actor|extension)\s+([A-Z]\w*)/g)) {
    declaredTypes.add(match[1]);
  }
  for (const match of code.matchAll(/(?:->|:)\s*\[?([A-Z]\w*)/g)) {
    usedTypes.add(match[1]);
    annotatedTypes.add(match[1]);
  }
  for (const match of code.matchAll(/\b(?:struct|class|enum|protocol|actor)\s+[A-Z]\w*\s*:\s*([A-Z]\w*)/g)) {
    usedTypes.add(match[1]);
  }
  // `Type(` constructor calls
  for (const match of code.matchAll(/(?<![.\w])([A-Z]\w{2,})\s*\(/g)) {
    usedTypes.add(match[1]);
  }
}

const appleTypes = new Set([
  "Array", "Bool", "Bundle", "Character", "Codable", "Comparable", "Data", "Date", "DateFormatter", "Decodable",
  "Dictionary", "Double", "Duration", "Encodable", "Equatable", "Error", "FileManager", "Float", "Hashable",
  "Identifiable", "IndexPath", "Int", "JSONDecoder", "JSONEncoder", "JSONSerialization", "LocalizedError",
  "Locale", "NotificationCenter", "Observable", "ObservableObject", "Optional", "Result", "Self", "Sendable",
  "Set", "String", "Substring", "Task", "TimeInterval", "URL", "URLComponents", "URLRequest", "URLSession",
  "URLSessionConfiguration", "URLProtocol", "HTTPURLResponse", "URLError", "UUID", "UserDefaults", "Void",
  "XCTestCase", "XCTAssert", "XCTAssertEqual", "XCTFail",
  "XCTAssertTrue", "XCTAssertFalse", "XCTAssertNil", "XCTAssertThrowsError", "XCTAssertGreaterThanOrEqual",
  "XCTAssertLessThanOrEqual", "XCTAssertNotNil", "XCTUnwrap", "XCTMain",
  "AVAudioApplication", "AVAudioEngine", "AVAudioPCMBuffer", "AVAudioSession", "AVAudioSynthesizer",
  "AVSpeechSynthesisVoice", "AVSpeechSynthesizer", "AVSpeechSynthesizerDelegate", "AVSpeechUtterance",
  "SFSpeechAudioBufferRecognitionRequest", "SFSpeechRecognitionTask", "SFSpeechRecognizer",
  "SFSpeechRecognizerAuthorizationStatus", "SecItemAdd", "SecItemCopyMatching", "SecItemDelete",
  "SecItemUpdate", "CFDictionary", "CFTypeRef", "OSStatus", "Security",
  "Color", "ContentUnavailableView", "ForEach", "GridItem", "Group", "HStack", "Image", "Label", "LabeledContent",
  "LazyVGrid", "LazyVStack", "LinearGradient", "List", "Menu", "NavigationLink", "NavigationStack",
  "ProgressView", "ScrollView", "ScrollViewReader", "Section", "ShareLink", "Slider", "Spacer", "TabView",
  "Text", "TextField", "SecureField", "Toggle", "Picker", "ToolbarItem", "VStack", "ZStack", "Capsule", "Circle",
  "RoundedRectangle", "Rectangle", "Divider", "Button", "ShapeStyle", "View", "ViewModifier", "Binding",
  "ButtonStyle", "NavigationDestination", "EdgeInsets", "Animation", "Content", "Configuration", "MainActor",
  "Preview", "FocusState", "Environment", "State", "Bindable", "UIKit", "UIApplication", "UIPasteboard",
  "NSTemporaryDirectory", "DispatchQueue", "MainRunLoop", "EmptyView", "Any", "App", "Never",
  "NSObject", "ScrollViewProxy", "AsyncThrowingStream", "CGFloat", "CGSize", "CharacterSet", "CGPoint",
  "CGRect", "Timer", "ProcessInfo", "NSLock", "OperationQueue", "StringProtocol", "Sequence",
]);

const isKnown = (type) => declaredTypes.has(type) || appleTypes.has(type);
const missingTypes = [...annotatedTypes].filter((type) => !isKnown(type));
for (const type of missingTypes) {
  fail(`type ${type} is used in a type annotation but is neither declared in this project nor in the SDK allowlist (missing file or typo?)`);
}
const unknown = [...usedTypes].filter((type) => !isKnown(type));
if (unknown.length) {
  note(`capitalised identifiers not resolved locally (usually SDK initialisers): ${unknown.sort().join(", ")}`);
}

// ------------------------------------------------------------------ 5. fixtures
if (!exists(`${TESTS}/RunFixtures.swift`)) {
  fail("RunFixtures.swift is missing (run Tools/contract_check.js --update-fixtures)");
} else {
  const fixtures = read(`${TESTS}/RunFixtures.swift`);
  for (const token of ["[REPLY]", "[/REPLY]", "recordedEnglishAnswer", "recordedJapaneseAnswer"]) {
    if (!fixtures.includes(token)) fail(`RunFixtures.swift is missing ${token}`);
  }
  const recorded = fixtures.match(/Recorded: /);
  note(recorded ? "recorded model answers are stamped with endpoint/date" : "recorded model answers have no provenance stamp");
}

// ------------------------------------------------------------------ report
console.log(`checked ${swiftFiles.length} Swift files, ${exists(pbxPath) ? "project.pbxproj" : "no project"}, plists and assets\n`);
for (const line of notes) console.log(`NOTE  ${line}`);
for (const line of problems) console.log(`FAIL  ${line}`);
console.log(`\n${problems.length === 0 ? "STATIC CHECKS PASSED" : `${problems.length} STATIC CHECKS FAILED`}`);
process.exit(problems.length ? 1 : 0);
