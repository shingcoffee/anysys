# Platform Module Settings Workspace Redesign

Date: 2026-09-07
Status: Approved for implementation planning

## Objective

Refactor `/81721200/admin/maintenance/platform/module_settings` and every
nested module-settings surface into one consistent, professional, responsive
workspace that is easier to scan, understand, and operate.

The redesign covers Authentication, Captcha, Email, Payments, SMS, and Speech
to Text. It may reorganize and consolidate navigation and presentation where
that improves usability, but it must preserve existing routes, authorization,
persistence, provider discovery, tenant behavior, and business logic.

## Users and access

The workspace is exclusively for the platform owner: the user with the
`owner` role under customer `81721200`.

The redesign must preserve existing controller-level authorization:

- Anonymous users cannot access protected platform settings.
- `admin` and `member` users cannot read or mutate platform settings.
- Requests in a non-platform customer context cannot expose or mutate platform
  settings.
- UI visibility is not an authorization mechanism.

## Design principles

1. Use one predictable page structure across all modules.
2. Separate routine configuration from operational and developer concerns.
3. Show configuration health and consequences before exposing controls.
4. Keep one clear primary action per page state.
5. Prefer progressive disclosure over presenting every setting at once.
6. Preserve context when moving between module overview and nested pages.
7. Make routine tasks usable without horizontal page scrolling.
8. Use reusable ViewComponents, Tailwind utilities, and narrowly scoped
   Stimulus controllers.
9. Route every displayed string through I18n with matching `en` and `zh-CN`
   keys and interpolation variables.

## Information architecture

Every module uses the same conceptual navigation. Sections are displayed only
when they apply to that module.

### Overview

The module's operational summary:

- Active, inactive, required, or mandatory status
- Configuration-health summary
- Assigned provider or gateway summary where applicable
- Important warnings or incomplete setup
- Platform-wide scope notice
- Links to the next useful configuration task

### Configuration

Normal platform behavior and schema-backed defaults, including
module-specific controls such as Authentication customer signup.

### Providers

Provider assignment, credential state, provider selection, connection testing,
delivery mode, and provider-specific configuration for Email, SMS, Captcha,
Speech to Text, and Payments where applicable.

### Resources

Module-owned records and targeting controls:

- SMS templates
- Captcha protected or skipped surfaces and shared pages
- Similar module-owned resources added later

### Operations

Operational diagnostics and event history:

- Payment webhook events and redrive actions
- Connection tests
- Provider failures and actionable status information

### Developer

Technical controls and reference information that should not compete with
routine settings:

- Handoff target
- Models and table metadata
- Extendability
- Template token exposure
- Integration contracts or schema details

## Shared workspace shell

All module pages and nested pages use a shared
`Admin::Maintenance::Platform::ModuleSettings::ShellComponent`.

The shell owns:

- Breadcrumbs
- Module identity and description
- Platform-wide scope notice
- Semantic status and health indicators
- Module-level navigation
- Active-section state
- Consistent content widths and vertical rhythm
- Responsive navigation behavior

Desktop pages use a constrained general workspace of approximately
`max-w-6xl`. Ordinary settings forms use a narrower readable region of
approximately `max-w-3xl`. Wide technical or operational collections may use
the full workspace width.

The module navigation appears beneath the module header. It uses stable labels
and ordering across modules. On small screens, it becomes a horizontally
scrollable control or a compact select/drawer when the number of sections
would make tabs difficult to use.

## Shared component system

The redesign should reuse existing project components where suitable:

- `AdminPageComponent`
- `BreadcrumbsComponent`
- `ButtonComponent`
- `BadgeComponent`
- `AlertComponent`
- `EmptyStateComponent`
- `AdminTableComponent`
- `FormErrorsComponent`

New or consolidated components:

### `ModuleSettings::ShellComponent`

Provides the module header, status, scope notice, primary navigation, active
state, and responsive workspace container.

### `ModuleSettings::SummaryComponent`

Presents availability, configuration health, assignment state, and warnings in
a compact and consistent summary.

### `ModuleSettings::SectionCardComponent`

Standardizes section title, description, actions, content, validation or
warning state, and optional footer.

### `ModuleSettings::SettingRowComponent`

Standardizes a setting's label, explanation, current value or control,
validation state, and disabled/dependency explanation. Rows stack cleanly on
small screens.

### `ModuleSettings::ProviderWorkspaceComponent`

Provides a common provider flow:

