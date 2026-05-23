#!/usr/bin/env node
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = rawArgs;
const isSelfTest = process.env.CLAWIX_UI_PATTERN_MUTATION_GUARD_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-approved-visual-scope",
  "--simulate-overbudget-visual-scope",
  "--simulate-wrong-file-visual-scope",
  "--simulate-layout-only-visual-scope",
  "--simulate-revoked-visual-scope",
  "--simulate-expired-visual-scope",
  "--simulate-budget-kind-visual-scope",
  "--simulate-missing-pattern-visual-scope",
  "--simulate-duplicate-pattern-visual-scope",
  "--simulate-invalid-budget-visual-scope",
  "--simulate-unsafe-reference-visual-scope",
  "--simulate-unauthorized-pattern-notes-mutation",
  "--simulate-unauthorized-pattern-mutation",
  "--simulate-unauthorized-pattern-removal",
  "--simulate-unauthorized-pattern-deletion",
];
const allowedFlags = new Set(simulationFlags);
const today = new Date().toISOString().slice(0, 10);
const simulateApprovedVisualScope = args.includes("--simulate-approved-visual-scope");
const simulateOverbudgetVisualScope = args.includes("--simulate-overbudget-visual-scope");
const simulateWrongFileVisualScope = args.includes("--simulate-wrong-file-visual-scope");
const simulateLayoutOnlyVisualScope = args.includes("--simulate-layout-only-visual-scope");
const simulateRevokedVisualScope = args.includes("--simulate-revoked-visual-scope");
const simulateExpiredVisualScope = args.includes("--simulate-expired-visual-scope");
const simulateBudgetKindVisualScope = args.includes("--simulate-budget-kind-visual-scope");
const simulateMissingPatternVisualScope = args.includes("--simulate-missing-pattern-visual-scope");
const simulateDuplicatePatternVisualScope = args.includes("--simulate-duplicate-pattern-visual-scope");
const simulateInvalidBudgetVisualScope = args.includes("--simulate-invalid-budget-visual-scope");
const simulateUnsafeReferenceVisualScope = args.includes("--simulate-unsafe-reference-visual-scope");
const simulateUnauthorizedPatternNotesMutation = args.includes("--simulate-unauthorized-pattern-notes-mutation");
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI pattern mutation guard received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function git(args) {
  try {
    return execFileSync("git", ["-C", rootDir, ...args], { encoding: "utf8" });
  } catch {
    return "";
  }
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const allowlistPath = "docs/ui/visual-model-allowlist.manifest.json";
const allowlist = readJson(allowlistPath);
requireFields(config, configPath, ["visualAuthorizationPolicy"]);
requireFields(allowlist, allowlistPath, [
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "allowedVisualModels",
]);

const visualAuthorization = config?.visualAuthorizationPolicy || {};
const authorizationEnv = String(visualAuthorization.publicSignalEnv || allowlist?.authorizationSignal?.env || "");
const authorizationValue = String(visualAuthorization.publicSignalValue || allowlist?.authorizationSignal?.value || "");
const modelEnv = String(allowlist?.modelSignal?.env || "");
const requestedModel = modelEnv ? String(process.env[modelEnv] || "") : "";
const activeModels = new Set(
  requireArray(allowlist, allowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
const visualAuthorized =
  Boolean(authorizationEnv) &&
  process.env[authorizationEnv] === authorizationValue &&
  Boolean(modelEnv) &&
  activeModels.has(requestedModel);
const visualScopesPath = "docs/ui/visual-change-scopes.manifest.json";
const visualScopes = readJson(visualScopesPath);
const visualScopeEnv = String(visualScopes?.scopeSignal?.env || "CLAWIX_UI_VISUAL_SCOPE_ID");
const requestedVisualScopeId = visualScopeEnv ? String(process.env[visualScopeEnv] || "") : "";
const simulatedScopeApproval = {
  approvedBy: "user",
  approvedAt: "2026-05-17",
  externalApprovalReference: "external-ui-approval:simulated",
};
const simulatedPatternScope = {
  platforms: ["macos", "ios", "android", "web"],
  surfaces: ["macos-sidebar"],
  patterns: ["sidebar-row"],
};
if (simulateApprovedVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-approved-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateOverbudgetVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-overbudget-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 1, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateWrongFileVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-wrong-file-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/other.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateLayoutOnlyVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-layout-only-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateRevokedVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-revoked-scope",
      status: "revoked",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateExpiredVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-expired-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2000-01-01",
    },
  ];
}
if (simulateBudgetKindVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-budget-kind-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateMissingPatternVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-missing-pattern-scope",
      status: "approved",
      ...simulatedScopeApproval,
      platforms: ["macos", "ios", "android", "web"],
      surfaces: ["macos-sidebar"],
      patterns: ["composer-chrome"],
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateDuplicatePatternVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-duplicate-pattern-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      patterns: ["sidebar-row", "sidebar-row"],
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateInvalidBudgetVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-invalid-budget-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedPatternScope,
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 0, maxLines: "3", allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateUnsafeReferenceVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-unsafe-reference-scope",
      status: "approved",
      ...simulatedPatternScope,
      approvedBy: "user",
      approvedAt: "2026-05-17",
      externalApprovalReference: "external-ui-approval:../private/approval",
      files: ["docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
      changeKinds: ["layout", "microcopy", "hierarchy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy", "hierarchy"] },
      expiresAt: "2099-12-31",
    },
  ];
}

