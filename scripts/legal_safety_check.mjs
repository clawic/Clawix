#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let failed = false;

function fail(message) {
  failed = true;
  console.error(`legal safety check failed: ${message}`);
}

function read(relativePath) {
  const file = path.join(root, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  const normalizedText = text.replace(/\s+/g, " ");
  const normalizedSnippet = snippet.replace(/\s+/g, " ");
  if (!normalizedText.includes(normalizedSnippet)) {
    fail(`${relativePath} is missing required snippet: ${snippet}`);
  }
}

function extractTableIds(text, prefix) {
  return new Set(text.split(/\r?\n/)
    .map((line) => line.match(new RegExp(`^\\|\\s*(${prefix}-\\d{3})\\s*\\|`))?.[1])
    .filter(Boolean));
}

function assertExternalPendingLedger(relativePath, expectedCount) {
  const text = read(relativePath);
  const currentRowsSection = text.split("## Goal Completion Impact")[0] || text;
  const rows = currentRowsSection.split(/\r?\n/)
    .map((line) => line.match(/^\|\s*(LEGAL-EXT-\d{3})\s*\|[^|]+\|[^|]+\|[^|]+\|\s*([^|]+?)\s*\|/))
    .filter(Boolean)
    .map((match) => ({ id: match[1], status: match[2].trim() }));
  if (rows.length !== expectedCount) {
    fail(`${relativePath} must contain ${expectedCount} LEGAL-EXT rows, found ${rows.length}`);
  }
  const ids = new Set(rows.map((row) => row.id));
  for (let index = 1; index <= expectedCount; index += 1) {
    const id = `LEGAL-EXT-${String(index).padStart(3, "0")}`;
    if (!ids.has(id)) fail(`${relativePath} is missing ${id}`);
  }
  for (const row of rows) {
    if (row.status !== "EXTERNAL PENDING") {
      fail(`${relativePath} ${row.id} must have EXTERNAL PENDING status, found ${row.status}`);
    }
  }
}

const ignoredWalkDirectories = new Set([
  ".build",
  ".dart_tool",
  ".git",
  "AppPackages",
  "build",
  "dist",
  "node_modules",
  "publish",
  ["release", "output"].join("-"),
  "target",
  "web-dist",
]);

function walk(dir, predicate, files = []) {
  const absoluteDir = path.join(root, dir);
  if (!fs.existsSync(absoluteDir)) return files;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (ignoredWalkDirectories.has(entry.name) || entry.name.startsWith(".build")) continue;
      walk(relativePath, predicate, files);
    } else if (predicate(relativePath)) {
      files.push(relativePath);
    }
  }
  return files;
}

function assertNoBannedMarketingClaims() {
  const roots = [
    "README.md",
    "TERMS.md",
    "PRIVACY.md",
    "DISCLAIMER.md",
    "SAFETY.md",
    "REGULATED_DOMAINS.md",
    "EULA.md",
    "SECURITY.md",
  ];
  const extensions = new Set([".md", ".html", ".json", ".js", ".jsx", ".ts", ".tsx", ".xaml", ".resw"]);
  const scanned = [
    ...roots,
    ...walk("docs", (file) => extensions.has(path.extname(file))),
    ...walk("web", (file) => extensions.has(path.extname(file))),
    ...walk("apps", (file) => extensions.has(path.extname(file))),
    ...walk("examples", (file) => extensions.has(path.extname(file))),
    ...walk("linux", (file) => extensions.has(path.extname(file))),
    ...walk("windows", (file) => extensions.has(path.extname(file))),
    ...walk("packages", (file) => path.basename(file) === "README.md"),
  ].filter((file) => ![
    "docs/codebase-manifest.json",
    "docs/persistent-surface-clawix.manifest.json",
  ].includes(file));
  const bannedClaims = [
    "autopilot",
    "compliance-ready",
    "hipaa compliant",
    "gdpr compliant",
    "ai act compliant",
    "fda approved",
    "fda cleared",
    "cfpb compliant",
    "diagnose and treat",
    "replaces a doctor",
    "replaces a lawyer",
    "replaces a therapist",
    "provides legal advice",
    "provides medical advice",
    "provides financial advice",
    "makes credit decisions",
    "makes insurance decisions",
    "makes employment decisions",
    "makes admission decisions",
    "submits regulated filings autonomously",
    "send bank details",
    "bank details included",
    "zero wait time",
    "every workflow is built and maintained by autonomous agents",
    "every seat is an autonomous agent",
  ];
  for (const file of scanned) {
    const text = read(file).toLowerCase();
    for (const claim of bannedClaims) {
      if (text.includes(claim)) {
        fail(`${file} contains banned or unqualified marketing/legal claim: ${claim}`);
      }
    }
  }
}

