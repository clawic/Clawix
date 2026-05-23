import { z } from "zod";
import { bridgeFrameBase as base } from "./frame-base";
import {
  ZWireClawJSServiceSnapshot,
  ZWireRateLimitSnapshot,
} from "./wire";

export const ZRateLimitsPayload = z.object({
  rateLimits: ZWireRateLimitSnapshot.nullable().optional(),
  rateLimitsByLimitId: z.record(z.string(), ZWireRateLimitSnapshot).default({}),
});

export const ZRateLimitsSnapshot = z.object({
  ...base,
  type: z.literal("rateLimitsSnapshot"),
  ...ZRateLimitsPayload.shape,
});

export const ZRateLimitsUpdated = z.object({
  ...base,
  type: z.literal("rateLimitsUpdated"),
  ...ZRateLimitsPayload.shape,
});

export const ZClawJSServiceStatusesSnapshot = z.object({
  ...base,
  type: z.literal("clawJSServiceStatusesSnapshot"),
  services: z.array(ZWireClawJSServiceSnapshot),
});

export const ZClawJSServiceStatusUpdated = z.object({
  ...base,
  type: z.literal("clawJSServiceStatusUpdated"),
  service: ZWireClawJSServiceSnapshot,
});
