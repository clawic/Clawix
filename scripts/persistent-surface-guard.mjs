#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);

const rules = [
  {
    id: "ts.direct-api-route",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /(["'`])\/v\d+\/[A-Za-z0-9_/${}().{}?=&:-]+\1/,
    message: "stable API routes must be registered through stable surface builders",
  },
  {
    id: "ts.direct-private-api-route",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /(["'`])\/api\/[A-Za-z0-9_/${}().{}?=&:-]+\1/,
    message: "stable private app/host API routes must be registered through stable surface builders",
  },
  {
    id: "ts.direct-env-var",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /process\.env\.(?:CLAW|CLAWIX)_[A-Z0-9_]+|process\.env\[\s*(["'`])(?:CLAW|CLAWIX)_[A-Z0-9_]+\1\s*\]/,
    message: "owned environment variables must be registered as envVar surfaces",
  },
  {
    id: "ts.direct-event-topic",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /\b(?:event|topic|queue|eventType|type)\s*:\s*(["'`])[a-z][a-z0-9-]*\.[a-z0-9_.-]+\1/,
    message: "event and queue topics must be registered through stable surface builders",
  },
  {
    id: "ts.direct-schema-version-field",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /(["'`])(?:schemaVersion|protocolVersion|sessionId|recordId|runtimeId|agentId)\1\s*:/,
    message: "stable JSON fields must be registered through stable surface builders or typed schemas",
  },
  {
    id: "ts.direct-database-path",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /new\s+Database\s*\([^;\n]*(?:path\.join|join)\s*\(/,
    message: "database paths must be produced by persistent surface builders",
  },
  {
    id: "ts.direct-claw-path",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /(?:path\.join|join)\s*\([^;\n]*(["'`])(?:\.claw|\.clawix|\.clawjs|~\/\.claw|~\/\.clawix)/,
    message: "durable Claw paths must be registered through persistent surface builders",
  },
  {
    id: "ts.local-storage-literal",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /localStorage\.(?:getItem|setItem|removeItem)\(\s*(["'`])[^"'`]+\1/,
    message: "browser storage keys must be registered as browserStorageKey surfaces",
  },
  {
    id: "ts.bridge-name-literal",
    extensions: [".ts", ".tsx", ".js", ".mjs"],
    pattern: /(["'`])(?:clawix-bridge|clawix\.bridge|_clawix-bridge\._tcp)\1/,
    message: "bridge service names must be registered as native identity surfaces",
  },
  {
    id: "ts.ddl-literal",
    extensions: [".ts", ".tsx", ".js", ".mjs", ".sql"],
    pattern: /\bCREATE\s+(?:TABLE|INDEX)\b/i,
    message: "DDL tables and indexes must be registered as table/index surfaces",
  },
  {
    id: "swift.user-defaults-literal",
    extensions: [".swift"],
    pattern: /UserDefaults(?:\.standard)?\.(?:set|string|stringArray|bool|object|integer|double|data|dictionary|removeObject)\([^;\n]*forKey:\s*"[^"]+"/,
    message: "UserDefaults keys must be registered as preferenceKey surfaces",
  },
  {
    id: "swift.direct-api-route",
    extensions: [".swift"],
    pattern: /"\/(?:v\d+|api)\/[A-Za-z0-9_/${}().{}?=&:-]+"/,
    message: "stable Swift API routes must be registered through stable surface builders",
  },
  {
    id: "swift.direct-env-var",
    extensions: [".swift"],
    pattern: /environment\[\s*"(?:CLAW|CLAWIX)_[A-Z0-9_]+"\s*\]|ProcessInfo\.processInfo\.environment\[\s*"(?:CLAW|CLAWIX)_[A-Z0-9_]+"\s*\]/,
    message: "owned Swift environment variables must be registered as envVar surfaces",
  },
  {
    id: "swift.direct-coding-key",
    extensions: [".swift"],
    pattern: /\bcase\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"(?:schemaVersion|protocolVersion|sessionId|recordId|runtimeId|agentId|clientId|installationId|deviceId|requestId|threadId|type|state|role|status)"/,
    message: "wire CodingKeys must be registered through stable surface builders",
  },
  {
    id: "swift.user-defaults-suite-literal",
    extensions: [".swift"],
    pattern: /UserDefaults\s*\(\s*suiteName:\s*"[^"]+"/,
    message: "UserDefaults suite names must be registered as preferenceKey surfaces",
  },
  {
    id: "swift.sidebar-prefs-literal",
    extensions: [".swift"],
    pattern: /SidebarPrefs\.(?:bool|store\.set|store\.bool)\([^;\n]*forKey:\s*"[^"]+"/,
    message: "SidebarPrefs keys must be registered as preferenceKey surfaces",
  },
  {
    id: "swift.app-storage-literal",
    extensions: [".swift"],
    pattern: /@AppStorage\("[^"]+"/,
    message: "AppStorage keys must be registered as appStorageKey surfaces",
  },
  {
    id: "swift.database-queue-path",
    extensions: [".swift"],
    pattern: /DatabaseQueue\s*\(\s*path:/,
    message: "GRDB database paths must be registered as database surfaces",
  },
  {
    id: "swift.persistent-path-component",
    extensions: [".swift"],
    pattern: /appendingPathComponent\("(?:(?:Clawix)|(?:\.claw(?:ix)?)|(?:resources\.json)|[^"]*(?:\.sqlite|bridge-status|host-action-audit|mac-control-timeline|mac-control-pending-approvals|dictation-audio)[^"]*)"/,
    message: "durable Swift path components must be registered through persistent surface builders",
  },
  {
    id: "swift.bridge-name-literal",
    extensions: [".swift"],
    pattern: /"(?:clawix-bridge|clawix\.bridge|_clawix-bridge\._tcp)"/,
    message: "bridge service names must be registered as native identity surfaces",
  },
  {
    id: "swift.native-permission-literal",
    extensions: [".swift"],
    pattern: /"(?:mac\.permission\.[a-z0-9_]+)"/,
    message: "native permission ids must be registered as nativePermission surfaces",
  },
  {
    id: "kotlin.direct-api-route",
    extensions: [".kt", ".kts", ".java"],
    pattern: /"\/(?:v\d+|api)\/[A-Za-z0-9_/${}().{}?=&:-]+"/,
    message: "stable Kotlin/Java API routes must be registered through stable surface builders",
  },
  {
    id: "kotlin.direct-serial-name",
    extensions: [".kt", ".kts", ".java"],
    pattern: /@SerialName\("(?:schemaVersion|protocolVersion|sessionId|recordId|runtimeId|agentId|clientId|installationId|deviceId|requestId|threadId|type|state|role|status)"\)/,
    message: "wire Kotlin serial names must be registered through stable surface builders",
  },
  {
    id: "kotlin.android-permission-literal",
    extensions: [".kt", ".kts", ".java", ".xml"],
    pattern: /android\.permission\.[A-Z0-9_]+/,
    message: "Android native permissions must be registered as nativePermission surfaces",
  },
  {
    id: "csharp.direct-api-route",
    extensions: [".cs"],
    pattern: /"\/(?:v\d+|api)\/[A-Za-z0-9_/${}().{}?=&:-]+"/,
    message: "stable C# API routes must be registered through stable surface builders",
  },
  {
    id: "csharp.direct-json-property",
    extensions: [".cs"],
    pattern: /JsonPropertyName\("(?:schemaVersion|protocolVersion|sessionId|recordId|runtimeId|agentId|clientId|installationId|deviceId|requestId|threadId|type|state|role|status)"\)/,
    message: "wire C# JSON property names must be registered through stable surface builders",
  },
  {
    id: "csharp.bridge-name-literal",
    extensions: [".cs"],
    pattern: /"(?:clawix-bridge|clawix\.bridge|_clawix-bridge\._tcp)"/,
    message: "bridge service names must be registered as native identity surfaces",
  },
  {
    id: "plist.native-permission-usage",
    extensions: [".plist", ".xml"],
    pattern: /<key>NS(?:Camera|LocalNetwork|Microphone|PhotoLibrary|PhotoLibraryAdd|SpeechRecognition|Calendars|CalendarsFullAccess|Contacts)UsageDescription<\/key>/,
    message: "Apple native permission usage keys must be registered as nativePermission surfaces",
  },
];

function isBuilderFile(filePath, body) {
  return body.includes("@persistent-surface-wrapper")
    || /(?:clawPersistentSurface|clawStableSurface|ClawixPersistentSurface|PersistentSurfaceRegistry|StableSurfaceRegistry)/.test(body)
    || filePath.endsWith("persistent-surface-guard.mjs");
}

function registryText(registry) {
  if (!registry) return "";
  return typeof registry === "string" ? registry : registry.text;
}

function registryHasValue(registry, value) {
  if (!registry || !value) return false;
  if (typeof registry !== "string" && registry.values?.has(value)) return true;
  const text = registryText(registry);
  if (text.includes(value)) return true;
  const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`["'\`]${escaped}["'\`]`).test(text);
}

function isRegisteredDdlSource(filePath, body, registryBody) {
  const relative = path.relative(rootDir, filePath);
  return body.includes("@clawjs-persistent-surface-ddl-source")
    && registryText(registryBody).includes(`"${relative}"`);
}

function lineNumber(body, index) {
  return body.slice(0, index).split("\n").length;
}

function quotedRegistryContains(registryBody, value) {
  return registryHasValue(registryBody, value);
}

function registeredRouteContains(registryBody, route) {
  if (quotedRegistryContains(registryBody, route)) return true;
  const parts = route.split("/").filter(Boolean);
  for (let length = parts.length - 1; length >= 2; length -= 1) {
    const prefix = `/${parts.slice(0, length).join("/")}`;
    if (quotedRegistryContains(registryBody, prefix)) return true;
  }
  return false;
}

function isSwiftTestFixture(filePath) {
  return /\/Tests\//.test(filePath);
}

function xmlKeyValue(matched) {
  return matched.match(/<key>([^<]+)<\/key>/)?.[1];
}

function registeredRuleValue(rule, match, body, registryBody) {
  if (!registryBody) return false;
  const matched = match[0];
  const quoted = [...matched.matchAll(/["'`]([^"'`]+)["'`]/g)].map((item) => item[1]);

  if (rule.id.endsWith("direct-env-var")) {
    const env = matched.match(/(?:CLAW|CLAWIX)_[A-Z0-9_]+/)?.[0];
    return Boolean(env && quotedRegistryContains(registryBody, env));
  }

  if (rule.id.endsWith("direct-api-route") || rule.id.endsWith("direct-private-api-route")) {
    const route = quoted.find((value) => /^\/(?:v\d+|api)\//.test(value));
    return Boolean(route && registeredRouteContains(registryBody, route));
  }

  if (rule.id === "ts.direct-event-topic") {
    const topic = quoted.find((value) => /^[a-z][a-z0-9-]*\.[a-z0-9_.-]+$/.test(value));
    return Boolean(topic && quotedRegistryContains(registryBody, topic));
  }

  if (rule.id === "ts.local-storage-literal") {
    const value = quoted[0];
    return Boolean(value && quotedRegistryContains(registryBody, value));
  }

  if (rule.id === "ts.direct-claw-path") {
    const token = matched.match(/(?:\.claw(?:ix|js)?|~\/\.claw(?:ix)?|\.claw-[A-Za-z0-9_-]+)/)?.[0];
    return Boolean(token && quotedRegistryContains(registryBody, token));
  }

  if (rule.id.endsWith("bridge-name-literal")) {
    const value = quoted[0];
    return Boolean(value && quotedRegistryContains(registryBody, value));
  }

  if (rule.id === "swift.native-permission-literal") {
    const value = quoted[0];
    return Boolean(value && quotedRegistryContains(registryBody, value));
  }

  if (rule.id === "swift.persistent-path-component") {
    const value = quoted[0];
    const filePath = match.inputPath ?? "";
    return Boolean(value && (quotedRegistryContains(registryBody, value) || isSwiftTestFixture(filePath)));
  }

  if (rule.id === "kotlin.android-permission-literal") {
    const value = matched.match(/android\.permission\.[A-Z0-9_]+/)?.[0];
    return Boolean(value && quotedRegistryContains(registryBody, value));
  }

  if (rule.id === "plist.native-permission-usage") {
    const value = xmlKeyValue(matched);
    return Boolean(value && quotedRegistryContains(registryBody, value));
  }

  if (rule.id === "ts.ddl-literal") {
    return isRegisteredDdlSource(match.inputPath ?? "", body, registryBody);
  }

  return false;
}

function enclosingSwiftType(body, index) {
  const prefix = body.slice(0, index);
  const matches = [...prefix.matchAll(/\b(?:enum|struct|class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)/g)];
  return matches.at(-1)?.[1];
}

function isLikelyPersistentSwiftKey(value) {
  return /^(?:clawix|Clawix|dictation|quickAsk|FeatureFlags|Sidebar|Terminal|Life|provider|feature|SystemTelemetry)\b/.test(value)
    || /(?:\.v\d+|Defaults|Storage|Panel|Mode|Key|Enabled|Disabled|Expanded|Visible|Hidden|Width|Height|TTL|URL|Path|Port|Token|Bearer)/.test(value);
}

function swiftRegisteredKeyFindings(filePath, body, registryBody) {
  if (path.extname(filePath) !== ".swift" || !registryBody) return [];
  const findings = [];
  const pattern = /\b(?:private\s+|nonisolated\s+|static\s+|public\s+|internal\s+|fileprivate\s+)*let\s+([A-Za-z_][A-Za-z0-9_]*(?:Key|StorageKey|DefaultsKey|Suite|SuiteName|suiteName|defaultsKey|storageKey))\s*=\s*"([^"]+)"/g;
  for (const match of body.matchAll(pattern)) {
    const [, name, value] = match;
    if (!isLikelyPersistentSwiftKey(value)) continue;
    const typeName = enclosingSwiftType(body, match.index);
    const qualified = typeName ? `${typeName}.${name}` : name;
    if (!registryHasValue(registryBody, qualified) && !registryHasValue(registryBody, `.${name}`) && !registryHasValue(registryBody, value)) {
      findings.push({
        file: path.relative(rootDir, filePath),
        line: lineNumber(body, match.index),
        rule: "swift.unregistered-persistent-key",
        message: "persistent Swift key constants must be registered in the persistent surface manifest",
      });
    }
  }
  return findings;
}

function addManifestNodeValues(values, node) {
  for (const key of ["id", "key", "value", "path", "route", "fieldPath"]) {
    if (typeof node?.[key] === "string" && node[key].length > 0) {
      values.add(node[key]);
    }
  }
}

function buildRegistryIndex(files) {
  const values = new Set();
  const textParts = [];
  for (const filePath of files) {
    if (!fs.existsSync(filePath)) continue;
    const body = fs.readFileSync(filePath, "utf8");
    if (filePath.endsWith("persistent-surface-clawix.manifest.json")) {
      const manifest = JSON.parse(body);
      for (const node of manifest.nodes ?? []) {
        addManifestNodeValues(values, node);
      }
      continue;
    }
    if (filePath.endsWith("surface-registry.ts")) {
      textParts.push(body);
    }
  }
  return { values, text: textParts.join("\n") };
}

function scanFile(filePath, registryBody = "") {
  const ext = path.extname(filePath);
  if (!rules.some((rule) => rule.extensions.includes(ext))) return [];
  const body = fs.readFileSync(filePath, "utf8");
  if (isBuilderFile(filePath, body)) return [];

  const findings = [];
  for (const rule of rules) {
    if (!rule.extensions.includes(ext)) continue;
    if (rule.id === "ts.ddl-literal" && isRegisteredDdlSource(filePath, body, registryBody)) continue;
    const flags = rule.pattern.flags.includes("g") ? rule.pattern.flags : `${rule.pattern.flags}g`;
    const pattern = new RegExp(rule.pattern.source, flags);
    for (const match of body.matchAll(pattern)) {
      match.inputPath = filePath;
      if (registeredRuleValue(rule, match, body, registryBody)) continue;
      findings.push({
        file: path.relative(rootDir, filePath),
        line: lineNumber(body, match.index),
        rule: rule.id,
        message: rule.message,
      });
    }
  }
  findings.push(...swiftRegisteredKeyFindings(filePath, body, registryBody));
  return findings;
}

function listFiles(targetPath) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) return [targetPath];
  return fs.readdirSync(targetPath, { withFileTypes: true }).flatMap((entry) => {
    if (["node_modules", "dist", ".git", ".build", ".build-test", "build", ".next", ".next-e2e", ".tmp", ".claude", ".tmp-pack-smoke", "coverage", "artifacts", "test-results", "playwright-report", "output", "Resources"].includes(entry.name)) return [];
    const next = path.join(targetPath, entry.name);
    return entry.isDirectory() ? listFiles(next) : [next];
  });
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(fs.realpathSync("/tmp"), "clawix-persistent-surface-guard-"));
  const badTs = path.join(tempRoot, "bad.ts");
  const badSwift = path.join(tempRoot, "Bad.swift");
  const badKt = path.join(tempRoot, "Bad.kt");
  const badCs = path.join(tempRoot, "Bad.cs");
  const badPlist = path.join(tempRoot, "Info.plist");
  const badXml = path.join(tempRoot, "AndroidManifest.xml");
  const builderSwift = path.join(tempRoot, "PersistentSurfaceRegistry.swift");
  fs.writeFileSync(badTs, [
    "const db = new Database(path.join(home, '.claw', 'data', 'core.sqlite'));",
    "const route = '/v1/namespaces/{namespace}/collections';",
    "const privateRoute = '/api/apps/{appId}/dashboard';",
    "const home = process.env.CLAW_HOME;",
    "const payload = { event: 'workspace.initialized' };",
    "const record = { 'schemaVersion': 1 };",
    "localStorage.setItem('clawix.panel', 'open');",
    "const bridge = 'clawix-bridge';",
    "db.exec('CREATE TABLE direct_table (id TEXT PRIMARY KEY)');",
  ].join("\n"));
  fs.writeFileSync(badSwift, [
    "@AppStorage(\"SidebarViewMode\") var mode = \"all\"",
    "let route = \"/v1/mesh/jobs\"",
    "let privateRoute = \"/api/apps/dashboard\"",
    "let env = ProcessInfo.processInfo.environment[\"CLAWIX_BRIDGE_PORT\"]",
    "enum Keys: String, CodingKey { case schemaVersion = \"schemaVersion\" }",
    "UserDefaults.standard.set(true, forKey: \"DictationEnabled\")",
    "let bridgeDefaults = UserDefaults(suiteName: \"clawix.bridge\")",
    "SidebarPrefs.store.set(true, forKey: \"TerminalPanelOpen\")",
    "static let missingKey = \"quickAsk.missing\"",
    "let db = try DatabaseQueue(path: url.path)",
    "let path = root.appendingPathComponent(\"bridge-status.json\")",
    "let bridge = \"_clawix-bridge._tcp\"",
    "let permission = \"mac.permission.microphone\"",
  ].join("\n"));
  fs.writeFileSync(builderSwift, "enum ClawixPersistentSurfaceRegistry { static let nodes: [String] = [] }\n");
  fs.writeFileSync(badKt, [
    "val route = \"/v1/mesh/jobs\"",
    "@SerialName(\"schemaVersion\") val version: Int = 1",
    "val permission = \"android.permission.CAMERA\"",
  ].join("\n"));
  fs.writeFileSync(badCs, [
    "const string Route = \"/v1/mesh/jobs\";",
    "[JsonPropertyName(\"schemaVersion\")] public int SchemaVersion { get; set; }",
    "const string Bridge = \"clawix-bridge\";",
  ].join("\n"));
  fs.writeFileSync(badPlist, "<plist><dict><key>NSCameraUsageDescription</key><string>Camera</string></dict></plist>");
  fs.writeFileSync(badXml, "<manifest><uses-permission android:name=\"android.permission.RECORD_AUDIO\" /></manifest>");

  const findings = [
    ...scanFile(badTs),
    ...scanFile(badSwift, "registeredKey"),
    ...scanFile(badKt),
    ...scanFile(badCs),
    ...scanFile(badPlist),
    ...scanFile(badXml),
    ...scanFile(builderSwift),
  ];
  const foundRules = new Set(findings.map((finding) => finding.rule));
  for (const expected of [
    "ts.direct-api-route",
    "ts.direct-private-api-route",
    "ts.direct-env-var",
    "ts.direct-event-topic",
    "ts.direct-schema-version-field",
    "ts.direct-database-path",
    "ts.local-storage-literal",
    "ts.bridge-name-literal",
    "ts.ddl-literal",
    "swift.direct-api-route",
    "swift.direct-env-var",
    "swift.direct-coding-key",
    "swift.app-storage-literal",
    "swift.user-defaults-literal",
    "swift.user-defaults-suite-literal",
    "swift.sidebar-prefs-literal",
    "swift.unregistered-persistent-key",
    "swift.database-queue-path",
    "swift.persistent-path-component",
    "swift.bridge-name-literal",
    "swift.native-permission-literal",
    "kotlin.direct-api-route",
    "kotlin.direct-serial-name",
    "kotlin.android-permission-literal",
    "csharp.direct-api-route",
    "csharp.direct-json-property",
    "csharp.bridge-name-literal",
    "plist.native-permission-usage",
  ]) {
    if (!foundRules.has(expected)) {
      throw new Error(`self-test did not trigger ${expected}`);
    }
  }
  if (findings.some((finding) => finding.file.endsWith("PersistentSurfaceRegistry.swift"))) {
    throw new Error("self-test incorrectly flagged builder registry file");
  }
  console.log("persistent surface guard self-test passed");
}

function summarizeFindings(findings) {
  const byRule = {};
  const byFile = {};
  for (const finding of findings) {
    byRule[finding.rule] = (byRule[finding.rule] ?? 0) + 1;
    byFile[finding.file] = (byFile[finding.file] ?? 0) + 1;
  }
  return {
    total: findings.length,
    byRule,
    byFile,
  };
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  process.exit(0);
}

const wantsReport = process.argv.includes("--report");
const wantsJson = process.argv.includes("--json");
const targets = process.argv.slice(2).filter((arg) => !arg.startsWith("--"));
if (targets.length === 0) {
  console.error("Usage: node scripts/persistent-surface-guard.mjs --self-test | [--report] [--json] <file-or-dir>...");
  process.exit(64);
}

const allFiles = targets.flatMap((target) => listFiles(path.resolve(rootDir, target)));
const canonicalRegistryFiles = [
  path.join(rootDir, "docs/persistent-surface-clawix.manifest.json"),
  path.join(rootDir, "macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json"),
  path.join(rootDir, "../clawjs/packages/clawjs-core/src/surface-registry.ts"),
  path.join(rootDir, "../../clawjs/packages/clawjs-core/src/surface-registry.ts"),
].filter((filePath) => fs.existsSync(filePath));
const registryBody = buildRegistryIndex(
  [...allFiles, ...canonicalRegistryFiles]
    .filter((filePath) => filePath.endsWith("surface-registry.ts") || filePath.endsWith("persistent-surface-clawix.manifest.json"))
);
const findings = allFiles.flatMap((filePath) => scanFile(filePath, registryBody));
if (wantsJson) {
  console.log(JSON.stringify({ ok: findings.length === 0, summary: summarizeFindings(findings), findings }, null, 2));
  process.exit(wantsReport || findings.length === 0 ? 0 : 1);
}
if (wantsReport) {
  const summary = summarizeFindings(findings);
  console.log(`persistent surface guard report: ${summary.total} finding(s)`);
  for (const [rule, count] of Object.entries(summary.byRule).sort()) {
    console.log(`- ${rule}: ${count}`);
  }
  process.exit(0);
}
if (findings.length > 0) {
  console.error("persistent surface guard failed:");
  for (const finding of findings) {
    console.error(`- ${finding.file}:${finding.line} ${finding.rule}: ${finding.message}`);
  }
  process.exit(1);
}

console.log("persistent surface guard passed");
