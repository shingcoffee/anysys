# Speech-to-text dual-job providers — UX spec

Date: 2026-09-04
Audience: frontend developer. Implement ViewComponent + Tailwind only. There is no React shadcn in the runtime.

Follows: `docs/stt-dual-job-providers-design.md` (locked), `docs/stt-dual-job-providers-plan.md`.

Visual language: match the current Speech-to-text platform settings card and the Captcha sibling
(`app/components/admin/maintenance/platform/speech_to_text/settings_component.html.erb`,
`app/components/admin/maintenance/platform/captcha/settings_component.html.erb`).
Use `card`, `card-header`, `section-header`, `form-label`, `input-field`, `text-body`,
`text-body-sm`, `text-caption`, `text-text-primary`, `text-text-secondary`, `text-text-muted`,
`divide-y divide-border-subtle`, and the existing 12rem definition-list grid.

shadcn analog (mental map only — do not add shadcn JS): Card + Field / FieldSet + Select + Checkbox + Badge + Tabs.
Deliver those as the existing platform cards, native `<input>` / `<select>`, and `BadgeComponent` / `ProviderSwitcherComponent`.

All new copy: I18n `en` + `zh-CN`. English value = the string that would otherwise have been hard-coded.
Never bake `t()` into a Ruby constant.

Do **not** restyle the dictate widget or the dashboard assistant offline state.
Do **not** add a Stimulus controller. Cursor models are a server-rendered `<select>` from the cached list.

---

## 1. Surface inventory

| # | Surface | Nav area | URL | Audience | Change |
|---|---|---|---|---|---|
| A | Speech to text platform settings — **show** | Maintenance / Platform / Module Settings | `GET /:cid/admin/maintenance/platform/module_settings/speech_to_text/settings` (`?provider=` optional) | `owner` on customer `81721200` | Dual job groups on every vendor card; status strip lists both assignees; Cursor tab |
| B | Speech to text platform settings — **edit** | same | `GET …/settings/edit?provider=` and `PATCH …/settings?provider=` | same | Replace the single “Make this the active provider” card with two job groups; job-owned model fields move into those groups |
| C | Speech to text module-settings landing | Maintenance / Platform / Module Settings | `GET /:cid/admin/maintenance/platform/module_settings/:id` (numeric id, e.g. `/module_settings/7` when that row is `speech_to_text`) | same | **No visual change.** Existing `SettingsLinkCardComponent` still links into A |
| D | Dictate widget | admin (entity fields + dashboard composer) | existing `DictateFieldComponent` hosts | `admin` / `owner` | **No visual change.** Widget already hides when ineligible; eligibility will key off a transcribe assignee (component Ruby, not a new layout) |
| E | Dashboard assistant offline | admin dashboard | existing `Admin::Dashboard::WorkspaceComponent` | `admin` / `owner` | **No visual change.** Offline state already exists; `assistant_available?` keys off a generation assignee (controller, not this UI) |

Out of scope (no new surfaces, no restyle):

- Settings / Speech to text (tenant language + duration)
- Maintenance / Modules enable-disable row
- Member or public pages
- Tenant credential/model overrides
- Live OpenAI model lists

Module URL mapping (AGENTS.md four areas):

- **Modules / Speech to text** — empty; no entries table
- **Settings / Speech to text** — unchanged tenant config
- **Maintenance / Modules** — existing enable/disable; no change
- **Maintenance / Platform / Module Settings** — surfaces A–C

---

## 2. Layout spec

### Shared chrome (A + B — already built, do not restyle)

`app/views/admin/maintenance/platform/speech_to_text/settings/{show,edit}.html.erb` keep
`AdminPageComponent`:

```
[ Maintenance / Module Settings / Speech to text / Settings ]

[ {provider display_name}                              [ Edit ] ]   ← Edit only on show
[ Platform-wide provider credentials used by every tenant.      ]

[ SettingsComponent body ]
```

- Title = current tab’s `display_name` (falls back to `speech_to_text.platform_settings.title`).
- Description = existing `page_description`.
- Show actions: existing primary Edit button (`speech_to_text.platform_settings.edit`).
- Edit: no header actions; Cancel / Save stay at the bottom of the form.

### Shared body stack (A + B)

