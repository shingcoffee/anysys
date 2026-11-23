# Speech to text — implementation plan

> Execute via parallel anysys SDLC subagents. Do **not** git commit. Global constraints from `docs/speech-to-text-design.md` and `docs/speech-to-text-ux.md`.

**Goal:** Admin-only microphone on entity text/textarea fields; Solid Queue job transcribes with OpenAI Whisper; Turbo Stream inserts text; audio discarded.

**Architecture:** Captcha-shaped feature module `speech_to_text`. Puma never calls Whisper. Provider plugin + ruby-openai wrap.

**Tech stack:** Rails 8.1.2, Trailblazer activities, Reform, ViewComponent, Stimulus, Solid Queue, ruby-openai, Turbo Streams.

## Global constraints

- Grok/implementation: I18n en + zh-CN for every user-facing string; no literals in JS (Stimulus values + server `t()`)
- Roles: owner / admin / member only; owner only `lingercoffee@gmail.com` @ 81721200
- Admin URLs under `/:cid/admin/`; RouteAuthorization already gates — do not duplicate `before_action :require_admin_or_owner!`
- Fail closed; no audio/transcript persistence after job
- `customer_id` on clips; provider_settings are platform-wide (no customer_id), justified like captcha
- Tailwind + Stimulus + ViewComponent only
- Do not commit
- Never call STT/LLM APIs inside a request thread

## File map

**T-model (backend):** Gemfile; migrations; `app/models/speech_to_text/*`; `app/services/speech_to_text/**`; `app/jobs/speech_to_text/**`; `app/services/feature_modules/speech_to_text/**`; `config/recurring.yml`; `config/locales/speech_to_text.{en,zh-CN}.yml`; `config/locales/feature_modules.{en,zh-CN}.yml` keys; factories + model/activity/contract/job/provider specs.

**T-component-dictate (frontend):** `SpeechToText::DictateFieldComponent`, `SpeechToText::ResultComponent`; wrap `FormFields::TextFieldComponent` + `TextareaFieldComponent`; `speech_to_text_controller.js` + `speech_to_text_result_controller.js` + Vitest 100%; `config/locales/admin_misc.{en,zh-CN}.yml` field labels; component specs.

**T-component-platform (frontend):** `Admin::Maintenance::Platform::SpeechToText::SettingsComponent`; card on `app/views/admin/maintenance/platform/module_settings/show.html.erb`; `maint_platform` i18n keys; component spec.

**T-routes (security):** `config/routes.rb`; transcriptions controller; platform settings controller; thin views that only render components; `Ability#platform_owner_subjects` add `:platform_speech_to_text`; routing + request specs (anon/member/admin/cross-tenant/disabled/unconfigured).

**T-qa (after build):** remaining request/system/auth-matrix specs.

## Interfaces

```
SpeechToText::Providers.for("openai_whisper")
SpeechToText::ProviderSettings.active # => row or nil
SpeechToText::ProviderSettings.for_provider(key)
# instance:
provider.transcribe(io:, filename:, content_type:, language:)
# => { outcome: :success|:empty|:configuration_error|:unreachable, text: String|nil, raw: }

SpeechToText::Activities::EnqueueTranscription.call(
  customer:, user:, audio:, field_dom_id:, language: nil
) # => Result success?/clip/http_status/errors

SpeechToText::TranscribeJob.perform_later(clip_id)

SpeechToText::Stream.name(customer_id:, user_id:) # => [:speech_to_text, cid, uid]

POST /:cid/admin/speech_to_text/transcriptions
  params: audio (file), field_dom_id
  202 { clip_id: } | 403/422/429
```

DictateFieldComponent data-controller `speech-to-text`; transcribe URL from `helpers` admin path; turbo_stream_from Stream.name.

## Tasks

### T-model — independent: true
Backend developer. See design spec. Add `ruby-openai`. Mirror Captcha provider/settings/activities. Clip TenantScoped + ActiveStorage. Job sets Current.customer. Prune job + recurring.yml production entry.

### T-component-dictate — independent: true
Frontend. UX spec dictate section. Do not edit speech_to_text.yml (backend). Widget copy keys: `speech_to_text.widget.*`.

### T-component-platform — independent: true
Frontend. Platform settings component like captcha but dashboard tokens (`card`, `input-field`, `btn`). Link row on module_settings show when key is speech_to_text.

### T-routes — independent: true
Security. Namespace under admin. Platform nested like captcha. Controllers stay thin; call activities. No duplicate auth filters.

### T-qa — after the four above
QA engineer. Auth matrix + cross-tenant + system happy path if feasible without a live OpenAI key (stub provider).
