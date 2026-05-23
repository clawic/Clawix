import { For, Show, createSignal, onMount } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import { daemonStore, requestClawJSServiceStatuses, requestRateLimits } from "../lib/daemon_ws";
import { rateLimitRows, type RateLimitSnapshot } from "../lib/rate_limits_model";
import { serviceStatusRows, type ServiceStatus } from "../lib/service_status_model";
import IntegrationSettings from "./IntegrationSettings";
import PortableArchiveSettings from "./PortableArchiveSettings";
import RuntimeSettings from "./RuntimeSettings";

type Tab = "general" | "appearance" | "data" | "integrations" | "runtime" | "advanced";

interface DaemonStatus {
  installed: boolean;
  running: boolean;
  version: string | null;
}

export default function SettingsView() {
  const [tab, setTab] = createSignal<Tab>("general");
  const [status, setStatus] = createSignal<DaemonStatus | null>(null);
  const [hotkey, setHotkey] = createSignal("Super+Space");
  const [deviceName, setDeviceName] = createSignal("Linux");
  const [theme, setTheme] = createSignal<"system" | "light" | "dark">("system");

  onMount(async () => {
    try {
      setStatus(await invoke<DaemonStatus>("daemon_status"));
    } catch (_) {
      setStatus({ installed: false, running: false, version: null });
    }
    void requestRateLimits();
    void requestClawJSServiceStatuses();
    try {
      const stored = await invoke<string | null>("get_setting", { key: "ui.hotkey" });
      if (stored) setHotkey(stored);
      const name = await invoke<string | null>("get_setting", { key: "ui.deviceName" });
      if (name) setDeviceName(name);
      const t = await invoke<string | null>("get_setting", { key: "ui.theme" });
      if (t === "light" || t === "dark" || t === "system") setTheme(t);
    } catch (_) {
      /* preview mode or settings backend unavailable */
    }
  });

  async function persist(key: string, value: string) {
    try {
      await invoke("set_setting", { key, value });
    } catch (_) {
      /* preview mode or settings backend unavailable */
    }
  }

  return (
    <section class="flex h-full flex-col">
      <header class="flex h-14 items-center gap-4 border-b border-zinc-200/70 px-6 dark:border-zinc-800/70">
        <h1 class="text-[15px] font-semibold">Settings</h1>
        <nav class="inline-flex rounded-lg bg-zinc-100 p-0.5 text-xs font-medium dark:bg-zinc-900">
          <For each={["general", "appearance", "data", "integrations", "runtime", "advanced"] as const}>
            {(item) => (
              <button
                type="button"
                class="h-7 rounded-md px-3 transition-colors"
                classList={{
                  "bg-white text-zinc-950 shadow-sm dark:bg-zinc-800 dark:text-zinc-50": tab() === item,
                  "text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100": tab() !== item
                }}
                onClick={() => setTab(item)}
              >
                {titleForTab(item)}
              </button>
            )}
          </For>
        </nav>
      </header>

      <div class="flex-1 overflow-y-auto">
        <div class="mx-auto max-w-[720px] px-6 pb-12 pt-8">
          <PageHeader tab={tab()} />
          <Show when={tab() === "general"}>
            <GeneralSettings
              deviceName={deviceName()}
              hotkey={hotkey()}
              setDeviceName={setDeviceName}
              setHotkey={setHotkey}
              persist={persist}
            />
          </Show>
          <Show when={tab() === "appearance"}>
            <AppearanceSettings theme={theme()} setTheme={setTheme} persist={persist} />
          </Show>
          <Show when={tab() === "data"}>
            <PortableArchiveSettings />
          </Show>
          <Show when={tab() === "integrations"}>
            <IntegrationSettings />
          </Show>
          <Show when={tab() === "runtime"}>
            <RuntimeSettings />
          </Show>
          <Show when={tab() === "advanced"}>
            <AdvancedSettings status={status()} persist={persist} />
          </Show>
        </div>
      </div>
    </section>
  );
}

function GeneralSettings(props: {
  deviceName: string;
  hotkey: string;
  setDeviceName: (value: string) => string;
  setHotkey: (value: string) => string;
  persist: (key: string, value: string) => Promise<void>;
}) {
  return (
    <>
      <Section title="Connection">
        <Card>
          <Row label="Paired with" hint={daemonStore.hostDisplayName() ? `Currently bonded to ${daemonStore.hostDisplayName()}` : "Not paired"}>
            <code class="text-xs text-zinc-500">{daemonStore.hostDisplayName() ?? "-"}</code>
          </Row>
          <Divider />
          <Row label="Device label" hint="Shown in connected peers lists.">
            <input
              type="text"
              class="h-8 w-[220px] rounded-lg bg-zinc-100 px-3 text-[13px] font-medium outline-none dark:bg-zinc-800"
              value={props.deviceName}
              onChange={(e) => {
                props.setDeviceName(e.currentTarget.value);
                void props.persist("ui.deviceName", e.currentTarget.value);
              }}
            />
          </Row>
        </Card>
      </Section>

      <Section title="Keyboard">
        <Card>
          <Row label="QuickAsk hotkey" hint="Captured via the desktop portal on Wayland.">
            <input
              type="text"
              class="h-8 w-48 rounded-lg bg-zinc-100 px-3 text-[13px] font-medium outline-none dark:bg-zinc-800"
              value={props.hotkey}
              onChange={(e) => {
                props.setHotkey(e.currentTarget.value);
                void props.persist("ui.hotkey", e.currentTarget.value);
              }}
            />
          </Row>
        </Card>
      </Section>
    </>
  );
}

