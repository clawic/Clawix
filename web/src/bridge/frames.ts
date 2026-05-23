/**
 * Discriminated union of all bridge frame bodies.
 * Mirrors `BridgeBody` in `packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift`.
 *
 * Wire format is FLAT: every frame is a top-level JSON object with
 * `schemaVersion`, `type`, and the payload fields. There is no `payload` envelope.
 */

import { z } from "zod";
import {
  BRIDGE_MAX_FRAME_BYTES,
  BRIDGE_SCHEMA_VERSION,
} from "./frame-base";
import {
  ALLOWED_PAYLOAD_KEYS,
  TOP_LEVEL_FRAME_KEYS,
  type BridgePayloadFrameType,
} from "./frame-payload-keys";
import {
  ZArchiveSession,
  ZAuth,
  ZEditPrompt,
  ZInterruptTurn,
  ZListProjects,
  ZListSessions,
  ZLoadOlderMessages,
  ZNewSession,
  ZOpenSession,
  ZPairingStart,
  ZPinSession,
  ZReadFile,
  ZRenameSession,
  ZRequestAudio,
  ZRequestClawJSServiceStatuses,
  ZRequestGeneratedImage,
  ZRequestRateLimits,
  ZRequestRolloutAttachment,
  ZSendMessage,
  ZTranscribeAudio,
  ZUnarchiveSession,
  ZUnpinSession,
} from "./client-frames";
import {
  ZAudioSnapshot,
  ZAuthFailed,
  ZAuthOk,
  ZBridgeState,
  ZErrorEvent,
  ZFileSnapshot,
  ZGeneratedImageSnapshot,
  ZMessageAppended,
  ZMessageStreaming,
  ZMessagesPage,
  ZMessagesSnapshot,
  ZPairingPayload,
  ZProjectsSnapshot,
  ZRolloutAttachmentSnapshot,
  ZSessionUpdated,
  ZSessionsSnapshot,
  ZTranscriptionResult,
  ZVersionMismatch,
} from "./server-frames";
import {
  ZAudioAttachTranscript,
  ZAudioAttachTranscriptResult,
  ZAudioBytesResult,
  ZAudioDelete,
  ZAudioDeleteResult,
  ZAudioGet,
  ZAudioGetBytes,
  ZAudioGetResult,
  ZAudioList,
  ZAudioListResult,
  ZAudioRegister,
  ZAudioRegisterResult,
} from "./audio-frames";
import {
  ZClawJSServiceStatusesSnapshot,
  ZClawJSServiceStatusUpdated,
  ZRateLimitsSnapshot,
  ZRateLimitsUpdated,
} from "./runtime-frames";

export {
  ZArchiveSession,
  ZAuth,
  ZClientKind,
  ZEditPrompt,
  ZInterruptTurn,
  ZListProjects,
  ZListSessions,
  ZLoadOlderMessages,
  ZNewSession,
  ZOpenSession,
  ZPairingStart,
  ZPinSession,
  ZReadFile,
  ZRenameSession,
  ZRequestAudio,
  ZRequestClawJSServiceStatuses,
  ZRequestGeneratedImage,
  ZRequestRateLimits,
  ZRequestRolloutAttachment,
  ZSendMessage,
  ZTranscribeAudio,
  ZUnarchiveSession,
  ZUnpinSession,
  type ClientKind,
} from "./client-frames";
export {
  ZAudioSnapshot,
  ZAuthFailed,
  ZAuthOk,
  ZBridgeState,
  ZErrorEvent,
  ZFileSnapshot,
  ZGeneratedImageSnapshot,
  ZMessageAppended,
  ZMessageStreaming,
  ZMessagesPage,
  ZMessagesSnapshot,
  ZPairingPayload,
  ZProjectsSnapshot,
  ZRolloutAttachmentSnapshot,
  ZSessionUpdated,
  ZSessionsSnapshot,
  ZTranscriptionResult,
  ZVersionMismatch,
} from "./server-frames";
export {
  BRIDGE_INITIAL_PAGE_LIMIT,
  BRIDGE_MAX_FRAME_BYTES,
  BRIDGE_OLDER_PAGE_LIMIT,
  BRIDGE_SCHEMA_VERSION,
} from "./frame-base";
export {
  ZAudioAttachTranscript,
  ZAudioAttachTranscriptResult,
  ZAudioBytesResult,
  ZAudioDelete,
  ZAudioDeleteResult,
  ZAudioGet,
  ZAudioGetBytes,
  ZAudioGetResult,
  ZAudioList,
  ZAudioListResult,
  ZAudioRegister,
  ZAudioRegisterResult,
} from "./audio-frames";
export {
  ZClawJSServiceStatusesSnapshot,
  ZClawJSServiceStatusUpdated,
  ZRateLimitsPayload,
  ZRateLimitsSnapshot,
  ZRateLimitsUpdated,
} from "./runtime-frames";

