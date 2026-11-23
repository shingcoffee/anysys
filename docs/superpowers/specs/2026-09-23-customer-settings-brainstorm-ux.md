# Customer settings — customer mental model and UX brainstorm

Date: 2026-09-23

Scope: `/81721200/admin/settings` and every nested customer settings surface, including record details, forms, dialogs, provider environments, generic module configuration, and download/print states.

Stage: **READY_FOR_FRONTEND — brainstorming finalized, parent-approved.** Implementation plan: [Customer settings redesign](../plans/2026-09-23-customer-settings-redesign.md). No production implementation in this documentation pass.

Approved scope: preserve existing capabilities, module visibility and permission filters, including unknown future module contributions. The existing custom/multiple-role policy inconsistency is a recorded, non-blocking baseline. This UI task introduces no role types, grants, assignments, schema changes or authorization rewrite. The only planned backend behavior change is narrow preservation of omitted member visibility arrays during partial updates.

## 1. Decision

**Use a task-grouped settings workspace, with a shallow left navigation and one consistent content grammar throughout the nested pages.**

Customers arrive with questions: “What do members see?”, “Who can access this?”, “How do I receive payments?”, “How do I pay for this service?”, “How do I change my website?”, and “How do I control messages?” They should not need to know which module, schema, controller, or provider implementation owns a setting.

### Concepts considered

| Concept | Strength | Tradeoff | Decision |
| --- | --- | --- | --- |
| Module-first, renamed and polished | Familiar to existing users; mirrors today's registry | Still separates related access tasks and adds one-child expansion steps; customers must understand module boundaries | Reject as the organizing model |
| Flat, searchable settings directory | Fast when a user knows a setting's name; minimal hierarchy | Long menu, weak browsing/context, billing and collection easily confused | Use its direct-to-setting search behavior only |
| **Customer task groups + contextual detail pages** | Predictable browsing, clear money direction, durable deep-link context; works on small screens | Requires explicit display metadata and deliberate grouping of registry contributions | **Recommend** |

This is a navigation/display change over existing capabilities and routes. Group headings are not new landing routes. Specific records and form sections do not become global sidebar entries.

## 2. Evidence from the current app

Inspected the live local app using Chromium/Playwright with a request interceptor allowing **GET only**, blocking other methods and external requests. Visited the root and 44 linked settings destinations; then inspected seven representative pages at 1440×1000 and 390×844. Screenshots show the viewport of the existing internally scrolling shell. This is an owner-session usability observation, not proof of tenant-admin authorization or successful mutations.

| Observed issue | Evidence | Customer consequence |
| --- | --- | --- |
| Duplicate settings search and directory | Root screenshot has sidebar search and a second settings search above cards that repeat the sidebar | Two similar controls with different result presentations; wasted first-screen space |
| Cards hide their actual destination | `CatalogComponent#href_for`, lines 34–38, chooses the first child. The “User Authentication” card describes password reset/roles but goes directly to sign-up | Searching for a task can lead to a different task |
| One-child navigation expansion | Root has expandable AI Assistant, Captcha, Payments, SMS, Website parents | Extra clicks with no meaningful choice |
| Technical grouping/wording | Live “Member surfaces” → “Built-in / Modules / Entities”; “User Role Assignments”; “Forget password”; “Template tokens” | Users must translate implementation concepts before acting |
| Deep payment pages lose orientation | Provider list and Alipay edit have no content H1 or breadcrumb. On `/merchant_accounts/1/edit`, Payments is collapsed and no settings item is active | The provider, environment, and return location are hard to establish |
| One field consumes most of a page | Email cap screen uses separate large Status, Your Configuration, and Exit Landing Page cards; cap input spans almost the full content width | Scanning and editing a simple setting requires disproportionate space |
| Implementation details in forms | Email/SMS/AI show `{"kind":"route","name":"customer_home"}`. Member editor shows `Surface key: payments`, editable `credit_card`, and numeric navigation position | The form presents storage syntax as a customer decision |
| Permission display misrepresents effective access | Owner grants screen says full access but shows `0 / 412 granted`; admin shows raw subjects such as `admin/assistants` | Database grant counts are mistaken for effective permissions |
| Role policy mismatch | Live roles list offers “New Role”; assignment copy says “one or more roles”; one seeded user shows no roles. Project rules require exactly one of owner/admin/member | A wording-only redesign cannot settle the underlying contract |
| Money direction ambiguous | Root “Payment Method” says “collection methods”, while its page describes platform subscription fees; a separate Payments screen configures incoming payments | Customers may configure the wrong payment relationship |
| Weak customer names in secondary content | Captcha rows expose UUID-based page paths; token sources show model/attribute names; member rows include generated association names | Internal keys compete with useful page/field names |
| Mobile fits but remains laborious | Root and seven representative pages had no document/main horizontal overflow at 390px. Root's first viewport reaches billing but not module settings; member editor shows seven fields before visibility choices; grants toolbar is tall | Responsive stacking alone does not provide efficient mobile task completion |

