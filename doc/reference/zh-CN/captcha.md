---
title: "验证码"
summary: "平台只启用一个验证码厂商；URL 限流在页面渲染之前把超额访问转到挑战页。"
---

## 概要

`FeatureModules::Captcha::Registration`（模块键 `captcha`）用厂商组件和栈前端的限流保护公开 HTML。厂商是 `app/services/captcha/providers/` 下的 `Captcha::Providers` 子类：`aliyun.rb`（调用了 `default!`）、`turnstile.rb`、`google_recaptcha_v3.rb`。新厂商就是这一个文件，并调用 `register!`。厂商字段在 `Captcha::ProviderSettings#config`。共用的类型化列是 `access_key_id`、加密的 `access_key_secret`、`enabled`、`fail_policy` 和 `score_threshold`。不为单个厂商写迁移。

`Captcha::ProviderSettings.active` 是唯一一条已启用且已配置完成的行。`Captcha::RackGate` 用 `Rack::Attack.cache` 计数，把超限请求重定向到 `Captcha::ChallengesController`。挑战通过后，`Captcha::Grant` 按该 IP 和 URL 模式放行。

## 配置验证码供应商

在 `/81721200/admin/maintenance/platform/module_settings/captcha/settings` 保存供应商密钥、选择**失败处理策略**（`open` 或 `closed`），运行**连接测试**，再启用该供应商；同时只能启用一个。到 `.../captcha/surfaces` 配置平台保护路径，到 `.../captcha/pages` 配置共享页面；租户自己的公开页面在 `/:cid/admin/settings/modules/captcha` 配置。没有已配齐且已启用的供应商时，Rack 网关**直接放行**，不受单条规则的失败时拦截标志影响。**连接测试**向厂商发送固定的*无效令牌*，收到 `invalid` 也算成功：只能初步判断连通性及部分凭证错误，**不能**证明挑战通过、场景 ID 或浏览器站点密钥／域名匹配。应在实际域名完成浏览器挑战和服务端验证。这些供应商无需登记 webhook 或重定向 URI。

### 阿里云验证码 2.0（`aliyun`）

