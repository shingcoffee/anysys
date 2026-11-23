---
title: "客户"
summary: "平台所有者管理客户。域名是客户资料上的可选字段，与组织名称一起保存。新增域名须配置直接 CNAME，并支持回收站、恢复与客户代管。"
---

## 概要

`Admin::Maintenance::Platform::CustomersController` 是全部 `Customer` 的目录。创建、更新、软删除、回收站与清空回收站都在 `/admin/maintenance/platform/customers`。恢复由 `CustomerRestorationsController` 处理。切换租户由 `CustomerContextsController` 完成：它只做重定向，随后 `TenantContext` 按新的 URL 重建本次请求的客户。

`/81721200/admin/maintenance/platform/customers` 的 HTML 首页只显示客户表格。「客户」仍是唯一的平台侧栏入口。

域名是客户的可选属性，与组织名称在同一资料表单中编辑，并显示在资料页。见[自定义域名](custom-domains)。没有单独的域名管理页面。

平台所有者客户是 `Authentication::User::PLATFORM_CUSTOMER_ID`（`81721200`）。`Authentication::User#platform_owner?` 表示该客户上的 `owner?`。系统只有 `owner`、`admin`、`member` 三种保留角色，说明见 [租户与角色](tenancy-and-roles)。这个命名空间已由 `RouteAuthorization` 限制为 `platform_owner?`。

## 流程

```text
/81721200/admin/maintenance/platform/customers（客户表格）
        |
        |  RouteAuthorization：platform_owner?
        v
CustomersController
        |
        +-- index / show / edit / create / update
        |     Customer（8 位 id；show 使用 unscoped，其余使用 default_scope 可见行）
        |     after_create：角色／模块；after_create_commit：Billing::Onboarding
        |     HTML 首页：仅客户表格
        |     HTML 详情：组织资料（含域名）、主要联系人与账户
        |     HTML 编辑／资料更新 422：同一资料表单，包含域名
        +-- destroy -> Customer#soft_delete（status 变为 inactive；拒绝 81721200）
        +-- trash -> Customer.only_deleted
        +-- empty_trash -> Customers::Purge.call(customers: Customer.only_deleted)
        |
        v
CustomerRestorationsController#update -> Customer#restore

PATCH /:cid/admin/maintenance/platform/customer_context
        |
        v
重定向到 /:target_id/admin/dashboard
        |
        v
TenantContext#set_current_tenant
        |
        |  目标是其他租户，且当前用户 platform_owner?
        v
Current.platform_owner_context
Current.acting_as_customer
        |
        v
Platform::ContextBannerComponent
```

## 实现

`Customer` 引入 `SoftDeletable`，`deleted_status` 为 `:inactive`，并引入 `RandomIdGeneratable`，`digits` 为 `8`。`default_scope { visible }` 让列表不显示已停用的行。`status` 为 `active` 或 `inactive`。`tier` 为 `basic`、`standard`、`premium`、`enterprise`。`industry` 是从 `config/industries.yml` 载入的枚举。`locale` 可空，有值时必须属于 `I18n.available_locales`。

仅 `CustomersController#show` 使用 `Customer.unscoped.find`，因此平台所有者可以查看已停用客户的资料，包括域名。编辑、更新及删除仍使用默认作用域查找；停用客户的资料编辑／更新仍返回 404。

`after_create` 创建保留角色并开通必需模块；`Billing::Onboarding.call` 在创建提交后执行并恢复 Current。`skip_authentication_provisioner` 让公开注册分配真正管理员，见[身份认证](authentication)。

`customer_params` 允许 name／alias／domain／address／contact／phone／tier／industry／locale。列表使用 `ModuleEntriesResolver`。软删除及恢复检查实际结果；清空回收站将完整已删除集合交给 `Customers::Purge`，仅成功时报告真实数量。status／tier／role／industry 无效值通过校验反馈，不在赋值时抛错。

首页列为客户、客户编号、域名、用户、模块和创建时间。客户列显示组织名称和建筑标识，有简称时显示在名称下方。客户编号和域名使用等宽字体；未设置域名时显示破折号。用户和模块为右对齐的数量。创建时间显示相对时间，悬停可见精确时间。简称不再单独成列。搜索匹配名称、简称、域名和客户编号。回收站表格仍列出名称、简称、用户、模块和创建时间。

### 客户资料

详情与编辑使用 `AdminPageComponent`。详情渲染 `Platform::Customers::ProfileComponent`：主栏为组织资料与主要联系人，`xl` 起账户栏并列其旁。组织资料包含名称和可选域名。启用账户的页头显示状态与服务方案徽章，以及「编辑资料」和「移入回收站」。客户 `81721200` 没有「移入回收站」。停用账户改为「恢复」（`restoration_admin_maintenance_platform_customer_path`）及回收站提示；不提供编辑与移入回收站，因为停用账户的编辑／更新本就返回 404。资料不展示 `Customer#role`。

编辑 GET 及资料更新失败的 HTML 422 将 `CustomerFormComponent` 分成组织资料、主要联系人与服务方案。组织资料包含名称和可选的「域名」字段。表单还包含只读客户编号，不含角色控件。表单容器为 `w-full max-w-3xl`。保存表单时，`customers.domain` 与其他资料字段一起写入。见[自定义域名](custom-domains)。

