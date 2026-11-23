---
title: "Person linking"
summary: "How an entry of a person entity is linked to one same-tenant user account, how ownership kinds decide which rows each audience may reach, and what the link unlocks on admin and member surfaces."
---

## Summary

A **person entity** is an entity whose `extended_model` is `EntityDefinitions::Capabilities::PERSON_MODEL` (`Authentication::User`) — Student, Patient, Volunteer. `Entity#person?` answers it; a bridge never qualifies. A business domain has at most one person entity (see [Operations API](operations-api)).

Each entry of a person entity may be linked to **one** user of the same tenant through the nullable `entity_entries.user_id` column. The user is the login identity (credentials, roles, MFA); the entry is the domain profile. The link is optional, so people who never sign in are still recorded.

Identity fields (`People::IDENTITY_KEYS`: `first_name`, `last_name`, `email`) exist in exactly one place at a time:

| Entry state | Where identity lives |
|---|---|
| Not linked | The entry's `data`, under the reserved keys. They cannot clash with attribute slugs, because an extension of a base model may not declare its columns. |
| Linked | On the `User` only; the keys are removed from the entry. |
| Unlinked again | The user's current values are copied back into the entry. |

Linking never changes roles. The link is also how `People::Ownership` finds the viewer's own person rows: member surfaces, reference dropdowns, and form submit bind through those linked entries. Public registration writes an unlinked person entry plus a pending claim; the first confirmation (or a later sign-in) completes it and records `person.claimed`. Identity fields on a person-entity form reach the flowchart as `ctx[:identity]` — see [Page builder](page-builder) and [Audience flows](audience-flows). How each audience gets its own page and flowchart for the same action is [Audience flows](audience-flows).

## Flow

1. An admin opens `/:customer_id/admin/entities/:entity_id/entries/:id` for a person entity. `Admin::Entities::EntryDetailComponent` renders `Admin::Entities::PersonLinkComponent` (the Account card) first in the aside.
2. Not linked and writable: **Link user account** opens the `person-link-picker` combobox. It debounces input (250 ms, at least two characters) and calls `GET …/entries/:entry_id/person_link/candidates?q=` for `{ "users": [{ "id", "name", "email" }] }`.
3. Choosing a user shows an in-card confirmation; **Link** posts `user_id` to `POST …/entries/:entry_id/person_link`.
4. `People::Link.link!` runs `People::Activities::Link` under the customer row lock, validates `People::Contracts::Link`, sets `user_id`, drops the identity keys from `data`, records `person.linked`, and the controller redirects back with a flash.
5. Linked: **Unlink** (`DELETE …/person_link`, Turbo confirm) runs `People::Activities::Unlink`, which copies the user's identity back into `data`, clears `user_id` and records `person.unlinked`.
6. The member opens a person or owned entity's surface under `/:customer_id/member/`; `People::Ownership.scope` lists only rows they own. A same-tenant admin may GET the same surface and still sees only rows linked to themselves (the scope always uses the member audience and `current_user`).

## Implementation

**Schema.** `entity_entries.user_id` references `users` with `on_delete: :nullify`. `idx_entity_entries_person_link` is unique on `(entity_id, user_id)` where `user_id IS NOT NULL`, so one user is linked at most once per entity but may be linked from entries of different person entities. `(customer_id, user_id)` is indexed for member lookups. SQLite would null `customer_id` too on a composite set-null key, so the same-tenant rule is enforced by the contract, not a composite foreign key.

**Models.** `EntityEntry belongs_to :user` (optional) and `#linked?`; `Authentication::User has_many :person_entries`, and destroying a user runs `People::Link.detach!` on each linked entry first, so the entries get the identity back exactly as on unlink (no audit row, since there is no acting admin). `EntityEntry#validate_data_keys` accepts `People::IDENTITY_KEYS` on person entries so an unlinked entry's identity survives later validated saves.

