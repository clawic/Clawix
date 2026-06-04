#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const errors = [];

function fail(message) {
  errors.push(message);
}

function valueAfter(flag) {
  const index = rawArgs.indexOf(flag);
  if (index === -1) return null;
  return rawArgs[index + 1] ?? null;
}

const allowedFlags = new Set([
  "--self-test",
  "--render-log",
  "--phase",
  "--allow-hitch100",
  "--allow-rowbody",
]);

// Default per-window bound on cumulative `row.body` evaluations. ADR 0041/0043:
// a draw-only row re-evaluates only on a named event, so a scroll/stream window
// must stay bounded, not scale with token or timeline cardinality. Override per
// scenario with --allow-rowbody when a window legitimately mounts more rows.
const DEFAULT_ROW_BODY_BUDGET = 240;

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`markdown_render_heavy_check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function read(relativePath) {
  const absolute = path.join(rootDir, relativePath);
  if (!fs.existsSync(absolute)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(absolute, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const source = read(relativePath);
  if (!source.includes(snippet)) {
    fail(`${relativePath} must include ${snippet}`);
  }
  return source;
}

function parseMetrics(line) {
  const metrics = new Map();
  for (const match of line.matchAll(/(?:^|\s)([A-Za-z0-9_.>:-]+)=([0-9]+)/g)) {
    metrics.set(match[1], Number(match[2]));
  }
  return metrics;
}

function parsePhaseWindow(text, phase) {
  const startMarker = `MARK: ${phase}-start`;
  const endMarker = `MARK: ${phase}-end`;
  let inside = false;
  let sawStart = false;
  let sawEnd = false;
  const lines = [];

  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (line.includes(startMarker)) {
      inside = true;
      sawStart = true;
      continue;
    }
    if (line.includes(endMarker)) {
      inside = false;
      sawEnd = true;
      continue;
    }
    if (inside) lines.push({ line, lineNumber: index + 1 });
  }

  return { sawStart, sawEnd, lines };
}

function countNeedle(lines, needle) {
  return lines.reduce((total, item) => {
    let count = 0;
    let index = item.line.indexOf(needle);
    while (index !== -1) {
      count += 1;
      index = item.line.indexOf(needle, index + needle.length);
    }
    return total + count;
  }, 0);
}

function analyzeRenderLog(text, { label, phase = "scroll-chat", allowHitch100 = 0, allowRowBody = DEFAULT_ROW_BODY_BUDGET }) {
  const result = {
    sawWindow: false,
    hitch33: 0,
    hitch100: 0,
    hitch250: 0,
    hitch1000: 0,
    rowBodies: 0,
    visibleTimelineEvents: 0,
    cacheHits: 0,
    cacheMisses: 0,
    renderSamples: 0,
    findings: [],
  };

  const window = parsePhaseWindow(text, phase);
  if (!window.sawStart || !window.sawEnd) {
    result.findings.push(`${label} must include MARK: ${phase}-start/end markers`);
    return result;
  }
  result.sawWindow = true;

  result.cacheHits = countNeedle(window.lines, "parse.cache_hit");
  result.cacheMisses = countNeedle(window.lines, "parse.cache_miss");

  for (const item of window.lines) {
    if (!item.line.startsWith("[")) continue;
    const metrics = parseMetrics(item.line);
    if (
      item.line.includes("ChatView=") ||
      item.line.includes("row.body=") ||
      item.line.includes("timeline.entries.visible=") ||
      item.line.includes("parse.cache_") ||
      item.line.includes("hitch>")
    ) {
      result.renderSamples += 1;
    }
    result.hitch33 += metrics.get("hitch>33ms") ?? 0;
    result.hitch100 += metrics.get("hitch>100ms") ?? 0;
    result.hitch250 += metrics.get("hitch>250ms") ?? 0;
    result.hitch1000 += metrics.get("hitch>1000ms") ?? 0;
    result.rowBodies += metrics.get("row.body") ?? 0;
    result.visibleTimelineEvents += metrics.get("timeline.entries.visible") ?? 0;
  }

  if (result.hitch1000 > 0 || result.hitch250 > 0) {
    result.findings.push(
      `${label} ${phase} has severe hitches ` +
        `(hitch>250ms=${result.hitch250}, hitch>1000ms=${result.hitch1000})`
    );
  }
  if (result.renderSamples === 0) {
    result.findings.push(`${label} ${phase} has no render telemetry samples`);
  }
  if (result.hitch100 > allowHitch100) {
    result.findings.push(
      `${label} ${phase} exceeds allowed hitch>100ms count ` +
        `(${result.hitch100} > ${allowHitch100})`
    );
  }
  // Bound (not just observe) cumulative row.body evaluations: a draw-only row
  // re-evaluates per named event, so the window must not scale with token or
  // timeline cardinality.
  if (result.rowBodies > allowRowBody) {
    result.findings.push(
      `${label} ${phase} exceeds allowed row.body count ` +
        `(${result.rowBodies} > ${allowRowBody})`
    );
  }
  if (result.cacheHits + result.cacheMisses > 0 && result.cacheHits < result.cacheMisses) {
    result.findings.push(
      `${label} ${phase} cache hit/miss evidence regressed ` +
        `(hits=${result.cacheHits}, misses=${result.cacheMisses})`
    );
  }

  return result;
}

function runSelfTest() {
  const passingFixture = [
    "[1.000] === MARK: scroll-chat-start ===",
    "[1.500 Δ0.50s] ChatView=1 row.body=8 timeline.entries.visible=8 hitch>33ms=1",
    "[2.000 Δ0.50s] parse.cache_hit.bytes=12000 parse.cache_hit.bytes=8000 parse.cache_miss.bytes=1000",
    "[2.500] === MARK: scroll-chat-end ===",
  ].join("\n");
  const severeHitchFixture = [
    "[1.000] === MARK: scroll-chat-start ===",
    "[1.500 Δ0.50s] ChatView=1 hitch>250ms=1 hitch>100ms=1",
    "[2.500] === MARK: scroll-chat-end ===",
  ].join("\n");
  const missDominantFixture = [
    "[1.000] === MARK: scroll-chat-start ===",
    "[1.500 Δ0.50s] parse.cache_miss.bytes=1 parse.cache_miss.bytes=2 parse.cache_hit.bytes=3",
    "[2.500] === MARK: scroll-chat-end ===",
  ].join("\n");
  const emptyWindowFixture = [
    "[1.000] === MARK: scroll-chat-start ===",
    "[2.500] === MARK: scroll-chat-end ===",
  ].join("\n");

  const pass = analyzeRenderLog(passingFixture, {
    label: "passing-fixture",
    allowHitch100: 0,
  });
  if (!pass.sawWindow || pass.findings.length !== 0) {
    fail("passing fixture must satisfy markdown render heavy log contract");
  }

  const severe = analyzeRenderLog(severeHitchFixture, {
    label: "severe-hitch-fixture",
    allowHitch100: 1,
  });
  if (severe.findings.length === 0) {
    fail("severe hitch fixture must fail");
  }

  const misses = analyzeRenderLog(missDominantFixture, {
    label: "miss-dominant-fixture",
    allowHitch100: 0,
  });
  if (misses.findings.length === 0) {
    fail("miss-dominant cache fixture must fail");
  }

  const emptyWindow = analyzeRenderLog(emptyWindowFixture, {
    label: "empty-window-fixture",
    allowHitch100: 0,
  });
  if (emptyWindow.findings.length === 0) {
    fail("empty render window fixture must fail");
  }

  // row.body bound: a window whose cumulative row.body evaluations exceed the
  // budget is a regression (a draw-only row should not re-evaluate per token).
  const overBudgetRowBodyFixture = [
    "[1.000] === MARK: scroll-chat-start ===",
    "[1.500 Δ0.50s] ChatView=1 row.body=500 timeline.entries.visible=8",
    "[2.500] === MARK: scroll-chat-end ===",
  ].join("\n");
  const overBudget = analyzeRenderLog(overBudgetRowBodyFixture, {
    label: "over-budget-rowbody-fixture",
    allowHitch100: 0,
    allowRowBody: 240,
  });
  if (!overBudget.findings.some((finding) => finding.includes("row.body count"))) {
    fail("over-budget row.body fixture must fail the bound");
  }
  // The same window passes when the scenario legitimately raises the budget.
  const raised = analyzeRenderLog(overBudgetRowBodyFixture, {
    label: "raised-rowbody-budget-fixture",
    allowHitch100: 0,
    allowRowBody: 600,
  });
  if (raised.findings.length !== 0) {
    fail("raised row.body budget fixture must pass");
  }
}

requireSnippet("macos/PERF.md", "Long chat scrolls badly");
requireSnippet("macos/PERF.md", "render.markdown.parse");
requireSnippet("macos/scripts/perf-workout.sh", "run_phase \"scroll-chat\"");
requireSnippet(
  "macos/Tests/ClawixMeshTests/AssistantMarkdownIncrementalCacheTests.swift",
  "testLongComplexMarkdownCachesAndKeepsAllHeavyShapes"
);
requireSnippet(
  "macos/Tests/ClawixMeshTests/TimelineEntryWindowTests.swift",
  "testVisibleWindowRemainsBoundedWhenToolGroupContainsManyItems"
);

if (rawArgs.includes("--self-test")) {
  runSelfTest();
}

const renderLog = valueAfter("--render-log");
if (renderLog) {
  const absolute = path.isAbsolute(renderLog) ? renderLog : path.join(rootDir, renderLog);
  if (!fs.existsSync(absolute)) {
    fail(`render log does not exist: ${renderLog}`);
  } else {
    const allowHitch100 = Number(valueAfter("--allow-hitch100") ?? 0);
    const allowRowBody = Number(valueAfter("--allow-rowbody") ?? DEFAULT_ROW_BODY_BUDGET);
    const phase = valueAfter("--phase") ?? "scroll-chat";
    const analysis = analyzeRenderLog(fs.readFileSync(absolute, "utf8"), {
      label: renderLog,
      phase,
      allowHitch100,
      allowRowBody,
    });
    for (const finding of analysis.findings) fail(finding);
  }
}

if (errors.length > 0) {
  console.error(`Markdown render heavy check failed with ${errors.length} finding(s):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Markdown render heavy check passed.");
