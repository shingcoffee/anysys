# Module Settings Page Refactor — Platform Owner

Date: 2026-06-29
Page: `/:cid/admin/maintenance/platform/module_settings/:id` (platform-owner only, customer `81721200`)
Controller: `Admin::Maintenance::Platform::ModuleSettingsController#show/#update`
View: `app/views/admin/maintenance/platform/module_settings/show.html.erb`

## Goal

For each feature module on the platform-owner module settings page, refactor two things:

- **(a) Exposed platform settings** — evaluate and expose the platform-wide settings the
  owner can actually change for each module.
- **(b) Per-model "Extendable" toggle** — list every Model belonging to the module, each
  with a toggle controlling whether that model may be *extended* (used as a base model in
  the Entity Builder). **Default: not allowed (off).**

## Critical background (verified against current code)

An earlier, broader "extendability" feature existed and was **deliberately removed** by
migration `20260322090215_remove_extensibility_and_step_actions`:

- dropped tables `base_model_configurations`, `extended_model_entries`
- dropped columns `entities.extendable_models`, `feature_modules.base_model_settings`,
  `feature_modules.step_actions`

What survives today is **dead leftover wiring** on the front end only:

- `entity_form_controller.js` declares a `extendableModels` Stimulus value and an
  `extendableModelChanged` handler that `fetch`es
  `/:cid/admin/maintenance/entities/base_model_fields?model=…` — **no route, no controller
  action, and no `<select>` in the form feeds it.**
- `entity_form/attribute_manager.js` reads `extendableModelValue` / `reservedFieldNamesValue`
  to block reserved field-name collisions.
- `FormParamsRouter`, `ActivitySteps::PopulatePrimary`, `EntityFieldOrganizer`,
  `PageFieldPopulator` all still carry a `base_models: {}` / `base_fields: {}` channel that is
  always empty.

Therefore part (b) is **re-introducing a narrower, owner-governed version** of the removed
feature, NOT reusing surviving infrastructure. Persistence must be rebuilt.

## Part (b): Per-model "Extendable" toggle

### Persistence

Reuse the existing `feature_modules.configuration_schema` precedent (JSON text column managed
by `JsonSerializable`). Add a **new JSON text column** `extendable_models` on `feature_modules`
storing the set of extendable model class names for that module:

```json
["Authentication::User", "Payments::Order"]
```

Migration: `add_extendable_models_to_feature_modules` → `add_column :feature_modules,
:extendable_models, :text`.

On `FeatureModules::Module`:

```ruby
json_attribute :extendable_models, default: []

def extendable_model?(class_name) = extendable_models_json.include?(class_name.to_s)

def set_extendable_model!(class_name, on)
  set = Array(extendable_models_json)
  on ? set |= [class_name.to_s] : set -= [class_name.to_s]
  update!(extendable_models: set.to_json)
end
```

A model is extendable **only when its class name is present in the array**. Empty array (the
default for every module) ⇒ nothing extendable ⇒ matches "default not allowed".

### UI — Models card

Add an **"Extendable"** column to the existing Models table in `show.html.erb`. Each row gets a
`ModuleToggleComponent` (already used for Status/Required/Payment tenders) that PATCHes the
module-settings `update` action with `extendable_model=<ClassName>` and the on/off value.

### Controller — update action

Extend `ModuleSettingsController#update` to handle the new param, alongside the existing
`status_active` / `required` branches:

```ruby
apply_extendable_model! if params.key?(:extendable_model)
```

```ruby
def apply_extendable_model!
  class_name = params[:extendable_model]
  return unless ModuleModelDiscovery.call(@feature_module.key).any? { |m| m[:name] == class_name }
  @feature_module.set_extendable_model!(class_name, params[:extendable] == "1")
end
```

The discovery guard prevents writing arbitrary class names into the JSON blob.

### Wiring into the Entity Builder (completing the dead JS)

1. **Registry service** `ExtendableModelRegistry.for_customer(customer_id)` — across all modules
   **enabled for that customer**, collect each model the owner flagged extendable. Returns
   `[{ class_name:, label:, module_key: }, …]`. Uses `FeatureModules::Module.enabled_for_customer`
   + `extendable_models_json`.

