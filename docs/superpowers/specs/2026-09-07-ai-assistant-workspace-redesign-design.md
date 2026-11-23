# AI Assistant Workspace Redesign

Date: 2026-09-07

## Problem

The dedicated admin AI Assistant works, but its hierarchy and artifact experience are still shaped like the dashboard rail it replaced. The current page preview is a short live iframe, the action label is ambiguous, and non-desktop layouts place Preview below a long transcript. Admins need a focused workspace where conversation and generated output are equally understandable, rendered pages are recognizable at a glance, and a larger inspection view is available without losing the conversation.

## Audience and scope

- Applies to every `GET /:cid/admin/assistant` surface, not only customer `81721200`.
- Audience remains authenticated `admin` and `owner` users under existing admin-route authorization.
- Existing tenant scoping, per-user conversations, Turbo streams, assistant tools, messages, attachments, dictation, and generation behavior remain unchanged.
- The preview represents the page's current saved render. No frozen screenshot or screenshot history is stored.

## Selected approach

Use a live, thumbnail-style rendering of the current page and an accessible in-page enlarged viewer.

This is preferred over persisted screenshot files because it stays current without adding browser-rendering infrastructure, background jobs, Active Storage lifecycle rules, cache invalidation, or stale-image behavior. The viewer is deliberately non-interactive; explicit links open the real preview or detail page when the user wants to continue working.

## Workspace architecture

### Desktop (`lg` and wider)

- Render a full-height two-column workspace.
- Conversation remains the primary pane using `minmax(0, 1fr)`.
- Preview is a stable right rail sized with a responsive `minmax` column rather than a small dashboard card.
- Each pane owns its scrolling. The composer remains anchored inside the conversation pane.
- The preview rail renders the latest artifact and keeps its header/actions visible while its body can scroll.

### Tablet and mobile (below `lg`)

- Replace the current vertical stack with a mobile tab switch: **Conversation** and **Preview**.
- Only the active panel is displayed, so Preview is immediately reachable instead of appearing after a fixed-height transcript.
- The tab switch uses `role="tablist"`, `role="tab"`, `role="tabpanel"`, `aria-selected`, and `aria-controls`.
- Switching tabs does not recreate the panels; composer state, transcript position, Turbo subscriptions, and artifact contents stay in the DOM.

## Components

### `Admin::Assistants::WorkspaceComponent`

- Own the responsive layout and Conversation/Preview tab strip.
- Set the document title to the translated AI Assistant label.
- Mount a small `assistant-workspace` Stimulus controller for mobile tab state.
- Keep the existing `data-dashboard-region="chat"` and `data-dashboard-region="overview"` hooks.
- Continue rendering the unavailable state as one focused full-canvas panel.

### `SpeechToText::AssistantPanelComponent`

- Preserve its public API and assistant behavior.
- Refine spacing and hierarchy only where required by the new workspace.
- Keep the thread as the independently scrolling region and the composer as the stable footer.
- Preserve every existing action and keyboard behavior.

### `SpeechToText::ArtifactPaneComponent`

- Remain the Turbo replacement root identified by `SpeechToText::Stream::ARTIFACT_ID`.
- Fill the Preview panel rather than ending after a short card.
- Render three explicit states:
  - page artifact;
  - entity or flowchart summary;
  - no resolved artifact.
- Continue deriving all destinations from the current customer and resolved record.

### `SpeechToText::ArtifactPreviewDialogComponent`

- New ViewComponent rendered only for a resolved page artifact.
- Render a native `<dialog>` with a required translated title, close control, large safe iframe, and footer actions.
- Provide separate **Open preview** and **Open details** links.
- Open destination links in a new tab with `rel="noopener"` so the assistant conversation remains available.

## Page thumbnail and enlarged viewer

### Thumbnail

- Use the existing authorized page-preview URL.
- Render a fixed-aspect, clipped iframe at a reduced visual scale so more of the page is recognizable than in the current 256px crop.
- Make the iframe non-interactive and non-focusable.
- Place an explicit button overlay above the frame with translated accessible text and a visible “View larger” affordance.
- Use project semantic colors, borders, radius, and typography; do not introduce custom CSS.

### Enlarged viewer

