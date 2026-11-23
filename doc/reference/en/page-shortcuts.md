---
title: "Page shortcuts"
summary: "Map any eligible website or public form page to a chosen root, single-segment or nested URL, with host-aware tenant routing."
---

## Summary

Page shortcuts are customer-owned mappings from a path to a `WebsitePage` or public `Page`. This is general URL mapping: `/`, `/join`, and `/campaign/register` are examples, not separate features. A shortcut renders the destination directly and keeps the chosen address in the browser. Website home and inner-page paths also work automatically without saved mappings.

Management lives at `/:cid/admin/maintenance/page_shortcuts`, alongside the Maintenance landing card and sidebar entry. Website settings and tenant Maintenance → Pages link to the same screen. The platform shared-page list does not advertise tenant mappings. See [Websites](websites), [Website builder](website-builder), and [Page rendering](page-rendering).

## Flow

```text
Maintenance → Page shortcuts
  Choose customer-relative path + WebsitePage:<id> or Page:<id>
  POST create / PATCH update / DELETE remove (native Rails forms)
  Invalid input → 422, retained values and server errors
  Saved mapping → host + request.path_info → tenant + target
    WebsitePage → existing website home/show rendering
    Page        → existing public-page rendering/submission
```

Edit is a normal GET to the index with `?edit=<id>#shortcut-form`. The form then submits PATCH to that record. Remove submits DELETE with Rails' hidden method field and CSRF protection; removing the shortcut keeps the destination page. Forms set `data-turbo="false"` and need no JavaScript.

## Implementation

### Host and path configuration

Each customer's exact domain is the nullable string `customers.domain`, set by the platform owner on that customer's profile form, beside the organization name. For example, configure a direct CNAME to `anysys.net` for `forms.acme.example`, then save that domain on customer 12345678. See [Custom domains](custom-domains).


`PageShortcuts::Hosts.customer_id` and `dedicated?` read live database bindings; committed changes take effect without restart. `config.x.page_shortcuts.default_customer_id` defaults to `81721200`. A normalized domain is globally unique, and each customer has at most one. Inactive bindings remain stored and return 404 instead of default-tenant content. Saving a new or changed domain requires a direct answer-section CNAME from that exact domain to `anysys.net`; A/AAAA-only records and indirect alias chains fail. Clearing the domain, or saving the profile without changing it, does not check DNS. Deployment publishes DNS and separately configures TLS, ingress and Rails HostAuthorization; saving a domain does not admit a host to Rails' allowlist.

An unprefixed path uses the mapped host's customer, otherwise the default customer. An explicit eight-digit customer prefix takes precedence. Signed-in session state never selects the destination tenant. On the shared host, customer 81721200 gets `/` and `/pricing`; another customer gets `/:cid/` and `/:cid/pricing`. A dedicated mapped host gets unprefixed paths for its customer.

### Mapping and availability

Only `WebsitePage` and `Page` are accepted target types. Website targets belong to the selected customer's website and require the Website module, site, and page to be published. Public form targets must be active, launched, public-visible, and either owned by that customer or shared. Shared definitions use `Current.customer` and `resolved_current_version` so the customer's override renders.

Routing constraints reuse `Resolver.cached_resolve(request)` for one request-local resolution. A single fallback glob per fixed destination handles both prefixed and unprefixed paths; the resolver extracts the customer prefix. Root routes remain explicit so unavailable mappings and bootstrap fallback keep their distinct behavior. `RouteContext` retains the trusted resolved target, and website dispatch looks up its record ID within the selected customer and website, rechecking publication. Slug reuse or a home-page change between resolution and dispatch cannot substitute another record. Canonical website endpoints still use their normal home/slug lookup.

`PageShortcuts::Activities::Save` and `Websites::Activities::SavePage` share `Collisions.with_customer_lock(customer_id:)`. The transaction locks the active customer before collision validation, generated slugs and persistence; on SQLite, Rails uses an immediate write transaction. Persisted shortcuts reload within their explicit customer scope before constructing the Reform contract: submitted fields apply to the latest row, while omitted fields retain its current values. Invalid updates leave the stored mapping intact; unique-index conflicts return localized errors. Direct model writes do not enforce this cross-table rule—application writes must use the activities.

