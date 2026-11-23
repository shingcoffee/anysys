---
title: "Announcements"
summary: "Platform-owner banners with a time window, a draft or published status, and an all-customers or segmented audience."
---

## Summary

`PlatformAnnouncement` is a platform catalog row: it has no `customer_id`. `Admin::Maintenance::Platform::AnnouncementsController` creates and edits it through `PlatformAnnouncements::Activities::Save` and `PlatformAnnouncements::Contracts::Announcement`. A live row becomes the admin-shell banner `Platform::AnnouncementBannerComponent`. The bell history is `PlatformAnnouncements::InboxResolver`. Dismiss and mark-read sit on the tenant admin prefix, so a customer admin can post them.

The platform namespace is already limited to `platform_owner?`. Audience fields and the customer columns they may filter are described with [customers](customers).

## Flow

```text
POST /:cid/admin/maintenance/platform/announcements
        |
        v
AnnouncementsController#save_and_respond
        |
        v
PlatformAnnouncements::Activities::Save
        |  TargetRules.parse + Contracts::Announcement
        v
PlatformAnnouncement
        |
        +-- live? -> Notifications::Stream.sync_announcement!
        |              recipients: active tenant admins of matching customers
        |              scheduled starts_at -> BroadcastAnnouncementJob
        +-- destroy -> discard_or_destroy!
        |
        v
Admin shell
        |
        +-- AnnouncementBannerComponent
        |     Resolver.for_viewer (skips dismissals, max 3)
        +-- Notifications::Inbox
              InboxResolver (live + 7-day history, ignores dismissals)
```

## Implementation

Constants on the model: `SEVERITIES` are `info`, `warning`, `critical`. `STATUSES` are `draft` and `published`. `AUDIENCES` are `all` and `selected`. `live?` means kept, published, and inside `starts_at` / `ends_at` (`nil` on either side is open). `lifecycle` is `:draft`, `:scheduled`, `:live`, or `:ended`. `body_for` returns `body_zh` when the locale string starts with `zh`, otherwise `body_en`.

`Save.sanitize` blanks `link_url`, `starts_at`, and `ends_at` to nil, parses `target_rules_json` with `TargetRules`, and stores `TargetRules::EMPTY` unless `audience` is `selected` or the JSON is malformed. The contract requires both bodies (500 characters), a title (120), a severity, a status, and an audience. `link_url` must match `https?://` and parse as an HTTP URI with a host and no userinfo. A `selected` audience must be usable `CustomerQuery` rules. An empty or unusable segment matches `Customer.none`.

`CustomerFieldCatalog` is the compiler allowlist. Unknown/invalid fields, operators, joins, value types or trees reject the entire selected audience instead of dropping a condition and broadening it. Arel binds values; LIKE wildcards are literal. `AudienceResolver` scans keyset batches of 100 and caps results only after tenant eligibility. Banner ordering prioritizes critical/warning/info before its candidate cap and displays at most three; inbox is newest-first, includes seven-day history and ignores dismissals. Query count scales with scanned batches, not a globally constant budget.

`audience_preview` posts the JSON and returns `{ count, sample }` of five customers, or 422 when `TargetRules` is malformed. It evaluates the posted rules only. On show, `PlatformAnnouncement#matching_customers` returns `Customer.none` unless the row is segmented, and `@matching_count` is nil when `all_customers?`. A segmented row lists at most `MATCHING_CUSTOMERS_LIMIT` (50) names. `AnnouncementPresenter` formats badges and does not count the segment on the index.

`destroy` calls `discard_or_destroy!`. A live, ended, or previously live row gets `deleted_at`. A draft or a scheduled row that never went live is `destroy!`. When the row is still persisted, `Notifications::Stream.sync_announcement!` runs with the recipients captured before the discard.

## Where to pay attention

### Route audit: audience and live-window invariants

Selected rules require valid catalog fields/operators, signed-64-bit integer IDs, finite numbers, real enum values and ISO dates, with bounded joins/depth (12)/nodes (500). Contract/model/preview reject malformed trees; historical malformed rules fail closed on reads. Empty selected rules never mean all customers. More than 50 irrelevant newer notices cannot crowd out an eligible older/critical notice.

`Notifications::ExpireAnnouncementJob.schedule` captures exact ends_at and refreshes the existing signed per-user stream at expiry. The job locks/reloads the record and ignores deleted/draft/rescheduled/end-mismatched work. Refresh removes expired banner state while preserving bell history; scheduled start and expiry remain separate jobs. Read/dismiss actions retain viewer/customer eligibility. See [Background jobs](background-jobs), [Customers](customers), [Tenancy and roles](tenancy-and-roles).

:::note
Malformed-audience, multi-batch/severity and expiry-stream regressions are authored, not executed here. Open-browser refresh and production queue timing remain unverified.
:::

:::attention
`AnnouncementsController` documents that `/admin/maintenance/platform/*` is already gated by `RouteAuthorization`. It sets no role `before_action`. Dismissals are `Admin::PlatformAnnouncementDismissalsController` and reads are `Admin::PlatformAnnouncementReadsController`, both under `/:cid/admin/`, because a tenant admin must be able to POST them.
:::

:::attention
`PlatformAnnouncements::CustomerQuery` matches nobody when the rules are empty or unusable. `Save` also clears `target_rules` when `audience` is `all`. A selected announcement with a blank builder cannot publish, and it cannot fall through to every customer.
:::

:::attention
`Notifications::Stream.announcement_recipients` is `Authentication::User.unscoped_by_tenant.active.by_role(:admin)` for the matched customers. The comment on `Stream` says announcement pushes never go to the platform owner. `AnnouncementBannerComponent` still renders for `platform_owner?` on a full page load via `Resolver`.
:::

:::attention
`PlatformAnnouncementDismissal` is per user and per customer, and `Resolver` hides those ids from the banner. `InboxResolver` does not look at dismissals. `PlatformAnnouncementRead` is the bell cursor only.
:::

## Key code

```ruby
# app/models/platform_announcement.rb
def live?(now: Time.current)
  deleted_at.blank? &&
    status == "published" &&
    (starts_at.nil? || starts_at <= now) &&
    (ends_at.nil? || ends_at > now)
end
```

```ruby
# app/services/platform_announcements/activities/save.rb
def self.call(record:, params:)
  was_live = record.persisted? && record.live?
  previous_users = was_live ? Notifications::Stream.announcement_recipients(record).to_a : []
  attributes = sanitize(params)
  record.assign_attributes(attributes.slice(*ATTRIBUTES))

  contract = PlatformAnnouncements::Contracts::Announcement.new(record)
  unless contract.validate(attributes)
    return Result.new(success?: false, model: record,
                      errors: contract.errors.messages.to_h, messages: contract.errors.full_messages)
  end

  persist!(record, contract, was_live: was_live)
  Notifications::Stream.sync_announcement!(record, previous_users: previous_users)
  Result.new(success?: true, model: record, errors: {}, messages: [])
end
```

```ruby
# app/services/notifications/stream.rb
def self.announcement_recipients(announcement)
  customer_ids = announcement_customer_ids(announcement)
  return Authentication::User.none if customer_ids.blank?

  Authentication::User.unscoped_by_tenant.active.by_role(:admin).where(customer_id: customer_ids)
end
```

```ruby
# app/components/platform/announcement_banner_component.rb
def viewer_allowed?
  viewer.present? && (viewer.admin? || viewer.platform_owner?)
end
```
