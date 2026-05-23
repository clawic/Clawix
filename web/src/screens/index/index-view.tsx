import { useMemo, useState } from "react";
import { SlidingSegmented } from "../../components/sliding-segmented";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import {
  CircleAlertIcon,
  CircleCheckIcon,
  ClockIcon,
  DatabaseIcon,
  FileTextIcon,
  FolderIcon,
  PlusIcon,
  RefreshCwIcon,
  SearchIcon,
} from "../../icons";
import { t } from "../../localization/i18n";
import {
  INDEX_DATASET,
  INDEX_TABS,
  filterIndexCatalog,
  indexTabCount,
  indexTabLabel,
  sortedIndexAlerts,
  unreadIndexAlerts,
  type IndexAlertItem,
  type IndexCatalogItem,
  type IndexMonitorItem,
  type IndexRunItem,
  type IndexSearchItem,
  type IndexTabId,
} from "./index-model";

export function IndexView() {
  const [activeTab, setActiveTab] = useState<IndexTabId>("catalog");
  const [query, setQuery] = useState("");
  const catalog = useMemo(() => filterIndexCatalog(INDEX_DATASET.catalog, query), [query]);
  const alerts = useMemo(() => sortedIndexAlerts(INDEX_DATASET.alerts), []);
  const unread = unreadIndexAlerts();

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="flex flex-wrap items-start gap-3 mb-4">
            <PageHeader
              title={
                <span className="inline-flex items-center gap-2">
                  <DatabaseIcon size={18} />
                  {t("Index")}
                  {unread > 0 && (
                    <span className="rounded-full bg-[#f0a23a] px-1.5 py-0.5 text-[10.5px] font-semibold text-black">
                      {unread}
                    </span>
                  )}
                </span>
              }
              subtitle={t("Catalog, saved searches, monitors, runs, and alerts.")}
            />
            <div className="flex-1 min-w-[160px]" />
            <IconChipButton icon={<PlusIcon size={12} />} label={t("New search")} isPrimary />
            <IconChipButton icon={<RefreshCwIcon size={12} />} label={t("Refresh")} />
          </div>

          <div className="mb-3 flex flex-wrap items-center gap-3">
            <SlidingSegmented
              value={activeTab}
              onChange={setActiveTab}
              options={INDEX_TABS.map((tab) => ({ value: tab.id, label: indexTabLabel(tab.id) }))}
              size="sm"
            />
            <div className="flex-1" />
            {activeTab === "catalog" && (
              <TextField
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={t("Search catalog")}
                aria-label={t("Search catalog")}
                className="max-w-[260px]"
                style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
              />
            )}
          </div>

          <div className="grid gap-3 lg:grid-cols-[224px_1fr_230px]">
            <IndexSummary activeTab={activeTab} />
            <Card className="min-w-0">
              {activeTab === "catalog" && <CatalogList items={catalog} />}
              {activeTab === "searches" && <SearchList items={INDEX_DATASET.searches} />}
              {activeTab === "monitors" && <MonitorList items={INDEX_DATASET.monitors} />}
              {activeTab === "runs" && <RunList items={INDEX_DATASET.runs} />}
              {activeTab === "alerts" && <AlertList items={alerts} />}
            </Card>
            <IndexDetail activeTab={activeTab} />
          </div>
        </div>
      </div>
    </div>
  );
}

