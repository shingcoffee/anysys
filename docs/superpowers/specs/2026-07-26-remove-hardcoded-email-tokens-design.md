# Remove Hard-Coded Email Template Tokens Design Specification

## Goal
Remove hard-coded default model tokens (`email`, `first_name`, `last_name`, `full_name`, `customer.name`, `customer.id`) so that email template reference tokens derive dynamically from either:
1. Platform Module Settings (model attributes checked/toggled as template tokens in `email_template_tokens` with `source_type: 'platform_field'`).
2. Customer Entity Attribute Settings (custom entity attribute tokens in `email_template_tokens` with `source_type: 'entity_attribute'`).

`unsubscribe_url` remains as the sole built-in system token.

---

## Architecture & Components

### 1. `Emails::PlatformTokenSeeds` (`app/services/emails/platform_token_seeds.rb`)
- Reduce `ROWS` array to only:
  ```ruby
  ROWS = [
    { source_key: "unsubscribe_url", label: "unsubscribe_url" }
  ].freeze
  ```
- Update `self.ensure!`:
  - Ensure `unsubscribe_url` exists as a `platform_field` row.
  - Delete legacy hard-coded seed rows (`email`, `first_name`, `last_name`, `full_name`, `customer.name`, `customer.id`) where `source_type = 'platform_field'`.

### 2. `Emails::VariableContext` (`app/services/emails/variable_context.rb`)
- Update `to_h` hash to map model attribute structures for dynamic token resolution:
  ```ruby
  def to_h
    {
      "authentication_user" => @user.attributes,
      "customer"            => @user.customer&.attributes || {},
      "unsubscribe_url"     => unsubscribe_url
    }
  end
  ```
- When a model attribute is enabled in Platform Module Settings (e.g. `Authentication::User.email`), its `source_key` in `email_template_tokens` is `authentication_user.email`. `TokenCatalog.resolve_path("authentication_user.email", context_hash)` splits by `.` and resolves `@user.attributes["email"]` seamlessly.

### 3. Database Cleanup
- Running `db:seed` or `Emails::PlatformTokenSeeds.ensure!` cleans up legacy hard-coded `email_template_tokens` rows (`email`, `first_name`, `last_name`, `full_name`, `customer.name`, `customer.id`).

---

## Testing Strategy

- `spec/services/emails/platform_token_seeds_spec.rb`: Verify that only `unsubscribe_url` is seeded and legacy hard-coded model seeds are removed.
- `spec/services/emails/variable_context_spec.rb`: Verify that `VariableContext.for(user:)` exposes `authentication_user` and `customer` attribute hashes alongside `unsubscribe_url`.
- `spec/services/emails/token_catalog_spec.rb` and `spec/services/emails/template_renderer_spec.rb`: Verify that tokens enabled via Platform Module Settings (e.g. `authentication_user.email`) resolve properly during template compilation and rendering.
