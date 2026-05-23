#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const jsonMode = args.has("--json");
const selfTest = args.has("--self-test");
const requireAppBundle = args.has("--require-app-bundle");
const target = process.argv.slice(2).find((arg) => !arg.startsWith("--")) ?? "macos";
const supportedLocales = ["de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "ru", "zh-Hans"];
const sourceLanguage = "en";
const sourceExtensions = new Set([".swift", ".kt", ".java"]);
const spanishSourcePatterns = [
  { reason: "Spanish punctuation", regex: /[¿¡]/u },
  {
    reason: "Spanish wording",
    regex: /\b(?:aquí|aqui|aún|aun|cargando|escribe|empezar|mensajes|motivo|sincronizando|subtítulo|subtitulo|tarjeta|todavía|todavia|trabajas|qué|que)\b/iu,
  },
];

const scanCalls = [
  { name: "Text", kind: "call" },
  { name: "Button", kind: "call" },
  { name: "Label", kind: "call" },
  { name: "Toggle", kind: "call" },
  { name: "Picker", kind: "call" },
  { name: "TextField", kind: "call" },
  { name: "SecureField", kind: "call" },
  { name: "MCPFieldLabel", kind: "call" },
  { name: ".help", kind: "method" },
  { name: ".accessibilityLabel", kind: "method" },
  { name: "String", kind: "localizedString" },
  { name: "L10n.t", kind: "l10n" },
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function walkFiles(dir, predicate, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const next = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if ([".build", "build", ".swiftpm", "DerivedData", "node_modules"].includes(entry.name)) continue;
      walkFiles(next, predicate, acc);
    } else if (entry.isFile() && predicate(next)) {
      acc.push(next);
    }
  }
  return acc;
}

function parseSwiftString(line, start) {
  if (line[start] !== "\"") return null;
  let value = "";
  let i = start + 1;
  while (i < line.length) {
    const ch = line[i];
    if (ch === "\"") {
      return { value, end: i + 1 };
    }
    if (ch === "\\" && line[i + 1] === "(") {
      const interpolation = parseInterpolation(line, i + 2);
      if (!interpolation) return null;
      value += `\\(${interpolation.value})`;
      i = interpolation.end;
      continue;
    }
    if (ch === "\\" && i + 1 < line.length) {
      const next = line[i + 1];
      if (next === "n") value += "\n";
      else if (next === "t") value += "\t";
      else if (next === "\"") value += "\"";
      else if (next === "\\") value += "\\";
      else value += `\\${next}`;
      i += 2;
      continue;
    }
    value += ch;
    i += 1;
  }
  return null;
}

function parseInterpolation(line, start) {
  let depth = 1;
  let i = start;
  let value = "";
  let inString = false;
  while (i < line.length) {
    const ch = line[i];
    if (inString) {
      value += ch;
      if (ch === "\\" && i + 1 < line.length) {
        value += line[i + 1];
        i += 2;
        continue;
      }
      if (ch === "\"") inString = false;
      i += 1;
      continue;
    }
    if (ch === "\"") {
      inString = true;
      value += ch;
      i += 1;
      continue;
    }
    if (ch === "(") {
      depth += 1;
      value += ch;
      i += 1;
      continue;
    }
    if (ch === ")") {
      depth -= 1;
      if (depth === 0) return { value, end: i + 1 };
      value += ch;
      i += 1;
      continue;
    }
    value += ch;
    i += 1;
  }
  return null;
}

function skipWhitespace(line, index) {
  let i = index;
  while (i < line.length && /\s/.test(line[i])) i += 1;
  return i;
}

function parseFirstStringArgument(line, openParenIndex, { requireLabel } = {}) {
  let i = skipWhitespace(line, openParenIndex + 1);
  if (line.startsWith("verbatim:", i)) {
    return { skipped: "verbatim" };
  }
  if (requireLabel) {
    if (!line.startsWith(`${requireLabel}:`, i)) return null;
    i = skipWhitespace(line, i + requireLabel.length + 1);
  }
  if (line[i] !== "\"") return null;
  const parsed = parseSwiftString(line, i);
  if (!parsed) return null;
  return { value: parsed.value };
}

