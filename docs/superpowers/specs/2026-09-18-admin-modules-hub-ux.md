# Admin Modules hub + nested chrome — UX spec

Date: 2026-09-18
Audience: frontend. ViewComponent + Tailwind + Stimulus only.

Beautify GET /:cid/admin/modules into a catalog of enabled modules and give nested /:cid/admin/modules/... pages shared identity chrome. No new routes, no Stimulus on the hub, no flowchart chrome, no checkout, no platform module_settings. Reuse Dashboard::ModuleCards and Admin::Dashboard::ModuleCardComponent.

## Hub
Admin::Modules::HubComponent. Header via Admin::Modules::PageComponent. Empty uses EmptyStateComponent. Populated: 1/2/3-col grid of module cards (footer buttons, card is not a link).

## Nested
Wrap bodies with PageComponent (module_key authentication|email|sms|payment). Payments indexes get a real page header. Users show/new/edit and SMS message show join the same header. Email analytics replace zinc/raw colors with admin tokens.
