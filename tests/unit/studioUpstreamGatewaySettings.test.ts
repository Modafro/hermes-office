import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it } from "vitest";

const makeTempDir = (name: string) => fs.mkdtempSync(path.join(os.tmpdir(), `${name}-`));

describe("server studio upstream gateway settings", () => {
  const priorEnv = {
    OPENCLAW_STATE_DIR: process.env.OPENCLAW_STATE_DIR,
    CLAW3D_GATEWAY_URL: process.env.CLAW3D_GATEWAY_URL,
    NEXT_PUBLIC_GATEWAY_URL: process.env.NEXT_PUBLIC_GATEWAY_URL,
    CLAW3D_GATEWAY_TOKEN: process.env.CLAW3D_GATEWAY_TOKEN,
    CLAW3D_GATEWAY_ADAPTER_TYPE: process.env.CLAW3D_GATEWAY_ADAPTER_TYPE,
    HERMES_ADAPTER_PORT: process.env.HERMES_ADAPTER_PORT,
    DEMO_ADAPTER_PORT: process.env.DEMO_ADAPTER_PORT,
  };
  let tempDir: string | null = null;

  afterEach(() => {
    for (const [key, value] of Object.entries(priorEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
      tempDir = null;
    }
  });

  it("falls back to openclaw.json token/port when studio settings are missing", async () => {
    tempDir = makeTempDir("studio-upstream-openclaw-defaults");
    process.env.OPENCLAW_STATE_DIR = tempDir;

    fs.writeFileSync(
      path.join(tempDir, "openclaw.json"),
      JSON.stringify({ gateway: { port: 18790, auth: { token: "tok" } } }, null, 2),
      "utf8"
    );

    const { loadUpstreamGatewaySettings } = await import("../../server/studio-settings");
    const settings = loadUpstreamGatewaySettings(process.env);
    expect(settings.url).toBe("ws://127.0.0.1:18790");
    expect(settings.token).toBe("tok");
  });

  it("keeps a configured url and fills token from openclaw.json when missing", async () => {
    tempDir = makeTempDir("studio-upstream-url-keep");
    process.env.OPENCLAW_STATE_DIR = tempDir;

    fs.mkdirSync(path.join(tempDir, "claw3d"), { recursive: true });
    fs.writeFileSync(
      path.join(tempDir, "claw3d", "settings.json"),
      JSON.stringify({ gateway: { url: "ws://gateway.example:18789", token: "" } }, null, 2),
      "utf8"
    );
    fs.writeFileSync(
      path.join(tempDir, "openclaw.json"),
      JSON.stringify({ gateway: { port: 18789, auth: { token: "tok-local" } } }, null, 2),
      "utf8"
    );

    const { loadUpstreamGatewaySettings } = await import("../../server/studio-settings");
    const settings = loadUpstreamGatewaySettings(process.env);
    expect(settings.url).toBe("ws://gateway.example:18789");
    expect(settings.token).toBe("tok-local");
  });

  it("uses explicit env gateway settings before stale saved settings", async () => {
    tempDir = makeTempDir("studio-upstream-env-override");
    process.env.OPENCLAW_STATE_DIR = tempDir;
    process.env.CLAW3D_GATEWAY_URL = "ws://127.0.0.1:18790";
    process.env.CLAW3D_GATEWAY_ADAPTER_TYPE = "hermes";

    fs.mkdirSync(path.join(tempDir, "claw3d"), { recursive: true });
    fs.writeFileSync(
      path.join(tempDir, "claw3d", "settings.json"),
      JSON.stringify({ gateway: { url: "ws://localhost:18789", token: "old", adapterType: "openclaw" } }, null, 2),
      "utf8"
    );

    const { loadUpstreamGatewaySettings } = await import("../../server/studio-settings");
    const settings = loadUpstreamGatewaySettings(process.env);
    expect(settings.url).toBe("ws://127.0.0.1:18790");
    expect(settings.token).toBe("");
    expect(settings.adapterType).toBe("hermes");
  });

  it("builds a Hermes upstream from HERMES_ADAPTER_PORT", async () => {
    tempDir = makeTempDir("studio-upstream-hermes-port");
    process.env.OPENCLAW_STATE_DIR = tempDir;
    process.env.HERMES_ADAPTER_PORT = "18790";

    const { loadUpstreamGatewaySettings } = await import("../../server/studio-settings");
    const settings = loadUpstreamGatewaySettings(process.env);
    expect(settings.url).toBe("ws://127.0.0.1:18790");
    expect(settings.token).toBe("");
    expect(settings.adapterType).toBe("hermes");
  });
});
