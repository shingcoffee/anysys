# Templates Index — Professional Directory (v2)

**Date:** 2026-07-25  
**Status:** Approved (agent-decided; user directed autonomous SDLC)  
**PO brief:** `/tmp/sdd-templates-index-v2/po-brief.md`

## Decisions

1. **Filters:** Status + Editor toolbar filters (Suppressions pattern); apply on scope in controller; pass `filters:` to AdminTable for UI.
2. **Directory calm:** Keep Template (name + subject), Editor, Status, Updated. Row click → Edit. No inline Edit link required.
3. **More overflow:** New AdminTable `row_menu_actions:` — Preview, Versions, status transitions in a native `<details>` menu. No long divider link row.
4. **Empty query:** Treat active filters like search for “no matches” empty state (not “create first template”).
5. **Figma:** MCP `needsAuth` — AdminPage / AdminTable / Lists / Suppressions are source of truth.
6. **No schema, no new routes, no commit unless asked.**

## Acceptance

See PO brief §3. I18n en+zh-CN for More + filter labels (reuse status/editor type labels).
