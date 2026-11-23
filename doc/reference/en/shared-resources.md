---
title: "Shared resources"
summary: "Platform definitions with a null customer id, per-customer heads, and which writes stay on the platform prefix."
---

## Summary

Entities, pages, flowcharts, and constants can be shared. `SharedIdentity#shared?` is `customer_id` nil. There is no separate sharing column. Entity, Page, and Flowchart keep the definition body in version rows through `Versionable`. A customer override is a head pointer (`entity_customer_heads`, `page_customer_heads`, `flowchart_customer_heads`), and reads go through `resolved_current_version`. Constants are not versioned; a customer override is a `ConstantCustomerOverride` options row. See [constants](constants) for that store.

The global prefix is `/81721200/admin/maintenance/platform/{constants,entities,flowcharts,pages}`. `PlatformPathHelper` recognizes this anchored PATH_INFO including optional formats; `RouteAuthorization` additionally enforces actual outer CID and pinned platform-owner identity. Flowchart editors remain owner-only; bound pages still run. See [Entity builder](entity-builder), [Page builder](page-builder), [Flowchart builder](flowchart-builder), [Tenancy and roles](tenancy-and-roles).

## Flow

```text
GET/POST /81721200/admin/maintenance/platform/{constants,entities,flowcharts,pages}
        |
        |  PlatformPathHelper sets Current.shared_resources_mode
        |  RouteAuthorization: platform_owner?
        v
SharedResourceMode#apply_create_identity!  -> customer_id = nil
SharedResourceMode#definition_scope         -> klass.shared
Versionable#override_customer_id            -> nil (global line)
        |
        v
commit_version! promotes current_version_id

GET/POST /:cid/admin/maintenance/{constants,entities,flowcharts,pages}
        |
        |  shared_resources_mode is false, including customer 81721200
        v
definition_scope -> klass.accessible (own rows OR customer_id nil)
tenant Save of a shared row -> that customer's head / options override
DELETE .../:id/override -> reset_customer_override!(current_customer_id)
```

Launch, audiences, action key, flowchart `crud_type`, destroy, restore, and empty-trash of a shared row follow the platform prefix. A tenant URL of customer `81721200` still writes an `81721200` override.

## Implementation

`Versionable.acts_as_versionable` is called from `Entity`, `Page`, and `Flowchart` with `customer_head_reflection` set. The parent row is the head. `current_snapshot` is the JSON stored in a content-addressed row. `after_save :autocommit_version_snapshot` calls `commit_version!`. An unchanged payload hash is a no-op, so a rename or status change does not add a version. `MAX_VERSIONS` is 50 per line.

`override_customer_id` returns nil when the record is not shared, when no customer is current, or when `Current.shared_resources_mode` is set. Otherwise it returns that customer id. `resolved_current_version` returns the override head when one exists, otherwise `current_version`. `Page#reload_definition_from_head!`, `Entity#reload_definition_from_head!`, and `Flowchart#reload_definition_from_head!` copy that payload into the virtual definition. `current_line_versions` is the line the versions UI shows, so one customer does not list another customer's override history.

`commit_version!` writes the version row with `customer_id` equal to the override customer, or the resource `customer_id` (nil for the global line). `promote_line_head!` updates `current_version_id` on the global line and `find_or_initialize_by(customer_id:)` on an override. The first override sets `based_on_version_id` to the global head.

`SharedResourceMode#definition_scope` uses `klass.shared` on the platform prefix and `klass.accessible` on a tenant URL, and preloads the head association. `apply_create_identity!` sets `customer_id` nil on the platform prefix and assigns `current_customer` on a tenant URL. `tenant_override?` is a shared record outside shared-resources mode. Entity, page, and flowchart updates then permit the definition body and leave identity columns alone. `EntitiesController` identity keys are `name`, `display_label`, `extended_model`, and `associations`. Page and flowchart tenant overrides permit `configuration` only.

`guard_shared_global_writes` calls `reject_shared_global_mutation!`. That helper redirects HTML with `maint_core.flash.shared_resources.platform_path_only` and returns 403 JSON when a shared record is written off the platform prefix. It is installed on destroy for entities, pages, flowcharts, and constants, and on every action of `PageLaunchesController`, `PageVisibilitiesController`, `FlowchartLaunchesController`, and `FlowchartCrudTypesController`.

Trash follows the same split. `deleted_definition_scope` is `only_deleted.shared` on the platform prefix and `only_deleted.where(customer_id: current_customer_id)` on a tenant URL. `scoped_deleted_resources` uses the shared deleted set when shared-resources mode is on, so empty-trash on a tenant URL does not destroy shared rows.

`SharedResourceOverridesController` is nested as `resource :override, only: :destroy` under tenant constants, entities, flowcharts, and pages. The platform remount does not declare that route. `destroy` calls `reset_customer_override!(current_customer_id)`. On a versioned resource that deletes the customer's head, that customer's version rows, and orphaned content, then reloads the definition from the global head. A missing override redirects with `override_missing`.

