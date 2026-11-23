---
title: "访问授权"
summary: "RolePermission 行以及 Ability 里的保留角色短路如何变成每次请求上的 CanCan 规则。"
---

## 概要

`Ability` 是 CanCanCan 以 `Ability.new(current_user)` 构造的能力对象。平台所有者得到 `can :manage, :all` 后立即返回。持有保留角色 `admin` 的用户得到 `can :manage, :all`，但平台主体和流程图路由主体除外，然后同样返回。还能继续往下走的人——实际是成员，以及挂在 `member` 旁边的自定义角色——先得到固定的成员路由清单，再由 `RolePermissions::Operation::ResolveGrants` 为每条 `RolePermission` 生成一条规则。

[租户与角色](tenancy-and-roles) 里的路径门槛先执行。授权不能让非 `admin_or_owner?` 的人打开 `/admin`，也不能让非 `member?` 的人打开 `/member`。

## 流程

```text
创建 Customer
        |
        v
Roles::Operation::SeedReserved
        |  系统角色 owner、admin、member（locked_grants）
        |  admin：AccessPoints::Catalog -> RolePermission.insert_all!
        v
设置界面
GET/PATCH /:cid/admin/settings/modules/authentication/roles/:role_id/grants
        |
        |  Admin::Settings::Modules::Authentication::RoleGrantsController
        |  GrantsEditorComponent + grants_editor_controller.js
        v
RoleGrants::Operation::Update
        |  拒绝 locked_grants
        |  除非 actor.owner?，否则拒绝 Platform 与流程图路由
        |  实例编号必须属于 role.customer_id
        v
role_permissions
        |
        v
请求
RouteAuthorization#authorize_route!
        |
        v
Ability#initialize
        |  platform_owner? -> manage :all 后返回
        |  保留角色 admin  -> manage :all，排除平台与流程图，后返回
        |  保留角色 member -> can manage member_route_subjects
        |  然后每条 RolePermission -> apply_grant
        v
CanCan authorize! 动词, :"route_<controller_path>"
```

自定义角色创建于 `/:cid/admin/settings/modules/authentication/roles`。把它们赋给用户由 `UserRoleAssignmentsController` 调用 `UserRoles::Operation::Assign`。这次赋值里，用户必须恰好保留一个保留角色。

## 实现

### 角色

`Role` 属于 `customer`，经 `users_roles` 拥有多条 `role_permissions` 和多个 `users`。`key` 在每个 `customer_id` 内唯一。`RESERVED_KEYS` 为 `owner`、`admin`、`member`。`reserved?` 表示键在这份清单里。`system` 与 `locked_grants` 是布尔值。

`Roles::Operation::SeedReserved` 用 `find_or_create_by!` 创建这三个键，`system: true` 且 `locked_grants: true`。只有 `admin`，并且该角色还没有任何权限时，会清空 `Current.access_points_catalog`，构建 `AccessPoints::Catalog.for(customer_id:)`，再对每个描述符的每个动作 `insert_all!` 一条 `RolePermission`。键为 `"platform"`，或以 `"admin.maintenance.platform"` 开头的分组会被跳过。`insert_all!` 不跑校验，因此 `assert_grant_shape!` 用普通 Ruby 复述 `RolePermission` 对键与编号的形状要求。

`Roles::Operation::Create` 建立 `system: false`、`locked_grants: false` 的角色，并用 `Roles::Contract::Create` 校验（`key` 匹配 `[a-z0-9_]+`）。`Update` 拒绝 `role.system?`。`Destroy` 拒绝 `role.system?`。HTTP 入口是 `Admin::Settings::Modules::Authentication::RolesController`，范围是 `current_customer.roles`。

`UserRoles::Operation::Assign` 锁住用户，并通过 `user.customer.roles` 解析角色 ID。受理集合必须恰好包含一个保留角色。替换保留角色时原位更新连接行；owner 分配即使由所有者本人操作也不可变，`UserRoles::AssignmentPolicy` 拒绝单独删除唯一保留角色连接。认证模块的单用户编辑器使用同一操作，保留附加自定义角色，并将资料与角色修改纳入同一回滚边界。分配控制器返回本地化 HTML／JSON 错误，仅成功修改后记录审计。

### 目录

`config/initializers/access_points.rb` 在初始化之后调用 `AccessPoints::Registry.install_default_providers!`。提供者顺序为 `RouteProvider`、`ModuleProvider`、`EntityClassProvider`、`EntityProvider`、`PageClassProvider`、`PageProvider`、`PlatformProvider`。

`AccessPoints::Catalog.for` 把结果记在 `Current.access_points_catalog` 上。`groups` 向每个 `applicable?` 的提供者要 `Descriptor`，再按 `group_key` 分桶。描述符带有 `subject_type`、`subject_key`、`subject_id`、`actions`、`group_key` 和 `label`。

