# AWS Bedrock speech-to-text vendor — design spec

Date: 2026-09-07
Status: locked (user chose approach 1; no further confirmation)

## Problem

Platform owners configure speech-to-text vendors at
`/:cid/admin/maintenance/platform/module_settings/speech_to_text/settings`.
The Providers tab is registry-driven. AWS Bedrock is missing. It must support
**both** Audio Transcribe and Entity/Flowchart generation.

## Decisions

| Topic | Choice |
|---|---|
| Key | `aws_bedrock` |
| Display name | AWS Bedrock |
| Default vendor | unchanged (`openai_whisper`) |
| Transcribe | Bedrock Runtime `converse` with an audio content block (`aws-sdk-bedrockruntime`) |
| Generation | `Llm.complete(provider: :bedrock)` via RubyLLM's existing Bedrock adapter |
| Speech API | Not Nova Sonic |
| Credentials | Access Key ID + Secret Access Key + Region (same shape as AWS Transcribe) |
| Schema | none — `ProviderSettings` JSON `config` + encrypted `api_key` |
| UI | no controller/view changes; `register!` is enough |
| Native tools | enabled for Bedrock the same way as Whisper |
| Health check | default silent WAV through `#transcribe` |

## Plugin

`SpeechToText::Providers::AwsBedrock < Base`

- `supports_transcribe?` true, `supports_generation?` true
- `register!` at class-body load time; do not call `default!`
- `configured?` when `api_key` (secret) and `config.access_key_id` are present

### Config fields

- `access_key_id` (string, required)
- `region` (string, default `us-east-1`)
- `model` (transcribe, default `amazon.nova-lite-v1:0`)
- `chat_model` (generation, default `amazon.nova-lite-v1:0`)

Owners may paste inference-profile IDs (e.g. `us.amazon.nova-lite-v1:0`) into
the model fields.

Encrypted `api_key` is the Secret Access Key. I18n credential label:
"Secret Access Key" / same as AWS Transcribe in zh-CN.

## Transcribe flow

Job thread only. Never construct the AWS client on a Puma thread.

1. Read clip bytes.
2. Resolve a Nova audio format via `SpeechToText::AudioFormats.vendor_format(:bedrock, ...)`.
   Pass-through: `wav`, `mp3`, `ogg`, `opus`, `aac`, `flac`, `mp4`.
   Otherwise (notably MediaRecorder `webm`, plus `amr`) ffmpeg to 16 kHz mono WAV.
3. `Aws::BedrockRuntime::Client#converse` with model id from `config.model`:
   - user content: audio block then text "Transcribe the spoken audio. Return only the transcript text with no quotes or commentary."
   - if language is `en` / `zh-CN`, append " The speech is in English." / " The speech is in Chinese."
   - `auto` / blank: omit language sentence
4. Join text content blocks. Blank → `:empty`. Else `:success`.

Prompt text is vendor-facing, not I18n.

## Generation flow

Same as Whisper's `#chat`:

- unconfigured → `:configuration_error`, no network
- `ScriptedCompletion` when the E2E stub is on
- else `Llm.complete(provider: :bedrock, model: chat_model, api_key: secret, access_key_id:, region:, json:, tools:, request_timeout: 60)`

`Llm` gains `:bedrock` in `PROVIDERS`. Context sets `bedrock_api_key` (access key id),
`bedrock_secret_key` (secret), `bedrock_region`. Missing secret or access key id →
`:configuration_error` without calling RubyLLM.

`SpeechToText::Assistant::ProviderClient#native_tools` returns the tool list for
Whisper **and** Bedrock; empty for Cursor / Transcribe / Aliyun.

## Errors

| Condition | Outcome |
|---|---|
| Missing credentials | `:configuration_error`, no AWS/Llm call |
| ffmpeg missing (`ENOENT`) | `:configuration_error` |
| 4xx / AccessDenied / ValidationException / ResourceNotFound / MissingCredentials | `:configuration_error` |
| Timeout / 5xx / networking / NoSuchEndpoint | `:unreachable` |
| Blank transcript / blank chat text | `:empty` |

Open timeout 5s, read timeout 60s.

## AudioFormats

Add a `:bedrock` token per family:

| Family | Token |
|---|---|
| wav | wav |
| mpeg | mp3 |
| ogg | ogg |
| aac | aac |
| flac | flac |
| mp4 | mp4 |
| m4a | mp4 |
| webm | (omit — transcode) |
| amr | (omit — transcode) |

## I18n

`speech_to_text.providers.aws_bedrock` in both `speech_to_text.en.yml` and
`speech_to_text.zh-CN.yml`: name, fields (`access_key_id`, `region`, `model`,
`chat_model`), credentials (`api_key`). English values byte-identical to the
labels above. zh-CN matches AWS Transcribe for shared field names
(`地域` for region, `Secret Access Key` for the secret, `模型` / `对话模型`).

## Testing

- `spec/services/speech_to_text/providers/aws_bedrock_spec.rb` — stub the SDK, stub ffmpeg; no live AWS
- `spec/services/llm_spec.rb` — Bedrock context keys; blank access key id
- `spec/services/speech_to_text/audio_formats_spec.rb` — `:bedrock` tokens
- Registry include `:aws_bedrock`; platform settings request spec includes the tab name
- ProviderClient native tools for Bedrock; still empty for Cursor
- Do not run the full suite

## Out of scope

Nova Sonic, session token field, model listing dropdown, replacing AWS Transcribe,
changing the default vendor, migrations, controller/view edits.
