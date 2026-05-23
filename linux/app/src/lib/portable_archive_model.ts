export type PortableArchiveStateId =
  | "ready"
  | "verificationFailed"
  | "secretsRequireReauth"
  | "externalSourceReferenced"
  | "cacheWillRebuild"
  | "restoreBlocked"
  | "restoreComplete";

export type PortableArchiveActionId =
  | "exportFullBackup"
  | "verifyArchive"
  | "inspectManifest"
  | "importPreview"
  | "restore"
  | "restoreReport";

export interface PortableArchiveState {
  id: PortableArchiveStateId;
  label: string;
  detail: string;
  tone: "ok" | "warn" | "danger";
}

export interface PortableArchiveAction {
  id: PortableArchiveActionId;
  label: string;
  command: string;
  detail: string;
  nextState: PortableArchiveStateId;
  primary?: boolean;
}

export const portableArchiveExtensions = [".clawbackup", ".clawexport", ".clawsecrets"] as const;

export const portableArchiveStates: PortableArchiveState[] = [
  {
    id: "ready",
    label: "Ready",
    detail: ".clawbackup can be planned, verified, previewed, and restored after approval.",
    tone: "ok"
  },
  {
    id: "verificationFailed",
    label: "Verification failed",
    detail: "The archive manifest, hashes, compatibility range, or restore graph did not verify.",
    tone: "warn"
  },
  {
    id: "secretsRequireReauth",
    label: "Secrets require reauth",
    detail: ".clawsecrets export, import, and restore require requires_signed_host proof before secrets move.",
    tone: "danger"
  },
  {
    id: "externalSourceReferenced",
    label: "External source referenced",
    detail: "External read-only sources are referenced with provenance and sync metadata.",
    tone: "warn"
  },
  {
    id: "cacheWillRebuild",
    label: "Cache will rebuild",
    detail: "Rebuildable caches and search indexes are excluded and rebuilt from canonical data.",
    tone: "ok"
  },
  {
    id: "restoreBlocked",
    label: "Restore blocked",
    detail: "Restore waits for import preview, verification, signed-host proof, explicit approval, and exact target confirmation.",
    tone: "danger"
  },
  {
    id: "restoreComplete",
    label: "Restore complete",
    detail: "Restore report is available with counts, target root, approvals, and redacted receipts.",
    tone: "ok"
  }
];

export const portableArchiveActions: PortableArchiveAction[] = [
  {
    id: "exportFullBackup",
    label: "Export full backup",
    command: "claw archive export --output PATH.clawbackup --json",
    detail: ".clawbackup includes canonical data, files, instructions, sessions, audit metadata, policies, grants, and encrypted secrets envelopes.",
    nextState: "secretsRequireReauth",
    primary: true
  },
  {
    id: "verifyArchive",
    label: "Verify archive",
    command: "claw archive verify --archive PATH.clawbackup --json",
    detail: "Check manifest.json, hashes, compatibility, external references, cache exclusions, and restore graph.",
    nextState: "ready"
  },
  {
    id: "inspectManifest",
    label: "Inspect manifest",
    command: "claw archive inspect --archive PATH.clawbackup --json",
    detail: "Show deterministic .clawexport and .clawbackup inventory, counts, restore report schema, and referenced external sources.",
    nextState: "externalSourceReferenced"
  },
  {
    id: "importPreview",
    label: "Import preview",
    command: "claw archive import --archive PATH.clawbackup --target TARGET --json",
    detail: "Map archive contents into a new or selected target before anything is applied.",
    nextState: "cacheWillRebuild"
  },
  {
    id: "restore",
    label: "Restore",
    command: "claw archive restore --archive PATH.clawbackup --target TARGET --approve --confirm-restore TARGET --json",
    detail: "Apply only after successful verification, explicit approval, exact target confirmation, and signed-host proof for encrypted secrets.",
    nextState: "restoreBlocked"
  },
  {
    id: "restoreReport",
    label: "Restore report",
    command: "claw archive doctor --json",
    detail: "Review restored counts, target root, blocked reasons, approvals, file hashes, and redacted receipts.",
    nextState: "restoreComplete"
  }
];

export function portableArchiveStateById(id: PortableArchiveStateId): PortableArchiveState {
  return portableArchiveStates.find((state) => state.id === id) ?? portableArchiveStates[0];
}

export function portableArchiveStateForAction(id: PortableArchiveActionId): PortableArchiveState {
  const action = portableArchiveActions.find((item) => item.id === id);
  return portableArchiveStateById(action?.nextState ?? "ready");
}
