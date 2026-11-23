---
title: "页面快捷路径"
summary: "将符合条件的网站页面或公开表单映射到指定的根路径、单段或多级 URL，并按主机确定租户。"
---

## 概要

页面快捷路径是客户自有的路径映射，目标为 `WebsitePage` 或公开 `Page`。这是通用的 URL 映射：`/`、`/join`、`/campaign/register` 都只是示例，不是独立功能。快捷路径直接渲染目标页面，浏览器保留指定地址。网站首页及内页也会自动生成访问路径，无需保存映射。

管理入口为 `/:cid/admin/maintenance/page_shortcuts`，维护首页卡片和侧栏均可进入。网站设置及租户「维护 → 页面」也链接至该屏幕。平台共享页面列表不提供租户映射入口。另见 [网站模块](websites)、[网站构建器](website-builder) 和 [页面渲染](page-rendering)。

## 流程

```text
维护 → 页面快捷路径
  选择客户相对路径 + WebsitePage:<id> 或 Page:<id>
  POST 创建 / PATCH 更新 / DELETE 移除（原生 Rails 表单）
  输入无效 → 422，保留输入并显示服务端错误
  已保存的映射 → 主机 + request.path_info → 租户 + 目标
    WebsitePage → 现有网站 home/show 渲染
    Page        → 现有公开页面渲染／提交
```

编辑通过普通 GET 打开列表，携带 `?edit=<id>#shortcut-form`，表单随后向该记录提交 PATCH。移除采用 DELETE，使用 Rails 隐藏方法字段及 CSRF 保护；移除快捷路径不会删除目标页面。表单设置 `data-turbo="false"`，无需 JavaScript。

## 实现

### 主机与路径配置

每个客户的精确域名是可空字符串 `customers.domain`，由平台所有者在该客户资料表单中与组织名称一起设置。例如，为 `forms.acme.example` 配置直接指向 `anysys.net` 的 CNAME，再将该域名保存到客户 12345678。见[自定义域名](custom-domains)。


`PageShortcuts::Hosts.customer_id` 和 `dedicated?` 实时读取数据库绑定，提交后无需重启即可生效。`config.x.page_shortcuts.default_customer_id` 默认为 `81721200`。规范域名全局唯一，每个客户最多一个。停用绑定仍保留，返回 404，不展示默认租户内容。保存新增或变更的域名时，要求应答区中由该精确域名直接持有、指向 `anysys.net` 的 CNAME；仅有 A/AAAA 或间接别名链不能通过。清空域名，或保存资料时域名未变，不检查 DNS。部署负责发布 DNS，并分别配置 TLS、入口路由及 Rails HostAuthorization；保存域名不会将主机加入 Rails 允许列表。

无客户前缀时，使用主机映射的客户，否则使用默认客户。显式八位客户前缀优先。登录会话不决定目标租户。共享主机上，客户 81721200 使用 `/` 和 `/pricing`，其他客户使用 `/:cid/` 和 `/:cid/pricing`。已映射的专属主机为所属客户生成无前缀路径。

### 映射与可访问性

目标类型仅允许 `WebsitePage` 和 `Page`。网站目标须属于当前客户的网站，且网站模块启用、网站及页面均已发布。公开表单目标须有效、已上线、对公众可见，并属于该客户或为共享页面。共享定义通过 `Current.customer` 和 `resolved_current_version` 渲染该客户的覆盖版本。

路由约束复用 `Resolver.cached_resolve(request)`，每个请求共享一次解析。每个固定目标只需一条回退通配路由，即可处理有无客户前缀的路径；客户前缀由解析器提取。根路径仍使用显式路由，分别保留不可用映射和初始化回退行为。`RouteContext` 保留可信的已解析目标，网站分派按记录编号在所选客户及网站内查找，并重新检查发布状态。解析至分派期间的 slug 复用或首页切换不会替换为其他记录。规范网站端点仍按原有首页／slug 规则查找。

`PageShortcuts::Activities::Save` 和 `Websites::Activities::SavePage` 共用 `Collisions.with_customer_lock(customer_id:)`。事务先锁定启用客户，再执行冲突校验、slug 生成和持久化；SQLite 下 Rails 使用即时写事务。持久化快捷路径在创建 Reform 合约前，按显式客户范围重新加载：提交字段应用于最新记录，未提交字段保留当前值。无效更新不改变已保存映射；唯一索引冲突返回本地化错误。直接写模型不执行这项跨表规则，应用写入必须经过上述活动。

