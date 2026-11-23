---
title: "Audience flows"
summary: "How one business action is served to admin, member and public through separate pages and flowcharts, joined by an action key."
---

## Summary

One business domain is served to three audiences. Each audience gets its own form and its own flowchart, and no audience can reach another audience's flow or another person's records. Page audiences are an exact set (`audience_admin`, `audience_member`, `audience_public`), not a hierarchical level. Pages that share an `action_key` form one action; `GET /:customer_id/actions/:action_key` sends every viewer to the live page for their audience.

The worked example is **Enroll in course** in a domain with a Student person entity, a Course entity and the Enrollment bridge between them.

| Audience | Opened from | Form | Flowchart | Trusted by the platform |
|---|---|---|---|---|
| Admin | Student detail page, Enrollments card | Association card: picks a course | The existing association writer | The tenant in the URL |
| Member | Member navigation, course catalog row link | Page bound to Enrollment, course picker only | Member enroll: course open, no duplicate, capacity under a lock, optional payment or approval | Student = the member's linked Student entry |
| Public | Website button, QR code, catalog row link | Page bound to Student with name, email and profile fields | Public register: starts member registration and remembers the chosen course | Nothing. The account and entry are linked once the email is confirmed |

After confirming the email, the public visitor is signed in and lands on the member enroll form with the course pre-selected. The member flowchart writes the enrollment, so an unverified email never gets enrollments. See **Public enrollment** below.

See [Page builder](page-builder) for the switches and action key, [Page rendering](page-rendering) for GET/POST rules, [Member and public](member-and-public) for member links and row actions, [Person linking](person-linking) for ownership kinds, and [Authentication](authentication) for `RegisterMember` and the sign-in destination.

## Flow

```text
GET /:cid/actions/enroll
        |
        |  Pages::ActionsController (public URL; redirect only)
        |  audience = EntityAttributeAudience.for_user(...)
        v
Pages::ActionResolver.page_for(customer_id, "enroll", audience)
        |
        +-- public  -> GET /:cid/page/:uuid          (Student page)
        |              + continuation= when a live member page exists
        +-- member  -> GET /:cid/member/pages/:id    (Enrollment page)
        +-- admin   -> GET /:cid/admin/pages/:id/form
        +-- anonymous, no public page, member page exists
        |              store member path + prefill, redirect to sign-in
        +-- otherwise 404
```

Each audience's flowchart is written for that audience only. Shared rules live in one **Enroll core** subflow.

```text
Admin
  Student detail -> Enrollments card
        |
        v
  association writer (writes the Enrollment row directly)
  does not call Enroll core

Member
  member nav / catalog row action
        |
        |  page bound to Enrollment (member only)
        |  course picker; owner reference hidden
        v
  member enroll flowchart
        |  optional payment or approval
        v
  Enroll core (subflow)

Public
  website button / QR / catalog link
        |
        |  GET /:cid/actions/enroll?prefill[course]=<id>
        |  page bound to Student (public in the set)
        |  signed continuation when a live member page exists
        v
  public register flowchart
        |  register_member (ctx[:identity], ctx[:continuation])
        |  never writes enrollments
        v
  "Check your email to finish signing up."
        |
        v
  confirmation email -> signed in -> claim completed
        |
        v
  member enroll page, course pre-selected
```

```text
Enroll core (shared subflow)
        |
        |  course is open
        |  upsert_model matching student and course
        |  capacity check under acquire_lock
        v
  Enrollment row
```

