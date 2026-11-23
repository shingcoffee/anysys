---
title: "模块框架"
summary: "七个功能模块如何注册、在启用时配置，并暴露四个管理界面。"
---

## 概要

功能模块是 `FeatureModules::<Key>::Registration`，它是 `FeatureModules::BaseModule` 的子类。启动时加载每一个 `app/services/feature_modules/*/registration.rb` 并调用 `register!`，向 `feature_modules` 表写入或更新一行。为客户启用时运行 `provision!`，并把 `FeatureModules::CustomerAssignment` 标为 active。七个键是 `authentication`、`payment`、`email`、`sms`、`captcha`、`ai_assistant` 与 `website`。每个模块有四个管理界面：记录、客户设置、启用开关、平台模块设置。各模块的行为见 [authentication-module](authentication-module)、[payments](payments)、[email](email)、[sms](sms)、[captcha](captcha)、[ai-assistant](ai-assistant) 与 [websites](websites)。

## 配置核对表

平台所有者的模块目录为 `/81721200/admin/maintenance/platform/module_settings`。模块状态为 **active** 只表示可以为客户启用，不代表供应商凭证、产品权限、回调或客户设置已配齐。应核对运行环境对应的模式（Rails 生产环境用 `production`，其余用 `sandbox`），并完成真实交易或验证码挑战；应用模式不会自动切换厂商沙箱。

| 模块 | 待核对配置 | 详细步骤 |
| --- | --- | --- |
| 认证（`authentication`） | 必选模块；决定平台客户注册开关，再分别配置租户的成员注册、找回密码和 MFA 策略。无需外部身份供应商凭证。 | [认证模块](authentication-module) |
| 支付（`payment`） | 平台开放网关；每个客户按网关和模式启用并配齐商户账户，开通厂商产品权限及收款通知。 | [支付：网关配置](payments) |
| 邮件（`email`） | 保存运行模式的平台凭证，启用一个投递厂商，验证发件地址或域名，并按需配置投递回执。 | [邮件：供应商配置](email) |
| 短信（`sms`） | 保存并启用平台凭证，申请通过审核的发送方和模板，在启用的平台模板上填写厂商模板编号；如使用 Twilio，还要配置回调。 | [短信：供应商配置](sms) |
| 验证码（`captcha`） | 保存并启用一个平台供应商，按需登记挑战页域名，并配置平台或租户 URL 限流。供应商未配齐时 Rack 网关会放行。 | [验证码：供应商配置](captcha) |
| AI 助手（`ai_assistant`） | 保存供应商凭证，分别为「生成」和「语音转写」指派已配好的供应商，再为租户启用模块。 | [AI 助手：供应商配置](ai-assistant) |
| 网站（`website`） | 在模块配置中选择默认骨架，按需整理平台骨架与布局目录，为租户启用后发布网站和页面；无需外部供应商凭证。 | [网站构建器](website-builder) |

目录上的配置标记只区分**供应商、默认值或无配置结构**，并非实时健康检查或缺失字段清单。请按链接区分厂商侧准备工作与应用内设置。

### 本地配置核查（2026 年 10 月 3 日）

下表是**本地应用已保存设置的定期快照**，不是实时监控，也不能证明厂商侧审核通过。核查时七个模块均在平台全局启用；租户分配和端到端测试仍需分别确认。表中不含密钥值。

