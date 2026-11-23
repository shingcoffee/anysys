---
title: "Industry templates"
summary: "Platform mappings from a customer industry to page-layout template keys, edited one industry at a time and seeded from category defaults."
---

## Summary

`IndustryTemplateMapping` stores `(industry, template_key)` with no `customer_id`. `Admin::Maintenance::Platform::IndustryTemplatesController` lists industries from `Customer::INDUSTRY_GROUPS` and replaces one industry's keys. Single-card add and remove are `IndustryTemplateAssignmentsController`. Card HTML is `IndustryTemplateCardsController`. Defaults come from `IndustryTemplateMappingSeeder`, through `IndustryTemplateDefaultSeedsController` and `IndustryTemplateNewTemplateSeedsController`.

`PageLayoutTemplates.for_industry` reads those rows when a page is chosen. The platform namespace is already limited to `platform_owner?`. The industry enum is loaded from `config/industries.yml` onto `Customer`; see [customers](customers). Applying a template on a page is [page builder](page-builder).

## Flow

```text
GET /:cid/admin/maintenance/platform/industry_templates
        |
        v
IndustryTemplatesController#index
  Customer::INDUSTRY_GROUPS
  IndustryTemplateMapping.group(:industry).count
        |
        +-- PATCH :id -> replace_for_industry!(industry, template_keys)
        +-- POST  :id/template_assignments -> one IndustryTemplateMapping
        +-- DELETE template_assignments/:template_key
        +-- GET template_cards -> template_cards partial, layout false
        |
        +-- POST   default_seed     -> seed_defaults!  (industries with zero rows)
        +-- DELETE default_seed     -> seed_all!       (delete_all, then defaults)
        +-- POST   new_template_seed -> seed_new_templates!
        |
        v
PageLayoutTemplates.for_industry(industry)
  keys present -> those templates
  keys empty   -> PageLayoutTemplates.all
```

## Implementation

`IndustryTemplateMapping` validates `industry` with `Customer.industries` and `template_key` with `PageLayoutTemplates.find`. The unique index is `(industry, template_key)`. `template_keys_for` plucks keys. `replace_for_industry!` `delete_all`s that industry inside a transaction, then `create!`s each remaining key. The update action keeps string and symbol entries in `params[:template_keys]` and drops blanks. `ActiveRecord::RecordInvalid` redirects to the edit page with `maint_platform.flash.industry_templates.invalid_template_keys`. `show` renders JSON `{ industry, template_keys }`. An id that is not an industry key is a JSON 404 or an HTML redirect.

`IndustryTemplateAssignmentsController#create` saves one row and returns `{ status: "added", template_key, count }` or 422 with `errors`. `#destroy` finds by `params[:id]` or `params[:template_key]` and returns `"removed"` or 404. `IndustryTemplateCardsController#show` assigns the full `PageLayoutTemplates` catalog and renders `admin/maintenance/platform/industry_templates/template_cards` with `layout: false`.

`IndustryTemplateMappingSeeder::UNIVERSAL_CATEGORIES` (`general`, `registration`, `contact`, `survey`, `feedback`, `scheduling`, `application`, `hr`) map to every industry. `CATEGORY_INDUSTRY_MAP` maps each other template category to a list of industry symbols. `seed_defaults!` inserts, via `insert_all`, only for industries that currently have no rows, and returns the size of that record list. `seed_all!` `delete_all`s every mapping, then runs the same insert for every `Customer.industries` key. The controller wires `seed_all!` to `IndustryTemplateDefaultSeedsController#destroy`. `seed_new_templates!` takes `PageLayoutTemplates.keys` minus keys already stored on any row, and calls `IndustryTemplateMapping.create` once per industry from `industries_for_category`.

`PageLayoutTemplates.for_industry` returns `all` when the industry is blank or `template_keys_for` is empty. Otherwise it keeps templates whose `:key` is in that list. `category_counts_for_industry` counts the filtered set.

## Where to pay attention

### Route audit: replacement input invariant

Industry updates require an array of string/symbol template keys before any replacement. Malformed containers/items return controlled failure and preserve mappings; explicit `[]` still clears the industry and restores the existing all-template fallback. The centralized platform guard requires outer CID `81721200` for every format. See [Customers](customers), [Tenancy and roles](tenancy-and-roles).

:::note
Category buttons and card badges call `PageLayoutTemplates.category_label` at render time in both locales. Malformed-container and category-label regressions are covered by the 2026-10-12 parallel suite (**25,266 examples, 0 failures**). The separate seed-count semantics below remain unchanged.
:::

:::attention
`IndustryTemplatesController` inherits the central platform role/path guards. `Ability#platform_owner_subjects` includes `platform_industry_templates`; route authorization uses a separate route subject. The mapping table is global, without `customer_id`.
:::

:::attention
`PageLayoutTemplates.for_industry` treats an industry with zero `IndustryTemplateMapping` rows as "show every template". `IndustryTemplateMapping.replace_for_industry!` with an empty `template_keys` array deletes that industry's rows and leaves this fallback in place. `seed_defaults!` only fills industries that have no rows, so it will refill an industry that was cleared.
:::

:::attention
`IndustryTemplateDefaultSeedsController#create` calls `seed_defaults!`. `#destroy` calls `seed_all!`, which `IndustryTemplateMapping.delete_all`s the whole table before inserting defaults. `IndustryTemplateNewTemplateSeedsController#create` calls `seed_new_templates!` and does not replace mappings that already exist.
:::

:::attention
`IndustryTemplateMappingSeeder#seed_new_templates!` adds 1 to its return count after every `IndustryTemplateMapping.create` call. `create` does not raise when the row is invalid, so the flash count `maint_platform.flash.industry_templates.new_mappings_created` can include a call that did not insert. `seed_defaults!` and `seed_all!` use `insert_all`, which skips model validations.
:::

## Key code

```ruby
# app/models/industry_template_mapping.rb
def self.replace_for_industry!(industry, template_keys)
  transaction do
    for_industry(industry).delete_all
    template_keys.each do |key|
      create!(industry: industry.to_s, template_key: key.to_s)
    end
  end
end
```

```ruby
# app/services/page_layout_templates.rb
def for_industry(industry)
  return all if industry.blank?

  allowed_keys = IndustryTemplateMapping.template_keys_for(industry)
  return all if allowed_keys.empty?

  allowed_set = allowed_keys.to_set
  all.select { |t| allowed_set.include?(t[:key]) }
end
```

```ruby
# app/controllers/admin/maintenance/platform/industry_template_default_seeds_controller.rb
def create
  count = IndustryTemplateMappingSeeder.seed_defaults!
  redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
              notice: t("maint_platform.flash.industry_templates.defaults_seeded", count: count)
end

def destroy
  IndustryTemplateMappingSeeder.seed_all!
  redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
              notice: t("maint_platform.flash.industry_templates.reset_to_defaults")
end
```

```ruby
# app/services/industry_template_mapping_seeder.rb
def seed_new_templates!
  mapped_keys = IndustryTemplateMapping.distinct.pluck(:template_key)
  all_keys = PageLayoutTemplates.keys
  new_keys = all_keys - mapped_keys

  return 0 if new_keys.empty?

  templates = new_keys.map { |k| PageLayoutTemplates.find(k) }.compact
  count = 0

  templates.each do |template|
    industries = industries_for_category(template[:category])
    industries.each do |industry|
      IndustryTemplateMapping.create(industry: industry.to_s, template_key: template[:key])
      count += 1
    end
  end

  count
end
```
