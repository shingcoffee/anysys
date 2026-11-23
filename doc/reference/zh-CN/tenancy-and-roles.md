---
title: "租户与角色"
summary: "八位客户编号、Current，以及三种保留角色如何决定已登录用户可以打开哪一类 URL。"
---

## 概要

每个租户是一条 `Customer` 记录，主键为随机生成的八位数字。请求进入控制器之前，这个编号会写入 `Current`。授权只认 `Authentication::User` 上的三种保留角色：`owner`、`admin`、`member`，再叠加路径前缀。`platform_owner?` 表示客户 `81721200` 上的所有者，`/admin/maintenance/platform` 与流程图都由这个谓词放行。

另外还有可编辑的 `roles`、`users_roles`、`role_permissions`。这些行不会变成第四种保留角色，也不能取代路径门槛。授权矩阵见 [访问授权](access-grants)。

## 流程

```text
GET /:cid/...                         path_info，首段为 8 位数字
        |
        v
TenantContext#auto_set_tenant_from_path
        |
        |  Customer.find_by(id:)
        |  受保护路由，已登录且不是本租户？
        |       platform_owner? -> Current.platform_owner_context
        |       其他人           -> LandingPath（拒绝）
        v
Current.customer / Current.user
        |
        v
RouteAuthorization   （仅 /:cid/admin 或 /:cid/member）
        |
        |  1. authenticate_user!
        |  2. enforce_route_role!
        |       平台或流程图命名空间 -> platform_owner?
        |       /admin              -> admin_or_owner?
        |       /member             -> member?
        |         GET/HEAD 且 allow_admin_member_preview! -> admin_or_owner?
        |  3. authorize_route!  -> Ability
        v
Authentication::EnforcesMfa
        |
        v
控制器动作
```

公共 URL 不经过受保护路由授权，允许其他租户的已登录访客访问。租户仍由 URL／主机确定；发布、页面受众及协议验证按动作执行。登录见[身份认证](authentication)。操作路由器 `GET /:cid/actions/:action_key` 属于公开 URL，见[受众流程](audience-flows)。

[页面快捷路径](page-shortcuts) 在没有客户前缀时，还可根据数据库中的精确 `customers.domain` 绑定或默认客户 81721200 选择公开租户。显式客户前缀优先；绑定客户停用时返回 404，不回退。可信路由上下文调用现有 `set_current_tenant` 门禁；会话状态及表单／查询中的客户字段不决定目标。快捷路径管理位于 `/:cid/admin/maintenance/page_shortcuts`，仅允许 admin／owner，所有者也须按该 URL 客户限定记录。

[自定义域名](custom-domains)是客户资料的可选属性，不是另一种路由／授权主体。所有受保护平台动作及格式均要求实际外层 PATH_INFO CID 为 `81721200`，所有者也不例外。新增／变更域名须配置直接指向 `anysys.net` 的 CNAME，不会放宽 admin／member 归属检查。见[客户](customers)。

## 实现

### 客户编号

`Customer` 引入 `RandomIdGeneratable`，并设置 `random_id digits: 8`，新建编号落在 `10000000` 到 `99999999`。`TenantContext::TENANT_PATH_PATTERN` 以及 `RouteAuthorization` 的管理端、成员端正则都要求恰好八位。平台客户是固定编号 `Authentication::User::PLATFORM_CUSTOMER_ID`（`81_721_200`）。

`Customer` 另有 `enum :role`，取值为 `owner`、`admin`、`member`。这是租户资料上的一列。公开注册在 `Authentication::CustomerSignup` 里写成 `role: :admin`。应用代码没有用 `Customer#owner?`、`Customer#admin?` 或 `Customer#member?` 来放行请求。`RouteAuthorization` 使用的谓词在 `Authentication::User` 上。