| 模块 | 已保存状态／待办 |
| --- | --- |
| 认证 | 必选且已启用；平台客户注册已开放。按需逐个核对租户成员注册、MFA 与找回密码策略。 |
| 支付 | 四个网关均在平台开放。五条**已启用的沙箱**商户账户中，仅**一条 Stripe 账户**通过 `configured?`；其余四条仍使用预置商户标识，且缺少凭证字段。查到的正式环境商户账户均未启用。按[网关步骤](payments)配置所需租户和模式。 |
| 邮件 | **没有平台凭证记录。** 添加并指派运行模式的凭证，完成发件身份验证和需要的回执配置。 |
| 短信 | **没有平台凭证记录。** 添加并指派凭证，准备审核通过的发送方及已映射的模板。 |
| 验证码 | 阿里云、Turnstile 和 reCAPTCHA v3 均**未启用且未配齐**。填写密钥，启用一个供应商并验证挑战流程。 |
| AI 助手 | 已配好的 **AWS Bedrock** 指派给「生成」，**AWS Transcribe** 指派给「语音转写」。已保存的 OpenAI / Whisper 也已配齐，但未指派。须完成实际聊天和语音测试，才能认定现有任务可用。 |
| 网站 | `default_skeleton_key` 默认为 `presence`；平台目录已有骨架和布局，并有已发布的网站。无需第三方供应商凭证；仍需分别核对租户网站和发布状态。 |

四条未配齐的**已启用沙箱支付账户**具体缺少以下值（仅列字段名）：支付宝——商户标识、`private_key_pem`、`platform_public_key_pem`；PayPal——商户标识、`client_id`、`client_secret`、`webhook_id`；Stripe——商户标识、`secret_key`、`publishable_key`、`webhook_signing_secret`；微信支付——商户标识、`appid`、`api_key_v3`、`private_key_pem`、`platform_public_key_pem`、`wechat_cert_serial`。另有**一条独立的** Stripe 沙箱账户已配齐；此快照不能证明该账户已经实际收到 Stripe webhook。

## 流程

```text
config/initializers/feature_modules.rb
        |
        |  扫描 registration.rb -> constantize -> register!
        v
feature_modules 行（key、name、status、required）
        |
        |  mandatory? -> status 为 active，required 为 true
        |  required 行会为每一个 Customer 执行 provision!
        v
POST /:cid/admin/maintenance/modules/:module_id/enablement
        |
        |  ModuleEnablementsController#create
        |  registration_class.provision!(customer)
        |  再持久化 CustomerAssignment 状态 active
        v
侧栏记录与设置，HostIntegration#before_request

页面提交交接（活动成功后，提交事务完成前）
        |
        v
FeatureModules::Invocation.begin!
        |
        |  session[:feature_module_invocation]
        |  重定向到 registration.entry_path_for(customer)
        v
模块入口页
        |
        v
FeatureModules::Complete.call -> ExitResolver -> 清除会话
```

编译出的流程图步骤不调用 `Invocation`。调用服务步骤可以调用 `FlowchartRuntime::Invocable::SERVICE_NAMESPACES` 下已允许的类，该名单包含 `FeatureModules`。见 [flowchart-runtime](flowchart-runtime) 与 [page-rendering](page-rendering)。

## 实现

`BaseModule` 要求实现 `module_key`、`module_name` 与 `provision!`。默认的 `deprovision!` 是空方法。默认的 `before_request` 返回 nil。`sidebar_contributions` 默认返回空的 `entries` 与 `settings` 数组。`mandatory!` 把这个类标成永久启用。`enabled_for?(customer_id)` 是租户开关，即以该类自身的 `module_key` 调用 `FeatureModules::Module.enabled?`；调用方用 `FeatureModules::Website::Registration.enabled_for?(customer.id)` 这类写法，不再重复书写 key 字符串。`register!` 按 key 查找或初始化 `FeatureModules::Module`，写入名称、描述和 `configuration_schema`；`mandatory?` 为真时把 `status` 设为 `:active`、`required` 设为 true。新建的非强制行以 `inactive` 与 `required: false` 开始。已存在的非强制行保留已存储的 status 与 required。

交接 DSL 是 `entry_path`、`default_exit`（`kind` 为 `page`、`flowchart`、`url`、`route` 之一）、`input_contract` 与 `output_contract`。契约字段变成 `HandoffField` 描述和一个 `Reform::Form` 子类。`source` 默认为 `:author_only`。`:user_fillable` 是模块入口页可以收集的值。

`FeatureModules::Module#registration_class` 将 `FeatureModules::<驼峰 key>::Registration` 常量化。类不存在时返回 `NullRegistration`，其 `provision!` 与 `deprovision!` 为空。`enabled?` 表示模块为 active，并且该客户有一条 active 的 `CustomerAssignment`。`available` 是 `status: :active`。`handoff_enabled` 是一列；inactive 的模块不能把它设为真。

