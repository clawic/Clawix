import { z } from "zod";
import { bridgeFrameBase as base } from "./frame-base";
import {
  ZWireAudioAssetWithTranscripts,
  ZWireAudioAttachTranscriptInput,
  ZWireAudioListFilter,
  ZWireAudioListResult,
  ZWireAudioRegisterRequest,
  ZWireAudioTranscript,
} from "./wire";

// Audio catalog frames (outbound: client -> daemon).
export const ZAudioRegister = z.object({
  ...base,
  type: z.literal("audioRegister"),
  requestId: z.string(),
  request: ZWireAudioRegisterRequest,
});
export const ZAudioAttachTranscript = z.object({
  ...base,
  type: z.literal("audioAttachTranscript"),
  requestId: z.string(),
  audioId: z.string(),
  transcript: ZWireAudioAttachTranscriptInput,
});
export const ZAudioGet = z.object({
  ...base,
  type: z.literal("audioGet"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});
export const ZAudioGetBytes = z.object({
  ...base,
  type: z.literal("audioGetBytes"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});
export const ZAudioList = z.object({
  ...base,
  type: z.literal("audioList"),
  requestId: z.string(),
  filter: ZWireAudioListFilter,
});
export const ZAudioDelete = z.object({
  ...base,
  type: z.literal("audioDelete"),
  requestId: z.string(),
  audioId: z.string(),
  appId: z.string(),
});

// Audio catalog frames (inbound: daemon -> client).
export const ZAudioRegisterResult = z.object({
  ...base,
  type: z.literal("audioRegisterResult"),
  requestId: z.string(),
  asset: ZWireAudioAssetWithTranscripts.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioAttachTranscriptResult = z.object({
  ...base,
  type: z.literal("audioAttachTranscriptResult"),
  requestId: z.string(),
  transcript: ZWireAudioTranscript.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioGetResult = z.object({
  ...base,
  type: z.literal("audioGetResult"),
  requestId: z.string(),
  asset: ZWireAudioAssetWithTranscripts.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioBytesResult = z.object({
  ...base,
  type: z.literal("audioBytesResult"),
  requestId: z.string(),
  audioBase64: z.string().nullable().optional(),
  mimeType: z.string().nullable().optional(),
  durationMs: z.number().int().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioListResult = z.object({
  ...base,
  type: z.literal("audioListResult"),
  requestId: z.string(),
  list: ZWireAudioListResult.nullable().optional(),
  errorMessage: z.string().nullable().optional(),
});
export const ZAudioDeleteResult = z.object({
  ...base,
  type: z.literal("audioDeleteResult"),
  requestId: z.string(),
  deleted: z.boolean(),
  errorMessage: z.string().nullable().optional(),
});
