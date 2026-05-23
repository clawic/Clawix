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
  for (const snippet of ["runtime lens", "semantic native parity", "local overlays", "product-blocked", "status-tone contract", "finalPromotionReview", "finalSupportClaimDecision", "closureChecklist", "evidenceReentryPackets", "supportContract", "EXTERNAL PENDING", "resources <domain>", "stable `ok:false` JSON error envelopes", "claw commands resolve runtime resources --json", "model and plugin inventory", "capability diagnostics", "common runtime resource metadata", "claim source", "audit provenance source/runtime", "capability-map status counts", "top-level session descriptors", "top-level workspace canonical/managed file counts", "top-level resource aggregates"]) {
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
  "readProjectionStatus: String?",
  "implementedFacets: [String]?",
  "blockingFacets: [String]?",
  "projectionDisposition: String?",
  "evidenceReentryPackets: [EvidenceReentryPacket]?",
  "struct EvidenceReentryPacket",
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
  "workspace?.canonicalPaths",
  "workspace?.managedFiles",
  "runtimeResources?.skills",
  "runtimeResources?.providers",
  "runtimeResources?.auth",
  "runtimeResources?.defaultModel"
]) {
  requireSnippet("macos/Sources/Clawix/ClawJS/ClawJSRuntimeLensClient.swift", snippet);
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
  "claimSource",
  "provenanceSource",
  "sourceLabel",
  "blockingReasonCount",
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
  "riskControlsLabel",
  "claimEffect",
  "supportResolution",
  "productDecision",
  "userVisibleContract",
  "expectedEvidenceCount",
  "riskControlCount",
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
  "runtimeLensViewStatePresentation",
  "ClawJSRuntimeLensViewStatePresentation.make",
  "runtimeLensViewState(viewState)",
  "runtime-lens-view-state-",
  "runtimeLensSessionInventory(sessions)",
  "ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions)",
  "runtime-lens-session-inventory",
  "ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)",
  "runtime-lens-runtime-summary",
  "runtime-lens-runtime-location-",
  "runtime-lens-runtime-capability-",
  "enabled \\(presentation.rawCapabilityEnabledCount)/\\(presentation.rawCapabilityCount)",
  "snapshot.domainData?.sessions?.session ?? snapshot.session",
  "Workspace files",
  "Runtime resources",
  "groups \\(presentation.runtimeResourceAggregateDomainCount)",
  "workspaceCanonicalPathCount",
  "ClawJSRuntimeLensSupportOverviewPresentation.make(support: support)",
  "runtime-lens-support-overview",
  "Source: \\(source)",
  "runtimeLensSession(session)",
  "ClawJSRuntimeLensSessionDescriptorPresentation.make(session: session)",
  "runtime-lens-session-descriptor",
  "runtimeLensSessionActions(actions)",
  "ClawJSRuntimeLensSessionActionPresentation.make(actions: actions)",
  "evidence \\(action.requiredEvidenceCount)",
  "Evidence: \\(evidence)",
  "runtime-lens-session-actions",
  "runtimeLensSessionActionContracts(",
  "ClawJSRuntimeLensSessionActionContractPresentation.make",
  "runtime-lens-session-action-contracts",
  "runtime-lens-session-action-contract-",
  "runtimeLensCommands(commands)",
  "ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands)",
  "args \\(command.argumentCount)",
  "Args: \\(args)",
  "runtime-lens-command-matrix",
  "runtimeLensSupportAudit(supportAudit)",
  "ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit)",
  "runtime-lens-support-audit",
  "Audit source: \\(provenance)",
  "runtimeLensFinalPromotionReview(review)",
  "runtimeLensFinalSupportClaimDecision(decision)",
  "ClawJSRuntimeLensSupportDecisionPresentation.make(review: review)",
  "ClawJSRuntimeLensSupportDecisionPresentation.make(decision: decision)",
  "runtime-lens-final-promotion-review",
  "runtime-lens-final-support-claim-decision",
  "runtimeLensSyncPolicySummary(syncSummary)",
  "runtime-lens-sync-policy-summary",
  "ClawJSRuntimeLensSupportSummaryPresentation.make(sync: summary)",
  "runtimeLensProjectionSummary(projectionSummary)",
  "ClawJSRuntimeLensSupportSummaryPresentation.make(projection: summary)",
  "runtime-lens-projection-summary",
  "runtimeLensEvidenceReadinessSummary(readinessSummary)",
  "ClawJSRuntimeLensSupportSummaryPresentation.make(evidenceReadiness: summary)",
  "runtime-lens-evidence-readiness-summary",
  "runtimeLensClosureChecklist(checklist",
  "runtimeLensEvidenceReentryPackets(packets)",
  "ClawJSRuntimeLensEvidenceReentryPresentation.make",
  "runtime-lens-evidence-reentry-packets",
  "runtime-lens-evidence-reentry-row-",
  "row.expectedEvidenceLabel",
  "row.supportResolution",
  "row.productDecision",
  "row.userVisibleContract",
  "runtimeLensSessionOverlayState(overlayState)",
  "ClawJSRuntimeLensSessionOverlayPresentation.make(state: state)",
  "runtime-lens-session-overlays",
  "runtimeLensMissingDomains(snapshot)",
  "ClawJSRuntimeLensMissingDomainPresentation.make(domains: snapshot.domains)",
  "runtime-lens-missing-domains",
  "runtime-lens-missing-domain-",
  "runtimeLensDomains(snapshot)",
  "ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)",
  "Limitations: \\(limitations)",
  "runtime-lens-domains",
  "runtime-lens-domain-",
  "runtimeLensSupportContracts(snapshot)",
  "ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)",
  "runtime-lens-support-contracts",
  "runtime-lens-support-contract-",
  "runtimeLensDomainCommands(domain: domain.domain, commands: domain.officialCommands)",
  "ClawJSRuntimeLensDomainCommandPresentation.make",
  "runtime-lens-domain-commands-",
  "runtime-lens-domain-command-",
  "runtimeLensEvidenceRequirements",
  "ClawJSRuntimeLensEvidenceRequirementPresentation.make",
  "runtime-lens-evidence-requirements",
  "runtime-lens-evidence-requirement-",
  "ClawJSRuntimeLensClosureChecklistPresentation.make",
  "ClawJSRuntimeLensValidationSummary.make",
  "runtime-lens-section-",
  "runtimeLensInventory(snapshot)",
  "ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)",
  "runtime-lens-inventory",
  "runtime-lens-inventory-domain-",
  "runtime-lens-inventory-resource-",
  "Attributes: \\(attributes)",
  "runtimeSessionOverlayButton(snapshot: snapshot, resource: row.resource)",
  "ClawJSRuntimeLensSessionOverlayActionPresentation.make",
  "runtimeLensColor(ClawJSRuntimeLensStatusTone.",
  "runtime-lens-closure-checklist",
  "readProjectionStatus",
  "projectionDisposition",
  "blocked write",
  "requirement.evidenceDisposition",
  "requirement.currentBehavior",
  "requirement.resolutionLabel",
  "product-blocked",
  "Promotion needs",
  "safeDefault",
  "External evidence required before this claim can be promoted."
]) {
  requireSnippet("macos/Sources/Clawix/Settings/ClawJSSettingsPage.swift", snippet);
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
  "snapshot.supportAudit?.finalSupportClaimDecision?.blockerClasses",
  "snapshot.supportAudit?.finalSupportClaimDecision?.promotionEvidenceRequired",
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
  "channelInventory.statusLabel",
  "configurationInventory.statusLabel",
  "managed-file-1",
  "configuration-diagnostics",
  "snapshot.resources(for: \"auth\")",
  "snapshot.resources(for: \"gateway\")",
  "snapshot.resources(for: \"doctorCompat\")",
  "snapshot.resources(for: \"sandboxPermissions\")",
  "snapshot.resources(for: \"configuration\")",
  "setSessionPinned"
]) {
  requireSnippet("macos/Tests/ClawixMeshTests/ClawJSRuntimeLensClientTests.swift", snippet);
}

if (errors.length > 0) {
  console.error("Runtime ecosystem lens check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("runtime ecosystem lens check passed");
