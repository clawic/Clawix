export const BRIDGE_LOOPBACK_HOST = "localhost";
export const BRIDGE_DEFAULT_PORT = 24080;

export function bridgeWebSocketEndpoint(
  protocol: string,
  host: string,
  port: number | null,
  path = "/ws",
): string {
  const targetHost = port ? `${host}:${port}` : host;
  return `${protocol}//${targetHost}${path}`;
}