创建客户时会调用 `Roles::Operation::SeedReserved`，再执行 `enable_required_feature_modules`：把每条 `FeatureModules::Module.required` 记录激活，并运行该模块的 `provision!`。`app/services/feature_modules` 里注册的七个模块键是 `authentication`、`payment`、`email`、`sms`、`captcha`、`ai_assistant`、`website`。只有 `FeatureModules::Authentication::Registration` 调用了 `mandatory!`。模块开关见 [模块框架](module-framework)。

### 请求中的租户

`ApplicationController` 最先引入 `TenantContext`。`auto_set_tenant_from_path` 匹配 `request.path_info`，不是带 `SCRIPT_NAME` 的 `request.path`。受保护路由上，已登录用户所属客户与 URL 不同时：

- `platform_owner?` 把 `Current.customer` 设为 URL 上的租户，`Current.platform_owner_context` 设为 true，`Current.original_customer` 设为所有者自己的客户，`Current.acting_as_customer` 设为 URL 租户。`ApplicationController#platform_elevated_access?` 是这个标志再加上 `platform_owner?`。
- 其他已登录用户由 `render_tenant_forbidden_error` 重定向到 `Authentication::LandingPath.for(current_user)`。
- 匿名请求不算「进入别人的租户」。`Current.customer` 就是 URL 中的客户，后面的过滤再决定要不要登录。

`Authentication::User` 和各定义模型引入的 `TenantScoped` 是 `belongs_to :customer, optional: true`。创建时若行上还没有客户，就复制 `Current.customer_id`。`Current.shared_resources_mode` 与 `skip_tenant_customer_assignment!` 会把 `customer_id` 留空，以便保存共享行。共享的页面、流程图、实体通过 `Versionable#resolved_current_version` 读取：有该客户的覆盖头就用覆盖，否则用全局默认。租户路径上的保存写入的是这份覆盖。共享行本身只在平台前缀上修改。详见 [共享资源](shared-resources)。

`Current.page_shortcuts_lookup` 是仅供展示使用的单客户不可变身份快照，由公开网站／Page 控制器的 around-action 设置。公开链接辅助方法仅在快照客户编号与显式参数一致时使用它；路由和授权不从中推断租户。渲染／提交后恢复原值，请求之间重置。见 [页面快捷路径](page-shortcuts)。

直接设置 `Current` 的隔离测试使用 `after { Current.reset }` 收尾，即使断言失败也会清理上下文。不要用 `Current.customer_id = nil` 清理：编号设置方法忽略空值，会保留之前的租户。

### 保留角色

设置租户的服务测试应使用块作用域 `Current.set`，在每个用例结束后恢复上下文，刻意切换租户的用例也一样。AI 回复／取消测试遵循此边界。验证真实提交的测试不能依赖夹具回滚：`spec/jobs/billing/finalize_invoice_job_spec.rb` 仅追踪并销毁为手动结算新建的平台客户／所有者，保留已有所有者的凭据与记录。平台上下文、公开路径及 HomeSite 夹具仍自行创建客户 `81721200`；意外存在的同编号记录仍视为隔离失败。

`Authentication::User::RESERVED_ROLE_KEYS` 为 `owner`、`admin`、`member`。`owner?`、`admin?`、`member?` 在 `reserved_role_keys` 包含对应键时为真。`reserved_role_keys` 来自关联 `Role` 中 `system: true` 的 `key`。`primary_role_key` 按同一顺序查找，没有任何保留角色时回落到 `"member"`。

`admin_or_owner?` 即 `admin? || owner?`。`platform_owner?` 为 `owner? && eligible_for_owner_role?`：客户为 `81721200`，邮箱忽略大小写后为固定值 `lingercoffee@gmail.com`。持久化后不能改变 owner 身份或分配。

`UsersRole` 拒绝把系统角色 `owner` 授给 `eligible_for_owner_role?` 不为真的用户，也拒绝客户编号与用户不一致的角色。`Roles::Operation::SeedReserved` 为每个客户创建这三个系统角色，且 `locked_grants: true`。`FeatureModules::Authentication::Provisioner` 只在该客户还没有用户时创建第一位用户：客户 `81721200` 授予 `owner`，其他客户授予 `admin`。公开注册会设置 `skip_authentication_provisioner`，并自行授予 `admin`，因此不会再生成一个占位管理员。

