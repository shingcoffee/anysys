import { defineConfig, devices } from "@playwright/test"
import { fileURLToPath } from "node:url"

// Vitest/Playwright are invoked from the Rails root, but this config file lives
// under config/javascript/. Build absolute paths so file resolution stays correct.
const root = (p) => fileURLToPath(new URL(`../../${p}`, import.meta.url))

// Layer 2 (Tier C): real-browser tests for geometry-dependent JS — drag-and-drop,
// canvas positioning, pointer/rAF flows — that happy-dom cannot fake.
//
// Two kinds of e2e tests live under spec/e2e:
//   *.selfcontained.spec.js — serve a tiny static HTML page (no Rails); proves the
//     vendored interaction libs (SortableJS, etc.) actually reorder in a real browser.
//   *.app.spec.js           — drive the real Rails app; require a running server at
//     APP_BASE_URL (default http://127.0.0.1:3001). Skipped automatically if unset.
//
// Chromium is the locally-cached Playwright build; no network needed at run time.
export default defineConfig({
  testDir: root("spec/e2e"),
  testMatch: /.*\.spec\.js/,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: process.env.APP_BASE_URL || "http://127.0.0.1:3011",
    trace: "retain-on-failure",
    headless: true,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
      testIgnore: /speech_to_text_mic\.app\.spec\.js/
    },
    {
      // Fake audio input: this host has no capture device, so getUserMedia
      // would otherwise throw NotFoundError on the dashboard mic.
      name: "chromium-media",
      testMatch: /speech_to_text_mic\.app\.spec\.js/,
      use: {
        ...devices["Desktop Chrome"],
        permissions: ["microphone"],
        launchOptions: {
          args: [
            "--use-fake-ui-for-media-stream",
            "--use-fake-device-for-media-stream"
          ]
        }
      }
    },
  ],
  // Static file server for *.selfcontained.spec.js fixtures (serves the worktree
  // root so fixtures can import vendored ESM by absolute path). App-backed
  // (*.app.spec.js) tests point at their own APP_BASE_URL instead.
  webServer: {
    command: "python3 -m http.server 3011",
    // Playwright resolves the command's working directory relative to this config
    // file, which is now under config/javascript/. Serve the Rails root instead.
    cwd: root("."),
    url: "http://127.0.0.1:3011/vendor/javascript/sortable.esm.js",
    reuseExistingServer: true,
    timeout: 20000,
  },
})