输入相对于客户的路径，以 `/` 开头，各段可使用小写字母、数字、短横线及内部单个点，例如 `/join.html` 或 `/campaign.v2/join`，允许 `/`。首尾点及连续分隔符被拒绝。应用命名空间及数字首段仍属于保留路径，包括 `/admin.json`、`/12345678.html` 等带格式的写法。协议、主机、查询、片段、转义、路径穿越、重复斜杠、控制字符及空白均被拒绝。自动网站 slug 仍限于不含点的单段小写短横线格式；含点路径必须有精确保存的映射，不推断格式，也不回退到去掉后缀的别名。自动网站 slug 的冲突由后端路径／冲突策略验证。根路径映射可选择网站首页以外的目标。现有规范网站及 UUID 端点继续可用。

255 字节上限适用于已保存的客户相对路径，包含前导斜杠。可选的 `/:cid` 前缀及部署 `SCRIPT_NAME` 不计入该上限：有效的 255 字节别名可通过添加客户前缀后的 264 字节路由路径及挂载 URL 访问。解析器仅识别规范的八位客户前缀，按同一路径策略校验相对后缀，并在移除挂载前缀后重新校验原始 URI。提取客户前缀不会放宽保留命名空间，也不会允许编码／畸形前缀、重复分隔符、路径穿越或超长相对路径。

`PageShortcuts::Resolver.resolve(request)` 对可访问的网站和公开 `Page` 目标支持 GET/HEAD，仅对符合条件的公开 `Page` 映射支持 POST。`Page` 目标必须在受众集合中含 `public`（`Page.for_audience("public")`）；仅面向会员的页面不能作为快捷路径目标。POST 与读取采用相同的发布状态、公开受众及显式租户／共享归属检查，根路径和专属主机映射同样适用。不可变的 Page 目标保留 `action: "show"`，由 `PageShortcuts::RouteConstraint` 为 POST 选择现有的 `public_pages#submit`。其他写入方法及网站 POST 别名均不解析。

[验证码网关](captcha) 按别名所指向的可信目标的规范路径匹配限流。先精确查询原始路径，再对已知规范路由处理可选格式：`/join.html` 和 `/join` 可分别选择不同的目标及策略。规范路径的计数、跳过规则及放行凭据同样适用于别名。挑战返回路径和 POST 快照保留原始别名、查询、正文及挂载前缀；重放清除旧路由状态，再次经过正常授权及发布检查。查询／正文中的身份参数不能选择其他限流规则或提交目标。

创建下拉框只提供当前符合条件的目标。已保存的下线或已删除映射仍显示在列表，标记为「不可访问」，编辑时保留目标身份，并可移除。仅可访问的目标提供公开链接。请求时检查才是最终依据；发布状态变化不会绕过访问控制。不可访问的已保存映射返回失败，不会在同地址改为展示其他页面。

### 展示与依赖库

`PageShortcuts::ManagementComponent` 接收 `shortcuts:`、`available_targets:`（`[显示标签, "Type:id"]`）、`customer_id:`，以及可选的 `errors:`、`form_values:`、`editing_shortcut:`。组件复用后台外壳和卡片，提供明确的标签、关联的说明／错误、错误摘要、原生下拉框，以及在 `md` 以下堆叠的语义表格。英文和简体中文文案放在成对 locale 文件的 `page_shortcuts` 下；后端校验文案使用独立的 `page_shortcut_errors.*` 文件。

管理下拉框通过 `TargetEligibility` 作用域和标量 `pluck` 查询读取标签。组件复用一个 `Lookup.new(customer_id:, host:, include_titles: true)`，提供已保存标签、可用性和按主机生成的链接。`Lookup#shortcut_available?` 也用于构建首选公开别名，共用规范路径、目标和冲突检查。`#target_title(type, id)` 读取网站标题，并批量查询已保存的本客户／共享 Page 名称，包含保留的下线／已删除记录；缺失或其他客户的记录不返回标签。控制器及组件均不预加载多态目标、不加载 Page 定义，查询次数不随记录数量线性增长。普通公开快照不执行这项可选名称查询。

`PageShortcuts::PublicPath` 提供 `website_home`、`website_page`、`website_slug`、`public_page`、`public_page_uuid(uuid:, customer_id:, host: nil)` 和 `shortcut`。展示层传入 `request.host`；`PageShortcutsHelper#page_shortcuts_mounted_path` 添加 Rack 的 `SCRIPT_NAME`。未传主机时使用共享主机默认规则。`Websites::Href.resolve(value, customer_id:, host: nil)` 转换有效的已保存本地网站及 UUID 地址。UUID 解析为符合条件的本客户／共享公开 Page 返回首选别名；无别名时返回规范 UUID 路径。不可访问、其他客户或未知身份返回 nil，由 Href 保留原规范链接。外部 HTTPS、媒体及其他应用路径沿用原有处理，同时保留语言、重复查询参数及片段。