`feature_modules` 表存在时，`config/initializers/feature_modules.rb` 在 `after_initialize` 运行。它对每个注册文件 `require_dependency`，把 `FeatureModules::<目录名>::Registration` 常量化，并调用 `register!`。然后查找 `FeatureModules::Module.required`，对每个还没有 active 分配的客户保存一条分配并调用 `provision!`。

| 键 | 类 | `provision!` | 启用说明 |
| --- | --- | --- | --- |
| `authentication` | `FeatureModules::Authentication::Registration` | `FeatureModules::Authentication::Provisioner.call` | 调用 `mandatory!`；`deprovision!` 调用 `FeatureModules::Authentication::Deprovisioner.call` |
| `payment` | `FeatureModules::Payment::Registration` | `FeatureModules::Payment::Provisioner.call` | `deprovision!` 调用 `FeatureModules::Payment::Provisioner.revoke` |
| `email` | `FeatureModules::Email::Registration` | `FeatureModules::Email::Provisioner.call` | `deprovision!` 调用 `FeatureModules::Email::Provisioner.revoke` |
| `sms` | `FeatureModules::Sms::Registration` | `FeatureModules::Sms::Provisioner.call` | `deprovision!` 调用 `FeatureModules::Sms::Provisioner.revoke` |
| `captcha` | `FeatureModules::Captcha::Registration` | `FeatureModules::Captcha::Provisioner.call` | `deprovision!` 调用 `FeatureModules::Captcha::Provisioner.deprovision` |
| `ai_assistant` | `FeatureModules::AiAssistant::Registration` | 返回 nil | `deprovision!` 返回 nil |
| `website` | `FeatureModules::Website::Registration` | `FeatureModules::Website::Provisioner.call` | `deprovision!` 调用 `FeatureModules::Website::Provisioner.deprovision` |

`Payment::Provisioner.call` 为每个可用网关和模式插入一条停用的 `Payments::MerchantAccount`。`revoke` 把这些账户设为 `disabled`，并保留凭证行。

`Admin::Maintenance::ModulesController#index` 列出 `FeatureModules::Module.available` 以及该客户已启用的分配 id，并从 `Dashboard::ModuleCards` 取得各已启用模块的主链接。`Admin::Maintenance::ModuleCatalogComponent` 渲染已启用／未启用／必需计数、`list-filter` 搜索框，以及按 `NavigationOrder` 分组的 `ModuleCatalogCardComponent` 卡片。每张卡片显示模块图标、状态、`Dashboard::ModuleCards.blurb_for` 描述、已启用时的**打开**链接，以及 `ModuleToggleComponent` 开关：开关对 `enablement` 资源发送 POST 或 DELETE（`http_method:`，不传 `field`）。必需模块启用后开关锁定。`ModuleEnablementsController#create` 要求 `feature_module.active?`，把分配设为 `active`，并在同一事务里调用 `provision!`。`destroy` 拒绝 `required?` 的模块，把分配设为 `suspended`，并调用 `deprovision!`。`ModuleSubTogglesController#update` 写入一个布尔键：它既在 `configuration_keys` 里，又在 `configuration_schema` 中类型为 `"boolean"`。注册类以 `owner_managed_configuration_keys` 声明客户专属限额：客户在设置中只能查看，平台所有者在该客户的「维护／模块」页面编辑。`ModuleOwnerConfigurationsController#update` 接受 `PATCH /:cid/admin/maintenance/modules/:module_id/owner_configuration`，要求平台所有者、已启用的模块及客户分配，以及范围内的整数（发送上限可为零，录音秒数须为正）；仅将声明过的键合并至该客户分配。邮件和短信声明 `daily_send_cap`，AI 助手声明 `max_duration_seconds`。

