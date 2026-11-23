---
title: "认证模块"
summary: "必选功能模块，负责租户用户、注册设置与角色授权，与平台登录栈并列。"
---

## 概要

`FeatureModules::Authentication::Registration` 是键为 `authentication` 的功能模块。它被标成必选：每个客户都保留它，维护页上的开关不能关掉它。启用时会准备第一个用户。之后客户管理员管理用户与审计流水，并编辑自助注册、找回密码、角色和授权。

登录、Devise、MFA 会话和路由守卫属于 [authentication](authentication) 上的平台栈。已保存的授权如何变成 CanCan 规则见 [access-grants](access-grants)。本页只写模块注册和四个管理面。注册基类见 [module-framework](module-framework)。

## 配置核对表

在 `/81721200/admin/maintenance/platform/module_settings/authentication` 设置全局客户注册开关。租户设置分别控制会员注册、密码重置、MFA、正整数会话超时分钟及失败次数上限。`Authentication::Settings` 与 `User::TenantSecurityPolicy` 按账户执行后两项，缺失／无效／未启用值回退到 Devise 默认。Anysys 自行签发第一方令牌，见 [OAuth](oauth)。

## 流程

```text
创建客户 / 启用模块
        |
        v
FeatureModules::Authentication::Provisioner
        |  该客户已有 Authentication::User 则直接返回
        |  平台客户 81721200 -> owner 角色 + 固定邮箱
        |  其他客户 -> admin 角色
        v
customer_feature_modules.configuration
        |
        +-- allow_registration       SignUpController
        +-- allow_password_reset     ForgetPasswordController
        +-- mfa_enabled              ModuleConfigsController
        |                            ModuleSubTogglesController
        +-- session_timeout          ModuleConfigsController -> 账户 timeout_in
        +-- max_login_attempts       ModuleConfigsController -> Lockable 钩子
        v
Authentication::Settings
        |  注册／重置／MFA 开关 + timeout_in / maximum_attempts
        v
公开的 Devise 控制器与 Authentication::MfaObligation
```

模块没有 `before_request`。管理端和成员端的登录检查留在 `RouteAuthorization`。租户 MFA 留在 `Authentication::EnforcesMfa`，它读取 `Authentication::Settings`。

## 实现

### 注册

`module_key` 为 `"authentication"`。`mandatory!` 让每次 `register!` 都把 `FeatureModules::Module` 行写成 `active` 且 `required`。`entry_path` 是 `/auth/sign_in`。`default_exit` 是路由 `customer_home`。

`configuration_schema` 暴露 `mfa_enabled`（默认 false）、`session_timeout`（默认 30）和 `max_login_attempts`（默认 10）。`configuration_keys` 就是这三项，因此 `Admin::ModuleConfigsController` 可以写它们，不能写 `allow_registration` 或 `allow_password_reset`。后两个键只由各自的控制器写入。

### 四个面

| 面 | 路径 | 控制器 |
| --- | --- | --- |
| 条目 | `/:cid/admin/modules/authentication/users` 与 `/events` | `Admin::Modules::Authentication::UsersController`、`UserActivationsController`、`UserMfaResetsController`、`UserTrustedDevicesController`、`EventsController` |
| 客户设置 | `/:cid/admin/settings/modules/authentication` | MFA、超时、锁定次数走 `Admin::ModuleConfigsController`；另有 `SignUpController`、`ForgetPasswordController`、`RolesController`、`RoleGrantsController`、`UserRoleAssignmentsController` |
| 启用 / 停用 | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController` 会列出它；因模块为 required，`ModuleEnablementsController#destroy` 拒绝停用 |
| 平台设置 | `/:cid/admin/maintenance/platform/module_settings/:id` | `Admin::Maintenance::Platform::ModuleSettingsController`（没有独立的 authentication 命名空间） |

`SettingsContributor#module_path` 把这个模块的通用设置段保持为单数（`.../authentication`）。设置表单提交到 `key.pluralize`（`.../authentications`）。`ModuleConfigsController#resolve_module_key` 接受复数段并还原成单数。侧栏高亮同时覆盖两条路径。

`UsersController` 按 `current_customer_id` 列出用户。仅当目标角色为 member 时，在客户锁内检查账单 `member` 配额，再分配保留角色。owner 必须符合固定邮箱／客户身份。激活、重置 MFA 及设备动作使用同一租户用户范围。审计模型没有 `TenantScoped`，`EventsController` 必须使用 `Authentication::Event.for_customer`。用户表单从绑定的 `@user` 回填 `first_name`、`last_name` 和 `email`。校验失败后重新渲染时，若提交了 `authentication_user[role]`，角色下拉框会显式选中该值；否则根据 `@user.primary_role_key` 选中用户的保留角色，新用户默认为 `member`。校验失败后重试会保留已提交的非密码字段值。密码及确认密码字段始终留空；编辑时两者均留空则保留原密码。

`SignUpController` 写入 `allow_registration`。`ForgetPasswordController` 写入 `allow_password_reset`。两者都调用 `CustomerAssignment#merge_configuration!`。分配缺失或未激活时，`Authentication::Settings` 的对应谓词为 false；注册默认关，找回密码默认开。

