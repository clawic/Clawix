export interface ServiceStatus {
  id?: string;
  state?: string;
  port?: number;
  pid?: number | null;
  restartCount?: number;
  lastError?: string | null;
  source?: string;
}

export interface ServiceStatusRow {
  id: string;
  detail: string;
  tone: "ok" | "warn" | "muted";
}

export function serviceStatusRows(services: ServiceStatus[]): ServiceStatusRow[] {
  return services.map((service) => {
    const state = service.state ?? "unknown";
    const port = typeof service.port === "number" ? `:${service.port}` : "no port";
    const pid = typeof service.pid === "number" ? `pid ${service.pid}` : "no pid";
    const restartCount = typeof service.restartCount === "number" ? `${service.restartCount} restarts` : "restarts unknown";
    const error = service.lastError ? ` · ${service.lastError}` : "";
    return {
      id: service.id ?? "service",
      detail: `${state} · ${port} · ${pid} · ${restartCount}${error}`,
      tone: state === "running" || state === "ready" ? "ok" : service.lastError ? "warn" : "muted"
    };
  });
}