1. [开通验证码 2.0 并创建 Web/H5 场景](https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/quick-start)，复制**场景 ID**。创建获准调用[服务端校验 API](https://www.alibabacloud.com/help/en/captcha/captcha2-0/user-guide/server-access) 的 RAM AccessKey。在应用填写 **Access Key ID**、**Access Key Secret**、`scene_id`，以及实例对应的**服务端** `endpoint`／`region`（上海：`captcha.cn-shanghai.aliyuncs.com`／`cn-shanghai`；新加坡：`captcha.ap-southeast-1.aliyuncs.com`／`ap-southeast-1`）。**浏览器**中的 `AliyunCaptchaConfig.region` 则使用**不同格式**：`cn` 或 `sgp`。
2. 在 `prefix` 填写实例**身份凭证前缀**。就绪检查要求凭据、`scene_id` 和 `prefix` 均已填写；已启用但缺少前缀的配置仍未就绪，`.active` 返回 nil。V2 控制器在加载 SDK 前设置 `AliyunCaptchaConfig`，以元素／按钮选择器及 `getInstance` 调用 `initAliyunCaptcha`，根据服务端 `X-Captcha-Result` 及 Turbo 提交结果完成回调。服务端地域映射为浏览器 `cn`／`sgp`；端点／地域组合受白名单约束。仍固定使用嵌入模式；真实浏览器验证尚需执行，探测用无效令牌不能证明完整流程。

### Cloudflare Turnstile（`turnstile`）

1. 在 Cloudflare 的 [Turnstile → Add widget](https://developers.cloudflare.com/turnstile/get-started/widget-management/dashboard/) 创建组件，选择展示模式并登记挑战页的[域名](https://developers.cloudflare.com/turnstile/additional-configuration/hostname-management/)（不带协议、端口或路径）。将厂商的 **Site Key** 填入 Anysys 的**站点密钥**，将 **Secret Key** 填入**私有密钥**（内部字段分别为 `access_key_id` 与 `access_key_secret`）。
2. 在每个目标域名测试。[Siteverify](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/) 成功结果必须匹配请求域名；插页预期无 action（nil／空），与组件配置一致。厂商域名限制也应保留。

### Google reCAPTCHA v3（`google_recaptcha_v3`）

1. 在 [reCAPTCHA 管理控制台](https://developers.google.com/recaptcha/docs/v3)注册 **v3** 密钥，登记挑战页域名（开发环境如需使用 `localhost`，也应单独添加）。把 **Site Key** 填入 Anysys 的 **Site Key（站点密钥）**，**Secret Key** 填入 **Secret Key（通信密钥）**（内部字段分别为 `access_key_id` 与 `access_key_secret`）；设置应用的**评分阈值**（可从 `0.5` 开始，再按真实流量调整）。
2. 在实际域名测试。Google [siteverify](https://developers.google.com/recaptcha/docs/verify) 必须返回匹配的 hostname／action，以及 0..1 内达到阈值的有限数值评分。插页将逻辑 `access_challenge` 映射为 SDK action `submit`；保留 Google 域名验证。

## 流程

```text
请求
        |
        v
CaptchaRackGateProxy -> Captcha::RackGate
        |  跳过 /captcha/challenge 和一键 List-Unsubscribe
        |  可访问的页面别名 -> 可信的规范限流路径
        |  Captcha::UrlMatcher.for_request
        |  Captcha::Grant.active? -> 放行
        |  every_hit，或 Rack::Attack.cache.count 超过上限
        |  ProviderSettings.active 为空 -> 失败时放行
        v
302 /captcha/challenge?return_to=...
        |  POST/PUT/PATCH 正文留在 Captcha::RequestSnapshot
        v
Captcha::ChallengesController
        |  Captcha::WidgetComponent
        |  Captcha::Activities::Verify
        v
Captcha::Grant.store，再重放 POST 或重定向 GET
```

`Captcha::Activities::Verify` 解析 `ProviderSettings.active`，拒绝空令牌和重放令牌（`Captcha::TokenReplay`），调用 `provider.verify`，并对 `score_based?` 厂商应用 `score_threshold`。结果为 `:success`、`:invalid`、`:replayed`、`:configuration_error`、`:unreachable`、`:disabled`。

## 实现

### 一个厂商文件

`Captcha::Providers::Base` 要求 `key`、`default_display_name`、`config_fields`、`configured?(settings)`，以及 `verify(context:)`。返回值包含 `:outcome`、`:http_status`、`:raw`，可选 `:score` 和 `:hostname`。厂商给出的结果是 `:success`、`:invalid`、`:configuration_error`、`:unreachable`。`widget(settings)` 为 `Captcha::WidgetComponent` 返回 Stimulus 元数据，返回 nil 则不渲染页内组件。`register!` 写在类体末尾。`Captcha::ProviderSettings.for_provider` 在首次访问时建行。

`enabled` 既是平台开关，也是当前厂商的选择器。`activate!` 清掉其他已启用的行。`.active` 只在 `configured?` 为真时返回那条已启用的行。厂商缺失或未配完时，`Verify` 返回 `:disabled`。`fail_policy` 为 `open` 或 `closed`。

`FeatureModules::Captcha::Provisioner.call` 返回 nil。`deprovision` 遍历该客户的 `Page`，从 `configuration_json` 删掉 `captcha` 键。它不删除 `Captcha::UrlThrottle` 行。

### 机架门与限流

`config/initializers/captcha_rack_gate.rb` 插入 `CaptchaRackGateProxy` 及外层 `CaptchaResponseMarkerProxy`，并把 `Rack::Attack.enabled` 设为 false，因此只有 `Captcha::RackGate` 使用缓存计数。`Captcha::UrlMatcher` 先取最具体的已存行，再取公开页规则，再取 `Captcha::SurfaceCatalog` 模板。对不上的路径不会被挑战。硬跳过的前缀只有 `/captcha/challenge`。

`Captcha::UrlMatcher.for_request(request)` 通过 `PageShortcuts::Resolver` 解析符合条件的[页面快捷路径](page-shortcuts)，按可信目标的 `canonical_path` 匹配规则。公开 `Page` 别名的 GET/HEAD/POST 沿用规范 UUID 端点的策略；网站别名仅在 GET/HEAD 时沿用适用的规范网站路径策略。规范路径的跳过规则仍然生效，但别名上的跳过规则不能绕过已有的规范路径策略。计数和放行凭据使用规范规则的模式，切换别名或规范端点不会重置限流。租户由主机和路径确定；查询／正文中的 `customer_id`、`uuid` 或 slug 不参与选择限流目标。不可访问的别名不会借用原目标的规范路径策略。

精确快捷路径查询先使用原始路径，再对已知路由处理可选格式。`/join.html` 可保存为与 `/join` 指向不同目标的映射；点属于别名本身，并非推断出的格式。没有该映射时，任意含点路径不会回退为去掉后缀的别名或自动网站 slug。`/auth/sign_in.json` 等已知规范页面／界面路径仍沿用规范限流，格式后缀不能绕过保护。

网关位于 Rails executor 内，代理仍在请求到达后才加载服务。解析结果仅缓存于当前请求环境，供后续 Journey 约束复用；网关不标记已匹配路由、不注入参数，也不设置 `Current`。`Captcha::UrlMatcher.for_path(path, request:)` 为挑战页的 `return_to` 校验提供相同的主机／挂载路径感知规则查询。挑战地址、返回路径及查询字符串保留原始别名。POST 快照保留原始正文、对外路径、`PATH_INFO` 和 `SCRIPT_NAME`。重放恢复这些路径和原始查询，清除挑战请求的解析／路由缓存，并通过正常的租户授权及发布检查重新解析别名；`captcha.replay` 仅跳过重复的网关挑战。快照令牌仍为一次性，并绑定 IP／路径。

挂载应用通过 `SCRIPT_NAME` 为挑战端点和快照 Cookie 作用域添加前缀：挂载于 `/portal` 时，重定向到 `/portal/captcha/challenge?return_to=...`，HttpOnly 快照 Cookie 限定于 `/portal/captcha/challenge`。挑战成功消费快照后，删除的也是同一挂载 Cookie 路径。返回地址保留 `/portal` 及原始查询；重放分别恢复路由相对的 `PATH_INFO` 和 `SCRIPT_NAME`，保证 Cookie 正确送达并保留最终映射重定向的前缀。

`Captcha::SurfaceCatalog::LOCKED` 包含登录、客户注册、找回密码、确认信、租户注册、账户编辑、MFA 设置/会话/恢复、邮件退订、OAuth 授权和支付结账。其中多条 `fail_closed: true`。`Admin::Maintenance::Platform::Captcha::SurfacesController` 按 `surface.path` 写入 `template` 限流。同一命名空间的 `PagesController` 为共享公开页写入模板 `/:customer_id/page/<public_uuid>`。

客户页面的限流是精确匹配。`Admin::Settings::Modules::Captcha::PagesController` 通过 `Captcha::Activities::UpdateUrlThrottle` 保存 `/<customer_id>/page/<public_uuid>`，页面必须属于该客户且受众集合含 `public`（`page.visible_to?("public")`／`Page.for_audience("public")`），包括管理员关闭的仅公开页。`Captcha::ThrottleRegistry` 缓存 `Captcha::UrlThrottle`，并索引 `Page.for_audience("public")`。`skipped` 行直接放行。

`ProviderSettings.active` 为 nil，或验证码处理自身抛错时，`RackGate` 失败即放行。救援分支不覆盖下游应用：控制器／CSRF 异常正常向上传递，网关不会重试应用。租户无需启用验证码模块；网站别名的可访问性仍会检查网站模块是否启用。

### 页面开关与表单内校验

`Page#captcha_enabled?` 读取 `configuration_json["captcha"]["enabled"]`。`Admin::Maintenance::PagesController` 允许 `captcha_enabled`。`PublicPagesController` 引入了 `CaptchaProtectable`。生产代码里没有任何控制器调用 `protect_with_captcha`，因此页面提交、登录和注册上都没有装上这个 `before_action`。若装上，`CaptchaProtectable#captcha_required_for_request?` 会对 `:page_submit` 要求验证码模块已启用，并要求 `Page#captcha_enabled?`。客户号为空的平台认证动作（`sign_up`、`sign_in`、`password_reset`）只要求 `ProviderSettings.active`。这个方法只有在控制器调用 `protect_with_captcha` 时才会运行。

真正会跑的挑战是 `Captcha::ChallengesController`，它以动作 `:access_challenge` 调用 `Captcha::Activities::Verify`。插页上的组件是 `Captcha::WidgetComponent`。公开页 HTML 见[页面渲染](page-rendering)。

收集名字／姓氏／邮箱的公开注册页，应在 `/:cid/page/<public_uuid>` 上配置 URL 限流（客户设置），并打开页面验证码开关。实际挑战仍是 Rack 网关，不是 `protect_with_captcha`。见[页面构建器](page-builder)（账号分组）与[受众流程](audience-flows)（公开报名）。

### 四个面

| 面 | 路径 | 控制器 |
| --- | --- | --- |
| 条目 | 无（`sidebar_contributions` 的 entries 为空） | — |
| 客户设置 | `/:cid/admin/settings/modules/captcha` | `Admin::Settings::Modules::Captcha::StatusController`（展示）；`PagesController`（更新限流）。这条路由写在通用 `module_configs` 之前 |
| 启用 / 停用 | `/:cid/admin/maintenance/modules` | `Admin::Maintenance::ModulesController`、`ModuleEnablementsController`（`Provisioner.deprovision`） |
| 平台设置 | `/:cid/admin/maintenance/platform/module_settings/captcha/settings`、`/surfaces`、`/pages` | `Admin::Maintenance::Platform::Captcha::SettingsController`、`SurfacesController`、`PagesController`；共用窗格在 `ModuleSettingsController` |

`StatusController` 展示 `ProviderSettings.active`、该客户是否启用模块，以及该客户公开页的限流展示行。注册类的 `entry_path` 就是这个设置 URL。没有 configuration schema，通用设置表单上没有验证码字段。`Admin::ModuleConfigsController` 不是验证码设置页。

## 需要特别注意

### 路由审计：原请求及失败策略不变量

`OriginalRequestVerifier` 在快照接收前及重放前检查原写入的 CSRF／来源。一次性快照绑定 IP、会话摘要、来源、路径及查询。`RequestReplayer.call(env:, payload:)` 恢复原 CSRF／来源头及正文，不生成新真实性令牌，并保留嵌套分发的会话修改。无效 CSRF 继续抛出，不进入失败放行救援。快照 Cookie 为 HttpOnly、限定挂载路径，HTTPS 时带 Secure。

已知可选格式路径继承规范限流；任意含点别名保留身份。实际失败处理取界面 fail-closed 或平台 `fail_policy == closed`；供应商停用或未配置完成时仍放行。供应商已就绪且故障结果允许放行时，`RequestPassage` 仅放行下一次精确 GET，绑定会话、来源、IP、路径及查询。该请求携带 `X-Captcha-Result: false`，不生成 `Grant`；供应商仍就绪时，后续 GET 再次进入挑战。供应商未就绪则直接绕过网关，不调用挑战验证。

`CaptchaResponseMarkerProxy` 包装 `Captcha::ResponseMarker`，紧邻 `Warden::Manager` 之前，位于会话中间件内部。`RackGate` 将已消费凭据的结果记录在请求环境中；外层标记器为实际响应添加 `X-Captcha-Result` 和 `Cache-Control: no-store`，包括 Warden 通过非局部跳转生成的认证失败重定向。后续同源重定向仅传递结果凭据（`allow: false`），不会再次授予故障放行。挑战页使用 same-origin 来源策略，并允许嵌入式支付浏览器。见[页面快捷路径](page-shortcuts)、[身份认证](authentication)、[支付](payments)。

:::note
回归测试覆盖重放／CSRF、厂商上下文、含点别名路由，以及经过认证重定向的一次性故障放行。配置探测不等于完整挑战验证；真实厂商浏览器流程需要实际凭据及域名。
:::

:::attention
新厂商是 `app/services/captcha/providers/` 下一个继承 `Captcha::Providers::Base` 并调用 `register!` 的文件。`Captcha::ProviderSettings.for_provider` 创建 JSON 行。不要加类型化列。真正把 `enabled` 设上并清掉其他已启用行的是 `ProviderSettings#activate!`。在 `configured?` 为真之前，`ProviderSettings.active` 仍返回 nil，此时 `Captcha::Activities::Verify` 返回 `:disabled`。
:::

:::attention
只有 `Captcha::UrlMatcher` 找到一条未被跳过的规则，且 `Captcha::Grant.active?` 为假时，`Captcha::RackGate` 才重定向到 `/captcha/challenge`。`Captcha::ProviderSettings.active` 为 nil，或网关自身抛错时，请求继续进入应用。租户无需启用验证码模块。`/unsubscribe/` 下带一键 `List-Unsubscribe` 的 POST 会跳过这道门。
:::

:::attention
`PublicPagesController` 引入了 `CaptchaProtectable`，但从未调用 `protect_with_captcha`。在 `app/` 里搜索这个类方法，只出现在该 concern 中。因此这个控制器的提交动作不会应用 `Page#captcha_enabled?`。公开页上实际生效的挑战是 `Captcha::UrlThrottle` 加上 `Captcha::RackGate`。客户限流是 `Admin::Settings::Modules::Captcha::PagesController` 写入的精确路径。共享页限流是 `Admin::Maintenance::Platform::Captcha::PagesController` 写入的模板。
:::

:::attention
`FeatureModules::Captcha::Provisioner.deprovision` 删掉该客户 `Page#configuration_json` 里的 `captcha` 键，`Captcha::UrlThrottle` 行仍然留着。`Captcha::SurfaceCatalog` 里的限流（例如 `/auth/sign_in`）是平台 URL 规则。单个租户停用模块之后它们还在。更新这些模板的是 `Admin::Maintenance::Platform::Captcha::SurfacesController`。
:::

## 关键代码

```ruby
# app/services/captcha/providers.rb
module Providers
  extend PluginRegistry.build(label: "captcha provider", dir: "app/services/captcha/providers")
end
```

```ruby
# app/models/captcha/provider_settings.rb
def self.active
  row = where(enabled: true).first
  row if row&.configured?
end
```

```ruby
# app/services/captcha/rack_gate.rb
rule = Captcha::UrlMatcher.for_request(req)
return if Captcha::Grant.active?(ip: ip, pattern: rule.pattern)

if rule.every_hit
  return challenge(req, rule) unless captcha_unavailable_fail_open?(rule)
```

```ruby
# config/initializers/captcha_rack_gate.rb
Rack::Attack.enabled = false

Rails.application.config.middleware.use CaptchaRackGateProxy
```

```ruby
# app/services/feature_modules/captcha/provisioner.rb
def self.deprovision(customer)
  Page.unscoped.where(customer_id: customer.id).find_each do |page|
    config = page.configuration_json
    next unless config.is_a?(Hash) && config.key?("captcha")
```