Source anchors: `app/services/settings_contributor.rb`; `app/components/sidebar_{component,node_component}.{rb,html.erb}`; `app/components/admin/settings/catalog_component.{rb,html.erb}`; `app/views/admin/module_configs/show.html.erb`; `app/components/payments/admin/gateway_config_component.html.erb`; `app/components/admin/settings/member_surface_form_component.html.erb`; `app/components/admin/settings/modules/authentication/grants_editor_component.html.erb`.

Useful existing foundations: shared gray canvas/white surfaces/indigo selection; responsive shell and drawer; shared sidebar tree; reusable page, card, badge, alert, and form-error components; website theme preview and section links. Preserve the ongoing website work as the implementation baseline.

## 3. Recommended information architecture and bilingual labels

One settings search, Overview, then five task groups. Leaves navigate directly; only a real set of sibling destinations justifies nesting. On long menus, scroll the navigation independently with search pinned. Do not render chevrons for single-destination settings.

| Group (en / zh-CN) | Menu label (en / zh-CN) | Existing destination under `/81721200/admin/settings` |
| --- | --- | --- |
| — | Overview / 设置概览 | root |
| People & access / 用户与访问 | Member portal / 会员中心 | `/member` |
| | Member registration / 会员注册 | `/modules/authentication/sign_up` |
| | Password reset / 密码重置 | `/modules/authentication/forget_password` |
| | Account security / 账户安全 | `/modules/authentication` (existing generic configuration root) |
| | Roles & permissions / 角色与权限 | `/modules/authentication/roles` |
| | User access / 用户访问权限 | `/modules/authentication/user_role_assignments` |
| | Public page protection / 公开页面防护 | `/modules/captcha` |
| Website & tools / 网站与工具 | Website / 网站 | `/modules/website` |
| | AI assistant / AI 助手 | `/modules/ai_assistant` |
| Communication / 通信设置 | Email sending limit / 邮件发送限额 | `/modules/emails/daily_cap` |
| | Email personalization / 邮件个性化 | `/modules/emails/template_tokens` |
| | SMS sending limit / 短信发送限额 | `/modules/sms/daily_cap` |
| Receive payments / 收款设置 | Payment providers / 收款服务商 | `/modules/payments/merchant_accounts` |
| Subscription & billing / 订阅与账单 | Plan & subscription / 套餐与订阅 | `/billing/subscription` |
| | Billing payment methods / 账单付款方式 | `/billing/payment_methods` |
| | Invoices / 账单明细 | `/billing/invoices` |

“Receive payments” means money paid to the organization. “Subscription & billing” means the organization's service charges. Explain this once in group descriptions and on the relevant page; don't use the same generic “Payments” heading for both.

**Search behavior:** match authorized destinations by translated label, description, and curated familiar synonyms (e.g. captcha, tokens, merchant account). Results are individual destinations with group context, not a filtered parent card that silently opens its first child. Include nested settings sections using existing URLs plus anchors where appropriate. Use the same descriptor data for sidebar, overview, search, breadcrumbs, and ancestor-active matching. Do not index internal IDs or arbitrary record contents into settings navigation search.

**Overview:** compact group panels with task links and one-line explanations, two columns where space permits, single column on mobile. A group panel is not a giant link to a default child. Any status shown must come from an existing trustworthy readiness signal; don't invent setup percentages, “healthy” badges, or onboarding requirements. A customer can reach every leaf from here.

Account security matches the generic authentication root exactly; it must not also highlight on registration, password-reset, role or assignment pages. Deep pages select their most specific destination. Preserve availability/permission filtering before presentation and retain unmatched future contributions through readable fallback placement within Website & tools when no explicit group is known.

