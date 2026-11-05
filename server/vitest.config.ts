import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          // Test-only values. Real keys are set by the author as Workers secrets.
          bindings: {
            TEST_MIGRATIONS: migrations,
            APNS_KEY_P8: "set-per-test",
            APNS_KEY_ID: "TESTKEY123",
            APNS_TEAM_ID: "TESTTEAM12",
            APNS_TOPIC: "test.mimamori.app",
            ANTHROPIC_API_KEY: "test-anthropic-key",
            // 32 zero bytes, base64. Only for tests.
            TOKEN_ENC_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            GOOGLE_CLIENT_ID: "test-client.apps.googleusercontent.com",
            GOOGLE_CLIENT_SECRET: "test-client-secret",
          },
        },
      }),
    ],
    test: {
      setupFiles: ["./test/setup.ts"],
    },
  };
});
