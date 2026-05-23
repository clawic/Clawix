import type { ReactNode } from "react";
import { Card, CardDivider, IconChipButton, PageHeader } from "../../components/ui";
import {
  CircleCheckIcon,
  FileTextIcon,
  FolderIcon,
  RefreshCwIcon,
  ShieldAlertIcon,
  WrenchIcon,
} from "../../icons";
import { t } from "../../localization/i18n";
import {
  MAC_CARE_DATASET,
  formatBytes,
  macCareSummary,
  selectedMacCareScan,
  type MacCareCandidate,
  type MacCareFinalizerAction,
  type MacCareRoute,
  type MacCareScanSummary,
} from "./mac-care-model";

export function MacCareView() {
  const summary = macCareSummary();
  const selectedScan = selectedMacCareScan();

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="mb-5 flex flex-wrap items-start gap-3">
            <PageHeader
              title={
                <span className="inline-flex items-center gap-2">
                  <WrenchIcon size={18} />
                  {t("Mac Care")}
                </span>
              }
              subtitle={t("Read-only reports from the framework atlas and persisted scan history.")}
            />
            <div className="flex-1 min-w-[160px]" />
            <IconChipButton icon={<RefreshCwIcon size={12} />} label={t("Refresh")} />
          </div>

          <div className="mb-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <MetricTile title={t("Routes")} value={String(summary.routes)} detail={MAC_CARE_DATASET.sidecarFilename} />
            <MetricTile title={t("Scans")} value={String(summary.scans)} detail={selectedScan?.completedAtLabel ?? "No scan"} />
            <MetricTile title={t("Candidates")} value={String(summary.candidates)} detail={summary.sizeLabel} />
            <MetricTile title={t("Authority")} value={summary.authority} detail={MAC_CARE_DATASET.destructiveExecutionAuthority} />
          </div>

          <div className="grid gap-3 lg:grid-cols-[1fr_1fr]">
            <SectionCard title={t("Scan history")}>
              {MAC_CARE_DATASET.scans.map((scan, index) => (
                <div key={scan.id}>
                  {index > 0 && <CardDivider />}
                  <ScanRow scan={scan} selected={scan.id === MAC_CARE_DATASET.selectedScanId} />
                </div>
              ))}
            </SectionCard>

            {selectedScan && (
              <SectionCard title={t("Selected scan")}>
                <div className="grid gap-3 p-3 sm:grid-cols-4">
                  <InlineMetric title={t("Status")} value={selectedScan.status} />
                  <InlineMetric title={t("Candidates")} value={String(selectedScan.candidateCount)} />
                  <InlineMetric title={t("Size")} value={formatBytes(selectedScan.totalSizeBytes)} />
                  <InlineMetric title={t("Safety")} value={selectedScan.destructiveActions > 0 ? "review" : "none"} />
                </div>
                <CardDivider />
                {MAC_CARE_DATASET.candidates.map((candidate, index) => (
                  <div key={candidate.id}>
                    {index > 0 && <CardDivider />}
                    <CandidateRow candidate={candidate} />
                  </div>
                ))}
              </SectionCard>
            )}

            <SectionCard title={t("Finalizer preview")}>
              <div className="grid gap-3 p-3 sm:grid-cols-4">
                <InlineMetric title={t("Authority")} value="signed host" />
                <InlineMetric title={t("Execution")} value="No" />
                <InlineMetric title={t("Receipts")} value="0" />
                <InlineMetric title={t("Actions")} value={String(MAC_CARE_DATASET.finalizerActions.length)} />
              </div>
              <CardDivider />
              {MAC_CARE_DATASET.finalizerActions.map((action, index) => (
                <div key={action.id}>
                  {index > 0 && <CardDivider />}
                  <FinalizerRow action={action} />
                </div>
              ))}
            </SectionCard>

            <SectionCard title={t("Route atlas")}>
              {MAC_CARE_DATASET.routes.map((route, index) => (
                <div key={route.id}>
                  {index > 0 && <CardDivider />}
                  <RouteRow route={route} />
                </div>
              ))}
            </SectionCard>
          </div>
        </div>
      </div>
    </div>
  );
}

function SectionCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card className="min-w-0">
      <div className="px-3.5 py-3 text-[13px] font-semibold text-[var(--color-fg)]">{t(title)}</div>
      <CardDivider />
      {children}
    </Card>
  );
}

function MetricTile({ title, value, detail }: { title: string; value: string; detail: string }) {
  return (
    <Card>
      <div className="grid min-h-[96px] content-start gap-1.5 p-3.5">
        <div className="text-[11.5px] font-semibold text-[var(--color-fg-secondary)]">{t(title)}</div>
        <div className="truncate text-[20px] font-semibold text-[var(--color-fg)]">{value}</div>
        <div className="truncate text-[11px] text-[var(--color-fg-secondary)]">{detail}</div>
      </div>
    </Card>
  );
}

function ScanRow({ scan, selected }: { scan: MacCareScanSummary; selected: boolean }) {
  return (
    <div className="flex items-center gap-3" style={{ padding: "11px 14px" }}>
      <CircleCheckIcon size={14} className={selected ? "text-[#86c98a]" : "text-[var(--color-fg-secondary)]"} />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{scan.id}</div>
        <div className="truncate text-[11px] text-[var(--color-fg-secondary)]">
          {scan.modules.join(", ")} / {scan.completedAtLabel}
        </div>
      </div>
      <InlineMetric title={t("Candidates")} value={String(scan.candidateCount)} />
      <InlineMetric title={t("Size")} value={formatBytes(scan.totalSizeBytes)} />
    </div>
  );
}

function CandidateRow({ candidate }: { candidate: MacCareCandidate }) {
  return (
    <div className="flex items-start gap-3" style={{ padding: "11px 14px" }}>
      <FileTextIcon size={14} className="mt-0.5 text-[var(--color-fg-secondary)]" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{candidate.displayName}</div>
        <div className="truncate text-[11px] text-[var(--color-fg-secondary)]">{candidate.path}</div>
      </div>
      <InlineMetric title={candidate.action} value={candidate.selection} />
      <InlineMetric title={t("Size")} value={formatBytes(candidate.sizeBytes)} />
    </div>
  );
}

function FinalizerRow({ action }: { action: MacCareFinalizerAction }) {
  return (
    <div className="flex items-start gap-3" style={{ padding: "11px 14px" }}>
      <ShieldAlertIcon size={14} className="mt-0.5 text-[#f0a23a]" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{action.displayName}</div>
        <div className="truncate text-[11px] text-[var(--color-fg-secondary)]">{action.path}</div>
      </div>
      <InlineMetric title={action.action} value={action.selection} />
      <InlineMetric title={t("Rollback")} value={action.rollbackLevel} />
      <InlineMetric title={t("Receipt")} value={action.receiptStatus} />
    </div>
  );
}

function RouteRow({ route }: { route: MacCareRoute }) {
  return (
    <div className="flex items-start gap-3" style={{ padding: "11px 14px" }}>
      <FolderIcon size={14} className="mt-0.5 text-[var(--color-fg-secondary)]" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{route.label}</div>
        <div className="truncate text-[11px] text-[var(--color-fg-secondary)]">{route.pathPattern}</div>
      </div>
      <InlineMetric title={route.sensitivity} value={route.mutability} />
    </div>
  );
}

function InlineMetric({ title, value }: { title: string; value: string }) {
  return (
    <div className="grid min-w-[72px] content-start gap-0.5">
      <span className="truncate text-[10.5px] font-semibold text-[var(--color-fg-secondary)]">{t(title)}</span>
      <span className="truncate text-[11.5px] font-semibold text-[var(--color-fg)]">{value}</span>
    </div>
  );
}