**Hierarchy examples:**

- Member portal → Record pages → Student profiles → Display settings. Existing source routes remain deep-linkable.
- Roles & permissions → Admin → Permissions. Readable role scope precedes capability detail.
- Email personalization → Add field / Edit field.
- Payment providers → Alipay → Test / Live. Provider environments remain separate existing records and links.
- Invoices → Invoice number → Download / Print. Invoice numbers are business references, not database IDs.

## 4. Layout sketches and common composition

### Desktop root

```text
Existing global header and admin navigation
┌──────────────────────────┬────────────────────────────────────────────────────┐
│ Settings                 │ Settings                                           │
│ [Search settings…]       │ Manage your organization's preferences.            │
│ Overview                 │                                                    │
│ PEOPLE & ACCESS          │ People & access         Website & tools            │
│ Member portal            │ Member portal       →   Website                →   │
│ Member registration      │ Member registration →   AI assistant           →   │
│ Password reset           │ Password reset      →                              │
│ Account security         │ Account security    →                              │
│ Roles & permissions      │ Roles & permissions →   Communication              │
│ User access              │ User access         →   Email sending limit    →   │
│ Public page protection   │ Public page protection→ Email personalization  →   │
│ WEBSITE & TOOLS          │                         SMS sending limit      →   │
│ …                        │ Receive payments        Subscription & billing     │
│                          │ Payment providers   →   Plan & subscription    →   │
│                          │                         Billing payment methods→   │
│                          │                         Invoices               →   │
└──────────────────────────┴────────────────────────────────────────────────────┘
```

### Nested edit page

```text
Settings / Payment providers / Alipay
Alipay                                  Test environment
Connect Alipay to receive payments for this organization.
[Test] [Live]                  (existing environment URLs)

┌ Connection details ───────────────────────────────────────┐
│ Merchant account number     [                             ]│
│ Private key                 [                             ]│
│ Saved credential state; blank keeps the current value.      │
│ [Test saved connection]  Result + last checked time, if known│
├ Payment preferences ──────────────────────────────────────┤
│ Default currency            [                             ]│
│ ▸ Additional connection options                            │
└───────────────────────────────────────────────────────────┘
                              [Cancel] [Save changes]
```

Provider terminology necessary to enter real credentials stays accurate. Internal merchant row IDs and seeded placeholders do not become customer labels or purported account numbers. If a saved value is a provisioning placeholder, the presenter must recognize it explicitly and show “Not configured”; it must not guess from arbitrary user values.

### Nested member editor

```text
Settings / Member portal / Record pages / Student profiles
Student profiles
Choose how this page appears in the member portal.

Visibility             [Visible to members]
Navigation             Display name / icon picker / position among named pages
List display           Records per page / visible columns
Record details         Sections with their nested field choices
Empty state            Heading / message
                       [Display preview] (settings-only preview, no member data)
                                      [Cancel] [Save changes]
```

### Composition rules for every nested page

1. One H1, meaningful subtitle, linked parent breadcrumb, selected ancestor in the sidebar. Group headings with no route are plain breadcrumb text.
2. A small status row next to the title when needed; status text distinguishes configured, enabled, unavailable, test, and live. Do not equate “enabled” with working.
3. Forms have a readable `max-w-3xl` content column; use wider space for provider lists, permissions, invoice detail, and website preview. Align content left within the existing shell rather than centering a small form in a large void.
4. Semantic fieldsets group related decisions; label, control, hint, and inline error travel together. Most fields are vertical; short paired fields can use two columns at sufficient available width.
5. One primary action **per actual save transaction**. Simple forms end with Cancel/Save changes. Long forms may have a sticky in-content action bar, with reserved bottom space. Never imply one atomic Save when separate endpoints can partly succeed.
6. Preserve independent actions such as connection testing, environment navigation, invoice download, and provider enablement. Clearly label immediate-save row controls; pending/error state belongs to the row. Do not mix invisible autosave with explicit Save on the same fields.
7. Advanced disclosure contains uncommon customer-configurable choices, not untranslated syntax. Destructive actions are distinct from routine form submission. Site replacement retains an explicit consequence summary and existing confirmation behavior.

## 5. Comprehensive nested-surface treatment

