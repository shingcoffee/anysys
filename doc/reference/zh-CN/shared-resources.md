---
title: "共享资源"
summary: "customer_id 为空的平台定义、按客户保存的头指针，以及哪些写入只能走平台前缀。"
---

## 概要

实体、页面、流程图和常量都可以是共享资源。`SharedIdentity#shared?` 的含义是 `customer_id` 为 nil，没有单独的共享列。Entity、Page 与 Flowchart 通过 `Versionable` 把定义正文放在版本行里。客户覆盖是一条头指针（`entity_customer_heads`、`page_customer_heads`、`flowchart_customer_heads`），读取走 `resolved_current_version`。常量不走版本；客户覆盖是一行 `ConstantCustomerOverride` 的 options。该表见 [constants](constants)。

全局前缀为 `/81721200/admin/maintenance/platform/{constants,entities,flowcharts,pages}`。`PlatformPathHelper` 匹配该锚定 PATH_INFO，包含可选格式；`RouteAuthorization` 另强制实际外层 CID 及固定平台所有者身份。流程图编辑器仍仅所有者可见，已绑定页面仍执行。见[实体构建器](entity-builder)、[页面构建器](page-builder)、[流程图构建器](flowchart-builder)、[租户与角色](tenancy-and-roles)。

## 流程

```text
GET/POST /81721200/admin/maintenance/platform/{constants,entities,flowcharts,pages}
        |
        |  PlatformPathHelper 设置 Current.shared_resources_mode
        |  RouteAuthorization：platform_owner?
        v
SharedResourceMode#apply_create_identity!  -> customer_id = nil
SharedResourceMode#definition_scope         -> klass.shared
Versionable#override_customer_id            -> nil（全局行）
        |
        v
commit_version! 推进 current_version_id

GET/POST /:cid/admin/maintenance/{constants,entities,flowcharts,pages}
        |
        |  shared_resources_mode 为 false，客户 81721200 同样如此
        v
definition_scope -> klass.accessible（本客户的行，或 customer_id 为 nil）
租户路径保存共享行 -> 该客户的头指针 / options 覆盖
DELETE .../:id/override -> reset_customer_override!(current_customer_id)
```

共享行的发布、受众、操作标识、流程图 `crud_type`、删除、恢复和清空回收站都走平台前缀。客户 `81721200` 的租户 URL 写入的仍是 `81721200` 的覆盖。

## 实现

`Entity`、`Page`、`Flowchart` 调用 `Versionable.acts_as_versionable`，并设置 `customer_head_reflection`。父行是头。`current_snapshot` 是写入内容寻址行的 JSON。`after_save :autocommit_version_snapshot` 调用 `commit_version!`。载荷哈希未变时是空操作，因此改名或改状态不会新增版本。每条版本线的 `MAX_VERSIONS` 是 50。

记录不是共享资源、当前没有客户，或 `Current.shared_resources_mode` 已设置时，`override_customer_id` 返回 nil。否则返回该客户 id。存在覆盖头时，`resolved_current_version` 返回覆盖头，否则返回 `current_version`。`Page#reload_definition_from_head!`、`Entity#reload_definition_from_head!` 与 `Flowchart#reload_definition_from_head!` 把该载荷抄进虚拟定义。版本界面读取 `current_line_versions`，一个客户看不到另一个客户的覆盖历史。

`commit_version!` 写入版本行时，`customer_id` 取覆盖客户；没有覆盖时取资源自身的 `customer_id`（全局行是 nil）。`promote_line_head!` 在全局行上更新 `current_version_id`，在覆盖行上按 `find_or_initialize_by(customer_id:)` 更新。第一次覆盖把 `based_on_version_id` 设为全局头。

平台前缀上 `SharedResourceMode#definition_scope` 使用 `klass.shared`，租户 URL 使用 `klass.accessible`，并预加载头关联。`apply_create_identity!` 在平台前缀把 `customer_id` 设为 nil，在租户 URL 赋 `current_customer`。`tenant_override?` 表示共享记录且不在共享资源模式。实体、页面、流程图的更新于是只允许定义正文，身份列保持原样。`EntitiesController` 的身份键是 `name`、`display_label`、`extended_model` 与 `associations`。页面和流程图的租户覆盖只允许 `configuration`。

