import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { createSignal, onCleanup, onMount } from "solid-js";
import { appendMessage, applyStreamingMessage, editPromptMessage, prependMessagesPage, updateSessionFlags, updateSessionTitle, upsertSession } from "./bridge_state_model";

export interface BridgeFrame {
  schemaVersion: number;
  type: string;
  [k: string]: unknown;
}

const [chats, setChats] = createSignal<unknown[]>([]);
const [projects, setProjects] = createSignal<unknown[]>([]);
const [activeSessionId, setActiveSessionId] = createSignal<string | null>(null);
const [streamingMessages, setStreamingMessages] = createSignal<Record<string, unknown>>({});
const [hasMoreMessages, setHasMoreMessages] = createSignal<Record<string, boolean>>({});
const [fileSnapshots, setFileSnapshots] = createSignal<Record<string, unknown>>({});
const [generatedImages, setGeneratedImages] = createSignal<Record<string, unknown>>({});
const [audioById, setAudioById] = createSignal<Record<string, unknown>>({});
const [rateLimits, setRateLimits] = createSignal<unknown | null>(null);
const [rateLimitsByLimitId, setRateLimitsByLimitId] = createSignal<Record<string, unknown>>({});
const [bridgeState, setBridgeState] = createSignal<string>("booting");

export const daemonStore = {
  chats,
  projects,
  activeSessionId,
  setActiveSessionId,
  streamingMessages,
  hasMoreMessages,
  fileSnapshots,
  generatedImages,
  audioById,
  rateLimits,
  rateLimitsByLimitId,
  bridgeState,
  send: (body: BridgeFrame["body"]) => invoke("send_intent", { body })
};

export function useDaemonStream(): void {
  onMount(async () => {
    try {
      const unlisten = await listen<BridgeFrame[]>("bridge:frames", (event) => {
        for (const frame of event.payload) {
          switch (frame.type) {
            case "authOk":
              void requestRateLimits();
              break;
            case "sessionsSnapshot":
              setChats((frame.sessions as unknown[]) ?? []);
              break;
            case "sessionUpdated":
              setChats((prev) => upsertSession(prev, frame.session));
              break;
            case "projectsSnapshot":
              setProjects((frame.projects as unknown[]) ?? []);
              break;
            case "messagesSnapshot":
              setStreamingMessages((prev) => ({
                ...prev,
                [frame.sessionId as string]: frame.messages
              }));
              if (typeof frame.sessionId === "string" && typeof frame.hasMore === "boolean") {
                setHasMoreMessages((prev) => ({ ...prev, [frame.sessionId as string]: frame.hasMore as boolean }));
              }
              break;
            case "messagesPage":
              setStreamingMessages((prev) => prependMessagesPage(prev, frame.sessionId, frame.messages));
              if (typeof frame.sessionId === "string" && typeof frame.hasMore === "boolean") {
                setHasMoreMessages((prev) => ({ ...prev, [frame.sessionId as string]: frame.hasMore as boolean }));
              }
              break;
            case "messageAppended":
              setStreamingMessages((prev) => appendMessage(prev, frame.sessionId, frame.message));
              break;
            case "messageStreaming":
              setStreamingMessages((prev) => applyStreamingMessage(prev, frame));
              break;
            case "fileSnapshot":
              if (typeof frame.path === "string") {
                setFileSnapshots((prev) => ({
                  ...prev,
                  [frame.path as string]: {
                    content: frame.content,
                    isMarkdown: frame.isMarkdown,
                    error: frame.error
                  }
                }));
              }
              break;
            case "generatedImageSnapshot":
              if (typeof frame.path === "string") {
                setGeneratedImages((prev) => ({
                  ...prev,
                  [frame.path as string]: {
                    dataBase64: frame.dataBase64,
                    mimeType: frame.mimeType,
                    errorMessage: frame.errorMessage
                  }
                }));
              }
              break;
            case "audioSnapshot":
              if (typeof frame.audioId === "string") {
                setAudioById((prev) => ({
                  ...prev,
                  [frame.audioId as string]: frame.audioBase64
                    ? { mimeType: frame.mimeType ?? "audio/mp4", base64: frame.audioBase64 }
                    : { error: frame.errorMessage ?? "Audio no longer available" }
                }));
              }
              break;
            case "rateLimitsSnapshot":
            case "rateLimitsUpdated":
              setRateLimits(frame.rateLimits ?? null);
              setRateLimitsByLimitId(isRecord(frame.rateLimitsByLimitId) ? frame.rateLimitsByLimitId : {});
              break;
            case "bridgeState":
              setBridgeState((frame.state as string) ?? "booting");
              break;
            default:
              break;
          }
        }
      });
      onCleanup(() => unlisten());
    } catch (_) {
      setBridgeState("preview");
    }
  });
}