1. Assignment or delivery selection
2. Provider selection
3. Configuration status
4. Connection test or diagnostics
5. Credential/configuration details
6. Advanced provider options

Existing provider switcher and provider-status fragments should be composed
inside this workspace rather than defining separate page conventions.

### `ModuleSettings::CredentialPanelComponent`

Provides a consistent show/edit treatment for Email, SMS, Captcha, and Speech
to Text provider credentials and settings. Secret-preserving behavior remains
unchanged.

### `ModuleSettings::FormActionsComponent`

Provides consistent Cancel and Save placement. Long forms may use a responsive
sticky action bar, provided it does not cover content and remains accessible.

### `ModuleSettings::ResponsiveCollectionComponent`

Provides a desktop table and a mobile summary-card/disclosure treatment for
templates, webhook events, models, tokens, or similar collections.

### `ModuleSettings::EmptySectionComponent`

Provides a consistent section-level empty state with an optional primary
action.

## Page archetypes

### Module catalog

The catalog remains searchable and filterable. Each module entry shows:

- Name and concise description
- Active, inactive, required, or mandatory state
- Configuration-health indicator
- Provider or assignment summary where relevant
- Warning or incomplete-setup indicator
- Clear Configure action

The empty-catalog and no-filter-match states must explain why no results are
shown. Search and filtering remain client-side Stimulus behavior with all
wording supplied by the server through translated values.

### Module overview

The overview leads with the summary and the most important next action.
Availability and requirement controls are grouped together with explicit
platform-wide consequences and dependency explanations.

Module-specific configuration appears in focused section cards rather than a
single mixed collection of controls.

### Provider settings

Email, SMS, Captcha, and Speech to Text use one provider-workspace pattern.
The page separates assignment, health, credentials, and provider-specific
options. Connection testing is visible near provider health, not buried inside
unrelated form actions.

If more than three providers are available, mobile layouts use a select rather
than wrapping provider tabs.

### Resource index

SMS templates and Captcha surface/page controls use:

- A clear page title and primary action
- Search or filtering where useful
- Consistent status treatment
- Desktop table or structured list
- Mobile summary cards with disclosure
- Standard empty and no-match states

### Resource form

Create and edit forms use a narrow content column, grouped fieldsets,
descriptions for consequential settings, inline validation, and a consistent
Save/Cancel footer.

### Operations ledger

Payment webhook events use an operations-focused layout with:

- Summary or filter controls
- Responsive event collection
- Clear delivery/processing state
- Eligibility explanation for redrive
- Confirmation and feedback for redrive actions

Detailed event content may use disclosure, sheet, or drawer behavior if that
improves readability without changing the route or server behavior.

### Developer reference

Models, token exposure, schema details, and similar technical information move
under Developer. Accordions or grouped technical sections reduce initial
density while keeping all information available.

## Module mapping

### Authentication

- Overview: availability and requirement state
- Configuration: public customer signup
- Developer: models, tokens, handoff, and schema details where currently
  available

### Captcha

- Overview: availability, health, and provider summary
- Providers: provider configuration and connection testing
- Resources: protected/skipped surfaces and shared pages
- Developer: common technical module information

### Email

- Overview: availability, health, assignment, and provider summary
- Providers: delivery assignment and credentials
- Developer: handoff and common technical module information

### Payments

- Overview: availability and gateway-health summary
- Providers: platform gateway availability
- Operations: webhook event ledger and redrive
- Developer: common technical module information

### SMS

- Overview: availability, health, assignment, and provider summary
- Providers: delivery assignment and credentials
- Resources: templates
- Developer: handoff and common technical module information

### Speech to Text

- Overview: availability, health, and provider summary
- Providers: provider configuration and connection testing
- Developer: handoff and common technical module information

## Responsive behavior

### Desktop

- General workspace is constrained to a readable width.
- Forms use a narrower column than technical tables.
- Optional section navigation may use a
  `lg:grid-cols-[14rem_minmax(0,1fr)]` layout where it materially improves
  long pages.
- Primary actions remain in predictable header or footer locations.

### Tablet

- Multi-column setting rows reduce to simpler two-column or stacked layouts.
- Navigation remains visible without crowding the page header.
- Tables retain only columns essential to the task.

### Mobile

- Module navigation becomes horizontally scrollable or a compact selector.
- Setting rows stack label, description, control, and state.
- Appropriate actions become full-width.
- Routine collections become summary cards with accessible disclosure instead
  of requiring horizontal scrolling.
- Long forms may use a bottom sticky Save/Cancel bar with safe-area and content
  clearance.