| 提供者 | 主体 | 列出的内容 |
| --- | --- | --- |
| `RouteProvider` | `Route`，键为控制器路径 | 来自 `Rails.application.routes` 的管理端路由。动词映射为 `:read`、`:create`、`:update`、`:destroy`。`FlowchartVisibility.controller?` 命中的控制器被省略。 |
| `ModuleProvider` | `Module`，键为模块键 | `FeatureModules::Module.available_for_customer`，动作为 `:manage` |
| `EntityClassProvider` | `EntityClass`，键 `"Entity"` | 一条集合描述符，动作为读、建、改、删 |
| `EntityProvider` | `Entity`，编号为行 id | `Entity.where(customer_id:)` |
| `PageClassProvider` | `PageClass`，键 `"Page"` | 一条集合描述符 |
| `PageProvider` | `Page`，编号为行 id | `Page.where(customer_id:)` |
| `PlatformProvider` | `Platform` | 仅当 `customer_id` 为 `81721200`。键：`customers`、`module_settings`、`industry_templates`、`code_generators` |

`RolePermission::SUBJECT_TYPES` 还包括 `FeaturePage`。`Ability#apply_grant` 把它译成 `:"feature_<subject_key>"`。已注册的提供者都不产生 `FeaturePage`，因此授权编辑器不会列出它。

### 编辑器

`Admin::Settings::Modules::Authentication::GrantRouteLabel` 在渲染时使用英文和简体中文均有译文的键生成路由名称。`admin/maintenance/page_shortcuts` 描述符复用 `page_shortcuts.title`，使 [页面快捷路径](page-shortcuts) 在权限目录中具有独立的本地化资源标签。这属于展示元数据；授权仍由控制器路径主体键、授权动作、admin／owner 门禁和租户范围决定。

嵌套账单写入控制器复用既有动作标签：`admin/settings/billing/plan_changes` 使用 `settings_billing.subscription.cancel_change`，`admin/settings/billing/invoice_payments` 使用 `comp_billing.invoice_detail.pay_invoice`。不同的本地化后缀分别标识取消变更与付款，避免两者合并为通用资源标签。

短信受众／活动的八个控制器在短信上下文下保持独立的 `Route` 主体。`AccessPoints::SmsRouteLabels` 为 `RouteProvider` 与 `GrantRouteLabel` 提供共用的调用时翻译键；编辑器显示如**模块记录 — 短信 — 联系人**的名称，子系统仅出现一次。两种语言均定义每个资源后缀，不会合并为“其他资源”。联系人／受众／活动及取消群发复用已有翻译；同意、同步、启动和报告标签位于成对的 `settings_people.grant_resources.sms_*` 键。

| `admin/modules/sms/` 下的控制器后缀 | 资源标签 | 已注册动作 |
| --- | --- | --- |
| `contacts` | 联系人 | read、create、update、destroy |
| `consent_events` | 同意记录 | create |
| `entity_syncs` | 联系人同步 | read、create |
| `segments` | 受众 | read、create、update、destroy |
| `campaigns` | 活动 | read、create、update、destroy |
| `campaign_launches` | 启动活动 | create |
| `campaign_cancellations` | 取消群发 | create |
| `campaign_reports` | 活动报告 | read |

标签仅影响展示，授权仍由控制器路径键、HTTP 派生动作、保留角色、短信启用状态及 URL 租户门禁决定。同意记录创建、活动启动和取消分别授权，报告为只读操作。公开签名退订 URL 不属于管理端路由授权。参见[短信受众与活动](sms-campaigns)。

客户域名是资料属性，不是独立 CanCan 主体。中央平台授权对所有格式／动作要求实际外层 PATH_INFO 客户为 `81721200`；查询／正文及嵌套目标 ID 不能替代。新增／变更域名须配置直接指向 `anysys.net` 的 CNAME，这不授予权限。见[客户](customers)及[自定义域名](custom-domains)。

`RoleGrantsController#show` 为 `current_customer.id` 加载目录，并把 `role.role_permissions` 收成 `"类型:键:编号:动作"` 集合。`GrantsEditorComponent` 渲染矩阵。`locked?` 即 `role.locked_grants?`。`owner_access?` 即 `role.key == "owner"`，此时 `granted?` 对每个动作都为真。这只是显示上的捷径。所有者的能力对象不读这些复选框。

`app/javascript/controllers/grants_editor_controller.js` 以 JSON `{ role_grants: { added, removed } }` `PATCH` 更新地址。每一项含 `subject_type`、`subject_key`、`subject_id` 和 `action`。`RoleGrantsController#update` 允许这些键，并调用 `RoleGrants::Operation::Update`。`RoleGrants::Contract::Update` 是 `app/concepts/role_grants/contract/update.rb` 里的 Reform 表单。控制器没有调用它。

