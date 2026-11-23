---
title: "Module framework"
summary: "How the seven feature modules register, provision on enablement, and expose four admin surfaces."
---

## Summary

A feature module is `FeatureModules::<Key>::Registration`, a subclass of `FeatureModules::BaseModule`. Boot loads every `app/services/feature_modules/*/registration.rb` and calls `register!`, which upserts a `feature_modules` row. Enabling a customer runs `provision!` and marks `FeatureModules::CustomerAssignment` active. The seven keys are `authentication`, `payment`, `email`, `sms`, `captcha`, `ai_assistant`, and `website`. Each module has four admin surfaces: entries, customer settings, the enable toggle, and platform module settings. Per-module behavior is in [authentication-module](authentication-module), [payments](payments), [email](email), [sms](sms), [captcha](captcha), [ai-assistant](ai-assistant), and [websites](websites).

## Configuration checklist

The platform-owner directory is `/81721200/admin/maintenance/platform/module_settings`. An **active** module means it can be enabled for a customer; it does not mean its provider credentials, vendor permissions, callbacks, or customer settings are complete. Check the relevant environment (`sandbox` outside Rails production, `production` in Rails production) and make a real transaction or challenge before considering a provider ready. These are application modes, not automatic vendor sandboxes.

| Module | What still needs configuring | Detailed setup |
| --- | --- | --- |
| Authentication (`authentication`) | Required module; choose the platform customer sign-up switch, then set each tenant's member registration, password reset and MFA policies. No external identity-provider credentials are required. | [Authentication module](authentication-module) |
| Payments (`payment`) | Make gateways available globally; each customer needs its own active, configured merchant row per gateway and mode, vendor product permissions and payment notifications. | [Payments: gateway setup](payments) |
| Email (`email`) | Save a platform credential in the runtime mode, activate one delivery vendor, verify its sender/domain and set up receipt notifications when supported. | [Email: provider setup](email) |
| SMS (`sms`) | Save and activate a platform credential, obtain approved sender/templates, and map vendor template codes on active platform templates; configure Twilio callbacks if used. | [SMS: provider setup](sms) |
| Captcha (`captcha`) | Save and activate one platform provider, register challenge hostnames where applicable, and select platform/tenant URL throttles. An incomplete provider makes the Rack gate fail open. | [Captcha: provider setup](captcha) |
| AI assistant (`ai_assistant`) | Save provider credentials, separately assign configured providers to Generation and Audio Transcribe, then enable the module for each tenant. | [AI assistant: provider setup](ai-assistant) |
| Website (`website`) | Choose the default skeleton in module configuration, curate platform skeleton/layout catalogs as needed, enable per tenant and publish its site/pages; there is no external provider credential. | [Website builder](website-builder) |

The directory's configuration indicator describes **provider vs defaults vs no schema**, not a live health check or a list of missing fields. Follow the linked pages to distinguish vendor prerequisites from saved app settings.

### Local configuration audit (October 3, 2026)

This is a **dated snapshot of the local application's saved settings**, not a live monitor or confirmation of vendor-side approval. All seven module rows were globally active at the time of the check; a tenant assignment and end-to-end test are still separate requirements. No secret values are included.

| Module | Saved-setting result / remaining work |
| --- | --- |
| Authentication | Mandatory and active; platform customer sign-up enabled. Review each tenant's member sign-up, MFA and password-reset choices as needed. |
| Payments | All four platform gateways available. Of five **active sandbox** merchant rows, only **one Stripe row** passes `configured?`; four other active rows still have a seeded merchant ID and missing credential fields. All observed production merchant rows are disabled. Set up the desired tenant/mode rows using [the gateway steps](payments). |
| Email | **No platform credential rows.** Add and assign at least one credential in the runtime mode; complete sender verification and any receipt callback. |
| SMS | **No platform credential rows.** Add and assign a credential, then create approved sender and mapped platform templates. |
| Captcha | Aliyun, Turnstile and reCAPTCHA v3 rows are all **inactive and unconfigured**. Supply keys, activate one provider and check challenges. |
| AI assistant | **AWS Bedrock** is the configured Generation assignee; **AWS Transcribe** is the configured Audio Transcribe assignee. The saved OpenAI / Whisper row is configured but not assigned. Test a chat reply and spoken audio before treating either active assignment as verified. |
| Website | `default_skeleton_key` defaults to `presence`; the platform catalog contains skeletons and layouts, with a published site. No third-party provider credential is needed; review each tenant's site and publication state separately. |