Outer wrapper stays `flex flex-col gap-6`.

```
┌─ ProviderSwitcher (4 tabs) ─────────────────────────────────────┐
│ OpenAI Whisper [Active] │ AWS Transcribe │ Aliyun │ Cursor      │
└─────────────────────────────────────────────────────────────────┘

┌─ ProviderStatusStrip ───────────────────────────────────────────┐
│ Connection [badge]   This provider [Assigned|Not assigned]      │
│ Assignees  {transcribe name} · {generation name}                │
│                                              [ Test connection ]│  ← show only
└─────────────────────────────────────────────────────────────────┘

[ AlertComponent ]   ← only when errors.any?

┌─ Credentials ───────────────────────────────────────────────────┐
│ unchanged: api_key + vendor credential-like fields              │
└─────────────────────────────────────────────────────────────────┘

┌─ Configuration ─────────────────────────────────────────────────┐
│ leftover option fields only (Organization, Region, App Key, …)  │
│ hide the whole card when the leftover list is empty             │
└─────────────────────────────────────────────────────────────────┘

┌─ Jobs ──────────────────────────────────────────────────────────┐
│ ALWAYS two groups, in this order, on every vendor               │
│  1. Audio Transcribe                                            │
│  2. Entity/Flowchart generation                                 │
└─────────────────────────────────────────────────────────────────┘

[ Cancel ] [ Save ]   ← edit only
```

### Provider switcher

Reuse `ProviderSwitcherComponent` unchanged.

Tab order is registry order. After Cursor is registered the fourth tab is **Cursor**.
Do not hard-code four names in the ERB — keep `switcher_items` from `providers`.

| Item field | Rule |
|---|---|
| `name` | `pc.display_name` (OpenAI Whisper, AWS Transcribe, Aliyun, Cursor) |
| `path` | `…/settings?provider={key}` |
| `current` | tab being viewed (`settings.provider`) |
| `active` | **true if that vendor is assigned to either job** (transcribe **or** generation). Two tabs may show Active at once |

Existing switcher chrome: underline tab, `aria-current="page"` on current, `BadgeComponent` `:success` “Active” on `sm+`, green dot on mobile. Do not invent a second badge for “which job”.

### Status strip

Reuse `ProviderStatusStripComponent` unchanged. Only the values passed in change.

| Slot | Caption (en) | Value |
|---|---|---|
| Health | `Connection` (existing) | Existing health badge for **this** vendor’s last check. Variants unchanged (`ok` success, `configuration_error` danger, `unreachable` warning, else default) |
| This provider | `This provider` (existing) | **Assigned** (`BadgeComponent` `:success`) if `transcribe_active? \|\| generation_active?` on the viewed row; otherwise **Not assigned** as `text-body-sm text-text-secondary` |
| Assignees | **Assignees** (replaces “Active provider”) | Always two slots, transcribe first: `{transcribe display_name} · {generation display_name}`. Missing slot = `common.labels.em_dash` (`—`). Both missing = a single `—` (do not print `— · —`) |

Trailing slot (show only): existing Test connection `ButtonComponent` `:secondary` `:sm`. Edit has no Test button (same as today).

Drop `active_key` / `active_provider_name` / `enabled?`. The component receives (or derives):

- `transcribe_key` — `ProviderSettings.active_for(:transcribe)&.provider`
- `generation_key` — `ProviderSettings.active_for(:generation)&.provider`

`switcher_items[].active` is true when `pc.key` equals either of those keys.

### Credentials card — unchanged

Same card as today:

- Header: `Credentials` + existing show/edit hints.
- Rows: encrypted `api_key`, then `credential_config_fields` (password-type or name matching `CREDENTIAL_FIELD`).
- Show: mask or em dash. Edit: password inputs, keep-existing placeholder, never echo secrets.

Do not move Organization, Region, or job models into this card.

### Configuration card — leftover options only

Same card chrome as today (`Configuration` + existing hint).

`option_config_fields` **minus job-owned names**. Job-owned (render inside Jobs, never here):

- `model` — OpenAI Audio Transcribe
- `chat_model` — OpenAI / Cursor Entity/Flowchart generation

Examples:

