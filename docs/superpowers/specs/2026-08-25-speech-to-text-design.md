# Speech-to-text — design spec

Date: 2026-08-25
Status: locked for implementation (user asked to complete without further confirmation)

Canonical copies also live under `docs/superpowers/specs/` (cursorignored; written via shell).

## Problem

Tenant admins can only type into entity form fields. They need a microphone on admin text/textarea fields so spoken audio is transcribed by the server and inserted as text. No speech/STT code exists today.

## Decisions (locked)

| Topic | Choice |
|---|---|
| Audience | `admin` / `owner` only. Not public visitors, not `member`. |
| First host | Reusable dictate widget; first wiring is entity **text** and **textarea** `FormFields` when the current user is admin/owner. |
| Vendor | Plugin architecture. v1 vendor is **OpenAI Whisper** via the `ruby-openai` gem, wrapped in `SpeechToText::Providers::OpenaiWhisper`. Later vendors are a single new file. |
| Retention | Store **nothing** after success/failure: no transcript log, no audio archive. Ephemeral `SpeechToText::Clip` exists only as a job handoff. |
| Async | **Never** call Whisper (or future LLM/TTS) on a Puma thread. Controller validates + attaches + enqueues, returns 202. |
| Job backend | **Solid Queue** (already in the app). Not Sidekiq. |
| v1 pipeline | Capture → upload/enqueue → Whisper in job → Turbo Stream transcript into the field. |
| Later (same job/stream, not v1) | LLM completion + TTS (`tts-1` / ElevenLabs) + `<audio>` playback. |
| Fail policy | **Fail closed** if the module is off or the vendor is unconfigured. |
| Module key | `speech_to_text` |

## Four module surfaces

1. **Modules / Speech to text** — empty entries (like Captcha). Sidebar `entries: []`. `entry_path` points at Settings.
2. **Settings / Speech to text** — `/:cid/admin/settings/modules/speech_to_text` via generic `Admin::ModuleConfigsController`. Keys: `language` (`auto` default, `en`, `zh-CN`), `max_duration_seconds` (default 60, min 5, max 120).
3. **Maintenance / Modules** — existing enable/disable. Auto-register `app/services/feature_modules/speech_to_text/registration.rb`.
4. **Maintenance / Platform / Module Settings** — owner / `81721200`. Nested `/:cid/admin/maintenance/platform/module_settings/speech_to_text/settings` for Whisper API key, model (`whisper-1`), optional organization, activate, test connection.

## Runtime flow

MediaRecorder (Stimulus) → POST multipart `/:cid/admin/speech_to_text/transcriptions` → Enqueue activity (module + vendor + size + duration; no Whisper) → attach blob to `SpeechToText::Clip` → `SpeechToText::TranscribeJob.perform_later(clip.id)` → 202 `{ clip_id }` → job calls Whisper via ruby-openai → `Turbo::StreamsChannel.broadcast_replace_to` signed stream `[:speech_to_text, customer_id, user_id]` → Stimulus writes transcript into the field (append with a separating space if non-empty) → ensure purge blob + destroy clip.

## Data model

**`speech_to_text_provider_settings`** — platform-wide, **no** `customer_id` (same justification as captcha_provider_settings). Columns: `provider` (unique), `enabled` (partial unique), encrypted `api_key`, `config` JSON, health-check fields.

**`speech_to_text_clips`** — TenantScoped, `customer_id` required. Columns: `user_id`, `field_dom_id`, `language`, `status` (`pending|succeeded|failed`), `error_code`. `has_one_attached :audio`. **No transcript column.** Job ensure destroys; daily prune of pending clips older than 15 minutes.

## Provider plugin

`SpeechToText::Providers` via PluginRegistry + VendorPlugin.mixin.

`transcribe(io:, filename:, content_type:, language:)` → `{ outcome:, text:, raw: }` with outcomes `:success`, `:empty`, `:configuration_error`, `:unreachable`.

OpenaiWhisper key `"openai_whisper"`, `default!`. Uses `OpenAI::Client` from `ruby-openai`. Do not hand-roll Whisper HTTP.

## Auth

Admin prefix is enough — do **not** duplicate `before_action :require_admin_or_owner!` (RouteAuthorization). Tenant from `current_customer`. Add `:platform_speech_to_text` to `Ability#platform_owner_subjects`. Fail closed. Rate limit 30 enqueues/user/hour via Rails.cache. Max upload 25 MB.

## Widget `render?`

`current_user.admin_or_owner?` AND module enabled AND `ProviderSettings.active` configured. Hidden for members/anonymous.

## Out of scope (v1)

LLM, TTS, stored transcripts/audio, public/member dictation, other admin forms, Web Speech API as backend, streaming partials, speech-only field type, billing UI, second vendor file.
