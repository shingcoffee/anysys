# Remove Extendable, Step Actions, and Base Model Auto-Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the entity base model extension system, feature module step actions, base model auto-discovery (FeatureModuleOwned/BaseModelConfiguration), and the Payment model entirely.

**Architecture:** Bottom-up removal — delete core files first, then clean up all references in dependent files (models, services, controllers, views, JS, specs). The feature module system remains (FeatureModule, CustomerFeatureModule, Registration/Provisioner/Deprovisioner, configuration schema) but without step actions, base model settings, or extendable toggles.

**Tech Stack:** Ruby on Rails 8.1.2, StimulusJS, ViewComponent, RSpec

---

## File Map

### Files to DELETE entirely

**Models & Concerns:**
- `app/models/concerns/extendable.rb`
- `app/models/concerns/feature_module_owned.rb`
- `app/models/extended_model_entry.rb`
- `app/models/base_model_configuration.rb`
- `app/models/payment.rb`

**Services:**
- `app/services/extendable_models_service.rb`
- `app/services/extended_model_service.rb`
- `app/services/feature_module_step_resolver.rb`
- `app/services/step_action_registry.rb`

**Payment Module (entire directory):**
- `app/services/feature_modules/payment/` (all files: registration.rb, provisioner.rb, deprovisioner.rb, steps/*.rb)

**Authentication Step Classes:**
- `app/services/feature_modules/authentication/steps/authenticate_user.rb`
- `app/services/feature_modules/authentication/steps/require_mfa.rb`
- `app/services/feature_modules/authentication/steps/check_session.rb`

**Views:**
- `app/views/entities/base_models.html.erb`
- `app/views/entities/base_model_definition.html.erb`
- `app/views/entities/edit_base_model.html.erb`
- `app/views/entities/_base_model_field_modal.html.erb`

**JavaScript:**
- `app/javascript/controllers/feature_module_settings_controller.js`
- `app/javascript/controllers/base_model_config_controller.js`
- `app/javascript/controllers/base_model_config/options_manager.js`
- `app/javascript/controllers/base_model_config/validator_manager.js`

**Specs:**
- `spec/models/concerns/feature_module_owned_spec.rb`
- `spec/models/base_model_configuration_spec.rb`
- `spec/models/payment_spec.rb`
- `spec/services/extendable_models_service_spec.rb`
- `spec/services/feature_module_step_resolver_spec.rb`
- `spec/services/step_action_registry_spec.rb`
- `spec/services/feature_modules/payment/` (all specs)
- `spec/factories/payments.rb`
- `spec/factories/base_model_configurations.rb`

**Docs:**
- `docs/ENTITY_EXTENSIBILITY_FEATURE.md`
- `docs/EXTENSIBILITY_EXAMPLES.md`
- `docs/GENERIC_MODEL_EXTENSIBILITY.md`

**Compiled Assets (will be regenerated):**
- `public/assets/controllers/base_model_config_controller-*.js`
- `public/assets/controllers/feature_module_settings_controller-*.js`

### Files to MODIFY

**Models:**
- `app/models/entity.rb` — Remove `extendable_models` json_attribute, `extension?`, `standalone?`, `extendable_models_list`, `base_model_classes`, `base_model_class`, `reserved_field_names`, `reserved_field_name?`, `as_palette_item` extendable_models ref, `extensions_for` scope, `standalone` scope
- `app/models/concerns/entity_schema_validation.rb` — Remove `validate_extendable_models` and `validate_no_reserved_field_names` validations
- `app/models/user.rb` — Remove `include FeatureModuleOwned` and `base_model_of` declaration
- `app/models/feature_module.rb` — Remove `json_attribute :step_actions`, `json_attribute :base_model_settings`, `SYSTEM_FIELDS`, all base_model_* methods, all extendable methods, class methods `owning_module`, `model_extendable?`, `all_extendable_model_names`

**Services:**
- `app/services/feature_modules/base_module.rb` — Remove `step_actions`, `base_model_names`, `base_models_metadata`, step registration in `register!`, `build_default_base_model_settings`, `ensure_base_model_configurations!`, base_model_settings from update!
- `app/services/feature_modules/authentication/registration.rb` — Remove `step_actions` method
- `app/services/activity_generator.rb` — Remove `FeatureModuleStepResolver` fallback in `generate_step_code` and `generate_feature_module_step` method
- `app/services/activity_steps/save_all.rb` — Remove `save_base_model_extensions` method and its call
- `app/services/activity_steps/detect_and_route_params.rb` — Remove `extract_base_models` method, simplify `route_multi_source`
- `app/services/entity_field_organizer.rb` — Remove `extract_base_model_fields` and `extract_base_model_fields_for_model` methods, simplify `call`
- `app/services/form_params_router.rb` — Remove `extract_base_models` method, simplify `build_primary`

**Controllers:**
- `app/controllers/entities_controller.rb` — Remove `base_models`, `edit_base_model`, `update_base_model`, `base_model_fields`, `base_model_definition` actions; remove `@extendable_models` from new/edit/copy/create/update; remove `extendable_models` from `entity_params`
- `app/controllers/feature_modules_controller.rb` — Remove `update_base_model_settings`, `available_step_actions` actions; remove from `before_action`

**Views:**
- `app/views/entities/_form.html.erb` — Remove "Extends Base Models" section (lines 60-92), remove `reserved_field_names` and `extendable_models` from data attributes
- `app/views/entities/show.html.erb` — Remove "Extends Base Models" section
- `app/views/feature_modules/show.html.erb` — Remove Step Actions card from overview, remove Base Models card from overview, remove entire Module Settings tab content (base_model_settings form + extendable toggles + field table), remove Module Settings tab button
- `app/components/entity_list_table_component.html.erb` — Remove "Extends" column
- `app/components/feature_module_card_component.rb` — Remove `step_actions` method
- `app/components/feature_module_card_component.html.erb` — Remove step actions badges section

**Routes:**
- `config/routes.rb` — Remove `base_model_fields`, `base_model_definition`, `base_models`, `edit_base_model`, `update_base_model` entity routes; remove `base_model_settings`/`update_base_model_settings` and `available_step_actions` feature_module routes

**Initializers:**
- `config/initializers/feature_modules.rb` — Remove Payment registration line

**Specs (modify, not delete):**
- `spec/requests/feature_modules_spec.rb` — Remove tests for base_model_settings, step_actions, available_step_actions
- `spec/controllers/entities_controller_spec.rb` — Remove tests for base_model actions
- `spec/services/feature_modules/authentication/registration_spec.rb` — Remove step_actions tests
- `spec/services/activity_steps/save_all_spec.rb` — Remove base model extension tests
- `spec/services/activity_steps/detect_and_route_params_spec.rb` — Remove base model extraction tests
- `spec/services/form_params_router_spec.rb` — Remove base model tests
- `spec/models/feature_module_spec.rb` — Remove base_model_settings/extendable tests
- `spec/components/feature_module_card_component_spec.rb` — Remove step_actions tests

---

## Task 1: Delete Payment module and its specs

**Files:**
- Delete: `app/models/payment.rb`
- Delete: `app/services/feature_modules/payment/registration.rb`
- Delete: `app/services/feature_modules/payment/provisioner.rb`
- Delete: `app/services/feature_modules/payment/deprovisioner.rb`
- Delete: `app/services/feature_modules/payment/steps/collect_payment.rb`
- Delete: `app/services/feature_modules/payment/steps/verify_payment.rb`
- Delete: `app/services/feature_modules/payment/steps/refund_payment.rb`
- Delete: `spec/models/payment_spec.rb`
- Delete: `spec/factories/payments.rb`
- Delete: `spec/services/feature_modules/payment/registration_spec.rb`
- Delete: `spec/services/feature_modules/payment/provisioner_spec.rb`
- Delete: `spec/services/feature_modules/payment/deprovisioner_spec.rb`
- Delete: `spec/services/feature_modules/payment/steps/collect_payment_spec.rb`
- Delete: `spec/services/feature_modules/payment/steps/verify_payment_spec.rb`
- Delete: `spec/services/feature_modules/payment/steps/refund_payment_spec.rb`
- Modify: `config/initializers/feature_modules.rb` — Remove `FeatureModules::Payment::Registration.register!` line

- [ ] **Step 1:** Delete payment model: `rm app/models/payment.rb`
- [ ] **Step 2:** Delete payment services directory: `rm -rf app/services/feature_modules/payment/`
- [ ] **Step 3:** Delete payment specs: `rm spec/models/payment_spec.rb spec/factories/payments.rb && rm -rf spec/services/feature_modules/payment/`
- [ ] **Step 4:** Edit `config/initializers/feature_modules.rb` — Remove the line `FeatureModules::Payment::Registration.register!`

---

## Task 2: Delete authentication step classes

**Files:**
- Delete: `app/services/feature_modules/authentication/steps/authenticate_user.rb`
- Delete: `app/services/feature_modules/authentication/steps/require_mfa.rb`
- Delete: `app/services/feature_modules/authentication/steps/check_session.rb`

- [ ] **Step 1:** Delete authentication steps directory: `rm -rf app/services/feature_modules/authentication/steps/`

---

## Task 3: Delete core extensibility files

**Files:**
- Delete: `app/models/concerns/extendable.rb`
- Delete: `app/models/concerns/feature_module_owned.rb`
- Delete: `app/models/extended_model_entry.rb`
- Delete: `app/models/base_model_configuration.rb`
- Delete: `app/services/extendable_models_service.rb`
- Delete: `app/services/extended_model_service.rb`
- Delete: `app/services/feature_module_step_resolver.rb`
- Delete: `app/services/step_action_registry.rb`
- Delete: `spec/models/concerns/feature_module_owned_spec.rb`
- Delete: `spec/models/base_model_configuration_spec.rb`
- Delete: `spec/services/extendable_models_service_spec.rb`
- Delete: `spec/services/feature_module_step_resolver_spec.rb`
- Delete: `spec/services/step_action_registry_spec.rb`
- Delete: `spec/factories/base_model_configurations.rb`

- [ ] **Step 1:** Delete model concerns: `rm app/models/concerns/extendable.rb app/models/concerns/feature_module_owned.rb`
- [ ] **Step 2:** Delete models: `rm app/models/extended_model_entry.rb app/models/base_model_configuration.rb`
- [ ] **Step 3:** Delete services: `rm app/services/extendable_models_service.rb app/services/extended_model_service.rb app/services/feature_module_step_resolver.rb app/services/step_action_registry.rb`
- [ ] **Step 4:** Delete specs: `rm spec/models/concerns/feature_module_owned_spec.rb spec/models/base_model_configuration_spec.rb spec/services/extendable_models_service_spec.rb spec/services/feature_module_step_resolver_spec.rb spec/services/step_action_registry_spec.rb spec/factories/base_model_configurations.rb`

---

## Task 4: Delete views and JS controllers

**Files:**
- Delete: `app/views/entities/base_models.html.erb`
- Delete: `app/views/entities/base_model_definition.html.erb`
- Delete: `app/views/entities/edit_base_model.html.erb`
- Delete: `app/views/entities/_base_model_field_modal.html.erb`
- Delete: `app/javascript/controllers/feature_module_settings_controller.js`
- Delete: `app/javascript/controllers/base_model_config_controller.js`
- Delete: `app/javascript/controllers/base_model_config/options_manager.js`
- Delete: `app/javascript/controllers/base_model_config/validator_manager.js`
- Delete: `docs/ENTITY_EXTENSIBILITY_FEATURE.md`
- Delete: `docs/EXTENSIBILITY_EXAMPLES.md`
- Delete: `docs/GENERIC_MODEL_EXTENSIBILITY.md`

- [ ] **Step 1:** Delete entity base model views: `rm app/views/entities/base_models.html.erb app/views/entities/base_model_definition.html.erb app/views/entities/edit_base_model.html.erb app/views/entities/_base_model_field_modal.html.erb`
- [ ] **Step 2:** Delete JS controllers: `rm app/javascript/controllers/feature_module_settings_controller.js app/javascript/controllers/base_model_config_controller.js && rm -rf app/javascript/controllers/base_model_config/`
- [ ] **Step 3:** Delete docs: `rm -f docs/ENTITY_EXTENSIBILITY_FEATURE.md docs/EXTENSIBILITY_EXAMPLES.md docs/GENERIC_MODEL_EXTENSIBILITY.md`
- [ ] **Step 4:** Delete compiled assets: `rm -f public/assets/controllers/base_model_config_controller-*.js public/assets/controllers/feature_module_settings_controller-*.js`

---

## Task 5: Clean up Entity model and validation concern

**Files:**
- Modify: `app/models/entity.rb`
- Modify: `app/models/concerns/entity_schema_validation.rb`

- [ ] **Step 1:** Edit `app/models/entity.rb`:
  - Remove `json_attribute :extendable_models, default: []`
  - Remove `extensions_for` scope
  - Remove `standalone` scope
  - In `as_palette_item`, remove `, extendable_models: extendable_models_list`
  - Remove methods: `extension?`, `standalone?`, `extendable_models_list`, `base_model_classes`, `base_model_class`, `reserved_field_names`, `reserved_field_name?`

- [ ] **Step 2:** Edit `app/models/concerns/entity_schema_validation.rb`:
  - Remove `validate :validate_extendable_models` from `included` block
  - Remove `validate :validate_no_reserved_field_names` from `included` block
  - Remove `validate_extendable_models` method
  - Remove `validate_no_reserved_field_names` method

---

## Task 6: Clean up User model

**Files:**
- Modify: `app/models/user.rb`

- [ ] **Step 1:** Edit `app/models/user.rb`:
  - Remove `include FeatureModuleOwned`
  - Remove the entire `base_model_of "authentication", ...` declaration (lines 13-20)

---

## Task 7: Clean up FeatureModule model

**Files:**
- Modify: `app/models/feature_module.rb`

- [ ] **Step 1:** Edit `app/models/feature_module.rb`:
  - Remove `json_attribute :step_actions, default: []`
  - Remove `json_attribute :base_model_settings, default: {}`
  - Remove `SYSTEM_FIELDS` constant
  - Remove all methods from `# Base Model Settings` section through end of instance methods: `base_model_extendable?`, `base_model_description`, `field_extendability`, `field_extendable?`, `extendable_fields_for`, `base_model_names`
  - Remove all class methods: `owning_module`, `model_extendable?`, `all_extendable_model_names`

---

## Task 8: Clean up BaseModule and Authentication Registration

**Files:**
- Modify: `app/services/feature_modules/base_module.rb`
- Modify: `app/services/feature_modules/authentication/registration.rb`

- [ ] **Step 1:** Edit `app/services/feature_modules/base_module.rb`:
  - Remove `step_actions` method (the NotImplementedError one)
  - Remove `base_model_names` method
  - Remove `base_models_metadata` method
  - In `register!`: Remove `step_actions: step_actions.to_json` from update! call, remove `base_model_settings: build_default_base_model_settings.to_json` from update! call, remove the step_actions registration loop (lines 71-74), remove `ensure_base_model_configurations!` call
  - Remove private methods: `build_default_base_model_settings`, `ensure_base_model_configurations!`

- [ ] **Step 2:** Edit `app/services/feature_modules/authentication/registration.rb`:
  - Remove `def self.step_actions = %w[authenticate_user require_mfa check_session]`

---

## Task 9: Clean up ActivityGenerator

**Files:**
- Modify: `app/services/activity_generator.rb`

- [ ] **Step 1:** Edit `app/services/activity_generator.rb`:
  - In `generate_step_code` method (around line 376-383): Remove the line `generate_feature_module_step(action) if FeatureModuleStepResolver.registered?(action)` and the comment above it
  - Remove the entire `generate_feature_module_step` method (lines 387-393)

---

## Task 10: Clean up activity steps services

**Files:**
- Modify: `app/services/activity_steps/save_all.rb`
- Modify: `app/services/activity_steps/detect_and_route_params.rb`
- Modify: `app/services/entity_field_organizer.rb`
- Modify: `app/services/form_params_router.rb`

- [ ] **Step 1:** Edit `app/services/activity_steps/save_all.rb`:
  - In `save_primary`: Remove `save_base_model_extensions(ctx) if ctx[:bound_entity]&.extension?` line
  - Remove entire `save_base_model_extensions` method (lines 49-76)
  - Update comment at top of module to remove mention of ExtendedModelEntry / base model extensions

- [ ] **Step 2:** Edit `app/services/activity_steps/detect_and_route_params.rb`:
  - In `route_multi_source`: Change `base_models: extract_base_models(params["base"], bound_entity)` to `base_models: {}`
  - Remove `extract_base_models` method entirely
  - Update top-of-file comments to remove base model references

- [ ] **Step 3:** Edit `app/services/entity_field_organizer.rb`:
  - In `call`: Change `base_fields: extract_base_model_fields` to `base_fields: {}`
  - Remove `extract_base_model_fields` and `extract_base_model_fields_for_model` methods

- [ ] **Step 4:** Edit `app/services/form_params_router.rb`:
  - In `build_primary`: Change `base_models: extract_base_models(raw_params["base"] || {})` to `base_models: {}`
  - Remove `extract_base_models` method
  - Update comment to remove base model references

---

## Task 11: Clean up EntitiesController

**Files:**
- Modify: `app/controllers/entities_controller.rb`

- [ ] **Step 1:** Edit `app/controllers/entities_controller.rb`:
  - Remove `before_action :require_owner_role!, only: %i[base_models edit_base_model update_base_model]`
  - Remove entire `base_models` action (lines 23-25)
  - Remove entire `edit_base_model` action (lines 28-37)
  - Remove entire `update_base_model` action (lines 40-76)
  - Remove entire `base_model_fields` action (lines 93-110)
  - Remove entire `base_model_definition` action (lines 113-145)
  - In `new` action: Remove `@extendable_models = ExtendableModelsService.model_options`
  - In `copy` action: Remove `extendable_models: source_entity.extendable_models,` from Entity.new call; remove `@extendable_models = ExtendableModelsService.model_options`
  - In `edit` action: Remove `@extendable_models = ExtendableModelsService.model_options`
  - In `create` action (error path): Remove `@extendable_models = ExtendableModelsService.model_options`
  - In `update` action (error path): Remove `@extendable_models = ExtendableModelsService.model_options`
  - In `entity_params`: Remove `extendable_models: []` from permit list; remove the entire `if permitted[:extendable_models]...` serialization block

---

## Task 12: Clean up FeatureModulesController

**Files:**
- Modify: `app/controllers/feature_modules_controller.rb`

- [ ] **Step 1:** Edit `app/controllers/feature_modules_controller.rb`:
  - In `before_action` for `find_feature_module` (line 12): Remove `:update_base_model_settings` from the only list
  - Remove `before_action :require_owner_role!, only: [:update_base_model_settings, :toggle_required]` — change to `before_action :require_owner_role!, only: [:toggle_required]`
  - Remove entire `update_base_model_settings` action (lines 95-123)
  - Remove entire `available_step_actions` action (lines 150-152)

---

## Task 13: Clean up routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1:** Edit `config/routes.rb`:
  - In entities collection routes: Remove `get :base_model_fields`, remove `get 'base_model/:model_name'...` route, remove `get :base_models`, remove `get 'base_models/:model_name/edit'...` route, remove `patch 'base_models/:model_name'...` route
  - In feature_modules member routes: Remove `patch :base_model_settings, action: :update_base_model_settings`
  - In feature_modules collection routes: Remove `get :available_step_actions`

---

## Task 14: Clean up entity views

**Files:**
- Modify: `app/views/entities/_form.html.erb`
- Modify: `app/views/entities/show.html.erb`

- [ ] **Step 1:** Edit `app/views/entities/_form.html.erb`:
  - Remove `entity_form_reserved_field_names_value: @entity.reserved_field_names.to_json` from data attributes (line 9)
  - Remove `entity_form_extendable_models_value: @entity.extendable_models_list.to_json` from data attributes (line 10)
  - Remove the entire "Extends Base Models" section (lines 60-92 — the `<div>` containing the `entity_extendable_models` select and its helper text)

- [ ] **Step 2:** Edit `app/views/entities/show.html.erb`:
  - Remove the "Extends Base Models" section (the block starting with `<p class="text-sm font-medium text-gray-500">Extends Base Models</p>` through its closing `</div>` — approximately lines 89-112)

---

## Task 15: Clean up feature module views and components

**Files:**
- Modify: `app/views/feature_modules/show.html.erb`
- Modify: `app/components/feature_module_card_component.rb`
- Modify: `app/components/feature_module_card_component.html.erb`
- Modify: `app/components/entity_list_table_component.html.erb`

- [ ] **Step 1:** Edit `app/views/feature_modules/show.html.erb`:
  - Remove the "Step Actions Card" from overview tab (lines 113-139 — the entire `<div>` with `<h3>Step Actions</h3>`)
  - Remove the "Base Models Card" from overview tab (lines 205-244 — the entire `<div>` with `<h3>Base Models</h3>`)
  - Remove the "Module Settings" tab button from tab navigation (lines 81-93)
  - Remove the entire TAB 2: MODULE SETTINGS panel (lines 248-426 — the `<% if owner? %>...<% end %>` block containing the module-settings panel)

- [ ] **Step 2:** Edit `app/components/feature_module_card_component.rb`:
  - Remove `step_actions` method

- [ ] **Step 3:** Edit `app/components/feature_module_card_component.html.erb`:
  - Remove step actions badges section (lines 22-33 — the `<% if step_actions.any? %>` block)

- [ ] **Step 4:** Edit `app/components/entity_list_table_component.html.erb`:
  - Remove the "Extends" column header (line 6)
  - Remove the "Extends" column cell (lines 33-48 — the `<td>` containing `entity.extension?` check)

---

## Task 16: Clean up specs

**Files:**
- Modify: `spec/requests/feature_modules_spec.rb`
- Modify: `spec/controllers/entities_controller_spec.rb`
- Modify: `spec/services/feature_modules/authentication/registration_spec.rb`
- Modify: `spec/services/activity_steps/save_all_spec.rb`
- Modify: `spec/services/activity_steps/detect_and_route_params_spec.rb`
- Modify: `spec/services/form_params_router_spec.rb`
- Modify: `spec/models/feature_module_spec.rb`
- Modify: `spec/components/feature_module_card_component_spec.rb`
- Modify: Various other spec files referencing removed features

- [ ] **Step 1:** Read each spec file and remove tests that reference removed features (base_model_settings, step_actions, extendable, ExtendableModelsService, FeatureModuleStepResolver, StepActionRegistry, BaseModelConfiguration, Payment, ExtendedModelEntry, available_step_actions, update_base_model_settings, base_models routes). Keep all tests for remaining functionality.
- [ ] **Step 2:** Run `bundle exec rspec` to verify all remaining tests pass
- [ ] **Step 3:** Fix any test failures caused by the removal

---

## Task 17: Create database migration to clean up removed columns/tables

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_remove_extensibility_and_step_actions.rb`

- [ ] **Step 1:** Generate a migration to:
  - Drop `payments` table
  - Drop `extended_model_entries` table
  - Drop `base_model_configurations` table
  - Remove `extendable_models` column from `entities` table
  - Remove `step_actions` column from `feature_modules` table
  - Remove `base_model_settings` column from `feature_modules` table

```ruby
class RemoveExtensibilityAndStepActions < ActiveRecord::Migration[8.1]
  def up
    drop_table :payments if table_exists?(:payments)
    drop_table :extended_model_entries if table_exists?(:extended_model_entries)
    drop_table :base_model_configurations if table_exists?(:base_model_configurations)
    remove_column :entities, :extendable_models if column_exists?(:entities, :extendable_models)
    remove_column :feature_modules, :step_actions if column_exists?(:feature_modules, :step_actions)
    remove_column :feature_modules, :base_model_settings if column_exists?(:feature_modules, :base_model_settings)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 2:** Run `bin/rails db:migrate` to apply the migration
- [ ] **Step 3:** Run `bundle exec rspec` to verify everything passes

---

## Task 18: Update AGENTS.md

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1:** Edit `AGENTS.md`:
  - Remove the "Feature Module Development" section and all its subsections (Model Auto-Discovery Convention, Registration Class, What `register!` Does Automatically, Step Classes, Checklist for Adding a New Feature Module)
  - Or significantly simplify it to reflect that feature modules now only have: Registration (metadata + config schema), Provisioner, Deprovisioner — no step actions, no base models, no BaseModelConfiguration

---

## Task 19: Final verification

- [ ] **Step 1:** Run `bundle exec rspec` — all tests should pass
- [ ] **Step 2:** Run `bin/rails assets:precompile` to rebuild assets (or verify the app boots)
- [ ] **Step 3:** Grep for any remaining references: `grep -r "Extendable\|ExtendedModelEntry\|FeatureModuleOwned\|BaseModelConfiguration\|ExtendableModelsService\|FeatureModuleStepResolver\|StepActionRegistry\|step_actions\|base_model_of\|base_model_settings\|extendable_models\|Payment" app/ spec/ config/ --include="*.rb" --include="*.erb" --include="*.js" -l` — should return no results (except possibly migration files which are fine to keep)
- [ ] **Step 4:** Fix any remaining references found