Specifically, the four incomplete **active sandbox payment rows** have these missing values (field names only): Alipay — Merchant ID, `private_key_pem`, `platform_public_key_pem`; PayPal — Merchant ID, `client_id`, `client_secret`, `webhook_id`; Stripe — Merchant ID, `secret_key`, `publishable_key`, `webhook_signing_secret`; WeChat Pay — Merchant ID, `appid`, `api_key_v3`, `private_key_pem`, `platform_public_key_pem`, `wechat_cert_serial`. A **separate** Stripe sandbox row is fully configured. This snapshot says nothing about whether its Stripe webhook has actually delivered.

## Flow

```text
config/initializers/feature_modules.rb
        |
        |  glob registration.rb -> constantize -> register!
        v
feature_modules row (key, name, status, required)
        |
        |  mandatory? -> status active, required true
        |  required rows provisioned for every Customer
        v
POST /:cid/admin/maintenance/modules/:module_id/enablement
        |
        |  ModuleEnablementsController#create
        |  registration_class.provision!(customer)
        |  then persist CustomerAssignment status active
        v
sidebar entries + settings, HostIntegration#before_request

Page submit handoff (after activity success, before submission commits)
        |
        v
FeatureModules::Invocation.begin!
        |
        |  session[:feature_module_invocation]
        |  redirect to registration.entry_path_for(customer)
        v
module entry page
        |
        v
FeatureModules::Complete.call -> ExitResolver -> clear session
```

Compiled flowchart steps do not call `Invocation`. An invoke-service step may call an allow-listed class under `FlowchartRuntime::Invocable::SERVICE_NAMESPACES`, which includes `FeatureModules`. See [flowchart-runtime](flowchart-runtime) and [page-rendering](page-rendering).

## Implementation

`BaseModule` requires `module_key`, `module_name`, and `provision!`. The default `deprovision!` is an empty method. `before_request` defaults to nil. `sidebar_contributions` defaults to empty `entries` and `settings` arrays. `mandatory!` sets the class as permanently active. `enabled_for?(customer_id)` is the tenant gate, `FeatureModules::Module.enabled?` for the class's own `module_key`; callers such as `FeatureModules::Website::Registration.enabled_for?(customer.id)` use it instead of repeating the key string. `register!` finds or initializes `FeatureModules::Module` by key, writes name, description, and `configuration_schema`, and sets `status: :active` and `required: true` when `mandatory?`. A new non-mandatory row starts `inactive` and `required: false`. An existing non-mandatory row keeps the stored status and required flag.

The handoff DSL is `entry_path`, `default_exit` (`kind` one of `page`, `flowchart`, `url`, `route`), `input_contract`, and `output_contract`. Contract fields become `HandoffField` descriptors and a `Reform::Form` subclass. `source` defaults to `:author_only`. `:user_fillable` is the value a module entry page may collect.

`FeatureModules::Module#registration_class` constantizes `FeatureModules::<camelized key>::Registration`. A missing class returns `NullRegistration`, whose `provision!` and `deprovision!` are nil. `enabled?` is an active module joined to an active `CustomerAssignment` for that customer. `available` is `status: :active`. `handoff_enabled` is a column; an inactive module cannot set it.

`config/initializers/feature_modules.rb` runs `after_initialize` when `feature_modules` exists. It `require_dependency`s each registration file, constantizes `FeatureModules::<directory>::Registration`, and calls `register!`. It then finds `FeatureModules::Module.required` and, for each customer missing an active assignment, saves one and calls `provision!`.

| Key | Class | `provision!` | Enablement note |
| --- | --- | --- | --- |
| `authentication` | `FeatureModules::Authentication::Registration` | `FeatureModules::Authentication::Provisioner.call` | `mandatory!`; `deprovision!` calls `FeatureModules::Authentication::Deprovisioner.call` |
| `payment` | `FeatureModules::Payment::Registration` | `FeatureModules::Payment::Provisioner.call` | `deprovision!` calls `FeatureModules::Payment::Provisioner.revoke` |
| `email` | `FeatureModules::Email::Registration` | `FeatureModules::Email::Provisioner.call` | `deprovision!` calls `FeatureModules::Email::Provisioner.revoke` |
| `sms` | `FeatureModules::Sms::Registration` | `FeatureModules::Sms::Provisioner.call` | `deprovision!` calls `FeatureModules::Sms::Provisioner.revoke` |
| `captcha` | `FeatureModules::Captcha::Registration` | `FeatureModules::Captcha::Provisioner.call` | `deprovision!` calls `FeatureModules::Captcha::Provisioner.deprovision` |
| `ai_assistant` | `FeatureModules::AiAssistant::Registration` | returns nil | `deprovision!` returns nil |
| `website` | `FeatureModules::Website::Registration` | `FeatureModules::Website::Provisioner.call` | `deprovision!` calls `FeatureModules::Website::Provisioner.deprovision` |

