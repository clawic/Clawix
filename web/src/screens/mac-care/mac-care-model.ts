// UI-only fixture projection for the Web companion. ClawJS owns the Mac Care
// route atlas, scan sidecar, action plans, approvals, and finalizer previews.
export interface MacCareRoute {
  id: string;
  family: string;
  label: string;
  pathPattern: string;
  sensitivity: string;
  mutability: string;
  steward: string;
}

export interface MacCareScanSummary {
  id: string;
  moduleId: string;
  status: string;
  completedAtLabel: string;
  modules: string[];
  candidateCount: number;
  totalSizeBytes: number;
  destructiveActions: number;
}

export interface MacCareCandidate {
  id: string;
  displayName: string;
  path: string;
  action: string;
  selection: string;
  sizeBytes: number;
  confidence: number;
}

export interface MacCareFinalizerAction {
  id: string;
  displayName: string;
  path: string;
  action: string;
  selection: string;
  rollbackLevel: string;
  receiptStatus: string;
}

export interface MacCareDataset {
  sidecarFilename: string;
  destructiveExecutionAuthority: string;
  routes: MacCareRoute[];
  scans: MacCareScanSummary[];
  selectedScanId: string;
  candidates: MacCareCandidate[];
  finalizerActions: MacCareFinalizerAction[];
}

export const MAC_CARE_DATASET: MacCareDataset = {
  sidecarFilename: "mac_care.sqlite",
  destructiveExecutionAuthority: "agent_plan_only",
  selectedScanId: "scan.web-parity.latest",
  routes: [
    {
      id: "route-cache",
      family: "cache",
      label: "Build caches",
      pathPattern: "~/Library/Caches/clawix/**",
      sensitivity: "low",
      mutability: "read-only report",
      steward: "framework",
    },
    {
      id: "route-logs",
      family: "logs",
      label: "Diagnostic logs",
      pathPattern: "~/Library/Logs/Clawix/**",
      sensitivity: "medium",
      mutability: "review required",
      steward: "host",
    },
    {
      id: "route-sidecars",
      family: "sidecar",
      label: "Sidecar reports",
      pathPattern: "~/.claw/mac-care/*.sqlite",
      sensitivity: "medium",
      mutability: "read-only report",
      steward: "framework",
    },
  ],
  scans: [
    {
      id: "scan.web-parity.latest",
      moduleId: "mac-care",
      status: "completed",
      completedAtLabel: "Today 10:42",
      modules: ["cache", "logs", "sidecar"],
      candidateCount: 4,
      totalSizeBytes: 18_944_000,
      destructiveActions: 1,
    },
    {
      id: "scan.web-parity.previous",
      moduleId: "mac-care",
      status: "completed",
      completedAtLabel: "Yesterday 18:20",
      modules: ["cache", "logs"],
      candidateCount: 2,
      totalSizeBytes: 7_168_000,
      destructiveActions: 0,
    },
  ],
  candidates: [
    {
      id: "candidate-cache-vite",
      displayName: "Vite transform cache",
      path: "~/Library/Caches/clawix/web-transform",
      action: "review",
      selection: "candidate",
      sizeBytes: 12_288_000,
      confidence: 0.92,
    },
    {
      id: "candidate-old-log",
      displayName: "Old bridge log",
      path: "~/Library/Logs/Clawix/bridge-previous.log",
      action: "archive",
      selection: "manual",
      sizeBytes: 4_096_000,
      confidence: 0.84,
    },
    {
      id: "candidate-stale-sidecar",
      displayName: "Stale sidecar report",
      path: "~/.claw/mac-care/scan-previous.sqlite",
      action: "keep",
      selection: "reference",
      sizeBytes: 2_560_000,
      confidence: 0.76,
    },
  ],
  finalizerActions: [
    {
      id: "finalizer-old-log",
      displayName: "Old bridge log",
      path: "~/Library/Logs/Clawix/bridge-previous.log",
      action: "archive",
      selection: "manual",
      rollbackLevel: "copy",
      receiptStatus: "preview",
    },
  ],
};

export function macCareSummary(dataset: MacCareDataset = MAC_CARE_DATASET) {
  return {
    routes: dataset.routes.length,
    scans: dataset.scans.length,
    candidates: dataset.scans.reduce((sum, scan) => sum + scan.candidateCount, 0),
    sizeLabel: formatBytes(dataset.scans.reduce((sum, scan) => sum + scan.totalSizeBytes, 0)),
    authority: hasDestructiveActionPlan(dataset) ? "Review" : "Read-only",
  };
}

export function selectedMacCareScan(dataset: MacCareDataset = MAC_CARE_DATASET): MacCareScanSummary | null {
  return dataset.scans.find((scan) => scan.id === dataset.selectedScanId) ?? dataset.scans[0] ?? null;
}

export function hasDestructiveActionPlan(dataset: MacCareDataset = MAC_CARE_DATASET): boolean {
  return dataset.scans.some((scan) => scan.destructiveActions > 0) || dataset.finalizerActions.length > 0;
}

export function routesBySensitivity(dataset: MacCareDataset = MAC_CARE_DATASET): Record<string, number> {
  return dataset.routes.reduce<Record<string, number>>((counts, route) => {
    counts[route.sensitivity] = (counts[route.sensitivity] ?? 0) + 1;
    return counts;
  }, {});
}

export function formatBytes(value: number): string {
  if (value < 1024) return `${value} B`;
  const units = ["KB", "MB", "GB"];
  let amount = value / 1024;
  let unitIndex = 0;
  while (amount >= 1024 && unitIndex < units.length - 1) {
    amount /= 1024;
    unitIndex += 1;
  }
  return `${amount.toFixed(amount >= 10 ? 0 : 1)} ${units[unitIndex]}`;
}
