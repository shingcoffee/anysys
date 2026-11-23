# Design Spec: Remove Email Assets Feature

This document specifies the deprecation and complete removal of the Email Assets feature from the Email module of the platform. Since users can upload images directly into the Lexxy template editor, a separate asset library is redundant and removing it simplifies the system and increases maintainability.

## 1. Objectives

- Safely and completely remove all routes, models, views, controllers, components, and assets associated with Email Assets.
- Clean up unused localization keys in English (`en`) and Simplified Chinese (`zh-CN`).
- Update the sidebar contributions to remove references to assets.
- Remove all related test suites to keep the CI green and maintain 100% test coverage.

## 2. Affected Files

### To Be Removed (Deleted)
- `app/controllers/admin/modules/emails/assets_controller.rb`
- `app/models/emails/asset.rb`
- `app/views/admin/modules/emails/assets/index.html.erb`
- `app/views/admin/modules/emails/assets/new.html.erb`
- `app/views/admin/modules/emails/assets/edit.html.erb`
- `app/views/admin/modules/emails/assets/_form.html.erb`
- `app/components/emails/asset_picker_component.rb`
- `app/components/emails/asset_picker_component.html.erb`
- `app/javascript/controllers/asset_picker_controller.js`
- `spec/models/emails/asset_spec.rb`
- `spec/requests/admin/modules/emails/assets_spec.rb`
- `spec/components/emails/asset_picker_component_spec.rb`
- `spec/factories/email_assets.rb`
- `spec/javascript/controllers/asset_picker_controller.test.js`

### To Be Modified
- `config/routes.rb`: Remove `resources :assets` route inside the `emails` namespace.
- `app/services/feature_modules/email/registration.rb`: Remove `assets` tab and update sidebar contributions.
- `app/views/admin/modules/emails/shared/_content_tabs.html.erb`: Remove assets tab.
- `app/views/admin/modules/emails/templates/_form.html.erb`: Remove `Emails::AssetPickerComponent` rendering.
- `config/locales/admin_modules.en.yml` / `config/locales/admin_modules.zh-CN.yml`: Delete `assets` localization keys.
- `config/locales/feature_modules.en.yml` / `config/locales/feature_modules.zh-CN.yml`: Delete `assets` tab localization keys.

## 3. Database Schema
We will create a migration to drop the `email_assets` table to ensure clean schema state.

## 4. Verification Plan
- Run targeted RSpec tests:
  - `bundle exec rspec spec/services/feature_modules/email/registration_spec.rb`
  - `bundle exec rspec spec/services/module_contribution_spec.rb`
- Run vitest suite to verify 100% JS line/branch coverage:
  - `npx vitest run --coverage`
