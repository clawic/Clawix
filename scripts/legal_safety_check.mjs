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

function walk(dir, predicate, files = []) {
  const absoluteDir = path.join(root, dir);
  if (!fs.existsSync(absoluteDir)) return files;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
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

for (const file of [
  "TERMS.md",
  "PRIVACY.md",
  "DISCLAIMER.md",
  "SAFETY.md",
  "REGULATED_DOMAINS.md",
  "EULA.md",
  "SECURITY.md",
  "docs/legal-closure-decision-audit.md",
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
requireSnippet("CONSTITUTION.md", "Regulated domains are assistive, never final decision authorities");
requireSnippet("AGENTS.md", "Regulated domains are assistive only");
requireSnippet("docs/decision-map.md", "Regulated domains are assistive, not final decision authorities");
requireSnippet("docs/decision-map.md", "Clawix Legal Closure Decision Audit");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "termsVersion = \"2026-05-18\"");
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
requireSnippet("macos/Sources/Clawix/Dictation/ExportService.swift", "legal_labels");
requireSnippet("macos/Sources/Clawix/Dictation/ExportService.swift", "\"legal\"");
requireSnippet("macos/Sources/Clawix/LegalSafety.swift", "reviewedSensitiveOutputText");
requireSnippet("macos/Sources/Clawix/Chat/ChatView+MessageEntry.swift", "reviewedSensitiveOutputText(content)");
requireSnippet("macos/Sources/Clawix/QuickAsk/QuickAskMessageBubble.swift", "reviewedSensitiveOutputText(message.content)");
requireSnippet("macos/Sources/Clawix/Dictation/Enhancement/EnhancementService.swift", "LegalSafetyStore.shared.providerDisclosureOptIn");
requireSnippet("macos/Sources/Clawix/Dictation/DictationCoordinator.swift", "LegalSafetyStore.shared.providerDisclosureOptIn");
requireSnippet("macos/Sources/Clawix/Design/EditorExport.swift", "legalHTMLComment");
requireSnippet("macos/Sources/Clawix/Design/EditorExport.swift", "<metadata>\\(legalPlainText)</metadata>");
requireSnippet("ios/Sources/Clawix/Design/EditorView.swift", "requestExportReview(format");
requireSnippet("ios/Sources/Clawix/Design/EditorView.swift", "Export or share sensitive data?");
requireSnippet("ios/Sources/Clawix/Design/EditorExport.swift", "legalHTMLComment");
requireSnippet("ios/Sources/Clawix/Design/EditorExport.swift", "<metadata>\\(legalPlainText)</metadata>");
requireSnippet("ios/Sources/Clawix/ChatDetail/ImageViewerView.swift", "pendingSensitiveImageAction");
requireSnippet("ios/Sources/Clawix/ChatDetail/ImageViewerView.swift", "Export or share sensitive data?");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "reviewedSensitiveOutputText");
requireSnippet("ios/Sources/Clawix/LegalSafety.swift", "termsVersion = \"2026-05-18\"");
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
requireSnippet("macos/Tests/ClawixMeshTests/SecretsSecurityBoundaryTests.swift", "testProviderBackedDictationRoutesRequireLegalProviderOptIn");
requireSnippet("macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift", "clawix.prefs.legal.acceptedTermsVersion");
requireSnippet("macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift", "clawix.prefs.legal.localAuditRetentionDays");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testAcceptCurrentLegalPersistsVersionedClickwrapState");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testOptInDoesNotBypassManualSupportOrExternalActionReview");
requireSnippet("macos/Tests/ClawixMeshTests/LegalSafetyTests.swift", "testCrisisPromptReturnsRefusalAndEmergencyResources");
requireSnippet("macos/Tests/ClawixMeshTests/PersistentSurfaceRegistryTests.swift", "clawix.prefs.legal.sensitiveExportConfirmationRequired");
requireSnippet("macos/scripts/build_release_app.sh", "Legal safety preflight");
requireSnippet("macos/scripts/build_release_app.sh", "scripts/legal_safety_check.mjs");
requireSnippet("ios/scripts/build_release_app.sh", "Legal safety preflight");
requireSnippet("ios/scripts/build_release_app.sh", "scripts/legal_safety_check.mjs");
requireSnippet("linux/scripts/build_release_appimage.sh", "legal safety preflight");
requireSnippet("linux/scripts/build_release_appimage.sh", "scripts/legal_safety_check.mjs");
requireSnippet("linux/scripts/build_release_deb.sh", "legal safety preflight");
requireSnippet("linux/scripts/build_release_deb.sh", "scripts/legal_safety_check.mjs");
requireSnippet("windows/scripts/build-release.ps1", "legal_safety_check.mjs");

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
requireSnippet("docs/legal-closure-decision-audit.md", "Source conversation: `019e3a44-1175-7930-b45c-252f342b5ec2`");
requireSnippet("docs/legal-closure-decision-audit.md", "Closure state: `active_goal_not_complete`");
requireSnippet("docs/legal-closure-decision-audit.md", "LCA-001");
requireSnippet("docs/legal-closure-decision-audit.md", "LCA-033");
requireSnippet("docs/legal-closure-decision-audit.md", "Required Evidence Spine");
const legalClosureAudit = read("docs/legal-closure-decision-audit.md");
const legalClosureIds = extractTableIds(legalClosureAudit, "LCA");
if (legalClosureIds.size !== 33) {
  fail(`docs/legal-closure-decision-audit.md must contain 33 LCA rows, found ${legalClosureIds.size}`);
}
for (let index = 1; index <= 33; index += 1) {
  const id = `LCA-${String(index).padStart(3, "0")}`;
  if (!legalClosureIds.has(id)) fail(`docs/legal-closure-decision-audit.md is missing ${id}`);
}
assertNoBannedMarketingClaims();

if (failed) {
  process.exit(1);
}

console.error("legal safety check passed");
