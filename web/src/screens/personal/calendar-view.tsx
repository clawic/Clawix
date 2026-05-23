import { useMemo, useState } from "react";
import { CalendarIcon, PlusIcon } from "../../icons";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import { t } from "../../localization/i18n";
import { CALENDAR_EVENTS, CALENDAR_SOURCES, filterCalendarEvents, sourceForEvent } from "./personal-data-model";

export function CalendarView() {
  const [query, setQuery] = useState("");
  const events = useMemo(() => filterCalendarEvents(CALENDAR_EVENTS, query), [query]);

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[900px] mx-auto pt-8 pb-12 px-6">
          <div className="flex items-start gap-3 mb-4">
            <PageHeader title={t("Calendar")} subtitle={t("Local calendar sources and upcoming events.")} />
            <div className="flex-1" />
            <TextField value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("Search events")} aria-label={t("Search events")} className="max-w-[240px]" style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }} />
            <IconChipButton icon={<PlusIcon size={12} />} label={t("New event")} />
          </div>

          <div className="grid gap-3 md:grid-cols-[220px_1fr]">
            <Card>
              <div style={{ padding: 14 }}>
                <div className="mb-2 text-[13px] font-semibold text-[var(--color-fg)]">{t("Calendars")}</div>
                <div className="grid gap-2">
                  {CALENDAR_SOURCES.map((source) => (
                    <div key={source.id} className="flex items-center gap-2 rounded-md bg-white/[0.035] px-2.5 py-2">
                      <span className="h-2.5 w-2.5 rounded-full" style={{ background: source.color }} />
                      <div className="min-w-0 flex-1 truncate text-[12.5px] text-[var(--color-fg)]">{source.title}</div>
                      {source.isReadOnly && <span className="text-[10px] text-[var(--color-fg-tertiary)]">{t("read-only")}</span>}
                    </div>
                  ))}
                </div>
              </div>
            </Card>

            <Card>
              {events.map((event, index) => {
                const source = sourceForEvent(event);
                return (
                  <div key={event.id}>
                    {index > 0 && <CardDivider />}
                    <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
                      <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 32, height: 32 }}>
                        <CalendarIcon size={14} className="text-[var(--color-fg-secondary)]" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{event.title}</div>
                        <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">{source.title} · {event.day}</div>
                      </div>
                      <div className="grid justify-items-end gap-1">
                        <span className="font-mono text-[11.5px] text-[var(--color-fg)]">{event.time}</span>
                        <span className="text-[10.5px] text-[var(--color-fg-tertiary)]">{event.isAllDay ? t("all day") : `${event.durationMinutes}m`}</span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
