# ruby_llm chat wrapper (except Whisper STT)

Date: 2026-09-07
Status: locked for implementation (user chose approach B; no further confirmation)

## Goal

Use the `ruby_llm` gem for every chat/completions call that it can express. Keep Whisper transcription on `ruby-openai`. Do not use `ruby_llm` for Cursor Cloud Agents, AWS Transcribe, or Aliyun.

## Architecture

Add `ruby_llm` and put chat/completions behind a thin `Llm` service (same idea as `OutboundHttp`). Callers never talk to `RubyLLM` directly. Persistence stays on existing `SpeechToText::Conversation` / `Message` — no `acts_as_chat`, no ruby_llm Rails generators.

## Components

### `Llm`

Single public method:

```ruby
Llm.complete(
  provider:,          # :openai, :anthropic, :ollama
  model:,
  messages:,          # [{ role:, content: }, ...] (string or symbol keys)
  api_key:,
  organization: nil,  # OpenAI org header
  json: false,        # JSON object mode; ignored when tools present
  tools: nil,         # Array of RubyLLM::Tool instances
  temperature: nil,
  max_tokens: nil,
  request_timeout: 60
) # => { outcome: :success|:empty|:configuration_error|:unreachable, text:, raw: }
```

Per-call credentials go through `RubyLLM.context`. Global initializer only sets logger, `request_timeout` 60, `max_retries` 0.

When `tools` is present, run `chat.step` until complete or 8 tool executions. Do not send `response_format: json_object` together with tools.

### STT providers

- `OpenaiWhisper#transcribe` — unchanged, `ruby-openai`.
- `OpenaiWhisper#chat(messages:, tools: nil)` — `Llm.complete(provider: :openai, ...)`. `json: true` when tools blank. `ScriptedCompletion` still short-circuits in E2E.
- `Cursor#chat` — still Cursor Agents over `OutboundHttp`. Accepts and ignores `tools:`.
- `Base#chat` — `tools: nil` kwarg.

### Native assistant tools

`SpeechToText::Assistant::Tools::Runner` stays the executor. Three `RubyLLM::Tool` adapters wrap it: `ListCatalog`, `GeneratePageTool`, `VerifyArtifactTool`. Entity/flowchart persist stays on the JSON intent processors. Tool descriptions are LLM protocol (English), not UI copy.

`Reply` passes native tools only when the generation provider is `OpenaiWhisper`. After that chat, the JSON `{tool, arguments}` `Loop` still runs as a fallback (no-op when the document has no `tool` key). Cursor keeps the text-tool loop as its only tool path.

### Flowchart `ai_inference`

Generated runtime for `openai`, `anthropic`, and `ollama` emits `Llm.complete` (keys from `ENV` as today). Cohere stays on `OutboundHttp`. No streaming. Do not emit a `tools` key for those providers (the previous `{name, spec}` payload was not valid function-calling). Rewrite generator specs that looked for `OutboundHttp` / `api.openai.com` / `stream: false`.

## Data flow

1. `Reply` builds `prompt_messages` (system + last 20 complete turns).
2. If generation vendor is OpenAI, `chat(messages:, tools: native_instances)`.
3. `Llm` seeds a `RubyLLM::Chat` from messages, optionally attaches tools, completes, maps errors.
4. `Loop` parses the final text; `{tool:}` documents still round-trip through `vendor_chat` without tools.
5. Entity then optional flowchart processors consume the JSON intent document.
6. Flowchart follow-on `vendor_chat` has no tools, so OpenAI uses JSON mode.

## Error handling

- missing api_key / `UnauthorizedError` / `ForbiddenError` / `BadRequestError` / `ConfigurationError` / `ModelNotFoundError` → `:configuration_error`
- `RateLimitError` / `ServerError` / `ServiceUnavailableError` / `OverloadedError` / other `RubyLLM::Error` → `:unreachable`
- blank content → `:empty`

`Llm.complete` does not raise. `Reply` already fail-closes on non-success.

## Testing

- `spec/services/llm_spec.rb` — stub chat; success, empty, config error, unreachable, JSON mode without tools, tools skip JSON mode.
- `openai_whisper_spec` `#chat` expects `Llm.complete`. `#transcribe` still uses `OpenAI::Client`.
- Native tool specs delegate to `Runner` and stay tenant-scoped.
- `Loop` fallback spec unchanged.
- `Reply` stubs `OpenaiWhisper#chat`; first OpenAI call receives tools.
- `AiInferenceGenerator` asserts `Llm.complete` for openai/anthropic/ollama and `OutboundHttp` for cohere.

## Out of scope

Whisper STT, Cursor Agents protocol, AWS/Aliyun, `acts_as_chat`, token streaming UI, Cohere via `ruby_llm`.
