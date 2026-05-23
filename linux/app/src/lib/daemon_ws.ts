import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { createSignal, onCleanup, onMount } from "solid-js";
import { applyAudioAttachTranscriptResult, applyAudioDeleteResult, applyAudioGetResult, applyAudioListResult, emptyAudioCatalogState } from "./audio_catalog_model";
import { bridgeDiagnostic } from "./bridge_diagnostics_model";
import { appendMessage, applyStreamingMessage, editPromptMessage, prependMessagesPage, updateSessionFlags, updateSessionTitle, upsertSession } from "./bridge_state_model";

export interface BridgeFrame {
  schemaVersion: number;
  type: string;
  [k: string]: unknown;
}

export interface PairingPayload {
  token: string;
  shortCode: string;
  qrJson: string;
}

const [chats, setChats] = createSignal<unknown[]>([]);
const [projects, setProjects] = createSignal<unknown[]>([]);
const [activeSessionId, setActiveSessionId] = createSignal<string | null>(null);
const [streamingMessages, setStreamingMessages] = createSignal<Record<string, unknown>>({});
const [hasMoreMessages, setHasMoreMessages] = createSignal<Record<string, boolean>>({});
const [fileSnapshots, setFileSnapshots] = createSignal<Record<string, unknown>>({});
const [generatedImages, setGeneratedImages] = createSignal<Record<string, unknown>>({});
const [rolloutAttachments, setRolloutAttachments] = createSignal<Record<string, unknown>>({});
const [audioById, setAudioById] = createSignal<Record<string, unknown>>({});
const [audioRequestIds, setAudioRequestIds] = createSignal<Record<string, string>>({});
const [audioDeleteRequestIds, setAudioDeleteRequestIds] = createSignal<Record<string, string>>({});
const [audioCatalog, setAudioCatalog] = createSignal(emptyAudioCatalogState);
const [transcriptionsByRequestId, setTranscriptionsByRequestId] = createSignal<Record<string, unknown>>({});
const [rateLimits, setRateLimits] = createSignal<unknown | null>(null);
const [rateLimitsByLimitId, setRateLimitsByLimitId] = createSignal<Record<string, unknown>>({});
const [clawJSServiceStatuses, setClawJSServiceStatuses] = createSignal<unknown[]>([]);
const [bridgeState, setBridgeState] = createSignal<string>("booting");
const [bridgeMessage, setBridgeMessage] = createSignal<string | null>(null);
const [hostDisplayName, setHostDisplayName] = createSignal<string | null>(null);
const [pairingPayload, setPairingPayload] = createSignal<PairingPayload | null>(null);

export const daemonStore = {
  chats,
  projects,
  activeSessionId,
  setActiveSessionId,
  streamingMessages,
  hasMoreMessages,
  fileSnapshots,
  generatedImages,
  rolloutAttachments,
  audioById,
  audioCatalog,
  transcriptionsByRequestId,
  rateLimits,
  rateLimitsByLimitId,
  clawJSServiceStatuses,
  bridgeState,
  bridgeMessage,
  hostDisplayName,
  pairingPayload,
  send: (body: BridgeFrame["body"]) => invoke("send_intent", { body })
};

