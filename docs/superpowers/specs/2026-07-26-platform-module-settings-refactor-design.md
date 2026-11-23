# Platform Module Settings Refactor & Model Attribute Tokens Design

**Date:** 2026-07-26  
**Target Surface:** `/:cid/admin/maintenance/platform/module_settings/:id` (`Admin::Maintenance::Platform::ModuleSettingsController`)

## 1. Overview & Goals
Refactor the Platform Module Settings UI (`/81721200/admin/maintenance/platform/module_settings`) across all registered feature modules (User Authentication, Email, Payments, SMS, Captcha) to satisfy four key requirements:
1. **Right-aligned Toggles (Item a):** Prevent toggle switches and their adjacent text labels from wrapping across lines, ensuring toggles always align cleanly at the rightmost edge of their row.
2. **Remove Routes Section (Item b):** Remove the obsolete "Routes" card from the Technical Reference tab.
3. **Complete Model Discovery (Item c):** Upgrade `ModuleModelDiscovery` to discover all models for each module (fixing missing models for User Authentication, Email, and Payments).
4. **Model Attributes & Template Tokens (Item d):** Add a new section after the "Models" section in the Technical Reference tab listing all attributes of each model belonging to the module, with checkboxes to toggle availability as reference tokens persisted in the `email_template_tokens` table.

## 2. Technical Design

### A. Toggle Alignment (`ModuleToggleComponent` & Views)
- **Component Update:** Update `Admin::Maintenance::Platform::ModuleToggleComponent`'s root template (`app/components/admin/maintenance/platform/module_toggle_component.html.erb`) to wrap controls in `<div class="flex items-center justify-end gap-3 whitespace-nowrap flex-shrink-0 ml-auto">`.
- **View Rows Update:** Ensure parent flex containers in `app/views/admin/maintenance/platform/module_settings/show.html.erb` use `flex items-center justify-between gap-4 sm:flex-nowrap` so left text flex-grows while right toggles stay pinned to the right edge without wrapping.

### B. Routes Section Removal
- Remove `<%# Routes Card %>` block from `show.html.erb`.
- Controller `@module_routes` can remain or be cleaned up safely.

### C. Comprehensive Model Discovery (`ModuleModelDiscovery`)
Update `app/services/module_model_discovery.rb` to map module keys to their respective directories and associated top-level models:
- **`authentication`**: `Authentication::User`, `Authentication::Event`, `Authentication::TrustedDevice`, `Role`, `RolePermission`, `UsersRole`
- **`email`**: `Emails::Audience::List`, `Emails::Audience::ListMembership`, `Emails::Credential`, `Emails::Message`, `Emails::MessageEvent`, `Emails::SendActivities::SendActivity`, `Emails::SendActivities::SendActivityList`, `Emails::Suppression`, `Emails::Template`, `Emails::TemplateContent`, `Emails::TemplateToken`, `Emails::TemplateVersion`
- **`payment`**: `Payments::DefaultGateway`, `Payments::Dispute`, `Payments::MerchantAccount`, `Payments::Order`, `Payments::Payment`, `Payments::PaymentMethod`, `Payments::PlatformGateway`, `Payments::ReconciliationBill`, `Payments::Refund`, `Payments::Subscription`, `Payments::WebhookEvent`
- **`sms`**: `Sms::Credential`, `Sms::Message`, `Sms::OptOut`, `Sms::Template`
- **`captcha`**: `Captcha::ProviderSettings`, `Captcha::Verification`

### D. Model Attributes & Template Tokens Section
- **UI Section:** In `show.html.erb` under the Technical Reference tab (below the Models Card), render a new Card section titled "Model Attributes & Template Tokens" (`maint_platform.module_settings.show.tokens.title`).
- **Layout:** Grouped by model class name. Each model card/table displays:
  - **Attribute Name:** `column.name`
  - **Type:** `column.type` (styled via `BadgeComponent`)
  - **Template Token Toggle:** A `ModuleToggleComponent` or submit checkbox. Toggling submits `PATCH /:cid/admin/maintenance/platform/module_settings/:id` with `token_model`, `token_attribute`, and `token_enabled`.
- **Persistence (`Emails::TemplateToken`):**
  - Source Key format: `#{model_name.underscore.tr('/', '_')}.#{attribute_name}` (e.g. `authentication_user.email`).
  - When enabled: Find or create a platform `Emails::TemplateToken` (`customer_id: nil`, `source_type: 'platform_field'`, `source_key: source_key`, `label: "#{model_name.demodulize}.#{attribute_name}"`).
  - When disabled: Find and destroy the platform `Emails::TemplateToken` with matching `source_key`.
  - Token availability state is determined by `Emails::TemplateToken.platform.exists?(source_key: source_key)`.

## 3. Localization (I18n)
All new labels and headers added to `config/locales/maint_platform.en.yml` and `config/locales/maint_platform.zh-CN.yml`:
- `maint_platform.module_settings.show.tokens.title`: "Model Attributes & Template Tokens" / "模型属性与模板 Token"
- `maint_platform.module_settings.show.tokens.subtitle`: "Configure which model attributes are exposed as reference tokens for email and SMS templates" / "配置哪些模型属性可作为邮件和短信模板中的引用 Token"
- `maint_platform.module_settings.show.tokens.enabled`: "Available as Token" / "可用作 Token"
- `maint_platform.module_settings.show.tokens.disabled`: "Not Tokenized" / "不可用"

## 4. Verification & Testing
- RSpec unit tests for `ModuleModelDiscovery` covering complete model list per module key.
- RSpec request tests for `Admin::Maintenance::Platform::ModuleSettingsController` covering token attribute toggling and persistence in `email_template_tokens`.
- System/View verification for UI layout and right-aligned toggles across viewports.
