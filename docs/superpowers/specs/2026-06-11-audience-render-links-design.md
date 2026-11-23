# Audience Render Links on Page Detail — Design

Date: 2026-06-11
Status: approved (autonomous, per standing feedback: drive design to completion after scope is set)

## Problem

The admin page detail page (`/:cid/admin/maintenance/pages/:id`) shows a "Generated Template"
card — a raw ERB dump with no operational value. Admins have no single place to open the page
as it actually renders for each audience (admin / member / public), even though page-level
visibility already gates rendering per audience and each audience has its own themed layout
(`dashboard`, `member`, `public_page`).

## Decision summary

Replace the "Generated Template" card with an **Audience Links card** that shows one row per
audience with an "open rendered view" link, enabled only when the page is published and visible
to that audience. Add the two missing rendered-view routes (admin, member); reuse the existing
public route.

## Routes & controllers

| Audience | URL | Controller#action | Layout | Guards |
|---|---|---|---|---|
| admin | `GET /:cid/admin/maintenance/pages/:page_id/render` | `Admin::Maintenance::PageRendersController#show` | `dashboard` | admin-or-owner; tenant-scoped find; 404 unless `published?` && `visible_to?(:admin)` |
| member | `GET /:cid/member/pages/:id` | `Member::PagesController#show` | `member` | member role; tenant-scoped find; 404 unless `published?` && `visible_to?(:member)` |
| public | `GET /:cid/forms/:token` (existing) | `PublicPagesController#show` (unchanged) | `public_page` | existing behavior |

- Action is named `show` (an action named `render` would shadow Rails' `render`).
- Admin route nests under the existing `resources :pages` block as
  `resource :render, only: :show, controller: "maintenance/page_renders"`.
- Member route is the first entry in the member namespace: `resources :pages, only: :show`.
- Both new controllers resolve the page with the tenant-scoped lookup used elsewhere
  (customer_id from `:cid`), re-check `published?` and `visible_to?(audience)` at request
  time (links may be stale), and render `@page.generate_content` inline, resolving
  `@form_action` the same way `PublicPagesController` does. Real submission continues to go
  through the existing public submit endpoint; no new submit routes.

## UI: Audience Links card

- New ViewComponent `Pages::AudienceLinksCardComponent` (ERB template, Tailwind only),
  replacing `app/views/admin/maintenance/pages/show.html.erb:153-176` ("Generated Template",
  which is deleted along with its `CodeBlockComponent` usage if now unused).
- Placement: immediately after the Visibility card, before Page Information.
- Three rows (Admin / Member / Public): audience label + short description of the themed
  surface, and either
  - an active link with `target="_blank" rel="noopener noreferrer"`, or
  - a disabled non-anchor element with reason text: `Not published` (takes precedence) or
    `Not visible to <audience>`.
- Member row carries a permanent caption: opening it requires being signed in as a member;
  no impersonation is provided.
- Responsive per AGENTS.md (mobile → desktop).

## Out of scope

Impersonation/view-as, changes to `PublicPagesController`, the existing raw preview
route/button (kept as-is), member page listing/navigation, submission from the admin render
view, analytics.

## Testing

- Request specs for both new routes: auth matrix (anonymous → sign-in redirect; wrong role
  denied; correct role 200), cross-tenant 404, unpublished 404, visibility-off 404,
  happy-path renders generated content in the right layout.
- Component spec for `Pages::AudienceLinksCardComponent`: enabled/disabled states per
  (published × visibility) combinations, reason text precedence, new-tab attributes.
- Show view no longer contains "Generated Template".