function findCallOpenParens(line, call) {
  const results = [];
  let index = 0;
  while (index < line.length) {
    const found = line.indexOf(call.name, index);
    if (found === -1) break;
    const before = found === 0 ? "" : line[found - 1];
    const afterName = found + call.name.length;
    if (call.kind !== "method" && /[A-Za-z0-9_]/.test(before)) {
      index = afterName;
      continue;
    }
    let openParen = -1;
    if (call.kind === "localizedString") {
      openParen = line.indexOf("(", afterName);
      if (openParen === -1 || line.slice(afterName, openParen).trim() !== "") {
        index = afterName;
        continue;
      }
    } else {
      openParen = skipWhitespace(line, afterName);
      if (line[openParen] !== "(") {
        index = afterName;
        continue;
      }
    }
    results.push(openParen);
    index = openParen + 1;
  }
  return results;
}

function isCommentLine(line) {
  const trimmed = line.trimStart();
  return trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("/*");
}

function isNonUserLiteral(value) {
  const trimmed = value.trim();
  if (!trimmed) return true;
  if (["px", "ESC"].includes(trimmed)) return true;
  if (/^[0-9%() _.\/\\>_<⌘·:|+\-–—•]+$/.test(trimmed)) return true;
  if (/^#[0-9A-Fa-f]{3,8}$/.test(trimmed)) return true;
  if (/^~?\//.test(trimmed)) return true;
  if (/^https?:\/\//.test(trimmed)) return true;
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return true;
  if (/^[a-z]{2,8}_[.…]+$/.test(trimmed)) return true;
  if (/^[A-Za-z0-9_.-]+\.(json|toml|yaml|yml|sqlite|db|md|swift|ts|js|mjs|tsx|jsx)$/.test(trimmed)) return true;
  if (/^[A-Za-z0-9_.-]+$/.test(trimmed) && /[._-]/.test(trimmed)) return true;
  if (/^[A-Z0-9_]{2,}$/.test(trimmed) && !["OK", "ON", "OFF"].includes(trimmed)) return true;
  return false;
}

function isNonUserCatalogKey(key) {
  const trimmed = key.trim();
  if (/^(?:%[@d]|%lld)(?:\s*(?:[·|:,+\-–—/()])\s*(?:%[@d]|%lld))*$/.test(trimmed)) return true;
  if (!trimmed.replace(/%lld|%[@d]/g, "").replace(/[0-9%() _.\/\\>_<⌘·:|,+\-–—•]/g, "").trim()) return true;
  return isNonUserLiteral(trimmed);
}

function interpolationPlaceholder(expression) {
  const expr = expression.trim();
  if (expr.includes("\"")) return "%@";
  if (/\b(Int|UInt|Double|Float|CGFloat)\s*\(/.test(expr)) return "%lld";
  if (/\b(count|index|number|seconds|minutes|mins|percent|total|used|remaining)\b/i.test(expr)) return "%lld";
  return "%@";
}

function catalogKeyForSwiftValue(value) {
  let output = "";
  let i = 0;
  while (i < value.length) {
    if (value[i] === "\\" && value[i + 1] === "(") {
      const interpolation = parseInterpolation(value, i + 2);
      if (!interpolation) {
        output += value[i];
        i += 1;
        continue;
      }
      output += interpolationPlaceholder(interpolation.value);
      i = interpolation.end;
      continue;
    }
    output += value[i];
    i += 1;
  }
  return output;
}

function keyCandidates(value) {
  const candidates = new Set([value, catalogKeyForSwiftValue(value)]);
  candidates.add(value.replace(/\\\(Int\([^)]*\)\)/g, "%lld").replace(/\\\([^)]*\)/g, "%@"));
  candidates.add(value.replace(/\\\([^)]*\)/g, "%lld"));
  return candidates;
}

function scanSwiftFile(filePath, projectDir) {
  const findings = [];
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    if (isCommentLine(line)) continue;
    for (const call of scanCalls) {
      for (const openParen of findCallOpenParens(line, call)) {
        const parsed = parseFirstStringArgument(line, openParen, {
          requireLabel: call.kind === "localizedString" ? "localized" : undefined,
        });
        if (!parsed || parsed.skipped) continue;
        const key = catalogKeyForSwiftValue(parsed.value);
        if (isNonUserLiteral(parsed.value) || isNonUserCatalogKey(key)) continue;
        findings.push({
          file: path.relative(projectDir, filePath),
          line: lineIndex + 1,
          api: call.name,
          value: parsed.value,
          key,
        });
      }
    }
  }
  return findings;
}

