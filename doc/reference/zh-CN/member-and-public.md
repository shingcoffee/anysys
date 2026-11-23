---
title: "会员与公开页面"
summary: "/:cid/member 下的会员入口，以及 /:cid/page/:uuid 的公开页面，包括管理员对会员页面的只读预览。"
---

## 概要

会员 URL 位于 `/:customer_id/member/`。`RouteAuthorization` 放行 `current_user.member?`。`Member::BaseController` 用 `authorize_owned!` 检查记录的 `customer_id`；记录若响应 `user_id`，还必须是当前用户。`Member::PagesController` 与 `Member::SurfacesController` 调用了 `allow_admin_member_preview!`，因此同一租户的管理员或所有者可以用 GET 打开会员渲染或会员界面。

`PublicPagesController` 提供 `/:customer_id/page/:uuid`。GET 只渲染已发布且受众集合含 `public` 的页面。POST 要求访问者受众在集合中，再把浏览器送回该受众界面。`GET /:customer_id/actions/:action_key` 是公开操作路由器。页面如何变成 HTML 见 [页面渲染](page-rendering)。报名模式见 [受众流程](audience-flows)。登录与三种角色见 [身份认证](authentication) 与 [租户与角色](tenancy-and-roles)。

## 流程

```text
GET /:cid/member
        |
        |  RouteAuthorization：member?
        |  例外：allow_admin_member_preview! 且为 GET/HEAD
        |        且 admin_or_owner?（同一租户；TenantContext）
        v
Member::BaseController  （布局 "member"）
        |
        +-- DashboardsController     GET /:cid/member
        +-- ProfilesController       资料的 show / edit / update
        +-- SecuritiesController     安全页 show
        +-- MfaController            只操作 current_user 的 setup 与 destroy
        +-- TrustedDevicesController 撤销自己的设备
        +-- PagesController          已发布且集合含 member 的页面
        +-- Payments::*              自己的卡片与卡片订阅
        +-- SurfacesController       /:cid/member/:key（不含内建项）
        +-- 页面来源链接              /:cid/member/pages/:id（启用后）

GET  /:cid/actions/:key Pages::ActionsController#show
        |  重定向到 page_runtime_audience 对应页
GET  /:cid/page/:uuid   PublicPagesController#show
        |  已发布且集合含 public，否则 404
        |  对应页 -> 303
POST /:cid/page/:uuid   PublicPagesController#submit
        |  访问者受众；否则按拒绝顺序
        v
公开页 | 会员页 | 管理端填写页
```

## 实现

公开表单还可使用指定别名，包括根路径和多级路径，在 `/:cid/admin/maintenance/page_shortcuts` 管理。发布卡片优先显示按主机生成的有效别名，否则显示规范 UUID 地址。GET/HEAD 及公开表单 POST 别名保留发布、公开受众检查、租户及提交授权；生成的表单仍向规范 UUID 端点提交。[自定义域名](custom-domains)是客户资料上的可选域名，实时读取，显式客户前缀优先，默认客户为 81721200；停用客户返回 404。保存新增或变更的域名时，须配置该域名直接指向 `anysys.net` 的 CNAME；失败则这次保存不写入，清空域名不检查 DNS。部署负责发布 DNS，并分别管理 TLS／入口路由／HostAuthorization。见 [页面快捷路径](page-shortcuts)。

`Member::BaseController` 使用布局 `member`。布局通过 `Websites::Theme` 读取该客户的 `Website#theme`，与 `/:cid/site` 使用同一套令牌。客户还没有网站时，采用公开站点的默认值（浅色、天蓝、无衬线、宽松）。外壳是吸顶顶栏、移动端菜单和简短页脚：站点字体、强调色按钮和细线卡片。

`Member::DashboardsController#show` 对应 `resource :dashboard, path: ""`，因此会员根路径就是仪表盘。它按小时问候，并列出最近的登录时间。`ProfilesController` 通过 `Member::Profiles::UpdateContract` 更新 `current_user`，允许 `:first_name`、`:last_name`、`:email`、`:current_password`。`SecuritiesController#show` 读取 `mfa_required?`、上次登录，以及 `trusted_devices.active`。`MfaController` 引入 `Authentication::MfaEnrollment`，用 `current_user` 与 `params[:code]` 调用 `Member::Mfa::Operation::Enable` 和 `Disable`。它不接收目标用户 id。`TrustedDevicesController#destroy` 通过 `current_user.trusted_devices` 查找设备。

`Member::PagesController#show` 加载 `Page.accessible.launched`，集合不含 `member` 则抛出 `RecordNotFound`。仅面向公开的页面不是会员页。预览开关不会放宽这一检查。

