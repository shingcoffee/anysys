---
title: "Constants"
summary: "Named option lists that are either customer-owned or shared, with a per-customer options override."
---

## Summary

A `Constant` is a named list of options. `customer_id` nil means shared (`SharedIdentity#shared?`). A customer-owned row belongs to one tenant. Shared constants are created on the platform prefix. A tenant Save of a shared constant writes `constant_customer_overrides` for the URL customer and leaves the global `options` column in place. Reads overlay that row when it exists. Reset drops it. See [shared-resources](shared-resources) for the prefix and [entity-builder](entity-builder) for attributes that pick a constant.

## Flow

```text
Platform prefix create
        |
        |  SharedResourceMode#apply_create_identity! sets customer_id nil
        v
constants row (name, options)  customer_id NULL

Tenant URL update of a shared constant
        |
        |  Constant#writing_customer_override?
        |  restore_shared_identity! puts the stored name back
        |  stash_customer_override! keeps the incoming options off the parent column
        v
constant_customer_overrides (constant_id, customer_id, options)

after_find / reload_options_from_override!
        |
        |  override present -> self.options = override.options
        |  override absent  -> constants.options
        v
Admin::Maintenance::ConstantsController index / show / JSON picker
```

`DELETE /:cid/admin/maintenance/constants/:id/override` calls `Constant#reset_customer_override!`.

## Implementation

`Constant` includes `SharedIdentity` and `has_many :constant_customer_overrides`. It does not call `acts_as_versionable`. `options` is required. `ensure_options_is_array` stores an array. When every entry is blank after strip, `options_must_not_be_blank` adds an error. Duplicate stripped values fail `options_must_be_unique`. Name uniqueness is scoped to `customer_id` for a customer-owned row and is global for a shared row.

`Admin::Maintenance::ConstantsController` includes `SharedResourceMode`. `index` HTML lists `definition_scope(Constant).ordered`. The JSON format is the same scope, unpaginated, `as_json(only: %i[id name options])`, because the attribute picker needs every accessible constant. `definition_scope` is `Constant.shared` on the platform prefix and `Constant.accessible` on a tenant URL (this customer's rows plus every shared row). `create` runs `apply_create_identity!` before save.

`update` permits `name` and, when the key is present, `options`. A missing `options` key leaves the stored array. `normalize_options` accepts a JSON string, parameter values, or an array, and turns a blank or unparseable value into `[]`, which then fails validation.

On a tenant-path update of a shared row, `writing_customer_override?` is true (`persisted?` and `override_customer_id` present). `override_customer_id` is nil when `Current.shared_resources_mode` is set, so a platform-prefix save writes the global columns. `restore_shared_identity!` assigns `name` from `attribute_in_database("name")` before validation. `stash_customer_override!` copies the incoming options aside and assigns `options` from the database so the shared column is unchanged. `persist_stashed_override!` writes `constant_customer_overrides` for `Current.customer_id`. When no override exists yet and the incoming array equals the global options, it does not insert a row.

`ConstantsController#update` calls `touch` only when `tenant_override?` is false, so an override save does not bump the shared row's `updated_at`. Destroy of a shared constant is wrapped in `guard_shared_global_writes`. `can_copy_definition?` allows copying a customer-owned row, or a shared row on the platform prefix.

`ConstantCustomerOverride` validates `customer_id` presence and uniqueness scoped to `constant_id`, and requires `options`. `reset_customer_override!` destroys that row and reloads options from the global column. It returns false when the constant is not shared or no override row exists.

`after_find :reload_options_from_override!` applies the overlay for the current customer. List pages preload `:constant_customer_overrides` from `SharedResourceMode#preload_override_association`.

### Flowchart step: read_setting

The `read_setting` step action reads a Constant from a flowchart. `constant` (required) is a reference to the `constants` source (the customer's constants plus shared ones). `returns: "options"` writes the option list; `returns: "label"` writes the label for `value` (an expression, required in that mode). It calls `FlowchartRuntime::Constants.options` / `.label`, which resolve against `ctx[:customer_id]`, never `Current`: a shared constant uses that customer's `ConstantCustomerOverride` when one exists, and another tenant's constant raises `Constants::Error`, which the step reports as `read_setting.failed`. The result goes to `resultVar` (default `constant_options`). See [Flowchart step actions](flowchart-step-actions).

## Where to pay attention

:::attention
`Constant#override_customer_id` follows the same rule as `Versionable`: nil in `Current.shared_resources_mode`, otherwise the current customer id for a shared row. `Admin::Maintenance::ConstantsController` on `/:cid/admin/maintenance/constants` therefore stores an override for `cid`, including customer `81721200`. The global `name` and `options` change on `/admin/maintenance/platform/constants`.
:::

:::attention
`Constant#persist_stashed_override!` skips `find_or_initialize_by` when the customer has no override and the submitted options equal the global array. A no-op tenant Save does not pin the customer off later global edits. A real difference inserts `ConstantCustomerOverride`.
:::

:::attention
`Constant#restore_shared_identity!` runs `before_validation` while `writing_customer_override?`. The stored `name` is written back before the uniqueness checks, so a tenant update cannot rename the shared constant. Destroy still goes through `guard_shared_global_writes` and `PlatformPathHelper#reject_shared_global_mutation!`.
:::

:::attention
The JSON index in `ConstantsController#index` renders `definition_scope(Constant).ordered` with no pagination. `SharedIdentity.accessible` is the current customer's rows or `customer_id` nil. A platform-prefix request uses `Constant.shared` only.
:::

## Key code

```ruby
# app/models/constant.rb
  def override_customer_id(cid = Current.customer_id)
    return nil unless shared?
    return nil if cid.blank? || Current.shared_resources_mode

    cid
  end
```

```ruby
# app/models/constant.rb
  def persist_stashed_override!
    return if @stashed_override_options.nil?

    incoming = Array(@stashed_override_options)
    # A tenant Save that matches the global default must not pin an override;
    # otherwise a no-op resubmit forks the customer off later global edits.
    if override_for(Current.customer_id).nil? && incoming == Array(options)
      self.options = incoming
      @stashed_override_options = nil
      return
    end

    constant_customer_overrides
      .find_or_initialize_by(customer_id: Current.customer_id)
      .update!(options: incoming)
    self.options = incoming
    @stashed_override_options = nil
  end
```

```ruby
# app/models/constant.rb
  def reset_customer_override!(cid = Current.customer_id)
    return false unless shared? && cid.present?

    ov = override_for(cid)
    return false unless ov

    ov.destroy
    reload_options_from_override!
    true
  end
```

```ruby
# app/controllers/admin/maintenance/constants_controller.rb
    def update
      if @constant.update(constant_params)
        # Reflect every Save in the "last updated" time. Rails only bumps
        # updated_at when an attribute actually changed; an identical resubmit
        # would otherwise leave the timestamp stale, so touch when nothing else
        # moved it. Tenant-path overrides must not touch the shared parent row.
        unless tenant_override?(@constant)
          @constant.touch unless @constant.saved_change_to_updated_at?
        end
```

```ruby
# app/models/constant_customer_override.rb
class ConstantCustomerOverride < ApplicationRecord
  belongs_to :constant

  validates :customer_id, presence: true, uniqueness: { scope: :constant_id }
  validates :options, presence: true
end
```
