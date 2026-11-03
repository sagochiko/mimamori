import { setupNetwork } from "@msw/cloudflare";

// Every outbound fetch in tests goes through this mock.
export const network = setupNetwork();