`ApplicationController` 引入 `FeatureModules::HostIntegration`。每次带有当前客户的请求都会遍历 `enabled_for_customer`，并调用 `registration_class.before_request`。遍历顺序没有规定。响应已经 `performed?` 时循环停止。`feature_module_enabled?` 是视图辅助方法。

`/:cid/admin` 下的四个界面：

1. 记录：`namespace :modules` 与 `ModulesContributor`，后者读取 `sidebar_contributions[:entries]`。通用读取器是 `Admin::ModuleEntriesController#show`，路径为 `/admin/modules/:module_key/entries/:key`，它调用 `entries_for`。目录及嵌套的记录页面只展示记录操作，不提供配置、网站发布或维护快捷入口；独立的使用指南页面另提供相关客户设置链接。验证码等仅有设置的已启用模块仍显示信息卡片，但没有记录操作；模块侧栏中仍有其使用指南入口。
2. 客户设置：`resources :module_configs` 位于 `settings/modules/:key`（`Admin::ModuleConfigsController`），再加上 `sidebar_contributions[:settings]` 与 `SettingsContributor` 给出的设置链接。`/admin/settings` 目录和侧栏按已启用模块分别归类，标题随语言切换；验证码和未来新增模块也各有自己的分组。会员和账单等通用设置独立成组。设置侧栏将目录使用的扁平分组标题交给与模块侧栏相同的 `SidebarNodeComponent` 折叠组件渲染。两个菜单样式统一：一级行为紧凑的 36px（移动端为 44px 触控行），左侧 24px 图标块按 `SidebarNode#tone` 经 `module_color_classes` 着色（概览、会员、账单为中性色）；子项为纯文字行，挂在细导线上，选中子项显示强调色底板，并在导线上加一段强调色标记；分组收起时，箭头旁显示其中入口数量。设置链接仍保留图标（缺少专用图标时用滑块图标）供收起后的图标栏使用，展开的子菜单不再绘制。桌面侧栏、全局抽屉和移动端设置对话框均采用此布局；全局抽屉中的模块菜单也改用同一个可搜索的 `SidebarComponent`。页面加载时仅展开当前子项所在分组，并用激活样式及 `aria-current="page"` 标记该子项；其他分组默认收起。搜索时临时展开匹配分组，清空后恢复先前状态。先按权限过滤，再归类。租户设置仍在 `/:cid/admin/settings/modules/<module>`，与平台所有者的配置命名空间分开。通用表单将平台所有者管理的限额显示为只读；PATCH 白名单也排除这些字段，伪造提交无法改动，其他客户偏好仍可编辑。
3. 启用、停用和平台所有者管理的客户限额：`Admin::Maintenance::ModulesController` 位于 `/admin/maintenance/modules`，`ModuleEnablementsController` 负责嵌套的启用资源，`ModuleOwnerConfigurationsController` 负责平台所有者对该客户的限额调整。
4. 平台模块设置：`Admin::Maintenance::Platform::ModuleSettingsController` 位于 `/admin/maintenance/platform/module_settings` 与 `/admin/maintenance/platform/module_settings/:key`（概览、`configuration`、`developer`）。供应商路由嵌在这个前缀下（`email/credentials`、`sms/credentials`、`sms/templates`、`captcha/settings`、`captcha/pages`、`ai_assistant/settings`、`payment/gateways`、`payment/webhook_events`）。这个命名空间要求 `platform_owner?`。

`FeatureModules::Invocation` 独占 `session[:feature_module_invocation]`。`begin!` 要求存在模块行、`handoff_enabled?`、一条 active 分配、通过输入契约（在 `InputCaster` 之后），以及非空白的 `entry_path_for`。它存储 `customer_id`、页面 id、记录 id、令牌、已转换的输入和 `exit_target`，然后返回入口路径。`Current.customer` 与存储的客户不同时，`current` 抛出 `CrossTenantViolation`。`FeatureModules::Complete.call` 验证输出契约，向 `ExitResolver` 要 URL，写日志，并对会话 `clear!`。