`RoleGrants::Operation::Update` 在 `role.locked_grants?` 时直接失败。主体类型为 `Platform`，或类型为 `Route` 且键被 `FlowchartVisibility.controller?` 命中时，若操作者不是 `owner?`，`add_grant!` 抛出 `PlatformGrantForbidden`。实例主体（`Entity` 或 `Page`）必须存在 id 相同且 `customer_id` 等于 `role.customer_id` 的行。随后 `create!`，因此 `RolePermission` 的校验会执行。`remove_grant!` 按类型、动作、键和编号 `destroy_all`。

`RolePermission::ACTIONS` 为 `read`、`create`、`update`、`destroy`、`manage`。按键的类型要求 `subject_key`，禁止 `subject_id`。实例类型要求 `subject_id`，禁止 `subject_key`。检查约束要求键与编号至少有一个。

### Ability

`Ability#initialize` 把 `@customer_id` 设为 `user.customer_id`；用户为空时用 `Current.customer_id`。空用户得到空的能力对象。

`platform_owner?` 执行 `can :manage, :all` 后 `return`。保留角色 `admin`（`has_reserved_role?(:admin)`）执行 `can :manage, :all`，再对 `platform_owner_subjects`，以及对 `FlowchartVisibility.route_subject?` 为真的符号（符号以 `route_admin_maintenance_flowchart` 开头）执行 `cannot :manage`，然后 `return`。这条路径不读取为管理员种下的 `RolePermission`。`cannot` 清单比 `PlatformProvider` 更宽，还包括 `platform_announcements`、`platform_support_tickets`、`platform_customer_context`、`platform_sms`、`platform_captcha` 和 `platform_ai_assistant`。

保留角色 `member` 为 `member_route_subjects` 增加 `can :manage`：

- `route_member_dashboards`、`route_member_profiles`、`route_member_securities`、`route_member_mfa`、`route_member_trusted_devices`、`route_member_payments`、`route_member_pages`、`route_member_surfaces`
- `route_member_payments_payment_methods`、`route_member_payments_subscriptions`、`route_member_payments_subscription_cancellations`

`grants_for` 加载 `RolePermission.where(role_id: user.role_ids)`。`apply_grant` 丢掉空白动作，以及 `RolePermission::ACTIONS` 之外的动作。`manage` 保持为 `:manage`，其他动作变成符号。主体翻译如下：

| `subject_type` | CanCan 主体 |
| --- | --- |
| `Route` | `:"route_<控制器>"`，斜杠换成下划线。键被 `FlowchartVisibility.controller?` 命中时跳过。 |
| `Module` | `:"module_<键>"` |
| `FeaturePage` | `:"feature_<键>"` |
| `Platform` | `:"platform_<键>"` |
| `EntityClass` | `Entity` 类，没有 id，也没有 `customer_id` |
| `PageClass` | `Page` 类，没有 id，也没有 `customer_id` |
| `Entity` 或 `Page` | `can action, klass, id:, customer_id:`。id 或 `@customer_id` 为空时跳过。`@customer_id` 是用户自己的客户，平台所有者查看其他租户时也是如此。平台所有者到不了这个方法。 |

管理员和平台所有者会先返回，因此挂在管理员身上的自定义角色不会改变 `Ability`。`UserRoles::Operation::Assign` 仍允许自定义角色与恰好一个保留角色并存。保留角色是 `member` 时，这些额外行才会影响 CanCan，因为成员分支在 `grants_for` 之前没有返回。它们不影响 URL 角色门槛：`/admin` 仍然要求 `admin_or_owner?`。

`RouteAuthorization#authorize_route!` 即 `authorize! verb_action, :"route_#{controller_path.tr('/', '_')}"`。新增成员控制器必须写进 `Ability#member_route_subjects`，否则成员的隐含规则覆盖不到它。新增仅平台可用的主体必须写进 `platform_owner_subjects`，否则管理员的 `can :manage, :all` 会在 CanCan 层放行。`/admin/maintenance/platform` 的路径门槛仍然是 `RouteAuthorization`。

流程图里做能力检查的步骤，由生成的 `authorize` 元素调用 `Ability.new(user)`（`CodeGenerators::ElementTypes::Process::Security::AuthorizeGenerator`）。用的是同一个类。

## 需要特别注意

### 路由审计：分配及授权不变量