**Contract.** `People::Contracts::Link` requires a person entity, an unlinked entry, a user that is not already linked to another entry of the same entity, and a user found by `id`, the entry's `customer_id` and `status: :active`. Missing, other-tenant and inactive users share `people.errors.user_unavailable`, so a foreign id never confirms that a user exists.

**Activities.** `People::Activities::Link` and `Unlink` are Trailblazer railways that run inside `Customer#with_lock(requires_new: true)`, reload the entry, save with `validate: false` and audit through `Authentication::AuditLog.record` (`entry_id`, `entity_id`, `linked_user_id`). A concurrent duplicate link that reaches the unique index returns a failed result with `people.errors.user_already_linked`.

**Service.** `People::Link` is the only public write entry point: `link!(entry:, user_id:, actor:)` and `unlink!(entry:, actor:)` return a result with `success?`, `entry` and translated `errors`; `candidates(entry:, query:, limit: 20)` returns active users of the entry's tenant not linked to this entity, matched case-insensitively on name or email (`sanitize_sql_like` with `ESCAPE '\'`). Member row scope lives on `People::Ownership`, not on `Link`.

**Controller.** `Admin::EntityEntryPersonLinksController` (`create`, `destroy`, `candidates`) is admin-category and guarded by `RouteAuthorization` (`admin_or_owner?`). It loads the entity from `Entity.where(customer_id: current_customer.id).or(Entity.shared)`, returns 404 unless `person?` (and unless active for writes), and loads the entry by `customer_id` and `entity_id`. Candidates are JSON only. Redirects use `303 See Other`; flashes are `admin_misc.person_link.flash.*`.

**Admin list.** For person entities `Admin::Entities::ColumnsBuilder` adds a **Linked account** column before the timestamps. Its cell shows `admin_misc.entities.columns.linked_account_value` (name and email); sort and search read the user's email through a subquery that also matches `users.customer_id = entity_entries.customer_id`. `Admin::EntitiesController#show` preloads `:user`.

**Member surface.** `Member::EntitySurfaceBuilder` scopes every entity surface with `People::Ownership.scope(..., audience: "member")`. `Member::SurfacesController` calls `allow_admin_member_preview!`. Show re-checks through `authorize_surface_record!`: an `EntityEntry` only has to match `current_user.customer_id` (owned rows have no `user_id` of their own); other records still go through `authorize_owned!`. See [Member and public](member-and-public).

### Ownership kinds and row scope

`People::Ownership` answers which kind an entity is and which rows a viewer may reach. Flowchart runtime never calls it: a capacity check must count every enrollment.

`describe(entity)` returns `Descriptor(kind:, owner:)`. `kind` is one of `:person`, `:owned`, `:private`, `:open`. `owner` is `Owner(slug:, person_entity_id:)` or nil. `kind(entity)` and `owner_reference(entity)` are shorthands.

| Kind | When | `owner_reference` |
|---|---|---|
| `:person` | `entity.person?` | nil |
| `:owned` | One reference is flagged `"owner": true`, or exactly one reference targets a person entity | that reference's slug and target id |
| `:private` | Two or more person references and none flagged | nil |
| `:open` | No person references | nil |

A **reference attribute** is `type: "EntityReference"` (bridge ends; target in `entity_id`) or an `entity_entries` select (target in `config.entity_id`). `person_references` loads those targets with `Entity.unscoped` in the entity's tenant or shared (`customer_id` NULL), filtered to the person model. A **trashed** person target still counts: trashing Student must not turn Enrollment into `:open`.

The owner flag is allowed only on a reference to a person entity, and at most once. Person entities, bridges, association extras, non-references and non-person targets cannot carry it. Bridges get no flag in the editor; Enrollment is `:owned` because `bridge_property_schema` already has a single person reference (`student`). See [Entity builder](entity-builder) for the editor switch and [Operations API](operations-api) for `owner` on `create_entity` / `update_entity`.

