import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { createSignal, onCleanup, onMount } from "solid-js";
import { appendMessage, applyStreamingMessage, upsertSession } from "./bridge_state_model";

export interface BridgeFrame {
  schemaVersion: number;
  type: string;
  [k: string]: unknown;
}

const [chats, setChats] = createSignal<unknown[]>([]);
const [projects, setProjects] = createSignal<unknown[]>([]);
const [activeSessionId, setActiveSessionId] = createSignal<string | null>(null);
const [streamingMessages, setStreamingMessages] = createSignal<Record<string, unknown>>({});
const [bridgeState, setBridgeState] = createSignal<string>("booting");

export const daemonStore = {
  chats,
  projects,
  activeSessionId,
  setActiveSessionId,
  streamingMessages,
  bridgeState,
  send: (body: BridgeFrame["body"]) => invoke("send_intent", { body })
};

export function useDaemonStream(): void {
  onMount(async () => {
    try {
      const unlisten = await listen<BridgeFrame[]>("bridge:frames", (event) => {
        for (const frame of event.payload) {
          switch (frame.type) {
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
              break;
            case "messageAppended":
              setStreamingMessages((prev) => appendMessage(prev, frame.sessionId, frame.message));
              break;
            case "messageStreaming":
              setStreamingMessages((prev) => applyStreamingMessage(prev, frame));
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

export async function sendMessage(text: string, sessionId?: string): Promise<void> {
  await invoke("send_message", { args: { sessionId, text } });
}
