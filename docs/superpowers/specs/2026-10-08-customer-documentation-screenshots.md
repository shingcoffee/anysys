# Customer documentation screenshots — capture handoff

- Date: 2026-10-08
- Status: **Complete — all 12 real PNGs captured and reviewed**
- Contract: [Customer documentation polish UX, section 6](2026-10-08-customer-documentation-polish-ux.md#6-screenshot-handoff--six-representative-captures-per-locale)
- Delivery: `public/help/docs/screenshots/{en,zh-CN}/*.png`

## Capture environment and authenticated role

Playwright Chromium captured the running Rails application at **1440 × 1500 CSS px**, 100% zoom, light appearance, **1× device pixel density**. Each output is a native browser screenshot clip; there is no compositing, redaction overlay, substituted text, fabricated control, or fabricated success state. Output dimensions equal crop dimensions. The tall viewport allows the complete payment configuration, saved-connection control, and Save changes button to appear together.

The capture server was an isolated development instance at **`http://127.0.0.1:3002`**, launched with **`SKIP_AUTH=0`**. Authentication used the real `/auth/sign_in` password form and Devise session, with the following disposable identity:

| Item | Actual value during capture |
| --- | --- |
| Customer | `68736490`, **Documentation Demo** |
| User | `17`, **Demo Administrator**, `docs-admin@example.test` |
| Reserved roles | Exactly `["admin"]` |
| Platform owner predicate | `false` |
| Owner-only endpoint check | Authenticated GET `/68736490/admin/maintenance/platform/developer_docs` with JSON Accept returned **403** |

The main server's `SKIP_AUTH` initializer chooses `current_user` before tenant extraction because `TenantContext#set_request_metadata` asks for it first. This can select the platform owner even for a different tenant URL. Therefore the main server was used only to verify public asset delivery, not to capture admin chrome.

Locales were selected through the **real language switcher**, which persisted the preference on this disposable admin and set the locale cookie. Each top-level source also includes `?locale=en` or `?locale=zh-CN`. Persisting the locale is important: the real Manage access Turbo-frame link omits the locale query and otherwise renders English for an admin without a language preference.

All captures have normal customer-visible controls. The workspace shows the demo identity; other crops omit unrelated shell chrome and retain the screen breadcrumb or the form drawer's own title and navigation. The Help action **Notify platform owner** is the actual customer action permitted by the UX specification. A platform announcement was dismissed through the real UI for this newly created admin before capture; announcement/private notification contents are absent from the delivered images. No owner identity, platform menu, flowchart tooling, credentials, card data, or recovery codes appears.

## Disposable demonstration setup and cleanup

Existing non-owner demo tenants were inspected first. None had a website, so a disposable customer was prepared using validated models and existing provisioners:

- `Customer.create!` created required authentication/email assignments and reserved roles. Authentication provisioning created a confirmed admin; a random temporary password was set only on this new account.
- Active **payment** and **website** module assignments were added only for this new customer.
- `FeatureModules::Payment::Provisioner.call` created eight disabled provider/environment rows with no credentials. The captured Stripe sandbox account was `22`.
- A valid unpublished `Website` row (`2`) was created using the existing **presence** catalog/theme and `Websites::Skeletons.apply!`, producing five unpublished pages. This reused the catalog without invoking a global catalog synchronization.
- `Entity.create!` created **Workshop registrations** (`37`), with Full name, Email, and Program fields and the normal version snapshot.
- Three `EntityEntry.create!` records contained only demonstration values: Alex Morgan / `alex@example.test`, Sam Chen / `sam@example.test`, and Jamie Lee / `jamie@example.test`; programs were Community workshop or Weekend workshop.
- `Page.new_with_defaults` created **Workshop registration** (`36`), bound to the new entity, with `launched: false` and `visibility: "admin"`.
- The email screenshot uses the existing new-list form with unsaved example input; no mailing list or send activity was created.

After capture and public-asset verification, the isolated server was stopped and **customer `68736490` plus all of its tenant rows were removed**. A database inspection across every table containing `customer_id` reported **zero remaining rows** for this customer. Existing tenant rows and existing user roles were not changed by the capture setup or cleanup.

The source URLs below are therefore **historical capture sources**, not retained demo navigation links. The PNG assets remain available independently of the disposable tenant. Temporary scripts and the capture report live under `/tmp/opencode/customer-doc-capture-*`; temporary password/session files were removed after cleanup. Recreating demonstration data will produce new IDs.

## Source URLs, locales, and measured crops

Source origin for every path in this table: **`http://127.0.0.1:3002`**. Crop coordinates are `(x, y, width, height)` in the original 1440 × 1500 CSS-pixel viewport. Files are under `public/help/docs/screenshots/<locale>/<basename>.png`.

| Locale | Basename | Source path | Crop | PNG dimensions |
| --- | --- | --- | --- | --- |
| en | `workspace-help.png` | `/68736490/admin/dashboard?locale=en` | `(0, 0, 1440, 404)` | 1440 × 404 |
| zh-CN | `workspace-help.png` | `/68736490/admin/dashboard?locale=zh-CN` | `(0, 0, 1440, 404)` | 1440 × 404 |
| en | `records-list.png` | `/68736490/admin/entities/37?locale=en` | `(304, 140, 1120, 484)` | 1120 × 484 |
| zh-CN | `records-list.png` | `/68736490/admin/entities/37?locale=zh-CN` | `(304, 140, 1120, 484)` | 1120 × 484 |
| en | `forms-publishing.png` | `/68736490/admin/pages?locale=en` → Manage access | `(928, 0, 512, 488)` | 512 × 488 |
| zh-CN | `forms-publishing.png` | `/68736490/admin/pages?locale=zh-CN` → 管理访问 | `(928, 0, 512, 455)` | 512 × 455 |
| en | `website-publishing.png` | `/68736490/admin/settings/modules/website/site?locale=en` | `(304, 140, 1120, 491)` | 1120 × 491 |
| zh-CN | `website-publishing.png` | `/68736490/admin/settings/modules/website/site?locale=zh-CN` | `(304, 140, 1120, 472)` | 1120 × 472 |
| en | `email-audience.png` | `/68736490/admin/modules/emails/lists/new?locale=en` | `(304, 140, 1056, 740)` | 1056 × 740 |
| zh-CN | `email-audience.png` | `/68736490/admin/modules/emails/lists/new?locale=zh-CN` | `(304, 140, 1056, 740)` | 1056 × 740 |
| en | `payment-settings.png` | `/68736490/admin/settings/modules/payments/merchant_accounts/22/edit?locale=en` | `(304, 140, 800, 1178)` | 800 × 1178 |
| zh-CN | `payment-settings.png` | `/68736490/admin/settings/modules/payments/merchant_accounts/22/edit?locale=zh-CN` | `(304, 140, 800, 1162)` | 800 × 1162 |

Both Manage access captures opened the actual Turbo-frame link **`/68736490/admin/pages/36`** from the localized list. The delivered crop is the real slide-over panel, including the form title, Preview/Close links, launch state, and all audience controls.

Deployed URLs are **`/help/docs/screenshots/<locale>/<basename>.png`**, without the `public` prefix.

## Actual state and content-lane caption guidance

| Subject | Actual captured state / fallback | Suggested English caption | Suggested Simplified Chinese caption |
| --- | --- | --- | --- |
| Workspace / Help | Primary: Home dashboard, Help open, Documentation visible; demo tenant with one entity, one page, four enabled modules, one admin. | Open Help to find Documentation and customer support actions. | 打开「帮助」，查看文档和客户支持入口。 |
| Records | Primary: three demo records; blank search; Columns and Export CSV visible; nothing selected. | Search records, choose visible columns, or export the list as CSV. | 搜索记录、选择显示列，或将列表导出为 CSV。 |
| Forms | Draft-form alternative: customer-owned form **not launched**; Admin always on; Member and Public unchecked. Launch is visible but was not clicked. | This form is not launched. Review launch status and audience controls before sharing it. | 此表单尚未上线。分享前，请先核对上线状态和访问范围。 |
| Website | Draft-site alternative: **Unpublished**; Make site public off; Save visible; public address explicitly not visible to visitors; View site disabled. | This website is unpublished. Review the publication switch and save your settings. | 此网站尚未发布。请核对公开开关，并保存设置。 |
| Email | **Permitted new-list fallback**, not the send wizard. Dynamic segment selected; example name **Workshop news / 工作坊通讯** and localized demo description entered; no conditions added; not saved; Preview and Create visible. No resolved recipients shown. | Start a dynamic email list, then add audience conditions and preview the matching subscribers. | 新建动态邮件列表，再添加受众条件并预览匹配的订阅者。 |
| Payments | Primary provider-edit screen: **Stripe**, **Test** sandbox row, **Disabled**, **Not configured**; merchant identifier and credentials blank; USD selected; Test saved connection and Save changes visible. No test/activation performed. | The Stripe test connection is disabled and unconfigured. Save credentials before testing the saved connection. | Stripe 测试连接已停用且未配置。请先保存凭据，再测试已保存的连接。 |

Demo tenant names, entity/form names, record data, and custom field labels are stored demonstration content, so they remain English in both captures. The existing Stripe gateway display name also remains **Credit / Debit Card (Stripe)** in the Chinese UI; surrounding environment labels, fields, status, and actions are genuinely localized. Captions should reflect those real screens rather than imply translated demo content or a successful configuration.

## Verification and release handoff

- All **12 PNGs** were opened and visually reviewed, including legible Chinese glyphs, actual drawer localization, complete controls, crops, and blank provider inputs.
- Browser captures returned **HTTP 200** for all six source surfaces in each locale; no JavaScript page errors were recorded in the final capture run.
- The authenticated admin session received **HTTP 403** from the owner-only documentation endpoint.
- A fresh unauthenticated Playwright request context retrieved all **12 deployed PNG URLs from `http://127.0.0.1:3000`** with **HTTP 200** and **`image/png`**. Response bytes matched the on-disk PNGs, and their measured PNG-header dimensions matched the table above.
- Rails inspection confirmed exactly the admin role, `platform_owner? == false`, the form/site still unpublished, and all eight provider rows disabled with empty credentials before cleanup.
- Capture work only added these PNGs and this handoff to the workspace. Temporary automation stayed in `/tmp/opencode`. The main server was not restarted. No application tests or asset rebuild were needed for this capture-only lane.
- **No capture failures remain.** Email intentionally uses the allowed new-list fallback; forms and website intentionally show the specified draft/unpublished alternatives.
