const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

export type StudioProxyGatewayUrlOptions = {
  allowDirectLoopback?: boolean;
};

export const resolveStudioProxyGatewayUrl = (
  upstreamGatewayUrl?: string,
  options: StudioProxyGatewayUrlOptions = {}
): string => {
  const raw = typeof upstreamGatewayUrl === "string" ? upstreamGatewayUrl.trim() : "";
  if (raw && options.allowDirectLoopback === true) {
    try {
      const parsed = new URL(raw);
      if (LOOPBACK_HOSTS.has(parsed.hostname)) {
        return raw;
      }
    } catch {
      // Fall through to the Studio proxy for malformed or non-URL values.
    }
  }

  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  const host = window.location.host;
  return `${protocol}://${host}/api/gateway/ws`;
};

