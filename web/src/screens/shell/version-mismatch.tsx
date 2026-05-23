/**
 * Banner shown when the daemon advertises a higher schemaVersion than
 * this SPA knows about. The fix is to update the Mac app, which will ship
 * a newer web bundle inside its daemon.
 */
import { t } from "../../localization/i18n";
import { classifyUserFacingFailure } from "../../lib/user-facing-failure";

export function VersionMismatchBanner({ serverVersion }: { serverVersion: number }) {
  return (
    <div className="px-5 py-3 border-b border-[var(--color-banner-danger-fg)]/40 bg-[var(--color-banner-danger-fg)]/10 text-[12.5px] text-[var(--color-banner-danger-fg)] flex items-center justify-between">
      <div>
        {t("Your Mac is running a newer Clawix bridge.")} {t("Protocol")} v{serverVersion}.{" "}
        {t("Reload this page after the Mac app finishes launching the new daemon.")}
      </div>
      <button
        onClick={() => window.location.reload()}
        className="h-8 px-3 rounded-[8px] bg-[var(--color-banner-danger-fg)]/20 hover:bg-[var(--color-banner-danger-fg)]/30 text-[12px]"
      >
        {t("Reload")}
      </button>
    </div>
  );
}

export function OfflineBridgeBanner({ reason }: { reason: string }) {
  const failure = classifyUserFacingFailure(reason);
  return (
    <div className="px-5 py-3 border-b border-[var(--color-banner-danger-fg)]/40 bg-[var(--color-banner-danger-fg)]/10 text-[12.5px] text-[var(--color-banner-danger-fg)] flex items-center justify-between">
      <div>
        {failure.message} {t("Retrying automatically.")}
      </div>
      <button
        onClick={() => window.location.reload()}
        className="h-8 px-3 rounded-[8px] bg-[var(--color-banner-danger-fg)]/20 hover:bg-[var(--color-banner-danger-fg)]/30 text-[12px]"
      >
        {t("Retry")}
      </button>
    </div>
  );
}
