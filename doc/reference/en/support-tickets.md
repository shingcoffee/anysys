---
title: "Support tickets"
summary: "The platform inbox for tenant help tickets, owner replies, and resolving a thread."
---

## Summary

A tenant admin opens a `SupportTicket` from the admin Help menu. The platform owner reads every tenant's tickets at `/admin/maintenance/platform/support_tickets`, replies as `author_role` `"owner"`, and resolves the thread. The requester's own show and reply stay on `Admin::SupportTicketsController` under `/:cid/admin/support_tickets`.

Both sides call `Help::Activities::AddMessage` and, for the owner, `Help::Activities::Resolve`. The bell that lists recent tickets is `Notifications::Inbox`, which is separate from the platform index. Roles are the three reserved roles; the platform namespace is already limited to `platform_owner?`. See [tenancy and roles](tenancy-and-roles).

The same Help menu provides **Documentation**, which opens the internal customer operational guides at `/:cid/admin/help/docs`. This read-only admin-or-owner surface is distinct from ticket creation, email support, and the owner-only developer reference. See [customer documentation](customer-documentation).

## Flow

```text
Tenant admin
  Admin::SupportTicketsController#create
        |
        v
Help::Activities::CreateRequest
  status open, author_role requester
  SupportTicketRead for the requester
  Notifications::Stream.broadcast_help! -> platform owner
        |
        v
Platform owner
  Admin::Maintenance::Platform::SupportTicketsController
        |  SupportTicket.unscoped_by_tenant
        +-- show -> SupportTicketRead.record!
        +-- SupportTicketMessagesController#create
        |     Help::Activities::AddMessage author_role "owner"
        |     broadcast_help! -> requester
        +-- SupportTicketResolutionsController#create
              Help::Activities::Resolve (status resolved)
```

## Implementation

`SupportTicket` includes `TenantScoped`, with `STATUSES` `open` and `resolved`. It belongs to a customer and a user. `messages` are `SupportTicketMessage` rows with `AUTHOR_ROLES` `requester` and `owner`. Images are attached on the message. `SupportTicketRead` is the per-user cursor; `record!` stores `customer_id` from the ticket, and a unique-index race updates `last_read_at` instead of raising.

`unread_for?` treats a `platform_owner?` viewer as waiting on `author_role` `"requester"`. Every other viewer waits on `"owner"`. A message newer than that user's `last_read_at` (or any counterpart message when they have no cursor) is unread.

The platform index is `SupportTicket.unscoped_by_tenant` with customer, user, reads, and messages, ordered `newest_first`, filtered by `status` through `ModuleEntriesResolver`. `show` records a read for `current_user` and assigns `thread_messages`. The reply controller finds the ticket the same unscoped way and calls `AddMessage` with `author_role: "owner"` and permitted `:body` plus `images: []`. `Resolve` sets `status` to `"resolved"` and returns a failure result when the ticket is already resolved. `AddMessage` refuses a resolved ticket and an unknown author role, validates with `Help::Contracts::Message` (body present, at most 5000 characters), then `Help::AttachmentRules` (jpeg, png, gif, webp; at most 5 files; 5 megabytes each).

`Admin::SupportTicketsController#create` redirects when `current_user.platform_owner?` with `help.errors.owner_cannot_notify`. Otherwise `CreateRequest` opens the ticket for `current_customer` and `current_user`. The tenant reply controller loads `for_customer(current_customer_id).where(user_id: current_user.id)` and posts `author_role: "requester"`.

`Notifications::Inbox#help_scope` uses `inbox_visible`: open tickets, plus resolved tickets whose `last_message_at` is inside `SupportTicket::HISTORY_RETENTION` (7 days). The platform owner sees that scope across tenants. A tenant user sees only their own `user_id`. The platform index does not apply `inbox_visible`.

`HelpMenuComponent#show_docs?` requires an admin-or-owner user and a customer id; `docs_url` calls `admin_help_docs_path(customer_id)` for same-app navigation. `Admin::Help::DocsController` relies on the centralized `RouteAuthorization` and `TenantContext` guards, renders Markdown from `doc/customer` through `CustomerDocs::Repository`, and sets `Cache-Control: private, no-store` for articles and missing-page responses. A customer admin cannot open another customer's guide URL. Developer reference remains under the platform-owner-only maintenance namespace.

## Where to pay attention

### Route audit: reply versus resolution invariant

`Help::Activities::AddMessage` and `Resolve` both reload state under `request.with_lock`. A stale open instance cannot commit a reply after resolution. Message, attachments, last-message time and author read cursor save together; reply notification uses `ActiveRecord.after_all_transactions_commit`. Rejection writes no message/read side effects and sends no reply push.

Requester routes remain opener-private even against peer tenant admins; platform owner routes intentionally read across tenants only under the owner/81721200 platform gate. There is no reopen route. See [Tenancy and roles](tenancy-and-roles), [Announcements](announcements), [Background jobs](background-jobs).

:::note
Stale-instance reply/resolve regressions are authored, not executed here. Live lock contention, read-cursor races beyond these writes and queue/browser notification delivery remain pending.
:::

:::attention
`Admin::Maintenance::Platform::SupportTicketsController` queries `SupportTicket.unscoped_by_tenant`. `TenantScoped` installs no default scope; the explicit unscope is how this inbox avoids `for_customer(current_customer_id)`. The tenant controllers keep `for_customer` and `user_id: current_user.id`.
:::

:::attention
`Help::Activities::AddMessage` writes `author_role` from the controller argument, `"owner"` on the platform messages controller and `"requester"` on `Admin::SupportTicketMessagesController`. `SupportTicket#unread_for?` flips the counterpart with `user.platform_owner?`. A wrong role marks the wrong side unread.
:::

:::attention
`SupportTicketRead.record!` sets `customer_id` to `support_ticket.customer_id`, the ticket tenant. The platform owner's cursor stays on that row when they are acting as another customer. See [customers](customers) for URL context.
:::

:::attention
`Help::Activities::Resolve` only updates `status` to `"resolved"`. `AddMessage` then returns `help.errors.resolved`. The platform resolutions controller has no reopen action. `Notifications::Inbox` drops resolved tickets after `HISTORY_RETENTION`; the platform index keeps listing them.
:::

## Key code

```ruby
# app/controllers/admin/maintenance/platform/support_tickets_controller.rb
def index
  result = ModuleEntriesResolver.call(
    scope:   SupportTicket.unscoped_by_tenant.includes(:customer, :user, :reads, :messages).newest_first,
    columns: index_columns,
    filters: index_filters,
    params:  index_params
  )
  # ...
end
```

```ruby
# app/controllers/admin/maintenance/platform/support_ticket_messages_controller.rb
def create
  request = SupportTicket.unscoped_by_tenant.find(params[:support_ticket_id])
  result = Help::Activities::AddMessage.call(
    request: request,
    user: current_user,
    author_role: "owner",
    params: message_params
  )
  # ...
end
```

```ruby
# app/models/support_ticket.rb
def unread_for?(user)
  return false if user.blank?

  cutoff = reads.find { |row| row.user_id == user.id }&.last_read_at
  counterpart = user.platform_owner? ? "requester" : "owner"
  unseen = messages.select { |msg| msg.author_role == counterpart }
  unseen = unseen.select { |msg| msg.created_at > cutoff } if cutoff
  unseen.any?
end
```

```ruby
# app/services/help/activities/resolve.rb
result = Help::Activities::Resolve.call(request: ticket)
# Persisted state is rechecked under the ticket lock.
```