`RolesController` 经 `Roles::Operation::Create` 创建附加自定义角色，保留角色授权仍锁定。`RoleGrantsController` 读取客户目录并应用新增／移除授权。分配／移除及单用户编辑器经 `Authentication::MutationAudit.roles` 记录实际 `role_granted`／`role_revoked` 差集，控制器不再重复产生成功事件。见[访问授权](access-grants)。

本模块的平台配置就是共用的概览、配置、开发者三个窗格。仅当模块键为 `authentication` 时，`apply_customer_signup!` 写入 `Authentication::PlatformSettings#allow_customer_signup`。这个单例开关控制公开的客户注册（`Authentication::CustomerRegistrationsController`）。它和租户自己的 `allow_registration` 不是一回事，后者控制 `/:cid/auth/sign_up` 上的 `Authentication::RegistrationsController`。

### 开通与回收

客户已有任意 `Authentication::User` 时，`Provisioner.call` 立即返回。否则创建已确认、状态为 active 的用户。客户 `81721200` 使用 `Authentication::User::PLATFORM_OWNER_EMAIL` 和系统角色 `owner`。其他客户在 `customer.contact` 是邮箱时用它，否则用 `admin@<参数化名称>.local`，角色为系统 `admin`。邮箱已被占用时，本地部分加上 `+<customer.id>`。平台所有者邮箱不会被改写。

`Deprovisioner.call` 把该客户所有 active 用户改成 `inactive`。它不删除行。

## 需要特别注意

### 路由审计：有效配置与用户修改

`ForgetPasswordController#update` 对省略／空白／仅含空格的 `enabled` 保存 false，保留其他配置；存储缺键默认 true。注册／MFA 默认 false。超时／次数按账户执行，已加载 User 也能读取策略修改，Devise 类默认保持不变。

资料与保留角色更新纳入同一事务；owner 身份／分配不可降级，拒绝自行停用及自行管理端 MFA 重置。创建 member 消耗[账单](billing)会员计数，创建 admin 不消耗。见[身份认证](authentication)及[访问授权](access-grants)。

:::note
重置开关、管理端用户及角色分配回归测试已编写，本次未执行。附加角色 CRUD 是既有界面，没有增加保留角色。
:::

:::attention
`FeatureModules::Authentication::Registration` 调用了 `mandatory!`。`Admin::Maintenance::ModuleEnablementsController#destroy` 在 `feature_module.required?` 时直接返回。`Admin::Maintenance::Platform::ModuleSettingsController` 的 `#apply_status!` 与 `#apply_required!` 对必选模块立即返回。若仍有代码调用 `FeatureModules::Authentication::Deprovisioner`，它会把用户标成 `inactive`。随后 `FeatureModules::Authentication::Provisioner` 只要发现已有用户行就返回，这些用户会一直保持未激活。回收器注释里“重新启用会激活他们”与 `Provisioner` 的实现不一致。
:::

:::attention
租户 MFA 适用于 admin／owner，member 自愿登记。`Settings#timeout_in(default:)` 与 `#maximum_attempts(default:)` 接受大于零的 JSON 整数或十进制整数字符串，无效值继承当前类默认。User 实例钩子不把租户策略写入 Devise 全局配置。
:::

:::attention
`FeatureModules::Authentication::Registration` 写明自己没有每次请求的钩子。注册类上曾经有过第二道 MFA 门，后来与 `Authentication::EnforcesMfa` 分叉。管理端和成员端的登录检查留在 [authentication](authentication)。不要在这里用 `before_request` 再判一次 MFA。
:::

:::attention
`RoleGrants::Operation::Update` 拒绝 `locked_grants` 的角色。主体类型 `Platform`，以及 `FlowchartVisibility.controller?` 认可的 `Route` 键，只有 `actor.owner?` 才能添加。实例授权（`Entity` 或 `Page`）必须属于 `role.customer_id`。编辑界面在本模块。消费 `RolePermission` 行的运行时见 [access-grants](access-grants)。
:::

## 关键代码

```ruby
# app/services/feature_modules/authentication/registration.rb
mandatory!

def self.configuration_keys
  %i[mfa_enabled session_timeout max_login_attempts]
end

def self.provision!(customer)
  FeatureModules::Authentication::Provisioner.call(customer)
end

def self.deprovision!(customer)
  FeatureModules::Authentication::Deprovisioner.call(customer)
end
```

```ruby
# app/services/feature_modules/authentication/provisioner.rb
def self.call(customer)
  return if ::Authentication::User.where(customer_id: customer.id).exists?

  platform_owner_customer = customer.id == ::Authentication::User::PLATFORM_CUSTOMER_ID
```

```ruby
# app/services/authentication/settings.rb
def signup_enabled?
  module_active? && bool(config["allow_registration"], default: false)
end

def password_reset_enabled?
  module_active? && bool(config["allow_password_reset"], default: true)
end

def mfa_enabled?
  module_active? && bool(config["mfa_enabled"], default: false)
end
```

```ruby
# app/concepts/role_grants/operation/update.rb
OWNER_ONLY_SUBJECT_TYPES = %w[Platform].freeze

def self.call(role:, added: [], removed: [], actor: nil)
  return Result.new(success?: false, model: role,
                    errors: { base: [I18n.t("auth.errors.role_grants_locked")] }) if role.locked_grants?
```
