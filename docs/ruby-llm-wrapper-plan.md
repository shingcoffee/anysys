# ruby_llm wrapper Implementation Plan

> Implement in this session. Do not auto-commit.

**Goal:** Wrap `ruby_llm` behind `Llm.complete` and use it for OpenAI/Anthropic/Ollama chat, plus native assistant tools.

**Architecture:** Thin `Llm` service; Whisper stays on `ruby-openai`; Cursor stays on `OutboundHttp`.

**Tech Stack:** Rails 8.1.2, ruby_llm ~> 1.16, ruby-openai ~> 8.1, Trailblazer activities, RSpec.

## Global Constraints

- No `acts_as_chat`. No hard-coded UI strings. Wrap the gem; do not call `RubyLLM` from providers/generators.
- `Llm.complete` returns `{ outcome:, text:, raw: }` and never raises.
- JSON mode off when tools are present. Cap native tool executions at 8.
- Do not commit unless asked.

### Task 1: `Llm` wrapper

- Create: `app/services/llm.rb`, `config/initializers/ruby_llm.rb`, `spec/services/llm_spec.rb`
- Gemfile already lists `ruby_llm ~> 1.16`

### Task 2: OpenAI chat via `Llm`

- Modify: `OpenaiWhisper#chat`, `Base#chat`, `Cursor#chat`
- Test: `spec/services/speech_to_text/providers/openai_whisper_spec.rb`

### Task 3: Native tools + Reply

- Create: `app/services/speech_to_text/assistant/tools/native.rb`
- Modify: `Reply#call` / `vendor_chat`
- Test: native tool specs + reply spec that first OpenAI chat receives tools

### Task 4: `ai_inference` generator

- Modify: `AiInferenceGenerator`
- Test: generator spec rewritten for `Llm.complete`
