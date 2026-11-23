# AI Assistant Workspace Redesign — UX Specification

Date: 2026-09-07  
Status: Ready for frontend  
Audience: authenticated `admin` and `owner` users  
Route: `GET /:cid/admin/assistant` for every tenant

This specification translates the approved live-preview-studio direction into an implementation-ready responsive design. It preserves existing assistant behavior, Turbo updates, authorization, tenant isolation, ViewComponent boundaries, Tailwind styling, Stimulus interactions, and bilingual I18n.

## Design evidence

The following supplied screenshots were inspected directly:

| Evidence | Viewport | Observed strengths | Observed problems |
|---|---:|---|---|
| `01-current-desktop.png` | 1440 × 1000 | Clear chat/preview split; composer stays visible; artifact type is recognizable | Preview is a short 256px iframe with a large unused rail below it; “Open” is ambiguous; thumbnail itself is not actionable |
| `02-current-tablet.png` | 900 × 1000 | Conversation remains readable and controls retain useful sizing | Preview is pushed below the entire conversation, making generated output slow to reach |
| `03-current-mobile.png` | 390 × 844 | Chat bubbles and composer reflow without horizontal overflow | Preview begins below a long fixed conversation surface; page-preview chrome becomes cramped; artifact inspection is not immediately accessible |
| `05-current-page-preview.png` | 1280 × 900 | The authorized preview route provides a truthful current saved render | The useful full render is only available after leaving the assistant; the embedded rail crop does not communicate the complete result |

Screenshot evidence can establish hierarchy, responsive reflow, affordance, and visible contrast risks. Keyboard behavior, screen-reader output, focus containment, and iframe failure handling require implementation testing.

## Design goals

1. Make Conversation and Preview feel like parts of one professional working environment.
2. Keep Conversation primary without treating generated output as a secondary afterthought.
3. Show a recognizable, current saved page render without persisting screenshot files.
4. Let users enlarge the rendered page without losing conversation state.
5. Make full preview and page details explicit, distinct destinations.
6. Keep entity and flowchart artifacts honest: summary cards, not artificial thumbnails.
7. Preserve all existing assistant actions and live-update behavior.

## 1. Surface inventory

| Surface | URL / placement | Nav area | Audience | Change |
|---|---|---|---|---|
| AI Assistant workspace | `/:cid/admin/assistant` | admin | admin / owner | Refactor responsive shell and hierarchy |
| Conversation panel | Workspace primary panel | admin | admin / owner | Visual refinement only; preserve behavior |
| Preview panel — empty | Workspace Preview panel | admin | admin / owner | New composed empty state |
| Preview panel — page | Workspace Preview panel | admin | admin / owner | Fixed-aspect live thumbnail and explicit actions |
| Preview panel — entity | Workspace Preview panel | admin | admin / owner | Summary card without thumbnail |
| Preview panel — flowchart | Workspace Preview panel | admin | admin / owner | Summary card without thumbnail |
| Enlarged page-preview dialog | In-page overlay on Assistant | admin | admin / owner | New responsive dialog |
| Assistant unavailable state | `/:cid/admin/assistant` | admin | admin / owner | Preserve existing centered state |

No member, public, Settings, Maintenance, or module-entry surface is added.

## 2. Workspace layout

### Desktop — `lg` and wider

Use a full-height two-pane workspace with independent scrolling.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Conversation — primary, flexible                       Preview — stable rail │
│ ┌──────────────────────────────────────────────┐  ┌────────────────────────┐ │
│ │ Assistant identity and capability summary    │  │ Preview        [Page]  │ │
│ ├──────────────────────────────────────────────┤  ├────────────────────────┤ │
│ │                                              │  │ Artifact name          │ │
│ │ Scrollable message thread                    │  │ Current saved version  │ │
│ │                                              │  │ ┌────────────────────┐ │ │
│ │                                              │  │ │ live page thumbnail│ │ │
│ │                                              │  │ │   View larger      │ │ │
│ │                                              │  │ └────────────────────┘ │ │
│ ├──────────────────────────────────────────────┤  │ [Open preview]         │ │
│ │ Composer, attachments, send/stop             │  │ [Open details]         │ │
│ │ Copy · Regenerate · Continue last            │  └────────────────────────┘ │
│ └──────────────────────────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