中央平台路径检查对全部动作／格式要求实际外层 PATH_INFO CID 为 `81721200`，包含 JSON 及通配符 Accept。软删除保留域名绑定，停用时公开请求 404，恢复后重新路由，永久删除时随记录移除。

详情标题换行显示，不截断。编辑资料与移入回收站（停用账户则为恢复）在小屏幕上纵向排列。较长的名称和域名会换行。两种语言都使用成对的 I18n 文案和原生控件。



`CustomerContextsController#search` 最多返回 20 条 `{ id, name }`，有查询词时用 `lower(name) LIKE` 过滤。`#update` 从 POST 正文的 `customer_id`，或正文／查询中的 `target_customer_id` 读取目标客户，再重定向到 `/:id/admin/dashboard`。路径段保持 `81721200`。「代管」链接为 `/81721200/admin/maintenance/platform/customer_context?target_customer_id=<id>`。`#destroy` 调用 `clear_platform_owner_context`，再重定向到当前用户自己的 `/admin/dashboard`。`Platform::ContextBannerComponent` 用 DELETE 回到同一条 `81721200` 路径。`TenantContext#set_current_tenant` 用路径第一段 8 位数字加载客户。当该客户不是用户所属客户时，只有 `platform_owner?` 可以继续，并进入 `setup_platform_owner_context`。`Current` 在这一次请求里保存 `platform_owner_context`、`original_customer` 与 `acting_as_customer`。`Platform::ContextBannerComponent` 在 `Current.platform_owner_context?` 时渲染。

侧栏入口在 `MaintenanceContributor`，仅当 URL 客户为 `81721200` 且 `current_user.platform_owner?` 时出现。见 [仪表盘](dashboard)。


## 需要特别注意

### 路由审计：归属感知清理及真实生命周期结果

`Customers::Purge.call(customers:, delete_customers: true)` 返回 `success?`、`deleted_count`、依赖计数及错误码。它绕过默认作用域枚举客户自有行，跟踪数据库及逻辑版本／内容／头关联，以及多态附件／富文本，置空内部指针并在一个事务中按依赖顺序删除。存活的外租户依赖阻止整次操作；保留共享父记录、平台凭证及存活版本线引用的内容。直接销毁 Customer 也使用同一自有记录清理。

此处是主数据库清理，不是厂商撤销或存储文件删除保证；SQL 删除不会运行每个子记录的回调，外部收尾须核对未完成财务／厂商工作。URL 代管仍限单次请求；[账单](billing)历史规则及[共享资源](shared-resources)归属是独立约束。

:::note
清理、枚举、恢复及平台路径回归测试已编写，本次未执行。没有实际依赖／schema 或存储清理运行证据。
:::

:::attention
客户查找前执行中央角色及实际外层路径检查。所有者身份不能授权其他 CID 的平台前缀，嵌套恢复目标及正文／查询值不能替代 `81721200`。见[租户与角色](tenancy-and-roles)。
:::

:::attention
`CustomersController#customer_params` 不包含 `:role`。客户详情页与 `CustomerFormComponent` 不再展示或编辑 `Customer#role`。该列仍留在 `Customer` 上。真正参与授权的三种保留角色是 `Authentication::User#owner?`、`#admin?` 与 `#member?`，通过 `UsersRole` 分配。
:::

:::attention
软删除与永久清理不同。完整归属集合可删除时清空回收站才成功；恢复检查校验结果，不再无条件提示成功。`Customer#soft_delete` 拒绝客户 `81721200`。`Customers::Purge` 在要求删除客户（清空回收站）时保留该行。硬删除前的附属清理仍会执行。恢复为 `PATCH /:cid/admin/maintenance/platform/customers/:id/restoration`，外层 `:customer_id` 与回收站客户的 `:id` 分开。
:::

:::attention
代管其他租户靠的是 URL，状态只放在当次请求的 `Current` 上。`CustomerContextsController#update` 只做重定向。之后若再访问 `/81721200/...`，因为 `signed_in_other_tenant?` 对所有者自己的客户为假，`platform_owner_context` 会回到 false。
:::

## 关键代码

```ruby
# app/controllers/admin/maintenance/platform/customers_controller.rb
def customer_params
  params.require(:customer).permit(
    :name,
    :alias,
    :domain,
    :address,
    :contact,
    :phone,
    :tier,
    :industry,
    :locale
  )
end
```

```ruby
# app/controllers/concerns/tenant_context.rb
def set_current_tenant(customer_id, required)
  return unless customer_id.present?

  customer = Customer.find_by(id: customer_id)

  if customer && signed_in_other_tenant?(customer) && route_protection_required?
    return render_tenant_forbidden_error unless current_user.platform_owner?

    setup_platform_owner_context(customer)
  else
    Current.customer = customer
    clear_platform_owner_context
  end

  render_tenant_not_found_error(customer_id) if required && Current.customer.nil?
end
```

```ruby
# app/models/authentication/user.rb
PLATFORM_CUSTOMER_ID = 81_721_200

def platform_owner?
  owner? && eligible_for_owner_role?
end
```

```ruby
# app/controllers/admin/maintenance/platform/customer_restorations_controller.rb
class CustomerRestorationsController < BaseRestorationsController
  restorable finder: -> { Customer.only_deleted.find(params[:id]) },
             redirect: -> { admin_maintenance_platform_customers_path(current_customer_id) },
             flash_key: "maint_platform.flash.customers.restored"
end
```