| Vendor | Stays in Configuration |
|---|---|
| OpenAI Whisper | `organization` only |
| AWS Transcribe | `region` |
| Aliyun | `app_key`, `region` (same as today’s option split) |
| Cursor | none → **omit the Configuration card** |

Organization is a general OpenAI option. It is **not** inside a job group.

### Jobs card (new — replaces “Make this the active provider”)

One card. Always two groups. Never omit a group. Never render the old `make_active` / `enabled` row.

Card header:

- Title: `Jobs`
- Hint: `Assign each job to at most one provider. A provider can hold both jobs.`

Body: `ul.divide-y divide-border-subtle` with exactly two `li`s.

#### Supported job (show)

Definition-list rows, same 12rem grid as credentials:

```
┌─ Jobs ──────────────────────────────────────────────────────────┐
│ Jobs                                                            │
│ Assign each job to at most one provider. A provider can hold    │
│ both jobs.                                                      │
├─────────────────────────────────────────────────────────────────┤
│ Audio Transcribe                                                │
│ Assignment          [Assigned]           ← BadgeComponent success│
│ Model               whisper-1            ← only if this job has  │
│                                            a model field         │
├─────────────────────────────────────────────────────────────────┤
│ Entity/Flowchart generation                                     │
│ Assignment          [Assigned]                                  │
│ Chat model          gpt-4o-mini                                 │
└─────────────────────────────────────────────────────────────────┘
```

If the job is supported but not assigned: Assignment value is `Not assigned` as `text-body-sm text-text-secondary` (same treatment as the status-strip inactive role — no badge).

AWS / Aliyun Audio Transcribe: heading + Assignment row only. **No fake model row.**

#### Supported job (edit)

Match the retired make-active row: heading + hint on the left, checkbox on the right (`flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between`). Model field (when any) is a second row under that heading using the existing `form-label` + `input-field` 12rem grid.

```
┌─ Jobs ──────────────────────────────────────────────────────────┐
│ Audio Transcribe                                    [ x ]       │
│ Assign this provider to Audio Transcribe                        │
│ Model                                           [ whisper-1   ] │
├─────────────────────────────────────────────────────────────────┤
│ Entity/Flowchart generation                         [ x ]       │
│ Assign this provider to Entity/Flowchart generation             │
│ Chat model                                      [ gpt-4o-mini ] │
└─────────────────────────────────────────────────────────────────┘
```

Checkbox pattern (same as today’s `enabled`):

```
<input type="hidden" name="…[transcribe_active]" value="0">
<input type="checkbox" name="…[transcribe_active]" value="1" …>
```

and the same pair for `generation_active`.

- Visible label / `sr-only`: `Assign this provider to Audio Transcribe` / `Assign this provider to Entity/Flowchart generation`.
- Checkbox classes (existing): `h-4 w-4 rounded border-border-subtle text-accent focus:ring-accent`.
- OpenAI `model` / `chat_model`: free-text `<input type="text" class="input-field">`, names `speech_to_text_provider_settings[model]` and `[chat_model]`, values via existing `#field_value` (stored or provider default).
- Cursor `chat_model`: native `<select class="input-field">` (same as Captcha fail-policy). Options from cached `config_json["generation_models"]` (`id` + `display_name`). Selected = stored `chat_model`. First option `value=""` labeled `Cursor default` (blank means omit model so Cursor uses its default). If the stored id is not in the cache, still emit it as a selected `<option>` so Save does not clobber it.
- Cursor cache empty: **no `<select>`**. Caption only: `Save credentials first. Models load after Test connection.` (`text-caption`). Do not fetch in the browser.

#### Unsupported job (show and edit)

Same group heading. Explicit copy. No checkbox, no hidden `*_active` inputs, no model input.

```
│ Entity/Flowchart generation                                     │
│ Not supported                                                   │
```

`Not supported` is `text-caption` (muted). Do not use a danger badge — this is capability, not an error.

Capability matrix (every card still shows both headings):

| Provider | Audio Transcribe | Entity/Flowchart generation |
|---|---|---|
| OpenAI Whisper | supported — checkbox + `model` | supported — checkbox + `chat_model` text |
| AWS Transcribe | supported — checkbox, no model | **Not supported** |
| Aliyun | supported — checkbox, no model | **Not supported** |
| Cursor | **Not supported** | supported — checkbox + cached `<select>` (or empty caption) |

