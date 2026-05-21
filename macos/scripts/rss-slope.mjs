#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.argv[2];
if (!root) {
  console.error("Usage: node macos/scripts/rss-slope.mjs <trace-or-diagnostics-dir>");
  process.exit(2);
}
if (!fs.existsSync(root)) {
  console.log("No resource-samples.json files found.");
  process.exit(0);
}

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.name === "resource-samples.json") {
      out.push(full);
    }
  }
  return out;
}

function slopeMbPerMinute(samples, key) {
  const points = samples
    .filter((sample) => Number.isFinite(sample.timestamp) && Number.isFinite(sample[key]))
    .map((sample) => ({
      t: sample.timestamp,
      mb: sample[key] / 1024 / 1024,
    }));
  if (points.length < 2) return null;
  const t0 = points[0].t;
  const xs = points.map((point) => point.t - t0);
  const ys = points.map((point) => point.mb);
  const meanX = xs.reduce((sum, value) => sum + value, 0) / xs.length;
  const meanY = ys.reduce((sum, value) => sum + value, 0) / ys.length;
  let numerator = 0;
  let denominator = 0;
  for (let i = 0; i < xs.length; i += 1) {
    numerator += (xs[i] - meanX) * (ys[i] - meanY);
    denominator += (xs[i] - meanX) ** 2;
  }
  if (denominator === 0) return null;
  return (numerator / denominator) * 60;
}

function format(value) {
  return value == null ? "n/a" : value.toFixed(3);
}

const files = fs.statSync(root).isDirectory()
  ? walk(root)
  : [root].filter((file) => path.basename(file) === "resource-samples.json");

if (files.length === 0) {
  console.log("No resource-samples.json files found.");
  process.exit(0);
}

for (const file of files) {
  const samples = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(samples) || samples.length < 2) {
    console.log(`${file}: insufficient samples`);
    continue;
  }
  const first = samples[0];
  const last = samples[samples.length - 1];
  const durationSeconds = Math.max(0, last.timestamp - first.timestamp);
  const rssSlope = slopeMbPerMinute(samples, "residentBytes");
  const footprintSlope = slopeMbPerMinute(samples, "footprintBytes");
  const rssStart = first.residentBytes / 1024 / 1024;
  const rssEnd = last.residentBytes / 1024 / 1024;
  const footprintStart = first.footprintBytes / 1024 / 1024;
  const footprintEnd = last.footprintBytes / 1024 / 1024;

  console.log(`Resource slope: ${file}`);
  console.log(`  samples: ${samples.length}`);
  console.log(`  duration_s: ${durationSeconds.toFixed(1)}`);
  console.log(`  rss_mb: ${rssStart.toFixed(1)} -> ${rssEnd.toFixed(1)}`);
  console.log(`  rss_slope_mb_per_min: ${format(rssSlope)}`);
  console.log(`  footprint_mb: ${footprintStart.toFixed(1)} -> ${footprintEnd.toFixed(1)}`);
  console.log(`  footprint_slope_mb_per_min: ${format(footprintSlope)}`);
}
