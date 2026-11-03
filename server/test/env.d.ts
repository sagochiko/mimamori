declare namespace Cloudflare {
  interface Env {
    // Added in vitest.config.ts so the setup file can apply migrations.
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