All rows below remain in the **Settings** navigation area (admin authorization). URL shorthand is relative to the root above. The parent's route inventory is the authoritative action-level coverage check; this UX matrix covers the discovered surface families rather than inventing record IDs for empty datasets.

| Surface / nested states | Right-content composition and retained capability |
| --- | --- |
| Root overview and search | Grouped task directory described above; search yields exact leaf/section links. No-results message and clear-search action. Module availability and current authorization drive all entry points consistently. |
| `/member` hub | Title “Member portal”; short explanation; compact summary of visible pages plus links to **Essential pages / 基础页面**, **Module pages / 模块页面**, **Record pages / 记录页面**. Existing source grouping remains accessible without terms “surface” or “schema”. A settings-only navigation preview helps explain ordering. |
| `/member/sources/builtin` | Home/Profile/Security in actual order; “Always available / 始终可用” with reason they cannot be hidden or reordered. Read-only state is neutral, not a warning card. |
| `/member/sources/modules` and `/entities` | Searchable name/visibility/action rows, sorted by effective navigation order; scope tabs are real links to existing source routes. Names use customer display labels; generated association labels resolve from named relationships. Keep every available row; missing display metadata needs a readable fallback, not suppression. |
| `/member/sources/:source/surfaces/:key` for module and entity pages | Shared form sketch above. Map `enabled`, `label`, `icon`, `subtitle`, `position`, `per_page`, `empty_headline`, `empty_body`, `visible_column_keys`, `visible_section_keys`, and `visible_detail_row_keys`. All existing visibility choices remain. Preserve required/locked columns. Use a visual icon selector backed by the existing allowed icon values; named placement controls preserve position behavior. Show fields under their sections rather than three unrelated checkbox walls. A preview must not broaden admin access to member records. |
| `/modules/authentication/sign_up` | Title “Member registration”; one status fieldset for enabled/disabled. Concise explanation of member registration and email confirmation. Expand “What changes when disabled” for existing confirmation/resend consequences. Explicit Save changes. |
| `/modules/authentication/forget_password` | Title “Password reset”; one enablement fieldset and short recovery-email explanation. Secondary detail explains current request/reset-link/sign-in behavior. Preserve enabled/disabled update behavior. |
| `/modules/authentication` | Title “Account security”; present all existing generic authentication configuration fields with customer labels and shared shell. Preserve submit semantics and return-URL override under Advanced. This is an existing destination, not a new security feature. |
| `/modules/authentication/roles` and `/:id` | Readable role directory and detail: role name, purpose, scope, assigned-user count, and effective capabilities. Replace raw key/system columns with meaningful scope. Owner is unrestricted; admin is organization-wide; member is self-only. Do not derive effective access from the count of stored permission rows. |
| `/roles/:id/grants`, filters, and review dialog | Title “Permissions”; readable scope summary and customer-named capabilities. Preserve current catalog, filters, edit/review/save/discard operations and read-only states. Replace raw controller subjects with meaningful labels without changing grants/catalog authorization or owner-authorized detail access. Existing role-policy mismatch is a baseline, not a layout blocker. |
| `/roles/new`, `/:id/edit`, existing delete action | **Inventory explicitly includes these existing surfaces.** Restyle current forms/actions without adding role types, novel custom-role affordances, removing capabilities or changing validation/policy. Record the existing inconsistency independently; do not repair or migrate roles in this task. |
| `/modules/authentication/user_role_assignments` and edit dialog | Title “User access”; name/email/current roles/actions. Dialog names the user and retains existing selection, submission, assignment/revocation behavior and guards. Do not change cardinality, seed assignments, normalize users, or alter authorization. Preserve existing owner restrictions. |
| `/modules/captcha`, per-page preset picker and custom inputs | Title “Public page protection”; readiness summary, search, page name/publication state, request limit and time-window controls. Preserve presets and custom limit/window updates and skip choices where supported. Page address becomes a named “Open page” link rather than a UUID string. Describe actual throttling, not a blanket promise of form security. Configuration-unavailable state explains next action without displaying provider credentials. |
| Email and SMS daily-cap routes; generic `/modules/email`, `/modules/sms` | Compact title/status, **Sending limit / 发送限额**, numeric field with unit and validated behavior. Do not invent daily usage or reset time not supplied by backend. Existing customer return-URL override stays in **After completion / 完成后跳转** disclosure, with a readable default destination plus custom URL choice. Preserve independent saves if configuration and override remain independent transactions. |
| `/modules/emails/template_tokens` | Title “Email personalization”; two sections **Built-in fields / 内置字段** and **Custom fields / 自定义字段**. Display business label, record type, field name, and appropriate edit/delete controls. Preserve built-in read-only availability and all custom mappings. Model/attribute identifiers remain values in the mapping, not visible names. Do not remove an authorized built-in field because its current label is technical; provide meaningful metadata. |
| `/template_tokens/new`, `/:id/edit`, delete | Title “Add personalization field” / “Edit personalization field”; Display name → Record type → Field. Preserve dependent attribute choices, validation and existing mapping semantics. Explain when recipient-linked values are available. No invented live recipient preview or new merge-token syntax. Cancel returns to the list; delete keeps its existing safeguards. |
| `/modules/payments/merchant_accounts` | H1 “Payment providers”, purpose “Receive payments from your customers”; clear environment context, provider name, enabled/configuration status, default where supported, Configure action. Customer-relevant capabilities such as cards/recurring/refunds may be secondary details; JSAPI/H5/webhook badge walls are removed from primary scanning. Preserve provider enable/disable and existing default selection, including state-dependent controls not visible in this seed. |
| `/merchant_accounts/:id/edit` for every provider × mode; any supported new/show states | Provider-named header, Test/Live links, real readiness status, dynamic credentials, currency, merchant identifier, optional callback override, test result, Save changes/Cancel. Keep every registered provider and vendor-specific field. Required customer integration details remain in readable connection sections; platform/global configuration does not migrate here. Testing must accurately state whether it uses saved or entered credentials; never show Verified from enablement alone. Preserve account-creation/provisioning affordances wherever the route inventory confirms them. |
| `/modules/ai_assistant` | Title “AI assistant”; language and recording duration with units. Preserve customer configuration and return destination override; keep model/provider/global prompts in Maintenance/Platform. No model selector is proposed. |
| `/modules/website` and supported site update aliases | Preserve current website work. Group sections into **General / 基本信息** (name/tagline), **Appearance / 外观** (theme/font/density/preview/default new-page layout), **Search & sharing / 搜索与分享** (SEO), **Footer / 页脚**, **Publishing / 发布**. Existing section anchors work; in-page tabs may reduce scrolling but retain draft state across panels and reveal validation errors in hidden panels. |
| Website footer repeaters, theme preview, publish control, starter replacement | Preserve add/edit/remove/reorder footer links/columns, all theme choices, default-layout selection, visibility and site preview. Customer links/URLs are real content, not internal keys. Place existing starter gallery behind a distinct “Replace website / 替换网站” disclosure or dialog with affected-page summary, separate from the routine form save. Do not rewrite prior website editor work or change replacement semantics in this brainstorm. |
| `/billing/subscription`, plan comparison, coupon, change/cancel states | Title “Plan & subscription”; current plan, price/interval, effective subscription state and applicable dates; compare plans below; coupon is a compact optional control. Preserve plan changes, coupon application and cancellation. State timing and price consequences from backend values; no invented immediate-effect promise. Cancellation is separate from routine actions. Seed's `prod` plan name and old trial-end date require accurate data/presentation, not a fabricated friendly price/plan. |
| `/billing/payment_methods`, add/authorize/default/remove flows | Title “Billing payment methods”; one-line explanation that these pay for the organization's subscription. Existing method cards show provider, safe account label, status/default and appropriate actions. Preserve external authorization/return, default selection and removal. Distinguish “No methods added” from “Payment setup unavailable”; only the former offers a working Add action. |
| `/billing/invoices`, `/:id`, download and print | List uses invoice number/date/amount/status/detail link. Detail uses invoice reference, period/due/paid dates, line items and totals; Download/Print in header. Keep list return and a readable print/download document. Empty invoices are neutral. Existing customer detail uses `platform: false`; owner viewing this customer path still gets customer actions, not platform mark-paid/retry/void. |
| Any generic module root/entry reached through registry or direct route | Explicitly retained in coverage: shared settings header, meaningful translated module/entry label, schema-backed fields, status and existing return override. Bind every authorized field/action to a customer label and task group; raw key fallback is a metadata gap to resolve. Do not silently drop an unrecognized module during IA grouping. |