### Empty / loading / error

| State | Treatment |
|---|---|
| Empty credentials | Existing em dash / blank password. No extra empty card |
| Empty leftover Configuration | Hide the Configuration card |
| Empty Cursor model cache | Caption in the generation group (edit and show). Not a spinner, not JS |
| Page loading | Server-rendered. No skeleton |
| Test connection | Existing flash `Connection test queued. Refresh this page shortly for the result.` Health badge updates after refresh. Cursor model list appears on the next show after the job writes the cache (successful Cursor Save also enqueues that job — still no in-page poll) |
| Validation / contract errors | Existing `AlertComponent` `type: :error` above the cards; stay on edit |
| Permission denied | Existing platform-owner gate. No new UI |
| Vendor down | Health badge `unreachable` / `configuration_error`. No modal |

### Primary / secondary / destructive

| Action | Where | Control |
|---|---|---|
| Edit | Show page header | `ButtonComponent` primary (existing `AdminPageComponent` action) |
| Test connection | Status strip, show only | `ButtonComponent` secondary sm, POST |
| Save | Edit footer, right | `ButtonComponent` primary md, submit |
| Cancel | Edit footer, left of Save | `ButtonComponent` secondary md, link back to show `?provider=` |
| Assign job | Jobs card, edit | Checkbox (not a button) |

No destructive action on this surface.

### Show variants (ASCII)

#### OpenAI Whisper — both jobs assigned, health OK

```
OpenAI Whisper [Active]   AWS Transcribe   Aliyun   Cursor
──────────────

Connection [Last check: OK]   This provider [Assigned]
Assignees  OpenAI Whisper · OpenAI Whisper          [ Test connection ]

┌ Credentials ──────────┐
│ API Key     ••••••    │
└───────────────────────┘

┌ Configuration ────────┐
│ Organization  org_123 │   ← or —
└───────────────────────┘

┌ Jobs ─────────────────┐
│ Audio Transcribe      │
│ Assignment  [Assigned]│
│ Model       whisper-1 │
│───────────────────────│
│ Entity/Flowchart      │
│   generation          │
│ Assignment  [Assigned]│
│ Chat model  gpt-4o-mini│
└───────────────────────┘
```

#### AWS Transcribe — transcribe assigned, generation unsupported; OpenAI holds generation

```
OpenAI Whisper [Active]   AWS Transcribe [Active]   Aliyun   Cursor
                          ──────────────  (current tab)

Connection [Last check: OK]   This provider [Assigned]
Assignees  AWS Transcribe · OpenAI Whisper          [ Test connection ]

┌ Credentials ──────────────────┐
│ Secret Access Key   ••••••    │
│ Access Key ID       AKIAxxxx  │
└───────────────────────────────┘

┌ Configuration ─┐
│ Region  us-east-1 │
└────────────────┘

┌ Jobs ─────────────────┐
│ Audio Transcribe      │
│ Assignment  [Assigned]│
│───────────────────────│
│ Entity/Flowchart      │
│   generation          │
│ Not supported         │
└───────────────────────┘
```

Aliyun show is the same Jobs shape as AWS (transcribe checkbox/assignment, generation “Not supported”). Credentials/config rows follow today’s Aliyun fields.

#### Cursor — generation assigned, transcribe unsupported; models cached

```
OpenAI Whisper [Active]   AWS Transcribe   Aliyun   Cursor [Active]
                                                    ──────  (current)

Connection [Last check: OK]   This provider [Assigned]
Assignees  AWS Transcribe · Cursor                  [ Test connection ]

┌ Credentials ──┐
│ API Key  •••••• │
└───────────────┘
  (no Configuration card)

┌ Jobs ─────────────────┐
│ Audio Transcribe      │
│ Not supported         │
│───────────────────────│
│ Entity/Flowchart      │
│   generation          │
│ Assignment  [Assigned]│
│ Chat model  Composer  │  ← display_name from cache, else stored id
└───────────────────────┘
```

#### Cursor — credentials saved, cache still empty

Same Jobs headings. Generation Assignment reflects the flag. Chat model value is the stored id or `—`. Caption under the value: `Save credentials first. Models load after Test connection.`

