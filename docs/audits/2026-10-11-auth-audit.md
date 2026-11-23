# Authentication route-chain audit and controller integration — 2026-10-11

## Provenance and verification limits

This is a **source audit**, not a runtime pass. The coordinator's initial auth
findings were checked against the pre-edit controller/config sources and installed
Devise 5.0.4 / Doorkeeper 5.9.6 code. The completed backend changes were then read
from the shared working tree before their controller integration was implemented.
Historical triggers below describe those inspected control flows; they are not
claims that an exploit, browser journey, or concurrent workload was executed.

No RSpec/Vitest/Playwright runs, application runners, migrations, server restarts,
or subagents were used for this auth dispatch. Ruby and new locale YAML syntax
checks passed. Request regressions were written but remain **unexecuted**. The
shared tree changed concurrently, so file/method anchors are more useful than old
line numbers. This report does not attribute another lane's edits to this lane.

The action inventory below was reconciled in source with `config/routes.rb`, the
installed Devise/Doorkeeper route/action implementations, and the authentication
registration. Effective runtime route expansion, CSRF-enabled browser journeys,
responsive geometry, and rendered locale completeness remain coordinator checks.
See `2026-10-11-route-audit-manifest.md` for the wider application inventory.

## Exact source action coverage

Notation: `C` = `/:customer_id` with an eight-digit id; `A` = `C/admin`;
`M` = `C/member`; `S` = `A/settings/modules/authentication`;
`U` = `A/modules/authentication/users`. GET declarations also admit HEAD;
ordinary resource `update` admits PATCH and PUT. Every action listed was read,
including inherited implementations and response/error branches. This table's
state is **source_inspected / runtime_pending** throughout.

### Public authentication and OAuth

| Controller | Actions and canonical routes | Identity / security boundary |
| --- | --- | --- |
| `Authentication::SessionsController` | `new` GET `/auth/sign_in`; `create` POST same; `destroy` DELETE `/auth/sign_out` | Password or email-link intent; shared IP limiter; Lockable; session rotation; MFA routing; sign-out cleanup |
| `Authentication::PasswordsController` | `new` GET `/auth/password/new`; inherited `create` POST `/auth/password`; `edit` GET `/auth/password/edit`; inherited `update` PATCH/PUT `/auth/password` | Uniform issuance response; token-owner tenant reset gate; no automatic sign-in after reset |
| `Authentication::ConfirmationsController` | `new` GET `/auth/confirmation/new`; inherited `create` POST `/auth/confirmation`; `show` GET `/auth/confirmation` | Throttled resend; signed-in account-swap guard; HEAD does not consume; MFA-aware completion |
| `Authentication::CustomerRegistrationsController` | `new`, `create` GET/POST `/auth/sign_up`; `check_email` GET `/auth/sign_up/check_email`; `resend` POST `/auth/sign_up/resend`; `confirm` GET `/auth/sign_up/confirm` | Platform signup switch; encrypted expiring email token; already-confirmed replay rejection; HEAD does not consume; signup transaction |
| `Authentication::RegistrationsController` | `new` GET `C/auth/sign_up`; `create` POST `C/auth`; `edit` GET `/auth/edit`; `update` PATCH/PUT `/auth` | Tenant member signup switch and quota lock; session-owned edit; current-password re-auth; passwordless email restriction; MFA gate |
| `Authentication::SignInLinksController` | `create` POST `/auth/sign_in_link`; `check_email` GET `/auth/sign_in_link/check_email`; `show` GET `/auth/sign_in_link` | Uniform request response; account-locked single-use token claim; signed-in guard; HEAD non-consumption; MFA completion |
| `Authentication::MfaSetupsController` | `show`, `create` GET/POST `C/auth/mfa/setup` | Explicit signed-in guard; enrollment cache suppression; enrolled-secret redisplay guard; shared TOTP throttle |
| `Authentication::MfaSessionsController` | `show`, `create` GET/POST `C/auth/mfa/session` | Explicit signed-in/configured guard; TOTP claim; secret-bound session verification; optional trusted-device issuance |
| `Authentication::MfasController` | `destroy` DELETE `C/auth/mfa` | Explicit signed-in guard; password or OTP re-auth; shared throttle; credential-locked disable; verification cleanup |
| `Authentication::MfaRecoveriesController` | `new` GET `C/auth/mfa_recovery/new`; `create` POST `C/auth/mfa_recovery`; `consume` GET/POST `C/auth/mfa_recovery/consume` | Uniform request response; tenant/email lookup; member/secret-bound expiring token; GET confirmation and HEAD non-consumption; locked POST consume; NoStore headers and audited successful reset |
| `Oauth::AuthorizationsController` | `new` GET `/oauth/authorize`; `create` POST same; `destroy` DELETE same; implicit `show` GET `/oauth/authorize/native` | Resource-owner/MFA authentication; desktop state/query-mode checks on new/create/destroy; validated client/destination denial; locked grant issuance; no-store loopback handoff |
| `Oauth::TokensController` | inherited `create` POST `/oauth/token`; inherited `revoke` POST `/oauth/revoke`; inherited `introspect` POST `/oauth/introspect` | Real Doorkeeper client/PKCE/token checks; user-before-grant authorization-code wrapper; backend refresh-family lock; RFC 7009 no-op behavior; gem introspection authorization |
| `Oauth::UserinfoController` | `show` GET `/oauth/userinfo` | Bearer `profile` scope; first-party client and Devise-eligible active/confirmed/unlocked owner; no-store identity document |
| `Oauth::DiscoveryController` | `show` GET `/.well-known/oauth-authorization-server` | Anonymous static metadata; APP_HOST issuer override; public cache and Vary: Host |

