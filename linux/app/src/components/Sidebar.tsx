import { For, Show, createMemo } from "solid-js";
import { A } from "@solidjs/router";
import { daemonStore } from "../lib/daemon_ws";
import { chatHasActiveTurn, chatPreview, chatWasInterrupted, deriveSidebarModel, type ChatBrief } from "../lib/sidebar_model";

interface Props {
  updateAvailable: boolean;
  onUpdate: () => void;
}

export function Sidebar(props: Props) {
  const chats = createMemo(() => (daemonStore.chats() as ChatBrief[]) ?? []);
  const projects = createMemo(() => daemonStore.projects() ?? []);
  const model = createMemo(() => deriveSidebarModel(chats(), projects()));

  return (
    <aside class="h-full bg-white/60 dark:bg-zinc-900/60 backdrop-blur-glass border-r border-zinc-200/60 dark:border-zinc-800/60 flex flex-col">
      <header class="px-4 pt-5 pb-3 flex items-center justify-between">
        <div class="text-sm font-semibold tracking-tightish">Clawix</div>
        <Show when={props.updateAvailable}>
          <button
            class="text-[11px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-700 dark:text-emerald-400"
            onClick={props.onUpdate}
          >
            Update
          </button>
        </Show>
      </header>

      <nav class="px-2 pb-2 space-y-0.5">
        <div class="px-3 pb-1 text-[11px] uppercase tracking-tighter2 text-zinc-400">
          Workspace
        </div>
        <A
          href="/"
          end
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          New chat
        </A>
        <A
          href="/all-chats"
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          All Chats
        </A>
        <A
          href="/pinned"
          class="flex items-center justify-between gap-2 px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          <span>Pinned</span>
          <span class="text-xs text-zinc-500">{model().pinned.length}</span>
        </A>
        <A
          href="/projects"
          class="flex items-center justify-between gap-2 px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          <span>Projects</span>
          <span class="text-xs text-zinc-500">{model().projects.length}</span>
        </A>
      </nav>

      <div class="flex-1 overflow-y-auto px-2 space-y-0.5">
        <Show when={model().pinned.length > 0}>
          <div class="px-3 pt-2 pb-1 text-[11px] uppercase tracking-tighter2 text-zinc-400">
            Pinned
          </div>
        </Show>
        <For each={model().pinned}>
          {(chat) => (
            <ChatLink chat={chat} />
          )}
        </For>
        <Show when={model().projectless.length > 0}>
          <div class="px-3 pt-2 pb-1 text-[11px] uppercase tracking-tighter2 text-zinc-400">
            Chats
          </div>
        </Show>
        <For each={model().projectless}>
          {(chat) => (
            <ChatLink chat={chat} />
          )}
        </For>
        <Show when={model().projects.length > 0}>
          <div class="px-3 pt-2 pb-1 text-[11px] uppercase tracking-tighter2 text-zinc-400">
            Projects
          </div>
        </Show>
        <For each={model().projects}>
          {(project) => (
            <A
              href={`/projects/${encodeURIComponent(project.id)}`}
              class="flex items-center justify-between gap-2 px-3 py-2 text-sm rounded-lg row-hover"
              activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
            >
              <span class="truncate">{project.name}</span>
              <span class="text-xs text-zinc-500">{project.chats.length}</span>
            </A>
          )}
        </For>
      </div>

      <footer class="px-2 pb-3 pt-2 border-t border-zinc-200/60 dark:border-zinc-800/60 space-y-0.5">
        <div class="px-3 pb-1 text-[11px] uppercase tracking-tighter2 text-zinc-400">
          System
        </div>
        <A
          href="/archived"
          class="flex items-center justify-between gap-2 px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          <span>Archived</span>
          <span class="text-xs text-zinc-500">{model().archived.length}</span>
        </A>
        <A
          href="/pairing"
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          Pair iPhone
        </A>
        <A
          href="/vault"
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          Vault
        </A>
        <A
          href="/settings"
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          Settings
        </A>
        <A
          href="/about"
          class="block px-3 py-2 text-sm rounded-lg row-hover"
          activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
        >
          About
        </A>
      </footer>
    </aside>
  );
}

function ChatLink(props: { chat: ChatBrief }) {
  return (
    <A
      href={`/chats/${props.chat.id}`}
      class="block rounded-lg px-3 py-2 row-hover"
      activeClass="bg-zinc-100/70 dark:bg-zinc-800/40"
    >
      <div class="flex items-center gap-2">
        <span class="min-w-0 flex-1 truncate text-sm">{props.chat.title || "Untitled"}</span>
        <Show when={chatHasActiveTurn(props.chat)}>
          <span class="h-1.5 w-1.5 rounded-full bg-blue-400 animate-pulse" />
        </Show>
        <Show when={chatWasInterrupted(props.chat)}>
          <span class="text-[10px] text-red-500">Paused</span>
        </Show>
      </div>
      <Show when={chatPreview(props.chat)}>
        {(preview) => <div class="mt-0.5 truncate text-xs text-zinc-500">{preview()}</div>}
      </Show>
    </A>
  );
}
