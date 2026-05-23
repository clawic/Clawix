import { For, Show, createEffect, createMemo, createSignal, onCleanup, onMount } from "solid-js";
import { useParams } from "@solidjs/router";
import { createVirtualizer } from "@tanstack/solid-virtual";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { daemonStore, editPrompt, interruptTurn, loadChats, loadOlderMessages, openSession, readFile, requestAudio, requestGeneratedImage, sendMessage } from "../lib/daemon_ws";
import { attachmentKindFromMime, filePathsForMessage, formatDurationMs, generatedImagePathsForMessage, mergeDictationText } from "../lib/chat_media_model";
import { chatHasActiveTurn, type ChatBrief } from "../lib/sidebar_model";
import { renderCachedMarkdown } from "../lib/markdown";

interface WorkItem {
  paths?: string[];
  generatedImagePath?: string;
}

interface TimelineEntry {
  type: string;
  items?: WorkItem[];
}

interface Message {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  timeline?: TimelineEntry[];
  attachments?: Attachment[];
  audioRef?: AudioRef;
  reasoningText?: string;
  streamingFinished?: boolean;
}

interface Attachment {
  id: string;
  kind: "image" | "audio";
  mimeType: string;
  filename?: string;
  dataBase64?: string;
}

interface ComposerAttachment extends Attachment {
  byteSize?: number;
}

interface AudioRef {
  id: string;
  mimeType: string;
  durationMs: number;
}

interface AudioSnapshot {
  mimeType?: string;
  base64?: string;
  error?: string;
}

interface FileSnapshot {
  content?: string;
  isMarkdown?: boolean;
  error?: string;
}

interface GeneratedImageSnapshot {
  dataBase64?: string;
  mimeType?: string;
  errorMessage?: string;
}