export function useDaemonStream(): void {
  onMount(async () => {
    try {
      const unlisten = await listen<BridgeFrame[]>("bridge:frames", (event) => {
        for (const frame of event.payload) {
          const diagnostic = bridgeDiagnostic(frame);
          if (diagnostic) {
            setBridgeState(diagnostic.state);
            setBridgeMessage(diagnostic.message);
            continue;
          }
          switch (frame.type) {
            case "authOk":
              setBridgeMessage(null);
              setHostDisplayName(typeof frame.hostDisplayName === "string" ? frame.hostDisplayName : null);
              void requestRateLimits();
              void requestClawJSServiceStatuses();
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
            case "pairingPayload":
              if (isPairingPayload(frame)) {
                setPairingPayload({ token: frame.token, shortCode: frame.shortCode, qrJson: frame.qrJson });
              }
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
            case "rolloutAttachmentSnapshot":
              if (typeof frame.attachmentId === "string") {
                setRolloutAttachments((prev) => ({
                  ...prev,
                  [frame.attachmentId as string]: {
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
            case "audioBytesResult": {
              const audioId = typeof frame.requestId === "string" ? audioRequestIds()[frame.requestId] : null;
              if (audioId) {
                setAudioById((prev) => ({
                  ...prev,
                  [audioId]: frame.audioBase64
                    ? { mimeType: frame.mimeType ?? "audio/mp4", base64: frame.audioBase64, durationMs: frame.durationMs }
                    : { error: frame.errorMessage ?? "Audio no longer available" }
                }));
                setAudioRequestIds((prev) => {
                  const next = { ...prev };
                  delete next[frame.requestId as string];
                  return next;
                });
              }
              break;
            }
            case "audioGetResult":
            case "audioRegisterResult":
              setAudioCatalog((prev) => applyAudioGetResult(prev, frame));
              break;
            case "audioAttachTranscriptResult":
              setAudioCatalog((prev) => applyAudioAttachTranscriptResult(prev, frame));
              break;
            case "audioListResult":
              setAudioCatalog((prev) => applyAudioListResult(prev, frame));
              break;
            case "audioDeleteResult":
              setAudioCatalog((prev) => applyAudioDeleteResult(prev, frame, audioDeleteRequestIds()));
              if (typeof frame.requestId === "string") {
                setAudioDeleteRequestIds((prev) => {
                  const next = { ...prev };
                  delete next[frame.requestId as string];
                  return next;
                });
              }
              break;
            case "transcriptionResult":
              if (typeof frame.requestId === "string") {
                setTranscriptionsByRequestId((prev) => ({
                  ...prev,
                  [frame.requestId as string]: {
                    text: frame.text,
                    errorMessage: frame.errorMessage
                  }
                }));
              }
              break;
            case "rateLimitsSnapshot":
            case "rateLimitsUpdated":
              setRateLimits(frame.rateLimits ?? null);
              setRateLimitsByLimitId(isRecord(frame.rateLimitsByLimitId) ? frame.rateLimitsByLimitId : {});
              break;
            case "clawJSServiceStatusesSnapshot":
              setClawJSServiceStatuses(Array.isArray(frame.services) ? frame.services : []);
              break;
            case "clawJSServiceStatusUpdated":
              setClawJSServiceStatuses((prev) => upsertServiceStatus(prev, frame.service));
              break;
            case "bridgeState":
              setBridgeState((frame.state as string) ?? "booting");
              setBridgeMessage(typeof frame.message === "string" ? frame.message : null);
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

export async function interruptTurn(sessionId: string): Promise<void> {
  try {
    await invoke("interrupt_turn", { sessionId });
  } catch (_) {
    /* preview mode or bridge unavailable */
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

export async function requestRolloutAttachment(attachmentId: string): Promise<void> {
  try {
    await invoke("request_rollout_attachment", { attachmentId });
  } catch (_) {
    setRolloutAttachments((prev) => ({ ...prev, [attachmentId]: { errorMessage: "Attachment unavailable." } }));
  }
}

export async function requestAudio(audioId: string): Promise<void> {
  try {
    const requestId = await invoke<string>("request_audio", { audioId });
    if (requestId) {
      setAudioRequestIds((prev) => ({ ...prev, [requestId]: audioId }));
    }
  } catch (_) {
    setAudioById((prev) => ({ ...prev, [audioId]: { error: "Audio unavailable." } }));
  }
}

export async function requestAudioAsset(audioId: string, appId = "clawix"): Promise<void> {
  try {
    await invoke<string>("audio_get", { audioId, appId });
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function registerAudioAsset(request: Record<string, unknown>): Promise<void> {
  try {
    await invoke<string>("audio_register", { request });
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function attachAudioTranscript(audioId: string, transcript: Record<string, unknown>): Promise<void> {
  try {
    await invoke<string>("audio_attach_transcript", { audioId, transcript });
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function requestAudioCatalog(filter: Record<string, unknown> = { appId: "clawix", limit: 50, offset: 0 }): Promise<void> {
  try {
    await invoke<string>("audio_list", { filter });
  } catch (_) {
    setAudioCatalog(emptyAudioCatalogState);
  }
}

export async function deleteAudioAsset(audioId: string, appId = "clawix"): Promise<void> {
  try {
    const requestId = await invoke<string>("audio_delete", { audioId, appId });
    if (requestId) {
      setAudioDeleteRequestIds((prev) => ({ ...prev, [requestId]: audioId }));
    }
  } catch (_) {
    /* preview mode or bridge unavailable */
  }
}

export async function transcribeAudio(audioBase64: string, mimeType: string, language?: string): Promise<string | null> {
  try {
    return await invoke<string>("transcribe_audio", { audioBase64, mimeType, language });
  } catch (_) {
    return null;
  }
}

export async function requestRateLimits(): Promise<void> {
  try {
    await invoke("request_rate_limits");
  } catch (_) {
    setRateLimits(null);
  }
}

export async function requestClawJSServiceStatuses(): Promise<void> {
  try {
    await invoke("request_clawjs_service_statuses");
  } catch (_) {
    setClawJSServiceStatuses([]);
  }
}

export async function requestPairingPayload(): Promise<void> {
  try {
    setPairingPayload(await invoke<PairingPayload>("start_pairing"));
  } catch (_) {
    setPairingPayload(null);
  }
}

export async function sendMessage(text: string, sessionId?: string, attachments: unknown[] = []): Promise<void> {
  await invoke("send_message", { args: { sessionId, text, attachments } });
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

function isPairingPayload(frame: BridgeFrame): frame is BridgeFrame & PairingPayload {
  return typeof frame.token === "string" && typeof frame.shortCode === "string" && typeof frame.qrJson === "string";
}

function upsertServiceStatus(services: unknown[], service: unknown): unknown[] {
  if (!isRecord(service) || typeof service.id !== "string") return services;
  const index = services.findIndex((item) => isRecord(item) && item.id === service.id);
  if (index < 0) return [...services, service];

  const next = services.slice();
  next[index] = service;
  return next;
}