`scope(entity, viewer:, audience:, customer_id:)` always starts from `EntityEntry.where(customer_id:, entity_id:)`. Another tenant's rows never appear.

| Kind | admin | member | public |
|---|---|---|---|
| person | all tenant rows | rows with `user_id = viewer.id` | none |
| owned | all tenant rows | rows whose owner value (stored as `"12"` or `12`) is the viewer's linked entry of that person entity | none |
| private | all tenant rows | none | none |
| open | all tenant rows | all tenant rows | all tenant rows |

Fail closed: `viewer: nil` with member audience, a viewer from another tenant, an unknown audience string, and a member with no linked person entry all return no rows for person / owned / private. Owned rows match with `CAST(json_extract(data, '$.<slug>') AS TEXT) = ?` after `JsonPathValidator.safe_json_path!` on the slug.

`reachable_ids(entity, ids, ...)` returns the in-scope subset as strings and ignores non-numeric ids. `person_entry_ids(user)` returns `{ "<person entity id>" => entry_id }` for entries in `user.customer_id` only; `person_entry_id(user, person_entity_id)` is the lookup.

Every output that lists another entity's rows uses `scope`: `Entities::ReferenceOptions` (dropdowns; pass `viewer:`), `Entities::EntryDisplay` (a label outside scope is the bare id, not the display field), `CompositePageRenderer` lists, `PageContentGenerator::DynamicOptionsResolver` query lists, and `Member::EntitySurfaceBuilder`. `FlowchartRuntime::QueryBuilder.for_entity` accepts an optional `scope:`; flowchart callers never pass it, so query steps see every tenant row.

### Trusted context

`Pages::PublicSubmission` seeds `ctx[:current_person_ids]` from `person_entry_ids` for a same-tenant viewer only. A signed-in user of another tenant is public here; their own tenant's person entries never enter this run. Anonymous and unlinked viewers get `{}`.

`FlowchartRuntime::CurrentUser.load` returns a frozen Hash `{ id, email, name, role, person_entries }`. `person_entries` is the same map.

`find_model` with `findBy: current_person` loads the viewer's linked entry of the bound person entity through `FlowchartRuntime::Entries.find_current_person(ctx)`. It reads only `ctx[:current_person_ids]`, never params. It fails `record_not_found` when the bound entity is not a person entity, nothing is linked, or the entry is gone. See [Flowchart runtime](flowchart-runtime) and [Flowchart step actions](flowchart-step-actions).

### Pending claims

A public `register_member` run records one row in `people_pending_claims` so confirmation or sign-in on any device can finish the hand-over. `People::PendingClaim` is thin (`self.table_name = "people_pending_claims"`; `People` has no table prefix): `customer_id` (tenant-scoped), `user_id` (unique, one claim per user, FK cascade), `entity_entry_id` (nullable, nullify on delete), `continuation` (JSON), `created_user` (boolean, default false), `expires_at` (3 days from `People::Claim::TTL`).

`People::Claim.record!(user:, entry: nil, continuation: nil, created_user:)` upserts by `user_id` and refreshes `expires_at`. A new visitor gets the Student entry and `created_user: true`; that claim is never replaced, so a repeat submission for the same address cannot strip its entry or change its continuation. An existing confirmed same-tenant active member gets a continuation-only claim (`entry` nil, `created_user: false`).

`People::Claim.complete!(user)` runs `People::Activities::CompleteClaim` under the user's customer lock:

1. Find the claim by `user_id`. None → nil.
2. Fail closed if it is expired or `claim.customer_id != user.customer_id`. An expired row is left for the job; a tenant mismatch never links or consumes.
3. When the entry is still present, unlinked, and in the user's tenant, `People::Link.link!(entry:, user_id:, actor: user, event: "person.claimed")`. An entry already linked to someone else is skipped (no error). A deleted entry (FK nullified) still returns the continuation.
4. Destroy the claim.
5. Build `Pages::ActionLink.path` from the continuation's `action_key` and `prefill` for **the user's own** `customer_id`. The signed continuation never carries a URL or a customer id, so a token cannot name another tenant's action. Invalid or missing payload → nil.

