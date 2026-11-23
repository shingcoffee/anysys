# AI Assistant Studio canvas — design

Date: 2026-09-08
Status: approved
Audience: `admin` or `owner` at `GET /:cid/admin/assistant`

## Problem

The dedicated AI Assistant workspace already splits chat and preview, but the page is two nested cards on a padded canvas. It should feel like a professional studio: flush, almost borderless, ChatGPT/Claude-calm, with preview as a living page canvas.

## Locked decisions

- **Layout:** Studio canvas — flush split, thin divider, almost no card chrome.
- **Preview:** Always visible on desktop. On phone/tablet, keep Conversation | Preview tabs (one tap).
- **Copy:** Existing English strings stay byte-identical. No new user-facing strings.
- **Capabilities:** Unchanged (composer, dictate, attach, send/stop, copy, regenerate, continue-last, chips, artifact open/preview/dialog, Turbo stream targets).
- **Out of scope:** history sidebar, multi-chat, Home dashboard, Settings/Maintenance/member/public surfaces, provider/schema/API changes.

## Surfaces

| Surface | Change |
|---|---|
| `Admin::Assistants::WorkspaceComponent` | Flush `bg-surface` canvas; no `p-3` gap; no dual `rounded-2xl` cards; desktop split with `lg:border-l` on preview; mobile tabs stay |
| `SpeechToText::AssistantPanelComponent` | Slim header (icon + title); “what” moves into the empty greeting; quieter empty prompts; composer is one docked well; drop redundant subtitle under the composer |
| `SpeechToText::MessageComponent` | Assistant replies are unboxed text; user keeps the accent bubble |
| `SpeechToText::ArtifactPaneComponent` | Page preview fills the pane (living canvas); entity/flowchart: title once + Open details; empty has no dashed inner box |
| Offline empty | Same copy/CTA; flush canvas, no outer card |

## Layout

### Desktop (`lg+`)

Chat column `minmax(0,1.6fr)`, preview `minmax(22rem,0.95fr)`, thin vertical rule via preview `border-l`. No horizontal page scroll.

### Phone / tablet (`< lg`)

Keep the existing tablist. Conversation is default. Preview is one tap. Tabs sit flush at the top.

### Offline

Single centered column: icon, title, body, Open modules. No composer, no preview, no tabs.

## Chat details

- Header: `h2#speech-to-text-assistant-title` stays for a11y. Drop the header “what” line.
- Empty: greeting, then `what`, then `how`, then try-prompt grid and optional recent chips.
- Composer: one `rounded-2xl` input well on a `border-t` dock. Copy / regenerate / continue-last stay visible.
- Keep `data-dashboard-region="chat"`, composer id, stream ids.

## Preview details

- Header: Preview title + kind badge. For pages, Open preview + Open details live in the header so the canvas can fill the rest.
- **Page:** iframe fills `flex-1`, still `sandbox="allow-same-origin"`, `pointer-events-none`, `data-artifact-thumbnail`. Overlay still opens the view-larger dialog.
- **Entity / flowchart:** no duplicate inner card. Label once, kind via badge, Open details.
- **Empty:** centered muted title + body; no dashed box-in-a-box.
- Keep `data-dashboard-region="overview"`, artifact pane id, dialog, `target="_blank"` + `rel="noopener noreferrer"`.
- Page link count stays four `_blank` links (pane header pair + dialog footer pair).

## Testing

Update component specs that pin old grid/card classes or expect `what` in the header when the thread is non-empty. Request spec “prior messages” should not require `what`. Keep Turbo/region/tab/aria/composer/artifact security assertions.

## Success

An admin on `/81721200/admin/assistant` sees a single flush studio: chat left, living preview right, quiet empty/offline states, all existing actions still obvious, responsive on phone/tablet/desktop.