`Member::Payments::PaymentMethodsController` 与 `SubscriptionsController` 调用 `require_payments_module!`（`"payment"` 的 `FeatureModules::Module.enabled?`，否则 `head :not_found`）。它们的注释写明这不是预览界面。支付方式使用 `for_current_customer` 与 `for_user(current_user.id)`，列表只取 `chargeable` 行。`setup_intent` 以提供商 `"stripe"` 调用 `Payments::Activities::VaultCard`。`destroy` 调用 `Payments::Gateway.detach_token` 与 `mark_removed!`。若 `detach_token` 抛出 `Payments::Errors::Error`，动作仍然 `mark_removed!`，并以已移除的提示重定向。订阅没有 `user_id`；查询通过当前用户拥有的 `Payments::PaymentMethod` 连接。`payment_method_id` 为空的非卡片订阅不在此列表中。`SubscriptionCancellationsController#create` 调用 `Payments::Activities::CancelSubscription`。网关行为见 [支付](payments)。

`Member::SurfacesController` 加载 `Member::Surfaces.fetch`，界面被停用或描述对象是 `Member::Sources::BuiltinSurface` 时返回 404。内建的首页、资料与安全页就是上面那些专用控制器。`Member::Sources::Builtin::ENTRIES` 指向这些路径。路由把 `namespace :payments` 写在 `resources :surfaces, path: ":key"` 之前，避免 `:key` 吃掉 `/payments`。index 与 show 用 `current_user` 调用 `index.scope`。show 再经 `authorize_surface_record!`：`EntityEntry` 只需匹配 `current_user.customer_id`（报名等归属行本身没有 `user_id`）；其他记录仍走 `authorize_owned!`。`Entities::EntryDisplay.prime!` 按会员受众与已登录访问者挂上标签。

### 实体界面

`Member::Sources::Entities` 列出租户自有实体与对该租户仍可见（默认 scope）的共享实体（`customer_id` 为 NULL）。**private** 实体、已进回收站的实体、以及不是 `:owned` 的桥接实体不产生界面。人员与归属实体（含归属的 Enrollment 类桥接）默认开启；开放实体默认关闭，管理员打开后列出本租户全部行（目录）。

`Member::Surface#default_enabled?` 在 `default_enabled` 不是 `false` 时为真。`member_surface_settings.enabled` 可空、无默认值：nil 表示继承。`SurfaceSetting#enabled_or(default)` 与 `NullSurfaceSetting#enabled_or(default)` 取代裸 `enabled?`。`Member::EffectiveSurface#enabled?` 为 `@settings.enabled_or(@descriptor.default_enabled?)`。仅改覆盖（改标签、未提交 `enabled`）的保存保持 nil，沿用默认。

`Member::EntitySurfaceBuilder.call(entity:, customer:)` 始终用 `People::Ownership.scope(..., audience: "member", viewer: user)` 限定范围。因此管理员预览也只能看到关联到自己的行。索引列、详情行与搜索都略去 Calculated 属性、`visibility.member: false` 的属性，以及归属引用（它始终是当前会员）。`enabled_for` 比较 `user.customer_id` 与所访 `customer.id`，共享实体仍按访问者租户把关。见[人员关联](person-linking)。

### 页面来源与行操作

`Member::Sources::Pages`（键 `:pages`，排在实体之后，可编辑）为每个已上线、有效、集合含 `member` 的租户或共享页面添加一个 `BuiltinSurface`：键 `page_<id>`，标签为页面名称，`path_seg` 为 `pages/<id>`，`default_enabled: false`。未上线、已进回收站、仅管理员、仅公开的页面跳过。租户页与共享页共用操作标识且都面向会员时，只列 `Pages::ActionResolver.page_for` 的选择。`Member::Navigation` 生成 `/:cid/member/pages/<id>`。`Member::SurfacesController` 对 `surfaces/page_<id>` 返回 404。文案：`admin_settings.member.sources.pages.name`「页面」／ "Pages"，`description`「会员可打开的已上线页面。」／ "Launched pages members can open."

实体界面可配置行操作（`row_action_key`、`row_action_field`、可选 `row_action_label`；`Member::SurfaceSetting` 的覆盖键）。`Member::EffectiveSurface#row_action` 返回 `{ action_key:, field:, label: }` 或 nil。会员索引（`SurfaceIndexComponent`／`IndexTableComponent`）在表格行与堆叠卡片上渲染按钮，链到 `Pages::ActionLink.path`，并带 `prefill[<field>]=<行 id>`。默认文字为 `member.entity_surfaces.row_action_default`「打开」。设置文案在 `comp_admin.member_surface.row_action_*` 与 `settings_people.member.row_action`。行操作缺字段时失败为 `admin_settings.errors.validations.row_action_invalid`（「行操作须填写操作标识和目标字段。」）。组合列表块接受 `config.row_action` 并渲染末列链接（`public_views.composite.row_action_default`）。见[受众流程](audience-flows)。