Devise registration and unlock routes are explicitly skipped; custom registration
routes above replace the former. Doorkeeper applications, authorized applications,
and token-info routes are skipped. Introspection is still mounted: the initializer
does not disable it, and the installed mapper mounts it unless
`allow_token_introspection` is exactly false. The native GET is the gem's implicit
template action displaying supplied `params[:code]`, not another grant issuer;
the normal desktop flow uses the app's loopback handoff instead.

### Tenant administration and settings

All of these inherit the admin/owner role gate and tenant context. Record lookup
is scoped to the URL customer; cross-tenant owner access still uses that target
customer scope. Platform-owner account mutation has an additional target guard.

| Controller | Exact actions / routes | Record and mutation checks |
| --- | --- | --- |
| `Admin::Modules::Authentication::UsersController` | `index`, `show`, `new`, `create`, `edit`, `update`: U | Scoped user lookup; quota lock on create; self credential re-auth; fixed-owner account guard; transactional profile + reserved-role assignment |
| `UserActivationsController` in the same namespace | `create`, `destroy`: U`/:user_id/activation` | Scoped user; owner-account guard; self-deactivation rejection |
| `UserMfaResetsController` in the same namespace | `create`: U`/:user_id/mfa_reset` | Scoped user; owner-account guard; self-reset rejection; configured-state check; credential-locked reset |
| `UserTrustedDevicesController` in the same namespace | `destroy`: U`/:user_id/trusted_devices/:id` | Scoped user, then that user's device association |
| `EventsController` in the same namespace | `index`: A`/modules/authentication/events` | Explicit `Event.for_customer` scope on the non-TenantScoped audit table |
| `Admin::Settings::Modules::Authentication::RolesController` | `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`: S`/roles` | Scoped role lookup; existing custom-role CRUD; system-role edit/delete refusal in operations |
| `RoleGrantsController` in the same settings namespace | `show`, `update`: S`/roles/:role_id/grants` | Scoped role; locked-grant policy; platform/flowchart grants owner-restricted; instance grants tenant-checked |
| `UserRoleAssignmentsController` in the same settings namespace | `index`, `create`, `destroy`: S`/user_role_assignments` | Scoped user/join; atomic replacement; immutable owner and sole-reserved deletion rejection; HTML/JSON translated failure; audit only after success |
| `SignUpController` in the same settings namespace | `show`, `update`: S`/sign_up` | Scoped assignment; only `allow_registration` merge |
| `ForgetPasswordController` in the same settings namespace | `show`, `update`: S`/forget_password` | Scoped assignment; only `allow_password_reset` merge; omitted/blank input writes false consistently with notice |

