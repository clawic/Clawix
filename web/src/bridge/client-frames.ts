import { z } from "zod";
import { bridgeFrameBase as base } from "./frame-base";
import { ZWireAttachment } from "./wire";

export const ZClientKind = z.enum(["companion", "desktop"]);
export type ClientKind = z.infer<typeof ZClientKind>;

/** Outbound: client -> server */
export const ZAuth = z.object({
  ...base,
  type: z.literal("auth"),
  token: z.string(),
  deviceName: z.string().optional(),
  clientKind: ZClientKind,
  clientId: z.string(),
  installationId: z.string(),
  deviceId: z.string(),
});

export const ZListSessions = z.object({ ...base, type: z.literal("listSessions") });

export const ZOpenSession = z.object({
  ...base,
  type: z.literal("openSession"),
  sessionId: z.string(),
  limit: z.number().int().optional(),
});

export const ZLoadOlderMessages = z.object({
  ...base,
  type: z.literal("loadOlderMessages"),
  sessionId: z.string(),
  beforeMessageId: z.string(),
  limit: z.number().int(),
});

export const ZSendMessage = z.object({
  ...base,
  type: z.literal("sendMessage"),
  sessionId: z.string(),
  text: z.string(),
  attachments: z.array(ZWireAttachment).optional().default([]),
});

export const ZNewSession = z.object({
  ...base,
  type: z.literal("newSession"),
  sessionId: z.string(),
  text: z.string(),
  attachments: z.array(ZWireAttachment).optional().default([]),
});

export const ZInterruptTurn = z.object({ ...base, type: z.literal("interruptTurn"), sessionId: z.string() });

export const ZEditPrompt = z.object({
  ...base,
  type: z.literal("editPrompt"),
  sessionId: z.string(),
  messageId: z.string(),
  text: z.string(),
});

export const ZArchiveSession = z.object({ ...base, type: z.literal("archiveSession"), sessionId: z.string() });
export const ZUnarchiveSession = z.object({ ...base, type: z.literal("unarchiveSession"), sessionId: z.string() });
export const ZPinSession = z.object({ ...base, type: z.literal("pinSession"), sessionId: z.string() });
export const ZUnpinSession = z.object({ ...base, type: z.literal("unpinSession"), sessionId: z.string() });
export const ZRenameSession = z.object({ ...base, type: z.literal("renameSession"), sessionId: z.string(), title: z.string() });
export const ZPairingStart = z.object({ ...base, type: z.literal("pairingStart") });
export const ZListProjects = z.object({ ...base, type: z.literal("listProjects") });
export const ZReadFile = z.object({ ...base, type: z.literal("readFile"), path: z.string() });

export const ZTranscribeAudio = z.object({
  ...base,
  type: z.literal("transcribeAudio"),
  requestId: z.string(),
  audioBase64: z.string(),
  mimeType: z.string(),
  language: z.string().optional(),
});
export const ZRequestAudio = z.object({ ...base, type: z.literal("requestAudio"), audioId: z.string() });
export const ZRequestGeneratedImage = z.object({ ...base, type: z.literal("requestGeneratedImage"), path: z.string() });
export const ZRequestRolloutAttachment = z.object({ ...base, type: z.literal("requestRolloutAttachment"), attachmentId: z.string() });
export const ZRequestRateLimits = z.object({ ...base, type: z.literal("requestRateLimits") });
export const ZRequestClawJSServiceStatuses = z.object({ ...base, type: z.literal("requestClawJSServiceStatuses") });