function spanishSourceReason(value) {
  for (const pattern of spanishSourcePatterns) {
    if (pattern.regex.test(value)) return pattern.reason;
  }
  return null;
}

function scanSpanishSourceFile(filePath, projectDir) {
  const findings = [];
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    if (isCommentLine(line)) {
      const reason = spanishSourceReason(line);
      if (reason) {
        findings.push({
          file: path.relative(projectDir, filePath),
          line: lineIndex + 1,
          kind: "comment",
          value: line.trim(),
          reason,
        });
      }
      continue;
    }
    for (const call of scanCalls) {
      for (const openParen of findCallOpenParens(line, call)) {
        const parsed = parseFirstStringArgument(line, openParen, {
          requireLabel: call.kind === "localizedString" ? "localized" : undefined,
        });
        if (!parsed || parsed.skipped) continue;
        const reason = spanishSourceReason(parsed.value);
        if (reason) {
          findings.push({
            file: path.relative(projectDir, filePath),
            line: lineIndex + 1,
            kind: call.name,
            value: parsed.value,
            reason,
          });
        }
      }
    }
  }
  return findings;
}

function localizationStateFor(entry, locale) {
  const loc = entry?.localizations?.[locale];
  if (!loc) return null;
  if (loc.stringUnit?.value) return "value";
  if (loc.variations?.plural) return "plural";
  return null;
}

function validateCatalog(catalog) {
  const missing = [];
  const strings = catalog.strings ?? {};
  if (catalog.sourceLanguage !== sourceLanguage) {
    missing.push({ key: "<catalog>", locale: sourceLanguage, reason: `sourceLanguage must be ${sourceLanguage}` });
  }
  for (const [key, entry] of Object.entries(strings)) {
    if (key.startsWith("_zzz_")) continue;
    for (const locale of supportedLocales) {
      if (!localizationStateFor(entry, locale)) {
        missing.push({ key, locale, reason: "missing localized value" });
      }
    }
  }
  return missing;
}

function validateGeneratedResources(projectDir) {
  const missing = [];
  const resourceDir = path.join(projectDir, "Sources/Clawix/Resources");
  const appResourceDir = path.join(projectDir, "build/Clawix.app/Contents/Resources");
  for (const locale of supportedLocales) {
    for (const name of ["Localizable.strings", "Localizable.stringsdict"]) {
      const filePath = path.join(resourceDir, `${locale}.lproj`, name);
      if (!fs.existsSync(filePath)) missing.push(path.relative(projectDir, filePath));
    }
    if (requireAppBundle) {
      const appLocale = ["pt-BR", "zh-Hans"].includes(locale) ? locale.toLowerCase() : locale;
      const appStrings = path.join(appResourceDir, `${appLocale}.lproj/Localizable.strings`);
      if (!fs.existsSync(appStrings)) missing.push(path.relative(projectDir, appStrings));
    }
  }
  if (requireAppBundle) {
    const bundle = path.join(appResourceDir, "Clawix_Clawix.bundle");
    if (!fs.existsSync(bundle)) missing.push(path.relative(projectDir, bundle));
  }
  return missing;
}

function validateMacos() {
  const projectDir = path.join(rootDir, "macos");
  const catalogPath = path.join(projectDir, "Sources/Clawix/Resources/Localizable.xcstrings");
  const catalog = readJson(catalogPath);
  const strings = catalog.strings ?? {};
  const catalogKeys = new Set(Object.keys(strings));
  const sourceDir = path.join(projectDir, "Sources/Clawix");
  const swiftFiles = walkFiles(sourceDir, (filePath) => filePath.endsWith(".swift"));
  const candidates = swiftFiles.flatMap((filePath) => scanSwiftFile(filePath, projectDir));
  const unregistered = candidates.filter((finding) => {
    for (const candidate of keyCandidates(finding.value)) {
      if (catalogKeys.has(candidate)) return false;
    }
    return true;
  });
  return {
    target: "macos",
    supportedLocales,
    missingCatalogLocalizations: validateCatalog(catalog),
    unregisteredUiStrings: unregistered,
    generatedResourceMissing: validateGeneratedResources(projectDir),
    spanishSourceText: validateSpanishSourceText(),
  };
}

