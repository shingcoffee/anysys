# Speech-to-text — UX spec

Date: 2026-08-25
Follows: `docs/speech-to-text-design.md`
shadcn analog: Input Group + trailing icon button (mic). Delivered as ViewComponent + Tailwind + Stimulus (no shadcn JS).

## 1. Surface inventory

- **Dictate control** (admin entity text/textarea fields) — not a nav area; overlays FormFields
- **Settings / Speech to text** — Settings — generic module config form
- **Maintenance / Modules** — existing toggle row (no new UI)
- **Maintenance / Platform / Module Settings** index card + dedicated Whisper credentials show/edit — Platform
- **Modules / Speech to text** — empty; no dedicated entries table

## 2. Layout per surface

### Dictate control (first host)

ASCII (desktop; stacks on mobile):

```
[ Label *                                           ]
[  _______________________________ text input  (mic) ]
[  status / error caption (one line)                 ]
```

- Mic is a `ButtonComponent` `variant: :ghost` `size: :sm` absolutely/flex at the input’s trailing edge (Input Group pattern).
- `aria-label` from i18n (`speech_to_text.widget.mic_label` / `stop_label`).
- States:
  - **idle**: ghost mic icon, `text-text-muted`
  - **recording**: `text-danger`, pulse via Tailwind `animate-pulse`, click stops
  - **uploading / transcribing**: mic disabled, caption “Transcribing…”
  - **success**: caption clears; text appears in the field
  - **error**: caption `text-danger` i18n message; field unchanged
  - **unavailable** (no MediaRecorder / insecure): control not shown OR disabled + unavailable caption (prefer hide if `render?` is false; if API missing after render, show unavailable)

Empty: no extra empty state. Loading: transcribing caption. Error: caption only, never a modal.

Primary action: toggle record. No destructive action.

### Settings (generic module config)

Reuse `admin/module_configs/show`. Fields:

- Language — select: Auto-detect / English / 简体中文 (labels i18n; values `auto`, `en`, `zh-CN`)
- Max recording duration (seconds) — number

If the generic form only supports text/number/boolean, language may render as a text input with the three allowed values; prefer `type: string` in schema and document allowed values in the field label. (Implementation: if module_configs select support is awkward, use string field with placeholder `auto`.)

### Platform credentials

Match Captcha platform settings card: provider tab (only Whisper in v1), API key (password, keep-existing if blank), model, organization, Active toggle, Test connection, Edit/Save.

Link card on `module_settings/show` when `key == "speech_to_text"`, same list-row pattern as SMS credentials (card + chevron).

## 3. Interaction flow

**Dictate (happy):** Admin opens entity form with text field → sees mic → click → browser permission → records → click stop → POST → 202 → caption Transcribing → Turbo replace → text inserted → clip discarded.

**Mic denied:** caption permission error; field unchanged.

**Vendor down:** caption retryable error; field unchanged.

**Module off:** no mic. POST 403/422 if crafted.

**Member / anonymous:** no mic. POST denied by admin route gate.

**Platform save:** owner opens Module Settings → Speech to text → Credentials → edit API key → save → flash updated.

## 4. Component reuse map

| Piece | Reuse / new |
|---|---|
| Mic + field wrap | **New** `SpeechToText::DictateFieldComponent` wrapping the existing input |
| Buttons | `ButtonComponent` ghost sm |
| Status flash on settings | `AlertComponent`, `BadgeComponent`, `BreadcrumbsComponent` |
| Platform page chrome | Same cards/table as captcha/SMS (`card`, `card-header`, `section-header`, `input-field`) |
| Settings form | Existing module_configs view — **no new settings component required** |
| Platform credentials | **New** `Admin::Maintenance::Platform::SpeechToText::SettingsComponent` |
| Turbo result shim | **New** `SpeechToText::ResultComponent` (hidden/status node the job replaces) |
| Stimulus | **New** `speech_to_text_controller.js` (record/upload) + `speech_to_text_result_controller.js` (apply transcript on connect) |

## 5. Tailwind & Stimulus

- Spacing: `flex items-center gap-2`, input `pr-10` if overlay button, caption `mt-1 text-caption`
- Colors: `text-text-muted`, `text-danger`, `text-text-primary`, `border-border-subtle` — match dashboard tokens, not raw `bg-blue-600` on new work (Captcha settings still uses older blues; new STT platform card should use `btn` / `input-field` / `card` like SMS/module_settings)
- Stimulus `speech-to-text`:
  - targets: `field`, `button`, `status`, `inbox`
  - values: `url`, `maxDuration`, `csrf`, plus i18n strings (`recording`, `transcribing`, `permissionDenied`, `unavailable`, `tooLong`, `genericError`, `stopLabel`, `micLabel`)
  - actions: `toggle` (start/stop)
- Stimulus `speech-to-text-result`:
  - values: `fieldId`, `status`, `transcript`, `error`
  - `connect()` writes transcript or error, then can no-op

Responsive: button stays in the trailing slot; caption wraps; no fixed min-width desktop-only layout.
