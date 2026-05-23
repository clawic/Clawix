import { z } from "zod";

export const BRIDGE_SCHEMA_VERSION = 1 as const;
export const BRIDGE_MAX_FRAME_BYTES = 8 * 1024 * 1024;
export const BRIDGE_INITIAL_PAGE_LIMIT = 60 as const;
export const BRIDGE_OLDER_PAGE_LIMIT = 40 as const;

export const bridgeFrameBase = { schemaVersion: z.number().int().default(BRIDGE_SCHEMA_VERSION) };
