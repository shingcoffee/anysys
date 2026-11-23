# Admin Pages Ops List — Design

**Date:** 2026-08-06
**Status:** Approved (proceed without further confirmation)

## Goal

Make `/:cid/admin/pages` (including `/entities/:id` and `/uncategorized`) an ops-only surface for customer admins: Preview, Launch/Take offline, and Control visibility. Page builder create/edit stays under Maintenance.

## UX

- Remove Status column (confusing vs Launched). Keep Launched + Visibility badges.
- Remove Edit row action, row→edit navigation, New Page header button, and empty-state create CTA.
- Row actions: Preview (new tab), Launch/Take offline, Manage access.
- Row name click / Manage access opens a right publishing slide-over (reuse slide-over Stimulus + turbo-frame).
- Slide-over content mirrors Maintenance Distribution card: launch, audience visibility toggles, Open links, Preview in header.

## Technical

- `GET /:cid/admin/pages/:id` → turbo-frame `page-publishing` with PublishingPanelComponent.
- Reuse maintenance launch/visibility/preview endpoints with safe `return_to`.
- AdminTableComponent optional `row_path_data` for turbo_frame targeting.
- I18n en + zh-CN.

## Out of scope

Maintenance builder/delete/copy/versions; Status semantics; batch activate UI.