export default function ChatView() {
  const params = useParams<{ id?: string }>();
  const [composer, setComposer] = createSignal("");
  const [attachments, setAttachments] = createSignal<ComposerAttachment[]>([]);
  const [dictating, setDictating] = createSignal(false);
  const [editingMessageId, setEditingMessageId] = createSignal<string | null>(null);
  const [editDraft, setEditDraft] = createSignal("");
  const [fileViewerPath, setFileViewerPath] = createSignal<string | null>(null);
  const [imageViewerPath, setImageViewerPath] = createSignal<string | null>(null);
  const [scrollEl, setScrollEl] = createSignal<HTMLDivElement | undefined>();

  onMount(() => {
    void loadChats();
    let unlistenPartial: UnlistenFn | undefined;
    let unlistenStopped: UnlistenFn | undefined;
    void listen<string>("dictation:partial", (event) => {
      setComposer((prev) => mergeDictationText(prev, event.payload));
    }).then((unlisten) => {
      unlistenPartial = unlisten;
    });
    void listen("dictation:stopped", () => {
      setDictating(false);
    }).then((unlisten) => {
      unlistenStopped = unlisten;
    });
    onCleanup(() => {
      unlistenPartial?.();
      unlistenStopped?.();
    });
  });

  createEffect(() => {
    const id = params.id;
    daemonStore.setActiveSessionId(id ?? null);
    if (id) void openSession(id);
  });

  const activeId = createMemo(() => params.id ?? daemonStore.activeSessionId() ?? "");
  const messages = createMemo<Message[]>(() => {
    const id = activeId();
    if (!id) return [];
    return ((daemonStore.streamingMessages()[id] as Message[]) ?? []).filter(
      (m) => m && (m.role === "user" || m.role === "assistant")
    );
  });
  const hasMore = createMemo(() => {
    const id = activeId();
    return id ? daemonStore.hasMoreMessages()[id] === true : false;
  });
  const activeChat = createMemo(() => {
    const id = activeId();
    return id ? (daemonStore.chats() as ChatBrief[]).find((chat) => chat.id === id) : undefined;
  });
  const hasActiveTurn = createMemo(() => chatHasActiveTurn(activeChat()));
  const oldestMessageId = createMemo(() => messages()[0]?.id ?? "");
  const activeFileSnapshot = createMemo(() => {
    const path = fileViewerPath();
    if (!path) return null;
    return daemonStore.fileSnapshots()[path] as FileSnapshot | undefined;
  });
  const activeImageSnapshot = createMemo(() => {
    const path = imageViewerPath();
    if (!path) return null;
    return daemonStore.generatedImages()[path] as GeneratedImageSnapshot | undefined;
  });

  const virtualizer = createMemo(() =>
    createVirtualizer({
      count: messages().length,
      getScrollElement: () => scrollEl() ?? null,
      estimateSize: () => 96,
      overscan: 8
    })
  );

  async function onSubmit(e: SubmitEvent) {
    e.preventDefault();
    const text = composer().trim();
    if (!text && attachments().length === 0) return;
    setComposer("");
    const queuedAttachments = attachments();
    setAttachments([]);
    await sendMessage(text, params.id, queuedAttachments);
  }

  async function onInterrupt() {
    const id = activeId();
    if (id) await interruptTurn(id);
  }

  function startEdit(message: Message) {
    setEditingMessageId(message.id);
    setEditDraft(message.content);
  }

  function cancelEdit() {
    setEditingMessageId(null);
    setEditDraft("");
  }

  async function submitEdit(message: Message) {
    const sessionId = activeId();
    const text = editDraft().trim();
    if (!sessionId || !text) return;
    await editPrompt(sessionId, message.id, text);
    cancelEdit();
  }

  function openFile(path: string) {
    setFileViewerPath(path);
    if (!daemonStore.fileSnapshots()[path]) void readFile(path);
  }

  function openGeneratedImage(path: string) {
    setImageViewerPath(path);
    if (!daemonStore.generatedImages()[path]) void requestGeneratedImage(path);
  }

  async function attachFiles(fileList: FileList | null) {
    if (!fileList) return;
    const next = await Promise.all(Array.from(fileList).map(fileToAttachment));
    setAttachments((prev) => [...prev, ...next]);
  }

  function removeAttachment(id: string) {
    setAttachments((prev) => prev.filter((attachment) => attachment.id !== id));
  }

  async function toggleDictation() {
    if (dictating()) {
      await invoke("stop_dictation");
      setDictating(false);
      return;
    }

    await invoke("start_dictation", { device: null });
    setDictating(true);
  }

  return (
    <section class="flex flex-col h-full">
      <header class="px-6 py-3 border-b border-zinc-200/60 dark:border-zinc-800/60 flex items-center gap-3">
        <h1 class="text-sm font-medium tracking-tightish">
          {params.id ? "Conversation" : "New chat"}
        </h1>
        <span class="text-xs text-zinc-500">{daemonStore.bridgeState()}</span>
      </header>

      <div ref={(el) => setScrollEl(el)} class="flex-1 overflow-auto px-6 py-4">
        <Show when={hasMore() && oldestMessageId()}>
          <div class="max-w-2xl mx-auto pb-3 text-center">
            <button
              type="button"
              class="px-3 py-1.5 rounded-lg bg-zinc-100/70 dark:bg-zinc-800/40 text-xs text-zinc-600 dark:text-zinc-300 row-hover"
              onClick={() => void loadOlderMessages(activeId(), oldestMessageId())}
            >
              Load earlier messages
            </button>
          </div>
        </Show>
        <Show when={messages().length === 0}>
          <div class="h-full flex items-center justify-center text-zinc-400 text-sm">
            Start a conversation.
          </div>
        </Show>
        <div
          style={{
            height: `${virtualizer().getTotalSize()}px`,
            position: "relative",
            width: "100%"
          }}
        >
          <For each={virtualizer().getVirtualItems()}>
            {(virtualRow) => {
              const msg = messages()[virtualRow.index];
              return (
                <article
                  data-role={msg.role}
                  ref={(el) => virtualizer().measureElement(el)}
                  data-index={virtualRow.index}
                  class="absolute left-0 right-0"
                  style={{ transform: `translateY(${virtualRow.start}px)` }}
                >
                  <div
                    class="max-w-2xl mx-auto py-3"
                    classList={{
                      "text-zinc-900 dark:text-zinc-100": true
                    }}
                  >
                    <Show when={msg.role === "user"}>
                      <div class="mb-1 flex items-center justify-between gap-3">
                        <div class="text-xs uppercase tracking-tighter2 text-zinc-500">
                          You
                        </div>
                        <Show when={editingMessageId() !== msg.id}>
                          <button
                            type="button"
                            class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                            onClick={() => startEdit(msg)}
                          >
                            Edit
                          </button>
                        </Show>
                      </div>
                    </Show>
                    <Show
                      when={editingMessageId() === msg.id}
                      fallback={
                        <div
                          class="prose prose-sm dark:prose-invert max-w-none leading-relaxed"
                          innerHTML={renderCachedMarkdown(msg.content)}
                        />
                      }
                    >
                      <div class="space-y-2">
                        <textarea
                          class="w-full resize-y rounded-xl bg-zinc-100/70 dark:bg-zinc-800/40 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-zinc-300 dark:focus:ring-zinc-700 min-h-[96px]"
                          value={editDraft()}
                          onInput={(event) => setEditDraft(event.currentTarget.value)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter" && !event.shiftKey) {
                              event.preventDefault();
                              void submitEdit(msg);
                            }
                            if (event.key === "Escape") cancelEdit();
                          }}
                        />
                        <div class="flex justify-end gap-2">
                          <button
                            type="button"
                            class="px-3 py-1.5 rounded-lg text-xs text-zinc-500 row-hover"
                            onClick={cancelEdit}
                          >
                            Cancel
                          </button>
                          <button
                            type="button"
                            class="px-3 py-1.5 rounded-lg bg-zinc-900 text-white text-xs font-medium dark:bg-zinc-100 dark:text-zinc-900 disabled:opacity-40"
                            disabled={!editDraft().trim()}
                            onClick={() => void submitEdit(msg)}
                          >
                            Save
                          </button>
                        </div>
                      </div>
                    </Show>
                    <Show when={msg.streamingFinished === false}>
                      <div class="mt-1 inline-block w-1.5 h-4 bg-zinc-400 dark:bg-zinc-500 animate-pulse" />
                    </Show>
                    <Show when={msg.audioRef}>
                      {(audioRef) => (
                        <AudioBubble
                          audioRef={audioRef()}
                          snapshot={daemonStore.audioById()[audioRef().id] as AudioSnapshot | undefined}
                        />
                      )}
                    </Show>
                    <Show when={(msg.attachments ?? []).length > 0}>
                      <AttachmentStrip attachments={msg.attachments ?? []} />
                    </Show>
                    <Show when={filePaths(msg).length > 0}>
                      <div class="mt-3 flex flex-wrap gap-2">
                        <For each={filePaths(msg)}>
                          {(path) => (
                            <button
                              type="button"
                              class="max-w-full truncate rounded-lg bg-zinc-100/70 px-2.5 py-1 text-xs font-mono text-zinc-600 row-hover dark:bg-zinc-800/40 dark:text-zinc-300"
                              onClick={() => openFile(path)}
                              title={path}
                            >
                              {fileName(path)}
                            </button>
                          )}
                        </For>
                      </div>
                    </Show>
                    <Show when={generatedImagePaths(msg).length > 0}>
                      <div class="mt-3 grid max-w-md grid-cols-2 gap-2">
                        <For each={generatedImagePaths(msg)}>
                          {(path) => (
                            <GeneratedImageTile
                              path={path}
                              snapshot={daemonStore.generatedImages()[path] as GeneratedImageSnapshot | undefined}
                              onOpen={() => openGeneratedImage(path)}
                            />
                          )}
                        </For>
                      </div>
                    </Show>
                  </div>
                </article>
              );
            }}
          </For>
        </div>
      </div>

      <Show when={fileViewerPath()}>
        {(path) => (
          <div class="fixed inset-0 z-50 flex items-end justify-center bg-black/30 px-4 py-4 sm:items-center">
            <div class="w-full max-w-3xl max-h-[80vh] overflow-hidden rounded-xl bg-white shadow-xl dark:bg-zinc-950">
              <header class="flex items-start justify-between gap-3 border-b border-zinc-200/60 px-4 py-3 dark:border-zinc-800/60">
                <div class="min-w-0">
                  <div class="truncate text-sm font-medium">{fileName(path())}</div>
                  <div class="truncate text-xs text-zinc-500">{path()}</div>
                </div>
                <button
                  type="button"
                  class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                  onClick={() => setFileViewerPath(null)}
                >
                  Close
                </button>
              </header>
              <div class="max-h-[64vh] overflow-auto p-4">
                <Show
                  when={activeFileSnapshot()}
                  fallback={<div class="text-sm text-zinc-500">Loading...</div>}
                >
                  {(snapshot) => (
                    <Show
                      when={!snapshot().error}
                      fallback={<div class="text-sm text-red-500">{snapshot().error}</div>}
                    >
                      <Show
                        when={snapshot().isMarkdown}
                        fallback={
                          <pre class="whitespace-pre-wrap break-words text-xs leading-relaxed text-zinc-800 dark:text-zinc-200">
                            {snapshot().content ?? ""}
                          </pre>
                        }
                      >
                        <div
                          class="prose prose-sm dark:prose-invert max-w-none"
                          innerHTML={renderCachedMarkdown(snapshot().content ?? "")}
                        />
                      </Show>
                    </Show>
                  )}
                </Show>
              </div>
            </div>
          </div>
        )}
      </Show>

      <Show when={imageViewerPath()}>
        {(path) => (
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4 py-4">
            <div class="max-h-[90vh] w-full max-w-5xl overflow-hidden rounded-xl bg-white shadow-xl dark:bg-zinc-950">
              <header class="flex items-start justify-between gap-3 border-b border-zinc-200/60 px-4 py-3 dark:border-zinc-800/60">
                <div class="min-w-0">
                  <div class="truncate text-sm font-medium">{fileName(path())}</div>
                  <div class="truncate text-xs text-zinc-500">{path()}</div>
                </div>
                <button
                  type="button"
                  class="px-2 py-1 rounded-md text-xs text-zinc-500 row-hover"
                  onClick={() => setImageViewerPath(null)}
                >
                  Close
                </button>
              </header>
              <div class="flex max-h-[78vh] items-center justify-center overflow-auto bg-zinc-950 p-4">
                <Show
                  when={activeImageSnapshot()}
                  fallback={<div class="text-sm text-zinc-400">Loading...</div>}
                >
                  {(snapshot) => (
                    <Show
                      when={!snapshot().errorMessage && snapshot().dataBase64}
                      fallback={<div class="text-sm text-red-300">{snapshot().errorMessage ?? "Image unavailable."}</div>}
                    >
                      <img
                        class="max-h-[72vh] max-w-full rounded-lg object-contain"
                        src={imageDataUrl(snapshot())}
                        alt={fileName(path())}
                      />
                    </Show>
                  )}
                </Show>
              </div>
            </div>
          </div>
        )}
      </Show>

      <form
        onSubmit={onSubmit}
        class="border-t border-zinc-200/60 dark:border-zinc-800/60 px-6 py-3"
      >
        <div class="max-w-2xl mx-auto space-y-2">
          <Show when={attachments().length > 0}>
            <div class="flex flex-wrap gap-2">
              <For each={attachments()}>
                {(attachment) => (
                  <button
                    type="button"
                    class="rounded-lg bg-zinc-100/70 px-2.5 py-1 text-xs text-zinc-600 row-hover dark:bg-zinc-800/40 dark:text-zinc-300"
                    onClick={() => removeAttachment(attachment.id)}
                    title="Remove attachment"
                  >
                    {attachment.filename ?? attachment.kind}
                  </button>
                )}
              </For>
            </div>
          </Show>
          <div class="flex items-end gap-2">
            <label class="rounded-xl bg-zinc-100/70 px-3 py-2 text-sm text-zinc-600 row-hover dark:bg-zinc-800/40 dark:text-zinc-300">
              Attach
              <input
                type="file"
                class="hidden"
                multiple
                accept="image/*,audio/*"
                onChange={(event) => {
                  void attachFiles(event.currentTarget.files);
                  event.currentTarget.value = "";
                }}
              />
            </label>
            <button
              type="button"
              class="rounded-xl bg-zinc-100/70 px-3 py-2 text-sm text-zinc-600 row-hover dark:bg-zinc-800/40 dark:text-zinc-300"
              classList={{
                "text-red-600 dark:text-red-400": dictating()
              }}
              onClick={() => void toggleDictation()}
            >
              {dictating() ? "Stop mic" : "Mic"}
            </button>
            <textarea
              class="flex-1 resize-none rounded-xl bg-zinc-100/70 dark:bg-zinc-800/40 px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-zinc-300 dark:focus:ring-zinc-700 min-h-[44px] max-h-[160px]"
              placeholder="Message Clawix"
              value={composer()}
              onInput={(e) => setComposer(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  e.currentTarget.form?.requestSubmit();
                }
              }}
            />
            <Show
              when={hasActiveTurn()}
              fallback={
                <button
                  type="submit"
                  class="px-4 py-2 rounded-xl bg-zinc-900 text-white text-sm font-medium dark:bg-zinc-100 dark:text-zinc-900 disabled:opacity-40"
                  disabled={!composer().trim() && attachments().length === 0}
                >
                  Send
                </button>
              }
            >
              <button
                type="button"
                class="px-4 py-2 rounded-xl bg-red-600 text-white text-sm font-medium disabled:opacity-40"
                disabled={!activeId()}
                onClick={() => void onInterrupt()}
              >
                Stop
              </button>
            </Show>
          </div>
        </div>
      </form>
    </section>
  );
}

