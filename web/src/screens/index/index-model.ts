// UI-only fixture projection for the Web companion. ClawJS remains the
// authority for durable index, search, monitor, run, and alert records.
export type IndexTabId = "catalog" | "searches" | "monitors" | "runs" | "alerts";

export interface IndexCatalogItem {
  id: string;
  title: string;
  type: "conversation" | "file" | "project" | "memory";
  path: string;
  updatedLabel: string;
  score: number;
}

export interface IndexSearchItem {
  id: string;
  title: string;
  query: string;
  scope: string;
  resultCount: number;
  updatedLabel: string;
}

export interface IndexMonitorItem {
  id: string;
  title: string;
  scope: string;
  cadence: string;
  status: "running" | "paused";
  lastRunLabel: string;
}

export interface IndexRunItem {
  id: string;
  title: string;
  status: "completed" | "running" | "failed";
  durationLabel: string;
  itemCount: number;
  startedLabel: string;
}

export interface IndexAlertItem {
  id: string;
  title: string;
  severity: "info" | "warning" | "critical";
  source: string;
  unread: boolean;
  createdLabel: string;
}

export interface IndexDataset {
  catalog: IndexCatalogItem[];
  searches: IndexSearchItem[];
  monitors: IndexMonitorItem[];
  runs: IndexRunItem[];
  alerts: IndexAlertItem[];
}

export const INDEX_TABS: Array<{ id: IndexTabId; label: string }> = [
  { id: "catalog", label: "Catalog" },
  { id: "searches", label: "Searches" },
  { id: "monitors", label: "Monitors" },
  { id: "runs", label: "Runs" },
  { id: "alerts", label: "Alerts" },
];

export const INDEX_DATASET: IndexDataset = {
  catalog: [
    {
      id: "catalog-chat-release",
      title: "Release validation thread",
      type: "conversation",
      path: "Chats / Release",
      updatedLabel: "Today 10:44",
      score: 0.94,
    },
    {
      id: "catalog-project-web",
      title: "Web parity project",
      type: "project",
      path: "Projects / Web",
      updatedLabel: "Today 09:28",
      score: 0.91,
    },
    {
      id: "catalog-note-storage",
      title: "Storage boundary notes",
      type: "memory",
      path: "Memory / Architecture",
      updatedLabel: "Yesterday 17:12",
      score: 0.82,
    },
    {
      id: "catalog-file-roadmap",
      title: "route-roadmap.md",
      type: "file",
      path: "Drive / Documents",
      updatedLabel: "Yesterday 14:03",
      score: 0.78,
    },
  ],
  searches: [
    {
      id: "search-open-parity",
      title: "Open parity gaps",
      query: "web surface companion",
      scope: "All indexed content",
      resultCount: 18,
      updatedLabel: "Today 11:00",
    },
    {
      id: "search-bridge-contracts",
      title: "Bridge contracts",
      query: "schemaVersion route",
      scope: "Code and docs",
      resultCount: 42,
      updatedLabel: "Today 08:15",
    },
  ],
  monitors: [
    {
      id: "monitor-surface-registry",
      title: "Surface registry drift",
      scope: "Routes and manifests",
      cadence: "Every 30 minutes",
      status: "running",
      lastRunLabel: "8 minutes ago",
    },
    {
      id: "monitor-doc-links",
      title: "Documentation links",
      scope: "Docs",
      cadence: "Daily",
      status: "paused",
      lastRunLabel: "Yesterday",
    },
  ],
  runs: [
    {
      id: "run-index-refresh",
      title: "Full index refresh",
      status: "completed",
      durationLabel: "41s",
      itemCount: 1284,
      startedLabel: "Today 10:38",
    },
    {
      id: "run-monitor-pass",
      title: "Monitor sweep",
      status: "running",
      durationLabel: "12s",
      itemCount: 87,
      startedLabel: "Now",
    },
  ],
  alerts: [
    {
      id: "alert-route-gap",
      title: "Route marked companion",
      severity: "warning",
      source: "Surface registry",
      unread: true,
      createdLabel: "Today 10:59",
    },
    {
      id: "alert-search-complete",
      title: "Saved search completed",
      severity: "info",
      source: "Open parity gaps",
      unread: false,
      createdLabel: "Today 09:04",
    },
  ],
};

export function unreadIndexAlerts(dataset: IndexDataset = INDEX_DATASET): number {
  return dataset.alerts.filter((alert) => alert.unread).length;
}

export function indexTabLabel(tab: IndexTabId, dataset: IndexDataset = INDEX_DATASET): string {
  const base = INDEX_TABS.find((entry) => entry.id === tab)?.label ?? tab;
  if (tab !== "alerts") return base;
  const unread = unreadIndexAlerts(dataset);
  return unread > 0 ? `${base} / ${unread}` : base;
}

export function indexTabCount(tab: IndexTabId, dataset: IndexDataset = INDEX_DATASET): number {
  return dataset[tab].length;
}

export function filterIndexCatalog(items: IndexCatalogItem[], query: string): IndexCatalogItem[] {
  const normalized = normalizeQuery(query);
  if (!normalized) return items;
  return items.filter((item) =>
    [item.title, item.type, item.path, item.updatedLabel].some((value) => matches(value, normalized)),
  );
}

export function severityRank(severity: IndexAlertItem["severity"]): number {
  switch (severity) {
    case "critical":
      return 3;
    case "warning":
      return 2;
    case "info":
      return 1;
  }
}

export function sortedIndexAlerts(alerts: IndexAlertItem[]): IndexAlertItem[] {
  return [...alerts].sort((lhs, rhs) => {
    if (lhs.unread !== rhs.unread) return lhs.unread ? -1 : 1;
    return severityRank(rhs.severity) - severityRank(lhs.severity);
  });
}

function normalizeQuery(query: string): string {
  return query.trim().toLowerCase();
}

function matches(value: string, normalizedQuery: string): boolean {
  return value.toLowerCase().includes(normalizedQuery);
}
