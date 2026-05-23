import { For, Show, createMemo, createSignal, onMount } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { applyQuickAskSnippet, quickAskSnippetSuggestions, quickAskSnippetSurface, type QuickAskSnippet } from "../lib/quickask_snippet_model";

export default function QuickAskHUD() {
  const [text, setText] = createSignal("");
  const [busy, setBusy] = createSignal(false);
  const suggestions = createMemo(() => quickAskSnippetSuggestions(text()));
  let inputRef: HTMLInputElement | undefined;

  onMount(() => {
    inputRef?.focus();
  });

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    const value = text().trim();
    if (!value || busy()) return;
    setBusy(true);
    try {
      await invoke("send_message", { args: { sessionId: null, text: value } });
      const win = getCurrentWindow();
      await win.hide();
      setText("");
    } finally {
      setBusy(false);
    }
  }

  async function injectSelectionFromActiveWindow() {
    try {
      const selection = await invoke<string>("read_primary_selection");
      if (selection) {
        setText((current) => `${current ? current + "\n" : ""}${selection}`);
      }
    } catch (_) {
      /* the user might not have a selection or wl-paste/xclip; quietly ignore */
    }
  }

  function applySnippet(snippet: QuickAskSnippet) {
    setText(applyQuickAskSnippet(text(), snippet));
    queueMicrotask(() => inputRef?.focus());
  }

  return (
    <section class="flex h-full w-full flex-col justify-center gap-2 bg-white/80 px-3 py-2 backdrop-blur-glass dark:bg-zinc-900/80">
      <Show when={suggestions().length > 0}>
        <div class="overflow-hidden rounded-lg bg-zinc-950/85 py-1 text-white shadow-lg dark:bg-zinc-950/95">
          <div class="px-2.5 pb-1 pt-1 text-[10px] font-bold uppercase text-white/55">
            {quickAskSnippetSurface.storageOwner}
          </div>
          <For each={suggestions()}>
            {(snippet) => (
              <button
                type="button"
                class="block w-full px-2.5 py-1.5 text-left hover:bg-white/10"
                onClick={() => applySnippet(snippet)}
              >
                <div class="text-[12px] font-semibold text-white/95">{snippet.title}</div>
                <div class="truncate text-[10px] font-medium text-white/55">{snippet.detail}</div>
              </button>
            )}
          </For>
        </div>
      </Show>

      <form onSubmit={submit} class="flex items-center gap-2">
        <input
          ref={(el) => (inputRef = el)}
          type="text"
          class="min-w-0 flex-1 bg-transparent text-base focus:outline-none placeholder-zinc-400"
          placeholder="Ask Clawix anything. Type / or @"
          value={text()}
          onInput={(e) => setText(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              void getCurrentWindow().hide();
            }
            if (e.key === "Tab") {
              e.preventDefault();
              void injectSelectionFromActiveWindow();
            }
          }}
        />
        <button
          type="submit"
          class="rounded-lg bg-zinc-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-40 dark:bg-zinc-100 dark:text-zinc-900"
          disabled={!text().trim() || busy()}
        >
          Send
        </button>
      </form>
    </section>
  );
}
