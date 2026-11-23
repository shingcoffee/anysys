# Audience Flows — Design

**Date:** 2026-10-27
**Status:** Draft for review
**Plans:** `docs/2026-10-27-audience-flows-plan-1-ownership.md`, `docs/2026-10-27-audience-flows-plan-2-audiences.md`, `docs/2026-10-27-audience-flows-plan-3-registration.md`

## 1. Goal

One business domain is served to three audiences. Each audience gets its own form and its own flowchart, and no audience can reach another audience's flow or another person's records.

The worked example is "Enroll in course" in a domain with a Student person entity, a Course entity and the Enrollment bridge between them.

| Audience | Opened from | Form | Flowchart | Trusted by the platform |
|---|---|---|---|---|
| Admin | Student detail page, Enrollments card (exists today) | Association card: picks a course | The existing association writer | The tenant in the URL |
| Member | Member navigation, course catalog row link | Page bound to Enrollment, course picker only | Member enroll: course open, no duplicate, capacity under a lock, optional payment or approval | Student = the member's linked Student entry |
| Public | Website button, QR code, catalog row link | Page bound to Student with name, email and profile fields | Public register: starts member registration and remembers the chosen course | Nothing. The account and entry are linked once the email is confirmed |

After confirming the email, the public visitor is signed in and lands on the member enroll form with the course pre-selected. The member flowchart writes the enrollment, so an unverified email never gets enrollments.

## 2. Terms

- **Audience.** `admin` is a signed-in admin or owner of the visited tenant, or the platform owner. `member` is a signed-in member of the visited tenant. `public` is everyone else, including signed-in users of other tenants. `EntityAttributeAudience.for_user(user, customer_id:)` stays the single source of truth.
- **Action.** The set of pages that share an action key. An action has at most one live page per audience.
- **Person entity.** Unchanged: `Entity#person?`.
- **Reference attribute.** An attribute whose `type` is `EntityReference` (bridge ends) or whose config is an `entity_entries` source (`Entities::ReferenceLabels.reference?`).
- **Owner reference.** The reference attribute that says which person a row belongs to.
- **Ownership kind.** `person`, `owned`, `private` or `open` (§3.3).
- **Continuation.** A signed `{ action_key, prefill }` value carried through registration (§3.10).

## 3. Rules

### 3.1 Page audiences are a set

1. `pages.visibility` is replaced by three booleans: `audience_admin` (default true), `audience_member` and `audience_public` (default false). The migration maps `admin` to admin only, `member` to admin and member, and `public` to all three, so existing pages behave as before.
2. A page has at least one audience (`maint_core.errors.validations.page_audiences_blank`).
3. `PageVisibility::AUDIENCES = %w[admin member public]`. `visible_to?(audience)` is membership in the set; unknown audiences are false. `visible_audiences` returns the set in that order. `Page.for_audience(audience)` is the SQL scope.
4. Reads:
   - `GET /:cid/page/:uuid` renders when `public` is in the set, for any viewer, unless §3.2.6 redirects the viewer.
   - `GET /:cid/member/pages/:id` requires `member`. Admin GET preview (`allow_admin_member_preview!`) is unchanged.
   - `GET /:cid/admin/pages/:id/form` and the maintenance render require `admin`. Maintenance Preview is unchanged and renders any page.
5. Writes: `POST /:cid/page/:uuid` requires the viewer's audience to be in the set. Otherwise nothing is written, and the first matching rule applies:
   - the page's action has a page for the viewer's audience: redirect there with `public_views.actions.continue_here`;
   - the viewer is anonymous and `member` or `admin` is in the set: store the page's member surface (or the admin render when there is no member audience) and redirect to sign-in (today's behaviour, so an expired admin session still lands back on the form);
   - `public` is in the set, so the viewer could open the page: redirect back to it with `public_views.actions.not_for_your_account`;
   - otherwise 404.
