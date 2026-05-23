import { useMemo, useState } from "react";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import {
  ArchiveIcon,
  ClockIcon,
  DownloadIcon,
  FileTextIcon,
  FolderIcon,
  ImageIcon,
  ImagesIcon,
  Share2Icon,
  StarIcon,
} from "../../icons";
import { t } from "../../localization/i18n";
import {
  driveItemCounts,
  driveItemsForView,
  driveViewConfig,
  filterDriveItems,
  type DriveItem,
  type DriveItemKind,
  type DriveViewId,
} from "./drive-model";

export function DriveView({ view }: { view: DriveViewId }) {
  const [query, setQuery] = useState("");
  const config = driveViewConfig(view);
  const counts = driveItemCounts();
  const items = useMemo(() => filterDriveItems(driveItemsForView(view), query), [query, view]);
  const selected = items[0] ?? null;

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="flex flex-wrap items-start gap-3 mb-4">
            <PageHeader title={t(config.title)} subtitle={t(config.subtitle)} />
            <div className="flex-1 min-w-[160px]" />
            <TextField
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t(config.searchPlaceholder)}
              aria-label={t(config.searchPlaceholder)}
              className="max-w-[260px]"
              style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
            />
            <IconChipButton icon={<FolderIcon size={12} />} label={t("New folder")} />
            <IconChipButton icon={<DownloadIcon size={12} />} label={t("Import")} isPrimary />
          </div>

          <div className="grid gap-3 lg:grid-cols-[224px_1fr_230px]">
            <DriveSummary activeView={view} counts={counts} />

            <Card className="min-w-0">
              {items.length === 0 ? (
                <div className="py-12 text-center text-[12.5px] text-[var(--color-fg-tertiary)]">
                  {t(config.emptyText)}
                </div>
              ) : config.prefersGrid ? (
                <div className="grid grid-cols-2 gap-2 p-3 sm:grid-cols-3">
                  {items.map((item) => (
                    <DriveGridItem key={item.id} item={item} />
                  ))}
                </div>
              ) : (
                <div>
                  {items.map((item, index) => (
                    <div key={item.id}>
                      {index > 0 && <CardDivider />}
                      <DriveListItem item={item} />
                    </div>
                  ))}
                </div>
              )}
            </Card>

            <DriveDetail item={selected} />
          </div>
        </div>
      </div>
    </div>
  );
}

function DriveSummary({
  activeView,
  counts,
}: {
  activeView: DriveViewId;
  counts: Record<DriveViewId, number>;
}) {
  const rows: Array<{ id: DriveViewId; label: string; icon: typeof FolderIcon }> = [
    { id: "drive", label: "Drive", icon: FolderIcon },
    { id: "photos", label: "Photos", icon: ImagesIcon },
    { id: "documents", label: "Documents", icon: FileTextIcon },
    { id: "recent", label: "Recent", icon: ClockIcon },
  ];
  return (
    <Card>
      <div className="p-3">
        <div className="mb-2 px-1 text-[12px] font-semibold text-[var(--color-fg-secondary)]">
          {t("Library")}
        </div>
        <div className="grid gap-1">
          {rows.map((row) => {
            const Icon = row.icon;
            const selected = row.id === activeView;
            return (
              <div
                key={row.id}
                className="flex items-center gap-2 rounded-md px-2.5 py-2"
                style={{
                  background: selected ? "rgba(255,255,255,0.10)" : "transparent",
                  color: selected ? "var(--color-fg)" : "var(--color-fg-secondary)",
                }}
              >
                <Icon size={13} />
                <span className="min-w-0 flex-1 truncate text-[12.5px] font-semibold">{t(row.label)}</span>
                <span className="font-mono text-[11px] text-[var(--color-fg-tertiary)]">{counts[row.id]}</span>
              </div>
            );
          })}
        </div>
      </div>
    </Card>
  );
}

function DriveListItem({ item }: { item: DriveItem }) {
  const Icon = iconForKind(item.kind);
  return (
    <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
      <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 34, height: 34 }}>
        <Icon size={15} className="text-[var(--color-fg-secondary)]" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{item.name}</div>
        <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
          {item.parentLabel} / {item.mimeType}
        </div>
      </div>
      <DriveBadges item={item} />
      <div className="grid min-w-[86px] justify-items-end gap-1">
        <span className="font-mono text-[11px] text-[var(--color-fg)]">{item.sizeLabel}</span>
        <span className="text-[10.5px] text-[var(--color-fg-tertiary)]">{item.modifiedLabel}</span>
      </div>
    </div>
  );
}

function DriveGridItem({ item }: { item: DriveItem }) {
  return (
    <div className="rounded-lg bg-white/[0.045] p-2.5 shadow-[inset_0_0_0_0.5px_rgba(255,255,255,0.08)]">
      <div className="mb-2 grid aspect-[4/3] place-items-center rounded-md bg-white/[0.06]">
        <ImageIcon size={24} className="text-[var(--color-fg-secondary)]" />
      </div>
      <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{item.name}</div>
      <div className="mt-0.5 flex items-center justify-between gap-2 text-[10.5px] text-[var(--color-fg-tertiary)]">
        <span className="truncate">{item.sizeLabel}</span>
        <span className="shrink-0">{item.modifiedLabel.split(" ")[0]}</span>
      </div>
    </div>
  );
}

function DriveBadges({ item }: { item: DriveItem }) {
  if (!item.starred && !item.shared) return null;
  return (
    <div className="hidden items-center gap-1 sm:flex">
      {item.starred && (
        <span className="grid h-6 w-6 place-items-center rounded-full bg-white/[0.055] text-[var(--color-fg-secondary)]">
          <StarIcon size={12} />
        </span>
      )}
      {item.shared && (
        <span className="grid h-6 w-6 place-items-center rounded-full bg-white/[0.055] text-[var(--color-fg-secondary)]">
          <Share2Icon size={12} />
        </span>
      )}
    </div>
  );
}

function DriveDetail({ item }: { item: DriveItem | null }) {
  return (
    <Card className="min-w-0">
      <div className="p-4">
        <div className="mb-3 text-[13px] font-semibold text-[var(--color-fg)]">{t("Details")}</div>
        {item ? (
          <div className="grid gap-3">
            <div className="grid place-items-center rounded-lg bg-white/[0.055]" style={{ height: 92 }}>
              {(() => {
                const Icon = iconForKind(item.kind);
                return <Icon size={24} className="text-[var(--color-fg-secondary)]" />;
              })()}
            </div>
            <div>
              <div className="break-words text-[13px] font-semibold text-[var(--color-fg)]">{item.name}</div>
              <div className="mt-1 text-[12px] text-[var(--color-fg-secondary)]">{item.mimeType}</div>
            </div>
            <DetailRow label="Location" value={item.parentLabel} />
            <DetailRow label="Modified" value={item.modifiedLabel} />
            <DetailRow label="Size" value={item.sizeLabel} />
          </div>
        ) : (
          <div className="py-8 text-[12.5px] text-[var(--color-fg-tertiary)]">
            {t("No file selected")}
          </div>
        )}
      </div>
    </Card>
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

function iconForKind(kind: DriveItemKind) {
  switch (kind) {
    case "folder":
      return FolderIcon;
    case "image":
      return ImageIcon;
    case "document":
      return FileTextIcon;
    case "archive":
      return ArchiveIcon;
  }
}