#### Neither job assigned (any vendor)

Status strip: This provider `Not assigned`. Assignees `—` if both platform jobs are empty, otherwise the other vendor’s name plus `—` for the empty slot.

Switcher: no Active badge on this tab.

### Edit variants (ASCII)

#### OpenAI edit

```
… switcher + status strip (no Test connection) …

┌ Credentials ─ password api_key, keep-existing … ─┐
└──────────────────────────────────────────────────┘

┌ Configuration ───────────────────────────────────┐
│ Organization   [ org_123                      ]  │
└──────────────────────────────────────────────────┘

┌ Jobs ────────────────────────────────────────────┐
│ Audio Transcribe                          [ x ]  │
│ Assign this provider to Audio Transcribe         │
│ Model          [ whisper-1                    ]  │
│──────────────────────────────────────────────────│
│ Entity/Flowchart generation               [ x ]  │
│ Assign this provider to Entity/Flowchart         │
│   generation                                     │
│ Chat model     [ gpt-4o-mini                  ]  │
└──────────────────────────────────────────────────┘

                              [ Cancel ]  [ Save ]
```

#### AWS edit (Aliyun is the same Jobs shape)

```
┌ Jobs ────────────────────────────────────────────┐
│ Audio Transcribe                          [ x ]  │
│ Assign this provider to Audio Transcribe         │
│   (no model field)                               │
│──────────────────────────────────────────────────│
│ Entity/Flowchart generation                      │
│ Not supported                                    │
└──────────────────────────────────────────────────┘
```

#### Cursor edit — cache populated

```
┌ Jobs ────────────────────────────────────────────┐
│ Audio Transcribe                                 │
│ Not supported                                    │
│──────────────────────────────────────────────────│
│ Entity/Flowchart generation               [ x ]  │
│ Assign this provider to Entity/Flowchart         │
│   generation                                     │
│ Chat model     [ Cursor default            ▾ ]  │
│                [ Composer                    ]  │
│                [ …cached models…             ]  │
└──────────────────────────────────────────────────┘
```

#### Cursor edit — cache empty

```
┌ Jobs ────────────────────────────────────────────┐
│ Audio Transcribe                                 │
│ Not supported                                    │
│──────────────────────────────────────────────────│
│ Entity/Flowchart generation               [ x ]  │
│ Assign this provider to Entity/Flowchart         │
│   generation                                     │
│ Save credentials first. Models load after        │
│ Test connection.                                 │
└──────────────────────────────────────────────────┘
```

Responsive: tabs `flex-wrap`; status strip `flex-col` then `lg:flex-row`; credential/job rows `grid-cols-1` then `sm:grid-cols-[12rem_minmax(0,1fr)]`; job checkbox stacks under the heading on mobile (`flex-col` / `sm:flex-row`). Inputs `w-full max-w-xl`.

---

## 3. Interaction flow

Start URL unless noted: `GET /81721200/admin/maintenance/platform/module_settings/speech_to_text/settings`.

### View a vendor (happy)

1. Owner opens C (`/module_settings/7` or the `speech_to_text` module-settings show) → clicks the existing credentials link.
2. Lands on A for the default/fallback provider. Switcher shows four tabs. Active badges mark whoever holds transcribe and/or generation.
3. Clicks **Cursor** → `GET …/settings?provider=cursor`. Title becomes Cursor. Jobs show transcribe “Not supported” and the generation group.
4. Clicks **Edit** → B `…/settings/edit?provider=cursor`.

### Assign mixed vendors (happy)

1. On AWS edit: check Audio Transcribe, leave generation as “Not supported”. Save.
2. `PATCH` succeeds → redirect show `?provider=aws_transcribe`, flash `Speech to text settings updated.`
3. Status strip Assignees: `AWS Transcribe · {existing generation name or —}`. AWS tab Active. Previous transcribe holder loses Active unless it still holds generation.
4. On Cursor edit: check Entity/Flowchart generation, pick a cached model (or leave Cursor default). Save.
5. Assignees become `AWS Transcribe · Cursor`. Dictate keeps working (transcribe still AWS). Dashboard assistant uses Cursor (controller).

### Assign both jobs to OpenAI (happy)