Because audiences are exact, the member flowchart can rely on `ctx[:current_person_ids]` (the viewer's linked Student). The public flowchart never writes the bridge. Admins keep the association card.

## Implementation

### Exact audiences

`pages.visibility` is gone. Three booleans replace it: `audience_admin` (default true), `audience_member` and `audience_public` (default false). A page needs at least one (`maint_core.errors.validations.page_audiences_blank`: "Choose at least one audience." / 「请至少选择一个受众。」). `PageVisibility::AUDIENCES` is `%w[admin member public]`. `visible_to?(audience)` is membership; an unknown audience is false. `visible_audiences` returns the set in that order. `Page.for_audience(audience)` is the SQL scope.

`EntityAttributeAudience.for_user(user, customer_id:)` is the viewer audience everywhere (`page_runtime_audience`). A signed-in user of another tenant is **public**.

Reads:

- `GET /:cid/page/:uuid` renders when `public` is in the set, unless the viewer's audience has a counterpart in the same action (303, prefill kept).
- `GET /:cid/member/pages/:id` requires `member`. Admin GET preview (`allow_admin_member_preview!`) is unchanged.
- `GET /:cid/admin/pages/:id/form` and the maintenance render require `admin`. Maintenance Preview still renders any page.

Writes: `POST /:cid/page/:uuid` requires the viewer's audience. Otherwise nothing is written. Refusal order is counterpart → anonymous sign-in store → public `not_for_your_account` → 404. See [Page rendering](page-rendering).

Audiences and the action key are identity. Shared pages change them only on the platform prefix (`guard_shared_global_writes` on `PageVisibilitiesController`).

### Ownership

`People::Ownership.kind(entity)` is `:person`, `:owned`, `:private` or `:open`. Bridges get no owner flag in the editor; Enrollment is `:owned` because it has one person reference (`student`). Row scope:

| Kind | admin | member | public |
|---|---|---|---|
| person | all tenant rows | rows linked to the viewer | none |
| owned | all tenant rows | rows whose owner reference is one of the viewer's linked entries | none |
| private | all tenant rows | none | none |
| open | all tenant rows | all tenant rows | all tenant rows |

Flowchart runtime never uses that scope: a capacity check must count every enrollment. Full rules: [Person linking](person-linking).

A page bound to an owned bridge may have only the member audience (`maint_core.errors.page_launch.bridge_page_member_only`: "A form on a link entity can only be opened by members" / 「关联实体的表单仅限会员使用」). The maintenance entity picker lists tenant bridges whose kind is `:owned`; shared-resources mode does not (shared entities cannot carry associations). `grouped_entity_options` keeps flowcharts bound to owned bridges.

### Actions and the router

`pages.action_key` is a nullable string matching `/\A[a-z][a-z0-9_]{1,62}\z/` (`page_action_key_invalid`: "The action key must start with a letter and use only lowercase letters, numbers and underscores." / 「操作标识须以字母开头，且只能包含小写字母、数字和下划线。」). Blank stores nil.

Within one owner (one customer's own pages, or the shared pages), at most one active, launched page per action key and audience. Launch and audience changes that would collide fail `action_audience_taken` (`%{audience}`, `%{action}`: "Another live form already handles %{audience} for action %{action}" / 「操作 %{action} 已有面向%{audience}的上线表单」). A tenant page wins over a shared page with the same key and audience. `launch!`, `Pages::VisibilityContract#save` and restoring a trashed launched page (`Page#restore`, refused with the same message) re-check the slot inside a transaction that holds `Customer.lock.find(page.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)` (shared pages lock the platform customer).

`Pages::ActionResolver` is the only lookup:

- `page_for(customer_id:, action_key:, audience:)` — active, launched, `for_audience`; tenant page before shared.
- `counterpart(page:, audience:, customer_id: page.customer_id)` — same key, nil when the page has none or the counterpart is itself. `PublicPagesController` passes the visited tenant, so a shared page yields to that tenant's page for the same audience.
- `siblings(page)` — other active pages with the same key and owner, launched or not (the distribution card).

`GET /:customer_id/actions/:action_key` (`page_action`, public URL category, `Pages::ActionsController#show`) has no auth guard. It only redirects; each target surface enforces its own guard. `prefill[<slug>]=<scalar>` passes through: at most 10 keys, slugs matching `Pages::FormParams::SLUG`, values up to 200 characters (`Pages::ActionLink`).

### Prefill and row actions

`Pages::Prefill.values(page:, params:, audience:, viewer:)` keeps only fields visible to the audience, keeps a reference value only if it is one of the viewer's options, and never prefills the owner reference. Generated ERB reads `page_prefill_value(slug)`. Submission validation is unchanged: prefill grants nothing.

Settings / Member: an entity surface may set a row action (action key, target field, optional button label; default `member.entity_surfaces.row_action_default` "Open" / 「打开」). Each index row links to `Pages::ActionLink.path` with `prefill[<field>]=<row id>`. Composite list tiles accept `config.row_action` with the same keys and render a trailing link column (`public_views.composite.row_action_default`).

### Public enrollment

A signed-out visitor opens `/:cid/actions/enroll?prefill[course]=<id>`.

1. **Router.** `Pages::ActionsController` resolves the public Student page and 303s there. Because the same action also has a live member page, it appends `continuation=` — a signed `{ action_key: "enroll", prefill: { "course" => "<id>" } }` (purpose `page_continuation`, 3 days). The token carries no URL and no customer id.
2. **Public Student page.** The form shows First name, Last name and Email (`identity[<key>]`) plus any profile fields. Course is not on this form: a public Student page never writes Enrollment (`AudienceGuard` ignores an empty bridge section). The generated ERB posts hidden `_continuation` from `@page_continuation`.
3. **`register_member`.** The public flowchart reads `ctx[:identity]` and `ctx[:continuation]`. A new email creates a passwordless unconfirmed member, an unlinked Student entry, and a claim (`created_user: true`). An existing confirmed same-tenant active member gets a sign-in link (within the sign-in link flood limit) and a continuation-only claim. Anyone else who already has an account gets nothing, and an unconfirmed member's first claim is kept as is. A full member quota answers the same way and saves nothing. The browser always sees `registration_pending` (`public_views.flash.outcomes.registration_pending`: "Check your email to finish signing up." / 「请查收邮件以完成注册。」). Do not branch the flowchart on `registration.status`.
4. **Confirmation.** Devise sends the confirmation email after the outermost commit. `Authentication::ConfirmationsController#show` signs the member in (`SignInFlow.complete` then `finish_sign_in`).
5. **Claim.** `signed_in_destination` runs `People::Claim.complete!` first (Student entry linked, audit `person.claimed`), then destination = safe stored location → claim continuation → `LandingPath`. The continuation path is always `/:cid/actions/:key` in the **user's** tenant.
6. **Member Enroll.** The signed-in member hits the action router and opens the member Enrollment page with the course preselected. Submitting that form writes the enrollment. An unverified email never gets enrollments.

A tampered or expired continuation is nil; registration still succeeds, and after confirm the member lands on the default path without the course preselected. Turn on captcha for the public Student page (page flag plus a URL throttle). See [Captcha](captcha), [Authentication](authentication), [Person linking](person-linking), [Flowchart runtime](flowchart-runtime).

## Where to pay attention

:::attention
A signed-in admin cannot submit a public-only page. `page_runtime_audience` is `admin`, which is not in the set, so POST follows the refusal rules and writes nothing. Test the public form signed out, or add the admin audience. A signed-in member of another tenant is public here.
:::

:::attention
`Pages::ActionsController` is a public URL and has no `before_action` auth guard. It only redirects. Do not put writes on this controller; the member and admin targets keep their own guards.
:::

:::attention
Two concurrent launches of the same action key and audience cannot both pass: `launch!` and the visibility contract hold the owning customer's row lock before `action_errors`. Taking a page offline frees the slot.
:::

:::attention
Flowcharts are platform-owner-only. Customers never see the editor or the word "flowchart". Bound pages still submit through `form_settings.flowchart_id`. Ask `FlowchartVisibility.allowed?` before adding chrome. See [Flowchart builder](flowchart-builder).
:::

:::attention
Do not branch the public flowchart on `registration.status`. `created` and `existing` share the same `registration_pending` flash so a visitor cannot tell whether an email already has an account.
:::

## Key code

```ruby
# app/models/concerns/page_visibility.rb
  AUDIENCES = %w[admin member public].freeze

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end
```

```ruby
# app/services/pages/action_resolver.rb
  def page_for(customer_id:, action_key:, audience:)
    scope = Page.where(action_key: action_key, launched: true).for_audience(audience)
    scope.find_by(customer_id: customer_id) || scope.find_by(customer_id: nil)
  end
```

```ruby
# config/routes.rb
    get  "actions/:action_key", to: "pages/actions#show", as: :page_action,
         constraints: { action_key: /[a-z][a-z0-9_]{1,62}/ }
```

```ruby
# app/controllers/pages/actions_controller.rb
    def show
      page = ActionResolver.page_for(
        customer_id: current_customer_id,
        action_key: params[:action_key],
        audience: page_runtime_audience
      )
      if page
        prefill = sanitized_action_prefill
        path = audience_surface_path(page, prefill: prefill)
        path = with_public_continuation(path, prefill) if public_continuation?
        redirect_to path, status: :see_other
        return
      end
      # anonymous + member page -> store location, sign-in; else 404
    end
```

Related: [Page builder](page-builder), [Page rendering](page-rendering), [Member and public](member-and-public), [Person linking](person-linking), [Authentication](authentication), [Captcha](captcha).
