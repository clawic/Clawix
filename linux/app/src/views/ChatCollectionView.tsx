import { A, useLocation } from "@solidjs/router";
import { For, Show, createMemo, onMount } from "solid-js";
import { daemonStore, loadChats, loadProjects } from "../lib/daemon_ws";
import { collectionForPath, type ChatBrief } from "../lib/sidebar_model";

export default function ChatCollectionView() {
  const location = useLocation();

  onMount(() => {
    void loadChats();
    void loadProjects();
  });

  const collection = createMemo(() =>
    collectionForPath((daemonStore.chats() as ChatBrief[]) ?? [], location.pathname, daemonStore.projects())
  );

  return (
    <section class="h-full overflow-auto">
      <div class="max-w-3xl mx-auto px-8 py-8 space-y-5">
        <header class="flex items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold tracking-tightish">{collection().title}</h1>
            <p class="text-sm text-zinc-500 mt-1">{collectionSubtitle(collection().kind)}</p>
          </div>
          <A
            href="/"
            class="px-3 py-1.5 rounded-lg bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900"
          >
            New chat
          </A>
        </header>

        <Show when={collection().projects.length > 0}>
          <div class="space-y-2">
            <For each={collection().projects}>
              {(project) => (
                <A
                  href={`/projects/${encodeURIComponent(project.id)}`}
                  class="flex items-center justify-between gap-3 rounded-lg px-3 py-2 row-hover"
                >
                  <span class="text-sm font-medium truncate">{project.name}</span>
                  <span class="text-xs text-zinc-500">{project.chats.length}</span>
                </A>
              )}
            </For>
          </div>
        </Show>

        <Show when={collection().chats.length > 0}>
          <div class="space-y-1">
            <For each={collection().chats}>
              {(chat) => (
                <A
                  href={`/chats/${chat.id}`}
                  class="block rounded-lg px-3 py-2 row-hover"
                >
                  <div class="flex items-center justify-between gap-3">
                    <div class="text-sm font-medium truncate">{chat.title || "Untitled"}</div>
                    <Show when={chat.hasActiveTurn}>
                      <span class="text-[11px] px-2 py-0.5 rounded-full bg-zinc-900/10 text-zinc-600 dark:bg-zinc-100/10 dark:text-zinc-300">
                        Running
                      </span>
                    </Show>
                  </div>
                  <Show when={chat.lastMessage}>
                    <div class="text-xs text-zinc-500 truncate mt-0.5">{chat.lastMessage}</div>
                  </Show>
                </A>
              )}
            </For>
          </div>
        </Show>

        <Show when={collection().projects.length === 0 && collection().chats.length === 0}>
          <div class="min-h-[40vh] flex items-center justify-center text-zinc-400 text-sm">
            {collection().empty}
          </div>
        </Show>
      </div>
    </section>
  );
}

function collectionSubtitle(kind: string): string {
  switch (kind) {
    case "pinned":
      return "Fast access to the conversations you keep at the top.";
    case "projects":
      return "Project groups from the bridge session snapshot.";
    case "project":
      return "Conversations attached to this project.";
    case "archived":
      return "Conversations hidden from the main chat list.";
    default:
      return "Every active conversation synced from the bridge daemon.";
  }
}
