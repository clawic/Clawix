#!/usr/bin/env node
// View render thinness check (ADR 0041).
//
// Static guard for the render-layer-thinness charter: a row-body file is
// DRAW-ONLY. It receives an already-computed display model and only draws it.
// A `var body` must not DERIVE anything at render time:
//   - no `Date()`/`Calendar` math (the timestamp arrives pre-formatted),
//   - no `MarkdownParseCache.parse` / markdown parse (the off-body parse lives
//     in the render model / compute layer),
//   - no `PlanSegmenter.segments` segment derivation (content arrives split),
//   - no `.sorted`/`.filter` over a message/timeline array,
//   - no relative-age formatting (`L10n.relativeAge` / `RelativeAge.label`).
//
// Derivation lives in the centralized, bounded compute/presentation layer
// (`SessionPresentationStore`, `SidebarSnapshot`, `MessageRowDisplayModel`,
// `RecentChatRowDisplayModel`) and never in a view body. A genuinely bounded
// exception inside a body must carry an inline marker:
//   `// render-thin-ok max<Bytes|Items>=<n> reason=<...>`
//
// The check strips comments and string literals before matching, so doc
// comments that DESCRIBE the forbidden derivations (the row files document what
// they intentionally do NOT do) never trip the guard.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const defaultRootDir = path.resolve(new URL("..", import.meta.url).pathname);

function parseArgs(argv) {
  const args = { rootDir: defaultRootDir, selfTest: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--root") args.rootDir = path.resolve(argv[++index]);
    else if (arg === "--self-test") args.selfTest = true;
    else throw new Error(`unknown argument ${arg}`);
  }
  return args;
}

// The render-layer leaf files this guard governs. Each is a draw-only view that
// the charter pins to a precomputed display model. NOTE: only the body files
// belong here; the compute layer (SessionPresentationStore, SidebarSnapshot,
// SessionTimestampFormatter, the RelativeAge cache) is allowed to derive and is
// deliberately NOT scanned.
const governedRowFiles = [
  "macos/Sources/Clawix/Chat/MessageRowView.swift",
  "macos/Sources/Clawix/Sidebar/SidebarView+Controls.swift",
];

const exceptionMarker = /\brender-thin-ok\b/u;
const boundMarker = /\bmax(?:Bytes|Items)\s*[:=]\s*[1-9][0-9_]*\b/u;
const reasonMarker = /\b(?:why|reason)\s*[:=]\s*\S+/u;

