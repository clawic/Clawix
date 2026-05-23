export interface NetworkControlAdapter {
  id: string;
  kind: string;
  label: string;
  status: string;
  enforcement: string;
  externalPending: boolean;
  reason: string;
  reentryCondition?: string;
}

export interface NetworkControlRule {
  id: string;
  action: string;
  subjectKind: string;
  endpointKind: string;
  endpointValue: string;
  priority: number;
  enabled: boolean;
  source: string;
  notes?: string;
}

export interface NetworkControlEvent {
  id: string;
  observedAt: string;
  subjectKind: string;
  subjectId: string;
  endpointKind: string;
  endpointValue: string;
  decision: string;
  adapterId: string;
  bytesIn: number;
  bytesOut: number;
  domainHidden: boolean;
  processHidden: boolean;
}

export interface NetworkControlStatus {
  detailOptIn: boolean;
  defaultRedaction: string;
  clawRuntime: string;
  gateway: string;
  nativeMac: string;
  recentEvents: number;
  monitorPath: string;
}

export interface NetworkControlSnapshot {
  status: NetworkControlStatus;
  adapters: NetworkControlAdapter[];
  rules: NetworkControlRule[];
  events: NetworkControlEvent[];
}

export const NETWORK_VISIBLE_EVENT_LIMIT = 100;

export const DEFAULT_NETWORK_SNAPSHOT: NetworkControlSnapshot = {
  status: {
    detailOptIn: false,
    defaultRedaction: "aggregate",
    clawRuntime: "observing",
    gateway: "policy-ready",
    nativeMac: "external-pending",
    recentEvents: 3,
    monitorPath: "~/.claw/network/events.db",
  },
  adapters: [
    {
      id: "claw-runtime",
      kind: "framework",
      label: "Claw runtime",
      status: "observing",
      enforcement: "policy",
      externalPending: false,
      reason: "Routes through the framework policy layer.",
    },
    {
      id: "gateway",
      kind: "gateway",
      label: "Gateway",
      status: "ready",
      enforcement: "deny-by-default",
      externalPending: false,
      reason: "Applies route decisions before outbound access.",
    },
    {
      id: "native-mac",
      kind: "native",
      label: "Mac native monitor",
      status: "external pending",
      enforcement: "host",
      externalPending: true,
      reason: "Requires signed host validation before native packet detail is shown.",
      reentryCondition: "Validate in the macOS host.",
    },
  ],
  rules: [
    {
      id: "allow-localhost",
      action: "allow",
      subjectKind: "companion",
      endpointKind: "host",
      endpointValue: "localhost",
      priority: 10,
      enabled: true,
      source: "framework",
      notes: "Local bridge traffic remains available to paired web clients.",
    },
    {
      id: "deny-unknown",
      action: "deny",
      subjectKind: "all",
      endpointKind: "default",
      endpointValue: "",
      priority: 1000,
      enabled: true,
      source: "framework",
      notes: "Unknown outbound routes need explicit approval.",
    },
  ],
  events: [
    {
      id: "evt-localhost",
      observedAt: "2026-05-23T00:00:00.000Z",
      subjectKind: "companion",
      subjectId: "web",
      endpointKind: "host",
      endpointValue: "localhost",
      decision: "allow",
      adapterId: "gateway",
      bytesIn: 4096,
      bytesOut: 2048,
      domainHidden: false,
      processHidden: true,
    },
    {
      id: "evt-unknown",
      observedAt: "2026-05-23T00:01:00.000Z",
      subjectKind: "agent",
      subjectId: "redacted",
      endpointKind: "domain",
      endpointValue: "redacted",
      decision: "deny",
      adapterId: "gateway",
      bytesIn: 0,
      bytesOut: 0,
      domainHidden: true,
      processHidden: true,
    },
    {
      id: "evt-native",
      observedAt: "2026-05-23T00:02:00.000Z",
      subjectKind: "host",
      subjectId: "mac",
      endpointKind: "native",
      endpointValue: "aggregate",
      decision: "observe",
      adapterId: "native-mac",
      bytesIn: 8192,
      bytesOut: 512,
      domainHidden: true,
      processHidden: false,
    },
  ],
};

export function visibleNetworkEvents(
  events: NetworkControlEvent[],
  limit = NETWORK_VISIBLE_EVENT_LIMIT,
): NetworkControlEvent[] {
  return events.slice(0, limit);
}

export function statusPills(snapshot: NetworkControlSnapshot): Array<{ label: string; value: string }> {
  return [
    { label: "Gateway", value: snapshot.status.gateway || "unknown" },
    { label: "Mac", value: snapshot.status.nativeMac || "unknown" },
    { label: "Events", value: String(snapshot.status.recentEvents || snapshot.events.length) },
  ];
}

export function describeEndpoint(kind: string, value: string): string {
  return value.trim() || kind || "unknown";
}

export function setNetworkDetailOptIn(
  snapshot: NetworkControlSnapshot,
  detailOptIn: boolean,
): NetworkControlSnapshot {
  return {
    ...snapshot,
    status: {
      ...snapshot.status,
      detailOptIn,
      defaultRedaction: detailOptIn ? "detail" : "aggregate",
    },
  };
}
