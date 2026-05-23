import { Show, createMemo, createResource, onMount } from "solid-js";
import QRCode from "qrcode";
import { daemonStore, requestPairingPayload } from "../lib/daemon_ws";
import { pairingDetails } from "../lib/pairing_model";

export default function BridgePairing() {
  onMount(() => {
    void requestPairingPayload();
  });

  const details = createMemo(() => pairingDetails(daemonStore.pairingPayload()));

  const [qrSvg] = createResource(() => daemonStore.pairingPayload()?.qrJson, async (qrJson) => {
    if (!qrJson) return "";
    return await QRCode.toString(qrJson, { type: "svg", margin: 1, width: 228 });
  });

  return (
    <section class="h-full overflow-auto">
      <div class="mx-auto max-w-[640px] px-8 py-10 space-y-5">
        <header class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-[22px] font-semibold tracking-tightish">Pair iPhone</h1>
            <p class="mt-1 text-sm text-zinc-500">
              Scan from the iOS app, or enter the short code and host details manually.
            </p>
          </div>
          <button
            type="button"
            class="shrink-0 rounded-lg bg-zinc-200 px-3 py-1.5 text-sm font-medium dark:bg-zinc-800"
            onClick={() => void requestPairingPayload()}
          >
            Refresh code
          </button>
        </header>

        <div class="overflow-hidden rounded-lg bg-zinc-100/70 dark:bg-zinc-900/70">
          <Show
            when={daemonStore.pairingPayload()}
            fallback={
              <div class="space-y-4 p-4">
                <div class="shimmer h-[260px] rounded-lg" />
                <div class="shimmer h-10 rounded-lg" />
                <div class="shimmer h-20 rounded-lg" />
              </div>
            }
          >
            <div class="grid gap-5 p-4 md:grid-cols-[260px_1fr]">
              <div class="grid place-items-center rounded-lg bg-white p-4" innerHTML={qrSvg() ?? ""} />
              <div class="space-y-4">
                <div>
                  <div class="text-[12px] font-medium uppercase tracking-[0.08em] text-zinc-500">
                    Short code
                  </div>
                  <div class="mt-1 break-all font-mono text-2xl font-semibold tracking-wider">
                    {details().shortCode}
                  </div>
                </div>

                <div class="divide-y divide-zinc-200 rounded-lg bg-white text-sm dark:divide-zinc-800 dark:bg-zinc-950">
                  <PairingRow label="Host" value={details().hostDisplayName ?? "This Linux host"} />
                  <PairingRow label="Manual address" value={details().manualAddress ?? "Waiting for daemon address"} />
                  <PairingRow label="Discovery" value={details().isLoopback ? "Local bridge" : "Network bridge"} />
                </div>

                <p class="text-[12.5px] leading-relaxed text-zinc-500">
                  Pairing requires Avahi (`systemctl is-active avahi-daemon`). If discovery is disabled,
                  use the manual address and short code.
                </p>
              </div>
            </div>
          </Show>
        </div>
      </div>
    </section>
  );
}

function PairingRow(props: { label: string; value: string }) {
  return (
    <div class="flex items-center justify-between gap-3 px-3 py-2.5">
      <span class="text-zinc-500">{props.label}</span>
      <span class="min-w-0 break-all text-right font-medium">{props.value}</span>
    </div>
  );
}
