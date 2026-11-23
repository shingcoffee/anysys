# Speech-to-text dual-job providers

Date: 2026-09-04

## Problem

Platform settings at `/81721200/admin/maintenance/platform/module_settings/7` (same surface as `.../module_settings/speech_to_text/settings`) used one `enabled` row for both dashboard jobs: audio transcription and entity/flowchart generation. Only OpenAI Whisper implemented `#chat`. AWS Transcribe and Aliyun broke the assistant when made active. Cursor (cursor.com) was missing.

## Decisions (locked)

- Independent assignees: one provider for Audio Transcribe, a possibly different provider for Entity/Flowchart generation.
- Unsupported jobs stay visible as “not supported” (never omit the job group).
- Cursor generation models are a live list from `GET https://api.cursor.com/v1/models` after credentials exist (cached; not fetched on the Puma request thread).
- Approach 1: two exclusive boolean flags on the existing per-vendor row. Drop `enabled`. No shims.

## Runtime

| Job | Assignee lookup | Callers |
|---|---|---|
| Audio Transcribe | `ProviderSettings.active_for(:transcribe)` | `Transcribe`, `EnqueueTranscription` preflight, dictate widget |
| Entity/Flowchart generation | `ProviderSettings.active_for(:generation)` | `Reply`, `SendMessage` / `ListMessages` preflight, dashboard assistant |

Dashboard assistant is available when the Speech-to-text module is on **and** a generation assignee is configured. The composer mic still requires a transcribe assignee (`DictateFieldComponent`).

## Schema

`speech_to_text_provider_settings`:

- Remove `enabled` and `index_speech_to_text_provider_settings_single_active`.
- Add `transcribe_active` boolean not-null default false, partial unique where true.
- Add `generation_active` boolean not-null default false, partial unique where true.
- Backfill: `transcribe_active = enabled`, `generation_active = enabled` before drop.

API: `activate_for!(:transcribe|:generation)`, `deactivate_for!(job)`, `active_for(job)` (configured row or nil).

Assigning a job the provider does not support is rejected in the Reform contract.

## Provider capabilities

| Provider | Transcribe | Generation | Models |
|---|---|---|---|
| `openai_whisper` | yes (`model`, default `whisper-1`) | yes (`chat_model`, default `gpt-4o-mini`) | free-text |
| `aws_transcribe` | yes (no model name) | no | — |
| `aliyun` | yes (no model name) | no | — |
| `cursor` | no | yes (`chat_model` from live list) | `GET /v1/models` |

`SpeechToText::Providers::Base`:

- `supports_transcribe?` default true
- `supports_generation?` default false
- `#chat` stays fail-closed
- `#health_check` default: silent WAV `#transcribe`

OpenAI Whisper: both supports true; health_check remains WAV transcribe (same API key).

Cursor: `supports_transcribe?` false, `supports_generation?` true.

## Cursor HTTP (single file)

`app/services/speech_to_text/providers/cursor.rb` via `OutboundHttp`. Auth: `Authorization: Bearer <api_key>`.

- **List models / health_check:** `GET https://api.cursor.com/v1/models`. 200 + `items` → ok; cache `[{ "id", "display_name" }, ...]` in `config_json["generation_models"]`. 4xx (except 429) → `:configuration_error`. 429/5xx/timeout → `:unreachable`.
- **#chat:** no-repo Cloud Agent. `POST https://api.cursor.com/v1/agents` with `{ prompt: { text: flattened messages }, model: { id: chat_model } }` (`model` omitted when blank so Cursor uses its default). Omit `repos`. Poll `GET /v1/agents/{id}` until `status` is `IDLE` (or timeout 60s). Then `GET /v1/agents/{id}/runs/{latestRunId}` and use `result`. Honor `E2E_STUB_ASSISTANT=1` via `ScriptedCompletion` like Whisper.
- **#transcribe:** `:configuration_error` (unsupported).

Do not construct HTTP clients in Puma request threads. Cache refresh happens in `TestConnection` (job). After a successful Cursor save, enqueue `TestConnectionJob` so the model list fills without a second click.

## Settings UI

Every provider card has two job groups, always visible, labeled **Audio Transcribe** and **Entity/Flowchart generation** (I18n en + zh-CN):

- Supported job: assignment checkbox for that job + that job’s model fields (if any).
- Unsupported job: the group heading plus “not supported” copy; no checkbox, no fake model input.

Replace the single “Make this the active provider” toggle.

Status strip: this-provider role reflects either-job assignment; platform value lists both assignees.

Switcher: Cursor is a fourth tab; a tab is marked active if assigned to either job.

## Out of scope

Tenant credential/model overrides; AWS/Aliyun `#chat`; Cursor speech-to-text; Cloud Agent repos/MCP; per-request model override; live model lists for OpenAI.
