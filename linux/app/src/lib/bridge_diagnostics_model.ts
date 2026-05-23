export interface BridgeDiagnosticFrame {
  type: string;
  reason?: unknown;
  serverVersion?: unknown;
  code?: unknown;
  message?: unknown;
}

export function bridgeDiagnostic(frame: BridgeDiagnosticFrame): { state: string; message: string } | null {
  switch (frame.type) {
    case "authFailed":
      return { state: "auth failed", message: stringOr(frame.reason, "Bridge authentication failed.") };
    case "versionMismatch":
      return { state: "version mismatch", message: `Bridge schema ${stringOr(frame.serverVersion, "unknown")} is not supported.` };
    case "errorEvent":
      return { state: "error", message: `${stringOr(frame.code, "bridge")}: ${stringOr(frame.message, "Unknown bridge error.")}` };
    default:
      return null;
  }
}

function stringOr(value: unknown, fallback: string): string {
  if (typeof value === "number") return String(value);
  return typeof value === "string" && value.trim() ? value : fallback;
}