6. Audiences and the action key are identity. Shared pages change them only on the platform prefix (`guard_shared_global_writes`).
7. The distribution card shows three independent toggles. Admin is no longer locked. The last remaining audience can't be turned off.

### 3.2 Actions

1. `pages.action_key` is a nullable string matching `/\A[a-z][a-z0-9_]{1,62}\z/` (`maint_core.errors.validations.page_action_key_invalid`).
2. Within one owner (one customer's own pages, or the shared pages), at most one active, launched page per action key and audience. Launch and audience changes are refused when they would collide (`maint_core.errors.page_launch.action_audience_taken`). When a tenant page and a shared page match the same action key and audience, the tenant page wins.
3. `Pages::ActionResolver.page_for(customer_id:, action_key:, audience:)` and `.counterpart(page:, audience:)` are the only lookups.
4. `GET /:customer_id/actions/:action_key` (public URL category, `Pages::ActionsController#show`):
   - a page for the viewer's audience: redirect to its surface (public: `PageShortcuts::PublicPath.public_page`; member: `member_page_path`; admin: `admin_page_form_path`);
   - an anonymous viewer, no public page, and a member page: store the member page path (with prefill) and redirect to sign-in;
   - otherwise 404.
5. `prefill[<slug>]=<scalar>` query values pass through to the target page: at most 10 keys, slugs matching `Pages::FormParams::SLUG`, values up to 200 characters.
6. `GET /:cid/page/:uuid` by a viewer whose audience has a counterpart page in the same action redirects (303) to that counterpart, keeping the prefill.

### 3.3 Ownership

1. A reference attribute may carry `"owner": true` when its target is a person entity. At most one per entity. Violations: `maint_core.errors.validations.entity_owner_reference_invalid` and `entity_owner_reference_multiple`.
2. `People::Ownership.kind(entity)`:
   - `:person` when `entity.person?`;
   - `:owned` when one reference attribute is flagged, or exactly one reference attribute targets a person entity;
   - `:private` when two or more reference attributes target person entities and none is flagged;
   - `:open` otherwise.
3. `People::Ownership.owner_reference(entity)` returns `{ slug:, person_entity_id: }` or nil.
4. Bridges get no flag in the editor. Their kind comes from inference, so Enrollment (student → Student) is `owned`.
5. The Operations API vocabulary gains `owner` on reference attributes so assistant updates keep the flag.

### 3.4 Row scope on outputs

| Kind | admin | member | public |
|---|---|---|---|
| person | all tenant rows | rows linked to the viewer | none |
| owned | all tenant rows | rows whose owner reference is one of the viewer's linked entries of that person entity | none |
| private | all tenant rows | none | none |
| open | all tenant rows | all tenant rows | all tenant rows |

1. `People::Ownership.scope(entity, viewer:, audience:, customer_id:)` returns the relation. Every output uses it: `Entities::ReferenceOptions` (options and labels), `CompositePageRenderer` lists, `PageContentGenerator::DynamicOptionsResolver` query lists, `Member::EntitySurfaceBuilder` scopes, and `Entities::EntryDisplay` through `ReferenceOptions`.
2. Flowchart runtime is never scoped. Flowcharts are trusted, owner-authored code; a capacity check must count every enrollment.
3. An admin previewing a member surface still sees only rows linked to themselves, because surface scopes run with the actor.

### 3.5 Inputs at the submit boundary

1. `Pages::AudienceGuard.call(entity:, primary:, sections:, viewer:, audience:, customer_id:)` runs after `Pages::FormParams` permits the input and before anything is written. When it refuses, the submission is rejected: nothing runs, and the viewer goes back to the page with the message.
2. Member audience: the owner reference of the primary entity and of each bridge section is removed from the permitted input and set to the viewer's linked entry (`People::Ownership.person_entry_id(user, person_entity_id)`). No linked entry: rejected with `common.errors.dynamic.profile_required`.
3. Every other submitted reference whose target is a person, owned or private entity must be inside the viewer's row scope; otherwise rejected with `common.errors.dynamic.reference_not_allowed`.
4. Public audience: a primary entity of kind `owned` or `private` is rejected with `common.errors.dynamic.sign_in_required`, and so is any filled bridge section whose bridge is `owned` or `private`. References follow rule 3. A public Student page therefore never creates enrollments.
5. The owner reference is not rendered for the member audience (`FormParams#visible_field?` is false) and the required-field launch check skips it for that audience.

### 3.6 Trusted context

1. `Pages::PublicSubmission` adds `current_person_ids: { "<person entity id>" => <entry id> }` for tenant viewers.
2. `FlowchartRuntime::CurrentUser.load` drops `member_profile_id` and adds `person_entries` (the same map).
3. `find_model` gains `findBy: current_person`: the viewer's linked entry of the bound person entity. It fails with `record_not_found` when the bound entity isn't a person entity or nothing is linked.

### 3.7 Page binding and launch checks

1. The page entity picker also lists bridges whose kind is `owned`.
2. A bridge-bound page may have only the member audience (`maint_core.errors.page_launch.bridge_page_member_only`).
3. A page bound to an `owned` or `private` entity, or carrying a bridge section whose bridge is `owned` or `private`, may not include the public audience (`owned_entity_public_audience`).
4. A reference field whose target is `person`, `owned` or `private` on a page with the public audience, or whose target is `private` on a page with the member audience, fails `reference_private_for_audience`.
5. These checks run in `Pages::LaunchChecks`, so they apply on launch and when an audience is added to a live page.

### 3.8 Member navigation and surfaces

1. `Member::Surface` gains `default_enabled` (default true). `member_surface_settings.enabled` becomes nullable; nil inherits the descriptor default.
2. Entity surfaces: `person` and `owned` default on; `open` defaults off and, when an admin turns it on, lists every tenant row (a catalog); `private` entities and bridges that aren't `owned` get no surface.
3. `Member::Sources::Entities` lists the tenant's own entities and shared entities.
4. Index columns and detail rows both respect `visibility.member` (fixes today's leak of hidden fields in index columns).
5. `Member::Sources::Pages` (key `pages`) adds one link per launched page with the member audience: a `Member::Sources::BuiltinSurface` descriptor (the existing link struct) with key `page_<id>`, `path_seg` `pages/<id>` and `default_enabled: false`. `Member::Navigation` already builds `/:cid/member/pages/<id>` from the `path_seg`, and `Member::SurfacesController` already returns 404 for link descriptors.

### 3.9 Row actions and prefill

1. `Pages::ActionLink.path(customer_id:, action_key:, prefill: {})` builds every action link.
2. Settings / Member gains a per-surface row action for entity surfaces: action key, target field and optional button label (overlay copy like the other overlay fields; default `member.entity_surfaces.row_action_default`). Each index row links to the action with `prefill[<field>]=<row id>`.
3. Composite list tiles accept `config.row_action` with the same keys and render a link column. Composite pages are still authored as configuration JSON; there is no builder UI for them.
4. `Pages::Prefill.values(page:, params:, audience:, viewer:)` keeps only fields visible to the audience, keeps a reference value only if it is one of the viewer's options, and never prefills the owner reference. The generator renders the values as initial field values. Submission validation is unchanged, so prefill grants nothing.

### 3.10 Registration and hand-over

1. `Authentication::RegisterMember.call(customer:, attributes:)` is extracted from `Authentication::RegistrationsController#create` and used by both the controller and the step: customer lock, member quota, save, member role, confirmation email after commit.
2. Pages bound to a person entity may place the identity fields `first_name`, `last_name` and `email` (`source: "identity"`). They render as `identity[<key>]`, are permitted for the public and admin audiences only, and reach the flowchart as `ctx[:identity]`. Generic record steps never write them.
3. The `register_member` step (security category; config `personVar` default `model`, `resultVar` default `registration`):
   1. fails `register_member.public_only` unless the run's audience is public;
   2. fails `register_member.person_entity_required` unless the bound entity is a person entity;
   3. fails `register_member.signup_disabled` unless the authentication module is enabled and `Authentication::Settings#signup_enabled?`;
   4. when the normalized email belongs to any existing user, saves nothing; when that user is an active member of this tenant, issues a sign-in link and records a continuation-only claim. Result status `existing`;
   5. otherwise registers a passwordless, unconfirmed member, saves the person entry with identity in its data (the unlinked-entry rule in [Person linking](person-linking)), and records a pending claim with the continuation. Result status `created`;
   6. when the quota is exhausted, fails `register_member.unavailable` (generic wording);
   7. sets the submission outcome preset `registration_pending` unless the flowchart set one. The browser sees the same response for statuses `created` and `existing`.
4. `people_pending_claims`: `customer_id`, `user_id` (unique), `entity_entry_id` (nullable, nullify on delete), `continuation` (JSON), `created_user` (boolean), `expires_at`.
5. `Pages::Continuation` signs `{ action_key, prefill }` with the Rails message verifier (purpose `page_continuation`, 3 days). Public pages reached through the action router render it as hidden `_continuation`; `PublicSubmission` exposes the verified value as `ctx[:continuation]`.
6. A sign-in completes the claim once the session is fully established: `finish_sign_in` when no MFA step is pending, and the MFA session and setup controllers once the second factor passes. All three call one `Authentication::FinishesSignIn#signed_in_destination(user)`, which calls `People::Claim.complete!(user)`. That links the claimed entry through `People::Link` (audit `person.claimed`, actor is the user) when the entry is unlinked and in the user's tenant, consumes the claim, and returns the continuation path. The destination order is: stored location, then continuation, then the landing page. The stored location wins because anyone can trigger the existing-email branch with someone else's address, and that must not override where that person's next sign-in returns (an OAuth authorize, for example). Claims live in the database, so a sign-in on another device completes them too.
7. `People::ExpirePendingClaimsJob` runs daily: it deletes expired claims and, for `created_user` claims whose user is still unconfirmed, destroys the unclaimed entry and that user.

## 4. Per-audience flowcharts

Rules that must hold for every audience go in one shared subflow, for example "Enroll core": the course is open, `upsert_model` matching student and course, and the capacity check under `acquire_lock`. The member flowchart calls it and adds payment or approval. The public flowchart runs `register_member` and never writes enrollments. Admins keep the association card, which writes the bridge row directly.

Because §3.1 makes audiences exact, each flowchart is written for one audience and can rely on the trusted context in §3.6. The new [Audience flows](audience-flows) reference page documents this pattern with the enrollment example.

## 5. Strings

| Key | en | zh-CN |
|---|---|---|
| `common.errors.dynamic.profile_required` | Your account isn't linked to a %{entity} profile yet. | 您的账号尚未关联%{entity}资料。 |
| `common.errors.dynamic.reference_not_allowed` | %{field}: you can't choose this record. | %{field}：无权选择该记录。 |
| `common.errors.dynamic.sign_in_required` | Sign in to submit this form. | 请登录后提交此表单。 |
| `maint_core.errors.validations.page_audiences_blank` | Choose at least one audience. | 请至少选择一个受众。 |
| `maint_core.errors.validations.page_action_key_invalid` | The action key must start with a letter and use only lowercase letters, numbers and underscores. | 操作标识须以字母开头，且只能包含小写字母、数字和下划线。 |
| `maint_core.errors.validations.entity_owner_reference_invalid` | %{field} can mark the record's owner only when it references a person entity. | 只有引用人员实体的字段才能设为记录所有者：%{field}。 |
| `maint_core.errors.validations.entity_owner_reference_multiple` | Only one field can mark the record's owner. | 只能有一个字段设为记录所有者。 |
| `maint_core.errors.page_launch.bridge_page_member_only` | A form on a link entity can only be opened by members | 关联实体的表单仅限会员使用 |
| `maint_core.errors.page_launch.owned_entity_public_audience` | %{entity} records belong to members, so Public can't submit this form | %{entity}记录归属于会员，公开访客无法提交此表单 |
| `maint_core.errors.page_launch.reference_private_for_audience` | %{field}: %{target} records aren't visible to %{audience}, so the dropdown would be empty | %{field}：%{audience}看不到%{target}记录，下拉列表将为空 |
| `maint_core.errors.page_launch.action_audience_taken` | Another live form already handles %{audience} for action %{action} | 操作 %{action} 已有面向%{audience}的上线表单 |
| `maint_core.errors.page_launch.identity_field_not_person` | Name and email fields need a form on a person entity | 姓名和邮箱字段仅可用于人员实体的表单 |
| `public_views.actions.continue_here` | Continue with the form for your account. | 请在适用于您账号的表单中继续。 |
| `public_views.actions.not_for_your_account` | This form isn't available for your account. | 此表单不适用于您的账号。 |
| `public_views.flash.outcomes.registration_pending` | Check your email to finish signing up. | 请查收邮件以完成注册。 |
| `member.entity_surfaces.row_action_default` | Open | 打开 |
| `public_views.composite.row_action_default` | Open | 打开 |
| `flowchart_runtime.errors.register_member.public_only` | Registration is only available to visitors who aren't signed in. | 仅未登录的访客可以注册。 |
| `flowchart_runtime.errors.register_member.person_entity_required` | Registration needs a form on a person entity. | 注册需要使用人员实体的表单。 |
| `flowchart_runtime.errors.register_member.signup_disabled` | Sign-up is turned off. | 注册功能已关闭。 |
| `flowchart_runtime.errors.register_member.unavailable` | We couldn't complete sign-up right now. Please try again later. | 暂时无法完成注册，请稍后再试。 |

The four `register_member` runtime failures live in `config/locales/flowchart_actions_security.{en,zh-CN}.yml` under `flowchart_runtime.errors`, next to `authorize.denied`. Editor labels and settings copy (owner toggle, action key field, audience toggles, page links source, row action fields, identity fields) are specified by the UX task in Plan 2 and the frontend tasks, with both locales in the same change. The step's palette labels go under `flowchart_actions.register_member` in the same file.

## 6. Documentation

Updated in both locales: `member-and-public`, `page-rendering`, `page-builder`, `person-linking`, `entity-builder`, `flowchart-runtime`, `flowchart-step-actions`, `authentication`, `shared-resources`, `page-shortcuts`, `captcha`, `operations-api`.

New page `audience-flows` in the `access` group of `DeveloperDocs::Catalog`, with the five headings `DeveloperDocs::Catalog::REQUIRED_HEADINGS` requires (en: Summary, Flow, Implementation, Where to pay attention, Key code; zh-CN: 概要, 流程, 实现, 需要特别注意, 关键代码).

## 7. Tests

Each plan lists its specs. The security matrix that must exist by the end of Plan 3:

- For each of admin, member, public, foreign-tenant admin and foreign-tenant member: GET and POST of a page per audience set, and the action router.
- Member reads and writes on person, owned, private and open entities through dropdowns, composite lists, surfaces and submissions, including a second member of the same tenant and a member of another tenant.
- Owner-reference tampering: a member submits another student's id; the stored value is still their own.
- Registration with a new email, an existing same-tenant member, an existing other-tenant user, sign-up off, quota exhausted, and a confirmation opened in a different session.

## 8. Out of scope

- Several courses in one submit. Entity attributes have no multi-select type (`HtmlTypeOptions::SELECTION_TYPES`). Members enroll once per course, helped by catalog row links.
- A member editing or withdrawing one of their owned records, which needs record-targeted pages.
- Person directories (opt-in listing of person rows to members or the public).
- Admin pages bound to bridges. Admins keep the association card.
- A builder UI for composite list tiles and row actions.
- Page shortcuts that point at an action.