function validateSpanishSourceText() {
  const sourceRoots = [
    path.join(rootDir, "macos/Sources/Clawix"),
    path.join(rootDir, "ios/Sources/Clawix"),
    path.join(rootDir, "android/app/src/main/java"),
    path.join(rootDir, "packages"),
  ].filter((dir) => fs.existsSync(dir));
  const projectDir = rootDir;
  const files = sourceRoots.flatMap((dir) => walkFiles(
    dir,
    (filePath) => sourceExtensions.has(path.extname(filePath)),
  ));
  return files.flatMap((filePath) => scanSpanishSourceFile(filePath, projectDir));
}

function formatReport(report) {
  const lines = [];
  const sections = [
    ["missing catalog localizations", report.missingCatalogLocalizations],
    ["unregistered UI strings", report.unregisteredUiStrings],
    ["missing generated resources", report.generatedResourceMissing],
    ["Spanish comments or visible source strings", report.spanishSourceText],
  ];
  for (const [label, items] of sections) {
    if (items.length === 0) continue;
    lines.push(label);
    for (const item of items.slice(0, 80)) {
      if (typeof item === "string") lines.push(`  ${item}`);
      else if (item.file && item.key) lines.push(`  ${item.file}:${item.line}: ${item.value} -> ${item.key}`);
      else if (item.file) lines.push(`  ${item.file}:${item.line}: ${item.kind}: ${item.value} (${item.reason})`);
      else lines.push(`  ${item.key} [${item.locale}]: ${item.reason}`);
    }
    if (items.length > 80) lines.push(`  ... ${items.length - 80} more`);
  }
  if (lines.length === 0) {
    lines.push("localization surface guard passed");
  }
  return lines.join("\n");
}

function hasFailures(report) {
  return report.missingCatalogLocalizations.length > 0
    || report.unregisteredUiStrings.length > 0
    || report.generatedResourceMissing.length > 0
    || report.spanishSourceText.length > 0;
}

function runSelfTest() {
  const parsed = parseSwiftString('Text("Hello \\(name)")', 5);
  if (!parsed || parsed.value !== "Hello \\(name)") throw new Error("failed to parse interpolated Swift string");
  const ternary = parseSwiftString('Text("\\(count) item\\(count == 1 ? "" : "s")")', 5);
  if (!ternary || ternary.value !== '\\(count) item\\(count == 1 ? "" : "s")') {
    throw new Error("failed to parse Swift interpolation containing quoted strings");
  }
  const ignored = parseFirstStringArgument('Text(verbatim: "skill-id")', 4);
  if (!ignored?.skipped) throw new Error("failed to skip Text(verbatim:)");
  if (!isNonUserLiteral("skill-id")) throw new Error("failed to classify technical identifier");
  if (isNonUserLiteral("Approval required")) throw new Error("misclassified visible copy");
  if (catalogKeyForSwiftValue("Used \\(name) \\(count) times") !== "Used %@ %lld times") {
    throw new Error("failed to normalize Swift interpolation");
  }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-localization-guard."));
  try {
    const fixture = path.join(tmp, "Fixture.swift");
    fs.writeFileSync(fixture, [
      'Text("Approval required")',
      'Text(verbatim: "agent-id")',
      'String(localized: "Used \\(name)")',
    ].join("\n"));
    const findings = scanSwiftFile(fixture, tmp);
    if (findings.length !== 2) throw new Error(`expected 2 fixture findings, got ${findings.length}`);
    fs.writeFileSync(fixture, [
      '/// Cargando este chat while loading',
      'Text("Aún no hay mensajes")',
    ].join("\n"));
    const spanishFindings = scanSpanishSourceFile(fixture, tmp);
    if (spanishFindings.length !== 2) {
      throw new Error(`expected 2 Spanish source findings, got ${spanishFindings.length}`);
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

if (selfTest) {
  runSelfTest();
  if (!jsonMode) console.log("localization surface guard self-test passed");
  else console.log(JSON.stringify({ ok: true }, null, 2));
  process.exit(0);
}

if (target !== "macos") {
  console.error(`unsupported localization surface target: ${target}`);
  process.exit(2);
}

const report = validateMacos();
if (jsonMode) {
  console.log(JSON.stringify({ ok: !hasFailures(report), ...report }, null, 2));
} else {
  console.log(formatReport(report));
}
process.exitCode = hasFailures(report) ? 1 : 0;