- The overlay button opens the native dialog through `artifact-preview`.
- The dialog fills most of the viewport on desktop and becomes full-height on small screens.
- The large iframe remains inspection-only. Users use the explicit destination links for the interactive preview or detail workflow.
- Both thumbnail and dialog iframes remove `allow-scripts` and `allow-forms`. They may use `allow-same-origin` for the existing authenticated preview response, avoiding the current `allow-scripts` plus `allow-same-origin` sandbox warning.
- Escape, the close button, backdrop activation, and the native cancel event close the dialog.
- Focus returns to the thumbnail trigger after close.

## Stimulus controllers

### `assistant_workspace_controller.js`

- Targets: tab buttons and panels.
- Value: initial tab, default `"conversation"`.
- Action: select a requested tab.
- Updates active classes, `aria-selected`, panel visibility, and panel `tabindex`.
- Contains no literal user-facing copy.

### `artifact_preview_controller.js`

- Targets: dialog and trigger.
- Actions: open, close, handle backdrop, and handle native cancel.
- Calls `showModal()` when supported and degrades to setting `open` when unavailable.
- Restores focus to the trigger when closing.
- Contains no literal user-facing copy.

Both controllers require matching Vitest suites with 100% line, function, and branch coverage.

## I18n

All new labels are added in matching English and Simplified Chinese locale files under `speech_to_text.assistant`.

Expected keys include:

- `tabs.conversation`
- `tabs.preview`
- `artifact.view_larger`
- `artifact.open_preview`
- `artifact.open_details`
- `artifact.close_preview`
- `artifact.dialog_title`
- `artifact.preview_loading`
- `artifact.preview_unavailable`
- `artifact.opens_new_tab`

English values must be byte-identical to the wording otherwise shown in templates. Chinese values must be concise, idiomatic, and use full-width punctuation where applicable.

## Live updates

The existing Turbo stream remains authoritative:

1. An assistant turn commits a new artifact.
2. `SpeechToText::Stream.broadcast_artifact` replaces `#speech_to_text_artifact`.
3. The replacement includes the current thumbnail, dialog, destinations, and `artifact-preview` controller.
4. The workspace tab state remains unchanged because its controller and panel wrapper are outside the replaced artifact root.

No new persistence or route is required.

## Security and authorization

- All preview and detail URLs continue to use existing admin routes and controller authorization.
- Artifact resolution remains customer-scoped through `SpeechToText::Assistant::Artifact.resolve`.
- No record identifier is accepted from JavaScript.
- No cross-tenant or member/public route is introduced.
- Preview iframes are non-interactive and more restrictive than the current iframe.
- Destination links use server-generated route helpers and `rel="noopener"` when opening new tabs.

## Accessibility

- Mobile tabs use complete tab semantics and keyboard-focusable buttons.
- Thumbnail activation is a real button with a descriptive accessible name.
- The dialog has `aria-modal`, a translated title, an explicit close button, Escape support, backdrop handling, and focus restoration.
- Iframes have distinct translated titles; the decorative thumbnail iframe is removed from sequential focus.
- Visible controls retain focus rings and minimum practical touch targets.
- Empty states do not expose dead actions.

## Testing

### Component and request specs

- Workspace renders mobile tabs and both panels while preserving chat-before-preview DOM order.
- Available and unavailable states remain correct.
- Page artifact renders thumbnail, dialog, secure sandbox attributes, and separate preview/detail links.
- Entity and flowchart artifacts render summaries without page preview UI.
- Empty and unresolved artifacts render guidance without stale links.
- Existing request authorization and cross-tenant coverage remains passing.

### JavaScript

- Write failing Vitest tests before both controllers.
- Cover default state, switching, invalid requested tabs, ARIA updates, dialog open/close, fallback open behavior, backdrop branches, cancel behavior, and focus restoration.
- Run `npx vitest run --coverage` and verify touched JavaScript files remain at 100% lines and branches.

### Rendered QA

- Rebuild Tailwind assets.
- Run the assistant page under `SKIP_AUTH=1 E2E_STUB_ASSISTANT=1`.
- Verify desktop, tablet, and mobile layouts in Chromium.
- Verify the page thumbnail opens the dialog, Escape closes it, focus returns, and preview/detail links point to the current tenant.
- Verify the browser console no longer emits the iframe sandbox warning.

## Out of scope

- Persisted screenshots or thumbnail history.
- Artifact galleries, version comparison, sharing, downloads, or annotations.
- Page-editor or page-rendering-engine redesign.
- Visual thumbnails for entities or flowcharts.
- Assistant model, prompt, provider, tool, or generation changes.
- Member or public assistant access.