`PageShortcuts::PublicPathContext` 在两个公开控制器外层调用 `PublicPath.with_lookup(customer_id:, host: request.host)`。可选的 `host:` 默认为 nil，保留现有服务调用方式。仅在已授权客户的渲染／提交范围内，将不可变的 `PageShortcuts::Lookup` 放入 `Current.page_shortcuts_lookup`。网站身份（含未发布页面的冲突 slug）、快捷路径身份及所有符合条件的本客户／共享公开 Page 的 UUID 身份映射均批量读取，包含未配置别名的 Page。快照仅捕获传入的规范化主机及其所选客户编号，并检查一次网站／模块可访问性；网站与 UUID 混合导航及页脚的不同目标增加时，SQL 次数仍保持有界。这不是主机注册表：其他主机／客户及直接 `Hosts` 调用仍执行实时查询。UUID 链接使用标量身份，不实例化 Page，也不触发 after-find 定义加载。around-action／代码块在异常及嵌套主机范围中也恢复原值，Rails 在请求之间重置 Current。范围外的服务调用仍读取最新数据库状态；下一渲染范围／请求会看到主机绑定、别名和发布状态变化。路由及保存校验不使用展示快照。

方案采用成熟的 Rails Action Dispatch/Journey 路由和现有 Addressable URI 库，不自行实现重写中间件或 URI 解析。公开渲染及分区／页脚／导航链接复用现有 ViewComponent 和 Tailwind。

## 需要特别注意

### 路由审计：全部 slug 写入及重放不变量

网站开通、直接骨架应用及替换与快捷路径／SavePage 共用 `Collisions.with_customer_lock`。删除旧页前检查完整结构及全部候选路径，畸形／冲突替换保留页面／映射。外租户公共会话可访问有效目标，但不选择租户或获得同租户归属。

验证码规范策略覆盖已知可选格式端点及别名。重放保留原路径／查询／正文／挂载及 CSRF／来源证据，绑定同一会话，再检查目标身份／发布。通过挑战不能授权原本无效写入。见[验证码](captcha)、[网站](websites)、[页面渲染](page-rendering)。

:::note
快捷路径策略、解析器及验证码重放测试覆盖租户、发布状态和格式边界。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。真实浏览器流程仍须另行验证。
:::

:::attention
管理仅允许 admin／owner，编辑／更新／删除限定 URL 租户。公开读取允许匿名及外租户已登录访客访问符合条件的已发布目标；受保护跨租户限制仍有效。见[租户与角色](tenancy-and-roles)。
:::

:::attention
网站及公开表单别名支持 GET/HEAD。公开表单别名也可经现有提交授权和流程图管线接收 POST，网站别名不接收 POST。生成的表单继续提交到规范 `/:cid/page/:uuid`，而非当前别名。映射不会改变页面的受众或发布状态。
:::

:::attention
在 `/`，符合条件的显式映射优先；没有映射时，自动展示已发布的网站首页。已保存但不可访问的根路径映射进入固定的 `PageShortcuts::UnavailableController#show` 路由，GET/HEAD 返回空正文 404；目标缺失、非公开、已删除或客户停用时，共享及专属主机均遵循此规则。专属主机所映射客户不存在或已停用时也返回 404。共享主机未配置显式映射且没有已发布的自动首页时，保留 HomeController 原有的登录／落地回退，即使默认平台客户尚未创建也可用于初始化。已知停用的默认客户（取消默认作用域查询后仍存在该行）返回 404，不走初始化回退。移除根映射后恢复自动首页或适用的回退。`Resolver.resolve` 仍返回 Target／nil，由 `Resolver.unavailable_root?` 区分根路径的终止失败，无需向验证码或链接服务传递哨兵目标。
:::

## 关键代码

```ruby
PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: request.host)
PageShortcuts::PublicPath.website_page(page: page, host: request.host)
PageShortcuts::PublicPath.public_page(page: page, customer_id: cid, host: request.host)
Websites::Href.resolve("/81721200/site/pricing?tag=a&tag=b#plans", customer_id: cid, host: request.host)
```

```ruby
render PageShortcuts::ManagementComponent.new(
  shortcuts: @shortcuts, available_targets: @available_targets,
  customer_id: current_customer_id, errors: @errors || [],
  form_values: @form_values || {}, editing_shortcut: @editing_shortcut
)
```