## 6. Interaction and state contract

- **Find a setting:** root → search “password” → Password reset → change selection → Save changes → inline confirmation on that page. Invalid response keeps selection and shows linked summary/field errors.
- **Change member display:** Member portal → Record pages → named page → change navigation/list/detail settings → Save changes → same page with confirmation; Cancel returns to source list. Required content remains clearly marked. Settings-only preview can reflect unsaved display choices without fetching another member's data.
- **Connect a provider:** Payment providers → provider → chosen environment → credentials → save → test saved connection (if that is the existing endpoint contract). Failure preserves usable form state and distinguishes invalid credentials from unreachable service. Switching environment must not silently discard an edited form.
- **Personalize email:** Email personalization → Add field → choose record type → choose field → save → list with the new label. Missing/deleted field keeps the form and asks for a valid selection; it does not silently remap data.
- **Manage user access:** User access → named user's existing dialog → permitted selection under the current operation contract → save → updated row. Permission failure stays actionable, without claiming success or leaving optimistic role badges changed. Assignment/cardinality behavior remains unchanged.
- **Billing:** Plan & subscription → compare/apply coupon/change or cancel through existing operations. Billing payment methods → authorize provider → existing return handling → actual status. Invoice list → detail → download/print. No payment or mutation was executed during the UX inspection.