`guard_shared_global_writes` 调用 `reject_shared_global_mutation!`。共享记录在平台前缀之外被写入时，HTML 重定向并带上 `maint_core.flash.shared_resources.platform_path_only`，JSON 返回 403。实体、页面、流程图和常量的 destroy 装了这个守卫；`PageLaunchesController`、`PageVisibilitiesController`、`FlowchartLaunchesController` 与 `FlowchartCrudTypesController` 的每个动作也都装了。

回收站按同一条分界。平台前缀的 `deleted_definition_scope` 是 `only_deleted.shared`，租户 URL 是 `only_deleted.where(customer_id: current_customer_id)`。共享资源模式打开时，`scoped_deleted_resources` 使用已删除的共享集合，因此租户 URL 上的清空回收站不会删掉共享行。

`SharedResourceOverridesController` 以 `resource :override, only: :destroy` 嵌在租户的常量、实体、流程图和页面下。平台重挂路由没有这条路由。`destroy` 调用 `reset_customer_override!(current_customer_id)`。版本化资源会删掉该客户的头、该客户的版本行和成为孤儿的内容，再从全局头重新加载定义。没有覆盖时重定向并带上 `override_missing`。

`Flowchart#generate_activity` 不会因覆盖而重写全局 `activity`。公开提交现以 `Pages::PublicSubmission::RuntimeFlowchart` 包装生效定义，在请求内编译覆盖，不写全局产物／头。见[流程图运行时](flowchart-runtime)。

## 需要特别注意

### 路由审计：全局路径与版本内容不变量

`/81721200/admin/maintenance/platform/entities.json` 等格式集合仍属于全局。错误外层客户对所有平台动作／格式返回 404，嵌套目标／正文／查询 ID 无法替代。租户创建始终是自有行，共享保存／重置／历史只处理该客户版本线。实体提升在移动该线头前校验并协调桥接。

`Versionable` 在父记录删除前收集候选内容 ID，仅删除同内容族所有剩余版本均未引用的 ID。覆盖重置／裁剪也跨归属／版本线检查引用，保留其他地方仍在使用的共享内容。客户清理保留全局共享父记录及存活内容引用；见[客户](customers)及[实体构建器](entity-builder)。

:::note
路径锁、实体版本线及内容 GC 回归测试已编写，本次未执行。不代表构建器运行审计或实际迁移／并发验证。
:::

:::attention
`Current.shared_resources_mode` 为 true 时，`Versionable#override_customer_id` 返回 nil；否则返回 URL 上的客户。平台所有者在 `/:cid/admin/maintenance/...` 保存共享实体、页面或流程图时，写入的是客户 `cid` 的头，`cid` 为 `81721200` 时同样如此。全局身份、发布、受众、操作标识和流程图 `crud_type` 留在平台前缀，由 `PlatformPathHelper#reject_shared_global_mutation!` 拦住租户路径。
:::

:::attention
`FlowchartVisibility.allowed?` 就是 `user.platform_owner?`。`RouteAuthorization#flowchart_namespace?` 匹配流程图控制器路径或 `FLOWCHART_PATH_PATTERN`，`enforce_route_role!` 拒绝不是平台所有者的用户。租户管理员没有编辑器。页面若保存了 `form_settings.flowchart_id`，提交仍然会跑。见 [page-rendering](page-rendering)。
:::

:::attention
`SharedResourceOverridesController#find_record` 用 `accessible` 加载 `Constant`、`Entity`、`Flowchart` 或 `Page`，`shared?` 为假时抛出 `ActiveRecord::RecordNotFound`。该客户没有头、也没有版本行时，`reset_customer_override!` 返回 false（常量则是没有 `ConstantCustomerOverride` 行）。HTML 响应是 `override_missing` 警告。
:::

:::attention
`commit_version!` 之后，`Versionable` 把每条版本线裁到 `MAX_VERSIONS`（50）。版本界面读 `current_line_versions`。`EntityVersionsController#line_version` 允许 show 和「从版本创建页面」读取全局版本，而 `default` 与 `destroy` 留在 `current_line_versions` 上，租户 URL 不能移动全局头。
:::

## 关键代码

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
