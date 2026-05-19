export const criticalMacosSliceId = "critical-macos-ui-evidence-2026-05-19";

const criticalMacosSurfaceIds = new Set([
  "macos-root-chrome",
  "macos-sidebar",
  "macos-chat-and-composer",
]);

const criticalMacosFlowIds = new Set([
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
]);

const criticalMacosPatternIds = new Set([
  "sidebar-section",
  "sidebar-row",
  "thin-scroller",
  "dropdown-menu",
  "icon-chip-button",
  "composer-chrome",
  "chat-surface",
  "sheet-chrome",
  "toast",
  "search-field",
  "right-sidebar-surface",
  "entity-card",
]);

export function privateSliceOption(args, fail, label) {
  const index = args.indexOf("--slice");
  if (index === -1) return null;

  const value = args[index + 1] || "";
  if (value !== criticalMacosSliceId) {
    fail(`${label} --slice must be ${criticalMacosSliceId}`);
    return null;
  }
  return value;
}

export function isCriticalMacosFlow(flow) {
  return flow?.platform === "macos" && criticalMacosFlowIds.has(flow?.id);
}

export function isCriticalMacosSurfaceCoverage(entry) {
  return entry?.platform === "macos" && criticalMacosSurfaceIds.has(entry?.coverageId);
}

export function isCriticalMacosDriftReport(report) {
  return report?.platform === "macos" && criticalMacosSurfaceIds.has(report?.coverageId);
}

export function isCriticalMacosPatternSnapshot(patternId, platform) {
  return platform === "macos" && criticalMacosPatternIds.has(patternId);
}

export function sliceLabel(slice) {
  return slice ? `; slice=${slice}` : "";
}
