import { describe, expect, it } from "vitest";
import { bridgeDiagnostic } from "./bridge_diagnostics_model";

describe("bridgeDiagnostic", () => {
  it("formats auth failures, version mismatches, and bridge errors", () => {
    expect(bridgeDiagnostic({ type: "authFailed", reason: "bad-token" })).toEqual({
      state: "auth failed",
      message: "bad-token"
    });
    expect(bridgeDiagnostic({ type: "versionMismatch", serverVersion: 2 })).toEqual({
      state: "version mismatch",
      message: "Bridge schema 2 is not supported."
    });
    expect(bridgeDiagnostic({ type: "errorEvent", code: "internal", message: "boom" })).toEqual({
      state: "error",
      message: "internal: boom"
    });
  });

  it("ignores non-diagnostic frames", () => {
    expect(bridgeDiagnostic({ type: "sessionsSnapshot" })).toBeNull();
  });
});