2. **Route + action** `GET /:cid/admin/maintenance/entities/base_model_fields` (collection route
   on `maintenance/entities`). Returns `{ fields: [<column names>] }` for the requested model —
   **but only if that model is currently extendable for the customer** (authorization: never leak
   columns of a non-extendable model). Reuses `ModuleModelDiscovery`-style column extraction.

3. **Form select** — add an "Extend base model(s)" multi-select to
   `app/views/admin/maintenance/entities/_form.html.erb`, options sourced from
   `ExtendableModelRegistry`. Wire `entity_form_customer_id_value` (already present) and the
   existing `extendableModelChanged` action. When the registry is empty, the section renders a
   muted "No base models are available to extend" note instead of an empty select.

4. **Persist the entity's choice** — store selected base-model class names on the entity so the
   builder remembers them. Add `extendable_models` JSON to `Entity` (re-add the column dropped in
   the removal migration) and surface it through `EntityFieldOrganizer#base_fields` so base-model
   fields appear in `PageFieldPopulator` (the `base_models: {}` channel finally carries data).

   **Conservative boundary:** the full runtime "save entity-entry values back onto a real base
   model row" path was part of the removed feature and is out of scope here. This spec wires the
   *builder selection + reserved-field-collision + page-field surfacing*, which is the
   user-visible "model can be extended" behavior, and leaves the persisted base_models param map
   populated for the existing activity steps to consume. If deeper runtime persistence proves to
   need the dropped `extended_model_entries` table, that is flagged as follow-up rather than
   guessed at.

## Part (a): Exposed platform settings, per module

Evaluation of what each module should expose to the platform owner. Existing module-specific
sections (SMS credentials/templates, Payment tenders, Captcha link) stay. New exposures:

| Module | Already exposed | Add / expose |
|---|---|---|
| **Authentication** (mandatory) | Status/Required locked | Surface its `configuration_schema` (mfa_enabled, session_timeout, max_login_attempts) as the **platform default** for these toggles. Read-only display today; expose as editable platform defaults. |
| **Captcha** | Settings link | Keep link (provider credentials are platform-wide already). |
| **Email** | — | Credentials link already routed (`platform/emails/credentials`); add the link card (parallel to SMS). |
| **Email Campaigns** | — | No platform-wide config identified beyond enable/disable. Leave as Status/Required + Models. |
| **Payments** | Available Tenders | Keep. |
| **SMS** | Credentials + Templates | Keep. |

The concrete, safe, high-value additions are:

1. **Email** → add a Credentials link card (route already exists), mirroring SMS.
2. **Generic `configuration_schema` exposure** → the existing read-only "Configuration Schema"
   card becomes **editable platform defaults** for modules that declare a schema (Authentication
   today). Persisted on `feature_modules.configuration_schema` defaults via the `update` action
   with a `config_defaults[...]` param, whitelisted to the module's declared schema keys (mirrors
   `ModuleConfigsController` whitelisting). Modules without a schema are unaffected.

Anything not clearly correct (e.g. per-module bespoke platform settings beyond a declared schema)
is **left documented, not guessed** — per the conservative-under-uncertainty working style.

## Testing

- `FeatureModules::Module` spec — `extendable_model?`, `set_extendable_model!` add/remove/idempotent.
- `ModuleSettingsController` request spec — toggling `extendable_model` persists; non-owner blocked;
  arbitrary/unknown class name rejected; config_defaults whitelist enforced.
- `ExtendableModelRegistry` spec — only enabled modules' flagged models; tenant isolation.
- `base_model_fields` request spec — returns columns only for an extendable model; 404/empty for a
  non-extendable one; tenant isolation.
- Entity-form component/JS coverage limited to server-rendered select (JS monolith is effectively
  untested per project memory — do not blind-refactor it).

## Out of scope

- Reviving `extended_model_entries` runtime persistence (dropped feature).
- Reviving `step_actions`.
- Member-facing surfaces.
