# AI Assistant Reliability Refactor Design

## Problem

The dashboard AI Assistant works, but its reply path has accumulated too many
responsibilities in `SpeechToText::Activities::Reply`. It selects providers,
builds prompts, runs tools, applies entity and flowchart documents, generates
pages, verifies and pins artifacts, persists messages, broadcasts UI state, and
manages cancellation.

The current conversation-wide generation token is also unsafe under overlap:
an older queued job can observe or clear a newer request's token. Model output
is trusted to assert that an update was confirmed, and queued work is not
reauthorized when it starts.

## Goals

- Preserve the existing dashboard, desktop API, provider, entity, flowchart,
  page, localization, and confirmation user experience.
- Give every queued reply a durable lifecycle record so duplicate, cancelled,
  and superseded jobs cannot mutate another generation's state.
- Revalidate authorization, tenant access, module availability, and provider
  availability when queued work starts.
- Replace model-authorized updates with a server-held pending proposal consumed
  only by an explicit subsequent confirmation message.
- Split reply orchestration into focused, independently tested collaborators.
- Ensure every state-changing tool effect participates in change metadata,
  artifact selection, and verification.
- Keep Turbo broadcasts best-effort and separate from database persistence.

## Non-goals

- No dashboard or composer redesign.
- No member or public assistant surface.
- No new model or provider integration.
- No multi-conversation UI, history pagination, or retention policy.
- No hard interruption of an HTTP request already executing at a provider.
- No broad rewrite of entity, flowchart, or page definition subsystems.

## Generation lifecycle

Add `SpeechToText::Generation`, a tenant-scoped record belonging to a
conversation and its source user message. It stores a unique token, status,
start/finish timestamps, cancellation timestamp, and an optional failure code.
The conversation points to its current generation.

Starting a generation locks the conversation, marks any active predecessor
`superseded`, creates a new queued generation, and updates the pointer. A reply
job receives the generation ID rather than a bare message ID. It atomically
claims only a queued generation that is still current. Duplicate jobs fail to
claim and return without side effects.

Cancellation marks the current generation. Completion clears the conversation
pointer only when it still points to that generation. A superseded job never
publishes a terminal message or clears the newer request's UI state.

## Execution policy

Before calling a provider, the job verifies:

- the source message, conversation, generation, and customer agree;
- the user is active;
- the user is either a same-tenant admin or the fixed platform owner;
- the Speech to text module remains enabled for the target customer;
- a generation provider remains active.

Failure produces a localized failed assistant turn and a terminal generation
state without invoking the provider or applying artifacts.

## Reply collaborators

`SpeechToText::Activities::Reply` remains the stable application entry point
but delegates to:

- `Assistant::PromptBuilder`: complete-turn history, schemas, and tenant
  catalogs for entity and flowchart modes.
- `Assistant::ProviderClient`: provider invocation and native tool selection.
- `Assistant::TurnProcessor`: fallback tool loop plus entity/flowchart
  sequencing and result-combination policy.
- `Assistant::Finalizer`: automatic page generation, effect merging, artifact
  resolution, verification, body construction, and change metadata.
- `Assistant::ReplyWriter`: assistant-message persistence followed by
  best-effort message/artifact broadcasts.

The flowchart processor uses `PromptBuilder` instead of depending on a constant
owned by `Activities::Reply`.

## Tool session

One `Assistant::Tools::Session` is created per reply. Native RubyLLM tools and
the JSON fallback loop share it. The session owns the allowlist, tenant-scoped
lookups, normalized result shape, and an effect journal.

Read tools produce no effects. A successful page-generation tool records the
page and whether it was created or reused. `Finalizer` merges those effects
with entity, flowchart, and automatic-page results before it builds metadata
or selects an artifact.

`Artifact.assign!` validates that the selected record belongs to the
conversation customer before storing its kind and ID.

## Server-held update confirmation

Entity and flowchart processors no longer trust `updates_confirmed` from model
JSON. When an update needs approval, the assistant message stores a pending
proposal in metadata containing the normalized document, proposal kind,
customer ID, and target record/version identity.

On a later message containing only an explicit confirmation, the reply path
loads the latest pending proposal from the same conversation and tenant,
verifies that the target version still matches, and applies that stored
document directly. It does not ask the model to reconstruct the update.
Non-confirmation messages follow the normal provider path and leave no reusable
authorization capability beyond the latest assistant proposal.

## Errors and observability

Provider errors map to the existing localized failure response. Application and
database errors remain visible to the job system after generation state is
closed safely. Persistence and broadcast failures use separate log contexts so
a Turbo failure is not reported as a database failure. Logs include generation,
conversation, and source-message IDs but never prompts, credentials, or
attachments.

## Testing

Focused RSpec coverage proves:

- only one job can claim a generation;
- stale and duplicate jobs cannot write or clear a newer generation;
- cancellation is scoped to the current generation;
- revoked users/modules fail before provider invocation;
- prompts preserve current history and catalog behavior;
- tools share one effect journal and tool-created pages are finalized;
- confirmation consumes the stored proposal and rejects stale target versions;
- existing create, update, flowchart, page, metadata, and tenant-isolation
  behavior remains intact;
- broadcast failures do not misclassify successful persistence.

