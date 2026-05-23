import { t } from "../localization/i18n";

export type UserFacingFailureKind =
  | "backendUnavailable"
  | "daemonUnavailable"
  | "permissionDenied"
  | "modelUnavailable"
  | "networkOffline"
  | "serviceUnavailable"
  | "unknown";

export interface UserFacingFailure {
  kind: UserFacingFailureKind;
  message: string;
  retryable: boolean;
}

export function classifyUserFacingFailure(reason: string | null | undefined): UserFacingFailure {
  const raw = (reason ?? "").trim();
  const lower = raw.toLowerCase();

  if (hasAny(lower, [
    "not connected to the internet",
    "internet connection appears to be offline",
    "network connection lost",
    "network is unreachable",
    "cannot connect to host",
    "cannot find host",
    "timed out",
    "offline",
  ])) {
    return {
      kind: "networkOffline",
      message: t("The network appears to be offline. Reconnect, then try again."),
      retryable: true,
    };
  }

  if (hasAny(lower, [
    "permission denied",
    "forbidden",
    "http 401",
    "http 403",
    "invalid api key",
    "authentication failed",
    "auth-failed",
    "not authorized",
    "unauthorized",
  ])) {
    return {
      kind: "permissionDenied",
      message: t("Permission was denied. Review permissions, then try again."),
      retryable: true,
    };
  }

  if (hasAny(lower, [
    "model unavailable",
    "model is unavailable",
    "model not found",
    "unknown model",
    "no model available",
    "not downloaded",
    "download a model",
    "no such model",
  ])) {
    return {
      kind: "modelUnavailable",
      message: t("That model is not available. Pick another model and try again."),
      retryable: true,
    };
  }

  if (hasAny(lower, [
    "background bridge",
    "bridge is not ready",
    "daemonunreachable",
    "daemon unreachable",
    "daemon is unavailable",
    "closed code=",
    "dead-link",
    "open-failed",
  ])) {
    return {
      kind: "daemonUnavailable",
      message: t("The background bridge is unavailable. Try again after it reconnects."),
      retryable: true,
    };
  }

  if (hasAny(lower, [
    "agent runtime is unavailable",
    "runtime is unavailable",
    "backend not ready",
  ])) {
    return {
      kind: "backendUnavailable",
      message: t("The agent runtime is unavailable. Try again after it reconnects."),
      retryable: true,
    };
  }

  if (hasAny(lower, [
    "service unavailable",
    "service not ready",
    "could not reach",
  ])) {
    return {
      kind: "serviceUnavailable",
      message: t("The service is unavailable. Try again in a moment."),
      retryable: true,
    };
  }

  return {
    kind: "unknown",
    message: t("Request failed. Try again in a moment."),
    retryable: true,
  };
}

export function logUserFacingFailure(surface: string, failure: UserFacingFailure): void {
  console.warn("[Clawix.failure]", {
    surface,
    kind: failure.kind,
    retryable: failure.retryable,
  });
}

function hasAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(needle));
}