function assertLegalDocsAreBilingual() {
  for (const file of [
    "TERMS.md",
    "PRIVACY.md",
    "DISCLAIMER.md",
    "SAFETY.md",
    "REGULATED_DOMAINS.md",
    "EULA.md",
  ]) {
    const text = read(file);
    for (const snippet of ["## English", "## Espanol"]) {
      if (!text.includes(snippet)) {
        fail(`${file} must keep bilingual legal section ${snippet}`);
      }
    }
  }
}

function assertLegalVersionsAreAligned() {
  const expectedVersion = "2026-05-18";
  const legalDocs = [
    "TERMS.md",
    "PRIVACY.md",
    "DISCLAIMER.md",
    "SAFETY.md",
    "REGULATED_DOMAINS.md",
    "EULA.md",
  ];
  for (const file of legalDocs) {
    requireSnippet(file, `Last updated: ${expectedVersion}`);
  }
  for (const [file, constants] of [
    ["macos/Sources/Clawix/LegalSafety.swift", [
      "termsVersion",
      "privacyVersion",
      "eulaVersion",
      "disclaimerVersion",
      "safetyVersion",
      "regulatedDomainsVersion",
    ]],
    ["ios/Sources/Clawix/LegalSafety.swift", [
      "termsVersion",
      "privacyVersion",
      "eulaVersion",
      "disclaimerVersion",
      "safetyVersion",
      "regulatedDomainsVersion",
    ]],
  ]) {
    const text = read(file);
    for (const constant of constants) {
      const pattern = new RegExp(`static let ${constant} = "${expectedVersion}"`);
      if (!pattern.test(text)) {
        fail(`${file} must keep ${constant} aligned to legal document version ${expectedVersion}`);
      }
    }
  }
}