1. OpenAI edit: check both boxes, keep/edit `model` and `chat_model`, Organization stays in Configuration. Save.
2. Assignees: `OpenAI Whisper · OpenAI Whisper`. Only the OpenAI tab is Active.

### Cursor models after first credentials save

1. Owner pastes API key on Cursor edit, checks generation, Save (cache empty — no select).
2. Redirect to show + updated flash. Backend enqueues `TestConnectionJob` after a successful Cursor save.
3. Existing queued flash may also appear if they clicked Test connection. Owner refreshes.
4. Cache filled → show lists `display_name`; next edit shows the `<select>`.

### Test connection

1. Show → Test connection → POST → redirect show + `Connection test queued…`
2. Refresh: health badge updates. Cursor: model list may now populate. No in-page spinner.

### Validation error

1. Edit Save with blank required credential (or a crafted unsupported-job assignment).
2. Stay on edit, `422`, `AlertComponent` with contract messages (`API Key can't be blank.`, `Unknown speech-to-text provider.`, field-blank, unsupported-job rejection).
3. Jobs card still shows both groups. Unsupported groups still have no checkbox.

### Permission denied

1. Non-owner hits A/B → existing platform authorization (redirect / 403). No extra flash UI in this component.

### Vendor down / bad credentials

1. Test connection or later health job → badge `Last check: 4xx — check credentials` or `Last check: unreachable`.
2. Assignment checkboxes are independent of health. Owner can still assign; runtime fail-closes as today.

### Unassign a job

1. Uncheck the job on the assignee’s edit form. Save.
2. That slot becomes `—` in Assignees. If the vendor holds no remaining job, its tab loses Active and This provider becomes Not assigned.

### Dictate (unchanged chrome)

1. Admin opens a dictate host. If no transcribe assignee (or module off), `DictateFieldComponent` hides the mic and still renders the input.
2. If a transcribe assignee exists, the existing mic UI is unchanged.

### Dashboard assistant (unchanged chrome)

1. Module on + generation assignee → existing assistant panel.
2. Otherwise → existing offline block (`Enable Speech to text and configure a provider…` + Open modules). No new dashboard layout.

---

## 4. Component reuse map

| Piece | Reuse / new |
|---|---|
| Page chrome, breadcrumbs, Edit | Existing `AdminPageComponent` in show/edit views — **no restyle** |
| Module-settings landing link | Existing `Admin::Maintenance::Platform::SettingsLinkCardComponent` — **no change** |
| Provider tabs | Existing `Admin::Maintenance::Platform::ProviderSwitcherComponent` — **no API change**; `active` means either-job |
| Health / role / assignees | Existing `Admin::Maintenance::Platform::ProviderStatusStripComponent` — **no API change**; pass new strings/values |
| Errors | Existing `AlertComponent` `type: :error` |
| Edit / Save / Cancel / Test | Existing `ButtonComponent` (primary / secondary, sizes as today) |
| Active / Assigned / health | Existing `BadgeComponent` (`:success`, `:danger`, `:warning`, `:default`, `size: :sm`) |
| Credentials + leftover Configuration | Stay inside `Admin::Maintenance::Platform::SpeechToText::SettingsComponent` ERB — same `card` / `form-label` / `input-field` rows |
| Jobs card | **Same** `SettingsComponent` ERB (no new ViewComponent). Prefer this over a `JobGroupComponent` unless the template becomes unreadable |
| Cursor model list | Native `<select class="input-field">` — same pattern as Captcha `fail_policy`. Empty cache = caption, not a component |
| Dictate | Existing `SpeechToText::DictateFieldComponent` — **no visual change** |
| Dashboard offline | Existing `Admin::Dashboard::WorkspaceComponent` branch — **no visual change** |

Do **not** add React, shadcn runtime, or a new Stimulus controller.

### SettingsComponent helpers the frontend should grow (no new public UI)

Keep `PARAM_KEY`, credential split, paths, health helpers.

Replace single-active helpers:

| Remove from template | Use instead |
|---|---|
| `enabled?` + `[enabled]` | `transcribe_active?` / `generation_active?` on `settings` |
| `active?` via `active_key` | `assigned?` = either flag on the viewed row |
| `active_provider_name` | `assignees_value` = `transcribe · generation` or `—` |
| `option_config_fields` as-is | leftover options: reject `:model` and `:chat_model` |

