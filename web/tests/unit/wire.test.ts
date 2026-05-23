/**
 * Vitest unit tests for the wire codec. Pins the JSON shape of every frame
 * so a Swift-side change (or a TS-side typo) shows up as a red dot here.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it, expect } from "vitest";
import { decodeFrame, encodeFrame, peekSchemaVersion, BRIDGE_MAX_FRAME_BYTES, BRIDGE_SCHEMA_VERSION, type FrameBody } from "../../src/bridge/frames";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const bridgeFixtureRoot = path.join(repoRoot, "packages/ClawixCore/Fixtures/BridgeV1");

describe("frames", () => {
  it("roundtrips an auth frame", () => {
    const body: FrameBody = {
      type: "auth",
      token: "abc",
      deviceName: "Web",
      clientKind: "companion",
      clientId: "client-web",
      installationId: "install-web",
      deviceId: "device-web",
    };
    const raw = encodeFrame(body);
    const back = decodeFrame(raw);
    expect(back).toMatchObject({
      type: "auth",
      token: "abc",
      deviceName: "Web",
      clientKind: "companion",
      clientId: "client-web",
      installationId: "install-web",
      deviceId: "device-web",
      schemaVersion: BRIDGE_SCHEMA_VERSION,
    });
  });

  it("decodes an authOk frame from the daemon", () => {
    const raw = JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION, type: "authOk", hostDisplayName: "Mac" });
    expect(decodeFrame(raw)).toMatchObject({ type: "authOk", hostDisplayName: "Mac" });
  });

  it("decodes a sessionsSnapshot with empty array", () => {
    const raw = JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION, type: "sessionsSnapshot", sessions: [] });
    expect(decodeFrame(raw)).toMatchObject({ type: "sessionsSnapshot", sessions: [] });
  });

  it("decodes pairingPayload with token and shortCode", () => {
    const raw = JSON.stringify({
      schemaVersion: BRIDGE_SCHEMA_VERSION,
      type: "pairingPayload",
      qrJson: "{\"v\":1,\"host\":\"127.0.0.1\",\"port\":24080,\"token\":\"tok\"}",
      token: "tok",
      shortCode: "ABC-234-XYZ",
    });
    expect(decodeFrame(raw)).toMatchObject({ type: "pairingPayload", token: "tok", shortCode: "ABC-234-XYZ" });
  });

  it("decodes a messagesSnapshot with messages", () => {
    const raw = JSON.stringify({
      schemaVersion: BRIDGE_SCHEMA_VERSION,
      type: "messagesSnapshot",
      sessionId: "c1",
      messages: [
        {
          id: "m1",
          role: "user",
          content: "hi",
          timestamp: "2026-05-09T00:00:00.000Z",
        },
      ],
    });
    const back = decodeFrame(raw);
    expect(back?.type).toBe("messagesSnapshot");
    if (back?.type === "messagesSnapshot") {
      expect(back.messages.length).toBe(1);
      expect(back.messages[0]?.content).toBe("hi");
    }
  });

  it("returns null on unknown schema versions and frame types", () => {
    const raw = JSON.stringify({ schemaVersion: 99, type: "futureFrame", foo: "bar" });
    expect(decodeFrame(raw)).toBeNull();
  });

  it("returns null on malformed, non-object, oversized, or extra-field frames", () => {
    expect(decodeFrame("{")).toBeNull();
    expect(decodeFrame(JSON.stringify(["not", "object"]))).toBeNull();
    expect(decodeFrame(JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION }))).toBeNull();
    expect(decodeFrame(JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION, type: "listSessions", sessionId: "extra" }))).toBeNull();
    expect(decodeFrame(" ".repeat(BRIDGE_MAX_FRAME_BYTES + 1))).toBeNull();
  });

  it("peeks the schema version without parsing", () => {
    const raw = JSON.stringify({ schemaVersion: 99, type: "ping" });
    expect(peekSchemaVersion(raw)).toBe(99);
  });

  it("decodes the generated Bridge V1 fixture corpus", () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(bridgeFixtureRoot, "manifest.json"), "utf8")) as {
      contractId: string;
      bridgeSchemaVersion: number;
      fixtureCount: number;
      fixtures: Array<{ file: string; type: string }>;
    };
    expect(manifest.contractId).toBe("clawix.protocol.bridge.v1");
    expect(manifest.bridgeSchemaVersion).toBe(BRIDGE_SCHEMA_VERSION);
    expect(manifest.fixtures.length).toBe(manifest.fixtureCount);

    for (const fixture of manifest.fixtures) {
      const raw = fs.readFileSync(path.join(bridgeFixtureRoot, fixture.file), "utf8");
      const decoded = decodeFrame(raw);
      expect(decoded, fixture.file).not.toBeNull();
      expect(decoded?.schemaVersion, fixture.file).toBe(BRIDGE_SCHEMA_VERSION);
      expect(decoded?.type, fixture.file).toBe(fixture.type);
      if (decoded) {
        const body = { ...decoded };
        delete (body as { schemaVersion?: number }).schemaVersion;
        expect(decodeFrame(encodeFrame(body)), fixture.file).toMatchObject({ type: decoded.type });
      }
    }
  });
});