- Long identifiers and translated text wrap without breaking page geometry.

## Interaction behavior

Stimulus is limited to behavior that improves the server-rendered experience:

- Catalog and resource search/filtering
- Responsive disclosure
- Provider-field switching
- Connection-test feedback
- Dirty-form protection where justified

JavaScript must not introduce literal user-facing wording. Translated strings
are supplied by Stimulus values with English defaults as required by project
conventions.

Any JavaScript change requires matching Vitest coverage with 100% lines and
branches. Browser-only interaction or geometry may use Playwright only under
the documented exclusion rules.

## Accessibility

- Navigation exposes the active section programmatically.
- Status never relies on color alone.
- Form labels, descriptions, errors, and disabled explanations are associated
  with their controls.
- Keyboard focus is visible and follows a logical order.
- Touch targets remain usable on mobile.
- Dialogs, drawers, and disclosures have accessible names and focus behavior.
- Tables and mobile collection alternatives preserve equivalent information
  and actions.
- Confirmation remains in place for destructive or broad-impact operations.

## Localization

Every new or changed visible string must use I18n:

- Headings and descriptions
- Navigation labels
- Buttons and links
- Status and health wording
- Placeholders and search labels
- Form labels and help text
- Empty states
- Alerts, confirmations, validation, success, and failure messages
- Tooltips and accessibility labels

English and Simplified Chinese locale files must have matching key sets and
interpolation variables. Existing English wording remains byte-identical when
specifications depend on it. Simplified Chinese must be idiomatic,
professional, and use canonical terminology.

## Error and edge states

The implementation must account for:

- No registered modules
- No registered providers
- Search or filters with no matches
- Mandatory modules with locked controls
- Inactive modules that cannot become required or act as handoff targets
- Incomplete credentials
- Blank secret fields preserving stored values during edit
- Provider connection timeout or invalid response
- Validation failure retaining safe non-secret input
- Empty or high-volume templates, surfaces, pages, and webhook events
- Ineligible or concurrently changed webhook redrive targets
- Concurrently changed settings or resources
- Partial customer provisioning failure
- Long names, descriptions, identifiers, translations, and error messages

## Testing strategy

Implementation follows TDD and uses scoped tests appropriate to the breadth of
the change.

Required coverage includes:

- ViewComponent specs for shared shell, summary, section, setting-row,
  provider, form-action, responsive-collection, and empty-state behavior
- Existing module-specific component specs updated for the shared workspace
- Request/controller specs confirming routes, mutation behavior,
  authorization, and platform-owner restrictions remain unchanged
- I18n parity checks for all added keys and interpolation variables
- Responsive browser coverage for catalog, module overview, provider settings,
  resource forms/lists, and webhook operations
- Keyboard and active-navigation behavior
- Targeted JavaScript unit coverage at 100% lines and branches whenever
  JavaScript changes
- Multi-tenant and role-isolation regression coverage

Because this is a cross-cutting UI refactor spanning every module-settings
surface, final verification should run the full RSpec suite in parallel when
the environment supports it, plus JavaScript coverage and relevant Playwright
tests.

## Verification and release

Before completion:

1. Run affected component, request, controller, JavaScript, and E2E specs
   during implementation.
2. Run the full parallel RSpec suite because the final change is cross-cutting.
3. Run `npx vitest run --coverage` if JavaScript changes.
4. Rebuild Tailwind assets.
5. Remove `public/assets/.manifest.json` before restarting development.
6. If digested assets shadow source files, run `assets:clobber`, then rebuild
   Tailwind.
7. Restart with `SKIP_AUTH=1`.
8. Smoke-test every module and nested page at desktop, tablet, and mobile
   widths.
9. Compare the implemented surfaces for consistent layout, styling,
   navigation, actions, status, empty states, and responsive behavior.

## Out of scope

- Adding, removing, or renaming modules
- Adding providers or gateways
- Changing provider registries or discovery
- Database schema changes
- Credential storage, encryption, or secret-handling changes
- Route path changes
- Authorization or tenant-policy changes
- Provisioning, delivery, webhook-processing, throttling, or handoff behavior
- Customer-specific settings
- Unrelated Maintenance or administration pages

## Success criteria

The redesign is complete when the platform owner can move between all six
modules and their nested pages without relearning layout or action placement;
routine settings are clearly separated from resources, operations, and
developer details; every surface is fully responsive and localized; and all
existing functional, authorization, persistence, and tenant behavior remains
intact.