function assertNoCredentialLikePublicSecrets() {
  const roots = [
    "README.md",
    "TERMS.md",
    "PRIVACY.md",
    "DISCLAIMER.md",
    "SAFETY.md",
    "REGULATED_DOMAINS.md",
    "EULA.md",
    "SECURITY.md",
    "RELEASING.md",
  ];
  const extensions = new Set([".md", ".html", ".json", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".yml", ".yaml", ".swift", ".cs", ".ps1"]);
  const scanned = [
    ...roots,
    ...walk("docs", (file) => extensions.has(path.extname(file))),
    ...walk("web", (file) => extensions.has(path.extname(file))),
    ...walk("apps", (file) => extensions.has(path.extname(file))),
    ...walk("linux", (file) => extensions.has(path.extname(file))),
    ...walk("windows", (file) => extensions.has(path.extname(file))),
    ...walk("packages", (file) => extensions.has(path.extname(file))),
    ...walk("macos", (file) => extensions.has(path.extname(file))),
    ...walk("ios", (file) => extensions.has(path.extname(file))),
    ...walk("tests", (file) => extensions.has(path.extname(file))),
  ]
    .filter((file, index, all) => all.indexOf(file) === index)
    .filter((file) => fs.existsSync(path.join(root, file)))
    .filter((file) => !file.includes("/node_modules/"))
    .filter((file) => !file.includes("/web-dist/"))
    .filter((file) => !file.includes("/.build/"))
    .filter((file) => !file.includes("/build/"));
  const patterns = [
    ["github-token", /(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9_]{20,}/g],
    ["openai-token", /(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}/g],
    ["slack-token", /(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{20,}/g],
    ["aws-access-key", /(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![A-Za-z0-9])/g],
    ["google-api-key", /(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{20,}/g],
    ["personal-email-domain", /\b[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook|icloud|me|live)\.(com|net|org)\b/gi],
  ];
  for (const file of scanned) {
    const lines = read(file).split(/\r?\n/);
    for (const [index, line] of lines.entries()) {
      for (const [id, pattern] of patterns) {
        pattern.lastIndex = 0;
        if (pattern.test(line)) {
          fail(`${file}:${index + 1} contains credential-like or personal fixture value (${id}); use synthetic placeholders or an explicit redaction test`);
        }
      }
    }
  }
}

for (const file of [
  "RELEASING.md",
  "TERMS.md",
  "PRIVACY.md",
  "DISCLAIMER.md",
  "SAFETY.md",
  "REGULATED_DOMAINS.md",
  "EULA.md",
  "SECURITY.md",
  "docs/governance/legal/source-audit.md",
  "docs/governance/legal/external-pending.md",
]) {
  read(file);
}

requireSnippet("README.md", "TERMS.md");
requireSnippet("README.md", "PRIVACY.md");
requireSnippet("README.md", "DISCLAIMER.md");
requireSnippet("README.md", "SAFETY.md");
requireSnippet("README.md", "REGULATED_DOMAINS.md");
requireSnippet("README.md", "EULA.md");
requireSnippet("README.md", "does not replace regulated professionals");
requireSnippet("RELEASING.md", "GitHub Release Channel Checklist");
requireSnippet("RELEASING.md", "App And Binary Channel Checklist");
requireSnippet("RELEASING.md", "Web Channel Checklist");
requireSnippet("RELEASING.md", "Store Channel Checklist");
requireSnippet("RELEASING.md", "node scripts/legal_safety_check.mjs");
requireSnippet("RELEASING.md", "explicit approval for that exact");
requireSnippet("RELEASING.md", "Classify every new sensitive app surface, route, connector, provider");
requireSnippet("RELEASING.md", "ClawJS regulated-domain safety policy");
requireSnippet("RELEASING.md", "docs/governance/legal/external-pending.md");
requireSnippet("CONSTITUTION.md", "Regulated domains are assistive, never final decision authorities");
requireSnippet("docs/agent-rules/index.md", "Regulated domains are assistive only");
requireSnippet("docs/decision-map.md", "Regulated domains are assistive, not final decision authorities");
requireSnippet("docs/decision-map.md", "Clawix Legal Closure Decision Audit");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "termsVersion = \"2026-05-18\"");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "acceptedDisclaimerVersion == LegalSafetyPolicy.disclaimerVersion");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "acceptedSafetyVersion == LegalSafetyPolicy.safetyVersion");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "acceptedRegulatedDomainsVersion == LegalSafetyPolicy.regulatedDomainsVersion");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "minimumAge = 18");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "sensitiveExportConfirmationRequired");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "requestSensitiveActionReview");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "crisisRefusal(for text");
requireSnippet("macos/Sources/Clawix/AppState/MessageSending.swift", "handleCrisisPromptIfNeeded");
requireSnippet("macos/Sources/Clawix/AppState/MessageSending.swift", "LegalSafetyPolicy.crisisRefusal(for: text)");
requireSnippet("macos/Sources/Clawix/LegalConsentSheet.swift", "interactiveDismissDisabled(true)");
requireSnippet("macos/Sources/Clawix/LegalConsentSheet.swift", "I confirm I am at least 18 years old");
requireSnippet("macos/Sources/Clawix/Settings/LegalSafetySettingsPage.swift", "Legal & Safety");
requireSnippet("macos/Sources/Clawix/SettingsView.swift", "case legalSafety");
requireSnippet("macos/Sources/Clawix/ContentChrome.swift", "LegalConsentGate");
requireSnippet("macos/Sources/Clawix/Dictation/TranscriptHistoryUI.swift", "requestExportReview");
requireSnippet("macos/Sources/Clawix/Design/EditorView.swift", "requestExportReview(format");
requireSnippet("macos/Sources/Clawix/ImagePreviewOverlay.swift", "downloadReviewedImage");
requireSnippet("macos/Sources/Clawix/PlanCardView.swift", "handleReviewedDownload");
requireSnippet("macos/Sources/Clawix/PlanCardView.swift", "handleReviewedCopy");
requireSnippet("macos/Sources/Clawix/PlanCardView.swift", "reviewedExportContent");
requireSnippet("macos/Sources/Clawix/PlanCardView.swift", "human review required; sources and gaps required");
requireSnippet("macos/Sources/Clawix/Dictation/ExportService.swift", "legal_labels");
requireSnippet("macos/Sources/Clawix/Dictation/ExportService.swift", "\"legal\"");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "reviewedSensitiveOutputText");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "human review required; sources and gaps required");
requireSnippet("macos/Sources/Clawix/Life/LifeRegistry.swift", "legalGuardLabel");
requireSnippet("macos/Sources/Clawix/Life/LifeHomeScreen.swift", "entry.legalGuardLabel");
requireSnippet("macos/Sources/Clawix/Life/LifeSidebarSection.swift", "entry.legalGuardLabel");
requireSnippet("macos/Sources/Clawix/Life/LifeSettingsView.swift", "entry.legalGuardLabel");
requireSnippet("macos/Sources/Clawix/Chat/ChatView+MessageEntry.swift", "reviewedSensitiveOutputText(content)");
requireSnippet("macos/Sources/Clawix/QuickAsk/QuickAskMessageBubble.swift", "reviewedSensitiveOutputText(message.content)");
requireSnippet("macos/Sources/Clawix/Dictation/Enhancement/EnhancementService.swift", "LegalSafetyStore.shared.providerDisclosureOptIn");
requireSnippet("macos/Sources/Clawix/Dictation/DictationCoordinator.swift", "LegalSafetyStore.shared.providerDisclosureOptIn");
requireSnippet("macos/Sources/Clawix/Settings/LegalSafetySettingsPage.swift", "Provider disclosure opt-in");
requireSnippet("macos/Sources/Clawix/Settings/LegalSafetySettingsPage.swift", "Provider terms remain the user's responsibility.");
requireSnippet("macos/Sources/Clawix/Design/EditorExport.swift", "legalHTMLComment");
requireSnippet("macos/Sources/Clawix/Design/EditorExport.swift", "<metadata>\\(legalPlainText)</metadata>");
requireSnippet("macos/Sources/Clawix/Design/EditorExport.swift", "human review required; sources and gaps required");
requireSnippet("ios/Sources/Clawix/Design/EditorView.swift", "requestExportReview(format");
requireSnippet("ios/Sources/Clawix/Design/EditorView.swift", "Export or share sensitive data?");
requireSnippet("ios/Sources/Clawix/Design/EditorExport.swift", "legalHTMLComment");
requireSnippet("ios/Sources/Clawix/Design/EditorExport.swift", "<metadata>\\(legalPlainText)</metadata>");
requireSnippet("ios/Sources/Clawix/Design/EditorExport.swift", "human review required; sources and gaps required");
requireSnippet("ios/Sources/Clawix/ChatDetail/ImageViewerView.swift", "pendingSensitiveImageAction");
requireSnippet("ios/Sources/Clawix/ChatDetail/ImageViewerView.swift", "Export or share sensitive data?");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "reviewedSensitiveOutputText");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "human review required; sources and gaps required");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "regulatedDecisionDisclaimer");
requireSnippet("ios/Sources/Clawix/Life/LifeRegistry.swift", "legalGuardLabel");
requireSnippet("ios/Sources/Clawix/Life/LifeRegistry.swift", "IOSLegalSafetyPolicy.regulatedDecisionDisclaimer");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "termsVersion = \"2026-05-18\"");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "acceptedDisclaimerVersion == IOSLegalSafetyPolicy.disclaimerVersion");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "acceptedSafetyVersion == IOSLegalSafetyPolicy.safetyVersion");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "acceptedRegulatedDomainsVersion == IOSLegalSafetyPolicy.regulatedDomainsVersion");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "minimumAge = 18");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "hasAcceptedCurrentLegal");
requireSnippet("ios/Sources/Clawix/LegalConsentSheet.swift", "I confirm I am at least 18 years old");
requireSnippet("ios/Sources/Clawix/LegalConsentSheet.swift", "I accept the Terms, Privacy Notice, Disclaimer, Safety Policy, Regulated Domains policy, and EULA version 2026-05-18.");
requireSnippet("ios/Sources/Clawix/LegalConsentSheet.swift", "Accept and continue");
requireSnippet("ios/Sources/Clawix/ClawixApp.swift", "IOSLegalConsentSheet(legal: legal)");
requireSnippet("ios/Sources/Clawix/ClawixApp.swift", "interactiveDismissDisabled(true)");
requireSnippet("ios/Sources/Clawix/ChatDetail/ChatDetailView.swift", "IOSLegalSafetyPolicy.reviewedSensitiveOutputText(content)");
requireSnippet("ios/Sources/Clawix/ChatDetail/AssistantMarkdownView.swift", "IOSLegalSafetyPolicy.reviewedSensitiveOutputText(code)");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "crisisRefusal(for text");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "988");
requireSnippet("ios/Sources/Clawix/Bridge/BridgeStore.swift", "IOSLegalSafetyPolicy.crisisRefusal(for: trimmed)");
requireSnippet("ios/Sources/Clawix/P2PChat/P2PChatView.swift", "IOSLegalSafetyPolicy.crisisRefusal(for: body)");
requireSnippet("macos/Tests/ClawixMeshTests/SecretsSecurityBoundaryTests.swift", "testSensitiveExportEntrypointsRequireLegalReview");
requireSnippet("macos/Tests/ClawixMeshTests/SecretsSecurityBoundaryTests.swift", "human review required; sources and gaps required");
requireSnippet("macos/Tests/ClawixMeshTests/SecretsSecurityBoundaryTests.swift", "testProviderBackedDictationRoutesRequireLegalProviderOptIn");
requireSnippet("macos/Tests/ClawixMeshTests/LifeRegistryTests.swift", "testSensitiveLifeVerticalsExposeLegalGuardMetadata");
for (const manifestPath of [
  "docs/persistent-surface-clawix.manifest.json",
  "macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json",
]) {
  requireSnippet(manifestPath, "clawix.prefs.legal.acceptedTermsVersion");
  requireSnippet(manifestPath, "clawix.prefs.legal.acceptedDisclaimerVersion");
  requireSnippet(manifestPath, "clawix.prefs.legal.acceptedSafetyVersion");
  requireSnippet(manifestPath, "clawix.prefs.legal.acceptedRegulatedDomainsVersion");
  requireSnippet(manifestPath, "clawix.prefs.legal.localAuditRetentionDays");
}
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testAcceptCurrentLegalPersistsVersionedClickwrapState");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testAnyLegalDocumentVersionMismatchForcesReacceptance");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testReviewedSensitiveOutputTextPersistsHumanReviewAndSourcesGaps");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testOptInDoesNotBypassManualSupportOrExternalActionReview");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testLocalAuditRetentionDaysAreConfigurableAndPersistent");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testCrisisPromptReturnsRefusalAndEmergencyResources");
requireSnippet("macos/Tests/ClawixMeshTests/RescueRepairContextTests.swift", "testExporterWritesRedactedRescueContextJson");
requireSnippet("macos/Tests/ClawixMeshTests/RescueRepairContextTests.swift", "explicit_approval_only");
requireSnippet("macos/Sources/Clawix/Rescue/RescueRepairContext.swift", "promptsIncluded: false");
requireSnippet("macos/Sources/Clawix/Rescue/RescueRepairContext.swift", "secretsIncluded: false");
requireSnippet("macos/Sources/Clawix/Rescue/RescueRepairContext.swift", "fullLocalPathsIncluded: false");
requireSnippet("macos/Tests/ClawixMeshTests/PersistentSurfaceRegistryTests.swift", "clawix.prefs.legal.sensitiveExportConfirmationRequired");
requireSnippet("docs/governance/release-readiness.manifest.json", "scripts/legal_safety_check.mjs");
requireSnippet("macos/scripts/build_release_app.sh", "Release readiness contract preflight");
requireSnippet("macos/scripts/build_release_app.sh", "scripts/release_readiness_check.mjs");
requireSnippet("macos/scripts/build_release_app.sh", "CLAWIX_RELEASE_APPROVED_FOR:-");
requireSnippet("macos/scripts/build_release_app.sh", "macos-app");
requireSnippet("macos/scripts/build_web_dist.sh", "Legal safety preflight");
requireSnippet("macos/scripts/build_web_dist.sh", "scripts/legal_safety_check.mjs");
requireSnippet("scripts/launch-web.sh", "scripts/legal_safety_check.mjs");
requireSnippet("scripts/launch-web.sh", "macos/scripts/build_web_dist.sh");
requireSnippet("web/package.json", "node ../scripts/legal_safety_check.mjs");
requireSnippet("ios/scripts/build_release_app.sh", "Release readiness contract preflight");
requireSnippet("ios/scripts/build_release_app.sh", "scripts/release_readiness_check.mjs");
requireSnippet("ios/scripts/build_release_app.sh", "CLAWIX_RELEASE_APPROVED_FOR:-");
requireSnippet("ios/scripts/build_release_app.sh", "ios-archive");
requireSnippet("linux/scripts/build_release_appimage.sh", "release readiness contract preflight");
requireSnippet("linux/scripts/build_release_appimage.sh", "scripts/release_readiness_check.mjs");
requireSnippet("linux/scripts/build_release_appimage.sh", "CLAWIX_RELEASE_APPROVED_FOR:-");
requireSnippet("linux/scripts/build_release_appimage.sh", "linux-appimage");
requireSnippet("linux/scripts/build_release_deb.sh", "release readiness contract preflight");
requireSnippet("linux/scripts/build_release_deb.sh", "scripts/release_readiness_check.mjs");
requireSnippet("linux/scripts/build_release_deb.sh", "CLAWIX_RELEASE_APPROVED_FOR:-");
requireSnippet("linux/scripts/build_release_deb.sh", "linux-deb");
requireSnippet("linux/app/package.json", "node ../../scripts/legal_safety_check.mjs");
requireSnippet("windows/scripts/build-release.ps1", "release_readiness_check.mjs");
requireSnippet("windows/scripts/build-release.ps1", "CLAWIX_RELEASE_APPROVED_FOR");
requireSnippet("windows/scripts/build-release.ps1", "windows-msix");

