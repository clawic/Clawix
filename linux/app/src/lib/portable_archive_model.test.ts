import { describe, expect, it } from "vitest";
import {
  portableArchiveActions,
  portableArchiveExtensions,
  portableArchiveStateForAction,
  portableArchiveStates
} from "./portable_archive_model";

describe("portable archive model", () => {
  it("keeps the Settings/Data actions aligned with the Claw archive command surface", () => {
    expect(portableArchiveActions.map((action) => action.label)).toEqual([
      "Export full backup",
      "Verify archive",
      "Inspect manifest",
      "Import preview",
      "Restore",
      "Restore report"
    ]);
    expect(portableArchiveActions.map((action) => action.command)).toEqual([
      "claw archive export --output PATH.clawbackup --json",
      "claw archive verify --archive PATH.clawbackup --json",
      "claw archive inspect --archive PATH.clawbackup --json",
      "claw archive import --archive PATH.clawbackup --target TARGET --json",
      "claw archive restore --archive PATH.clawbackup --target TARGET --approve --confirm-restore TARGET --json",
      "claw archive doctor --json"
    ]);
  });

  it("exposes every canonical portable archive state and file envelope", () => {
    expect(portableArchiveStates.map((state) => state.id)).toEqual([
      "ready",
      "verificationFailed",
      "secretsRequireReauth",
      "externalSourceReferenced",
      "cacheWillRebuild",
      "restoreBlocked",
      "restoreComplete"
    ]);
    expect(portableArchiveExtensions).toEqual([".clawbackup", ".clawexport", ".clawsecrets"]);
    expect(portableArchiveStates.some((state) => state.detail.includes("requires_signed_host"))).toBe(true);
    expect(portableArchiveStates.some((state) => state.detail.includes("exact target confirmation"))).toBe(true);
  });

  it("maps action previews to their resulting UX states", () => {
    expect(portableArchiveStateForAction("exportFullBackup").id).toBe("secretsRequireReauth");
    expect(portableArchiveStateForAction("verifyArchive").id).toBe("ready");
    expect(portableArchiveStateForAction("inspectManifest").id).toBe("externalSourceReferenced");
    expect(portableArchiveStateForAction("importPreview").id).toBe("cacheWillRebuild");
    expect(portableArchiveStateForAction("restore").id).toBe("restoreBlocked");
    expect(portableArchiveStateForAction("restoreReport").id).toBe("restoreComplete");
  });
});