附加角色 CRUD 不增加保留角色，也不能绕过 URL 门禁。`UsersRole` 保护租户一致、唯一保留分配、owner 固定及唯一保留角色不可删除。已挂载注册／开通原子保存账户与角色；直接模型创建是由调用方显式分配角色的底层 API。`Assign.call(user:, role_ids:, actor: nil, request: nil)` 及受保护移除经 `Authentication::MutationAudit.roles` 记录实际角色差集，与修改同事务并在提交后记日志。见[租户与角色](tenancy-and-roles)及[认证模块](authentication-module)。

:::note
角色模型／操作及分配请求回归测试已编写，本次整合未执行。拒绝处理与稳定连接 ID 已检查源码，尚未完成运行验证。
:::

:::attention
`Ability#initialize` 在 `platform_owner?` 分支和 `has_reserved_role?(:admin)` 分支里返回。这两类用户不会执行 `RolePermissions::Operation::ResolveGrants`。`Roles::Operation::SeedReserved` 插入的管理员行被 `locked_grants` 锁住，也不是管理员请求实际使用的规则。
:::

:::attention
`RoleGrants::Operation::Update` 在写入之前拒绝 `locked_grants`。`Roles::Operation::SeedReserved` 给 `owner`、`admin`、`member` 设置了 `locked_grants`。授权编辑器可以改自定义角色，不能改这三个保留角色。
:::

:::attention
`RoleGrants::Operation::Update.owner_only_grant?` 把 `Platform` 和流程图 `Route` 键视为仅所有者可授，操作者判断是 `actor.owner?`。`GrantsEditorComponent#owner_access?` 只影响 `role.key == "owner"` 时哪些框看起来已勾选。保存仍然经过这个操作。
:::

:::attention
`Ability#apply_grant` 把 `EntityClass` 映射为 `can action, Entity`，把 `PageClass` 映射为 `can action, Page`，条件里没有 `customer_id`。实例行走 `grant_instance`，会加上 `id` 和 `customer_id: user.customer_id`。类授权授权的是类本身。查询的租户范围仍由加载这些行的控制器或 scope 负责。
:::

:::note
`AccessPoints::Registry` 没有 `FeaturePage` 提供者。`FeaturePage` 权限仍可入库，`Ability` 也会翻译它，但 `GrantsEditorComponent` 不会为它显示复选框。
:::

## 关键代码

```ruby
# app/models/ability.rb
    if user.platform_owner?
      # Platform owner customer (81721200) — full access across every
      # tenant and every platform-scoped subject.
      can :manage, :all
      return
    end

    if user.has_reserved_role?(:admin)
      # Tenant admin — full access inside their own customer, but no
      # implicit access to platform-scoped subjects or flowchart routes.
      # Those surfaces are also gated by RouteAuthorization; these cannot
      # rules keep `authorize_route!` honest if a controller is remounted.
      can :manage, :all
      cannot :manage, platform_owner_subjects
      cannot :manage, Symbol do |subject|
        FlowchartVisibility.route_subject?(subject)
      end
      return
    end

    if user.has_reserved_role?(:member)
      # Tenant member — implicit access to every member route within
      # their own customer. Member routes don't carry per-action
      # role_permission rows; the URL-prefix gate (RouteAuthorization)
      # plus per-record ownership checks (Member::BaseController#
      # authorize_owned!) provide the actual security. This rule lets the
      # CanCan layer pass for any /:cid/member/* request.
      can :manage, member_route_subjects
    end

    grants_for(user).each { |g| apply_grant(g) }
```

```ruby
# app/models/ability.rb
  def grant_instance(action, klass, id)
    return if id.blank?
    return if customer_id.blank?

    can action, klass, id: id, customer_id: customer_id
  end
```

```ruby
# app/concepts/role_grants/operation/update.rb
      def self.owner_only_grant?(subject_type, subject_key)
        type = subject_type.to_s
        return true if OWNER_ONLY_SUBJECT_TYPES.include?(type)
        return true if type == "Route" && FlowchartVisibility.controller?(subject_key)

        false
      end
```

```ruby
# app/concepts/roles/operation/seed_reserved.rb
        return if admin_role.role_permissions.exists? # idempotent

        Current.access_points_catalog = nil
        catalog = AccessPoints::Catalog.for(customer_id: customer.id)
```

```ruby
# app/controllers/concerns/route_authorization.rb
  def authorize_route!
    authorize! verb_action, route_subject
  end

  def verb_action
    VERB_TO_ACTION.fetch(request.method, :read)
  end

  def route_subject
    :"route_#{controller_path.tr('/', '_')}"
  end
```

```ruby
# app/models/role_permission.rb
  ACTIONS = %w[read create update destroy manage].freeze

  KEY_BASED_TYPES      = %w[Route Module FeaturePage Platform EntityClass PageClass].freeze
  INSTANCE_BASED_TYPES = %w[Entity Page].freeze
```