`/:cid/admin/settings` 设置目录会依可用空间排为一至三列卡片，展示本地化页面简介、分组图标／名称／说明，以及每项获准设置的名称与解释；整行均可点击。独立的设置侧栏在桌面和移动端继续提供搜索，目录不再重复搜索框。权限筛选及分组仍由 `SettingsContributor` 处理：模块说明经分组标题传入，会员和账单分组使用本地化说明。发送和录音限额的说明明确指出，只有平台所有者能调整这些数值。

`FeatureModules::NavigationOrder` 统一两个侧栏的顺序，并维护模块分类（`SECTIONS`、`SECTION_ORDER`、`section_for`、`by_section`），模块目录页（`Dashboard::ModuleCards`、`Admin::Modules::HubComponent`）也共用这套分类。两个侧栏在概览之后按分类标题（`admin_modules.index.sections.*`，随语言切换）列出模块：**记录与数据**（用户认证、网站）、**沟通触达**（支付、邮件、短信）、**增长与安全**（验证码、AI 助手）、**更多模块**（未来新增模块，按名称排序）。分类标题是 `category: true` 的 `SidebarNode`；`SidebarComponent#categories` 将其渲染为标注所属列表的 `h3`，搜索时若其下无匹配项则隐藏，没有可见分组的分类直接省略。收起后的图标栏以分隔线代替标题。模块侧栏展示全部已启用模块；设置侧栏只展示已启用且有可用设置入口的模块。设置侧栏最后是 **组织** 分类（`settings_navigation.categories.organization`），包含会员与账单分组。移动端遵循相同顺序，设置目录也按此分组顺序展示。

### 可选返回网址的用途

仅当模块已为客户启用，且平台所有者开启 `FeatureModules::Module#handoff_enabled` 时，`Admin::Settings::ModuleConfigComponent` 才显示「返回网址（可选）」及其独立表单。交接关闭时，`Admin::ModuleConfigsController` 会忽略手动提交的 `exit_landing_page`，但仍可保存其他获准设置。`SettingsContributor` 会在每个已开启交接的模块设置分组下新增「返回网址（可选）」子项；即使模块没有其他设置，或使用专用设置页面，也能通过 `/:cid/admin/settings/modules/:module_key/return_url` 打开通用表单（部分模块使用复数路径）。客户先前保存在 `CustomerAssignment.configuration` 中的网址会保留，重新启用交接前不会生效。保存设置后不会因此跳转，普通模块操作也不会统一跳转。`FeatureModules::ExitResolver` 依次选用页面交接单独指定的 `exit_target`、**交接开启且客户分配有效时**保存的返回网址、模块的 `default_exit`，最后退回组织仪表盘。应填写完整的 HTTP 或 HTTPS 网址；留空则使用默认位置。只有模块完成交接或明确调用解析器时，才会使用该设置。

退出解析将缺失的 `CustomerAssignment.configuration`、JSON `null` 及非对象 JSON（数组、字符串、数字或布尔值）视为未配置客户级返回位置。会话退出目标缺失或无法解析时，解析器继续尝试注册类的 `default_exit`；默认目标也缺失或无法解析时，退回 `/:customer_id/admin/dashboard`。有效 JSON 对象仍按原有规则提供 `exit_landing_page` 值。完成交接不要求事先保存客户设置，新启用的短信模块也遵循此规则。

| 模块 | 返回网址何时生效 |
| --- | --- |
| 用户认证 | 日常登录、成员注册与找回密码遵循各自的跳转规则，不使用此网址。 |
| 邮件 | 发送或预约邮件目前不会完成页面交接，也不会使用此网址。 |
| 短信 | 发短信与查看送达情况目前不会完成页面交接，也不会使用此网址。 |
| 支付 | 经页面交接发起的付款成功后，若页面未另行指定返回位置，付款人会跳转至此；即使没有交接，独立结果页的「返回」按钮也使用此网址。这不是网关回调地址或支付服务商的返回地址。 |
| AI 助手 | 聊天回复与语音输入目前不会完成页面交接，也不会使用此网址。 |
| 验证码 | 挑战、校验与限流不使用返回网址；专用验证码设置页面不展示此通用字段。 |
| 网站 | 发布站点或页面不使用返回网址；专用网站设置页面不展示此通用字段。 |