Read Cursor cache with `settings.config_value(:generation_models)` (array of `id` / `display_name`). Do not call Cursor HTTP from the component.

Controller/security (not this ERB) must pass `transcribe_key` and `generation_key` instead of a single `active_key`, and permit `transcribe_active` / `generation_active` instead of `enabled`.

---

## 5. Tailwind & Stimulus notes

### Tailwind / existing utilities

- Stack: `flex flex-col gap-6` (outer and edit form). Footer `flex items-center justify-end gap-3 pt-1`.
- Cards: `card overflow-hidden`, `card-header`, `section-header`, `mt-0.5 text-caption`.
- Rows: `px-4 sm:px-6 py-3` (show) / `py-4` (edit), `divide-y divide-border-subtle`.
- Label/value grid: `grid grid-cols-1 gap-1 sm:grid-cols-[12rem_minmax(0,1fr)] sm:items-baseline sm:gap-6` (show); edit uses `gap-2` and `sm:items-start`.
- Inputs: `input-field` inside `w-full max-w-xl`.
- Job header row: `flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between`; checkbox `shrink-0`.
- Unsupported / empty-cache copy: `text-caption` (and `text-text-muted` if a sibling already uses it for secondary status).
- Assigned-but-inactive job (show): `text-body-sm text-text-secondary` — not a badge.
- Secrets: `font-mono` + masked string.
- Do not add custom CSS, `space-y-*`, or raw palette classes (`bg-blue-500`). Use project tokens (`border-border-subtle`, `text-accent`, `text-text-primary`, …).

### Stimulus

**None.** Cached Cursor models are rendered by the server. Empty cache is a caption. Test connection stays a normal POST + redirect.

### I18n (English values — byte-identical to the mockups)

Add (or retarget) under `speech_to_text.platform_settings` in both `speech_to_text_platform.*.yml` and any keys the template already reads from `speech_to_text.en.yml` / `zh-CN.yml`. Keep `en` / `zh-CN` in parity.

| Key | English |
|---|---|
| `jobs.section` | Jobs |
| `jobs.section_hint` | Assign each job to at most one provider. A provider can hold both jobs. |
| `jobs.transcribe` | Audio Transcribe |
| `jobs.generation` | Entity/Flowchart generation |
| `jobs.assign_transcribe` | Assign this provider to Audio Transcribe |
| `jobs.assign_generation` | Assign this provider to Entity/Flowchart generation |
| `jobs.not_supported` | Not supported |
| `jobs.assigned` | Assigned |
| `jobs.not_assigned` | Not assigned |
| `jobs.cursor_models_empty` | Save credentials first. Models load after Test connection. |
| `jobs.cursor_default_model` | Cursor default |
| `status.platform` | Assignees *(was Active provider)* |
| `role_active` | Assigned *(was Active for the platform)* |
| `role_inactive` | Not assigned *(was Not the active provider)* |

Reuse existing: `nav_label`, credentials/configuration copy, `edit` / `save` / `cancel`, test + health strings, `masked`, `secret_placeholder`, `keep_hint`, `common.status.active`, `common.labels.em_dash`.

Stop rendering `make_active` / `make_active_hint`. Locale keys may be deleted once unused.

Provider plugin copy (backend/I18n, consumed via `display_name` / `field_label`):

```
speech_to_text.providers.cursor.name: "Cursor"
speech_to_text.providers.cursor.fields.chat_model: "Chat model"
speech_to_text.providers.cursor.credentials.api_key: "API Key"
```

Reuse OpenAI `Model` / `Chat model` / `Organization` field labels as they are today.

Assignees join: interpolate two names with a space-middle-dot-space (` · `) in the component helper, not a hard-coded sentence in ERB. Missing names use `t("common.labels.em_dash")`.

---

## 6. Frontend boundaries

- Implement inside `SettingsComponent` + locales (+ component spec). Do not invent a dashboard or dictate redesign.
- Do not add job groups on Captcha or other vendor settings.
- Do not poll Cursor from Puma or the browser.
- Numeric `/module_settings/7` is the landing card, not a second credentials layout.
