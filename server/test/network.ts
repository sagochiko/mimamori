import { setupNetwork } from "@msw/cloudflare";

// Every outbound fetch in tests goes through this mock. A request without a handler fails
// instead of reaching the real Google, Anthropic, or Apple servers.
export const network = setupNetwork();
network.configure({ onUnhandledFrame: "error" });