Shared states: use initial server-rendered content; show localized busy state only during an actual operation. An empty dataset gets a next step only when the user can perform it. Validation errors use summary plus field messages and focus the first invalid field; errors inside disclosures/tabs are revealed. Network/vendor failure retains draft values and offers retry. Authorization denial is a dedicated server-enforced state with a safe return link; never present an unauthorized record title. Successful saves announce an inline status. Avoid global toasts as the only feedback.

## 7. Mobile, accessibility, and owner context

- Desktop: one sidebar around 16rem, one main scroll region within the existing shell; no second navigation rail. Keep the current global app navigation vocabulary separate from settings task groups.
- Tablet: switch the settings rail to a sheet when available content width is insufficient for a readable form; recommend the full rail at `lg`, rather than forcing it at `md`. Verify at 768 and 1024 during implementation.
- Mobile: a visible **Settings menu / 设置菜单** trigger and current page name above content open the same searchable navigation sheet. Root gets the same search component inline; nested pages get it in the sheet. Only one active instance of settings search is shown in a given layout. Existing global hamburger remains the global-app entry point.
- Drawer traps focus, closes on Escape/navigation, restores trigger focus and marks the active destination. Avoid nested drawers. Use `w-full`, `min-w-0`, wrapping text, approximately 44px touch targets, and one-column fields; a small “On this page” disclosure replaces wide section strips.
- Stack list rows into labeled cards on small screens; retain all actions and all important data. Where invoice columns genuinely need horizontal scroll, confine it to a labeled table container. Sticky action bars must not cover controls, browser keyboard space, or the final field error.
- Use sentence case and descriptive customer nouns. Labels and hints use readable `text-text-secondary`, not very faint muted text for essential information. Name required/locked states in text, not color alone. All controls need visible labels, associated IDs, focus rings, and error descriptions.
- On `/81721200/admin/settings`, owner is acting on that organization's customer settings. Display the organization name for scope, not its numeric ID. Owner status does not turn this path into a platform configuration page.
- Global credentials, platform modules, internal diagnostics and flowchart tools remain on their existing authorized Maintenance/Platform surfaces. If a customer setting is blocked by platform setup, ordinary admins see a concise availability message and existing help path; owner may get a contextual link to the existing platform destination. Never duplicate the global form into customer Settings.
- Menu visibility is a usability projection, not an access policy. Preserve server-side admin/owner guards, current-tenant record scoping, fixed owner assignment, and member-only data rules. Shared-resource edits and overrides keep the existing path-based semantics.
- **Recorded baseline, not a blocker:** current custom/multiple-role UI conflicts with the project's role policy. Preserve existing role/controller capabilities without introducing role types, grants, assignments or novel custom-role affordances. Security review checks confirmed regressions against baseline; it does not initiate a cross-cutting authorization rewrite.

## 8. shadcn guidance → native app implementation map

Consulted official docs before proposing the design (official skill/MCP unavailable):