function IndexSummary({ activeTab }: { activeTab: IndexTabId }) {
  return (
    <Card>
      <div className="p-3">
        <div className="mb-2 px-1 text-[12px] font-semibold text-[var(--color-fg-secondary)]">
          {t("Index")}
        </div>
        <div className="grid gap-1">
          {INDEX_TABS.map((tab) => {
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
                  {indexTabCount(tab.id)}
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </Card>
  );
}

function CatalogList({ items }: { items: IndexCatalogItem[] }) {
  if (items.length === 0) {
    return <EmptyState title={t("No catalog results")} detail="Try a different catalog query." />;
  }
  return (
    <div>
      {items.map((item, index) => (
        <div key={item.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 32, height: 32 }}>
              <CatalogIcon type={item.type} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.title}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {item.path} / {item.type}
              </div>
            </div>
            <div className="grid min-w-[74px] justify-items-end gap-1">
              <span className="font-mono text-[11px] text-[var(--color-fg)]">{Math.round(item.score * 100)}%</span>
              <span className="text-[10.5px] text-[var(--color-fg-tertiary)]">{item.updatedLabel}</span>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function SearchList({ items }: { items: IndexSearchItem[] }) {
  return (
    <div>
      {items.map((item, index) => (
        <div key={item.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <SearchIcon size={14} className="text-[var(--color-fg-secondary)]" />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.title}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {item.query} / {item.scope}
              </div>
            </div>
            <CountPill value={`${item.resultCount} results`} />
          </div>
        </div>
      ))}
    </div>
  );
}

function MonitorList({ items }: { items: IndexMonitorItem[] }) {
  return (
    <div>
      {items.map((item, index) => (
        <div key={item.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <ClockIcon size={14} className="text-[var(--color-fg-secondary)]" />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.title}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {item.scope} / {item.cadence}
              </div>
            </div>
            <CountPill value={item.status} />
          </div>
        </div>
      ))}
    </div>
  );
}

function RunList({ items }: { items: IndexRunItem[] }) {
  return (
    <div>
      {items.map((item, index) => (
        <div key={item.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <CircleCheckIcon size={14} className="text-[var(--color-fg-secondary)]" />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.title}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {item.startedLabel} / {item.durationLabel}
              </div>
            </div>
            <CountPill value={`${item.itemCount} items`} />
          </div>
        </div>
      ))}
    </div>
  );
}

function AlertList({ items }: { items: IndexAlertItem[] }) {
  return (
    <div>
      {items.map((item, index) => (
        <div key={item.id}>
          {index > 0 && <CardDivider />}
          <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
            <CircleAlertIcon size={14} className="text-[var(--color-fg-secondary)]" />
            <div className="min-w-0 flex-1">
              <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.title}</div>
              <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
                {item.source} / {item.createdLabel}
              </div>
            </div>
            <CountPill value={item.unread ? "Unread" : item.severity} />
          </div>
        </div>
      ))}
    </div>
  );
}

function IndexDetail({ activeTab }: { activeTab: IndexTabId }) {
  const tabLabel = INDEX_TABS.find((tab) => tab.id === activeTab)?.label ?? activeTab;
  return (
    <Card className="min-w-0">
      <div className="p-4">
        <div className="mb-3 text-[13px] font-semibold text-[var(--color-fg)]">{t("Details")}</div>
        <div className="grid gap-3">
          <div className="grid place-items-center rounded-lg bg-white/[0.055]" style={{ height: 92 }}>
            <TabIcon tab={activeTab} size={24} />
          </div>
          <DetailRow label={t("Tab")} value={tabLabel} />
          <DetailRow label={t("Items")} value={String(indexTabCount(activeTab))} />
          <DetailRow label={t("Unread alerts")} value={String(unreadIndexAlerts())} />
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

function CatalogIcon({ type }: { type: IndexCatalogItem["type"] }) {
  switch (type) {
    case "conversation":
      return <SearchIcon size={14} className="text-[var(--color-fg-secondary)]" />;
    case "file":
      return <FileTextIcon size={14} className="text-[var(--color-fg-secondary)]" />;
    case "project":
      return <FolderIcon size={14} className="text-[var(--color-fg-secondary)]" />;
    case "memory":
      return <DatabaseIcon size={14} className="text-[var(--color-fg-secondary)]" />;
  }
}

function TabIcon({ tab, size }: { tab: IndexTabId; size: number }) {
  switch (tab) {
    case "catalog":
      return <DatabaseIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "searches":
      return <SearchIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "monitors":
      return <ClockIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "runs":
      return <CircleCheckIcon size={size} className="text-[var(--color-fg-secondary)]" />;
    case "alerts":
      return <CircleAlertIcon size={size} className="text-[var(--color-fg-secondary)]" />;
  }
}