`Payment::Provisioner.call` inserts a disabled `Payments::MerchantAccount` per available gateway and mode. `revoke` sets those accounts to `disabled` and leaves the credential rows.

`Admin::Maintenance::ModulesController#index` lists `FeatureModules::Module.available` and the customer's enabled assignment ids, and takes each enabled module's primary link from `Dashboard::ModuleCards`. `Admin::Maintenance::ModuleCatalogComponent` renders them as enabled / not enabled / required counts, a `list-filter` search, and `NavigationOrder` sections of `ModuleCatalogCardComponent` cards. Each card shows the module icon, its status, the `Dashboard::ModuleCards.blurb_for` description, an **Open** link when enabled, and an on/off `ModuleToggleComponent` switch that POSTs or DELETEs the `enablement` resource (`http_method:`, no `field`). The switch is locked when a required module is enabled. `ModuleEnablementsController#create` requires `feature_module.active?`, sets the assignment `active`, and calls `provision!` in one transaction. `destroy` refuses `required?` modules, sets the assignment `suspended`, and calls `deprovision!`. `ModuleSubTogglesController#update` writes a boolean key that is both in `configuration_keys` and typed `"boolean"` in `configuration_schema`. A registration's `owner_managed_configuration_keys` declares customer-specific limits shown read-only in Settings and editable by the platform owner on that customer's Maintenance / Modules page. `ModuleOwnerConfigurationsController#update` at `PATCH /:cid/admin/maintenance/modules/:module_id/owner_configuration` requires the owner, an active module and assignment, and an integer in range (non-negative for send caps, positive for recording seconds); it merges only declared keys into that customer's assignment. Email and SMS declare `daily_send_cap`; AI Assistant declares `max_duration_seconds`.

`FeatureModules::HostIntegration` is included in `ApplicationController`. Each request with a current customer iterates `enabled_for_customer` and calls `registration_class.before_request`. Iteration order is unspecified. A performed response stops the loop. `feature_module_enabled?` is the view helper.

The four surfaces, as routed under `/:cid/admin`:

1. Entries and records: `namespace :modules` and `ModulesContributor`, which reads `sidebar_contributions[:entries]`. The generic reader is `Admin::ModuleEntriesController#show` at `/admin/modules/:module_key/entries/:key`, which calls `entries_for`. The hub and nested record pages show record actions only, without configuration, site-publishing, or maintenance shortcuts. The separate HowTo page also offers relevant customer settings links. Enabled settings-only modules such as Captcha remain visible as informational cards without record actions and have a HowTo item in the Modules sidebar.
2. Customer settings: `resources :module_configs` at `settings/modules/:key` (`Admin::ModuleConfigsController`), plus settings links from `sidebar_contributions[:settings]` and `SettingsContributor`. The `/admin/settings` catalog and sidebar group these destinations under a separate, localized heading for each enabled module (including Captcha and future modules); shared Member and Billing settings have their own sections. The Settings sidebar wraps those flat catalog headings in the same `SidebarNodeComponent` disclosure used for Modules. Both menus share one look: compact 36px top-level rows (44px touch rows on mobile) with a 24px icon tile tinted by `SidebarNode#tone` through `module_color_classes` (neutral for Overview, Members and Billing); plain-text child rows on a thin guide line, where the selected child gets an accent pill plus a short accent marker on the line; and, on a collapsed group, a count of its destinations beside the chevron. Setting links keep their icons (a sliders icon where none is supplied) for the collapsed icon rail, but the expanded sub-menu does not draw them. This applies to the desktop sidebar, global drawer and mobile Settings dialog; the global drawer renders Modules through the same searchable `SidebarComponent`. The section containing the selected child expands on page load, and that child shows its active styling and `aria-current="page"`; all other sections start closed. Search temporarily opens matching sections and restores their previous state afterward. Setting permissions are filtered before grouping. Tenant settings remain under `/:cid/admin/settings/modules/<module>`, independently of the platform-owner configuration namespace. The generic config form displays owner-managed limits as read-only values; its PATCH whitelist excludes them even for forged submissions, while other customer preferences remain editable.
3. Enable, disable and owner-managed customer limits: `Admin::Maintenance::ModulesController` at `/admin/maintenance/modules`, with `ModuleEnablementsController` on the nested `enablement` resource and `ModuleOwnerConfigurationsController` for the platform owner's per-customer limit changes.
4. Platform module settings: `Admin::Maintenance::Platform::ModuleSettingsController` at `/admin/maintenance/platform/module_settings` and `/admin/maintenance/platform/module_settings/:key` (overview, `configuration`, `developer`). Nested provider routes live under that prefix (`email/credentials`, `sms/credentials`, `sms/templates`, `captcha/settings`, `captcha/pages`, `ai_assistant/settings`, `payment/gateways`, `payment/webhook_events`). This namespace requires `platform_owner?`.