The reserved authentication roles remain exactly `owner`, `admin`, and `member`.
Existing supplemental/custom-role CRUD and grants are legacy surfaces retained in
this dispatch; no new application role was introduced. The single-user editor
keeps existing supplemental assignments when replacing its reserved assignment.

### Member identity, security and configurable surfaces

| Controller | Exact actions / routes | Ownership / eligibility boundary |
| --- | --- | --- |
| `Member::DashboardsController` | `show`: M | Current user's greeting and sign-in history |
| `Member::ProfilesController` | `show`, `edit`, `update`: M`/profile` | `current_user` only; Reform email-change password verification; shared controlled credential-conflict response |
| `Member::SecuritiesController` | `show`: M`/security` | Current user's MFA/sign-in/device state |
| `Member::MfaController` | `setup` GET/POST M`/security/mfa/setup`; `destroy` DELETE M`/security/mfa` | Current user only; explicit POST enable; HEAD does not claim OTP or enable MFA; enrolled-secret guard; shared throttle; credential-locked mutations |
| `Member::TrustedDevicesController` | `destroy`: M`/trusted_devices/:id` | Device lookup through `current_user.trusted_devices` |
| `Member::SurfacesController` | `index`, `show`: M`/:key` and M`/:key/:id` | Effective descriptor eligibility; immutable descriptor scope; owned-record check on detail; builtin descriptors excluded |
| `Member::PagesController` | `show`: M`/pages/:id` | Accessible launched page and member visibility; documented same-tenant admin/owner GET/HEAD preview exception |

Additional generic actions were read for their authentication/member applicability:

- `Admin::ModulesController#index`, `ModuleEntriesController#show`,
  `ModuleHowtosController#show` (module registry/enablement and contribution scope).
- `Admin::ModuleConfigsController#show, update`, including the entry-key GET;
  configuration whitelist/merge excludes dedicated registration/reset toggles.
- `Admin::Maintenance::ModulesController#index`,
  `ModuleEnablementsController#create, destroy`, `ModuleSubTogglesController#update`,
  `ModuleOwnerConfigurationsController#update` (mandatory auth module and owner knobs).
- `Admin::Maintenance::Platform::ModuleSettingsController#index, show,
  configuration, developer, update`, including auth's platform signup switch.
- `Admin::Settings::MembersController#show, update`,
  `MemberSourcesController#show, update`, and `MemberSurfacesController#show, update`.

Payment business actions and unrelated public-page submissions are separate lanes.
Member page rendering was checked at its authentication/publication boundary, not
inside the excluded page/flowchart builders or ignored layout-template directory.
The shared `TenantContext`, `RouteAuthorization`, `Ability`, MFA obligations,
locale handling, and bearer concern were read; this lane did not edit the two
core authorization concerns.

## Supporting chains inspected

| Chain | Source anchors and observed contract |
| --- | --- |
| Password/session | `SignInFlow`, `PasswordVerification`, `FinishesSignIn`, `User::TenantSecurityPolicy`, installed Lockable/Timeoutable/Trackable hooks: tenant timeout/lockout values at call time, first factor, lock counters, MFA routing, rotated session and one explicit-login tracking hook |
| Email issuance | `EmailFloodThrottled`, `Throttle`, `IssuesSignInLink`, `IssueSignInLink`, `IssueCustomerSignup`, user recovery class methods: shared IP/recipient buckets and normalized email lookup |
| Signup | `CustomerSignupToken`, `CustomerSignup`, platform settings, authentication provisioner: purpose/TTL, customer/user transaction, seeded admin/owner assignment and global email uniqueness |
| Credential lifecycle | `User#apply_credential_lifecycle`, `CredentialLifecycle`, `MfaMutation`, `OwnerIdentity`: dirty credential snapshot rejection and user-row serialization; same-transaction grant revocation |
| TOTP/trust | `User::MfaMethods`, `MfaSessionVerification`, `TrustedDevice`, trusted-cookie concern: conditional timecode claim, verified-secret digest binding, scoped opaque device credential and current-snapshot issuance |
| MFA recovery | `ResetToken`, `RequestResetLink`, `ConsumeResetLink`: tenant/member/secret fingerprint, purpose/TTL, revalidation and mutation within the user lock |
| OAuth | `Protocol`, `DesktopClient`, `AuthenticateResourceOwner`, `AuthorizationCodeExchange`, `AccessToken`, `RefreshTokenConsumption`, `TokenIdentity`, `ServerMetadata`, `Userinfo`; installed pre-authorization, URI checker, code request, error response and introspection |
| Roles | `UsersRole`, `AssignmentPolicy`, `UserRoles::Operation::Assign`, Role CRUD and grant operations, `Ability`: fixed owner pin, at most one reserved assignment, sole-reserved delete guard and in-place replacement |
| Member overlays | `Member::Settings::Operation::Update`, `SurfaceSetting`, `EffectiveSurface`: pre-resolved atomic batch under customer lock, omission preservation, explicit visibility [], blank-copy reset and protected non-hideable fields |
| Audit/storage | `MutationAudit`, `AuditLog`, `Instrumentation`, `Event`; mutation facts share the write transaction, success logs wait for commit; explicit non-secret projections; relevant users, users_roles, trusted_devices, OAuth and member-overlay schema/index definitions |

