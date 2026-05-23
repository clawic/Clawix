import { z } from "zod";
import { bridgeFrameBase as base } from "./frame-base";
import {
  ZWireMessage,
  ZWireProject,
  ZWireSession,
} from "./wire";

/** Inbound: server -> client */
export const ZAuthOk = z.object({ ...base, type: z.literal("authOk"), hostDisplayName: z.string().optional() });
export const ZAuthFailed = z.object({ ...base, type: z.literal("authFailed"), reason: z.string() });
export const ZVersionMismatch = z.object({ ...base, type: z.literal("versionMismatch"), serverVersion: z.number().int() });

export const ZSessionsSnapshot = z.object({ ...base, type: z.literal("sessionsSnapshot"), sessions: z.array(ZWireSession) });
export const ZSessionUpdated = z.object({ ...base, type: z.literal("sessionUpdated"), session: ZWireSession });

export const ZMessagesSnapshot = z.object({
  ...base,
  type: z.literal("messagesSnapshot"),
  sessionId: z.string(),
  messages: z.array(ZWireMessage),
  hasMore: z.boolean().optional(),
});

export const ZMessagesPage = z.object({
  ...base,
  type: z.literal("messagesPage"),
  sessionId: z.string(),
  messages: z.array(ZWireMessage),
  hasMore: z.boolean(),
});

export const ZMessageAppended = z.object({
  ...base,
  type: z.literal("messageAppended"),
  sessionId: z.string(),
  message: ZWireMessage,
});

export const ZMessageStreaming = z.object({
  ...base,
  type: z.literal("messageStreaming"),
  sessionId: z.string(),
  messageId: z.string(),
  content: z.string(),
  reasoningText: z.string(),
  finished: z.boolean(),
});

export const ZErrorEvent = z.object({ ...base, type: z.literal("errorEvent"), code: z.string(), message: z.string() });

export const ZPairingPayload = z.object({
  ...base,
  type: z.literal("pairingPayload"),
  qrJson: z.string(),
  token: z.string(),
  shortCode: z.string(),
});

export const ZProjectsSnapshot = z.object({
  ...base,
  type: z.literal("projectsSnapshot"),
  projects: z.array(ZWireProject),
});

export const ZFileSnapshot = z.object({
  ...base,
  type: z.literal("fileSnapshot"),
  path: z.string(),
  content: z.string().optional(),
  isMarkdown: z.boolean().default(false),
  error: z.string().optional(),
});

export const ZTranscriptionResult = z.object({
  ...base,
  type: z.literal("transcriptionResult"),
  requestId: z.string(),
  text: z.string(),
  errorMessage: z.string().optional(),
});

export const ZAudioSnapshot = z.object({
  ...base,
  type: z.literal("audioSnapshot"),
  audioId: z.string(),
  audioBase64: z.string().optional(),
  mimeType: z.string().optional(),
  errorMessage: z.string().optional(),
});

export const ZGeneratedImageSnapshot = z.object({
  ...base,
  type: z.literal("generatedImageSnapshot"),
  path: z.string(),
  dataBase64: z.string().optional(),
  mimeType: z.string().optional(),
  errorMessage: z.string().optional(),
});

export const ZRolloutAttachmentSnapshot = z.object({
  ...base,
  type: z.literal("rolloutAttachmentSnapshot"),
  attachmentId: z.string(),
  dataBase64: z.string().optional(),
  mimeType: z.string().optional(),
  errorMessage: z.string().optional(),
});

export const ZBridgeState = z.object({
  ...base,
  type: z.literal("bridgeState"),
  state: z.string(),
  chatCount: z.number().int(),
  message: z.string().optional(),
});
