---
title: "Speech to text"
summary: "Dictation uploads are transcribed by the AI assistant's active speech vendor; speech to text is not a feature-module registration."
---

## Summary

Speech to text is not a `FeatureModules` registration. There is no `FeatureModules::SpeechToText` class and no module key of its own. `app/services/speech_to_text/` validates the upload, stores a short-lived `SpeechToText::Clip`, and calls whichever `AiAssistant::Providers` subclass currently holds the transcribe job. The tenant gate is `FeatureModules::Module.enabled?(key: "ai_assistant")`. Length comes from that module's assignment (`language`, `max_duration_seconds`), read by `SpeechToText::DurationPolicy`. Tenant admins choose the language in Settings and see the recording limit there; the platform owner edits the limit for each customer under Maintenance / Modules. See [ai-assistant](ai-assistant) and [module-framework](module-framework).

Two callers enqueue the same activity. The cookie widget posts to `Admin::Modules::AiAssistant::TranscriptionsController`. The desktop client posts to `Admin::Assistant::TranscriptionsController` and later polls `show`. Both include `SpeechToText::TranscriptionEnqueueing`. The vendor call runs in `SpeechToText::TranscribeJob`, never on the Puma request thread.

## Flow

```text
DictateFieldComponent  or  desktop microphone
        |
        v
SpeechToText::TranscriptionEnqueueing#create
        |
        v
SpeechToText::Activities::EnqueueTranscription
        |  contract, duration, module, provider, rate limit
        |  SpeechToText::Clip (audio attached, status pending)
        v
SpeechToText::TranscribeJob
        |
        v
SpeechToText::Activities::Transcribe
        |  AiAssistant::ProviderSettings.active_for(:transcribe)
        |  provider.transcribe
        v
destination "field"     -> Turbo replace for SpeechToText::ResultComponent
destination "assistant" -> AiAssistant::Activities::SendMessage
        |
        v
clip.audio.purge (after durable terminal outcome)
desktop poll: SpeechToText::Activities::ShowTranscription
later: SpeechToText::PruneClipsJob deletes the row
```

## Implementation

`EnqueueTranscription` shares assistant module/provider/rate checks and validates declared upload type/size, field ID and normalized destination. Client duration and byte caps are cheap guards, not duration proof. `SpeechToText::AudioProbe` decodes actual audio with FFmpeg before enqueue or paid invocation, counting mono 8kHz signed-16 PCM bytes against the tenant duration. Protocols are restricted to local file/pipe and decoding is bounded to 30 seconds. Missing decoder returns 503 `audio_probe_unavailable`; invalid audio returns 422 `invalid_audio`; over-cap audio returns `too_long`. Install FFmpeg on request hosts as well as workers; `STT_FFMPEG_PATH` can select the executable.

`DurationPolicy::MODULE_KEY` is `"ai_assistant"`. The default cap is 60 seconds. The absolute cap is 120 seconds. The widget in `SpeechToText::DictateFieldComponent` reads the same policy, so the browser advertises the cap the server enforces. Language stored on the clip is the request value, or the assignment's `language`, or `"auto"`.

`Clip` destinations are `"field"` and `"assistant"`. `normalize_destination` returns `"field"` for anything else, so an unknown value fills the caller's input and does not post into the assistant thread. The cookie controller passes the destination the widget declared. The desktop controller fixes `dictation_destination` to `DESTINATION_ASSISTANT` and `field_dom_id` to `"desktop"`, and it rejects cookie sessions through `Oauth::BearerAuthenticatable`. See [authentication](authentication).

`Transcribe` atomically claims pending → processing, rechecks module/provider, transcribes and routes before persisting succeeded/failed. An assistant clip uses its enqueue-authorized `conversation_id` and `SendMessage` idempotency key `speech_to_text:clip:<id>`; deleted/foreign threads cannot redirect audio into a newer thread. Field clips retain text for the signed user stream, assistant clips clear it after chat handoff. Duplicate workers/terminal reruns do nothing. Audio purges only after durable terminalization; persistence outages retain it. `ShowTranscription` scopes clip/customer/user. `PruneClipsJob` terminalizes pending/processing work stale by five minutes, broadcasts failure, purges terminal audio and retains terminal rows for 15 minutes after updated_at. Its production schedule remains daily 4:45am, not every five minutes.

Pruning captures the terminal row's `updated_at` in a local `finished_at` before purging audio, because Active Storage detachment touches the owning clip. Deletion uses that captured age, not `created_at` or the timestamp changed by purge. A long-lived clip that just finished is retained; a terminal clip older than 15 minutes is deleted even when audio remains attached. The exact 15-minute boundary is retained. `finished_at` here is a local variable, not an additional database column.

