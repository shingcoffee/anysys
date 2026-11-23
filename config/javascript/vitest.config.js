import { defineConfig } from "vitest/config"
import { fileURLToPath } from "node:url"

// Absolute path to app/javascript so bare importmap specifiers resolve in tests.
// Vitest resolves relative to this config file's directory, so we step up two
// levels to reach the Rails root (config/javascript/ -> config/ -> root).
const root = (p) => fileURLToPath(new URL(`../../${p}`, import.meta.url))
const js = (p) => root(`app/javascript/${p}`)
const vendor = (p) => root(`vendor/javascript/${p}`)

// The app ships JS via importmap (no bundler). Imports use bare specifiers
// (e.g. `controllers/page_builder/base_manager`, `utils`, `flowchart/constants`)
// pinned by config/importmap.rb. Vitest has no importmap, so we mirror every
// `pin_all_from` root and vendored `pin` here as a resolve.alias. Regex forms
// (`^controllers/`) cover all nested files under a root with one entry.
export default defineConfig({
  resolve: {
    alias: [
      // pin_all_from roots -> app/javascript/<dir>
      { find: /^controllers\//, replacement: js("controllers/") },
      { find: /^lib\//, replacement: js("lib/") },
      { find: /^constants\//, replacement: js("constants/") },
      { find: /^versions\//, replacement: js("versions/") },
      { find: /^flowchart\//, replacement: js("flowchart/") },
      // exact single pins
      { find: "utils", replacement: js("utils/index.js") },
      { find: "application", replacement: js("application.js") },
      // vendored ESM libs
      { find: "sortablejs", replacement: vendor("sortable.esm.js") },
      { find: "diff", replacement: vendor("diff.js") },
      // `mermaid` is pinned to a CDN URL in config/importmap.rb (no npm/vendored
      // copy). Alias it to a local stub so `await import("mermaid")` resolves in
      // tests; render-sensitive specs can still vi.mock("mermaid").
      { find: "mermaid", replacement: root("spec/javascript/support/stubs/mermaid.js") },
      // `@hotwired/stimulus-loading` is pinned to the vendored copy shipped by the
      // stimulus-rails gem (not an npm package), so nothing under node_modules
      // resolves it. Alias to a local stub mirroring that gem file.
      { find: "@hotwired/stimulus-loading", replacement: root("spec/javascript/support/stubs/stimulus_loading.js") },
    ],
  },
  test: {
    // happy-dom is faster than jsdom and sufficient for Stimulus controllers.
    // Pure-logic (Tier A) tests don't touch the DOM; controller (Tier B) tests do.
    environment: "happy-dom",
    globals: true,
    include: ["spec/javascript/**/*.{test,spec}.js"],
    setupFiles: ["spec/javascript/setup.js"],
    coverage: {
      provider: "v8",
      reportsDirectory: "coverage/javascript",
      reporter: ["text-summary", "html", "lcov"],
      include: ["app/javascript/**/*.js"],
      exclude: [
        "app/javascript/application.js",
        // Tier C: geometry/pointer engines that require a real browser; covered
        // by Playwright (spec/e2e), not by happy-dom unit tests. Excluded so the
        // unit-coverage number is honest about what happy-dom can actually assert.
        "app/javascript/controllers/page_builder/drag_engine.js",
        "app/javascript/controllers/page_builder/drag_engine/**",
      ],
      all: true,
    },
  },
})
