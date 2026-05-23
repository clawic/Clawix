#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const jsonMode = args.has("--json");
const updateBaseline = args.has("--update-baseline");
const selfTest = args.has("--self-test");
const baselinePath = path.join(rootDir, "docs/localization-hardcoded-baseline.json");
const androidLocaleDirs = [
  "values-de",
  "values-es",
  "values-fr",
  "values-it",
  "values-ja",
  "values-ko",
  "values-pt-rBR",
  "values-ru",
  "values-b+zh+Hans",
];
const supportedLocales = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans"];

function walkFiles(dir, predicate, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const next = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if ([".build", "build", "node_modules", ".swiftpm", "DerivedData"].includes(entry.name)) continue;
      walkFiles(next, predicate, acc);
    } else if (entry.isFile() && predicate(next)) {
      acc.push(next);
    }
  }
  return acc;
}

function isIgnoredLiteral(value) {
  const text = value.trim();
  if (!text) return true;
  if (/^[?:]\s*[A-Za-z_$]/.test(text)) return true;
  if (/^[0-9%()_.\/\\:|+\-–—•×\s]+$/.test(text)) return true;
  if (/^#[0-9A-Fa-f]{3,8}$/.test(text)) return true;
  if (/^https?:\/\//.test(text)) return true;
  if (!text.replace(/\$\{[^}]+\}/g, "").match(/[A-Za-z]/)) return true;
  if (/^[A-Z0-9_]{2,}$/.test(text)) return true;
  if (/^[A-Za-z0-9_.-]+\.(json|toml|yaml|yml|sqlite|db|md|swift|ts|js|mjs|tsx|jsx|kt)$/.test(text)) return true;
  if (/^[A-Za-z0-9_.-]+$/.test(text) && /[._-]/.test(text)) return true;
  if (/^[@.#]\(?[A-Za-z0-9_.-]+\)?$/.test(text)) return true;
  return false;
}

function addFinding(findings, platform, filePath, line, kind, value) {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (isIgnoredLiteral(normalized)) return;
  findings.push({
    platform,
    file: path.relative(rootDir, filePath),
    line,
    kind,
    value: normalized,
  });
}

function lineNumberAt(content, index) {
  return content.slice(0, index).split(/\r?\n/).length;
}

function scanIosSwift(root) {
  const findings = [];
  const files = walkFiles(path.join(root, "ios/Sources"), (file) => file.endsWith(".swift"));
  const callPattern = /\b(Text|Button|Label|Toggle|Picker|TextField|SecureField|LabeledContent)\(\s*"((?:\\"|[^"])*)"/g;
  const methodPattern = /\.(accessibilityLabel|help)\(\s*"((?:\\"|[^"])*)"/g;
  for (const file of files) {
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((line, index) => {
      if (line.trimStart().startsWith("//")) return;
      for (const match of line.matchAll(callPattern)) addFinding(findings, "ios", file, index + 1, match[1], match[2]);
      for (const match of line.matchAll(methodPattern)) addFinding(findings, "ios", file, index + 1, `.${match[1]}`, match[2]);
    });
  }
  return findings;
}

function scanAndroidKotlin(root) {
  const findings = [];
  const files = walkFiles(path.join(root, "android/app/src/main/java"), (file) => file.endsWith(".kt"));
  const patterns = [
    { kind: "Text", regex: /\bText\(\s*(?:text\s*=\s*)?"((?:\\"|[^"])*)"/gs },
    { kind: "contentDescription", regex: /\bcontentDescription\s*=\s*"((?:\\"|[^"])*)"/gs },
    { kind: "placeholder", regex: /\bplaceholder\s*=\s*\{\s*Text\(\s*"((?:\\"|[^"])*)"/gs },
    { kind: "ActionRow", regex: /\bActionRow\([^)]*?(?:label\s*=\s*)?"((?:\\"|[^"])*)"/gs },
    { kind: "ActionPill", regex: /\bActionPill\([^)]*?label\s*=\s*"((?:\\"|[^"])*)"/gs },
    { kind: "ConnectionLabel", regex: /\bTriple\(\s*"((?:\\"|[^"])*)"/gs },
    { kind: "FallbackTitle", regex: /\bifBlank\s*\{\s*"((?:\\"|[^"])*)"\s*\}/gs },
  ];
  for (const file of files) {
    const content = fs.readFileSync(file, "utf8");
    const commentLineStarts = new Set(
      content
        .split(/\r?\n/)
        .map((line, index) => [line, index + 1])
        .filter(([line]) => line.trimStart().startsWith("//"))
        .map(([, lineNumber]) => lineNumber),
    );
    for (const pattern of patterns) {
      for (const match of content.matchAll(pattern.regex)) {
        const line = lineNumberAt(content, match.index);
        if (commentLineStarts.has(line)) continue;
        addFinding(findings, "android", file, line, pattern.kind, match[1]);
      }
    }
  }
  return findings;
}

function parseAndroidResourceNames(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  const names = new Set();
  for (const match of content.matchAll(/<(string|plurals)\b[^>]*\bname="([^"]+)"/g)) {
    names.add(`${match[1]}:${match[2]}`);
  }
  return names;
}

function checkAndroidResourceCompleteness(root) {
  const issues = [];
  const basePath = path.join(root, "android/app/src/main/res/values/strings.xml");
  if (!fs.existsSync(basePath)) return issues;
  const baseNames = parseAndroidResourceNames(basePath);
  for (const dir of androidLocaleDirs) {
    const localePath = path.join(root, "android/app/src/main/res", dir, "strings.xml");
    if (!fs.existsSync(localePath)) {
      issues.push({ locale: dir, missing: [...baseNames].sort(), file: path.relative(root, localePath) });
      continue;
    }
    const localeNames = parseAndroidResourceNames(localePath);
    const missing = [...baseNames].filter((name) => !localeNames.has(name)).sort();
    const extra = [...localeNames].filter((name) => !baseNames.has(name)).sort();
    if (missing.length || extra.length) {
      issues.push({
        locale: dir,
        file: path.relative(root, localePath),
        missing,
        extra,
      });
    }
  }
  return issues;
}

function scanAndroidStringReferences(root) {
  const issues = [];
  const basePath = path.join(root, "android/app/src/main/res/values/strings.xml");
  if (!fs.existsSync(basePath)) return issues;
  const stringNames = new Set([...parseAndroidResourceNames(basePath)].map((name) => name.split(":")[1]));
  const files = walkFiles(path.join(root, "android/app/src/main/java"), (file) => file.endsWith(".kt"));
  for (const file of files) {
    const content = fs.readFileSync(file, "utf8");
    for (const match of content.matchAll(/\bR\.(?:string|plurals)\.([A-Za-z0-9_]+)/g)) {
      if (!stringNames.has(match[1])) {
        issues.push({
          file: path.relative(root, file),
          line: lineNumberAt(content, match.index),
          key: match[1],
        });
      }
    }
  }
  return issues;
}

function checkAndroidResources(root = rootDir) {
  return {
    missingLocalizations: checkAndroidResourceCompleteness(root),
    missingReferences: scanAndroidStringReferences(root),
  };
}

function checkIosResourceCompleteness(root) {
  const issues = [];
  const catalogPath = path.join(root, "ios/Sources/Clawix/Resources/Localizable.xcstrings");
  if (!fs.existsSync(catalogPath)) return issues;
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  for (const [key, entry] of Object.entries(catalog.strings ?? {})) {
    if (key.startsWith("_")) continue;
    if (!entry?.localizations) continue;
    const missing = supportedLocales.filter((locale) => {
      return !hasLocalizedStringUnit(entry?.localizations?.[locale]);
    });
    if (missing.length) issues.push({ key, missing });
  }
  return issues;
}

function hasLocalizedStringUnit(localization) {
  const direct = localization?.stringUnit;
  if (direct && typeof direct.value === "string" && direct.value.length > 0) return true;
  const stack = Object.values(localization?.variations ?? {});
  while (stack.length > 0) {
    const next = stack.pop();
    if (!next || typeof next !== "object") continue;
    const unit = next.stringUnit;
    if (unit && typeof unit.value === "string" && unit.value.length > 0) return true;
    stack.push(...Object.values(next));
  }
  return false;
}

function scanIosLocalizationReferences(root) {
  const issues = [];
  const catalogPath = path.join(root, "ios/Sources/Clawix/Resources/Localizable.xcstrings");
  if (!fs.existsSync(catalogPath)) return issues;
  const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  const keys = new Set(Object.keys(catalog.strings ?? {}));
  const files = walkFiles(path.join(root, "ios/Sources"), (file) => file.endsWith(".swift"));
  for (const file of files) {
    const content = fs.readFileSync(file, "utf8");
    for (const match of content.matchAll(/\bL10n\.(?:t|format)\(\s*"((?:\\"|[^"])*)"/g)) {
      const key = match[1].replace(/\\"/g, '"');
      if (!keys.has(key)) {
        issues.push({
          file: path.relative(root, file),
          line: lineNumberAt(content, match.index),
          key,
        });
      }
    }
  }
  return issues;
}

function checkIosResources(root = rootDir) {
  return {
    missingLocalizations: checkIosResourceCompleteness(root),
    missingReferences: scanIosLocalizationReferences(root),
  };
}

function scanWebSource(root) {
  const findings = [];
  const files = walkFiles(path.join(root, "web/src"), (file) => /\.(tsx|jsx)$/.test(file));
  const attrPattern = /\b(title|subtitle|placeholder|aria-label|action|label)\s*=\s*"([^"]+)"/g;
  const jsxTextPattern = />([^<>{}]*[A-Za-z][^<>{}]*)</g;
  for (const file of files) {
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((line, index) => {
      if (line.trimStart().startsWith("//")) return;
      for (const match of line.matchAll(attrPattern)) addFinding(findings, "web", file, index + 1, match[1], match[2]);
      for (const match of line.matchAll(jsxTextPattern)) addFinding(findings, "web", file, index + 1, "jsxText", match[1]);
    });
  }
  return findings;
}

function readWebMessages(root) {
  const messagesPath = path.join(root, "web/src/localization/messages.json");
  if (!fs.existsSync(messagesPath)) return null;
  return {
    file: path.relative(root, messagesPath),
    messages: JSON.parse(fs.readFileSync(messagesPath, "utf8")),
  };
}

function isTranslatableEnglish(value) {
  return /[A-Za-z]{2,}/.test(value);
}

function checkWebResourceCompleteness(root) {
  const loaded = readWebMessages(root);
  if (!loaded) {
    return [{ file: "web/src/localization/messages.json", reason: "missing web messages catalog" }];
  }
  const issues = [];
  const localeSet = new Set(loaded.messages.supportedLocales ?? []);
  const missingSupportedLocales = supportedLocales.filter((locale) => !localeSet.has(locale));
  const extraSupportedLocales = [...localeSet].filter((locale) => !supportedLocales.includes(locale));
  if (loaded.messages.sourceLanguage !== "en" || missingSupportedLocales.length || extraSupportedLocales.length) {
    issues.push({
      file: loaded.file,
      key: "<catalog>",
      missing: missingSupportedLocales,
      extra: extraSupportedLocales,
      reason: "supported locale set must match the app locale contract",
    });
  }
  const allowedSame = loaded.messages.sameAsEnglishAllowed ?? {};
  for (const [key, entry] of Object.entries(loaded.messages.strings ?? {})) {
    const missing = supportedLocales.filter((locale) => {
      return typeof entry?.[locale] !== "string" || entry[locale].trim().length === 0;
    });
    if (missing.length) {
      issues.push({ file: loaded.file, key, missing, reason: "missing localized value" });
      continue;
    }
    const allowedLocales = new Set(allowedSame[key] ?? []);
    const sameAsEnglish = supportedLocales.filter((locale) => {
      return locale !== "en" && entry[locale] === entry.en && isTranslatableEnglish(entry.en) && !allowedLocales.has(locale);
    });
    if (sameAsEnglish.length) {
      issues.push({ file: loaded.file, key, missing: sameAsEnglish, reason: "unreviewed same-as-English localization" });
    }
  }
  return issues;
}

function scanWebLocalizationReferences(root) {
  const loaded = readWebMessages(root);
  if (!loaded) return [];
  const keys = new Set(Object.keys(loaded.messages.strings ?? {}));
  const issues = [];
  const files = walkFiles(path.join(root, "web/src"), (file) => /\.(ts|tsx|js|jsx)$/.test(file));
  for (const file of files) {
    if (file.endsWith("web/src/localization/i18n.ts")) continue;
    const content = fs.readFileSync(file, "utf8");
    for (const match of content.matchAll(/\bt\(\s*"((?:\\"|[^"])*)"/g)) {
      const key = match[1].replace(/\\"/g, '"');
      if (!keys.has(key)) {
        issues.push({
          file: path.relative(root, file),
          line: lineNumberAt(content, match.index),
          key,
        });
      }
    }
  }
  return issues;
}

function checkWebResources(root = rootDir) {
  return {
    missingLocalizations: checkWebResourceCompleteness(root),
    missingReferences: scanWebLocalizationReferences(root),
  };
}

function scanAll(root = rootDir) {
  return [
    ...scanIosSwift(root),
    ...scanAndroidKotlin(root),
    ...scanWebSource(root),
  ].sort((a, b) => a.platform.localeCompare(b.platform) || a.file.localeCompare(b.file) || a.line - b.line || a.value.localeCompare(b.value));
}

function keyFor(finding) {
  return `${finding.platform}\0${finding.kind}\0${finding.value}`;
}

function summarize(findings) {
  const byPlatform = {};
  for (const finding of findings) byPlatform[finding.platform] = (byPlatform[finding.platform] ?? 0) + 1;
  return { total: findings.length, byPlatform };
}

function readBaseline() {
  if (!fs.existsSync(baselinePath)) return null;
  return JSON.parse(fs.readFileSync(baselinePath, "utf8"));
}

function writeBaseline(findings) {
  const baseline = {
    version: 1,
    purpose: "Temporary inventory of non-macOS user-visible literals that must be reduced to zero. The guard blocks new growth.",
    findings,
  };
  fs.writeFileSync(baselinePath, JSON.stringify(baseline, null, 2) + "\n");
}

function compare(current, baseline) {
  if (!baseline) return { newFindings: current, resolvedFindings: [], baselineMissing: true };
  const baselineGroups = groupByFindingKey(baseline.findings ?? []);
  const currentGroups = groupByFindingKey(current);
  const newFindings = [];
  const resolvedFindings = [];
  for (const [key, group] of currentGroups) {
    const baselineCount = baselineGroups.get(key)?.length ?? 0;
    if (group.length > baselineCount) newFindings.push(...group.slice(baselineCount));
  }
  for (const [key, group] of baselineGroups) {
    const currentCount = currentGroups.get(key)?.length ?? 0;
    if (group.length > currentCount) resolvedFindings.push(...group.slice(currentCount));
  }
  return { newFindings, resolvedFindings, baselineMissing: false };
}

function groupByFindingKey(findings) {
  const groups = new Map();
  for (const finding of findings) {
    const key = keyFor(finding);
    const group = groups.get(key) ?? [];
    group.push(finding);
    groups.set(key, group);
  }
  return groups;
}

function runSelfTest() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-cross-platform-l10n."));
  try {
    fs.mkdirSync(path.join(tmp, "ios/Sources/App"), { recursive: true });
    fs.mkdirSync(path.join(tmp, "ios/Sources/Clawix/Resources"), { recursive: true });
    fs.mkdirSync(path.join(tmp, "android/app/src/main/java/app"), { recursive: true });
    fs.mkdirSync(path.join(tmp, "android/app/src/main/res/values"), { recursive: true });
    for (const dir of androidLocaleDirs) fs.mkdirSync(path.join(tmp, "android/app/src/main/res", dir), { recursive: true });
    fs.mkdirSync(path.join(tmp, "web/src"), { recursive: true });
    fs.writeFileSync(path.join(tmp, "ios/Sources/App/View.swift"), 'Text("Hello")\nText(verbatim: "agent-id")\nL10n.t("Hello")\n');
    const localizations = Object.fromEntries(supportedLocales.map((locale) => [locale, { stringUnit: { state: "translated", value: "Hello" } }]));
    fs.writeFileSync(
      path.join(tmp, "ios/Sources/Clawix/Resources/Localizable.xcstrings"),
      JSON.stringify({ sourceLanguage: "en", strings: { Hello: { localizations } }, version: "1.0" }),
    );
    fs.writeFileSync(path.join(tmp, "android/app/src/main/java/app/View.kt"), 'Text("Hello")\n');
    const strings = '<resources><string name="hello">Hello</string><plurals name="count"><item quantity="other">%1$d items</item></plurals></resources>';
    fs.writeFileSync(path.join(tmp, "android/app/src/main/res/values/strings.xml"), strings);
    for (const dir of androidLocaleDirs) fs.writeFileSync(path.join(tmp, "android/app/src/main/res", dir, "strings.xml"), strings);
    fs.writeFileSync(path.join(tmp, "web/src/app.tsx"), '<div title="Hello">World</div>\n');
    fs.mkdirSync(path.join(tmp, "web/src/localization"), { recursive: true });
    fs.writeFileSync(
      path.join(tmp, "web/src/localization/messages.json"),
      JSON.stringify({
        sourceLanguage: "en",
        supportedLocales,
        strings: {
          Hello: Object.fromEntries(supportedLocales.map((locale) => [locale, locale === "en" ? "Hello" : `Hello ${locale}`])),
        },
      }),
    );
    const findings = scanAll(tmp);
    if (findings.length !== 4) throw new Error(`expected 4 findings, got ${findings.length}`);
    const androidResources = checkAndroidResources(tmp);
    if (androidResources.missingLocalizations.length || androidResources.missingReferences.length) {
      throw new Error("expected Android resources to be complete");
    }
    const iosResources = checkIosResources(tmp);
    if (iosResources.missingLocalizations.length || iosResources.missingReferences.length) {
      throw new Error("expected iOS resources to be complete");
    }
    const webResources = checkWebResources(tmp);
    if (webResources.missingLocalizations.length || webResources.missingReferences.length) {
      throw new Error("expected Web resources to be complete");
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

if (selfTest) {
  runSelfTest();
  if (jsonMode) console.log(JSON.stringify({ ok: true }, null, 2));
  else console.log("cross-platform localization guard self-test passed");
  process.exit(0);
}

const current = scanAll();
if (updateBaseline) {
  writeBaseline(current);
}
const baseline = readBaseline();
const comparison = compare(current, baseline);
const androidResources = checkAndroidResources();
const iosResources = checkIosResources();
const webResources = checkWebResources();
const ok = !comparison.baselineMissing &&
  comparison.newFindings.length === 0 &&
  androidResources.missingLocalizations.length === 0 &&
  androidResources.missingReferences.length === 0 &&
  iosResources.missingLocalizations.length === 0 &&
  iosResources.missingReferences.length === 0 &&
  webResources.missingLocalizations.length === 0 &&
  webResources.missingReferences.length === 0;
const report = {
  ok,
  current: summarize(current),
  baseline: baseline ? summarize(baseline.findings ?? []) : null,
  newFindings: comparison.newFindings,
  resolvedFindings: comparison.resolvedFindings,
  androidResources,
  iosResources,
  webResources,
};

if (jsonMode) {
  console.log(JSON.stringify(report, null, 2));
} else if (ok) {
  const resolved = comparison.resolvedFindings.length;
  console.log(`cross-platform localization guard passed (${current.length} baseline findings${resolved ? `, ${resolved} resolved` : ""})`);
} else {
  if (comparison.baselineMissing) console.error("cross-platform localization baseline missing; run with --update-baseline after review");
  if (comparison.newFindings.length > 0) {
    console.error("new non-localized user-visible strings");
    for (const finding of comparison.newFindings.slice(0, 80)) {
      console.error(`  ${finding.file}:${finding.line} [${finding.platform}/${finding.kind}] ${finding.value}`);
    }
    if (comparison.newFindings.length > 80) console.error(`  ... ${comparison.newFindings.length - 80} more`);
  }
  if (androidResources.missingLocalizations.length > 0) {
    console.error("Android localized resource catalogs are incomplete");
    for (const issue of androidResources.missingLocalizations) {
      console.error(`  ${issue.file}: missing ${issue.missing.length}, extra ${issue.extra?.length ?? 0}`);
    }
  }
  if (androidResources.missingReferences.length > 0) {
    console.error("Android source references missing localized resources");
    for (const issue of androidResources.missingReferences.slice(0, 80)) {
      console.error(`  ${issue.file}:${issue.line} ${issue.key}`);
    }
  }
  if (iosResources.missingLocalizations.length > 0) {
    console.error("iOS localized string catalog is incomplete");
    for (const issue of iosResources.missingLocalizations.slice(0, 80)) {
      console.error(`  ${issue.key}: missing ${issue.missing.join(", ")}`);
    }
  }
  if (iosResources.missingReferences.length > 0) {
    console.error("iOS source references missing localized resources");
    for (const issue of iosResources.missingReferences.slice(0, 80)) {
      console.error(`  ${issue.file}:${issue.line} ${issue.key}`);
    }
  }
  if (webResources.missingLocalizations.length > 0) {
    console.error("Web localized message catalog is incomplete");
    for (const issue of webResources.missingLocalizations.slice(0, 80)) {
      console.error(`  ${issue.file}: ${issue.key}: ${issue.reason} (${issue.missing?.join(", ") ?? ""})`);
    }
  }
  if (webResources.missingReferences.length > 0) {
    console.error("Web source references missing localized messages");
    for (const issue of webResources.missingReferences.slice(0, 80)) {
      console.error(`  ${issue.file}:${issue.line} ${issue.key}`);
    }
  }
}
process.exitCode = ok ? 0 : 1;