Vendors live under `AiAssistant::Providers`, not under `app/services/speech_to_text/`. Transcription-capable classes: `OpenaiWhisper` (`ruby-openai`, the `default!` provider), `AwsTranscribe` (HTTP/2 streaming after ffmpeg to PCM), `Aliyun` (flash recognizer, token via `Vendor::AliyunRpc`), `AwsBedrock` (audio content block on Converse; other containers are ffmpeg'd to wav). `Deepseek`, `Qwen`, and `Cursor` set `supports_transcribe?` to false and their `#transcribe` returns `configuration_error`. `UpdateProviderSettings` will not assign those three to the transcribe job. A transcription-only provider's `#chat` remains `Providers::Base`, which returns `configuration_error`.

## Where to pay attention

### Browser recording proof

`spec/e2e/speech_to_text_mic.app.spec.js` uses the existing `chromium-media`
project's microphone permission and fake capture device with Chromium's real
`MediaRecorder`. It waits for the actual `speech-to-text` Stimulus controller and
Action Cable's confirmed panel stream subscriptions,
clicks the microphone, checks recording state, waits for recorded elapsed time,
then clicks Stop and asserts a normal 202 upload. The application decodes the
audio with `AudioProbe` and transcribes through the local HTTP SDK provider.
`helpers/speech_runtime.js` checks exact provider multipart byte count/SHA-256, the visible
transcript, the exact per-test owned conversation, positive decoded duration,
durable `succeeded` status and purged audio. Readiness and duration polling do
not invoke application action methods. `Clip` has no duration column: the helper
observes the native recorder's `dataavailable` event and re-probes those bytes
with the real `AudioProbe` after normal acceptance. The provider SHA-256 match
proves those same bytes crossed the SDK transport despite Chromium omitting
multipart file contents from its network inspector. The exact prepared database is reused;
see `spec/e2e/README.md` for the four-worker existing-server command.

The 2026-10-12 five-case follow-up passed 5/5 with four workers, zero retries/skips
or flaky cases; provider helper checks passed 4/4. Recorded clip 4 decoded to
1.32 seconds, matched the provider's 13,932 bytes and SHA-256, entered pinned
conversation 17, persisted `succeeded` and purged audio. The transcript was
visible in the browser and checked in the database. Evidence:
`/tmp/opencode/assistant-audio-followup/results-final.json` and `summary.md`.

### Route audit: queue acceptance and conversation binding

`EnqueueTranscription.call(..., conversation_id:)` requires an owned conversation for destination assistant before storing the clip. Refused/raising enqueue produces a failed clip and 503 `enqueue_failed`, not false 202. `BroadcastResult` separates committed terminal state from stream-delivery errors. The speech handoff migration adds conversation/processing state and start time.

:::attention
Both HTTP callers permit/pass `conversation_id`; assistant uploads require a conversation owned by the authenticated customer/user. `DictateFieldComponent(conversation_id:)` mounts the selected thread, and `speech-to-text` captures its ID before the microphone permission prompt. `ai-assistant:conversationChanged` updates the next recording only, never a buffered clip. Desktop uploads explicitly send the selected ID; polling returns id/status/conversation_id/error_code, with raw transcript only for a succeeded owned field clip. Assistant transcripts are consumed by the pinned chat. Enqueue failures include clip_id when a durable clip exists. See [AI assistant](ai-assistant), [OAuth](oauth), [Background jobs](background-jobs).
:::

:::note
On 2026-10-11 the targeted AI/entity-definition/STT/LLM slice passed 1,666 examples with zero failures on `storage/ai_verify.sqlite3`, schema version `20261011190000`. The STT specs decode real FFmpeg-generated compressed audio and cover thread binding, enqueue refusal, terminal/duplicate processing, broadcast fallback and pre-purge retention age. The schema was loaded into an isolated test database; loading it does not execute the data-only historical-payment backfill. Live vendor and browser journeys were outside this run. Evidence: `docs/audits/2026-10-11-ai-stt-targeted-verification.md`.
:::

:::attention
Speech to text is not registered with `FeatureModules`. `SpeechToText::Activities::Transcribe` and `SpeechToText::DurationPolicy` both key off `ai_assistant`. Turning off that module makes enqueue return 403 and makes an in-flight job record `disabled`. There is no separate enablement row for dictation.
:::

:::attention
`SpeechToText::Activities::EnqueueTranscription` never calls a vendor. `SpeechToText::Activities::Transcribe` is the only activity that opens the audio and calls `provider.transcribe`. `Admin::Modules::AiAssistant::TranscriptionsController` returns 202 with `clip_id` after the job is queued.
:::

:::attention
`SpeechToText::Clip.normalize_destination` fail-closes to `"field"`. `Admin::Assistant::TranscriptionsController` does not trust the request body for destination: it always sets `DESTINATION_ASSISTANT`. A field clip never calls `AiAssistant::Activities::SendMessage`.
:::

:::attention
Terminal state is persisted before audio purge. Processing/pending persistence failures retain audio for scheduled recovery; polling reads durable state, not blob existence. Prune retention uses terminal `updated_at` captured before purge touches the record.
:::

## Key code

```ruby
# app/services/speech_to_text/activities/enqueue_transcription.rb
def call
  failure = preflight_failure
  return failure if failure

  clip = create_clip!
  job = SpeechToText::TranscribeJob.perform_later(clip.id)
  return enqueue_failure(clip) unless job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)
  success_result(clip)
end
```

```ruby
# app/services/speech_to_text/activities/transcribe.rb
def transcribe_clip
  unless FeatureModules::Module.enabled?(key: "ai_assistant", customer_id: clip.customer_id)
    return failed("disabled")
  end

  settings = AiAssistant::ProviderSettings.active_for(:transcribe)
  return failed("disabled") unless settings
  return failed("generic_error") unless clip.audio.attached?

  result = clip.audio.open do |file|
    settings.provider_class.new(settings: settings).transcribe(
      io: file,
      filename: clip.audio.filename.to_s,
      content_type: clip.audio.content_type,
      language: clip.language
    )
  end
  map_outcome(result)
end
```

```ruby
# app/models/speech_to_text/clip.rb
def self.normalize_destination(value)
  candidate = value.to_s.strip
  DESTINATIONS.include?(candidate) ? candidate : DEFAULT_DESTINATION
end
```

```ruby
# app/services/speech_to_text/duration_policy.rb
MODULE_KEY            = "ai_assistant"
DEFAULT_MAX_DURATION  = 60
ABSOLUTE_MAX_DURATION = 120
```
