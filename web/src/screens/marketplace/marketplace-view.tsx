import { useMemo, useState } from "react";
import { SlidingSegmented } from "../../components/sliding-segmented";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import {
  BadgeCheckIcon,
  InboxIcon,
  LinkIcon,
  RefreshCwIcon,
  SearchIcon,
  StarIcon,
  WebhookIcon,
} from "../../icons";
import { t } from "../../localization/i18n";
import {
  MARKETPLACE_DATASET,
  MARKETPLACE_TABS,
  filterMarketplaceIntents,
  marketplaceTabCount,
  marketplaceTabLabel,
  prospectProgressPercent,
  receiptStatusLabel,
  unreadMarketplaceMessages,
  type MarketplaceIntent,
  type MarketplaceMessage,
  type MarketplaceProspect,
  type MarketplaceReceipt,
  type MarketplaceTabId,
} from "./marketplace-model";

export function MarketplaceView() {
  const [activeTab, setActiveTab] = useState<MarketplaceTabId>("offers");
  const [query, setQuery] = useState("");
  const offers = useMemo(() => filterMarketplaceIntents(MARKETPLACE_DATASET.offers, query), [query]);
  const wants = useMemo(() => filterMarketplaceIntents(MARKETPLACE_DATASET.wants, query), [query]);
  const unread = unreadMarketplaceMessages();

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="mb-4 flex flex-wrap items-start gap-3">
            <PageHeader
              title={
                <span className="inline-flex items-center gap-2">
                  <LinkIcon size={18} />
                  {t("Marketplace")}
                  {unread > 0 && (
                    <span className="rounded-full bg-[#f0a23a] px-1.5 py-0.5 text-[10.5px] font-semibold text-black">
                      {unread}
                    </span>
                  )}
                </span>
              }
              subtitle={t("Offers, wants, prospects, receipts, and encrypted peer inbox.")}
            />
            <div className="flex-1 min-w-[160px]" />
            <IconChipButton icon={<RefreshCwIcon size={12} />} label={t("Refresh")} />
          </div>

          <div className="mb-3 flex flex-wrap items-center gap-3">
            <SlidingSegmented
              value={activeTab}
              onChange={setActiveTab}
              options={MARKETPLACE_TABS.map((tab) => ({ value: tab.id, label: marketplaceTabLabel(tab.id) }))}
              size="sm"
            />
            <div className="flex-1" />
            {(activeTab === "offers" || activeTab === "wants") && (
              <TextField
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={t("Search marketplace")}
                aria-label={t("Search marketplace")}
                className="max-w-[260px]"
                style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
              />
            )}
          </div>

          <div className="grid gap-3 lg:grid-cols-[224px_1fr_230px]">
            <MarketplaceSummary activeTab={activeTab} />
            <Card className="min-w-0">
              {activeTab === "offers" && <IntentList intents={offers} emptyTitle="No offers published" />}
              {activeTab === "wants" && <IntentList intents={wants} emptyTitle="No active searches" />}
              {activeTab === "prospects" && <ProspectList prospects={MARKETPLACE_DATASET.prospects} />}
              {activeTab === "receipts" && <ReceiptList receipts={MARKETPLACE_DATASET.receipts} />}
              {activeTab === "inbox" && <InboxList messages={MARKETPLACE_DATASET.inbox} />}
            </Card>
            <MarketplaceDetail activeTab={activeTab} />
          </div>
        </div>
      </div>
    </div>
  );
}

