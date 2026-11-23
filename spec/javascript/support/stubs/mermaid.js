// Vitest stub for `mermaid`, which the app pins to a CDN URL (config/importmap.rb)
// and loads lazily via `await import("mermaid")`. There is no npm/vendored copy to
// resolve in tests, so this stub stands in for the module's shape. Tests that care
// about rendering should `vi.mock("mermaid", ...)` to assert on these spies.
export default {
  initialize: () => {},
  render: async (_id, _code) => ({ svg: "<svg data-stub='mermaid'></svg>" }),
}