`Authentication::LandingPath` 在 `primary_role_key == "member"` 时指向 `member_dashboard_path`，否则在有客户编号时指向 `admin_assistant_path`。没有任何角色行的用户会落到成员端，随后被 `enforce_route_role!` 拒绝。

### 三类 URL

`RouteAuthorization` 由 `ApplicationController` 引入，是唯一的前缀门槛。这些前缀下的控制器不再单独添加 `authenticate_user!` 或角色 `before_action`。

| 路径 | 能通过 `enforce_route_role!` 的人 |
| --- | --- |
| `/:cid/admin/maintenance/platform`，以及控制器路径以 `admin/maintenance/platform/` 开头 | `platform_owner?` |
| `/:cid/admin/maintenance/flowcharts`，以及 `FlowchartVisibility.controller?` 命中的控制器（路径中含 `flowchart`） | `platform_owner?` |
| `/:cid/admin/maintenance/entity_domains`、`.../entities/:id/domain_membership`，以及 `EntityDomainVisibility.controller?` 命中的控制器 | `platform_owner?` |
| 其他 `/:cid/admin` | `admin_or_owner?` |
| `/:cid/member` | `member?`。控制器调用过 `allow_admin_member_preview!` 时，同一租户的 `admin_or_owner?` 可以 `GET` / `HEAD` |
| 其余路径 | 不做角色过滤 |

当前调用 `allow_admin_member_preview!` 的是 `Member::PagesController` 与 `Member::SurfacesController`。写操作仍只允许成员。跨租户仍由 `TenantContext` 拦截。角色检查之后，`authorize_route!` 调用 CanCan 的 `authorize!`：动词映射为 `:read`、`:create`、`:update` 或 `:destroy`，主体为 `:"route_#{controller_path}"`（斜杠换成下划线）。CanCan 用 `Ability.new(current_user)` 构建能力对象。规则内容见 [访问授权](access-grants)。

侧栏、助手提及和编辑器链接使用 `FlowchartVisibility.allowed?`，它同样是 `platform_owner?`。HTTP 拒绝仍发生在 `RouteAuthorization`，流程图控制器上不要再加一道角色过滤。实体业务域通过 `EntityDomainVisibility` 采用同一模式。`OwnerOnlySurfaces` 汇总这两类入口，是 `RouteAuthorization`、`Ability` 拒绝规则、`AccessPoints::RouteProvider` 与 `RoleGrants::Operation::Update` 共同读取的唯一清单；新增仅所有者可用的入口时加在这里。详见[实体构建器](entity-builder)。

仪表板的 `MenuRegistry` 使用 `platform_owner?` 控制桌面菜单和移动端抽屉中的顶级「维护」入口。租户管理员看不到此入口，客户 `81721200` 的管理员也一样；导航可见性不改变租户维护 URL 现有的 `admin_or_owner?` 授权。详见[仪表板](dashboard)。

HTML 的 `CanCan::AccessDenied` 会重定向到 `Authentication::LandingPath`。若该地址正是刚刚被拒绝的路径，则返回纯文本 `403`，避免重定向循环。JSON 为 `{ error: "access_denied" }`，状态 `403`。

成员记录还有第三层：`Member::BaseController#authorize_owned!` 在 `customer_id` 不符，或记录带有 `user_id` 但与 `current_user.id` 不符时抛出 `ActiveRecord::RecordNotFound`。见 [成员与公共页面](member-and-public)。

## 需要特别注意

### 路由审计：路径、操作者及归属不变量

`enforce_platform_path_identity!` 读取外层八位 PATH_INFO 段，不受嵌套客户 ID、查询／正文及挂载前缀影响。错误平台前缀对 HTML／JSON 均返回 404。外租户公共会话不决定目标租户；`current_tenant_user` 仅在用户客户与 URL 租户一致时返回用户，所有者也一样。保存卡片／会员归属应使用此方法。

