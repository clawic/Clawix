#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingClawJs = path.resolve(rootDir, "../../clawjs");
const errors = [];

function exists(relativePath, base = rootDir) {
  return fs.existsSync(path.join(base, relativePath));
}

function read(relativePath, base = rootDir) {
  return fs.readFileSync(path.join(base, relativePath), "utf8");
}

function readJson(relativePath, base = rootDir) {
  return JSON.parse(read(relativePath, base));
}

function requireSnippet(file, snippet, label = snippet) {
  if (!exists(file)) {
    errors.push(`missing ${file}`);
    return;
  }
  if (!read(file).includes(snippet)) {
    errors.push(`${file} missing ${label}`);
  }
}

function requireSnippetInFiles(files, snippet, label = snippet) {
  const existingFiles = files.filter((file) => exists(file));
  for (const file of files) {
    if (!exists(file)) errors.push(`missing ${file}`);
  }
  if (existingFiles.length === 0) return;
  if (!existingFiles.some((file) => read(file).includes(snippet))) {
    errors.push(`${existingFiles.join(", ")} missing ${label}`);
  }
}

function requireEqual(actual, expected, label) {
  if (actual !== expected) {
    errors.push(`${label} expected ${expected}, got ${actual}`);
  }
}

function requireArrayEquals(actual, expected, label) {
  if (!Array.isArray(actual)) {
    errors.push(`${label} must be an array`);
    return;
  }
  const actualText = JSON.stringify(actual);
  const expectedText = JSON.stringify(expected);
  if (actualText !== expectedText) {
    errors.push(`${label} expected ${expectedText}, got ${actualText}`);
  }
}

const runtimeLensModelFiles = [
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClient.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensRuntimeResource.swift"
];

const runtimeLensSettingsFiles = [
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSettingsPresentation.swift",
  "macos/Sources/Clawix/Settings/ClawJSSettingsPage.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSection.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensChrome.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSummaryViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSupportOverviewViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSupportAuditViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSupportClosureViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensSessionViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensDomainViews.swift",
  "macos/Sources/Clawix/Settings/ClawJSRuntimeLensInventoryViews.swift"
];

const runtimeLensTestFiles = [
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensClientTests.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensClientBoundaryTests.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensInventoryPresentationTests.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensSessionActionTests.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensSettingsPresentationTests.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensSupportPresentationTests.swift"
];

for (const file of [
  "docs/runtime-ecosystem-lens.md",
  "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md",
  "docs/interface-surface-clawix.registry.json",
  "docs/decision-map.md",
  "docs/discoverability.registry.json",
  "docs/adr-operational-coverage.manifest.json"
]) {
  if (!exists(file)) errors.push(`missing ${file}`);
}

if (exists("docs/runtime-ecosystem-lens.md")) {
  const text = read("docs/runtime-ecosystem-lens.md");
  for (const snippet of ["runtime lens", "semantic native parity", "local overlays", "product-blocked", "status-tone contract", "finalPromotionReview", "finalSupportClaimDecision", "closureChecklist", "evidenceReentryPackets", "supportContract", "EXTERNAL PENDING", "resources <domain>", "stable `ok:false` JSON error envelopes", "claw commands resolve runtime resources --json", "model and plugin inventory", "capability diagnostics", "common runtime resource metadata", "claim source", "official snapshot", "source snapshot date", "source count", "drift policy", "audit provenance source/runtime", "capability-map status counts", "top-level session descriptors", "top-level workspace canonical/managed file counts", "top-level resource aggregates"]) {
    if (!text.includes(snippet)) errors.push(`runtime lens doc missing ${snippet}`);
  }
}

if (exists("docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md")) {
  const text = read("docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md");
  for (const snippet of ["Status: Accepted", "Surface Parity", "Discovery Route", "ClawJS ADR 0047"]) {
    if (!text.includes(snippet)) errors.push(`mirror ADR missing ${snippet}`);
  }
}

if (exists("docs/interface-surface-clawix.registry.json")) {
  const registry = readJson("docs/interface-surface-clawix.registry.json");
  const surface = (registry.surfaces ?? []).find((entry) => entry.id === "runtimeEcosystemLens");
  if (!surface) errors.push("interface registry missing runtimeEcosystemLens");
  else {
    if (surface.status !== "dev-only") errors.push("runtimeEcosystemLens must stay dev-only until full parity, native write-back, and live evidence exist");
    for (const field of ["humanSurface", "programmaticSurface", "storageOwner", "validation", "steward"]) {
      if (!surface[field]) errors.push(`runtimeEcosystemLens missing ${field}`);
    }
    if (!String(surface.humanSurface ?? "").includes("OpenClaw/Hermes partial lens evidence exists")) {
      errors.push("runtimeEcosystemLens must distinguish current partial lens evidence from full parity");
    }
  }
}

if (!read("docs/decision-map.md").includes("Runtime ecosystem lens")) {
  errors.push("decision map missing Runtime ecosystem lens row");
}
if (!read("docs/decision-map.md").includes("claw commands resolve runtime resources --json")) {
  errors.push("decision map missing runtime resource command-intent route");
}

const discoverability = readJson("docs/discoverability.registry.json");
const sources = new Set((discoverability.artifacts ?? []).map((entry) => entry.canonicalSource));
for (const source of [
  "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md",
  "docs/runtime-ecosystem-lens.md",
  "scripts/runtime_ecosystem_lens_check.mjs"
]) {
  if (!sources.has(source)) errors.push(`discoverability registry missing ${source}`);
}

const coverage = readJson("docs/adr-operational-coverage.manifest.json");
if (!(coverage.acceptedAdrCoverage ?? []).some((entry) => entry.adr === "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md")) {
  errors.push("ADR operational coverage missing runtime ecosystem mirror ADR");
}