`FeatureModules::Invocation` owns `session[:feature_module_invocation]`. `begin!` requires a module row, `handoff_enabled?`, an active assignment, a valid input contract (after `InputCaster`), and a non-blank `entry_path_for`. It stores `customer_id`, page id, entry id, a token, cast input, and `exit_target`, then returns the entry path. `current` raises `CrossTenantViolation` when `Current.customer` differs from the stored customer. `FeatureModules::Complete.call` validates the output contract, asks `ExitResolver` for a URL, writes a log, and `clear!`s the session.

The Settings catalog at `/:cid/admin/settings` uses responsive one-, two-, or three-column cards depending on available space. It shows the localized page introduction, group icon/name/description, and each permitted setting's name and explanation in a full-width link row; the separate Settings sidebar retains its desktop and mobile search. The catalog does not duplicate the search field. Permission filtering and grouping continue to come from `SettingsContributor`; module descriptions are passed through its section headings, and Member/Billing have localized group descriptions. Sending and recording limit descriptions explain that only the platform owner can adjust those values.

`FeatureModules::NavigationOrder` sets the order on both sidebars and owns the module categories (`SECTIONS`, `SECTION_ORDER`, `section_for`, `by_section`) that the Modules hub (`Dashboard::ModuleCards`, `Admin::Modules::HubComponent`) also uses. After Overview, both sidebars list modules under localized category headings (`admin_modules.index.sections.*`): **Records & data** (User Authentication, Website), **Communication** (Payments, Email, SMS), **Growth & protection** (Captcha, AI Assistant) and **More modules** (any future module, by name). A heading is a `SidebarNode` with `category: true`; `SidebarComponent#categories` renders it as an `h3` that labels its list, hides it while searching when none of its items match, and skips categories with no visible groups. The collapsed icon rail shows a divider instead. Only enabled modules with available destinations are shown on Settings; the Modules sidebar shows all enabled modules. Settings ends with an **Organization** category (`settings_navigation.categories.organization`) holding its Members and Billing sections. The same order applies to the mobile navigation; the Settings catalog follows the section order too.

### What the optional Return URL does

`Admin::Settings::ModuleConfigComponent` shows **Return URL (optional)** only when the module is enabled for the customer **and** the platform owner has enabled `FeatureModules::Module#handoff_enabled`. The field and its separate form are absent otherwise; `Admin::ModuleConfigsController` also ignores a manually submitted `exit_landing_page` when handoff is off, while continuing to save permitted non-handoff settings. `SettingsContributor` adds a **Return URL (optional)** child to the Settings section of each handoff-enabled module, including those with no schema or with dedicated settings pages; the link opens the generic configuration form at `/:cid/admin/settings/modules/:module_key/return_url` (plural route segments where applicable). A previously saved URL remains in that customer's `CustomerAssignment.configuration` but is ignored until handoff is enabled again. This is not a redirect after saving settings, nor a universal redirect after a module action. `FeatureModules::ExitResolver` uses the page handoff's own `exit_target` first, then an active customer's saved URL **only when handoff is enabled**, then the module's `default_exit`, then the organization dashboard. Enter a full HTTP or HTTPS URL; leave it blank to use the default. The override applies only when a module completes a handoff or explicitly uses the resolver.