export async function loadChats(): Promise<void> {
  try {
    const initial = await invoke<unknown[]>("get_chats");
    setChats(initial);
  } catch (_) {
    setChats([]);
  }
}

export async function loadProjects(): Promise<void> {
  try {
    const initial = await invoke<unknown[]>("get_projects");
    setProjects(initial);
  } catch (_) {
    setProjects([]);
  }
}

export async function openSession(sessionId: string): Promise<void> {
  try {
    await invoke("open_session", { sessionId });
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function loadOlderMessages(sessionId: string, beforeMessageId: string): Promise<void> {
  try {
    await invoke("load_older_messages", { sessionId, beforeMessageId });
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function setPinned(sessionId: string, pinned: boolean): Promise<void> {
  setChats((prev) => updateSessionFlags(prev, sessionId, { isPinned: pinned, pinned }));
  try {
    await invoke(pinned ? "pin_session" : "unpin_session", { sessionId });
  } catch (_) {
    setChats((prev) => updateSessionFlags(prev, sessionId, { isPinned: !pinned, pinned: !pinned }));
  }
}

export async function setArchived(sessionId: string, archived: boolean): Promise<void> {
  setChats((prev) => updateSessionFlags(prev, sessionId, { isArchived: archived, archived }));
  try {
    await invoke(archived ? "archive_session" : "unarchive_session", { sessionId });
  } catch (_) {
    setChats((prev) => updateSessionFlags(prev, sessionId, { isArchived: !archived, archived: !archived }));
  }
}

export async function renameSession(sessionId: string, title: string): Promise<void> {
  const trimmed = title.trim();
  if (!trimmed) return;

  const previous = titleForSession(chats(), sessionId);
  setChats((prev) => updateSessionTitle(prev, sessionId, trimmed));
  try {
    await invoke("rename_session", { sessionId, title: trimmed });
  } catch (_) {
    if (previous) setChats((prev) => updateSessionTitle(prev, sessionId, previous));
  }
}

export async function editPrompt(sessionId: string, messageId: string, text: string): Promise<void> {
  const trimmed = text.trim();
  if (!trimmed) return;

  const previous = streamingMessages()[sessionId];
  setStreamingMessages((prev) => editPromptMessage(prev, sessionId, messageId, trimmed));
  try {
    await invoke("edit_prompt", { sessionId, messageId, text: trimmed });
  } catch (_) {
    setStreamingMessages((prev) => ({ ...prev, [sessionId]: previous }));
  }
}

export async function readFile(path: string): Promise<void> {
  try {
    await invoke("read_file", { path });
  } catch (_) {
    setFileSnapshots((prev) => ({ ...prev, [path]: { error: "File preview unavailable." } }));
  }
}

export async function requestGeneratedImage(path: string): Promise<void> {
  try {
    await invoke("request_generated_image", { path });
  } catch (_) {
    setGeneratedImages((prev) => ({ ...prev, [path]: { errorMessage: "Image preview unavailable." } }));
  }
}

export async function requestAudio(audioId: string): Promise<void> {
  try {
    await invoke("request_audio", { audioId });
  } catch (_) {
    setAudioById((prev) => ({ ...prev, [audioId]: { error: "Audio unavailable." } }));
  }
}

export async function requestRateLimits(): Promise<void> {
  try {
    await invoke("request_rate_limits");
  } catch (_) {
    setRateLimits(null);
  }
}

export async function sendMessage(text: string, sessionId?: string): Promise<void> {
  await invoke("send_message", { args: { sessionId, text } });
}

function titleForSession(sessions: unknown[], sessionId: string): string | null {
  const match = sessions.find((session) => {
    return typeof session === "object" && session !== null && !Array.isArray(session) && "id" in session && session.id === sessionId;
  });
  return typeof match === "object" && match !== null && "title" in match && typeof match.title === "string" ? match.title : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