const filePaths = filePathsForMessage;
const generatedImagePaths = generatedImagePathsForMessage;

function fileName(path: string): string {
  return path.split(/[\\/]/).filter(Boolean).at(-1) ?? path;
}

function imageDataUrl(snapshot: GeneratedImageSnapshot): string {
  return `data:${snapshot.mimeType ?? "image/png"};base64,${snapshot.dataBase64 ?? ""}`;
}

function audioDataUrl(snapshot: AudioSnapshot): string {
  return `data:${snapshot.mimeType ?? "audio/mp4"};base64,${snapshot.base64 ?? ""}`;
}

function attachmentDataUrl(attachment: Attachment): string {
  return `data:${attachment.mimeType};base64,${attachment.dataBase64 ?? ""}`;
}

function AttachmentStrip(props: { attachments: Attachment[] }) {
  return (
    <div class="mt-3 flex flex-wrap gap-2">
      <For each={props.attachments}>
        {(attachment) => (
          <Show
            when={attachment.kind === "image" && attachment.dataBase64}
            fallback={
              <audio
                class="h-9"
                controls
                src={attachment.dataBase64 ? attachmentDataUrl(attachment) : undefined}
              />
            }
          >
            <img
              class="max-h-44 rounded-lg border border-zinc-200 object-contain dark:border-zinc-800"
              src={attachmentDataUrl(attachment)}
              alt={attachment.filename ?? "image"}
            />
          </Show>
        )}
      </For>
    </div>
  );
}