## Confirmed findings and remediation status

**Implemented** below means source changes and regressions exist, not that their
runtime checks passed. Prior behavior was source-confirmed before this lane's
corresponding controller edits.

| ID / priority | Confirmed trigger and evidence | Current remediation / regression home |
| --- | --- | --- |
| AUTH-01 / P1 | Reset guard preferred top-level token, but Devise update consumed `user[reset_password_token]`; a forged or another tenant's allowed top-level token bypassed the disabled payload owner's reset gate. `PasswordsController#reset_password_token_owner`; installed passwords update. | Implemented: edit checks query token, update checks permitted payload token. `authentication/passwords_spec.rb`: both conflict directions, forged token, token/password preservation. |
| AUTH-02 / P1 | Registrations called Devise `update_with_password`, whose digest-only `valid_password?` bypassed persisted Lockable effects. Installed database-authenticatable method and registrations hook. | Implemented: `PasswordVerification.authenticate` before assigning dirty credentials; blank/invalid current-password and field errors retained. `authentication/registrations_spec.rb`: counters, lock limit, reset-on-success, no rejected credential persistence. |
| AUTH-03 / P1 | Desktop state/response-mode filter ran only for `new`, leaving direct consent POST outside the protocol restriction. `Oauth::AuthorizationsController` filter declaration. | Implemented for new/create/destroy. `oauth/pkce_flow_spec.rb`: missing/short state, fragment/form_post rejection, valid query-mode issuance. |
| AUTH-04 / P1 | Inherited denial called `authorization.deny` without `pre_auth.authorizable?`, and redirectable access-denied responses used supplied redirect_uri. Installed authorizations destroy/code-request deny/error response. | Implemented: validate client, allowed flow and registered destination before denial; invalid requests stay local. PKCE request specs cover remote/wrong-path/malformed/missing callback, unknown/other client, IPv4/IPv6 valid denial. |
| AUTH-05 / P1 | Member setup's `request.get?` split treated HEAD as a write; a supplied valid `code` could enable MFA and consume its OTP. `Member::MfaController#setup`. | Implemented: only POST enables. `member/mfa_spec.rb`: HEAD retains secret/timecode/enforcement and subsequent POST can consume the same code. |
| AUTH-06 / P2 | Parameter filters covered OTP aliases and PKCE fields but missed bare member/OAuth `code`. Filter initializer and member/token controller inputs. | Implemented exact-key case-insensitive filter, including nested keys, without hiding postal_code. Member and OAuth request specs inspect real filtered parameters and valid processing. |
| AUTH-07 / P2 | Missing/blank enabled input cast to nil; forgot-password persisted nil yet announced disabled, while `Settings` treats nil as reset-enabled by default. | Implemented: missing/blank/whitespace writes false, preserves sibling config and announces disabled. Forgot-password request specs cover each payload. |
| AUTH-08 / P2 | `FinishesSignIn` called `update_tracked_fields!` after sign_in, although Devise's after_set_user hook already did so. | Implemented: remove explicit duplicate. Session/link request specs assert one increment and preserved previous timestamp/IP. Bearer tracking is a separate remaining finding below. |
| AUTH-09 / P1 | Single-user role edits bulk-deleted system joins, bypassing new model callbacks and the fixed-owner/in-place replacement policy. `UsersController#assign_user_role`. | Integrated `Assign` under user lock; existing supplemental roles retained. Profile + role save uses a requires_new transaction so rejection rolls back both even under an enclosing transaction. Admin-user request specs cover retained join id, supplemental roles, rejection rollback and owner self-demotion. |
| AUTH-10 / P1 | Owner self-removal used to be allowed; new immutable/sole-reserved model aborts would raise RecordNotDestroyed through controller destroy!. `UserRoleAssignmentsController#destroy`, `AssignmentPolicy.removable?`, `UsersRole` destroy callback. | Integrated pre-check plus model-race rejection handling; translated HTML/JSON errors and no false revocation audit. Existing self-removal specs now require rejection. |
| AUTH-11 / P1 | Backend credential revocation locks user before grants, but stock authorization-code consumption locks the grant and uses a resource-owner id. The completed backend exchange wrapper was not yet called by the token controller. | Integrated cached `AuthorizationCodeExchange.call(code:)` around only the authorization-code response. PKCE request specs assert user-before-grant order, one exchange, stale revoked-code invalid_grant and normal unknown-code handling. |
| AUTH-12 / P2 | Backend snapshot guards now raise StaleObjectError; member profile, password/reset and MFA/admin controllers had no controlled response for it. | Integrated shared `HandlesCredentialConflicts` through ApplicationController, limited to User records; 409 text/JSON, no-store/no-referrer and request-locale translation. New credential-conflict requests simulate persisted intervening changes across those routes. |
| AUTH-13 / P1 | Doorkeeper grant issuance directly inserts a grant without the user lock; it could insert after credential revocation's grant scan using an old authenticated snapshot. Installed `Authorization::Code#issue_token!`; authorize-response path. | Integrated cached `CredentialLifecycle.with_current(current_resource_owner)` around issuance. PKCE request regression rejects a replaced snapshot without issuing a code. |

