export interface PairingPayloadLike {
  token?: unknown;
  shortCode?: unknown;
  qrJson?: unknown;
}

export interface PairingDetails {
  token: string | null;
  shortCode: string;
  host: string | null;
  port: number | null;
  hostDisplayName: string | null;
  manualAddress: string | null;
  isLoopback: boolean;
}

export function pairingDetails(payload: PairingPayloadLike | null | undefined): PairingDetails {
  const qr = parseQrJson(payload?.qrJson);
  const host = stringOrNull(qr.host);
  const port = portOrNull(qr.port);
  const shortCode = stringOrNull(qr.shortCode) ?? stringOrNull(payload?.shortCode) ?? "";

  return {
    token: stringOrNull(qr.token) ?? stringOrNull(payload?.token),
    shortCode,
    host,
    port,
    hostDisplayName: stringOrNull(qr.hostDisplayName),
    manualAddress: host && port ? `${host}:${port}` : null,
    isLoopback: host === "127.0.0.1" || host === "::1" || host === "localhost"
  };
}

function parseQrJson(value: unknown): Record<string, unknown> {
  if (typeof value !== "string") return {};

  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function portOrNull(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value)) return null;
  return value > 0 && value <= 65535 ? value : null;
}