function AudioBubble(props: { audioRef: AudioRef; snapshot?: AudioSnapshot }) {
  createEffect(() => {
    if (!props.snapshot) void requestAudio(props.audioRef.id);
  });

  return (
    <div class="mt-3 max-w-sm rounded-xl bg-zinc-100/70 px-3 py-2 dark:bg-zinc-800/40">
      <div class="mb-2 text-xs text-zinc-500">{formatDurationMs(props.audioRef.durationMs)}</div>
      <Show
        when={props.snapshot?.base64}
        fallback={<div class="text-xs text-zinc-500">{props.snapshot?.error ?? "Loading audio..."}</div>}
      >
        <audio
          class="w-full"
          controls
          src={audioDataUrl(props.snapshot ?? { mimeType: props.audioRef.mimeType })}
        />
      </Show>
    </div>
  );
}

function GeneratedImageTile(props: {
  path: string;
  snapshot?: GeneratedImageSnapshot;
  onOpen: () => void;
}) {
  createEffect(() => {
    if (!props.snapshot) void requestGeneratedImage(props.path);
  });

  return (
    <button
      type="button"
      class="aspect-video overflow-hidden rounded-lg bg-zinc-100 text-left row-hover dark:bg-zinc-800/50"
      onClick={props.onOpen}
      title={props.path}
    >
      <Show
        when={props.snapshot?.dataBase64}
        fallback={
          <div class="flex h-full items-center justify-center px-2 text-center text-xs text-zinc-500">
            {props.snapshot?.errorMessage ?? "Loading image..."}
          </div>
        }
      >
        <img
          class="h-full w-full object-cover"
          src={imageDataUrl(props.snapshot ?? {})}
          alt={fileName(props.path)}
        />
      </Show>
    </button>
  );
}

async function fileToAttachment(file: File): Promise<ComposerAttachment> {
  return {
    id: crypto.randomUUID(),
    kind: attachmentKindFromMime(file.type),
    mimeType: file.type,
    filename: file.name,
    byteSize: file.size,
    dataBase64: await readFileBase64(file)
  };
}

function readFileBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const value = String(reader.result ?? "");
      resolve(value.includes(",") ? value.split(",").at(-1) ?? "" : value);
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}
