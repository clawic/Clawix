import { For, createSignal } from "solid-js";
import {
  agentLibrarySurfaceById,
  agentLibrarySurfaces,
  type AgentLibrarySurfaceId
} from "../lib/agent_library_model";

export default function AgentLibraryView() {
  const [selected, setSelected] = createSignal<AgentLibrarySurfaceId>("agents");
  const surface = () => agentLibrarySurfaceById(selected());

  return (
    <section class="h-full overflow-auto">
      <div class="mx-auto max-w-[720px] px-8 py-10">
        <header class="mb-7">
          <h1 class="text-[22px] font-semibold tracking-tightish">Agents</h1>
          <p class="mt-1 text-sm text-zinc-500">
            Agents, skills, collections, and connections share the framework library contracts.
          </p>
        </header>

        <section class="mb-7">
          <h2 class="mb-2 text-[11px] font-semibold uppercase text-zinc-500">Library</h2>
          <div class="grid gap-2 md:grid-cols-2">
            <For each={agentLibrarySurfaces}>
              {(item) => (
                <button
                  type="button"
                  class="rounded-lg border p-3 text-left transition-colors"
                  classList={{
                    "border-zinc-300 bg-white dark:border-zinc-700 dark:bg-zinc-950": selected() === item.id,
                    "border-transparent bg-zinc-100/70 dark:bg-zinc-900/70": selected() !== item.id
                  }}
                  onClick={() => setSelected(item.id)}
                >
                  <div class="text-sm font-semibold">{item.title}</div>
                  <p class="mt-1 text-[12px] leading-relaxed text-zinc-500">{item.detail}</p>
                </button>
              )}
            </For>
          </div>
        </section>

        <Section title="Details">
          <Card>
            <Row label="Surface" hint={surface().detail}>
              <code class="text-xs text-zinc-500">{surface().title}</code>
            </Row>
            <Divider />
            <Row label="Storage owner" hint={surface().storageOwner}>
              <code class="text-xs text-zinc-500">framework</code>
            </Row>
            <Divider />
            <Row label="Validation" hint={surface().validation}>
              <code class="text-xs text-zinc-500">guarded</code>
            </Row>
          </Card>
        </Section>

        <Section title="Commands">
          <Card>
            <For each={surface().commands}>
              {(command, index) => (
                <>
                  {index() > 0 ? <Divider /> : null}
                  <Row label={command}>
                    <code class="text-xs text-zinc-500">{command}</code>
                  </Row>
                </>
              )}
            </For>
          </Card>
        </Section>
      </div>
    </section>
  );
}

function Section(props: { title: string; children: any }) {
  return (
    <section class="mb-7">
      <h2 class="mb-2 text-[11px] font-semibold uppercase text-zinc-500">{props.title}</h2>
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
        {props.hint ? <div class="mt-0.5 text-[11px] font-medium leading-snug text-zinc-500">{props.hint}</div> : null}
      </div>
      <div class="shrink-0">{props.children}</div>
    </div>
  );
}