/** Full discriminated union covering both directions. */
export const ZBridgeFrame = z.discriminatedUnion("type", [
  ZAuth,
  ZListSessions,
  ZOpenSession,
  ZLoadOlderMessages,
  ZSendMessage,
  ZNewSession,
  ZInterruptTurn,
  ZEditPrompt,
  ZArchiveSession,
  ZUnarchiveSession,
  ZPinSession,
  ZUnpinSession,
  ZRenameSession,
  ZPairingStart,
  ZListProjects,
  ZReadFile,
  ZTranscribeAudio,
  ZRequestAudio,
  ZRequestGeneratedImage,
  ZRequestRolloutAttachment,
  ZRequestRateLimits,
  ZRequestClawJSServiceStatuses,
  ZAuthOk,
  ZAuthFailed,
  ZVersionMismatch,
  ZSessionsSnapshot,
  ZSessionUpdated,
  ZMessagesSnapshot,
  ZMessagesPage,
  ZMessageAppended,
  ZMessageStreaming,
  ZErrorEvent,
  ZPairingPayload,
  ZProjectsSnapshot,
  ZFileSnapshot,
  ZTranscriptionResult,
  ZAudioSnapshot,
  ZGeneratedImageSnapshot,
  ZRolloutAttachmentSnapshot,
  ZBridgeState,
  ZRateLimitsSnapshot,
  ZRateLimitsUpdated,
  ZClawJSServiceStatusesSnapshot,
  ZClawJSServiceStatusUpdated,
  ZAudioRegister,
  ZAudioAttachTranscript,
  ZAudioGet,
  ZAudioGetBytes,
  ZAudioList,
  ZAudioDelete,
  ZAudioRegisterResult,
  ZAudioAttachTranscriptResult,
  ZAudioGetResult,
  ZAudioBytesResult,
  ZAudioListResult,
  ZAudioDeleteResult,
]);

export type BridgeFrame = z.infer<typeof ZBridgeFrame>;
export type FrameType = BridgeFrame["type"];

export type FrameOf<T extends FrameType> = Extract<BridgeFrame, { type: T }>;

/** Distributive Omit so each member of the union keeps its own type tag. */
type DistributiveOmit<T, K extends keyof T> = T extends unknown ? Omit<T, K> : never;
export type FrameBody = DistributiveOmit<BridgeFrame, "schemaVersion">;

const TOP_LEVEL_KEYS = new Set(TOP_LEVEL_FRAME_KEYS);

function frameByteLength(raw: string): number {
  return new TextEncoder().encode(raw).byteLength;
}

function hasStrictTopLevelShape(obj: unknown): obj is { schemaVersion: number; type: FrameType } {
  if (typeof obj !== "object" || obj === null || Array.isArray(obj)) return false;
  const record = obj as Record<string, unknown>;
  if (record.schemaVersion !== BRIDGE_SCHEMA_VERSION) return false;
  if (typeof record.type !== "string" || !(record.type in ALLOWED_PAYLOAD_KEYS)) return false;
  const allowed = new Set<string>([...TOP_LEVEL_KEYS, ...ALLOWED_PAYLOAD_KEYS[record.type as BridgePayloadFrameType]]);
  return Object.keys(record).every((key) => allowed.has(key));
}

/** Encode a frame body to a JSON string ready to send over WebSocket. */
export function encodeFrame(body: FrameBody): string {
  const frame = { schemaVersion: BRIDGE_SCHEMA_VERSION, ...body };
  return JSON.stringify(frame);
}

/**
 * Decode a JSON text frame received over WebSocket.
 * Returns `null` if the type is unknown. The caller decides whether to surface
 * "Update Clawix" for schema mismatches.
 */
export function decodeFrame(raw: string): BridgeFrame | null {
  try {
    if (frameByteLength(raw) > BRIDGE_MAX_FRAME_BYTES) return null;
    const obj = JSON.parse(raw);
    if (!hasStrictTopLevelShape(obj)) return null;
    const result = ZBridgeFrame.safeParse(obj);
    if (result.success) {
      return result.data;
    }
    return null;
  } catch {
    return null;
  }
}

/** Inspect schemaVersion before full parsing to bail on mismatched peers. */
export function peekSchemaVersion(raw: string): number | null {
  try {
    const obj = JSON.parse(raw);
    if (typeof obj === "object" && obj !== null && typeof obj.schemaVersion === "number") {
      return obj.schemaVersion;
    }
    return null;
  } catch {
    return null;
  }
}

/** QR JSON payload from the daemon: shape declared in PairingService.swift */
export const ZQrPayload = z.object({
  v: z.number().int(),
  host: z.string(),
  port: z.number().int(),
  token: z.string(),
  shortCode: z.string(),
  hostDisplayName: z.string(),
  tailscaleHost: z.string().optional(),
});
export type QrPayload = z.infer<typeof ZQrPayload>;

/** Normalises a user-typed short code: strip spaces, uppercase, hyphens kept. */
export function normaliseShortCode(input: string): string {
  return input.replace(/\s+/g, "").toUpperCase();
}