const governedPattern = /^docs\/ui\/pattern-registry\/patterns\/[^/]+\.pattern\.json$/;
const governedPatternNotes = "docs/ui/pattern-registry/patterns/notes.md";
const governedFields = [
  { id: "geometry", changeKind: "visual-ui", scopeChangeKind: "layout", pattern: /"geometry"\s*:|"cornerRadius"|"padding"|"spacing"|"height"|"width"|"fontSize"|"animationDuration"|"source"\s*:/ },
  { id: "copy", changeKind: "copy-ui", scopeChangeKind: "microcopy", pattern: /"copy"\s*:|"labelMaxWords"|"tooltipMaxWords"|"visibleNamesAreCanon"|"placeholder|Label|Text|Words"/ },
  { id: "state", changeKind: "visual-ui", scopeChangeKind: "hierarchy", pattern: /"states"\s*:|"hover-or-highlight"|"focused"|"pressed"|"selected"|"busy"|"error"/ },
  { id: "references", changeKind: "visual-ui", scopeChangeKind: "layout", pattern: /"canonicalReferences"\s*:|"STYLE\.md#/ },
  { id: "pattern-notes", changeKind: "visual-ui", scopeChangeKind: "hierarchy", pattern: /\S/ },
];

function fileMatchesScope(file, scopeFiles = []) {
  return scopeFiles.some((scopeFile) => {
    if (scopeFile === file) return true;
    if (scopeFile.endsWith("/**")) return file.startsWith(scopeFile.slice(0, -3));
    return false;
  });
}

function isIsoDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

function isSafePrivateApprovalReference(value) {
  if (typeof value !== "string" || !value.startsWith("external-ui-approval:")) return false;
  const suffix = value.slice("external-ui-approval:".length);
  return Boolean(
    suffix &&
      !suffix.startsWith("/") &&
      !suffix.startsWith("\\") &&
      !suffix.startsWith("~/") &&
      !suffix.includes("..") &&
      !/^[A-Z]:\\/.test(suffix) &&
      !value.includes("/Users/") &&
      !value.startsWith("file://"),
  );
}

function requireScopeStringSet(values, fieldName) {
  if (!Array.isArray(values) || values.length === 0) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} must declare ${fieldName}` };
  }
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} ${fieldName} must only include non-empty strings` };
    }
    if (seen.has(value)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} ${fieldName} duplicates ${value}` };
    }
    seen.add(value);
  }
  return { ok: true, values: seen, list: values };
}

function patternIdForPath(file) {
  const match = /^docs\/ui\/pattern-registry\/patterns\/([^/]+)\.pattern\.json$/.exec(file);
  return match?.[1] || null;
}

const patternPlatformCache = new Map();
function platformsForPattern(patternId) {
  if (patternPlatformCache.has(patternId)) return patternPlatformCache.get(patternId);
  const pattern = readJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
  const platforms = Array.isArray(pattern?.platforms) ? pattern.platforms : [];
  patternPlatformCache.set(patternId, platforms);
  return platforms;
}

function approvedScopeForHits(hits) {
  if (!requestedVisualScopeId) return { ok: false, reason: `${visualScopeEnv}=<approved visual scope id> is required` };
  const scope = (visualScopes?.activeScopes || []).find((candidate) => candidate?.id === requestedVisualScopeId);
  if (!scope) return { ok: false, reason: `scope ${requestedVisualScopeId} is not listed in ${visualScopesPath}.activeScopes` };
  if (scope.status !== "approved") return { ok: false, reason: `scope ${requestedVisualScopeId} is ${scope.status}, not approved` };
  if (scope.expiresAt && scope.expiresAt < today) return { ok: false, reason: `scope ${requestedVisualScopeId} expired on ${scope.expiresAt}` };
  if (scope.approvedBy !== "user") return { ok: false, reason: `scope ${requestedVisualScopeId} must be approvedBy user` };
  if (!isIsoDate(scope.approvedAt)) return { ok: false, reason: `scope ${requestedVisualScopeId} must include approvedAt ISO date` };
  if (!isSafePrivateApprovalReference(scope.externalApprovalReference)) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} must include safe external approval reference` };
  }

  const files = new Set(hits.map((hit) => hit.path));
  const scopePlatformsResult = requireScopeStringSet(scope.platforms, "platforms");
  if (!scopePlatformsResult.ok) return scopePlatformsResult;
  const scopeSurfacesResult = requireScopeStringSet(scope.surfaces, "surfaces");
  if (!scopeSurfacesResult.ok) return scopeSurfacesResult;
  const scopePatternsResult = requireScopeStringSet(scope.patterns, "patterns");
  if (!scopePatternsResult.ok) return scopePatternsResult;
  const scopeFilesResult = requireScopeStringSet(scope.files, "files");
  if (!scopeFilesResult.ok) return scopeFilesResult;
  const scopeChangeKindsResult = requireScopeStringSet(scope.changeKinds, "changeKinds");
  if (!scopeChangeKindsResult.ok) return scopeChangeKindsResult;
  const scopePlatforms = scopePlatformsResult.values;
  const scopePatterns = scopePatternsResult.values;
  const scopeChangeKinds = scopeChangeKindsResult.values;
  const changeBudget = scope.changeBudget || {};
  if (!Number.isInteger(changeBudget.maxFiles) || changeBudget.maxFiles < 1) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget.maxFiles must be a positive integer` };
  }
  if (!Number.isInteger(changeBudget.maxLines) || changeBudget.maxLines < 1) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget.maxLines must be a positive integer` };
  }
  const budgetChangeKindsResult = requireScopeStringSet(changeBudget.allowedChangeKinds, "changeBudget.allowedChangeKinds");
  if (!budgetChangeKindsResult.ok) return budgetChangeKindsResult;
  const budgetChangeKinds = budgetChangeKindsResult.values;
  for (const file of files) {
    if (!fileMatchesScope(file, scopeFilesResult.list)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include ${file}` };
  }
  const touchedPatterns = new Set([...files].map(patternIdForPath).filter(Boolean));
  for (const patternId of touchedPatterns) {
    if (!scopePatterns.has(patternId)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include pattern ${patternId}` };
    for (const platform of platformsForPattern(patternId)) {
      if (!scopePlatforms.has(platform)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include platform ${platform}` };
    }
  }
  for (const hit of hits) {
    if (!scopeChangeKinds.has(hit.scopeChangeKind)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} does not allow ${hit.scopeChangeKind}` };
    }
  }
  for (const hit of hits) {
    if (!budgetChangeKinds.has(hit.scopeChangeKind)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget does not allow ${hit.scopeChangeKind}` };
    }
  }
  if (Number.isInteger(changeBudget.maxFiles) && files.size > changeBudget.maxFiles) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxFiles budget exceeded` };
  }
  if (Number.isInteger(changeBudget.maxLines) && hits.length > changeBudget.maxLines) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxLines budget exceeded` };
  }
  return { ok: true, scope };
}

function findPatternMutationHits(diffText, sourceLabel) {
  const hits = [];
  let oldPath = "<unknown>";
  let newPath = "<unknown>";
  let nextOldLine = 0;
  let nextNewLine = 0;

  for (const line of diffText.split("\n")) {
    if (line.startsWith("--- a/")) {
      oldPath = line.slice("--- a/".length);
      continue;
    }
    if (line.startsWith("+++ b/")) {
      newPath = line.slice("+++ b/".length);
      continue;
    }
    if (line === "+++ /dev/null") {
      newPath = "/dev/null";
      continue;
    }
    if (line.startsWith("@@ ")) {
      const match = /-(\d+)(?:,\d+)? \+(\d+)(?:,\d+)?/.exec(line);
      nextOldLine = match ? Number(match[1]) : 0;
      nextNewLine = match ? Number(match[2]) : 0;
      continue;
    }
    if ((line.startsWith("+") && !line.startsWith("+++")) || (line.startsWith("-") && !line.startsWith("---"))) {
      const isRemoval = line.startsWith("-");
      const sourceLine = isRemoval ? nextOldLine : nextNewLine;
      const currentPath = isRemoval ? oldPath : newPath;
      if (governedPattern.test(currentPath) || currentPath === governedPatternNotes) {
        for (const field of governedFields) {
          if (currentPath === governedPatternNotes && field.id !== "pattern-notes") continue;
          if (currentPath !== governedPatternNotes && field.id === "pattern-notes") continue;
          if (field.pattern.test(line)) {
            hits.push({
              path: currentPath,
              line: sourceLine || "?",
              source: sourceLabel,
              detector: field.id,
              changeKind: field.changeKind,
              scopeChangeKind: field.scopeChangeKind,
              operation: isRemoval ? "removed" : "added",
              text: line.slice(1, 241),
            });
          }
        }
      }
      if (isRemoval) {
        nextOldLine += 1;
      } else {
        nextNewLine += 1;
      }
      continue;
    }
    if (line.startsWith(" ")) {
      nextOldLine += 1;
      nextNewLine += 1;
    }
  }

  return hits;
}

const simulatedPatternMutation = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "@@ -0,0 +1,3 @@",
  '+  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '+  "copy": { "labelMaxWords": 5 },',
  '+  "states": ["idle", "focused"]',
].join("\n");

const simulatedPatternRemoval = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "--- a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "@@ -12,3 +12,0 @@",
  '-  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '-  "copy": { "labelMaxWords": 5 },',
  '-  "states": ["idle", "focused"]',
].join("\n");

const simulatedPatternDeletion = [
  "diff --git a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json b/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "deleted file mode 100644",
  "--- a/docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
  "+++ /dev/null",
  "@@ -12,3 +0,0 @@",
  '-  "geometry": { "rowHeight": 36, "cornerRadius": 10 },',
  '-  "copy": { "labelMaxWords": 5 },',
  '-  "states": ["idle", "focused"]',
].join("\n");

const simulatedPatternNotesMutation = [
  "diff --git a/docs/ui/pattern-registry/patterns/notes.md b/docs/ui/pattern-registry/patterns/notes.md",
  "--- a/docs/ui/pattern-registry/patterns/notes.md",
  "+++ b/docs/ui/pattern-registry/patterns/notes.md",
  "@@ -10,0 +10,1 @@",
  "+Sidebar rows may use a taller decorative treatment when desired.",
].join("\n");

const sourceRoots = ["docs/ui/pattern-registry/patterns"];
const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const visualHits = args.includes("--simulate-unauthorized-pattern-mutation")
  ? findPatternMutationHits(simulatedPatternMutation, "simulated unauthorized pattern mutation")
  : simulateUnauthorizedPatternNotesMutation
    ? findPatternMutationHits(simulatedPatternNotesMutation, "simulated unauthorized pattern notes mutation")
  : args.includes("--simulate-unauthorized-pattern-removal")
    ? findPatternMutationHits(simulatedPatternRemoval, "simulated unauthorized pattern removal")
    : args.includes("--simulate-unauthorized-pattern-deletion")
      ? findPatternMutationHits(simulatedPatternDeletion, "simulated unauthorized pattern deletion")
  : [
      ...findPatternMutationHits(
        git(changedBase ? ["diff", "--unified=0", changedBase, "--", ...sourceRoots] : ["diff", "--unified=0", "--", ...sourceRoots]),
        changedBase ? `diff against ${changedBase}` : "working tree",
      ),
      ...(changedBase ? [] : findPatternMutationHits(git(["diff", "--cached", "--unified=0", "--", ...sourceRoots]), "staged")),
    ];

if (visualHits.length > 0 && !visualAuthorized) {
  fail(
    [
      "unauthorized pattern registry visual/copy contract mutation detected",
      `required permission: ${authorizationEnv}=${authorizationValue} and ${modelEnv}=<active visual model from ${allowlistPath}>`,
      `current model signal: ${modelEnv || "<unset>"}=${requestedModel || "<unset>"}`,
      `proposal route: ${allowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
      "non-authorized agents may update governance wiring, but visual/copy contract mutations require an allowlisted visual lane",
      ...visualHits.map(
        (hit) =>
          `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}/${hit.operation}] text=${hit.text}`,
      ),
    ].join("\n"),
  );
}
if (visualHits.length > 0 && visualAuthorized) {
  const scopeResult = approvedScopeForHits(visualHits);
  if (!scopeResult.ok) {
    fail(
      [
        "authorized pattern registry visual/copy contract mutation missing approved scope",
        `required scope: ${visualScopeEnv}=<approved scope from ${visualScopesPath}>`,
        `current scope signal: ${visualScopeEnv}=${requestedVisualScopeId || "<unset>"}`,
        `reason: ${scopeResult.reason}`,
        `proposal route: ${allowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
        ...visualHits.map(
          (hit) =>
            `  ${hit.path}:${hit.line} [${hit.source}/${hit.detector}/${hit.changeKind}/${hit.operation}] text=${hit.text}`,
        ),
      ].join("\n"),
    );
  }
}

if (errors.length === 0 && !isSelfTest && args.length === 0) {
  const visualAuthEnv = authorizationEnv ? { [authorizationEnv]: authorizationValue } : {};
  const visualModelEnv = modelEnv && activeModels.size > 0 ? { [modelEnv]: [...activeModels][0] } : {};
  const sanitizedSelfTestEnv = { ...process.env };
  if (authorizationEnv) delete sanitizedSelfTestEnv[authorizationEnv];
  if (modelEnv) delete sanitizedSelfTestEnv[modelEnv];
  if (visualScopeEnv) delete sanitizedSelfTestEnv[visualScopeEnv];
  const baseSelfTestEnv = {
    ...sanitizedSelfTestEnv,
    CLAWIX_UI_PATTERN_MUTATION_GUARD_SELF_TEST: "1",
  };
  const authorizedEnv = {
    ...baseSelfTestEnv,
    ...visualAuthEnv,
    ...visualModelEnv,
  };
  const runSelfTest = (selfTestArgs, expectedOutput, env = baseSelfTestEnv) => {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...selfTestArgs], {
      cwd: rootDir,
      env,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${selfTestArgs.join(" ")} must fail when pattern mutation authorization is invalid`);
      return;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${selfTestArgs.join(" ")} output must include ${expectedOutput}`);
    }
  };

  for (const [selfTestArgs, expectedOutput, env] of [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-unauthorized-pattern-mutation"], "unauthorized pattern registry visual/copy contract mutation detected"],
    [["--simulate-unauthorized-pattern-notes-mutation"], "simulated unauthorized pattern notes mutation"],
    [["--simulate-unauthorized-pattern-removal"], "simulated unauthorized pattern removal"],
    [["--simulate-unauthorized-pattern-deletion"], "simulated unauthorized pattern deletion"],
    [["--simulate-unauthorized-pattern-mutation"], `${visualScopeEnv}=<approved visual scope id> is required`, authorizedEnv],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-overbudget-visual-scope"],
      "scope simulated-overbudget-scope maxLines budget exceeded",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-overbudget-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-wrong-file-visual-scope"],
      "scope simulated-wrong-file-scope does not include docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-wrong-file-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-layout-only-visual-scope"],
      "scope simulated-layout-only-scope does not allow microcopy",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-layout-only-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-revoked-visual-scope"],
      "scope simulated-revoked-scope is revoked, not approved",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-revoked-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-expired-visual-scope"],
      "scope simulated-expired-scope expired on 2000-01-01",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-expired-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-budget-kind-visual-scope"],
      "scope simulated-budget-kind-scope changeBudget does not allow microcopy",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-budget-kind-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-missing-pattern-visual-scope"],
      "scope simulated-missing-pattern-scope does not include pattern sidebar-row",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-missing-pattern-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-duplicate-pattern-visual-scope"],
      "scope simulated-duplicate-pattern-scope patterns duplicates sidebar-row",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-duplicate-pattern-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-invalid-budget-visual-scope"],
      "scope simulated-invalid-budget-scope changeBudget.maxFiles must be a positive integer",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-invalid-budget-scope" },
    ],
    [
      ["--simulate-unauthorized-pattern-mutation", "--simulate-unsafe-reference-visual-scope"],
      "scope simulated-unsafe-reference-scope must include safe external approval reference",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-unsafe-reference-scope" },
    ],
  ]) {
    runSelfTest(selfTestArgs, expectedOutput, env);
  }
}

if (errors.length > 0) {
  console.error("UI pattern mutation guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI pattern mutation guard passed");
