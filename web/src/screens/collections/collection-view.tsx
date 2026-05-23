import { useMemo, useState } from "react";
import { Card, CardDivider, PageHeader, TextField } from "../../components/ui";
import { FileTextIcon, ListChecksIcon, StarIcon } from "../../icons";
import { t } from "../../localization/i18n";
import { filterCollectionRecords, type CollectionConfig, type CuratedCollectionId } from "./collection-model";

export function CollectionView({ collection }: { collection: CollectionConfig }) {
  const [query, setQuery] = useState("");
  const records = useMemo(
    () => filterCollectionRecords(collection.records, query),
    [collection.records, query],
  );
  const Icon = iconFor(collection.id);

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[760px] mx-auto pt-8 pb-12 px-6">
          <div className="flex items-start gap-3 mb-4">
            <PageHeader title={t(collection.title)} subtitle={t(collection.subtitle)} />
            <div className="flex-1" />
            <TextField
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("Search records")}
              aria-label={t("Search records")}
              className="max-w-[240px]"
              style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
            />
          </div>

          {records.length === 0 ? (
            <div className="py-12 text-center text-[12.5px] text-[var(--color-fg-secondary)]">
              {t(collection.emptyText)}
            </div>
          ) : (
            <Card>
              {records.map((record, index) => (
                <div key={record.id}>
                  {index > 0 && <CardDivider />}
                  <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
                    <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 30, height: 30 }}>
                      <Icon size={14} className="text-[var(--color-fg-secondary)]" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{record.title}</div>
                      <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">{record.detail}</div>
                    </div>
                    <div className="grid justify-items-end gap-1">
                      <span className="rounded-full bg-white/[0.06] px-2 py-0.5 text-[10.5px] font-semibold text-[var(--color-fg-secondary)]">
                        {record.status}
                      </span>
                      <span className="font-mono text-[10.5px] text-[var(--color-fg-tertiary)]">{record.meta}</span>
                    </div>
                  </div>
                </div>
              ))}
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

function iconFor(collectionId: CuratedCollectionId) {
  switch (collectionId) {
    case "tasks":
      return ListChecksIcon;
    case "goals":
      return StarIcon;
    case "notes":
      return FileTextIcon;
  }
}