Exit resolution treats missing `CustomerAssignment.configuration`, JSON `null`, and non-object JSON (arrays, strings, numbers, or booleans) as having no customer-level override. If the session exit target is absent or cannot resolve, the resolver continues to the registration's `default_exit`, then `/:customer_id/admin/dashboard` if that default is absent or cannot resolve. Valid JSON objects still supply their `exit_landing_page` value as before. Saving customer settings is not a prerequisite for completing a handoff, including a newly enabled SMS module.

| Module | When the Return URL matters |
| --- | --- |
| Authentication | Regular sign-in, sign-up, and password recovery use their own destinations; they do not use this URL. |
| Email | Sending or scheduling email does not currently complete a page handoff or use this URL. |
| SMS | Sending messages and viewing delivery do not currently complete a page handoff or use this URL. |
| Payments | A successful page-to-payment handoff redirects the shopper here unless the page chose a destination. The standalone result page's **Return** button also uses this URL, even without a handoff. It is not a gateway webhook or provider return URL. |
| AI assistant | Chat replies and dictation do not currently complete a page handoff or use this URL. |
| Captcha | Challenges, verification, and throttling do not use a Return URL; the dedicated Captcha settings page does not show this generic field. |
| Website | Publishing the site or its pages does not use a Return URL; the dedicated Website settings page does not show this generic field. |

### Customer HowTo in the Modules sidebar

The `/:cid/admin/modules` directory shows an introduction, section headings, and spacious responsive module cards with icon, localized module description, and one list of record destinations. It has no search box or filtering; the separate Modules sidebar still has its own search. It omits the module-count badge, modules/pages overview tiles, and duplicate action buttons. The compact Admin Home module cards keep their own description and render their destinations as pill links (see [Dashboard](dashboard)). Both catalog pages use a restrained bordered Card/Item treatment with generous spacing, 44px-plus link targets, visible navigation arrows, and wrapping labels and descriptions on narrow screens.

`/:cid/admin/modules` renders enabled modules from `Dashboard::ModuleCards`. `ModulesContributor` adds **How to use** as the first nested link under **every enabled module** in the desktop and mobile Modules sidebar, before any record entries. This includes Captcha and AI Assistant, whose groups previously had no record entries. The link opens `GET /:cid/admin/modules/:module_key/howto` (`Admin::ModuleHowtosController#show`), guarded by the admin route policy and a customer-specific `available_for_customer` lookup; missing or disabled module keys return 404. `Admin::Modules::HowtoComponent` shows localized numbered steps with **contextual links alongside each step**: customer settings contributed by the module (permission-filtered) and available feature/record destinations. Every step link opens in a new tab (`target="_blank"`, `rel="noopener noreferrer"`); on mobile the links wrap beneath their step. Captcha links to its settings and the tenant's Pages list to configure and test a protected page; AI Assistant links to its workspace. Separate shortcut panels are not shown. The hub cards do not repeat the guide or link to settings. Steps live in `admin_modules.index.howto.steps` in both locale files. Future module keys get a generic guide tailored to whether record links exist, linking to the first available destination where one exists.

Each step has **exactly one** link, not a group of shortcuts. Authentication splits sign-up and password recovery; Email splits template creation and recipient-list creation; Captcha separates page limits from page editing; Website separates site publication from checking its pages. Future modules with no own links direct readers to the Settings catalog and Modules overview.

| Module | Guide covers |
| --- | --- |
| Authentication | Member sign-up/recovery policies, managing users and roles, reviewing the Security Log. |
| Email | Viewing the owner-managed sending limit and platform delivery prerequisite, creating a template and list, sending or scheduling an activity. |
| Payments | Configuring a tenant merchant account, collecting through checkout and reviewing transactions, recurring subscriptions. |
| SMS | Viewing the owner-managed daily cap and approved sender/template prerequisite, sending through a workflow, reviewing messages and opt-outs. |
| Captcha | Active provider prerequisite, page limits and optional page challenge, browser verification; no record link is added. |
| AI assistant | Choosing a language and viewing the owner-managed audio limit, asking or drafting, reviewing proposed changes and optional dictation. |
| Website | Site details, editing and publishing pages, publishing and checking the site. |

## Where to pay attention

### Route audit: defaults, rollout and handoff invariants

`BaseModule.register!` refreshes metadata and preserves saved defaults for declared keys. Platform update prevalidates types/models/sensitive-token fields, then locks/transacts mutations and required rollout; missing module stays 404. Tenant enablement and required-rollout controllers provision before activation. Website's provisioner checks `result.success?` and raises `FeatureModules::Website::Provisioner::ProvisioningError` on failure, so failed starter/collision validation cannot commit an active assignment. Customer/boot required-module paths retain their own transactional ordering.

