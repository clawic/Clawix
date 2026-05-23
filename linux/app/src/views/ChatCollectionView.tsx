import { A, useLocation } from "@solidjs/router";
import { For, Show, createMemo, createSignal, onMount } from "solid-js";
import { daemonStore, loadChats, loadProjects, renameSession, setArchived, setPinned } from "../lib/daemon_ws";
import { chatHasActiveTurn, collectionForPath, type ChatBrief } from "../lib/sidebar_model";

export default function ChatCollectionView() {
  const location = useLocation();
  const [renamingId, setRenamingId] = createSignal<string | null>(null);
  const [renameDraft, setRenameDraft] = createSignal("");

  onMount(() => {
    void loadChats();
    void loadProjects();
  });

  const collection = createMemo(() =>
    collectionForPath((daemonStore.chats() as ChatBrief[]) ?? [], location.pathname, daemonStore.projects())
  );

  const startRename = (chat: ChatBrief) => {
    setRenamingId(chat.id);
    setRenameDraft(chatTitle(chat));
  };

  const submitRename = async (sessionId: string) => {
    const title = renameDraft().trim();
    if (!title) return;
    await renameSession(sessionId, title);
    setRenamingId(null);
    setRenameDraft("");
  };

  const cancelRename = () => {
    setRenamingId(null);
    setRenameDraft("");
  };

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
                <div class="group flex items-center gap-2 rounded-lg px-3 py-2 row-hover">
                  <div class="min-w-0 flex-1">
                    <Show
                      when={renamingId() === chat.id}
                      fallback={
                        <A href={`/chats/${chat.id}`}>
                          <div class="flex items-center justify-between gap-3">
                            <div class="text-sm font-medium truncate">{chatTitle(chat)}</div>
                            <Show when={chatHasActiveTurn(chat)}>
                              <span class="text-[11px] px-2 py-0.5 rounded-full bg-zinc-900/10 text-zinc-600 dark:bg-zinc-100/10 dark:text-zinc-300">
                                Running
                              </span>
                            </Show>
                          </div>
                          <Show when={chat.lastMessage}>
                            <div class="text-xs text-zinc-500 truncate mt-0.5">{chat.lastMessage}</div>
                          </Show>
                        </A>
                      }
                    >
                      <div class="flex items-center gap-2">
                        <input
                          class="min-w-0 flex-1 rounded-md border border-zinc-300 bg-white px-2 py-1 text-sm outline-none focus:border-zinc-500 dark:border-zinc-700 dark:bg-zinc-900"
                          value={renameDraft()}
                          onInput={(event) => setRenameDraft(event.currentTarget.value)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter") void submitRename(chat.id);
                            if (event.key === "Escape") cancelRename();
                          }}
                          autofocus
                        />
                        <button
                          type="button"
                          class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                          onClick={() => void submitRename(chat.id)}
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                          onClick={cancelRename}
                        >
                          Cancel
                        </button>
                      </div>
                    </Show>
                  </div>
                  <div class="flex shrink-0 items-center gap-1 opacity-0 group-hover:opacity-100 focus-within:opacity-100">
                    <button
                      type="button"
                      class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                      onClick={() => startRename(chat)}
                    >
                      Rename
                    </button>
                    <button
                      type="button"
                      class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                      onClick={() => void setPinned(chat.id, !isPinned(chat))}
                    >
                      {isPinned(chat) ? "Unpin" : "Pin"}
                    </button>
                    <button
                      type="button"
                      class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                      onClick={() => void setArchived(chat.id, !isArchived(chat))}
                    >
                      {isArchived(chat) ? "Restore" : "Archive"}
                    </button>
                  </div>
                </div>
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

function chatTitle(chat: ChatBrief): string {
  return chat.title || "Untitled";
}

function isPinned(chat: ChatBrief): boolean {
  return chat.isPinned === true || chat.pinned === true;
}

function isArchived(chat: ChatBrief): boolean {
  return chat.isArchived === true || chat.archived === true;
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
