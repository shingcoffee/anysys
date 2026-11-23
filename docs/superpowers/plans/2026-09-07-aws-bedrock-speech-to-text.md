# AWS Bedrock Speech-to-Text Vendor Implementation Plan

> **For agentic workers:** Execute inline in this session. Do **not** git commit (AGENTS.md). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AWS Bedrock as a dual-capability speech-to-text vendor on the platform Providers tab.

**Architecture:** New `SpeechToText::Providers::AwsBedrock` plugin. Transcribe uses `aws-sdk-bedrockruntime` Converse with an audio block. Generation goes through `Llm` with RubyLLM `:bedrock`. Settings UI is registry-driven.

**Tech Stack:** Rails 8.1.2, Trailblazer-style provider plugin, `aws-sdk-bedrockruntime`, `ruby_llm` 1.16, RSpec, ffmpeg for unsupported containers.

## Global Constraints

- Grok 4.6 only; do not switch models
- I18n en + zh-CN for every user-facing string; English byte-identical to the labels that would have been hard-coded
- No migration, no controller/view changes, no `default!`
- Encrypted `api_key` is the AWS secret; `config` JSON holds the rest
- Never call Bedrock/LLM on a Puma thread
- Fail closed when unconfigured
- Prefer `aws-sdk-bedrockruntime` for transcribe; wrap chat behind `Llm`
- Do not commit
- Targeted specs only (not the full suite)

## File map

- Create: `app/services/speech_to_text/providers/aws_bedrock.rb`
- Create: `spec/services/speech_to_text/providers/aws_bedrock_spec.rb`
- Modify: `Gemfile` (add `aws-sdk-bedrockruntime`)
- Modify: `app/services/llm.rb` (`:bedrock` provider)
- Modify: `spec/services/llm_spec.rb`
- Modify: `app/services/speech_to_text/audio_formats.rb` (`:bedrock` tokens)
- Modify: `spec/services/speech_to_text/audio_formats_spec.rb`
- Modify: `app/services/speech_to_text/assistant/provider_client.rb` (native tools)
- Modify: `spec/services/speech_to_text/assistant/provider_client_spec.rb`
- Modify: `config/locales/speech_to_text.en.yml` / `speech_to_text.zh-CN.yml`
- Modify: `spec/services/speech_to_text/providers/openai_whisper_spec.rb` (registry keys)
- Modify: `spec/requests/admin/maintenance/platform/speech_to_text/settings_spec.rb` (tab name)

### Task 1: AudioFormats `:bedrock` tokens
### Task 2: `Llm` Bedrock provider
### Task 3: AwsBedrock provider + gem
### Task 4: Native tools, I18n, settings tab
