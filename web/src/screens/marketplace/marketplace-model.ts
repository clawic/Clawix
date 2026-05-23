export type MarketplaceTabId = "offers" | "wants" | "prospects" | "receipts" | "inbox";

export interface MarketplaceIntent {
  id: string;
  side: "offer" | "want";
  vertical: string;
  status: "published" | "draft" | "paused";
  provenance: "native" | "observed";
  title: string;
  summary: string;
  tags: string[];
}

export interface MarketplaceProspect {
  id: string;
  peerLabel: string;
  currentLevel: number;
  lastUpdatedLabel: string;
}

export interface MarketplaceReceipt {
  id: string;
  status: "signed" | "awaiting_human_approval" | "proposed_by_peer";
  peerLabel: string;
  reachedLevel: number;
  fieldsRevealed: string[];
}

export interface MarketplaceMessage {
  id: string;
  kind: string;
  senderLabel: string;
  text: string;
  receivedLabel: string;
  read: boolean;
}

export interface MarketplaceDataset {
  offers: MarketplaceIntent[];
  wants: MarketplaceIntent[];
  prospects: MarketplaceProspect[];
  receipts: MarketplaceReceipt[];
  inbox: MarketplaceMessage[];
}

export const MARKETPLACE_TABS: Array<{ id: MarketplaceTabId; label: string }> = [
  { id: "offers", label: "My Offers" },
  { id: "wants", label: "My Wants" },
  { id: "prospects", label: "Prospects" },
  { id: "receipts", label: "Receipts" },
  { id: "inbox", label: "Inbox" },
];

export const MARKETPLACE_DATASET: MarketplaceDataset = {
  offers: [
    {
      id: "offer-workspace-review",
      side: "offer",
      vertical: "workspace",
      status: "published",
      provenance: "native",
      title: "Workspace review",
      summary: "Review local project structure, docs, and validation evidence.",
      tags: ["review", "docs", "validation"],
    },
    {
      id: "offer-automation-audit",
      side: "offer",
      vertical: "automation",
      status: "draft",
      provenance: "native",
      title: "Automation audit",
      summary: "Inspect scheduled jobs and summarize stale or risky entries.",
      tags: ["automation", "audit"],
    },
  ],
  wants: [
    {
      id: "want-route-evidence",
      side: "want",
      vertical: "surface-routes",
      status: "published",
      provenance: "native",
      title: "Route validation packet",
      summary: "Looking for evidence packets that prove route parity across clients.",
      tags: ["routes", "parity"],
    },
  ],
  prospects: [
    {
      id: "prospect-peer-alpha",
      peerLabel: "peer-8f2a0c1b",
      currentLevel: 3,
      lastUpdatedLabel: "Today 10:30",
    },
    {
      id: "prospect-peer-beta",
      peerLabel: "peer-41ce902d",
      currentLevel: 1,
      lastUpdatedLabel: "Yesterday 19:05",
    },
  ],
  receipts: [
    {
      id: "receipt-route-packet",
      status: "signed",
      peerLabel: "peer-8f2a0c1b",
      reachedLevel: 3,
      fieldsRevealed: ["summary", "evidence"],
    },
    {
      id: "receipt-audit-review",
      status: "awaiting_human_approval",
      peerLabel: "peer-41ce902d",
      reachedLevel: 1,
      fieldsRevealed: ["title"],
    },
  ],
  inbox: [
    {
      id: "inbound-route-question",
      kind: "inquiry",
      senderLabel: "peer-8f2a0c1b",
      text: "Can you share the latest route validation packet?",
      receivedLabel: "Today 10:52",
      read: false,
    },
    {
      id: "inbound-audit-followup",
      kind: "follow-up",
      senderLabel: "peer-41ce902d",
      text: "The automation audit receipt is ready for review.",
      receivedLabel: "Yesterday 18:44",
      read: true,
    },
  ],
};

export function unreadMarketplaceMessages(dataset: MarketplaceDataset = MARKETPLACE_DATASET): number {
  return dataset.inbox.filter((message) => !message.read).length;
}

export function marketplaceTabLabel(tab: MarketplaceTabId, dataset: MarketplaceDataset = MARKETPLACE_DATASET): string {
  const base = MARKETPLACE_TABS.find((entry) => entry.id === tab)?.label ?? tab;
  if (tab !== "inbox") return base;
  const unread = unreadMarketplaceMessages(dataset);
  return unread > 0 ? `${base} / ${unread}` : base;
}

export function marketplaceTabCount(tab: MarketplaceTabId, dataset: MarketplaceDataset = MARKETPLACE_DATASET): number {
  return dataset[tab].length;
}

export function filterMarketplaceIntents(intents: MarketplaceIntent[], query: string): MarketplaceIntent[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return intents;
  return intents.filter((intent) =>
    [
      intent.title,
      intent.summary,
      intent.vertical,
      intent.status,
      intent.provenance,
      ...intent.tags,
    ].some((value) => value.toLowerCase().includes(normalized)),
  );
}

export function prospectProgressPercent(prospect: MarketplaceProspect): number {
  return Math.max(0, Math.min(100, Math.round((prospect.currentLevel / 5) * 100)));
}

export function receiptStatusLabel(status: MarketplaceReceipt["status"]): string {
  switch (status) {
    case "signed":
      return "signed";
    case "awaiting_human_approval":
      return "awaiting approval";
    case "proposed_by_peer":
      return "proposed by peer";
  }
}