会员预览另要求 `current_user.customer_id == current_customer_id`，所有者跨租户权限不扩大预览。公开字段权限使用 `EntityAttributeAudience.for_user(user, customer_id:)`，仅允许同租户角色或固定所有者，外访客仍为 public。保留连接原位替换，不可单独移除；已挂载账户创建原子分配唯一角色，直接 User 创建由底层调用方负责。见[访问授权](access-grants)、[支付](payments)、[会员与公开页面](member-and-public)。

:::note
路径、挂载／格式、公共受众及角色边界已按源码记载。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。超出该套件的运行验收仍须各自的证据。
:::

:::attention
`Authentication::User#platform_owner?` 要求 owner 及固定客户／邮箱身份，客户 `81721200` 的 admin 不满足。中央角色过滤与平台路径身份检查是两道不同边界。
:::

:::attention
`TenantContext#tenant_path` 与 `RouteAuthorization#authorization_path` 必须使用 `request.path_info`。`request.path` 会带上 `SCRIPT_NAME`。应用挂在子路径下时，`TENANT_PATH_PATTERN` 和管理端、成员端正则都会落空，`Current.customer` 不会设置，`/:cid/admin` 也会跳过认证。
:::

:::attention
`RouteAuthorization.allow_admin_member_preview!` 只在 `request.get?` 或 `request.head?` 时放行 `admin_or_owner?`。同一成员控制器上的 `POST`、`PATCH`、`PUT`、`DELETE` 仍然要求 `member?`。目前树里的接入点是 `Member::PagesController` 与 `Member::SurfacesController`。
:::

:::attention
`UserRoles::AssignmentPolicy` 与 `Authentication::OwnerIdentity` 保护 owner 分配及身份。资格同时要求客户 `81721200` 与邮箱 `lingercoffee@gmail.com`；`Customer#role` 不参与请求授权。
:::

:::note
`ApplicationController` 最后才引入 `Authentication::EnforcesMfa`，因此它排在 `RouteAuthorization` 之后。多因素本身见 [身份认证](authentication)。
:::

## 关键代码

```ruby
# app/models/authentication/user.rb
    PLATFORM_CUSTOMER_ID = 81_721_200
    PLATFORM_OWNER_EMAIL = "lingercoffee@gmail.com"

    # Check if user belongs to platform owner customer (81721200) with owner role.
    # These users can access platform-wide management features.
    def platform_owner?
      owner? && eligible_for_owner_role?
    end

    # The owner role is reserved for a single, specific user. See AGENTS.md
    # "Reserved Roles & Access Rules". Used by UsersRole to gate assignment.
    def eligible_for_owner_role?
      customer_id == PLATFORM_CUSTOMER_ID &&
        email.to_s.downcase.strip == PLATFORM_OWNER_EMAIL
    end
```

```ruby
# app/controllers/concerns/route_authorization.rb
  def enforce_route_role!
    if platform_namespace? || flowchart_namespace?
      return if current_user.platform_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
    end

    if admin_path?
      return if current_user.admin_or_owner?
      raise CanCan::AccessDenied, t("common.errors.authorization.admin_required")
    end

    if member_path?
      return if current_user.member?
      return if admin_member_preview_allowed && (request.get? || request.head?) &&
                current_user.admin_or_owner? && current_user.customer_id == current_customer_id

      raise CanCan::AccessDenied, t("common.errors.authorization.member_required")
    end
  end
```

```ruby
# app/controllers/concerns/tenant_context.rb
    if customer && signed_in_other_tenant?(customer) && route_protection_required?
      return render_tenant_forbidden_error unless current_user.platform_owner?

      setup_platform_owner_context(customer)
    else
      Current.customer = customer
      clear_platform_owner_context
    end
```

```ruby
# app/services/user_roles/assignment_policy.rb
UserRoles::AssignmentPolicy.validate(join)
UserRoles::AssignmentPolicy.removable?(join)
```

```ruby
# app/models/concerns/versionable.rb
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || current_version
  end
```