### 模块侧栏中的客户使用指南

`/:cid/admin/modules` 目录展示页面简介、分组标题，以及含图标、本地化模块说明和记录入口列表的宽松响应式卡片。目录不提供搜索框或筛选；模块侧栏仍可单独搜索。模块数量徽标、模块／页面概览数字和重复的操作按钮已移除。管理首页的精简模块卡片保留原有说明，入口以胶囊链接呈现（见 [仪表板](dashboard)）。两个目录统一采用简洁的描边卡片／列表行、充足留白、不小于 44px 的链接点击区域及常显的方向箭头；窄屏下标签与说明会自动换行。

`/:cid/admin/modules` 通过 `Dashboard::ModuleCards` 渲染已启用的模块。`ModulesContributor` 在桌面和移动端模块侧栏的**每个已启用模块**下，将「使用指南」列为首个子项，其后才是记录入口。验证码和 AI 助手即使没有记录入口，也显示模块分组。「使用指南」指向 `GET /:cid/admin/modules/:module_key/howto`（`Admin::ModuleHowtosController#show`）；管理路由权限及 `available_for_customer` 客户范围查询共同保护该页面，模块不存在或未启用时返回 404。`Admin::Modules::HowtoComponent` 在**每条编号步骤旁**展示对应的链接，包括由模块提供且经过权限过滤的客户设置，以及功能或记录入口。所有步骤链接均在新标签页打开（`target="_blank"`、`rel="noopener noreferrer"）；移动端链接排列在步骤下方。验证码链接至自身设置与租户的「页面」列表，以配置和测试受保护的页面；AI 助手可直达工作区。不再显示独立的快捷入口卡片。目录卡片不重复指南，也不添加设置链接。步骤定义在两种语言的 `admin_modules.index.howto.steps` 中；新增模块尚无专属文案时，按是否存在记录链接显示对应的通用指南，并在有入口时链接至第一个可用页面。

每条步骤**只对应一个链接**，不再同时展示多个快捷入口。用户认证的成员注册与找回密码、邮件的模板与收件人列表、验证码的页面限流与编辑，以及网站的站点发布与页面检查，均为独立步骤。新增模块若没有专属入口，则引导至设置目录与模块概览。

| 模块 | 指南内容 |
| --- | --- |
| 用户认证 | 成员注册／找回密码策略、用户与角色管理、安全日志。 |
| 邮件 | 查看平台所有者管理的发送上限及平台投递前提、创建模板及列表、立即或预约发送活动。 |
| 支付 | 配置租户商户账户、通过收银台收款并查看交易、定期扣款订阅。 |
| 短信 | 查看平台所有者管理的每日上限及已审核发送方／模板前提、通过流程发信、查看消息与退订名单。 |
| 验证码 | 服务商前提、页面限额及按需启用挑战、浏览器验证；不增加记录链接。 |
| AI 助手 | 选择语言并查看平台所有者管理的录音时长上限、提问与起草、审核改动及按需语音输入。 |
| 网站 | 站点信息、编辑与发布页面、发布并检查站点。 |

## 需要特别注意

### 路由审计：默认值、批量开通及交接不变量

`BaseModule.register!` 刷新元数据，保留已声明键的已存默认值。平台先校验类型／模型／敏感变量，再锁定并事务性修改及必需开通，模块缺失仍为 404。租户启用及必需开通先 provision 再 active。网站 provisioner 检查 `result.success?`，失败抛出 `FeatureModules::Website::Provisioner::ProvisioningError`，起步组合／冲突校验失败不能提交 active 分配。客户／启动路径保留各自事务顺序。

`InputMapper` 读取身份元数据及受众可见的结构数据，兼容 JSON 字符串 `data`，不调用任意模型方法。`HandoffCompletion` 仅接受声明的用户补填标量。`PublicSubmission` 在同一保存点运行活动及交接准备，失败时 `Invocation.with_submission` 恢复先前会话调用。拒绝时新增／更新一起回滚，不删除返回的既有记录。见[页面渲染](page-rendering)、[支付](payments)、[网站](websites)。

:::note
注册／默认值、开通及提交交接回归测试已编写，本次未执行。供应商就绪徽章或源码事务不代表端到端运行通过。
:::

:::attention
`FeatureModules::Authentication::Registration` 调用 `mandatory!`。`BaseModule.register!` 随后强制 `status: :active` 与 `required: true`。`required?` 为真时，`ModuleEnablementsController#destroy` 以 `required_module` 重定向。初始化文件的注释写的是 `required!`；`BaseModule` 上的方法是 `mandatory!`。
:::

