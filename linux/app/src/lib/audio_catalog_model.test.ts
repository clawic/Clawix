import { describe, expect, it } from "vitest";
import audioGetResult from "../../../../packages/ClawixCore/Fixtures/BridgeV1/053-audioGetResult.json";
import audioRegisterResult from "../../../../packages/ClawixCore/Fixtures/BridgeV1/051-audioRegisterResult.json";
import audioAttachTranscriptResult from "../../../../packages/ClawixCore/Fixtures/BridgeV1/052-audioAttachTranscriptResult.json";
import audioListResult from "../../../../packages/ClawixCore/Fixtures/BridgeV1/055-audioListResult.json";
import audioDeleteResult from "../../../../packages/ClawixCore/Fixtures/BridgeV1/056-audioDeleteResult.json";
import {
  applyAudioAttachTranscriptResult,
  applyAudioDeleteResult,
  applyAudioGetResult,
  applyAudioListResult,
  audioCatalogItemId,
  emptyAudioCatalogState
} from "./audio_catalog_model";

describe("audio catalog model", () => {
  it("indexes audioGetResult assets by audio id", () => {
    const state = applyAudioGetResult(emptyAudioCatalogState, audioGetResult);

    expect(Object.keys(state.itemsById)).toEqual(["audio-1"]);
    expect(audioCatalogItemId(state.itemsById["audio-1"])).toBe("audio-1");
  });

  it("stores audioListResult pages and totals", () => {
    const state = applyAudioListResult(emptyAudioCatalogState, audioListResult);

    expect(state.total).toBe(1);
    expect(state.list).toHaveLength(1);
    expect(Object.keys(state.itemsById)).toEqual(["audio-1"]);
  });

  it("indexes audioRegisterResult assets like fetched assets", () => {
    const state = applyAudioGetResult(emptyAudioCatalogState, audioRegisterResult);

    expect(Object.keys(state.itemsById)).toEqual(["audio-1"]);
    expect(audioCatalogItemId(state.itemsById["audio-1"])).toBe("audio-1");
  });

  it("attaches returned transcripts to an existing audio row", () => {
    const registered = applyAudioGetResult(emptyAudioCatalogState, audioRegisterResult);
    const next = applyAudioAttachTranscriptResult(registered, audioAttachTranscriptResult);

    expect((next.itemsById["audio-1"] as { transcripts: unknown[] }).transcripts).toHaveLength(1);
  });

  it("removes deleted audio rows by request id", () => {
    const listed = applyAudioListResult(emptyAudioCatalogState, audioListResult);
    const next = applyAudioDeleteResult(listed, audioDeleteResult, { "req-audio-6": "audio-1" });

    expect(next.total).toBe(0);
    expect(next.list).toEqual([]);
    expect(next.itemsById).toEqual({});
  });
});
