import { For, Show, createSignal } from "solid-js";
import {
  portableArchiveActions,
  portableArchiveExtensions,
  portableArchiveStateById,
  portableArchiveStateForAction,
  portableArchiveStates,
  type PortableArchiveActionId,
  type PortableArchiveStateId
} from "../lib/portable_archive_model";

export default function PortableArchiveSettings() {
  const [stateId, setStateId] = createSignal<PortableArchiveStateId>("ready");
  const state = () => portableArchiveStateById(stateId());

  function previewAction(actionId: PortableArchiveActionId) {
    setStateId(portableArchiveStateForAction(actionId).id);
  }

  return (
    <>
      <Section title="Portable archive">
        <div
          class="mb-3 rounded-lg border px-3.5 py-3 text-sm"
          classList={{
            "border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950/40 dark:text-emerald-200": state().tone === "ok",
            "border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-900/70 dark:bg-amber-950/40 dark:text-amber-200": state().tone === "warn",
            "border-red-200 bg-red-50 text-red-800 dark:border-red-900/70 dark:bg-red-950/40 dark:text-red-200": state().tone === "danger"
          }}
        >
          <div class="font-medium">{state().label}</div>
          <p class="mt-1 text-[12.5px] leading-relaxed">{state().detail}</p>
        </div>
        <Card>
          <For each={portableArchiveActions}>
            {(action, index) => (
              <>
                {index() > 0 ? <Divider /> : null}
                <Row label={action.label} hint={action.detail}>
                  <button
                    type="button"
                    aria-label={`Preview ${action.label}`}
                    class="rounded-lg px-3 py-1.5 text-sm font-medium"
                    classList={{
                      "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900": action.primary === true,
                      "bg-zinc-200 dark:bg-zinc-800": action.primary !== true
                    }}
                    onClick={() => previewAction(action.id)}
                  >
                    Preview
                  </button>
                </Row>
              </>
            )}
          </For>
        </Card>
      </Section>

      <Section title="Contract">
        <Card>
          <Row label="Programmatic surface" hint="Linux delegates archive authority to the framework CLI contract.">
            <code class="text-xs text-zinc-500">claw archive</code>
          </Row>
          <Divider />
          <Row label="File envelopes" hint={portableArchiveExtensions.join(", ")}>
            <code class="text-xs text-zinc-500">portable</code>
          </Row>
          <Divider />
          <Row label="Secrets gate" hint="Encrypted secrets backup, import, and restore require requires_signed_host proof.">
            <code class="text-xs text-zinc-500">signed-host proof</code>
          </Row>
          <Divider />
          <Row label="Restore gate" hint="Restore remains blocked until preview, verification, approval, and exact target confirmation pass.">
            <code class="text-xs text-zinc-500">two phase</code>
          </Row>
        </Card>
      </Section>

      <Section title="States">
        <Card>
          <For each={portableArchiveStates}>
            {(item, index) => (
              <>
                {index() > 0 ? <Divider /> : null}
                <Row label={item.label} hint={item.detail}>
                  <Show when={item.id === stateId()} fallback={<span class="w-[48px]" aria-hidden="true" />}>
                    <span class="text-xs font-medium text-zinc-950 dark:text-zinc-50">Current</span>
                  </Show>
                </Row>
              </>
            )}
          </For>
        </Card>
      </Section>
    </>
  );
}

function Section(props: { title: string; children: any }) {
  return (
    <section class="mb-7">
      <h3 class="mb-2 text-[11px] font-semibold uppercase text-zinc-500">{props.title}</h3>
      {props.children}
    </section>
  );
}

function Card(props: { children: any }) {
  return <div class="overflow-hidden rounded-lg bg-zinc-100/70 dark:bg-zinc-900/70">{props.children}</div>;
}

function Divider() {
  return <div class="h-px bg-zinc-200/70 dark:bg-zinc-800/70" />;
}

function Row(props: { label: string; hint?: string; children: any }) {
  return (
    <div class="flex items-center justify-between gap-6 px-3.5 py-3">
      <div class="min-w-0">
        <div class="text-[13px]">{props.label}</div>
        <div class="mt-0.5 text-[11px] font-medium leading-snug text-zinc-500">{props.hint}</div>
      </div>
      <div class="shrink-0">{props.children}</div>
    </div>
  );
}