:::attention
已存在且 `mandatory?` 为假的行，`BaseModule.register!` 不改 `status` 与 `required`。启动不会把所有者停用的模块重新打开。全新的非强制行以 `inactive` 保存。
:::

:::attention
`PublicPagesController#start_page_handoff` 经成功活动完成块，在 `Pages::PublicSubmission` 事务内执行。生成活动源码不调用 `Invocation`，白名单服务调用步骤仍是独立路径。
:::

:::attention
`FeatureModules::Payment::Provisioner.revoke` 把 `Payments::MerchantAccount` 行更新为 `status: "disabled"`。`revoke` 上的注释说明关闭模块时保留凭证行。`FeatureModules::AiAssistant::Registration.provision!` 与 `deprovision!` 返回 nil。
:::

:::attention
`FeatureModules::HostIntegration#run_feature_module_before_request` 遍历 `FeatureModules::Module.enabled_for_customer`，代码没有规定顺序。某个 `before_request` 使响应 `performed?` 之后，其余模块被跳过。常量缺失时，`registration_class` 回退到 `FeatureModules::Module::NullRegistration`。
:::

## 关键代码

```ruby
# app/services/feature_modules/base_module.rb
      def register!
        fm = ::FeatureModules::Module.find_or_initialize_by(key: module_key)
        fm.name                  = module_name
        fm.description           = module_description
        persisted_schema = fm.configuration_schema_json
        fm.configuration_schema = configuration_schema.to_h.transform_keys(&:to_s).to_h do |key, field|
          definition = field.stringify_keys
          configured = persisted_schema.is_a?(Hash) ? persisted_schema[key] : nil
          definition["default"] = configured["default"] if configured.is_a?(Hash) && configured.key?("default")
          [key, definition]
        end.to_json

        if mandatory?
          fm.status   = :active
          fm.required = true
        elsif fm.new_record?
          fm.status   = :inactive
          fm.required = false
        end
        # else: preserve persisted owner-set status/required.

        fm.save!
      end
```

```ruby
# config/initializers/feature_modules.rb
    klass.register!
```

```ruby
# app/controllers/admin/maintenance/module_enablements_controller.rb
        ActiveRecord::Base.transaction do
          feature_module.registration_class.provision!(current_customer)
          customer_feature.save!
        end
```

```ruby
# app/models/feature_modules/module.rb
    def registration_class
      "FeatureModules::#{key.camelize}::Registration".constantize
    rescue NameError
      NullRegistration
    end
```

```ruby
# app/services/feature_modules/invocation.rb
        session[SESSION_KEY] = {
          module_key:         feature_module.key,
          customer_id:        customer.id,
          triggering_page_id: triggering_page&.id,
          entity_entry_id:    entity_entry&.id,
          # Per-invocation secret. Modules that materialize a domain object
          # (e.g. Payments stamps it onto the Payment at charge time) can bind
          # completion to THIS invocation, not just to a shared idempotency key.
          token:              SecureRandom.hex(16),
          input:              casted_input.transform_keys(&:to_sym),
          exit_target:        exit_target,
          started_at:         Time.current.iso8601
        }
```

```ruby
# app/controllers/concerns/feature_modules/host_integration.rb
      FeatureModules::Module.enabled_for_customer(current_customer_id).each do |fm|
        fm.registration_class.before_request(self)
        return if performed?
      end
```