Regression paths in that table are relative to `spec/requests/`.

### Backend remediations inspected after completion

The backend lane supplied the original implementations below. The auth follow-up
added audit context to Assign/recovery and atomic app-registration boundaries;
underlying credential/owner/refresh invariants remain the backend implementation:

- Credential changes cover password, old-secret replacement/removal, email and
  customer identity. The account lock rejects stale snapshots and transactionally
  revokes trusted devices, OAuth access/refresh tokens, unredeemed authorization
  grants and email sign-in tokens. Initial nil-to-secret enrollment is not treated
  as replacement of an existing secret.
- Persisted owner identity remains pinned to email/customer; owner assignment is
  immutable even for the owner. Reserved replacements update their join in place.
- MFA checks and mutations bind to the current credential snapshot; timecode
  history resets on secret replacement. Trusted-device issuance and sign-in-link
  issuance/claim use account synchronization.
- Refresh consumption takes user-before-token locks, checks locked token state and
  expiry, and performs reuse family revocation outside the failed savepoint.
  Family scope is application/owner/family-clock, with a row-only NULL fallback.
- MFA recovery decodes and revalidates fingerprint/member/tenant under the same
  user lock as disabling the secret.
- Member settings resolve the whole batch before writing, serialize on customer,
  preserve omissions, support explicit empty visibility and reset display-copy
  overrides; protected descriptor fields remain visible.
- User password confirmation validation is now present; role predicates no longer
  use the old reserved-role-key instance memoization.

## Remaining-manifest remediation — RC-12 through RC-15

The four findings were source-confirmed in the coordinator's manifest. All four
now have scoped implementations and authored regressions; runtime remains pending.

