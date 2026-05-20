#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const files = ["AGENTS.md", "CLAUDE.md", "docs/agent-rules/index.md"];
const budgets = {
  "AGENTS.md": 120,
  "CLAUDE.md": 20,
};

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function lineCount(text) {
  return text.replace(/\n$/u, "").split(/\r?\n/u).length;
}

function normalizeLine(line) {
  return line.trim().replace(/\s+/gu, " ");
}

function longListSignals(relativePath, text) {
  const signals = [];
  let currentHeading = "top";
  let bulletRun = 0;
  const flush = () => {
    if (bulletRun >= 8) signals.push(`${relativePath}: ${currentHeading} has ${bulletRun} consecutive list items`);
    bulletRun = 0;
  };
  for (const line of text.split(/\r?\n/u)) {
    const heading = line.match(/^#{1,3}\s+(.+)$/u);
    if (heading) {
      flush();
      currentHeading = heading[1];
      continue;
    }
    if (/^\s*[-*]\s+/u.test(line) || /^\s*\d+\.\s+/u.test(line)) bulletRun += 1;
    else if (line.trim() !== "") flush();
  }
  flush();
  return signals;
}

function duplicatedInstructionLines(contents) {
  const seen = new Map();
  for (const [relativePath, text] of Object.entries(contents)) {
    for (const line of text.split(/\r?\n/u)) {
      const normalized = normalizeLine(line);
      if (normalized.length < 48) continue;
      if (!/[A-Za-z]/u.test(normalized)) continue;
      if (!seen.has(normalized)) seen.set(normalized, new Set());
      seen.get(normalized).add(relativePath);
    }
  }
  return [...seen.entries()]
    .filter(([, paths]) => paths.size > 1)
    .map(([line, paths]) => `${[...paths].sort().join(", ")} duplicate: ${line}`);
}

const errors = [];
const contents = {};
for (const relativePath of files) {
  const absolutePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(absolutePath)) {
    errors.push(`missing ${relativePath}`);
    continue;
  }
  contents[relativePath] = read(relativePath);
}

if (errors.length > 0) {
  console.error("agent instructions check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

const warnings = [];
for (const [relativePath, budget] of Object.entries(budgets)) {
  const count = lineCount(contents[relativePath]);
  if (count > budget) warnings.push(`${relativePath}: ${count} lines exceeds report-only target ${budget}`);
}

for (const relativePath of ["AGENTS.md", "CLAUDE.md"]) {
  if (!contents[relativePath].includes("docs/agent-rules/index.md")) {
    warnings.push(`${relativePath}: missing docs/agent-rules/index.md route`);
  }
}

warnings.push(...longListSignals("AGENTS.md", contents["AGENTS.md"]));
warnings.push(...longListSignals("CLAUDE.md", contents["CLAUDE.md"]));
warnings.push(...duplicatedInstructionLines(contents).slice(0, 20));

if (warnings.length > 0) {
  console.error("agent instructions report-only warnings:");
  for (const warning of warnings) console.error(`- ${warning}`);
} else {
  console.error("agent instructions check passed with no report-only warnings");
}

process.exit(0);
