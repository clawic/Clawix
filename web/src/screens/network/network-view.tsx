import { useMemo, useState } from "react";
import type { ReactNode } from "react";
import { Card, IconChipButton, PageHeader, PillToggle } from "../../components/ui";
import { GlobeIcon, RefreshCwIcon, ShieldAlertIcon } from "../../icons";
import { storage, StorageKeys } from "../../lib/storage";
import { t } from "../../localization/i18n";
import {
  DEFAULT_NETWORK_SNAPSHOT,
  describeEndpoint,
  setNetworkDetailOptIn,
  statusPills,
  visibleNetworkEvents,
  type NetworkControlSnapshot,
} from "./network-model";

export function NetworkView() {
  const [snapshot, setSnapshot] = useState<NetworkControlSnapshot>(() => {
    const detailOptIn = storage.get<boolean>(StorageKeys.networkDetailOptIn) ?? false;
    return setNetworkDetailOptIn(DEFAULT_NETWORK_SNAPSHOT, detailOptIn);
  });
  const [refreshedAt, setRefreshedAt] = useState<string | null>(null);
  const events = useMemo(() => visibleNetworkEvents(snapshot.events), [snapshot.events]);

  function refresh() {
    setRefreshedAt(new Date().toISOString());
  }

  function setDetailOptIn(detailOptIn: boolean) {
    storage.set(StorageKeys.networkDetailOptIn, detailOptIn);
    setSnapshot((current) => setNetworkDetailOptIn(current, detailOptIn));
  }

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[920px] mx-auto pt-8 pb-12 px-6">
          <div className="flex items-start gap-3 mb-4">
            <PageHeader title={t("Network")} subtitle={t("Route policy, adapters, rules, and recent decisions.")} />
            <div className="flex-1" />
            <IconChipButton icon={<RefreshCwIcon size={12} />} label={t("Refresh")} onClick={refresh} />
          </div>

          <div className="grid gap-3">
            <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))" }}>
              {statusPills(snapshot).map((pill) => (
                <StatusPill key={pill.label} label={pill.label} value={pill.value} />
              ))}
            </div>

            <Card>
              <div className="flex items-center gap-3" style={{ padding: 14 }}>
                <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 34, height: 34 }}>
                  <ShieldAlertIcon size={15} className="text-[var(--color-fg-secondary)]" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="text-[13.5px] font-semibold text-[var(--color-fg)]">{t("Default redaction")}</div>
                  <div className="text-[12px] leading-[1.45] text-[var(--color-fg-secondary)]">
                    {snapshot.status.defaultRedaction}
                    {refreshedAt ? ` · ${t("Refreshed")}` : ""}
                  </div>
                </div>
                <span className="text-[11px] text-[var(--color-fg-secondary)]">{snapshot.status.detailOptIn ? t("Detail") : t("Aggregate")}</span>
                <PillToggle isOn={snapshot.status.detailOptIn} onChange={setDetailOptIn} />
              </div>
            </Card>

            <Section title={t("Adapters")}>
              {snapshot.adapters.map((adapter) => (
                <Row key={adapter.id} primary={adapter.label} secondary={adapter.reason} trailing={adapter.status} flagged={adapter.externalPending} />
              ))}
            </Section>

            <Section title={t("Rules")}>
              {snapshot.rules.map((rule) => (
                <Row
                  key={rule.id}
                  primary={`${rule.action} · ${describeEndpoint(rule.endpointKind, rule.endpointValue)}`}
                  secondary={rule.notes ?? rule.source}
                  trailing={rule.enabled ? t("enabled") : t("disabled")}
                />
              ))}
            </Section>

            <Section title={t("Recent")}>
              {events.map((event) => (
                <Row
                  key={event.id}
                  primary={`${event.decision} · ${describeEndpoint(event.endpointKind, event.endpointValue)}`}
                  secondary={`${event.subjectKind} · ${event.bytesIn + event.bytesOut} bytes`}
                  trailing={event.adapterId}
                  flagged={event.domainHidden || event.processHidden}
                />
              ))}
            </Section>
          </div>
        </div>
      </div>
    </div>
  );
}

function StatusPill({ label, value }: { label: string; value: string }) {
  return (
    <Card>
      <div className="grid gap-1" style={{ padding: "10px 12px" }}>
        <div className="text-[11px] text-[var(--color-fg-secondary)]">{t(label)}</div>
        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{value}</div>
      </div>
    </Card>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card>
      <div style={{ padding: "12px 14px" }}>
        <div className="mb-2 flex items-center gap-2 text-[13px] font-semibold text-[var(--color-fg)]">
          <GlobeIcon size={13} className="text-[var(--color-fg-secondary)]" />
          {title}
        </div>
        <div className="grid gap-1.5">{children}</div>
      </div>
    </Card>
  );
}

function Row({
  primary,
  secondary,
  trailing,
  flagged,
}: {
  primary: string;
  secondary: string;
  trailing: string;
  flagged?: boolean;
}) {
  return (
    <div className="flex items-center gap-3 rounded-md bg-white/[0.035] px-3 py-2">
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12.5px] text-[var(--color-fg)]">{primary}</div>
        <div className="truncate text-[11.5px] text-[var(--color-fg-secondary)]">{secondary}</div>
      </div>
      {flagged && <ShieldAlertIcon size={12} className="text-[var(--color-fg-secondary)]" />}
      <div className="max-w-[150px] truncate text-right text-[11.5px] text-[var(--color-fg-secondary)]">{trailing}</div>
    </div>
  );
}