`InputMapper` reads identity metadata and audience-visible schema data (including JSON-string-backed `data`), never arbitrary model methods. `HandoffCompletion` accepts only declared fillable scalars. `PublicSubmission` runs activity and handoff preparation in one savepoint; `Invocation.with_submission` restores an earlier session invocation on failure. Rejected creates/updates roll back together rather than deleting a returned existing record. See [Page rendering](page-rendering), [Payments](payments), [Websites](websites).

:::note
Registration/default, rollout and submission-handoff regressions are authored, not executed here. A provider-ready badge or source-level transaction does not establish an end-to-end runtime pass.
:::

:::attention
`FeatureModules::Authentication::Registration` calls `mandatory!`. `BaseModule.register!` then forces `status: :active` and `required: true`. `ModuleEnablementsController#destroy` redirects with `required_module` when `required?` is true. The initializer comment mentions `required!`; the method on `BaseModule` is `mandatory!`.
:::

:::attention
`BaseModule.register!` leaves `status` and `required` untouched on an existing row that is not `mandatory?`. Boot does not turn an owner-disabled module back on. A brand-new non-mandatory row is saved `inactive`.
:::

:::attention
`PublicPagesController#start_page_handoff` runs through the successful activity completion block inside `Pages::PublicSubmission`'s transaction. Generated activity source does not call `Invocation`; allowlisted invoke-service steps remain separate.
:::

:::attention
`FeatureModules::Payment::Provisioner.revoke` updates `Payments::MerchantAccount` rows to `status: "disabled"`. The comment on `revoke` states that turning the module off keeps the credential rows. `FeatureModules::AiAssistant::Registration.provision!` and `deprovision!` are nil.
:::

:::attention
`FeatureModules::HostIntegration#run_feature_module_before_request` walks `FeatureModules::Module.enabled_for_customer` with no documented order. A `before_request` that `performed?` skips the remaining modules. `registration_class` falls back to `FeatureModules::Module::NullRegistration` when the constant is missing.
:::

## Key code

```ruby
# app/services/feature_modules/base_module.rb
      def register!
        fm = ::FeatureModules::Module.find_or_initialize_by(key: module_key)
        fm.name                  = module_name
        fm.description           = module_description
        persisted_schema = fm.configuration_schema_json
        fm.configuration_schema = configuration_schema.to_h.transform_keys(&:to_s).to_h do |key, field|
          definition = field.stringify_keys
          configured = persisted_schema.is_a?(Hash) ? persisted_schema[key] : nil
          definition["default"] = configured["default"] if configured.is_a?(Hash) && configured.key?("default")
          [key, definition]
        end.to_json

        if mandatory?
          fm.status   = :active
          fm.required = true
        elsif fm.new_record?
          fm.status   = :inactive
          fm.required = false
        end
        # else: preserve persisted owner-set status/required.

        fm.save!
      end
```

```ruby
# config/initializers/feature_modules.rb
    klass.register!
```

```ruby
# app/controllers/admin/maintenance/module_enablements_controller.rb
        ActiveRecord::Base.transaction do
          feature_module.registration_class.provision!(current_customer)
          customer_feature.save!
        end
```

```ruby
# app/models/feature_modules/module.rb
    def registration_class
      "FeatureModules::#{key.camelize}::Registration".constantize
    rescue NameError
      NullRegistration
    end
```

```ruby
# app/services/feature_modules/invocation.rb
        session[SESSION_KEY] = {
          module_key:         feature_module.key,
          customer_id:        customer.id,
          triggering_page_id: triggering_page&.id,
          entity_entry_id:    entity_entry&.id,
          # Per-invocation secret. Modules that materialize a domain object
          # (e.g. Payments stamps it onto the Payment at charge time) can bind
          # completion to THIS invocation, not just to a shared idempotency key.
          token:              SecureRandom.hex(16),
          input:              casted_input.transform_keys(&:to_sym),
          exit_target:        exit_target,
          started_at:         Time.current.iso8601
        }
```

```ruby
# app/controllers/concerns/feature_modules/host_integration.rb
      FeatureModules::Module.enabled_for_customer(current_customer_id).each do |fm|
        fm.registration_class.before_request(self)
        return if performed?
      end
```