- Root: full available height, `min-h-0`, canvas background, 12px outer gap/padding.
- Grid guidance: conversation approximately 64–68%; Preview approximately 32–36%.
- Recommended desktop columns: `lg:grid-cols-[minmax(0,1.85fr)_minmax(20rem,0.95fr)]`.
- Conversation and Preview each use a rounded surface, subtle border, and low shadow.
- Conversation thread is the only scrolling region inside the left pane.
- Preview body scrolls independently if its content exceeds the rail.
- Composer and Preview header remain visible.

### Tablet and mobile — below `lg`

Do not stack Preview after the transcript. Render a shadcn-inspired two-tab switch above two persistent panels.

```text
┌──────────────────────────────────┐
│ [ Conversation ] [ Preview ]     │
├──────────────────────────────────┤
│                                  │
│ Active panel fills the workspace │
│                                  │
└──────────────────────────────────┘
```

- Both panels remain mounted; switching only changes visibility.
- Default active tab is Conversation.
- The tab switch remains directly reachable above the active panel.
- Conversation retains thread scroll and anchored composer.
- Preview fills the same workspace height instead of appearing below Conversation.
- At 900px tablet width, use the tab design, fixing the supplied tablet failure.
- The enlarged viewer is nearly full-screen on tablet and full-screen on mobile.

### Mobile tab semantics

- Container: `role="tablist"` with a translated accessible label.
- Triggers: `role="tab"`, `aria-selected`, `aria-controls`, and roving `tabindex`.
- Panels: `role="tabpanel"`, `aria-labelledby`, and stable IDs.
- Support click/tap plus Left/Right, Home, and End keys.
- Switching tabs must not recreate the composer, reset draft text, change thread scroll, or interrupt Turbo subscriptions.

## 3. Surface layout specifications

### A. Conversation panel

Reuse `SpeechToText::AssistantPanelComponent` and preserve its public API.

Regions:

1. Header
   - Assistant icon.
   - `speech_to_text.assistant.title`.
   - Existing capability summary.
2. Scroll area
   - Greeting and prompt cards when empty.
   - Recent chips when available.
   - Existing user and assistant message components.
   - Existing stopped, failed, and change-summary states.
3. Composer
   - Dictation, attachments, textarea, send, and stop.
   - Copy, regenerate, and continue-last actions.
   - Existing status and keyboard guidance.

Data:

- `messages`
- `customer_id`
- `user_id`
- `user_name`
- Existing stream name, endpoints, attachment rules, and I18n values

Actions:

- Primary: Send.
- Secondary: dictate, attach, copy, regenerate, continue.
- Stop remains the existing active-generation control.
- No new destructive action.

The redesign must not change Enter-to-send, Shift+Enter-to-new-line, attachment validation, dictation, streaming, or message ordering.

### B. Preview panel shell

Refactor `SpeechToText::ArtifactPaneComponent` into a full-height Card composition:

1. Card header
   - Left: Preview title.
   - Right: artifact-kind `BadgeComponent` when resolved.
2. Card content
   - Empty state, page card, entity summary, or flowchart summary.
3. Card footer
   - Explicit destination actions appropriate to the artifact.

The existing `#speech_to_text_artifact` root remains the Turbo replacement target.

Data mapping:

| Display | Source |
|---|---|
| Artifact kind | `resolved.kind` |
| Artifact name | `resolved.label` |
| Page render | `admin_maintenance_page_preview_path(customer.id, resolved.record)` |
| Page details | `admin_maintenance_page_path(customer.id, resolved.record)` |
| Entity details | `admin_maintenance_entity_path(customer.id, resolved.record)` |
| Flowchart details | `admin_maintenance_flowchart_path(customer.id, resolved.record)` |
| Stream subscription | Current customer ID and conversation user ID |

### C. Page artifact

```text
┌────────────────────────────────────┐
│ Preview                     [Page] │
├────────────────────────────────────┤
│ Page name                          │
│ Current saved version              │
│                                    │
│ ┌────────────────────────────────┐ │
│ │                                │ │
│ │ recognizable live thumbnail   │ │
│ │                                │ │
│ │        [ View larger ]         │ │
│ └────────────────────────────────┘ │
│                                    │
│ [Open preview]   [Open details]    │
└────────────────────────────────────┘
```

Thumbnail:

- Use the current authorized saved-page preview URL; do not store a bitmap.
- Use a fixed `aspect-[16/10]` frame with `overflow-hidden`.
- Render the preview at a reduced visual scale so the frame resembles a page thumbnail instead of a narrow responsive iframe.
- Recommended pure-Tailwind scaling: iframe at `h-[250%] w-[250%] origin-top-left scale-[0.4]`.
- Thumbnail iframe is decorative, `tabindex="-1"`, and non-interactive.
- Do not put an iframe inside a button. Place a full-frame button overlay as a sibling above it.
- The overlay has a descriptive accessible name, visible “View larger” treatment on hover/focus, and a strong focus ring.
- Sandbox: `allow-same-origin` only. Do not include `allow-scripts` or `allow-forms`.

Persistent actions:

- `Open preview`: secondary action, opens the authorized full preview in a new tab with `rel="noopener noreferrer"`.
- `Open details`: primary action, opens page details in a new tab so Conversation remains available.
- External-tab meaning must be visible or included in accessible text.

Loading:

- Show a neutral Skeleton-style frame until the iframe loads.
- Keep artifact name and destination actions available during loading.

Failure:

- Replace the visual frame with an accessible muted fallback, not a broken iframe.
- Offer Retry and retain Open preview/Open details.
- A failed thumbnail must not make the artifact appear deleted.

### D. Enlarged page-preview dialog

New component: `SpeechToText::ArtifactPreviewDialogComponent`.

Use a shadcn-inspired Dialog composition adapted to a native `<dialog>`:

```text
┌────────────────────────────────────────────────────────────────────┐
│ Preview {page name}                                      [Close ×] │
│ Current saved version                                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│                 large live rendered page                           │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ Opens in a new tab              [Open preview] [Open details]      │
└────────────────────────────────────────────────────────────────────┘
```

- Desktop: approximately `92vw` × `88dvh`, capped near `max-w-7xl`.
- Tablet: nearly full viewport with retained rounded corners.
- Mobile: `100vw` × `100dvh`, no outer radius, footer actions stack if needed.
- Required translated title and explicit close button.
- Header and footer remain fixed; preview body owns overflow.
- Large iframe uses the same saved preview URL and restrictive sandbox.
- Defer the large iframe request until the dialog first opens.
- Close through Close, Escape/native cancel, or backdrop activation.
- Closing returns focus to the exact thumbnail trigger.
- Opening and closing never changes the Assistant URL or Conversation state.

Dialog states:

- Loading: centered Skeleton/spinner treatment with translated text.
- Loaded: large rendered page.
- Failed/timed out: inline fallback with Retry, Open preview, and Open details.

### E. Entity and flowchart artifacts

Do not render a page-shaped placeholder.

```text
┌────────────────────────────────────┐
│ Preview                   [Entity] │
├────────────────────────────────────┤
│ [artifact icon] Entity name        │
│ Entity                             │
│                                    │
│                  [Open details]    │
└────────────────────────────────────┘
```

- Use the artifact kind badge, name, a restrained kind-specific icon, and one explicit details action.
- Long names truncate visually but remain available through accessible text/tooltip.
- No “View larger,” iframe, dialog, or screenshot treatment.
- Entity and flowchart cards share the same spacing and hierarchy.

### F. No artifact / unresolved artifact

Use a compact shadcn-inspired Empty composition:

- Quiet artifact icon well.
- Title: “Nothing to preview yet.”
- Existing explanatory copy may be reused or refined.
- No disabled button or dead destination.
- Missing/deleted/unresolvable artifacts use this same safe state.

### G. Assistant unavailable

Preserve the current centered single-panel treatment:

- AI Assistant title.
- Existing explanation.
- Primary Open modules action.
- Do not render tabs or an empty Preview panel when the assistant itself is unavailable.

## 4. Interaction flows

### Open and use the workspace

1. Admin/owner opens `/:cid/admin/assistant`.
2. Desktop shows Conversation and Preview together.
3. Tablet/mobile opens Conversation with Preview one tab away.
4. Existing messages, draft behavior, composer actions, and stream subscription continue unchanged.

### Inspect a generated page

1. Assistant completes an action and assigns a page artifact.
2. Existing Turbo broadcast replaces `#speech_to_text_artifact`.
3. The Preview panel updates to the newest current saved render without a page reload.
4. User activates the thumbnail by pointer, Enter, or Space.
5. Enlarged dialog opens and focuses its Close control or heading region.
6. User closes it; focus returns to the thumbnail.

### Navigate from the artifact

- Open preview → authorized full page preview in a new tab.
- Open details → authorized page detail in a new tab.
- The original Assistant tab preserves conversation and composer state.

### Mobile Preview access

1. User activates Preview in the tab switch.
2. Preview panel appears in place without moving or recreating Conversation.
3. User returns to Conversation; thread position and draft remain intact.