`People::ExpirePendingClaimsJob` (`people_expire_pending_claims` in `config/recurring.yml`, every day at 5am in production) walks expired claims in batches of 500, each under that customer's row lock. It deletes the claim. For an expired `created_user` claim whose user is still unconfirmed, it also destroys the unclaimed entry and that user. A user who has confirmed since, and an entry that has already been linked, are kept. Another tenant's rows are never touched.

**UI.** `PersonLinkComponent` has three states: not linked, linked (with a Deactivated badge for an inactive user) and read-only (entity inactive or bridge). Strings are `comp_admin.person_link.*`; the Stimulus controller `person_link_picker_controller.js` reads every label from values passed by the component.

## Where to pay attention

:::attention
Never write `entity_entries.user_id` outside `People::Link`. The activities are what keep identity in one place and record the audit trail. `user_id` is in `FlowchartRuntime::Entries::INTERNAL_COLUMNS`, so `Entries.assign`, batch updates and `ActivitySteps::PopulatePrimary` (form submissions) skip it, and the assistant may not declare a `user_id` attribute.
:::

:::attention
The candidates endpoint and every link write are scoped through the URL tenant's entry. The owner acting on another tenant's URL still only sees and links that tenant's users.
:::

:::attention
Global email uniqueness stays: a user belongs to exactly one tenant. Later invitation flows must answer an address owned by another tenant with a generic message.
:::

:::note
Devise runs with `reconfirmable = false`, so a later email change on a user is not verified. `register_member` parks the claim at sign-up; `signed_in_destination` completes it on the first confirmation (or on a later sign-in through the emailed link). A later email change does not open a new claim.
:::

:::note
`person.linked`, `person.unlinked` and `person.claimed` persist through `Authentication::Instrumentation` but are not in `Authentication::Event::EVENTS`, so the auth events filter does not list them yet.
:::

:::attention
Flowchart runtime never calls `People::Ownership.scope`. `QueryBuilder.for_entity` without `scope:` still returns every tenant row. A capacity check or duplicate check that went through the member scope would under-count.
:::

:::attention
When ownership cannot be resolved — no viewer, another tenant's viewer, an unknown audience, or a missing owner link — member and public scopes return no rows. Do not treat an empty list as "show everything".
:::

## Key code

```ruby
# app/services/people/ownership.rb
def describe(entity)
  return Descriptor.new(kind: :person, owner: nil) if entity.person?

  references = person_references(entity)
  owner = owner_from(references)
  kind = owner ? :owned : (references.empty? ? :open : :private)
  Descriptor.new(kind: kind, owner: owner)
end

def scope(entity, viewer:, audience:, customer_id:)
  rows = EntityEntry.where(customer_id: customer_id, entity_id: entity.id)
  return rows if audience.to_s == EntityAttributeAudience::ADMIN
  # open + known audience → all tenant rows; otherwise member + same tenant
  # only, then person (user_id) / owned (json_extract owner slug) / none
end
```

```ruby
# app/services/people/contracts/link.rb
def linkable_user
  return @linkable_user if defined?(@linkable_user)

  id = user_id.presence
  @linkable_user = id && Authentication::User.find_by(
    id: id,
    customer_id: model.customer_id,
    status: :active
  )
end
```

```ruby
# config/routes.rb
resource :person_link, only: %i[create destroy], controller: "entity_entry_person_links" do
  get :candidates
end
```

```ruby
# app/services/people/claim.rb
    TTL = 3.days

    def self.record!(user:, created_user:, entry: nil, continuation: nil)
      # upsert by user_id; expires_at = 3.days.from_now
      # a created_user claim is returned unchanged, never replaced
    end

    def self.complete!(user)
      Activities::CompleteClaim.call(user: user)
    end
```