const riskRules = [
  {
    kind: "calendar-date-math-in-body",
    // Calendar/Date arithmetic or a live `Date()` clock read inside a body.
    pattern: /\b(?:Calendar\.current|Calendar\(|\.dateComponents\s*\(|\.startOfDay\s*\(|\.isDate\s*\(|Date\s*\(\s*\))/u,
  },
  {
    kind: "markdown-parse-in-body",
    pattern: /\b(?:MarkdownParseCache\.parse|AssistantMarkdownParser\.parse|AssistantMarkdown\.parse|renderMarkdown\s*\()/u,
  },
  {
    kind: "segment-derivation-in-body",
    pattern: /\bPlanSegmenter\.segments\b/u,
  },
  {
    kind: "relative-age-format-in-body",
    pattern: /\b(?:L10n\.relativeAge|RelativeAge\.label)\b/u,
  },
  {
    kind: "collection-transform-in-body",
    // `.sorted`/`.filter` applied to a message/timeline/transcript collection.
    pattern: /\b(?:messages|timeline|transcript|entries|items|workItems|rows)\b[^\n]{0,40}\.(?:sorted|filter)\s*[({]/u,
  },
];

function relative(rootDir, absolutePath) {
  return path.relative(rootDir, absolutePath).split(path.sep).join("/");
}

function readText(rootDir, relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function exists(rootDir, relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

// Replace comment and string-literal characters with spaces so matches only
// fire on real code. Preserves line structure (newlines + length) so line
// numbers and the inline-exception window stay accurate.
function maskCommentsAndStrings(source) {
  const out = source.split("");
  let index = 0;
  const length = source.length;
  let state = "code"; // code | line-comment | block-comment | string
  while (index < length) {
    const char = source[index];
    const next = source[index + 1];
    if (state === "code") {
      if (char === "/" && next === "/") {
        state = "line-comment";
        out[index] = " ";
        out[index + 1] = " ";
        index += 2;
        continue;
      }
      if (char === "/" && next === "*") {
        state = "block-comment";
        out[index] = " ";
        out[index + 1] = " ";
        index += 2;
        continue;
      }
      if (char === '"') {
        state = "string";
        index += 1; // keep the quote, mask the inside
        continue;
      }
      index += 1;
      continue;
    }
    if (state === "line-comment") {
      if (char === "\n") {
        state = "code";
        index += 1;
        continue;
      }
      out[index] = " ";
      index += 1;
      continue;
    }
    if (state === "block-comment") {
      if (char === "*" && next === "/") {
        out[index] = " ";
        out[index + 1] = " ";
        state = "code";
        index += 2;
        continue;
      }
      if (char !== "\n") out[index] = " ";
      index += 1;
      continue;
    }
    // string
    if (char === "\\") {
      out[index] = " ";
      out[index + 1] = next === "\n" ? "\n" : " ";
      index += 2;
      continue;
    }
    if (char === '"') {
      state = "code";
      index += 1; // keep the closing quote
      continue;
    }
    if (char !== "\n") out[index] = " ";
    index += 1;
  }
  return out.join("");
}

// Find each `var body: some View { ... }` region by brace matching on the
// masked source, returning [startLineIndex, endLineIndex] (0-based, inclusive).
function bodyRegions(maskedLines) {
  const regions = [];
  const headerPattern = /\bvar\s+body\s*:\s*some\s+View\b/u;
  for (let line = 0; line < maskedLines.length; line += 1) {
    if (!headerPattern.test(maskedLines[line])) continue;
    // Find the opening brace at or after this line.
    let openLine = line;
    while (openLine < maskedLines.length && !maskedLines[openLine].includes("{")) {
      openLine += 1;
    }
    if (openLine >= maskedLines.length) continue;
    let depth = 0;
    let started = false;
    let endLine = openLine;
    for (let l = openLine; l < maskedLines.length; l += 1) {
      for (const char of maskedLines[l]) {
        if (char === "{") {
          depth += 1;
          started = true;
        } else if (char === "}") {
          depth -= 1;
        }
      }
      if (started && depth <= 0) {
        endLine = l;
        break;
      }
      endLine = l;
    }
    regions.push([line, endLine]);
    line = endLine;
  }
  return regions;
}

function inRegion(lineIndex, regions) {
  return regions.some(([start, end]) => lineIndex >= start && lineIndex <= end);
}

function hasInlineException(maskedLines, rawLines, lineIndex) {
  const lo = Math.max(0, lineIndex - 2);
  const hi = Math.min(rawLines.length, lineIndex + 3);
  const window = rawLines.slice(lo, hi).join("\n");
  return exceptionMarker.test(window) && boundMarker.test(window) && reasonMarker.test(window);
}

function scanFile(rootDir, relativePath) {
  const raw = readText(rootDir, relativePath);
  const masked = maskCommentsAndStrings(raw);
  const rawLines = raw.split(/\r?\n/u);
  const maskedLines = masked.split(/\r?\n/u);
  const regions = bodyRegions(maskedLines);
  const findings = [];
  for (let line = 0; line < maskedLines.length; line += 1) {
    if (!inRegion(line, regions)) continue;
    for (const rule of riskRules) {
      if (!rule.pattern.test(maskedLines[line])) continue;
      if (hasInlineException(maskedLines, rawLines, line)) continue;
      findings.push({
        path: relativePath,
        line: line + 1,
        riskKind: rule.kind,
        snippet: rawLines[line].trim().slice(0, 160),
      });
    }
  }
  return findings;
}

function requireSnippet(rootDir, relativePath, snippet, failures) {
  if (!exists(rootDir, relativePath)) {
    failures.push(`missing ${relativePath}`);
    return;
  }
  if (!readText(rootDir, relativePath).includes(snippet)) {
    failures.push(`${relativePath} must include ${JSON.stringify(snippet)}`);
  }
}

function checkRoot(rootDir) {
  const failures = [];
  // The decision and routing the guard enforces must be reachable.
  requireSnippet(rootDir, "docs/adr/0041-render-layer-thinness-boundary.md", "The render layer is draw-only", failures);
  requireSnippet(rootDir, "docs/decision-map.md", "scripts/view_render_thinness_check.mjs", failures);
  requireSnippet(rootDir, "scripts/test.sh", "scripts/view_render_thinness_check.mjs", failures);

  let governed = 0;
  for (const relativePath of governedRowFiles) {
    if (!exists(rootDir, relativePath)) {
      failures.push(`governed row-body file missing: ${relativePath}`);
      continue;
    }
    governed += 1;
    for (const finding of scanFile(rootDir, relativePath)) {
      failures.push(
        `${finding.path}:${finding.line} ${finding.riskKind} in a view body must move to the compute layer ` +
          `or carry an inline render-thin-ok maxBytes/maxItems reason marker: ${finding.snippet}`
      );
    }
  }
  return { failures, governed };
}

function writeFixture(rootDir, relativePath, content) {
  const filePath = path.join(rootDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function fixtureDocs(rootDir) {
  writeFixture(rootDir, "docs/adr/0041-render-layer-thinness-boundary.md", "# ADR 0041\n\nThe render layer is draw-only.\n");
  writeFixture(rootDir, "docs/decision-map.md", "scripts/view_render_thinness_check.mjs\n");
  writeFixture(rootDir, "scripts/test.sh", "node scripts/view_render_thinness_check.mjs\n");
}

function spawnSelf(rootDir) {
  return spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", rootDir], { encoding: "utf8" });
}

function expectFailure(rootDir, needle) {
  const result = spawnSelf(rootDir);
  const out = `${result.stdout}${result.stderr}`;
  if (result.status === 0 || !out.includes(needle)) {
    throw new Error(`expected failure containing ${needle}, got status ${result.status}: ${out}`);
  }
}

function expectPass(rootDir) {
  const result = spawnSelf(rootDir);
  if (result.status !== 0) throw new Error(`expected pass: ${result.stdout}${result.stderr}`);
}

const cleanRowBody = `import SwiftUI
struct MessageRowView: View {
  let displayModel: MessageRowDisplayModel
  var body: some View {
    // Draw-only: timestamp arrives pre-formatted, no Date()/Calendar math here.
    // No MarkdownParseCache.parse, no PlanSegmenter.segments, no L10n.relativeAge.
    Text(verbatim: displayModel.formattedTimestamp)
  }
}
`;

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "view-render-thinness-"));
  try {
    fixtureDocs(tempRoot);
    const both = governedRowFiles;

    // Clean draw-only bodies pass; comments describing forbidden ops do not trip.
    writeFixture(tempRoot, both[0], cleanRowBody);
    writeFixture(tempRoot, both[1], "import SwiftUI\nstruct X: View { var body: some View { Text(\"x\") } }\n");
    expectPass(tempRoot);

    // Calendar/Date math in a body fails.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  var body: some View {\n    let now = Date()\n    let cal = Calendar.current\n    return Text(cal.isDate(now, inSameDayAs: now) ? \"a\" : \"b\")\n  }\n}\n");
    expectFailure(tempRoot, "calendar-date-math-in-body");

    // The same Date()/Calendar math passes behind a bounded inline exception.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  var body: some View {\n    // render-thin-ok maxItems=1 reason=single live clock badge tick\n    let now = Date()\n    return Text(String(describing: now))\n  }\n}\n");
    expectPass(tempRoot);

    // Markdown parse in a body fails.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  let text: String\n  var body: some View {\n    let parsed = MarkdownParseCache.parse(text)\n    return Text(String(describing: parsed))\n  }\n}\n");
    expectFailure(tempRoot, "markdown-parse-in-body");

    // Segment derivation in a body fails.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  let content: String\n  var body: some View {\n    ForEach(PlanSegmenter.segments(from: content), id: \\.self) { Text(String(describing: $0)) }\n  }\n}\n");
    expectFailure(tempRoot, "segment-derivation-in-body");

    // Relative-age formatting in a body fails.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  let date: Date\n  var body: some View {\n    Text(L10n.relativeAge(elapsed: 4))\n  }\n}\n");
    expectFailure(tempRoot, "relative-age-format-in-body");

    // Sorting a message/timeline array in a body fails.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  let messages: [Int]\n  var body: some View {\n    ForEach(messages.sorted(), id: \\.self) { Text(String($0)) }\n  }\n}\n");
    expectFailure(tempRoot, "collection-transform-in-body");

    // Forbidden derivation OUTSIDE a body (compute helper) is allowed.
    writeFixture(tempRoot, both[0], "import SwiftUI\nstruct MessageRowView: View {\n  static func compute() -> String { let c = Calendar.current; return String(describing: c) }\n  var body: some View { Text(MessageRowView.compute()) }\n}\n");
    expectPass(tempRoot);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

const args = parseArgs(process.argv.slice(2));
if (args.selfTest) {
  runSelfTest();
  console.log("view render thinness check self-test passed");
  process.exit(0);
}

const result = checkRoot(args.rootDir);
if (result.failures.length > 0) {
  console.error("view render thinness check failed:");
  for (const failure of result.failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`view render thinness check passed (${result.governed} row-body file(s) draw-only)`);