Paths are customer-relative, begin with `/`, and can use lowercase kebab-case segments with interior single dots, such as `/join.html` or `/campaign.v2/join`. `/` is allowed. Leading/trailing dots and repeated separators are rejected. Application namespaces and numeric leading segments remain reserved, including formatted spellings such as `/admin.json` and `/12345678.html`. Schemes, hosts, queries, fragments, escapes, traversal, repeated slashes, controls and whitespace are rejected. Automatic website slugs remain single kebab-case segments without dots: dotted paths require an exact saved mapping and never infer a format or fall back to an undotted alias. Automatic website-slug collisions are validated by the backend path/collision policy. Root mappings can choose a different destination from the website home. Existing canonical website and UUID endpoints remain available.

The 255-byte path limit applies to the stored customer-relative path, including its leading slash. The optional `/:cid` prefix and deployment `SCRIPT_NAME` do not count toward that limit: a valid 255-byte alias remains reachable through its 264-byte customer-prefixed router path and through mounted URLs. The resolver recognizes only a canonical eight-digit prefix, validates the relative suffix with the same path policy, and rechecks the original URI after removing the mount. Prefix extraction does not relax reserved namespaces or permit encoded/malformed prefixes, repeated separators, traversal, or overlong relative paths.

`PageShortcuts::Resolver.resolve(request)` accepts GET/HEAD for eligible website and public `Page` targets, and POST exclusively for eligible public `Page` mappings. A `Page` target must have `public` in the audience set (`Page.for_audience("public")`); a member-only page cannot be a shortcut target. POST uses the same publication, public-audience and explicit tenant/shared ownership checks as reads, including root and dedicated-host mappings. Its immutable Page target retains `action: "show"`; `PageShortcuts::RouteConstraint` selects the existing `public_pages#submit` destination for POST. Other write verbs and website POST aliases do not resolve.

The [Captcha gate](captcha) matches an alias against its trusted target's canonical throttle path. Exact original-path lookup happens before known canonical-route format normalization: `/join.html` and `/join` can select different targets and policies. Canonical counters, skipped rules and grants apply to aliases too. Challenge return paths and POST snapshots retain the original alias, query, body and mount; replay clears stale routing state and passes through normal authorization and publication checks again. Query/body identity cannot select a different throttle rule or submission target.

The creation select offers currently eligible targets. Saved offline or deleted mappings stay visible, show **Unavailable**, retain their destination identity when editing, and can still be removed. Only available destinations receive public links. Request-time checks remain authoritative; publication changes never bypass access controls. An unavailable saved mapping fails closed rather than switching to another page at the same address.

### Presentation and libraries

`PageShortcuts::ManagementComponent` accepts `shortcuts:`, `available_targets:` (`[label, "Type:id"]` pairs), `customer_id:`, and optional `errors:`, `form_values:`, and `editing_shortcut:`. It uses the shared admin shell, cards, explicit labels, linked field hints/errors, an alert summary, a native select, and a semantic table whose rows stack below `md`. EN and zh-CN text lives under `page_shortcuts` in paired locale files. Backend validation messages use separate `page_shortcut_errors.*` files.

Management select labels use `TargetEligibility` scopes and scalar `pluck` reads. The component keeps one `Lookup.new(customer_id:, host:, include_titles: true)` for saved labels, availability and host-aware links. `Lookup#shortcut_available?` also builds preferred public aliases, sharing canonical-path, target and collision checks. `#target_title(type, id)` reads website titles and one batch of saved owned/shared Page names, including retained offline/deleted rows; missing or foreign records have no label. Neither the controller nor component preloads polymorphic targets or loads Page definitions, and query counts stay bounded as rows grow. Ordinary public lookup omits this optional name query.

`PageShortcuts::PublicPath` owns `website_home`, `website_page`, `website_slug`, `public_page`, `public_page_uuid(uuid:, customer_id:, host: nil)`, and `shortcut`. Presentation callers pass `request.host`; `PageShortcutsHelper#page_shortcuts_mounted_path` adds Rack's `SCRIPT_NAME`. Without a host, the service applies shared-host defaults. Saved valid local website and UUID destinations are translated by `Websites::Href.resolve(value, customer_id:, host: nil)`. UUID resolution returns the preferred alias for an eligible local/shared public Page, or its canonical UUID path when no alias exists; unavailable/foreign/unknown identities return nil and Href retains the original canonical link. External HTTPS, media, and unrelated app paths retain their existing handling; locale, repeated query pairs and fragments survive.