| Manifest ID | Implemented fix | Regression evidence authored |
| --- | --- | --- |
| RC-12 | Recovery consume installs the existing NoStore concern/callback. GET, HEAD, POST and missing/invalid/expired-token branches carry private/no-store and no-referrer. | `authentication/mfa_recoveries_spec.rb` checks normal and error/redirect headers, unchanged HEAD/GET state and replay. |
| RC-13 | Bearer principal uses `warden.set_user(..., store: false, run_callbacks: false)`. TokenIdentity explicitly checks active_for_authentication? so suppressing Activatable does not admit locked/unconfirmed accounts. No browser Trackable/Rememberable callbacks or new session cookie. | Bearer request and TokenIdentity specs cover unchanged tracking, cookies, locked/unconfirmed users, member/admin role guards, token-over-cookie identity and cross-tenant/owner behavior. |
| RC-14 | MutationAudit captures actual role-ID deltas and MFA required/configured facts under the write lock. Outcome rows persist in the mutation transaction and disappear on rollback; success logging is deferred until all enclosing transactions commit. Shared writer is used by role editor/assignment/removal, auth/member MFA, admin reset and recovery. No-op/rejected writes emit no success row; old duplicate emissions are removed. | MutationAudit/Instrumentation services plus admin user, role-assignment, member MFA, global MFA and recovery requests cover actor/tenant/outcome attribution, before/after, rollback, failure, no-op, replay and absence of credentials in metadata. |
| RC-15 | Settings reads positive integer session_timeout (minutes) and max_login_attempts. User::TenantSecurityPolicy overrides instance timeout_in and Lockable's protected attempts_exceeded?/last_attempt? hooks. PasswordVerification and normal Devise strategies therefore share account-specific limits; no class/global configuration is mutated. Missing/malformed/inactive settings inherit current Devise class defaults. | Settings service, tenant-security model and real-session/request specs cover distinct tenants, changed policy on an already loaded user, real idle expiry, persisted tenant lock thresholds, last-attempt warning, successful reset/time unlock and unchanged class/global values. |

Mutation metadata is deliberately bounded to actor id, source, outcome, role ids
and boolean MFA before/after states, alongside existing event user/customer/IP/UA
attribution. Passwords/digests, OTP secrets/codes, recovery tokens and request
parameter hashes are not copied into the ledger. MFA reset of a configured but
not-enforced secret records mfa_disabled with truthful before/after flags.

### App-registration reserved-role completeness

Member signup now saves the account and its existing member-assignment hook inside
one requires_new customer-lock transaction. Assignment failure rolls the account
back and renders a translated existing error. Admin user create already uses its
atomic assignment operation and defaults omitted role to member. Customer signup
uses a requires_new transaction, and the provisioner locks the customer while
creating its account plus admin/pinned-owner join. Regressions cover exactly one
reserved role and failure leaving no orphan account/tenant.

Raw model creation is still available for legacy/internal fixtures; no new User
create callback assigns a role to unrelated callers. The mounted app registration
paths are complete; direct callers outside those paths must use the existing
provisioning/assignment APIs. Reserved roles remain owner/admin/member.

## Tests and integration handoff

No commands below were executed here. Run the focused changed request files:

```bash
bundle exec rspec \
  spec/requests/authentication/passwords_spec.rb \
  spec/requests/authentication/registrations_spec.rb \
  spec/requests/authentication/sessions_spec.rb \
  spec/requests/authentication/sign_in_links_spec.rb \
  spec/requests/authentication/credential_conflicts_spec.rb \
  spec/requests/authentication/tenant_security_policy_spec.rb \
  spec/requests/authentication/mfa_recoveries_spec.rb \
  spec/requests/authentication/mfa_setups_spec.rb \
  spec/requests/authentication/mfas_spec.rb \
  spec/requests/authentication/admin/users_spec.rb \
  spec/requests/admin/settings/modules/authentication/user_role_assignments_spec.rb \
  spec/requests/admin/settings/modules/authentication/forget_password_spec.rb \
  spec/requests/member/mfa_spec.rb \
  spec/requests/oauth/pkce_flow_spec.rb \
  spec/requests/oauth/bearer_authenticatable_spec.rb
```

Integration checks should also cover the existing member profile, auth MFA
setup/session/disable/recovery, confirmations/customer signup, bearer and roles/
grant request specs. Backend dependency checks:

