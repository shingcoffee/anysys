# Customer documentation implementation plan

## Goal

Provide practical English and Simplified Chinese guides through **Help → Documentation** in the authenticated customer backend. Serve the guides at `/:customer_id/admin/help/docs`, using existing admin/owner and tenant authorization. Anonymous users must sign in; members and cross-tenant admins cannot read articles.

## Design

- Keep customer content under `doc/customer/{en,zh-CN}` with a separate allow-listed `CustomerDocs::Catalog`.
- Reuse the Markdown renderer, repository behavior, and responsive ViewComponent reader through explicit catalog/content/label configuration. Existing developer reference defaults remain intact.
- Use customer-oriented labels and task guides, with prerequisites, steps, outcomes, troubleshooting, and related guides. Cover getting started, users, records, forms, websites, payments, email, SMS, settings, billing, assistant, and support.
- Link internally from Help for admin/owner users with a tenant context. Use the backend home menu context for reading room.
- See `docs/superpowers/specs/2026-10-08-customer-documentation-ux.md` for the UI specification.

## Build lanes

1. Backend: parameterize shared repository/renderer and add customer catalog/repository.
2. Frontend: parameterize reader labels, add customer views/locales, and replace Help destination.
3. Security: add routes and thin controller under the existing protected admin prefix.
4. Content: author matching customer guides in both locales; add and register the developer-reference page for the new surface.

## Verification

- Request specs: login required on index/articles, member denial, own-tenant admin success, cross-tenant admin denial, owner support, Chinese articles, unknown slug, search.
- Service specs: every allow-listed page exists in both locales, consistent sections and cross-links, tenant-scoped URLs, traversal rejection, no developer catalog leakage.
- Component specs: internal authorized Help link, anonymous/member absence, customer reader labels and responsive controls, old developer defaults.
- Run targeted specs for the touched layers and shared developer reader/repository/renderer; build Tailwind assets and smoke-test if the environment permits.
- Parallel correctness/security and convention reviews; address concrete issues before completion.