`PageShortcuts::PublicPathContext` wraps the two public controllers with `PublicPath.with_lookup(customer_id:, host: request.host)`. The optional `host:` defaults to nil, preserving existing service calls. It installs an immutable `PageShortcuts::Lookup` in `Current.page_shortcuts_lookup` only for that authorized customer's rendering/submission scope. Website identities (including unpublished collision slugs), shortcut identities, and all eligible owned/shared public Page UUID-to-identity mappings are read in batches, including Pages without aliases. The snapshot captures only the supplied normalized host and its selected customer ID once, alongside site/module availability; mixed website/UUID navigation and footer SQL stays bounded as distinct destinations increase. It is not a hostname registry: other hosts/customers and direct `Hosts` calls still use live queries. UUID links use scalar identities and never instantiate Page or invoke its definition-loading after-find callback. The around-action/block restores the previous value even on exceptions and nested host scopes, and Rails resets Current between requests. Service calls outside the block remain fresh database reads, and the next rendering scope/request sees hostname, alias and publication changes. Routing and save validation never use this presentation snapshot.

This uses mature Rails Action Dispatch/Journey routing and the existing Addressable URI library rather than custom rewrite middleware or URI parsing. Public rendering and section/footer/navigation links reuse existing ViewComponents and Tailwind.

## Where to pay attention

### Route audit: all slug writers and replay invariants

Website provision, direct skeleton application and replacement share `Collisions.with_customer_lock` with shortcut and SavePage writes. Whole structure and every candidate path are checked before deleting old pages; malformed/colliding replacements preserve existing pages/mappings. Public foreign sessions may visit eligible targets but never choose their tenant or gain same-tenant attribution.

Captcha canonical policy covers known optional-format endpoints and aliases. Replay preserves original path/query/body/mount and CSRF/origin evidence, binds the same session, then rechecks target identity/publication. Solving a challenge does not authorize an originally invalid write. See [Captcha](captcha), [Websites](websites), [Page rendering](page-rendering).

:::note
Shortcut path-policy, resolver, and CAPTCHA replay specs cover tenant, publication, and format boundaries. On 2026-10-12 the parallel RSpec suite passed **25,266 examples, 0 failures**. Live browser journeys remain a separate check.
:::

:::attention
Management is admin/owner-only and URL-tenant scoped for edit/update/delete. Public reads admit anonymous and foreign signed-in visitors only to eligible published targets; protected cross-tenant restrictions remain. See [Tenancy and roles](tenancy-and-roles).
:::

:::attention
GET/HEAD aliases render website or public-form pages. Public-form aliases also accept POST through the existing submission authorization and flowchart pipeline; website aliases do not accept POST. Generated forms continue to use the canonical `/:cid/page/:uuid` action, not the current alias. The mapping does not change a page's audiences or publication status.
:::

:::attention
At `/`, an eligible explicit mapping takes precedence; without a mapping, the published website home is automatic. A saved unavailable root mapping reaches a fixed `PageShortcuts::UnavailableController#show` route and returns an empty 404 on GET/HEAD, including missing/private/deleted targets and inactive customers, on shared or dedicated hosts. A dedicated host mapped to a missing/inactive customer also returns 404. On a shared host with no explicit mapping and no published automatic home, the existing HomeController sign-in/landing fallback remains available even before the default platform customer exists, supporting bootstrap. A known inactive default (a row still present when queried unscoped) returns 404 rather than bootstrap fallback. Removing a root mapping restores automatic home or the applicable fallback. `Resolver.resolve` still returns Target/nil; `Resolver.unavailable_root?` distinguishes terminal root failures without giving captcha/link code a sentinel target.
:::

## Key code

```ruby
PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: request.host)
PageShortcuts::PublicPath.website_page(page: page, host: request.host)
PageShortcuts::PublicPath.public_page(page: page, customer_id: cid, host: request.host)
Websites::Href.resolve("/81721200/site/pricing?tag=a&tag=b#plans", customer_id: cid, host: request.host)
```

```ruby
render PageShortcuts::ManagementComponent.new(
  shortcuts: @shortcuts, available_targets: @available_targets,
  customer_id: current_customer_id, errors: @errors || [],
  form_values: @form_values || {}, editing_shortcut: @editing_shortcut
)
```