`Flowchart#generate_activity` does not overwrite global `activity` for an override. Public submission now wraps the effective definition in `Pages::PublicSubmission::RuntimeFlowchart` and compiles an override request-locally without writing the global artifact/head. See [Flowchart runtime](flowchart-runtime).

## Where to pay attention

### Route audit: global path and version-content invariants

Formatted collections such as `/81721200/admin/maintenance/platform/entities.json` remain global. A wrong outer customer returns 404 for all platform actions/formats, regardless of nested target/body/query IDs. Tenant create always owns the row; tenant shared saves/reset/history stay on that customer's line. Entity promotion validates and reconciles bridges before moving that line's head.

`Versionable` collects candidate content IDs before parent destruction and removes only IDs unreferenced by any remaining version of that content family. Override reset/pruning likewise check references across owners/lines, retaining shared content used elsewhere. Customer purge preserves globally shared parents and surviving content references; see [Customers](customers) and [Entity builder](entity-builder).

:::note
Path-lock, entity-line and content-GC regressions are authored, not executed here. No runtime builder audit or live migration/concurrency evidence is implied.
:::

:::attention
`Versionable#override_customer_id` returns nil while `Current.shared_resources_mode` is true, and returns the URL customer otherwise. A platform owner saving a shared entity, page, or flowchart on `/:cid/admin/maintenance/...` writes customer `cid`'s head, including when `cid` is `81721200`. Global identity, launch, audiences, action key, and flowchart `crud_type` stay on the platform prefix through `PlatformPathHelper#reject_shared_global_mutation!`.
:::

:::attention
`FlowchartVisibility.allowed?` is `user.platform_owner?`. `RouteAuthorization#flowchart_namespace?` matches a flowchart controller path or `FLOWCHART_PATH_PATTERN`, and `enforce_route_role!` rejects anyone who is not a platform owner. Tenant admins do not get the editor. A page that stores `form_settings.flowchart_id` still submits. See [page-rendering](page-rendering).
:::

:::attention
`SharedResourceOverridesController#find_record` loads `Constant`, `Entity`, `Flowchart`, or `Page` with `accessible` and raises `ActiveRecord::RecordNotFound` unless `shared?`. `reset_customer_override!` returns false when there is no head and no version rows for that customer (constants: no `ConstantCustomerOverride` row). The HTML response is the `override_missing` alert.
:::

:::attention
`Versionable` prunes each line to `MAX_VERSIONS` (50) after `commit_version!`. The versions UI reads `current_line_versions`. `EntityVersionsController#line_version` allows show and create-page to read a global version, and keeps `default` and `destroy` on `current_line_versions` so a tenant URL cannot move the global head.
:::

## Key code

```ruby
# app/models/concerns/versionable.rb
  def override_customer_id(cid = Current.customer_id)
    return nil unless customer_overridable?
    return nil unless respond_to?(:shared?) && shared?
    return nil if cid.blank? || Current.shared_resources_mode
    cid
  end

  # The version whose definition the given customer should see: their override
  # head if present, else the global default head.
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || current_version
  end
```

```ruby
# app/models/concerns/shared_identity.rb
  def shared?
    customer_id.nil?
  end

  def customer_owned?
    customer_id.present?
  end
```

```ruby
# app/helpers/admin/maintenance/platform_path_helper.rb
      PATH_PATTERN = %r{\A/81721200/admin/maintenance/platform/(constants|entities|flowcharts|pages)(?:[/.]|\z)}

      def shared_resources_mode?
        Current.shared_resources_mode == true
      end
```

```ruby
# app/helpers/admin/maintenance/platform_path_helper.rb
      def install_platform_path_overrides
        Admin::Maintenance::PlatformPathHelper.install_if_needed!
        Current.shared_resources_mode = request.path_info.match?(PATH_PATTERN)
      end
```

```ruby
# app/controllers/concerns/admin/maintenance/shared_resource_mode.rb
      def apply_create_identity!(record)
        if shared_resources_mode?
          record.skip_tenant_customer_assignment! if record.respond_to?(:skip_tenant_customer_assignment!)
          record.customer_id = nil
        else
          record.customer = current_customer if record.respond_to?(:customer=)
        end
      end

      def require_copyable_source!(record)
        raise ActiveRecord::RecordNotFound unless can_copy_definition?(record)
      end

      def skip_quota_for_shared_create?(record)
        shared_record?(record)
      end

      def publishing_editable?(record)
        !shared_record?(record) || shared_resources_mode?
      end

      # Tenant-path Save of a shared row writes that customer's override, not
      # the global default (including when the URL customer is 81721200).
      def tenant_override?(record)
        shared_record?(record) && !shared_resources_mode?
      end
```

```ruby
# app/controllers/admin/maintenance/shared_resource_overrides_controller.rb
      def destroy
        cleared = @record.reset_customer_override!(current_customer_id)

        respond_to do |format|
          format.html do
            if cleared
              redirect_to record_show_path,
                          notice: t("maint_core.flash.shared_resources.override_reverted")
            else
              redirect_to record_show_path,
                          alert: t("maint_core.flash.shared_resources.override_missing")
            end
          end
```