const hermesFixturePath = "macos/Tests/ClawixMeshTests/Fixtures/ClawJSRuntimeLens/hermes-runtime-portal-envelope.json";
if (!exists(hermesFixturePath)) {
  errors.push(`missing ${hermesFixturePath}`);
} else {
  const fixture = readJson(hermesFixturePath);
  const supportAudit = fixture?.data?.supportAudit;
  const support = fixture?.data?.support;
  const officialSnapshot = fixture?.data?.officialSnapshot;
  const readiness = supportAudit?.evidenceReadinessSummary;
  const domains = supportAudit?.domains;
  const hermesWriteBackPolicy = "blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence";
  for (const summaryFragment of ["native write-back contracts", "approval-gate receipts", "TUI Gateway production transport policy", "channel/provider/auth/model evidence"]) {
    requireEqual(support?.ecosystem?.summary?.includes(summaryFragment), true, `Hermes fixture support summary includes ${summaryFragment}`);
    requireEqual(supportAudit?.summary?.includes(summaryFragment), true, `Hermes fixture support audit summary includes ${summaryFragment}`);
  }
  requireEqual(officialSnapshot?.capturedAt, "2026-05-26", "Hermes fixture official snapshot captured date");
  requireEqual(officialSnapshot?.sourceSnapshotDate, "2026-05-26", "Hermes fixture official snapshot source snapshot date");
  requireEqual(officialSnapshot?.sourceType, "official_docs", "Hermes fixture official snapshot source type");
  requireEqual(officialSnapshot?.manifestSource, "docs/runtime-ecosystem-integration.manifest.json", "Hermes fixture official snapshot manifest source");
  requireEqual(officialSnapshot?.driftPolicy, "hermes_remains_dev_only_until_snapshot_total_and_write_policy_are_complete", "Hermes fixture official snapshot drift policy");
  requireEqual(officialSnapshot?.sources?.length, 8, "Hermes fixture official snapshot source count");
  requireEqual(officialSnapshot?.sources?.includes("https://hermes-agent.nousresearch.com/docs/user-guide/cli/"), true, "Hermes fixture official snapshot CLI source");
  requireEqual(officialSnapshot?.sources?.includes("https://github.com/NousResearch/hermes-agent"), true, "Hermes fixture official snapshot repo source");
  requireEqual(support?.ecosystem?.officialSnapshot?.capturedAt, "2026-05-26", "Hermes fixture support ecosystem official snapshot");
  requireEqual(supportAudit?.officialSnapshot?.capturedAt, "2026-05-26", "Hermes fixture support audit official snapshot");
  requireEqual(supportAudit?.provenance?.officialSnapshotSource, "docs/runtime-ecosystem-integration.manifest.json", "Hermes fixture support audit snapshot provenance");
  requireEqual(supportAudit?.provenance?.sourceSnapshotDate, "2026-05-26", "Hermes fixture support audit source snapshot date");
  for (const reason of [
    "native_write_back_pending",
    "approval_gate_fixture_pending",
    "tui_gateway_round_trip_evidence_pending",
    "production_transport_policy_pending",
    "live_channel_evidence_pending",
    "live_provider_evidence_pending",
    "live_auth_evidence_pending",
    "live_model_evidence_pending",
  ]) {
    requireEqual(support?.ecosystem?.blockingReasons?.includes(reason), true, `Hermes fixture support blocking reason ${reason}`);
    requireEqual(supportAudit?.blockingReasons?.includes(reason), true, `Hermes fixture support audit blocking reason ${reason}`);
  }
  if (!supportAudit) {
    errors.push("Hermes runtime portal fixture missing data.supportAudit");
  }
  if (!readiness) {
    errors.push("Hermes runtime portal fixture missing evidenceReadinessSummary");
  } else {
    requireEqual(readiness.totalRequirementCount, 22, "Hermes fixture total readiness requirement count");
    requireEqual(readiness.approvalRequiredCount, 6, "Hermes fixture approval-required count");
    requireEqual(readiness.externalPendingCount, 4, "Hermes fixture external-pending count");
    requireEqual(readiness.upstreamContractBlockedCount, 16, "Hermes fixture upstream-contract blocked count");
    requireEqual(readiness.approvalGateBlockedCount, 2, "Hermes fixture approval-gate blocked count");
    requireEqual(readiness.tuiGatewayBlockedCount, 4, "Hermes fixture TUI Gateway blocked count");
    requireEqual(readiness.productionTransportBlockedCount, 4, "Hermes fixture production transport blocked count");
    requireEqual(readiness.writeBackContractBlockedCount, 12, "Hermes fixture write-back contract blocked count");
    requireEqual(readiness.productBlockedCount, 18, "Hermes fixture product-blocked count");
    requireEqual(readiness.safeDefaultCounts?.keep_unpromoted_and_do_not_synthesize_runtime_state, 14, "Hermes fixture generic unpromoted safe-default count");
    requireEqual(readiness.safeDefaultCounts?.keep_local_overlay_and_do_not_write_runtime_pin_state, 2, "Hermes fixture local overlay pin safe-default count");
    requireEqual(supportAudit?.syncPolicySummary?.writeBackPolicyCounts?.[hermesWriteBackPolicy], 10, "Hermes fixture precise official write-back policy count");
    requireEqual(supportAudit?.syncPolicySummary?.writeBackPolicyCounts?.blocked_until_fixture_coverage, undefined, "Hermes fixture does not use generic fixture-coverage write-back policy");
    requireEqual(supportAudit?.syncPolicySummary?.writeBackPolicyCounts?.blocked_until_policy, undefined, "Hermes fixture does not use generic blocked-until-policy write-back policy");
    requireArrayEquals(readiness.approvalGateRequirementIds, [
      "hermes.doctorCompat.approval_gate_evidence",
      "hermes.sandboxPermissions.approval_gate_evidence"
    ], "Hermes fixture approval-gate requirement ids");
    requireArrayEquals(readiness.tuiGatewayRequirementIds, [
      "hermes.sessions.send.action_contract",
      "hermes.sessions.inject.action_contract",
      "hermes.sessions.abort.action_contract",
      "hermes.sessions.create.action_contract"
    ], "Hermes fixture TUI Gateway requirement ids");
    requireArrayEquals(readiness.productionTransportRequirementIds, [
      "hermes.sessions.send.action_contract",
      "hermes.sessions.inject.action_contract",
      "hermes.sessions.abort.action_contract",
      "hermes.sessions.create.action_contract"
    ], "Hermes fixture production transport requirement ids");
    requireArrayEquals(readiness.writeBackContractRequirementIds, [
      "hermes.sessions.write_back_contract",
      "hermes.skills.write_back_contract",
      "hermes.memory.write_back_contract",
      "hermes.providers.write_back_contract",
      "hermes.auth.write_back_contract",
      "hermes.models.write_back_contract",
      "hermes.scheduler.write_back_contract",
      "hermes.plugins.write_back_contract",
      "hermes.gateway.write_back_contract",
      "hermes.configuration.write_back_contract",
      "hermes.sessions.pin.native_write_back_contract",
      "hermes.sessions.unpin.native_write_back_contract"
    ], "Hermes fixture write-back contract requirement ids");
  }
  if (!domains || typeof domains !== "object") {
    errors.push("Hermes runtime portal fixture missing supportAudit.domains");
  } else {
    requireEqual(Object.keys(domains).length, 13, "Hermes fixture support-audit domain count");
  }
  if (supportAudit && JSON.stringify(supportAudit).includes("/var/folders/")) {
    errors.push("Hermes runtime portal fixture supportAudit must not contain temp source paths");
  }
  const commands = fixture?.data?.commands?.executableByClawCli;
  if (!Array.isArray(commands)) {
    errors.push("Hermes runtime portal fixture missing command matrix rows");
  } else {
    const pinCommand = commands.find((entry) => entry.command === "runtime hermes sessions pin --session-key <id>");
    const unpinCommand = commands.find((entry) => entry.command === "runtime hermes sessions unpin --session-key <id>");
    requireEqual(pinCommand?.writesRuntime, false, "Hermes pin command matrix writesRuntime");
    requireEqual(pinCommand?.writesLocalOverlay, true, "Hermes pin command matrix writesLocalOverlay");
    requireEqual(pinCommand?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract", "Hermes pin command matrix native write-back status");
    requireEqual(pinCommand?.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state", "Hermes pin command matrix safe default");
    requireEqual(pinCommand?.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract", "Hermes pin command matrix evidence id");
    requireEqual(pinCommand?.nativeWriteBackContract?.officialContractRequired, true, "Hermes pin command matrix official contract required");
    requireEqual(pinCommand?.nativeWriteBackContract?.officialContractKnown, false, "Hermes pin command matrix official contract known");
    requireEqual(unpinCommand?.writesLocalOverlay, true, "Hermes unpin command matrix writesLocalOverlay");
    requireEqual(unpinCommand?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract", "Hermes unpin command matrix native write-back status");
    requireEqual(unpinCommand?.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state", "Hermes unpin command matrix safe default");
    requireEqual(unpinCommand?.evidenceRequirementId, "hermes.sessions.unpin.native_write_back_contract", "Hermes unpin command matrix evidence id");
    requireEqual(unpinCommand?.nativeWriteBackContract?.officialContractRequired, true, "Hermes unpin command matrix official contract required");
  }
  const sessionActionContracts = fixture?.data?.domainData?.sessions?.actionContracts;
  const sessionActionPolicy = fixture?.data?.domainData?.sessions?.actionPolicy;
  if (!Array.isArray(sessionActionContracts) || !Array.isArray(sessionActionPolicy)) {
    errors.push("Hermes runtime portal fixture missing session action contracts or policy");
  } else {
    const pinContract = sessionActionContracts.find((entry) => entry.action === "pin");
    const unpinPolicy = sessionActionPolicy.find((entry) => entry.action === "unpin");
    requireEqual(pinContract?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract", "Hermes pin action contract native write-back status");
    requireEqual(pinContract?.officialRuntimeWriteBackContractRequired, true, "Hermes pin action contract official write-back contract required");
    requireEqual(pinContract?.officialRuntimeWriteBackContractKnown, false, "Hermes pin action contract official write-back contract known");
    requireEqual(pinContract?.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state", "Hermes pin action contract safe default");
    requireEqual(pinContract?.userVisibleContract, "local_overlay_only_until_official_runtime_pin_api_exists", "Hermes pin action contract user-visible contract");
    requireEqual(pinContract?.claimEffect, "blocks_native_write_back_parity_not_local_overlay", "Hermes pin action contract claim effect");
    requireEqual(pinContract?.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract", "Hermes pin action contract evidence id");
    requireEqual(unpinPolicy?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract", "Hermes unpin action policy native write-back status");
    requireEqual(unpinPolicy?.evidenceRequirementId, "hermes.sessions.unpin.native_write_back_contract", "Hermes unpin action policy evidence id");
  }
}

if (fs.existsSync(siblingClawJs)) {
  for (const file of [
    "docs/runtime-ecosystem-integration.manifest.json",
    "docs/runtime-ecosystem-integration-standard.md",
    "docs/adr/0047-runtime-ecosystem-integration-standard.md"
  ]) {
    if (!exists(file, siblingClawJs)) errors.push(`sibling ClawJS missing ${file}`);
  }

  if (exists("docs/runtime-ecosystem-integration.manifest.json", siblingClawJs)) {
    const manifest = readJson("docs/runtime-ecosystem-integration.manifest.json", siblingClawJs);
    const clientPath = "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClient.swift";
    if (exists(clientPath)) {
      const client = read(clientPath);
      for (const domain of manifest.requiredDomains ?? []) {
        if (!client.includes(`"${domain}"`)) {
          errors.push(`${clientPath} missing canonical runtime domain ${domain}`);
        }
      }
    }
  }
}

for (const file of [
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClient.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensRuntimeSummaryPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportOverviewPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensViewStatePresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensMissingDomainPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensDomainCommandPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensDomainPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportContractPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensInventoryPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionInventoryPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionDescriptorPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionActionPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionActionContractPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionOverlayPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionOverlayActionPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensStatusTone.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportAuditPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensCommandMatrixPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClosureChecklistPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensEvidenceReentryPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensEvidenceRequirementPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportSummaryPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportDecisionPresentation.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensValidationSummary.swift",
  "macos/Sources/Clawix/Settings/ClawJSSettingsPage.swift",
  "macos/Tests/ClawixMeshTests/ClawJSRuntimeLensClientTests.swift"
]) {
  if (!exists(file)) errors.push(`missing ${file}`);
}

for (const snippet of [
  "case openclaw",
  "case hermes",
  "missingCanonicalDomains",
  "struct CommandMatrix",
  "session: SessionDescriptor?",
  "workspace: Workspace?",
  "runtimeResources: RuntimeResources?",
  "officialSnapshot: OfficialSnapshot?",
  "struct OfficialSnapshot",
  "sourceSnapshotDate: String?",
  "manifestSource: String?",
  "struct Workspace",
  "struct RuntimeResources",
  "struct SupportAudit",
  "claimSource: String?",
  "finalPromotionReview: FinalPromotionReview?",
  "struct FinalPromotionReview",
  "finalSupportClaimDecision: FinalSupportClaimDecision?",
  "struct FinalSupportClaimDecision",
  "closureChecklist: [ClosureChecklistItem]?",
  "closureChecklistSummary: [String: Int]?",
  "struct ClosureChecklistItem",
  "syncPolicySummary: SyncPolicySummary?",
  "struct SyncPolicySummary",
  "readOnlyProjectionDomains: [String]?",
  "localOverlayDomains: [String]?",
  "projectionSummary: ProjectionSummary?",
  "struct ProjectionSummary",
  "byReadProjectionStatus: [String: Int]?",
  "productBlockedButProjectedDomainCount: Int?",
  "evidenceReadinessSummary: EvidenceReadinessSummary?",
  "struct EvidenceReadinessSummary",
  "approvalRequiredCount: Int?",
  "upstreamContractBlockedCount: Int?",
  "approvalGateBlockedCount: Int?",
  "tuiGatewayBlockedCount: Int?",
  "productionTransportBlockedCount: Int?",
  "writeBackContractBlockedCount: Int?",
  "approvalGateRequirementIds: [String]?",
  "tuiGatewayRequirementIds: [String]?",
  "productionTransportRequirementIds: [String]?",
  "writeBackContractRequirementIds: [String]?",
  "runtimeCapabilityStatus: String?",
  "runtimeCapabilitySupported: Bool?",
  "runtimeCapabilityStrategy: String?",
  "readProjectionStatus: String?",
  "implementedFacets: [String]?",
  "blockingFacets: [String]?",
  "projectionDisposition: String?",
  "evidenceReentryPackets: [EvidenceReentryPacket]?",
  "struct EvidenceReentryPacket",
  "exactCommand: String?",
  "preflightCommand: String?",
  "approvalScope: String?",
  "evidenceSafetyPolicy: String?",
  "expectedRedactedEvidence: [String]?",
  "claimBlockedUntil: String?",
  "productionTransportCommandShape: String?",
  "doNotRunWithoutApproval: Bool?",
  "wouldWriteRuntime",
  "struct EvidenceRequirement",
  "evidenceRequirements",
  "struct SupportContract",
  "authority: String?",
  "provenance: Provenance?",
  "adapter: String?",
  "version: String?",
  "capabilities: [String: Bool]?",
  "capabilityMap: [String: Capability]?",
  "struct Capability",
  "actionContracts: [SessionActionPolicy]?",
  "inventoryError: String?",
  "evidenceDisposition",
  "currentBehavior",
  "fallbackPolicy",
  "reentryCondition",
  "productDecision",
  "supportResolution",
  "userVisibleContract",
  "SessionOverlayActionResult",
  "nativeWriteBackStatus",
  "officialRuntimeWriteBackContractRequired",
  "nativeWriteBackContract",
  "setSessionPinned",
  "func resources(for domain: String)",
  "authResources()",
  "hasProfileApiKey: Bool?",
  "attributes: [String]?",
  "authAttributes(_ state: DomainData.AuthBucket.AuthState)",
  "state.hasSubscription.map",
  "state.hasProfileApiKey.map",
  "defaultModel: DefaultModel?",
  "status: RuntimeCapability?",
  "struct Diagnostics: Decodable, Equatable",
  "diagnostics: Diagnostics?",
  "capabilityDiagnosticsAttributes",
  "diagnostic source:",
  "inventory freshness:",
  "modelResources()",
  "pluginResources()",
  "modelAttributes(",
  "pluginStatusAttributes",
  "commonResourceAttributes",
  "resourcesWithCommonAttributes",
  "scope: String?",
  "providerAuth = \"auth\"",
  "metadataKeysLabel",
  "pinAuthority: String?",
  "divergence: String?",
  "localOverlay: LocalOverlay?",
  "metadata keys:",
  "default_model",
  "plugin-status",
  "managedFiles: [String]?",
  "diagnostics: Status.Diagnostics?",
  "managed-file-",
  "configuration-diagnostics",
  "operationalResources(domain: domain, bucket: domainData?.gateway)",
  "operationalResources(domain: domain, bucket: domainData?.doctorCompat)",
  "operationalResources(domain: domain, bucket: domainData?.sandboxPermissions)",
  "configurationResources()",
  "domainData?.configuration?.capability",
  "workspace?.canonicalPaths",
  "workspace?.managedFiles",
  "runtimeResources?.skills",
  "runtimeResources?.providers",
  "runtimeResources?.auth",
  "runtimeResources?.defaultModel"
]) {
  requireSnippetInFiles(runtimeLensModelFiles, snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensRuntimeSummaryPresentation",
  "Runtime summary",
  "installedLabel",
  "cliLabel",
  "gatewayLabel",
  "CapabilityRow",
  "rawCapabilityEnabledCount",
  "capabilityStatusLabel",
  "capabilityRows",
  "capability map",
  "workspaceCanonicalPathCount",
  "workspaceManagedFileCount",
  "workspaceFilesLabel",
  "workspace files",
  "runtimeResourceAggregateDomainCount",
  "runtimeResourceCount",
  "runtimeResourcesLabel",
  "runtime resource aggregate domains",
  "LocationRow",
  "locationRows",
  "locationCount",
  "location details",
  "supportAuditPresent",
  "normalized"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensRuntimeSummaryPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSupportOverviewPresentation",
  "Runtime support overview",
  "adapterSupportLevel",
  "ecosystemSupportStage",
  "officialSnapshotLabel",
  "officialSnapshotSourceCount",
  "officialSnapshotDriftPolicy",
  "claimSource",
  "provenanceSource",
  "sourceLabel",
  "blockingReasonCount",
  "blockingReasons.joined(separator: \", \")",
  "evidenceRequirementCount",
  "notPromoted",
  "normalized"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportOverviewPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensViewStatePresentation",
  "Runtime lens view state",
  "load_error",
  "action_error",
  "refreshing",
  "snapshot pending",
  "hasActionError"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensViewStatePresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensMissingDomainPresentation",
  "Runtime missing domains",
  "all_domains_accounted",
  "semantic_lens_incomplete",
  "missingDomainCount",
  "presentDomainCount",
  "runtime missing domain"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensMissingDomainPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensDomainCommandPresentation",
  "Runtime domain commands",
  "totalCommandCount",
  "visibleCommandCount",
  "hiddenCommandCount",
  "stableId",
  "normalized"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensDomainCommandPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensDomainPresentation",
  "Runtime domains",
  "nativeCommandDomainCount",
  "limitationDomainCount",
  "limitationsLabel",
  "strategyLabel",
  "policyDomainCount",
  "writeBackAllowedCount",
  "persistenceLabel",
  "validationLabel",
  "policyLabel",
  "provenanceDomainCount",
  "provenanceSourceLabel",
  "provenanceLabel",
  "provenanceSource",
  "provenanceRuntimeId",
  "provenanceDomain",
  "runtimeCapabilityStatus",
  "runtimeCapabilitySupported",
  "runtimeCapabilityStrategy",
  "readProjectionStatus",
  "read projection",
  "nativeAuthority",
  "writeBackAllowed",
  "externalPendingDomainsLabel",
  "evidenceRequirementCount",
  "write back"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensDomainPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSupportContractPresentation",
  "Runtime support contracts",
  "contractDomainCount",
  "writeBackAllowedCount",
  "blockedWriteBackCount",
  "externalPendingCount",
  "nativeCommandDomainCount",
  "contractAuthorityDomainCount",
  "provenanceDomainCount",
  "contractAuthorityLabel",
  "provenanceSourceLabel",
  "contractAuthorityLabel: String?",
  "provenanceLabel: String?",
  "supportContract(for domain: String)",
  "write back policies",
  "contract authorities",
  "provenance sources"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportContractPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensInventoryPresentation",
  "Runtime inventory",
  "totalResourceCount",
  "visibleResourceCount",
  "pinnedResourceCount",
  "pathResourceCount",
  "updatedResourceCount",
  "kindResourceCount",
  "summaryResourceCount",
  "enabledResourceCount",
  "sizedResourceCount",
  "kindLabel",
  "summaryLabel",
  "enabledLabel",
  "sizeLabel",
  "nativeIdentifierResourceCount",
  "provenanceResourceCount",
  "limitationResourceCount",
  "limitationCount",
  "attributeResourceCount",
  "attributeCount",
  "nativeIdentifierLabel",
  "provenanceLabel",
  "limitationsLabel",
  "attributesLabel",
  "runtime inventory domain",
  "runtime inventory resource"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensInventoryPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionInventoryPresentation",
  "Runtime session inventory",
  "projectedCount",
  "visibleCount",
  "hasInventoryError",
  "statusLabel",
  "normalizedInventoryError"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionInventoryPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionDescriptorPresentation",
  "Runtime session descriptor",
  "primaryTransport",
  "transportKind",
  "streamingLabel",
  "fallbackTransport",
  "sessionPath",
  "sessionDatabasePath",
  "sessionTranscriptPath",
  "sessionIndexPath",
  "sessionStorageContract",
  "storageDetailLines",
  "normalizedFallback"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionDescriptorPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionActionPresentation",
  "Runtime session actions",
  "wouldWriteRuntimeCount",
  "localOverlayActionsLabel",
  "blockedActionsLabel",
  "requiredEvidenceCount",
  "requiredEvidenceLabel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionActionPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionActionContractPresentation",
  "Runtime session action contracts",
  "contractCount",
  "materializedCount",
  "statusChangedCount",
  "runtimeWriteContractCount",
  "wouldWriteRuntimeCount",
  "localOverlayContractCount",
  "statusChangedActionsLabel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionActionContractPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionOverlayPresentation",
  "Runtime session overlays",
  "totalConflicts",
  "conflictStatusLabel",
  "writeBackStatus",
  "no_silent_overwrite"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionOverlayPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSessionOverlayActionPresentation",
  "runtime session overlay action",
  "localOverlayAuthority",
  "targetPinned",
  "buttonTitle",
  "systemImage",
  "actionKey(runtimeId: String, sessionId: String)",
  "writesRuntime: false",
  "runtime-lens-session-overlay-action-"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSessionOverlayActionPresentation.swift", snippet);
}

for (const snippet of [
  "enum ClawJSRuntimeLensStatusTone",
  "commandDisposition(_ disposition: String)",
  "sessionActionStatus(_ status: String)",
  "sessionActionDisposition(_ disposition: String)",
  "overlayConflictStatus(_ status: String)",
  "closureStatus(_ status: String)",
  "direct_blocker",
  "external_pending",
  "evidenceReentryStatus(_ status: String)",
  "blocked_until_approval_gate_fixture",
  "ecosystemStage(_ stage: String)",
  "runtimeDomainStatus(",
  "supportClaim(_ claim: String)",
  "evidenceBlockerClass(_ blockerClass: String)",
  "resourceStatus(_ status: String)"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensStatusTone.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensCommandMatrixPresentation",
  "Runtime command matrix",
  "writesRuntimeCount",
  "wouldWriteRuntimeCount",
  "localOverlayCommandCount",
  "nativeWriteBackBlockedCount",
  "nativeWriteBackStatus",
  "argumentCommandCount",
  "argsLabel",
  "resourceDomainsLabel",
  "blocked write"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensCommandMatrixPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensSupportAuditPresentation",
  "Runtime support audit",
  "directBlockerCount",
  "externalPendingCount",
  "productBlockedRequirementCount",
  "blockerClassLabel",
  "blockedWriteBackDomainsLabel",
  "ecosystemExternalPendingDomainsLabel",
  "promotion gate",
  "provenanceLabel",
  "provenance source",
  "domainCoverageLabel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportAuditPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensClosureChecklistPresentation",
  "Runtime closure checklist",
  "evidenceCount",
  "implementedFacetCount",
  "blockingFacetCount",
  "read projection",
  "safe default",
  "writeBackPolicy",
  "validation",
  "blockerClassesLabel",
  "evidenceRequirementIdsLabel",
  "supportResolutionsLabel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClosureChecklistPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensEvidenceReentryPresentation",
  "Runtime evidence reentry packets",
  "approvalRequiredCount",
  "expectedEvidenceLabel",
  "exactCommand",
  "preflightCommand",
  "approvalScope",
  "evidenceSafetyPolicy",
  "expectedRedactedEvidenceLabel",
  "riskControlsLabel",
  "claimEffect",
  "claimBlockedUntil",
  "supportResolution",
  "productDecision",
  "userVisibleContract",
  "productionTransportCommandShape",
  "doNotRunWithoutApproval",
  "expectedEvidenceCount",
  "expectedRedactedEvidenceCount",
  "riskControlCount",
  "exact command",
  "evidence safety",
  "production command",
  "reentry condition",
  "safe default"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensEvidenceReentryPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensEvidenceRequirementPresentation",
  "Runtime evidence requirements",
  "totalRequirementCount",
  "approvalRequiredCount",
  "directBlockerCount",
  "externalPendingCount",
  "productBlockedCount",
  "commandShapeCount",
  "support resolution",
  "product decision"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensEvidenceRequirementPresentation.swift", snippet);
}

for (const snippet of [
  "enum ClawJSRuntimeLensSupportSummaryPresentation",
  "Runtime projection summary",
  "Runtime sync policy summary",
  "Runtime evidence readiness summary",
  "implementedFacetLabel",
  "blockingFacetLabel",
  "blockedWriteBackLabel",
  "canonicalAuthorityLabel",
  "nativeAuthorityLabel",
  "persistenceLabel",
  "relationLabel",
  "writeBackPolicyLabel",
  "lossPolicyLabel",
  "freshnessLabel",
  "blockerClassLabel",
  "safeDefaultLabel",
  "approvalRequiredIdsLabel",
  "externalPendingIdsLabel",
  "upstreamContractIdsLabel",
  "approvalGateIdsLabel",
  "tuiGatewayIdsLabel",
  "productionTransportIdsLabel",
  "writeBackContractIdsLabel",
  "productBlockedIdsLabel",
  "unresolvedNativeIdsLabel",
  "nextRequiredActionsLabel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportSummaryPresentation.swift", snippet);
}

for (const snippet of [
  "enum ClawJSRuntimeLensSupportDecisionPresentation",
  "Runtime final promotion review",
  "Runtime final support claim decision",
  "productBlockedCount",
  "externalPendingCount",
  "productBlockedIdsLabel",
  "externalPendingIdsLabel",
  "unresolvedNativeIdsLabel",
  "decision: String?",
  "recommended: Bool",
  "production: Bool",
  "uiParityClaim",
  "blockedPromotionClaimsLabel",
  "blockerClassesLabel",
  "promotionEvidenceRequiredLabel",
  "safe default"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensSupportDecisionPresentation.swift", snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensValidationSummary",
  "semantic_lens_covered",
  "Runtime lens validation",
  "projected domains",
  "product blocked but projected",
  "read only sync domains",
  "local overlay domains",
  "syncFreshnessLabel",
  "freshness",
  "upstream contract blocked",
  "blocked claims",
  "finalDecisionId",
  "recommended: Bool",
  "production: Bool",
  "uiParityClaim",
  "finalDecisionBlockerClassesLabel",
  "finalDecisionPromotionEvidenceLabel",
  "listLabel("
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensValidationSummary.swift", snippet);
}

for (const snippet of [
  "Picker(\"\", selection: $runtimeLensSelection)",
  ".onChange(of: runtimeLensSelection)",
  "refreshRuntimeLens(runtimeLensSelection)",
  "ClawJSRuntimeLensRefreshPlan.scoped(to: runtime)",
  "ClawJSRuntimeLensSettingsPresentation.make",
  "validationAccessibilityLabel",
  "runtimeLensPresentation",
  "runtimeLensPresentationSection(section)",
  "runtimeLensPresentationRow(presentationRow)",
  "runtime-lens-section-",
  "runtime-lens-presentation-row-",
  "viewStateSection(viewState)",
  "ClawJSRuntimeLensViewStatePresentation.make",
  "runtimeSummaryBySectionId",
  "domainPresentationBySectionId",
  "runtimeSection(runtimeSummary)",
  "ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)",
  "officialSnapshot: snapshot.officialSnapshot",
  "supportSection(",
  "ClawJSRuntimeLensSupportOverviewPresentation.make(",
  "supportAuditSection(ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit))",
  "syncSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(sync: sync))",
  "projectionSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(projection: projection))",
  "evidenceReadinessSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(evidenceReadiness: readiness))",
  "closureSection(ClawJSRuntimeLensClosureChecklistPresentation.make(checklist: checklist, summary: audit.closureChecklistSummary))",
  "promotionReviewSection(ClawJSRuntimeLensSupportDecisionPresentation.make(review: review))",
  "finalDecisionSection(ClawJSRuntimeLensSupportDecisionPresentation.make(decision: decision))",
  "reentrySection(ClawJSRuntimeLensEvidenceReentryPresentation.make(packets: packets))",
  "sessionInventorySection(ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions))",
  "sessions.session ?? snapshot.session",
  "ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions)",
  "ClawJSRuntimeLensSessionDescriptorPresentation.make(session: session)",
  "ClawJSRuntimeLensSessionActionPresentation.make(actions: actions)",
  "evidence \\(action.requiredEvidenceCount)",
  "ClawJSRuntimeLensSessionActionContractPresentation.make",
  "ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands)",
  "args \\(command.argumentCount)",
  "commandSection(ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands))",
  "missingDomainSection(missing)",
  "ClawJSRuntimeLensMissingDomainPresentation.make(domains: domains)",
  "domainSection(domains)",
  "ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)",
  "supportContractSection(contracts)",
  "ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)",
  "inventorySection(inventory)",
  "runtimeLensDetailedInventory()",
  "runtimeLensInventory(snapshot, presentation: inventory)",
  "ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)",
  "ClawJSRuntimeLensEvidenceRequirementPresentation.make",
  "ClawJSRuntimeLensEvidenceReentryPresentation.make",
  "$0.exactCommand ?? $0.commandShape",
  "$0.evidenceSafetyPolicy",
  "$0.expectedRedactedEvidenceLabel",
  "$0.productionTransportCommandShape",
  "$0.expectedEvidenceLabel",
  "$0.supportResolution",
  "$0.productDecision",
  "$0.userVisibleContract",
  "ClawJSRuntimeLensSessionOverlayPresentation.make(state: state)",
  "sessionOverlaySection(ClawJSRuntimeLensSessionOverlayPresentation.make(state: overlay))",
  "ClawJSRuntimeLensDomainCommandPresentation.make",
  "ClawJSRuntimeLensValidationSummary.make",
  "runtime-lens-inventory",
  "runtime-lens-inventory-domain-",
  "runtime-lens-inventory-resource-",
  "Attributes: \\(attributes)",
  "runtimeSessionOverlayButton(snapshot: snapshot, resource: row.resource)",
  "ClawJSRuntimeLensSessionOverlayActionPresentation.make",
  "runtimeLensColor(ClawJSRuntimeLensStatusTone.",
  "readProjectionStatus",
  "projectionDisposition",
  "blocked write",
  "requirement.evidenceDisposition",
  "requirement.currentBehavior",
  "requirement.resolutionLabel",
  "product-blocked",
  "Promotion needs",
  "safeDefault",
  "External evidence required before this claim can be promoted.",
  "Official snapshot:",
  "Drift policy:"
]) {
  requireSnippetInFiles(runtimeLensSettingsFiles, snippet);
}

for (const snippet of [
  "struct ClawJSRuntimeLensRefreshPlan",
  "static func scoped(to runtime: ClawJSRuntimeLensID)",
  "ClawJSRuntimeLensRefreshPlan(runtimes: [runtime])"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensRefreshPlan.swift", snippet);
}

for (const snippet of [
  "snapshot.commands?.resourceDomains",
  "ClawJSRuntimeLensRuntimeSummaryPresentation.make",
  "runtimeSummaryPresentation.accessibilityLabel",
  "runtimeSummaryPresentation.capabilityStatusLabel",
  "runtimeSummaryPresentation.capabilityRows",
  "runtimeSummary.runtimeResourceAggregateDomainCount",
  "runtimeSummary.runtimeResourcesLabel",
  "ClawJSRuntimeLensSupportOverviewPresentation.make",
  "supportOverviewPresentation.accessibilityLabel",
  "ClawJSRuntimeLensViewStatePresentation.make",
  "viewStatePresentation.accessibilityLabel",
  "ClawJSRuntimeLensCommandMatrixPresentation.make",
  "commandPresentation.accessibilityLabel",
  "snapshot.supportAudit?.closureState",
  "ClawJSRuntimeLensSupportAuditPresentation.make",
  "supportAuditPresentation.accessibilityLabel",
  "snapshot.supportAudit?.evidenceRequirements?.first?.fallbackPolicy",
  "snapshot.supportAudit?.evidenceRequirements?.first?.supportResolution",
  "snapshot.supportAudit?.finalPromotionReview?.claimDisposition",
  "snapshot.supportAudit?.finalPromotionReview?.productBlockedRequirementIds",
  "snapshot.supportAudit?.finalPromotionReview?.externalPendingRequirementIds",
  "snapshot.supportAudit?.finalSupportClaimDecision?.safeDefault",
  "snapshot.supportAudit?.finalSupportClaimDecision?.claimDisposition",
  "snapshot.supportAudit?.finalSupportClaimDecision?.blockerClasses",
  "snapshot.supportAudit?.finalSupportClaimDecision?.promotionEvidenceRequired",
  "finalDecisionPresentation.claimDisposition",
  "finalDecisionPresentation.blockerClassesLabel",
  "finalDecisionPresentation.promotionEvidenceRequiredLabel",
  "ClawJSRuntimeLensSupportDecisionPresentation.make",
  "ClawJSRuntimeLensSupportSummaryPresentation.make",
  "projectionPresentation.accessibilityLabel",
  "syncPresentation.accessibilityLabel",
  "readinessPresentation.accessibilityLabel",
  "promotionReviewPresentation.accessibilityLabel",
  "finalDecisionPresentation.accessibilityLabel",
  "snapshot.supportAudit?.syncPolicySummary?.readOnlyProjectionDomains",
  "snapshot.supportAudit?.syncPolicySummary?.canonicalAuthorityCounts",
  "snapshot.supportAudit?.syncPolicySummary?.nativeAuthorityCounts",
  "snapshot.supportAudit?.syncPolicySummary?.persistenceCounts",
  "snapshot.supportAudit?.syncPolicySummary?.relationCounts",
  "snapshot.supportAudit?.syncPolicySummary?.writeBackPolicyCounts",
  "snapshot.supportAudit?.syncPolicySummary?.lossPolicyCounts",
  "snapshot.supportAudit?.syncPolicySummary?.localOverlayDomains",
  "snapshot.supportAudit?.syncPolicySummary?.freshnessCounts",
  "validationSummary.syncFreshnessLabel",
  "validationSummary.finalDecisionBlockerClassesLabel",
  "validationSummary.finalDecisionPromotionEvidenceLabel",
  "snapshot.supportAudit?.closureChecklist?.first",
  "snapshot.supportAudit?.projectionSummary?.projectedDomainCount",
  "snapshot.supportAudit?.projectionSummary?.productBlockedButProjectedDomainCount",
  "snapshot.supportAudit?.projectionSummary?.implementedFacetCounts",
  "snapshot.supportAudit?.projectionSummary?.blockingFacetCounts",
  "snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractBlockedCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateBlockedCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateRequirementIds",
  "snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayBlockedCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayRequirementIds",
  "snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportBlockedCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportRequirementIds",
  "snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractBlockedCount",
  "snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractRequirementIds",
  "snapshot.supportAudit?.evidenceReadinessSummary?.blockerClassCounts",
  "snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts",
  "snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingRequirementIds",
  "snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedRequirementIds",
  "readinessPresentation.blockerClassLabel",
  "readinessPresentation.productBlockedIdsLabel",
  "readProjectionStatus",
  "projectionDisposition",
  "implementedFacets?.contains",
  "blockingFacets?.contains",
  "snapshot.supportAudit?.closureChecklistSummary?[\"external_pending\"]",
  "ClawJSRuntimeLensClosureChecklistPresentation.make",
  "closurePresentation.accessibilityLabel",
  "closurePresentation.rows.first?.writeBackPolicy",
  "closurePresentation.rows.first?.evidenceRequirementIdsLabel",
  "closurePresentation.rows.first?.supportResolutionsLabel",
  "ClawJSRuntimeLensValidationSummary.make",
  "validationSummary.accessibilityLabel",
  "snapshot.supportAudit?.evidenceReentryPackets?.first?.safeDefault",
  "snapshot.supportAudit?.evidenceReentryPackets?.first?.exactCommand",
  "snapshot.supportAudit?.evidenceReentryPackets?.first?.evidenceSafetyPolicy",
  "snapshot.supportAudit?.evidenceReentryPackets?.first?.expectedRedactedEvidence",
  "snapshot.supportAudit?.evidenceReentryPackets?.first?.claimBlockedUntil",
  "snapshot.supportAudit?.evidenceReentryPackets?.last?.productionTransportCommandShape",
  "reentryPresentation.rows.first?.exactCommand",
  "reentryPresentation.rows.first?.evidenceSafetyPolicy",
  "reentryPresentation.rows.first?.expectedRedactedEvidenceLabel",
  "reentryPresentation.rows.first?.claimBlockedUntil",
  "reentryPresentation.rows.last?.productionTransportCommandShape",
  "reentryPresentation.rows.first?.expectedEvidenceLabel",
  "reentryPresentation.rows.first?.supportResolution",
  "reentryPresentation.rows.first?.productDecision",
  "reentryPresentation.rows.first?.userVisibleContract",
  "snapshot.domainData?.sessions?.overlayState",
  "snapshot.domainData?.sessions?.inventoryError",
  "ClawJSRuntimeLensSessionInventoryPresentation.make",
  "ClawJSRuntimeLensSessionDescriptorPresentation.make",
  "sessionDescriptorPresentation.accessibilityLabel",
  "ClawJSRuntimeLensSessionOverlayPresentation.make",
  "overlayPresentation.accessibilityLabel",
  "ClawJSRuntimeLensSessionOverlayActionPresentation.make",
  "sessionOverlayActionPresentation.accessibilityLabel",
  "ClawJSRuntimeLensStatusTone.sessionActionStatus",
  "ClawJSRuntimeLensStatusTone.resourceStatus",
  "snapshot.domainData?.sessions?.actionContracts",
  "ClawJSRuntimeLensSessionActionContractPresentation.make",
  "sessionActionContractPresentation.accessibilityLabel",
  "snapshot.domainData?.sessions?.actionPolicy",
  "ClawJSRuntimeLensSessionActionPresentation.make",
  "sessionActionPresentation.accessibilityLabel",
  "snapshot.domainData?.sessions?.supportContract?.evidenceRequirements",
  "snapshot.domains.first { $0.domain == \"channels\" }?.evidenceRequirements",
  "ClawJSRuntimeLensEvidenceRequirementPresentation.make",
  "ecosystemEvidencePresentation.accessibilityLabel",
  "auditEvidencePresentation.accessibilityLabel",
  "domainEvidencePresentation.accessibilityLabel",
  "ClawJSRuntimeLensDomainPresentation.make",
  "ClawJSRuntimeLensDomainCommandPresentation.make",
  "domainCommandPresentation.accessibilityLabel",
  "ClawJSRuntimeLensMissingDomainPresentation.make",
  "missingDomainPresentation.accessibilityLabel",
  "domainPresentation.accessibilityLabel",
  "ClawJSRuntimeLensSupportContractPresentation.make",
  "supportContractPresentation.accessibilityLabel",
  "ClawJSRuntimeLensInventoryPresentation.make",
  "inventoryPresentation.accessibilityLabel",
  "inventoryPresentation.attributeResourceCount",
  "authInventory.rows.first { $0.id == \"openai\" }?.attributesLabel",
  "modelInventory.rows.first { $0.id == \"default-model\" }?.attributesLabel",
  "pluginInventory.rows.first?.attributesLabel",
  "skillInventory.rows.first?.attributesLabel",
  "channelInventory.rows.first { $0.id == \"telegram\" }?.attributesLabel",
  "providerInventory.rows.first { $0.id == \"openai\" }?.attributesLabel",
  "sessionInventory.accessibilityLabel",
  "XCTAssertEqual(hermesSessionResource.pinAuthority, \"none\")",
  "XCTAssertEqual(hermesSessionResource.divergence, \"none\")",
  "XCTAssertEqual(hermesSessionResource.localOverlay?.writesRuntime, false)",
  "XCTAssertTrue(sessionInventory.rows.first?.attributes.contains(\"overlay pinned: false\") == true)",
  "XCTAssertEqual(hermesOverlayActionPresentation.action, \"pin\")",
  "XCTAssertEqual(hermesOverlayActionPresentation.targetPinned, true)",
  "XCTAssertEqual(result.nativeWriteBackStatus, \"blocked_until_official_runtime_write_back_contract\")",
  "XCTAssertEqual(result.evidenceRequirementId, \"hermes.sessions.pin.native_write_back_contract\")",
  "XCTAssertEqual(result.nativeWriteBackContract?.officialContractRequired, true)",
  "XCTAssertEqual(hermesPinCommand.nativeWriteBackStatus, \"blocked_until_official_runtime_write_back_contract\")",
  "XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == \"pin\" }?.nativeWriteBackStatus, \"blocked_until_official_runtime_write_back_contract\")",
  "XCTAssertEqual(contractPresentation.nativeWriteBackBlockedCount, 2)",
  "XCTAssertEqual(commandPresentation.nativeWriteBackBlockedCount, 6)",
  "XCTAssertEqual(commandPresentation.rows.first?.blockerClass, \"direct_blocker\")",
  "XCTAssertEqual(commandPresentation.rows.first?.nativeWriteBackFixtureRequired, true)",
  "XCTAssertEqual(commandPresentation.rows.first?.userVisibleContract, \"non_executable_until_tui_gateway_wrapper_fixture_exists\")",
  "XCTAssertEqual(commandPresentation.rows.first?.requiredEvidenceLabel, \"tui_gateway_prompt_submit_fixture, non_destructive_fixture, confirmation_or_dry_run_policy, round_trip_native_visibility\")",
  "channelInventory.statusLabel",
  "configurationInventory.statusLabel",
  "managed-file-1",
  "configuration-diagnostics",
  "configuration-capability",
  "snapshot.resources(for: \"auth\")",
  "snapshot.resources(for: \"gateway\")",
  "snapshot.resources(for: \"doctorCompat\")",
  "snapshot.resources(for: \"sandboxPermissions\")",
  "snapshot.resources(for: \"configuration\")",
  "setSessionPinned"
]) {
  requireSnippetInFiles(runtimeLensTestFiles, snippet);
}

if (errors.length > 0) {
  console.error("Runtime ecosystem lens check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("runtime ecosystem lens check passed");
