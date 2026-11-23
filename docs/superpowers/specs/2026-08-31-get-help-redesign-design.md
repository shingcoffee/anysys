# Get Help redesign

Admin top-bar Help (`?`) is three actions: notify the platform owner in-app, email `help@anysys.com`, and open the Anysys doc center. Keyboard shortcuts, About, and Service status are removed.

## Decisions (locked)

- Two independent contact channels (not one form, not user-picked).
- Email is an in-app compose form (subject, message, attachments) sent to `help@anysys.com`.
- In-app notify lands in the owner’s bell **and** a Maintenance / Platform queue.
- Owner replies in-app; the requester gets a bell notification.
- Admin top bar only (`admin` / `owner`). Members are out of scope.
- Menu is only Notify / Email / Docs.
- Docs URL is `https://docs.anysys.com` (new tab).
- Platform owner does **not** see “Notify platform owner” (they are the desk). Email and Docs stay.

## Architecture

Two products share the Help menu.

### 1. In-app tickets

Tenant-owned `HelpRequest` (`customer_id`, requester `user_id`, `subject`, `status` `open`/`resolved`, `last_message_at`) plus `HelpRequestMessage` (`customer_id` of the ticket, `user_id`, `author_role` `requester`/`owner`, `body`). Images are `has_many_attached :images` on the message.

`HelpRequestRead` (`customer_id` of the ticket, `user_id`, `help_request_id`, `last_read_at`) unique on `(user_id, help_request_id)`. Unread = a message from the other role is newer than `last_read_at` (or no read row).

Owner queue: `/81721200/admin/maintenance/platform/help_requests` (list + thread + reply + resolve). RouteAuthorization already gates `/admin/maintenance/platform/*` to platform owner.

Requester thread: `/:cid/admin/help_requests/:id` — only the creating user, same tenant. They can reply until resolved.

Bell is a **unified inbox**: existing announcement rows plus help rows.

- Owner (any tenant URL): all open tickets, plus resolved tickets whose last message is within 7 days. Unread when the latest requester message is unseen.
- Admin: their own tickets. Unread when the latest owner message is unseen.
- Click: owner → platform show URL; requester → tenant show URL. Mark-read on open.

Inbox merge lives in `Notifications::Inbox` so `PlatformAnnouncements::InboxResolver` stays announcement-only.

### 2. Email support (not a ticket)

One-shot `Help::Activities::SendEmail` + `HelpMailer.support_request`. To `help@anysys.com`, From `noreply@anysys.com`, Reply-To requester. Body includes subject, message, customer name/id, user name/email, page URL. Attachments ride the mailer. Nothing is stored as a `HelpRequest`.

### 3. Docs

Help menu link, `target="_blank"` `rel="noopener noreferrer"`.

## Routes

Admin (tenant, `RouteAuthorization` admin-or-owner):

- `POST /:cid/admin/help_requests` create
- `GET /:cid/admin/help_requests/:id` show (own ticket)
- `POST /:cid/admin/help_requests/:help_request_id/messages` requester reply
- `POST /:cid/admin/help_emails` send email
- `POST /:cid/admin/help_request_reads` mark bell row read

Platform (owner, 81721200):

- `GET /81721200/admin/maintenance/platform/help_requests` index
- `GET /81721200/admin/maintenance/platform/help_requests/:id` show
- `POST .../help_requests/:help_request_id/messages` owner reply
- `POST .../help_requests/:id/resolution` mark resolved

## Validation

- Subject 1–120 chars; body 1–5000 chars.
- Notify images: jpeg/png/gif/webp, max 5, 5 MB each.
- Email attachments: same images plus PDF, max 5, 5 MB each.
- Cannot reply or notify on a resolved ticket.
- Create is forbidden for the platform owner (UI hidden + controller reject).

## Auth / tenancy

- Create/show/reply on tenant paths: admin-or-owner; record `customer_id` matches URL customer; show/reply additionally require `user_id == current_user.id`.
- Queue/owner reply/resolve: platform owner on 81721200 only. Tenant admins denied (including on their own `/maintenance/platform/help_requests`).
- Cross-tenant: tenant A cannot see tenant B tickets. Owner queue uses unscoped-by-tenant reads of all tickets.
- Owner replies stamp `customer_id` from the ticket, not 81721200.
- Ability: add `:platform_help_requests` to `platform_owner_subjects`.

## Out of scope

- Member chrome, SLA, assignment, categories, public status page, keyboard shortcuts, About, mailto fallback, Email module campaign ledger.