function AppearanceSettings(props: {
  theme: "system" | "light" | "dark";
  setTheme: (value: "system" | "light" | "dark") => "system" | "light" | "dark";
  persist: (key: string, value: string) => Promise<void>;
}) {
  return (
    <Section title="Theme">
      <Card>
        <Row label="Color scheme" hint="Linux follows the selected desktop preference unless overridden.">
          <select
            class="h-8 rounded-lg bg-zinc-100 px-3 text-[13px] font-medium outline-none dark:bg-zinc-800"
            value={props.theme}
            onChange={(e) => {
              const value = e.currentTarget.value as "system" | "light" | "dark";
              props.setTheme(value);
              void props.persist("ui.theme", value);
            }}
          >
            <option value="system">Match system</option>
            <option value="light">Always light</option>
            <option value="dark">Always dark</option>
          </select>
        </Row>
      </Card>
    </Section>
  );
}

function AdvancedSettings(props: { status: DaemonStatus | null; persist: (key: string, value: string) => Promise<void> }) {
  return (
    <>
      <Section title="Bridge runtime">
        <Card>
          <Row label="Daemon state">
            <code class="text-xs text-zinc-500">{daemonStore.bridgeState()}</code>
          </Row>
          <Divider />
          <Row label="Status">
            <code class="text-xs text-zinc-500">{props.status?.running ? "running" : "stopped"}</code>
          </Row>
          <Divider />
          <Row label="Installed">
            <code class="text-xs text-zinc-500">{props.status?.installed ? "yes" : "no"}</code>
          </Row>
          <Divider />
          <Row label="Version">
            <code class="text-xs text-zinc-500">{props.status?.version ?? "unknown"}</code>
          </Row>
          <Show when={daemonStore.bridgeMessage()}>
            <Divider />
            <Row label="Bridge message">
              <code class="text-xs text-red-500">{daemonStore.bridgeMessage()}</code>
            </Row>
          </Show>
        </Card>
      </Section>

      <Section title="Rate limits">
        <Card>
          <Show
            when={rateLimitRows(daemonStore.rateLimits() as RateLimitSnapshot | null).length > 0}
            fallback={<div class="px-3.5 py-3 text-xs text-zinc-500">No data yet.</div>}
          >
            <For each={rateLimitRows(daemonStore.rateLimits() as RateLimitSnapshot | null)}>
              {(row, index) => (
                <>
                  <Show when={index() > 0}>
                    <Divider />
                  </Show>
                  <Row label={row.label}>
                    <code class="text-xs text-zinc-500">{row.value}</code>
                  </Row>
                </>
              )}
            </For>
          </Show>
        </Card>
      </Section>

      <Section title="ClawJS services">
        <Card>
          <Show
            when={serviceStatusRows(daemonStore.clawJSServiceStatuses() as ServiceStatus[]).length > 0}
            fallback={<div class="px-3.5 py-3 text-xs text-zinc-500">No services reported yet.</div>}
          >
            <For each={serviceStatusRows(daemonStore.clawJSServiceStatuses() as ServiceStatus[])}>
              {(row, index) => (
                <>
                  <Show when={index() > 0}>
                    <Divider />
                  </Show>
                  <Row label={row.id}>
                    <code
                      class="text-xs"
                      classList={{
                        "text-emerald-600 dark:text-emerald-400": row.tone === "ok",
                        "text-red-600 dark:text-red-400": row.tone === "warn",
                        "text-zinc-500": row.tone === "muted"
                      }}
                    >
                      {row.detail}
                    </code>
                  </Row>
                </>
              )}
            </For>
          </Show>
        </Card>
      </Section>

      <Section title="Diagnostics">
        <Card>
          <Row label="Bridge port">
            <input
              type="number"
              class="h-8 w-32 rounded-lg bg-zinc-100 px-3 text-[13px] font-medium outline-none dark:bg-zinc-800"
              value={24080}
              onChange={(e) => void props.persist("daemon.port", e.currentTarget.value)}
            />
          </Row>
          <Divider />
          <Row label="Log level">
            <select
              class="h-8 rounded-lg bg-zinc-100 px-3 text-[13px] font-medium outline-none dark:bg-zinc-800"
              onChange={(e) => void props.persist("daemon.logLevel", e.currentTarget.value)}
            >
              <For each={["info", "debug", "warn", "error"]}>
                {(level) => <option value={level}>{level}</option>}
              </For>
            </select>
          </Row>
        </Card>
      </Section>
    </>
  );
}

function PageHeader(props: { tab: Tab }) {
  return (
    <header class="mb-7">
      <h2 class="text-[22px] font-semibold tracking-tightish">{titleForTab(props.tab)}</h2>
      <p class="mt-1 text-sm text-zinc-500">{subtitleForTab(props.tab)}</p>
    </header>
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
        <Show when={props.hint}>
          <div class="mt-0.5 text-[11px] font-medium leading-snug text-zinc-500">{props.hint}</div>
        </Show>
      </div>
      <div class="shrink-0">{props.children}</div>
    </div>
  );
}

function titleForTab(tab: Tab): string {
  if (tab === "general") return "General";
  if (tab === "appearance") return "Appearance";
  if (tab === "data") return "Data";
  if (tab === "integrations") return "Integrations";
  if (tab === "runtime") return "Runtime";
  return "Advanced";
}

function subtitleForTab(tab: Tab): string {
  if (tab === "general") return "Pairing, identity, and keyboard controls.";
  if (tab === "appearance") return "Theme and display preferences.";
  if (tab === "data") return "Export, verify, import, and restore portable archives.";
  if (tab === "integrations") return "MCP servers, provider accounts, and model routing.";
  if (tab === "runtime") return "Runtime adapter selection and local model availability.";
  return "Bridge runtime, rate limits, services, and diagnostics.";
}
