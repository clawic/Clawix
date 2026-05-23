import { Show, createResource, onMount } from "solid-js";
import QRCode from "qrcode";
import { daemonStore, requestPairingPayload } from "../lib/daemon_ws";

export default function BridgePairing() {
  onMount(() => {
    void requestPairingPayload();
  });

  const [qrSvg] = createResource(() => daemonStore.pairingPayload()?.qrJson, async (qrJson) => {
    if (!qrJson) return "";
    return await QRCode.toString(qrJson, { type: "svg", margin: 1, width: 220 });
  });

  return (
    <section class="h-full flex items-center justify-center px-8">
      <div class="max-w-md w-full text-center space-y-6">
        <header>
          <h1 class="text-xl font-semibold tracking-tightish">Pair iPhone</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Open the Clawix iOS app and scan this code, or type the short code shown below.
          </p>
        </header>
        <Show when={daemonStore.pairingPayload()} fallback={<div class="shimmer h-56 rounded-xl" />}>
          <div class="bg-white p-4 rounded-2xl inline-block" innerHTML={qrSvg() ?? ""} />
          <div class="text-2xl font-mono tracking-wider">{daemonStore.pairingPayload()?.shortCode}</div>
        </Show>
        <p class="text-xs text-zinc-500">
          Pairing requires Avahi (`systemctl is-active avahi-daemon`). If your distro disables it,
          enter the daemon IP and short code manually on the iPhone.
        </p>
      </div>
    </section>
  );
}
