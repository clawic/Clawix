import { Show, createSignal } from "solid-js";
import { bytesToHex, deriveArgon2id, hexToBytes } from "../lib/argon2";

export default function VaultManagement() {
  const [step, setStep] = createSignal<"locked" | "unlocked" | "create">("locked");
  const [pass, setPass] = createSignal("");
  const [hash, setHash] = createSignal<string | null>(null);
  const [busy, setBusy] = createSignal(false);

  async function runSelfTest() {
    setBusy(true);
    try {
      const key = await deriveArgon2id({
        passphrase: pass() || "test",
        salt: hexToBytes("000102030405060708090a0b0c0d0e0f"),
        keyLen: 32,
        opsLimit: 3,
        memLimitBytes: 64 * 1024 * 1024
      });
      setHash(bytesToHex(key));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section class="h-full overflow-auto">
      <div class="max-w-[560px] mx-auto px-8 py-10 space-y-5">
        <header>
          <h1 class="text-[22px] font-semibold tracking-tightish">Secrets vault</h1>
          <p class="text-sm text-zinc-500 mt-1">
            Local-first crypto with host vault parity.
          </p>
        </header>

        <div class="overflow-hidden rounded-lg bg-zinc-100/70 dark:bg-zinc-900/70">
          <Show when={step() === "locked"}>
            <form
              class="space-y-4 p-4"
              onSubmit={(e) => {
                e.preventDefault();
                setStep("unlocked");
              }}
            >
              <div class="grid h-12 w-12 place-items-center rounded-[14px] bg-zinc-200/70 dark:bg-zinc-800/80">
                <span class="text-lg">#</span>
              </div>
              <div>
                <div class="text-base font-semibold tracking-tightish">Vault locked</div>
                <p class="mt-1 text-[12.5px] leading-relaxed text-zinc-500">
                  Unlock and reveal stay with the signed host vault surface. The self-test below
                  derives a local Argon2id key without moving plaintext secrets.
                </p>
              </div>
              <input
                type="password"
                class="w-full rounded-lg bg-white px-3 py-2 text-sm outline-none dark:bg-zinc-800"
                placeholder="Test passphrase"
                value={pass()}
                onInput={(e) => setPass(e.currentTarget.value)}
              />
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-60 dark:bg-zinc-100 dark:text-zinc-900"
                  disabled={busy()}
                  onClick={() => void runSelfTest()}
                >
                  {busy() ? "Deriving..." : "Run Argon2 self-test"}
                </button>
                <button
                  type="submit"
                  class="rounded-lg bg-zinc-200 px-4 py-2 text-sm font-medium dark:bg-zinc-800"
                  disabled={!pass()}
                >
                  Unlock preview
                </button>
                <button
                  type="button"
                  class="rounded-lg px-4 py-2 text-sm text-zinc-500"
                  onClick={() => setStep("create")}
                >
                  Create vault
                </button>
              </div>
              <Show when={hash()}>
                {(value) => (
                  <pre class="break-all rounded-lg bg-white p-3 font-mono text-[11px] text-zinc-500 dark:bg-zinc-950">
                    {value()}
                  </pre>
                )}
              </Show>
            </form>
          </Show>

          <Show when={step() === "create"}>
            <div class="space-y-3 p-4">
              <p class="text-sm text-zinc-500">
                Pick a strong passphrase. Linux will use the same Argon2id parameters before
                host-side storage accepts an unlock.
              </p>
              <input
                type="password"
                class="w-full rounded-lg bg-white px-3 py-2 text-sm outline-none dark:bg-zinc-800"
                placeholder="New passphrase"
              />
              <input
                type="password"
                class="w-full rounded-lg bg-white px-3 py-2 text-sm outline-none dark:bg-zinc-800"
                placeholder="Confirm passphrase"
              />
              <button
                type="button"
                class="w-full rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white dark:bg-zinc-100 dark:text-zinc-900"
                onClick={() => setStep("unlocked")}
              >
                Create vault preview
              </button>
            </div>
          </Show>

          <Show when={step() === "unlocked"}>
            <div class="space-y-3 p-4">
              <div class="text-sm font-medium">No secrets yet.</div>
              <p class="text-[12.5px] leading-relaxed text-zinc-500">
                Secret reveal and mutation stay behind the signed host vault surface.
              </p>
              <button class="rounded-lg bg-zinc-200 px-3 py-1.5 text-sm dark:bg-zinc-800">
                Add secret
              </button>
            </div>
          </Show>
        </div>
      </div>
    </section>
  );
}