`PublicPagesController` 引入 `PageRendering` 与 `CaptchaProtectable`，布局为 `"public_page"`。`find_launched_page` 是 `Page.accessible.launched.find_by!(public_uuid:)`。`authorize_public_view!` 要求 `visible_to?(:public)`。`authorize_submission!` 要求 `page.visible_to?(page_runtime_audience)`。否则不写入：对应页加 `continue_here`、匿名登录回跳、公开 `not_for_your_account`，或 404。`post_submit_path` 按 `page_runtime_audience`。提交由 `Pages::PublicSubmission` 执行。交接使用 `FeatureModules::Invocation.begin!`。

## 需要特别注意

### 路由审计：自助服务与覆盖不变量

MFA 设置仅由 POST 启用，HEAD 不消费 OTP，也不启用强制验证。预取 GET 不写入 `otp_secret`。资料／MFA 凭据冲突使用[身份认证](authentication)中的本地化 `409 stale_credentials` 响应。会员预览还要求操作者属于本租户且使用 GET／HEAD；卡片／订阅控制器未加入此例外。

`Member::Settings::Operation::Update` 在客户锁内先解析整批可编辑界面，再写入。省略 enabled／覆盖值保留现值；nil 继承默认，空白显示文案移除覆盖，可见性 `[]` 隐藏所有可选项。描述符中不可隐藏的字段仍显示；描述符范围及详情归属始终有效。

外租户会话可访问公开内容，但在所访租户内按 public 字段受众处理；固定平台所有者保留明确运行例外。提交归属、校验、选项及交接使用同一租户策略，不替换真实会话操作者。支付保存卡片仍限同租户归属。提交／交接共用回滚边界，见[页面渲染](page-rendering)及[模块框架](module-framework)。

会员 MFA 经 `Authentication::MutationAudit.mfa` 记录已提交启用／停用结果、操作者及前后事实；拒绝、HEAD、无操作均不产生成功事件。

:::note
会员 MFA、覆盖及公开提交回归测试已编写，本次未执行；浏览器流程仍待验证。
:::

:::attention
`RouteAuthorization.allow_admin_member_preview!` 在 `Member::PagesController` 与 `Member::SurfacesController` 中调用。通过之后，同一租户的 `admin_or_owner?` 可以 GET 和 HEAD。POST、PATCH、PUT、DELETE 仍然只允许 `member?`。`Member::Payments::PaymentMethodsController` 与 `SubscriptionsController` 没有加入这一例外。已登录用户打开另一个客户的 `/member` URL 时，`TenantContext` 仍然拒绝，除非该用户是 `platform_owner?`。界面描述符的 scope 以 `current_user` 求值，管理员预览不会列出其他会员的行。
:::

:::attention
`Member::BaseController#authorize_owned!` 在 `customer_id` 不同于 `current_user.customer_id` 时抛出 `ActiveRecord::RecordNotFound`；记录若有 `user_id` 且不是 `current_user.id`，同样抛出。`Member::PagesController` 不调用它：页面属于租户，门槛是 `accessible`、`launched` 与 `visible_to?(:member)`。
:::

:::attention
`PublicPagesController#authorize_public_view!` 对集合不含 `public` 的页面一律 404。POST `#submit` 使用精确集合的拒绝规则，访问者受众不在集合中时不写入。登录之后，Devise 必须回到 `stored_submission_return_path`，而不是 `public_page_path`。
:::

:::attention
`Member::SurfacesController#load_surface` 在描述对象 `is_a?(Member::Sources::BuiltinSurface)` 时抛出 `RecordNotFound`。资料、安全与会员首页分别留在 `ProfilesController`、`SecuritiesController` 与 `DashboardsController`。捕获一切的 `path: ":key"` 声明在这些路由以及 `namespace :payments` 之后。
:::

## 关键代码

```ruby
# app/controllers/concerns/route_authorization.rb
def allow_admin_member_preview!
  self.admin_member_preview_allowed = true
end
```

```ruby
# app/controllers/concerns/route_authorization.rb
if member_path?
  return if current_user.member?
  return if admin_member_preview_allowed && (request.get? || request.head?) &&
            current_user.admin_or_owner? && current_user.customer_id == current_customer_id

  raise CanCan::AccessDenied, t("common.errors.authorization.member_required")
end
```

```ruby
# app/controllers/member/base_controller.rb
def authorize_owned!(record)
  raise ActiveRecord::RecordNotFound unless record &&
    record.customer_id == current_user.customer_id &&
    (!record.respond_to?(:user_id) || record.user_id == current_user.id)
end
```

```ruby
# app/controllers/member/pages_controller.rb
class PagesController < BaseController
  include PageRendering

  allow_admin_member_preview!

  def show
    @page = Page.accessible.launched.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

    prepare_page_render(@page)
  end
end
```

```ruby
# app/controllers/public_pages_controller.rb
def authorize_public_view!
  raise ActiveRecord::RecordNotFound unless @page.visible_to?(:public)
end
```
