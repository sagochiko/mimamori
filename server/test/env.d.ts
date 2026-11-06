declare namespace Cloudflare {
  interface Env {
    // Added in vitest.config.ts so the setup file can apply migrations.
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}

// Vite's `?raw` import: the file's text (test/demo-tour.test.ts reads ios/Core's DemoTour.swift).
declare module "*?raw" {
  const text: string;
  export default text;
}