function MarketplaceSummary({ activeTab }: { activeTab: MarketplaceTabId }) {
  return (
    <Card>
      <div className="p-3">
        <div className="mb-2 px-1 text-[12px] font-semibold text-[var(--color-fg-secondary)]">
          {t("Marketplace")}
        </div>
        <div className="grid gap-1">
          {MARKETPLACE_TABS.map((tab) => {
            const selected = tab.id === activeTab;
            return (
              <div
                key={tab.id}
                className="flex items-center gap-2 rounded-md px-2.5 py-2"
                style={{
                  background: selected ? "rgba(255,255,255,0.10)" : "transparent",
                  color: selected ? "var(--color-fg)" : "var(--color-fg-secondary)",
                }}
              >
                <TabIcon tab={tab.id} size={13} />
                <span className="min-w-0 flex-1 truncate text-[12.5px] font-semibold">{t(tab.label)}</span>
                <span className="font-mono text-[11px] text-[var(--color-fg-tertiary)]">
                  {marketplaceTabCount(tab.id)}
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </Card>
  );
}

function IntentList({ intents, emptyTitle }: { intents: MarketplaceIntent[]; emptyTitle: string }) {
  if (intents.length === 0) return <EmptyState title={emptyTitle} detail="No matching intents." />;
  return (
    <div className="grid gap-2 p-3">
      {intents.map((intent) => (
        <div key={intent.id} className="rounded-lg bg-white/[0.04] p-3">
          <div className="mb-1 flex flex-wrap items-center gap-1.5">
            <span className="text-[11px] font-semibold text-[var(--color-fg-secondary)]">{intent.vertical}</span>
            <CountPill value={intent.status} />
            <CountPill value={intent.provenance === "native" ? "verified" : "observed"} />
          </div>
          <div className="text-[13.5px] font-semibold text-[var(--color-fg)]">{intent.title}</div>
          <div className="mt-1 line-clamp-2 text-[12px] text-[var(--color-fg-secondary)]">{intent.summary}</div>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {intent.tags.map((tag) => (
              <CountPill key={tag} value={tag} />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function ProspectList({ prospects }: { prospects: MarketplaceProspect[] }) {
  return (
    <div>
      {prospects.map((prospect, index) => (
        <div key={prospect.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <div className="grid h-9 w-9 place-items-center rounded-full bg-white/[0.07] text-[12px] font-semibold text-[var(--color-fg)]">
              L{prospect.currentLevel}
            </div>
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{prospect.peerLabel}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                Last update {prospect.lastUpdatedLabel}
              </div>
            </div>
            <div className="h-1.5 w-28 overflow-hidden rounded-full bg-white/[0.08]">
              <div className="h-full rounded-full bg-white/[0.42]" style={{ width: `${prospectProgressPercent(prospect)}%` }} />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function ReceiptList({ receipts }: { receipts: MarketplaceReceipt[] }) {
  return (
    <div>
      {receipts.map((receipt, index) => (
        <div key={receipt.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <BadgeCheckIcon size={14} className="text-[var(--color-fg-secondary)]" />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">
                {receiptStatusLabel(receipt.status)}
              </div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {receipt.peerLabel} / level {receipt.reachedLevel}
              </div>
            </div>
            <CountPill value={receipt.fieldsRevealed.join(", ")} />
          </div>
        </div>
      ))}
    </div>
  );
}

function InboxList({ messages }: { messages: MarketplaceMessage[] }) {
  return (
    <div>
      {messages.map((message, index) => (
        <div key={message.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-start gap-3" style={{ padding: "12px 14px" }}>
            <span className={`mt-1.5 h-2 w-2 rounded-full ${message.read ? "bg-white/25" : "bg-[#f0a23a]"}`} />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{message.senderLabel}</div>
              <div className="text-[12px] text-[var(--color-fg-secondary)]">{message.text}</div>
              <div className="mt-1 text-[10.5px] text-[var(--color-fg-tertiary)]">
                {message.kind} / {message.receivedLabel}
              </div>
            </div>
            {!message.read && <CountPill value="Unread" />}
          </div>
        </div>
      ))}
    </div>
  );
}

function MarketplaceDetail({ activeTab }: { activeTab: MarketplaceTabId }) {
  const tabLabel = MARKETPLACE_TABS.find((tab) => tab.id === activeTab)?.label ?? activeTab;
  return (
    <Card className="min-w-0">
      <div className="p-4">
        <div className="mb-3 text-[13px] font-semibold text-[var(--color-fg)]">{t("Details")}</div>
        <div className="grid gap-3">
          <div className="grid place-items-center rounded-lg bg-white/[0.055]" style={{ height: 92 }}>
            <TabIcon tab={activeTab} size={24} />
          </div>
          <DetailRow label={t("Tab")} value={tabLabel} />
          <DetailRow label={t("Items")} value={String(marketplaceTabCount(activeTab))} />
          <DetailRow label={t("Unread inbox")} value={String(unreadMarketplaceMessages())} />
        </div>
      </div>
    </Card>
  );
}

function EmptyState({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="grid place-items-center gap-1 py-12 text-center">
      <div className="text-[13px] font-semibold text-[var(--color-fg-secondary)]">{t(title)}</div>
      <div className="text-[12px] text-[var(--color-fg-tertiary)]">{t(detail)}</div>
    </div>
  );
}

function CountPill({ value }: { value: string }) {
  return (
    <span className="rounded-full bg-white/[0.06] px-2 py-0.5 text-[10.5px] font-semibold text-[var(--color-fg-secondary)]">
      {value}
    </span>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid gap-0.5">
      <span className="text-[10.5px] uppercase text-[var(--color-fg-tertiary)]">{t(label)}</span>
      <span className="break-words text-[12px] text-[var(--color-fg-secondary)]">{value}</span>
    </div>
  );
}

function TabIcon({ tab, size }: { tab: MarketplaceTabId; size: number }) {
  switch (tab) {
    case "offers":
      return <StarIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "wants":
      return <SearchIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "prospects":
      return <WebhookIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "receipts":
      return <BadgeCheckIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "inbox":
      return <InboxIcon size={size} className="text-[var(--color-fg-secondary)]" />;
  }
}