- [Sidebar](https://ui.shadcn.com/docs/components/sidebar): header/content/groups/menu/submenu, active state, mobile off-canvas composition.
- [Field](https://ui.shadcn.com/docs/components/field): semantic fieldsets/legends, label/control/description/error, vertical-first responsive orientation.
- [Tabs](https://ui.shadcn.com/docs/components/tabs): related alternate panels, line treatment, correct orientation and active state. Use ordinary links for different routes; tabs only for panels of the same task.

These are design/accessibility references. Deliver in **ViewComponent + Tailwind + Stimulus**, with Rails forms and existing route helpers.

| Design responsibility | Existing reuse | Small proposed abstraction if needed |
| --- | --- | --- |
| Shell, grouped menu, mobile sheet | `ShellComponent`, `SidebarComponent`, `SidebarNodeComponent`, `DrawerComponent`; `SettingsContributor` and shared tree | Settings-specific descriptor metadata for labels/group/ancestor matching/search synonyms; avoid parallel hard-coded route catalogs |
| Header, breadcrumbs, page widths | `AdminPageComponent`, `BreadcrumbsComponent` | `Admin::Settings::PageComponent(customer_id:, title:, description: nil, breadcrumbs: [], actions: [], badges: [], width: :wide)` wraps AdminPageComponent, prepends a linked Settings root crumb and owns width |
| Overview links and search results | `Admin::Settings::CatalogComponent`, existing `list-filter` logic | Refactor catalog to exact-destination rows using the same descriptors |
| Section structure | Rails form builders, `FormErrorsComponent` | `Admin::Settings::SectionComponent(title: nil, description: nil, id: nil)` uses flat whitespace/hairlines; optional Advanced disclosure uses local native `details` |
| Fields, save scope and feedback | `.form-label`, `.input-field`, shared font/input/button tokens, `ButtonComponent`, `AlertComponent`, `BadgeComponent` | Avoid Field/FormActions abstractions unless genuine need emerges; explicit actions per actual operation |
| Domain screens | Existing member form/source/hub, grants editor/user-role table/token form/captcha status and throttle components; payment gateway/credential/test result components; billing payment-method/invoice components; website settings/theme/starter components | Compose/refine in place; no replacement domain engine |
| Tables | `AdminTableComponent`, `Admin::CardTableComponent`, existing domain tables | Responsive row presentation preserving the same columns/actions |

Tailwind: use existing `bg-canvas`, `bg-surface`, `border-border-subtle`, `text-text-primary`, `text-text-secondary`, `bg-accent-subtle`, `text-accent-text`, `rounded-xl`; `p-4 sm:p-6`, `gap-4 lg:gap-6`, `w-full max-w-3xl`, wider list containers. Account for this project's smaller admin type scale (`text-base` is 14px). Avoid excessive nested card borders and colored icon tiles as the sole grouping cue.

Final composition: muted neutral design with flat whitespace and hairlines. Existing return-route overrides remain accessible in plain-language **Advanced / 高级设置** disclosure, with URL input and explicit per-operation save; never render raw JSON. Use wide Page wrapper with readable inner form widths. The approved plan governs implementation scope; previews/icon selectors are optional presentation refinements, not additional backend features.

Stimulus: reuse drawer, list filter, dependent token selects, provider test, captcha picker, grant review, payment-method and website controllers. Any future changes to search, dirty state, tabs or icon picker need localized Stimulus Values and the project's real JS coverage checks. No JavaScript or production tests are changed in this brainstorming pass.

Every displayed string—including status explanations, empty/error text, accessibility labels and search synonyms—must be I18n-backed with en/zh-CN parity. Proposed menu translations above are the naming baseline. Customer-entered names are content; generated/system labels need translated presentation metadata. Internal IDs/slugs stay in route parameters/form values, not customer wording.

## 9. Handoff completeness

**READY_FOR_FRONTEND.** Parent approved the five groups, existing Account security root, stable Page/Section APIs and scoped responsibilities. The implementation plan defines six parallel lanes and targeted verification. Preserve existing route/action coverage, conditional states and ongoing website edits. The role-policy baseline does not block layout work. No further confirmation is required.

Local evidence: `/tmp/opencode/settings-ux-brainstorm-2026-09-23.cjs`; screenshots `/tmp/opencode/settings-ux-2026-09-23-81721200-admin-settings*-desktop.png` and `*-mobile.png`. Observed forms/statuses were read, not submitted; mutation success, error behavior, tenant-admin views, and Chinese layout still require later implementation verification.