```bash
bundle exec rspec \
  spec/services/oauth/authorization_code_exchange_spec.rb \
  spec/models/oauth/access_token_spec.rb \
  spec/models/authentication/user_credential_revocation_spec.rb \
  spec/models/authentication/user_identity_spec.rb \
  spec/models/authentication/user_otp_replay_spec.rb \
  spec/models/authentication/trusted_device_spec.rb \
  spec/models/users_role_spec.rb \
  spec/concepts/user_roles/operation/assign_spec.rb \
  spec/concepts/member/mfa/operation/consume_reset_link_spec.rb \
  spec/concepts/member/settings/operation/update_spec.rb \
  spec/models/member/surface_setting_spec.rb \
  spec/services/member/effective_surface_spec.rb \
  spec/services/authentication/consume_sign_in_link_spec.rb \
  spec/services/authentication/issue_sign_in_link_spec.rb
```

Additional exact remaining-manifest checks (also not executed):

```bash
bundle exec rspec \
  spec/models/authentication/user_tenant_security_policy_spec.rb \
  spec/services/authentication/settings_spec.rb \
  spec/services/authentication/mutation_audit_spec.rb \
  spec/services/authentication/audit_log_spec.rb \
  spec/services/authentication/instrumentation_spec.rb \
  spec/services/oauth/token_identity_spec.rb \
  spec/services/authentication/customer_signup_spec.rb \
  spec/services/feature_modules/authentication/provisioner_spec.rb
```

Controller integration of the completed backend APIs is source-complete. Runtime
acceptance, actual database lock-contention/deadlock checks, mounted/format route
expansion, and browser/CSRF verification are pending; deterministic interleaving
request examples do not substitute for those checks.

## Developer-reference follow-up

The coordinator owns matching updates under **both** `doc/reference/en/` and
`doc/reference/zh-CN/`:

- `authentication.md`: credential lifecycle/revocation, fixed-owner identity,
  Lockable account re-auth, token-selection reset gate, single-login tracking,
  bare-code filtering, translated 409 credential-conflict contract, transactional
  mutation outcomes, hardened recovery responses and tenant Devise policy hooks.
- `oauth.md`: protocol checks on POST/DELETE, registered denial destinations,
  user-before-grant exchange locks, account-locked issuance and ordinary OAuth
  invalid_grant responses; distinguish mounted introspection/native routes from
  advertised desktop endpoints; callback-free bearer principal and explicit
  Devise eligibility without browser tracking/session side effects.
- `authentication-module.md`: false persistence for missing/blank reset-toggle
  input, effective positive-integer tenant timeout/lockout policy, minutes unit,
  malformed/inactive defaults and unchanged global Devise fallback.
- `access-grants.md` and `tenancy-and-roles.md`: immutable fixed owner, sole
  reserved-role deletion refusal, atomic in-place replacement and retained legacy
  supplemental roles, with translated controller rejection behavior.
  Document actual role-ID delta events and atomic initial app assignments.
- `member-and-public.md`: POST-only MFA enable/HEAD non-consumption, credential
  conflicts on profile/MFA/admin reset paths and member overlay omission/reset
  semantics from the backend change.

This audit file was the documentation artifact written in the initial source-only
auth dispatch; later reference synchronization and test evidence are recorded below.

## Subsequent targeted RSpec remediation

Groups 6–10 of `2026-10-11-rspec-verification.md` were remediated and executed
against `storage/auth_verify.sqlite3`: the 11 associated files passed **280
examples, 0 failures**, and adjacent cookie/bearer/tenant-policy files passed **52
examples, 0 failures**. Exact commands, the concurrent data-migration preparation
step and remaining full-suite scope are recorded in that report's auth follow-up.

Quota fixtures use accepted member-limit snapshots and real member assignments;
protected Devise access stays protected; role fixtures perform reserved replacement;
idle expiry checks the real logged-out Warden scope and Devise's retry-to-sign-in
journey; grant errors carry a Doorkeeper ErrorResponse and return structured 400.
Nested billing grant labels reuse distinct bilingual action keys. OAuth,
authentication and access-grants references were updated in both locales.

The earlier source-only audit provenance remains historical. These targeted runs
do not establish a green full application suite, production contention behavior,
or browser/JavaScript acceptance beyond the two executed system files.