### Entity or flowchart artifact

1. Turbo updates Preview with the resolved artifact.
2. Summary card displays name and kind.
3. Open details navigates to the existing tenant-scoped detail destination.

### Failure flows

| Failure | Result |
|---|---|
| Assistant provider fails | Existing in-thread failure message; Preview keeps its last valid artifact |
| Preview iframe is slow | Loading state; destinations remain usable |
| Preview iframe fails | Fallback + Retry + destination links |
| Artifact was deleted/unresolved | Empty Preview state; no stale link |
| Assistant module/provider unavailable | Existing unavailable state and Open modules action |
| Anonymous/member access | Existing admin controller authorization denies access |
| Cross-tenant ID manipulation | Existing customer-scoped resolution and destination authorization deny access |

## 5. Component reuse map

| Layout piece | Reuse / change |
|---|---|
| Workspace shell | Refactor `Admin::Assistants::WorkspaceComponent` |
| Conversation | Reuse `SpeechToText::AssistantPanelComponent` |
| Artifact stream root and branching | Refactor `SpeechToText::ArtifactPaneComponent` |
| Enlarged page viewer | **New** `SpeechToText::ArtifactPreviewDialogComponent` |
| Surface/card language | Reuse project `CardComponent` conventions and semantic surface tokens |
| Actions | Reuse `ButtonComponent` |
| Artifact kind | Reuse `BadgeComponent` |
| Empty state language | Adapt project empty-state conventions inside the artifact pane |
| Tabs | New Assistant-specific workspace controller and semantic tab markup |
| Tooltips | Reuse `tooltip_controller` only for icon-only/overflow hints; never replace visible action labels |
| Live chat | Reuse existing Turbo streams and `speech_to_text_assistant_controller` |

No React component, shadcn runtime, custom CSS, or new JavaScript framework is introduced.

## 6. shadcn composition adaptation

| shadcn pattern | Anysys implementation |
|---|---|
| Card | Header/content/footer regions inside ViewComponents using project surfaces, borders, and shadows |
| Dialog | Native dialog + ViewComponent + Stimulus; required title, close, body, footer, focus restoration |
| AspectRatio | Tailwind `aspect-[16/10]` thumbnail frame |
| ScrollArea | `min-h-0 overflow-y-auto` regions; no custom scrollbar dependency |
| Tabs | Semantic two-trigger tablist below `lg`; persistent panels and roving keyboard focus |
| Tooltip | Existing controller for icon-only or truncated-content hints, always paired with accessible names |
| Skeleton | Project semantic neutral blocks while a preview loads |

## 7. Tailwind guidance

Use only existing semantic tokens.

Workspace:

- `grid h-full min-h-0 gap-3 bg-canvas p-3`
- `lg:grid-cols-[minmax(0,1.85fr)_minmax(20rem,0.95fr)]`
- Panel: `min-h-0 overflow-hidden rounded-2xl border border-border-subtle bg-surface shadow-xs`

Mobile tabs:

- Wrapper: `grid grid-cols-2 rounded-xl bg-surface-active p-1`
- Trigger: `min-h-11 rounded-lg px-3 py-2 text-sm font-medium transition-base`
- Active: `bg-surface text-text-primary shadow-xs`
- Inactive: `text-text-muted hover:text-text-primary`
- Focus: existing `focus-visible:ring-2 focus-visible:ring-accent`

Artifact:

- Stack: `flex min-h-0 flex-1 flex-col gap-4`
- Header/footer: `border-border-subtle px-4 py-3`
- Thumbnail: `relative aspect-[16/10] overflow-hidden rounded-xl border border-border-subtle bg-canvas`
- Summary card: `rounded-xl border border-border-subtle bg-canvas-elevated p-4`
- Avoid raw blue/purple values; use `accent`, `surface`, `canvas`, `text-*`, `border-*`, `danger`, and `success`.

Dialog:

- `m-auto flex h-[100dvh] w-full max-w-none flex-col overflow-hidden bg-surface p-0`
- `sm:h-[88dvh] sm:w-[92vw] sm:max-w-7xl sm:rounded-2xl`
- Backdrop uses a project-consistent dark translucent scrim and light blur.
- Mobile footer: `flex flex-col-reverse gap-2`; `sm:flex-row sm:justify-end`.

## 8. Stimulus specification

### `assistant_workspace_controller.js`

Targets:

- `tab`
- `panel`

Values:

- `active`, default `conversation`

Actions:

- `select`
- `keydown`

Responsibilities:

- Update active classes.
- Update `aria-selected` and roving `tabindex`.
- Hide/show panels without removing them.
- Support Left/Right/Home/End keyboard navigation.
- Retain active tab while an artifact Turbo replacement occurs.
- Contain no user-facing string literals.

### `artifact_preview_controller.js`

Targets:

- `dialog`
- `trigger`
- `frame`
- `loading`
- `failure`

Values:

- `src`
- numeric load-timeout value if timeout handling is implemented

Actions:

- `open`
- `close`
- `cancel`
- `backdrop`
- `loaded`
- `failed`
- `retry`

Responsibilities:

- Open the native dialog.
- Lazily assign the large iframe source.
- Toggle loading/loaded/failure states.
- Close through supported dismissal paths.
- Restore trigger focus.
- Clean up timers when disconnected or Turbo-replaced.
- Contain no user-facing string literals; translated markup comes from the server.

All added or changed JavaScript requires mirrored Vitest coverage at 100% lines, functions, and branches.

## 9. I18n contract

Add matching keys to both `speech_to_text.en.yml` and `speech_to_text.zh-CN.yml`.

| Key suffix under `speech_to_text.assistant` | English | Simplified Chinese |
|---|---|---|
| `tabs.label` | `Assistant workspace` | `助手工作区` |
| `tabs.conversation` | `Conversation` | `对话` |
| `tabs.preview` | `Preview` | `预览` |
| `artifact.current_saved` | `Current saved version` | `当前已保存版本` |
| `artifact.view_larger` | `View larger` | `放大查看` |
| `artifact.thumbnail_label` | `View larger preview of %{name}` | `放大查看“%{name}”的预览` |
| `artifact.open_preview` | `Open preview` | `打开完整预览` |
| `artifact.open_details` | `Open details` | `打开详情` |
| `artifact.dialog_title` | `Preview %{name}` | `预览“%{name}”` |
| `artifact.close_preview` | `Close preview` | `关闭预览` |
| `artifact.preview_loading` | `Loading preview…` | `正在加载预览…` |
| `artifact.preview_unavailable` | `Preview is unavailable.` | `暂时无法显示预览。` |
| `artifact.retry` | `Retry` | `重试` |
| `artifact.opens_new_tab` | `Opens in a new tab` | `将在新标签页中打开` |
| `artifact.empty_title` | `Nothing to preview yet` | `暂无可预览内容` |

Reuse existing keys when their English value is byte-identical. Do not place translated calls in Ruby constants.

## 10. Accessibility requirements

- Preserve logical DOM order: Conversation before Preview.
- Desktop visual columns must not alter reading order.
- Tab controls need complete keyboard and ARIA behavior.
- Thumbnail uses a real button overlay with at least a 44px practical target.
- Dialog has a translated title, modal semantics, Escape support, and focus restoration.
- Thumbnail iframe is removed from sequential focus; dialog iframe has a distinct translated title.
- Visible labels remain for Open preview and Open details.
- Tooltips supplement, never replace, labels and accessible names.
- Artifact updates may use `aria-live="polite"` on the artifact summary, but must not auto-switch the user to Preview.
- Loading and failure states communicate in text, not color alone.

## 11. Frontend verification checklist

- Desktop 1440 × 1000: two panes, independently scrolling, composer visible.
- Tablet 900 × 1000: tab switch, no Preview below Conversation.
- Mobile 390 × 844: tab switch, no horizontal overflow, full-screen dialog.
- Thumbnail click/Enter/Space opens the enlarged viewer.
- Escape, close, and backdrop dismiss; focus returns correctly.
- Open preview and Open details use the current customer and resolved record.
- Page artifact updates through Turbo without resetting the active workspace tab.
- Entity/flowchart artifacts never render a page thumbnail.
- Empty and deleted artifact states expose no stale links.
- Sandbox console warning from `allow-scripts` + `allow-same-origin` is eliminated.
- English and Simplified Chinese layouts remain readable.
- Component specs, request authorization specs, targeted browser checks, and mandatory JavaScript coverage pass.

## Out of scope

- Persisted screenshots, thumbnail files, or thumbnail history.
- Artifact galleries, comparison, sharing, download, or annotation.
- Page editor or page rendering engine redesign.
- Visual thumbnails for entities or flowcharts.
- AI model, prompt, provider, tool, or generation changes.
- Member or anonymous Assistant access.
- Authorization, tenant ownership, or reserved-role changes.
