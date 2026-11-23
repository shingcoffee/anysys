# Customer settings browser follow-up — 2026-10-12

**PASS: all 64 customer-settings browser cases passed with four workers, zero failures, zero skips and zero flaky cases.** This resolves the 36 settings variants numbered 4–39 in the completed final browser failure inventory. It is targeted settings acceptance; the historical complete-release run is recorded separately in [browser verification](2026-10-11-browser-verification.md).

## Scope and classification

Owned source: `spec/e2e/customer_settings_{support,conditional,interactions,navigation}` and the conditional-response exporter `spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb`. Matching developer reference: `doc/reference/{en,zh-CN}/dashboard.md`; reproduction guidance: `spec/e2e/README.md`.

| Original IDs | Root cause and correction | Result |
| --- | --- | --- |
| 4–7, 10–13, 32–39 | Global `main` / `main h1` selectors included website preview documents. Scope the settings shell to `#main-content` and its header H1 outside the content slot. | All corresponding conditional and inventory variants pass. |
| 8, 9, 14, 15 | Reserved-member permissions are locked. Replace the obsolete custom-role mutation scenario with disabled/unchanged checkbox, localized lock notice, label/action/granted filtering and no-write assertions. | All four variants pass. |
| 10–15 | Exported Chinese HTML was delivered without a charset. Serve `text/html; charset=utf-8`; verify UTF-8 and locale on every fixture visit. | Chinese breadcrumbs, labels and search work. The recorded 366px grants overflow at 320px disappears with proper decoding. |
| 16, 20, 24, 28 | Obsolete two-form/return-URL expectations. Current AI/security each have one explicit Save form; email/SMS limits are platform-managed and have no editable form. | All four variants pass, including payload isolation and reload checks. |
| 17, 21, 25, 29 | Browser tenant had no available payment provider. Export current authorized responses after enabling Stripe availability and normal tenant provisioning in the separate test DB. | Toggle failure rollback, saved-connection success/error, unsaved draft retention, credential Save and mode navigation pass. |
| 18, 22, 26, 30 | Browser tenant had no customer-owned public Pages, so no picker mount existed. Export a normally validated public Page and its current settings response. | Search, invalid custom values, explicit Apply and instant preset Save pass. |
| 19, 23, 27, 31 | Personalization creation now mounts `email-template-token-bulk`; the old single-field controller/data mapping was obsolete. Exercise current groups, selection/count controls and serialized fields; export normal tenant user access. | All four variants pass, including retained dialog/error handling and a payload with exactly one reserved role. |

**Application source defects requiring changes: none found in this slice.** The changes are spec/helper corrections and authorized fixture expansion. Application ViewComponents, Stimulus source and page-template source were not edited. Template source was not inspected. The official shadcn table reference and frontend agent conventions were consulted while assessing the possible layout defect; correct decoding eliminated it, so a Tailwind layout change was unnecessary.

## Fixture preparation

The exporter used the existing dedicated `storage/e2e_settings_exports_final.sqlite3` database, normal signed-in tenant-admin requests, current factories, model validations and the payment provisioner. It generated **24** current JSON responses (12 states × two locales). No schema load/wipe or application-browser database fixture mutation was performed in this lane. Reserved roles remain owner/admin/member; grant guards were not unlocked.

```bash
env -u RUBYOPT \
  E2E_DATABASE_PATH=/home/ec2-user/anysys/storage/e2e_settings_exports_final.sqlite3 \
  DATABASE_URL=sqlite3:/home/ec2-user/anysys/storage/e2e_settings_exports_final.sqlite3 \
  RAILS_ENV=test APP_HOST=127.0.0.1 APP_PORT=3001 \
  EXPORT_CUSTOMER_SETTINGS_FIXTURES=tmp/playwright-customer-settings/fixtures \
  node spec/e2e/helpers/bootstrap.js export
```

Result: **14 RSpec examples, 0 failures**. Browser fixture requests resolve only to registered exported responses; all non-GET/HEAD requests, including intercepted errors and Saves, remain guarded at browser-context level.

## Final verification

```bash
source /tmp/opencode/browser-final.env
set -o pipefail
SETTINGS_BROWSER_ARTIFACTS=/tmp/opencode/settings-followup-shots \
PLAYWRIGHT_JSON_OUTPUT_NAME=/tmp/opencode/settings-followup.json \
  npx playwright test --config config/javascript/playwright.config.js \
  spec/e2e/customer_settings_support.js \
  spec/e2e/customer_settings_conditional.app.spec.js \
  spec/e2e/customer_settings_interactions.app.spec.js \
  spec/e2e/customer_settings_navigation.app.spec.js \
  --workers=4 --output=/tmp/opencode/settings-followup --reporter=list,json \
  2>&1 | tee /tmp/opencode/settings-followup.log
```

The support file is a helper, not an additional test file. The three spec files executed **20 conditional + 24 interaction + 20 navigation = 64 cases**. JSON start time: `2026-10-12T05:03:40.476Z`; duration: `1,012,785.818 ms` (16.9 minutes). The reporter records no global errors and no retries. `.last-run.json` says `passed` with `failedTests: []`.

Both locales and 320/390/768/1440px inventory/conditional layouts passed. Geometry assertions still verify document/main horizontal fit and visible controls before and after disclosures open. Native menu tests retain modal focus isolation, search, Escape/focus return and real destination navigation. Printable invoice downloads retain opt-in overflow expansion; ordinary settings do not receive it. All tests assert zero unexpected requests.

The inventory also found a stale crawler behavior beyond the original failure point: converting links to `a.pathname` dropped required billing `plan_code`. It now preserves all GET query inputs except the matrix locale, so actual plan review and sort URLs are verified rather than requesting a fabricated parameter-free endpoint. Visits wait for DOM/fonts and interactive controller readiness. Journey budgets cover actual multi-page work on the shared server (90s navigation, 120s interactions, 600s inventory), with no added retries or skips.

## Evidence

| Artifact | Location |
| --- | --- |
| Final 64 outcomes and timing | `/tmp/opencode/settings-followup.json` |
| Full final console | `/tmp/opencode/settings-followup.log` |
| Final runner state | `/tmp/opencode/settings-followup/.last-run.json` |
| Fresh screenshots and eight route inventories | `/tmp/opencode/settings-followup-shots/` |
| Current authorized responses | `tmp/playwright-customer-settings/fixtures/` |
| First follow-up, retained failed contexts/traces | `/tmp/opencode/settings-followup-baseline/`, `.json`, `.log` |
| Focused corrected 320px inventory + native-menu probe | `/tmp/opencode/settings-navigation-probe/`, `.json`, `.log` — 2 passed |

The first follow-up completed **47 passed / 17 failed** under concurrent browser lanes. It passed all conditional cases and 23/24 interaction cases; remaining failures exposed dropped GET queries and shared-server journey timing. That evidence remains preserved. The final complete settings run is the passing evidence above, rather than an aggregate of selective reruns.

The shared application (3001), local provider (3012), and Python static server (3011) were reused without stopping/restarting them. The browser environment's isolated DELETE-journal preload was retained. No application JavaScript changed, so this lane ran no Vitest or full RSpec suite. Targeted exporter and browser checks, plus `git diff --check` on the owned source, passed.