requireSnippet("TERMS.md", "provided \"as is\"");
requireSnippet("TERMS.md", "laws of Spain and applicable European Union law");
requireSnippet("TERMS.md", "You are responsible for how you configure and use Clawix");
requireSnippet("PRIVACY.md", "local-first app");
requireSnippet("PRIVACY.md", "Data may leave the device only when the user explicitly configures or starts an external flow");
requireSnippet("PRIVACY.md", "manual opt-in");
requireSnippet("PRIVACY.md", "not directed to users under 18");
requireSnippet("DISCLAIMER.md", "not an emergency service");
requireSnippet("DISCLAIMER.md", "Sensitive outputs are drafts for review");
requireSnippet("SAFETY.md", "Allowed sensitive use");
requireSnippet("SAFETY.md", "Blocked sensitive use");
requireSnippet("SAFETY.md", "Required review");
requireSnippet("SAFETY.md", "Sensitive outputs must preserve labels");
requireSnippet("REGULATED_DOMAINS.md", "official app is 18+ by default");
requireSnippet("REGULATED_DOMAINS.md", "Clawix must not take final regulated decisions");
requireSnippet("EULA.md", "official Clawix binaries");
requireSnippet("EULA.md", "Sensitive native permissions");
requireSnippet("SECURITY.md", "Support diagnostics are manual opt-in");
requireSnippet("SECURITY.md", "EXTERNAL PENDING");
requireSnippet("tests/fixtures/README.md", "Synthetic fixtures shared across lanes live here.");
requireSnippet("tests/fixtures/README.md", "Do not store real customer data");
requireSnippet("docs/governance/legal/source-audit.md", "Source conversation: `source:legal-safety`");
requireSnippet("docs/governance/legal/source-audit.md", "Closure state: `active_goal_not_complete`");
requireSnippet("docs/governance/legal/source-audit.md", "LCA-001");
requireSnippet("docs/governance/legal/source-audit.md", "LCA-033");
requireSnippet("docs/governance/legal/source-audit.md", "Required Evidence Spine");
requireSnippet("docs/governance/legal/source-audit.md", "docs/governance/legal/external-pending.md");
requireSnippet("docs/governance/legal/external-pending.md", "Source conversation: `source:legal-safety`");
requireSnippet("docs/governance/legal/external-pending.md", "Status: `active_goal_not_complete`");
requireSnippet("docs/governance/legal/external-pending.md", "LEGAL-EXT-001");
requireSnippet("docs/governance/legal/external-pending.md", "LEGAL-EXT-007");
requireSnippet("docs/governance/legal/external-pending.md", "EXTERNAL PENDING");
requireSnippet("docs/governance/legal/external-pending.md", "not passes");
requireSnippet("docs/governance/legal/external-pending.md", "must not be downgraded to `EXTERNAL PENDING`");
requireSnippet("docs/governance/legal/external-pending.md", "No row authorizes a push, tag, publish, upload, notarization, TestFlight");
const legalClosureAudit = read("docs/governance/legal/source-audit.md");
const legalClosureIds = extractTableIds(legalClosureAudit, "LCA");
if (legalClosureIds.size !== 33) {
  fail(`docs/governance/legal/source-audit.md must contain 33 LCA rows, found ${legalClosureIds.size}`);
}
for (let index = 1; index <= 33; index += 1) {
  const id = `LCA-${String(index).padStart(3, "0")}`;
  if (!legalClosureIds.has(id)) fail(`docs/governance/legal/source-audit.md is missing ${id}`);
}
assertExternalPendingLedger("docs/governance/legal/external-pending.md", 7);
assertNoBannedMarketingClaims();
assertLegalDocsAreBilingual();
assertLegalVersionsAreAligned();
assertNoCredentialLikePublicSecrets();

if (failed) {
  process.exit(1);
}

console.error("legal safety check passed");
