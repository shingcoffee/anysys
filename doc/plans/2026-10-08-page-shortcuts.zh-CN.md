# 页面快捷路径——实现方案与 UX 契约

状态：设计提案，可进入实施规划。仅进行源码检查和文档研究。

## 1. 技术决策与 URL 行为

- 使用 Rails 8.1.2 Action Dispatch/Journey 的根路由、通配路由和请求约束。沿用现有 `addressable` 依赖（锁定版本 2.8.8）解析 URI、保留查询参数和片段。不引入重写中间件或 `rack-rewrite`。
- 将别名直接路由至 `Websites::PagesController#home`、`#show` 或 `PublicPagesController#show`，地址栏保留别名。现有网站、媒体、公开页面和提交端点继续可用。
- `config.x.page_shortcuts.hosts` 为规范化主机名到客户 ID 的精确映射；`config.x.page_shortcuts.default_customer_id` 默认为 `81721200`。主机映射属于部署配置，不提供租户编辑字段。专属主机也需加入 Rails HostAuthorization。
- 无客户前缀时，先按主机映射选择客户，否则使用默认客户。显式八位客户前缀始终决定客户。不根据登录会话推断客户。

| 公开 URL | 解析规则 |
|---|---|
| 共享主机上的 `/` | 客户 81721200 的首页；模块、网站和首页均已发布时展示，否则沿用 `HomeController#index` |
| 共享主机上的 `/pricing` | 自动展示平台网站已发布的 `pricing` 内页 |
| 共享主机上的 `/join` | 客户 81721200 配置的 `/join` 快捷路径 |
| `/12345678/pricing` 或 `/12345678/join` | 客户 12345678 的自动网站内页或显式快捷路径 |
| 映射至 12345678 的主机上的 `/` 或 `/pricing` | 该客户已发布的首页或内页 |
| `/12345678/` | 该客户已发布的首页；首页不可访问时返回 404 |

别名仅支持 GET/HEAD。公开表单继续向 `/:cid/page/:uuid` 提交 POST；必须明确使用现有提交路径 helper，不能向当前别名提交。未匹配的非根路径返回正常 404。根路径回退同时保留匿名登录页和 HomeController 的已登录用户跳转行为。

## 2. 存储、目标资格与路径冲突

- `PageShortcut`：必填 `customer_id`、`path`、`target_type`、`target_id`，另加时间戳。数据库为 `(customer_id, path)` 建立唯一索引；增加客户外键和目标查询索引。不增加 `enabled`：删除记录即移除显式映射。
- 目标类型仅允许 `WebsitePage` 和 `Page`。通过白名单解析提交值 `WebsitePage:<id>` 或 `Page:<id>`，不对任意输入调用 constantize。`customer_id` 来自已授权的 URL 客户上下文，不读取表单值。
- 网站目标必须属于快捷路径的客户及其网站。可访问条件为 Website 模块启用、网站发布、页面发布。首页目标进入 `#home`；内页目标进入 `#show`，使用记录当前的 slug。
- Page 目标必须有效、已上线、对公众可见且可由该客户访问：客户自有记录或共享记录（`customer_id NULL`）。共享定义通过所选客户的 `Current.customer` 和 `resolved_current_version` 解析。所有者在其他客户上下文中管理路径时，也不能指向第三个客户的私有记录。
- 创建时只提供当前符合条件的目标。目标下线后保留快捷路径，展示派生的“不可访问”状态；恢复资格前请求返回 404。目标被删除后仍可移除快捷路径，不能导致列表报错。每次请求重新检查资格。
- 存储路径为一个前导斜杠加小写短横线分段，例如 `/join` 或 `/campaign/spring`；允许输入时省略前导斜杠，并规范化单个尾部斜杠。拒绝空路径、`/`、重复斜杠、点或点路径段、百分号转义、反斜杠、控制字符、内部空白、协议、主机、查询和片段。输入的是客户相对路径，不是 `/12345678/join`。
- 保留 `/`、以八位客户号开头的路径，以及应用命名空间，包括 `admin`、`member`、`auth`、`oauth`、`locale`、`up`、`captcha`、`payments`、`sms`、`email`、`unsubscribe`、`page`、`site`、`site-images`、`assets`、`rails` 和 `.well-known`。按路径段边界判断，不能粗略匹配前缀。验证和运行时解析共用路径策略，并在路由测试中与 `config/routes.rb` 对照。
- 显式快捷路径不能占用自动网站 slug，包括未发布内页的 slug。首版也拒绝指向相同目标的重复映射。自动网站路径不生成 PageShortcut 记录，不能在此移除。
- 创建、修改或发布网站 slug 时进行反向冲突验证。既有保留 slug 仍可通过 `/:cid/site/:slug` 访问，但不生成自动简洁 URL。历史数据出现显式／自动冲突时，网站路由优先，显式映射标记为不可访问；不能将旧别名悄然指向无关目标。

## 3. 路由与租户回调契约

1. 在具名 `root "home#index"` 前加入未命名的受约束 GET `/`，指向现有网站首页 action；约束要求首页可公开访问。保留唯一的 `root_path` helper 及其回退。
2. 在现有端点之后追加兼容 GET/HEAD 的 `/:customer_id/*shortcut_path` 和 `/*shortcut_path`，设置 `format: false`。目标 controller/action 固定，通过轻量请求约束区分网站首页、网站内页和公开 Page。
3. `PageShortcuts::Resolver` 返回包含 `customer_id`、目标身份、目标类别及规范 `page_slug` 或 `uuid` 的类型化结果。路由约束运行时尚未设置 `Current.customer`，查询必须显式按客户限定。读取 `request.host` 和 `request.path_info`，不信任查询／请求体参数或可变的 `req.params`。
4. 查询结果仅缓存在当前请求环境中，以主机／路径为键。约束只选择目标，不修改 PATH_INFO、SCRIPT_NAME、Current 或路由参数。请求时解析，不在绘制路由时加载数据库记录。
5. 两个现有公开 controller 引入 `PageShortcuts::RouteContext`，为快捷路径路由添加前置回调。将可信解析结果写入 `params[:customer_id]`（项目实际键名，不是 `:cid`）、`params[:page_slug]` 或 `params[:uuid]`，并在常规回调前调用现有 `set_current_tenant(customer_id, true)`。租户解析失败后立即停止。只注入 params 不够：`TenantContext#auto_set_tenant_from_path` 读取实际路径。
6. 保留现有租户策略：匿名访客可以访问任意客户已发布的公开资源；非所有者登录用户的跨租户请求仍由 TenantContext 拒绝。不能直接赋值 Current 来绕过此限制。所有者上下文及发布／可见性检查继续执行。未知、禁用或删除的目标返回失败，不回退至同路径的其他目标。

## 4. 公开链接生成

- 增加轻量 `PageShortcuts::PublicPath` 接口，供网站链接、后台地址展示和公开 Page 链接共用。当前主机为客户专属主机，或共享主机上的默认客户时，生成 `/`、`/pricing`；其他情况生成 `/:cid/`、`/:cid/pricing`。显式快捷路径使用相同前缀规则。
- 网站优先使用自动路径；保留 slug 使用原有网站路径。公开 Page 存在多个有效快捷路径时，固定选择规范路径按字典序排序后的第一条；否则使用 `public_page_path`。
- 接入 `Websites::Href`、`PublicComponent#href_for`、`NavComponent#home_href`、HomeSite 专属导航、页脚／区块链接和网站／页面地址展示。在渲染时转换有效的原有本地网站／Page 链接，通过 Addressable 保留重复查询参数、片段和语言参数。外部 HTTPS、媒体及其他应用路径沿用既有处理。
- 保留不传请求主机时调用 `Websites::Href.resolve` 的能力，兼容现有 service／spec：有主机时显式传入，无主机时使用文档明确的共享主机默认规则。列表和导航批量加载快捷路径候选。

## 5. 界面清单与布局

| 界面 | 导航归属 | 契约 |
|---|---|---|
| `/:cid/admin/maintenance/page_shortcuts` | 后台 → 维护 → 页面快捷路径 | 当前客户的统一管理页 |
| 现有维护首页／侧栏 | 后台 → 维护 | 增加管理入口卡片和侧栏项 |
| 网站设置的发布卡片 | 后台 → 设置 → 网站 | 简洁网站地址及“管理页面快捷路径”次要链接 |
| 租户维护 → 页面列表 | 后台 → 维护 → 页面 | 增加次要管理链接；不放入平台共享资源管理 |
| 已发布网站／公开页面别名 | 公开 | 复用现有页面布局和渲染，导航及地址使用简洁路径 |

管理页由 `AdminPageComponent` 提供“维护 → 页面快捷路径”面包屑、本地化标题／描述及常规后台宽度。主体使用 `space-y-6`，按文档顺序排列两张全宽卡片：

1. **添加卡片：**标题、描述、服务端错误摘要、路径输入、目标原生下拉框、说明和主要“添加快捷路径”按钮。字段使用 `grid grid-cols-1 gap-4 md:grid-cols-2`、`min-w-0`、可见 `form-label` 和 `input-field min-h-11 w-full`；路径用 `font-mono`。按钮在移动端全宽，从 `sm` 起按内容宽度展示。说明网站首页／内页路径自动生成，输入路径相对于当前客户。
2. **已保存卡片：**路径／公开链接、目标（类型＋已保存标题／名称）、可访问状态和操作。从 `md` 起使用语义化表格；低于 `md` 使用堆叠行，显示翻译后的字段标签并允许路径换行（必要时 `break-all`）。每行“移除”使用独立表单及危险操作样式。仅为可访问目标提供链接，按路径排序。自动路径单独说明，不混入可删除记录。

采用 shadcn Card 的标题／描述／内容／底部结构、Input/Field 的标签／说明／错误关联、Table 的语义结构，以及 Native Select 的原生移动端交互，通过 ViewComponent＋Tailwind 实现。

复用 `AdminPageComponent`、`CardComponent`（`padding: :none`，内部区域使用 `p-4 sm:p-6`）、`ButtonComponent`、`BadgeComponent`、`EmptyStateComponent`、`AlertComponent`（不开启自动消失）和 `QuickActionCardComponent`。新建 `PageShortcuts::ManagementComponent`，封装原生表单及响应式表格／堆叠行。`AdminTableComponent` 作为视觉参考；其删除链接依赖 Turbo，不符合本界面无 JS 操作契约。`FormErrorsComponent` 要求传入 resource，因此本方案的 `errors` 输入使用 AlertComponent 和字段错误展示。

## 6. 组件、操作与状态

必填输入为 `shortcuts:`、`available_targets:`、`customer_id:`；可选 `errors: {}`。`available_targets` 是 `[显示标签, "WebsitePage:<id>" | "Page:<id>"]` 数组；标签由翻译后的类型名及经过转义的记录标题组成。预加载目标，在 URL 当前客户上下文中计算可访问状态。建议增加 `form_values: { path: "", target: "" }` 保留失败输入，以及 `editing_shortcut: nil` 支持更新流程。

- 创建：`form_with scope: :page_shortcut`，POST 至 `admin_maintenance_page_shortcuts_path(customer_id)`，仅包含 `page_shortcut[path]` 和 `page_shortcut[target]`。
- 移除：`button_to` 指向单条 helper `admin_maintenance_page_shortcut_path(customer_id, shortcut)`，通过 Rails 隐藏方法字段和 CSRF token 提交 DELETE。明确说明移除快捷路径不会删除页面。采用原生提交，不增加确认弹窗。
- 建议 REST `index/create/update/destroy`。编辑通过普通 GET 打开索引页，携带 `edit=<已限定客户的 id>#shortcut-form`；复用已填值卡片，PATCH 至单条 helper，提供保存和取消。更新保持原子性；移除后重建会造成不必要的访问中断。无需独立编辑页。
- 修改由客户限定的 Activities 和 Reform contract 承担。管理 controller 继承 `RouteAuthorization` 的 admin／owner 门禁；所有者会话也必须按 `(customer_id, id)` 查找记录。成功后以 303 返回索引并显示本地化 flash；验证失败以 422 返回完整索引，保留输入并显示字段错误。
- 空列表：EmptyState 说明网站路径自动生成，保留创建表单。无可选目标：禁用下拉框和提交按钮，链接至相关页面发布界面。编辑中的不可访问目标仍需可识别、可移除，不能静默选中其他目标。
- 无障碍：明确 input ID／label、必填属性；错误字段设置 `aria-invalid`；`aria-describedby` 关联说明和错误 ID；错误摘要设置 `role="alert"`；表格提供 caption 和表头 scope；操作目标至少 44 px，焦点可见，每行控件 ID 唯一。使用原生键盘下拉框和表单，不增加功能专用 JavaScript 或加载骨架。管理表单关闭 Turbo，禁用 JS 后仍可用。

## 7. 本地化文案

功能键放入 `config/locales/maint_core.en.yml` 和 `.zh-CN.yml` 的 `maint_core.page_shortcuts`；侧栏标签同时加入两份 `chrome` 文件。英文完全一致时复用通用操作键。验证错误、flash、描述、标题、占位符、类型及无障碍标签均需翻译，并在调用时解析。

| English | 简体中文 |
|---|---|
| Page shortcuts | 页面快捷路径 |
| Add shortcut | 添加快捷路径 |
| Path | 路径 |
| Destination | 目标页面 |
| Enter a path such as /join. Website page URLs are created automatically. | 输入路径，例如 /join。网站页面的访问路径会自动生成。 |
| Website page / Public page | 网站页面／公开页面 |
| Available / Unavailable | 可访问／不可访问 |
| No shortcuts yet | 暂无快捷路径 |
| Removing a shortcut keeps the page. | 移除快捷路径不会删除页面。 |
| This path is reserved by the application. | 此路径为系统保留路径。 |
| This path is already used by a website page. | 此路径已被网站页面使用。 |
| This destination is not publicly available. | 此目标页面当前不可公开访问。 |

## 8. 实施顺序与验收

1. 后端：迁移／薄模型、共用路径／目标策略、保存／删除 Activities 和 Reform contract、解析器和主机配置；包括网站 slug 反向冲突验证。
2. 路由：固定目标约束、回调 concern、首页资格／回退、公开路径接口及既有链接／地址接入。
3. 前端：管理 ViewComponent、原生表单、更新流程、发现入口及成对翻译。
4. 文档：实施时在 `doc/reference/en/` 和 `doc/reference/zh-CN/` 增加 `page-shortcuts.md`，注册至 `DeveloperDocs::Catalog`；按影响范围更新并关联 `websites`、`website-builder`、`page-rendering`、`member-and-public`、`tenancy-and-roles`、`system-map`。本提案不将功能描述为已部署。
5. 验证：针对模型／contract／activity／解析器／路径／组件／后台请求／公开请求运行测试；同时覆盖现有首页、网站公开页面、Href、公开页面可见性／提交、路由授权和跨租户隔离测试。由于路由与租户上下文具有跨模块影响，随后运行完整测试；条件允许时使用 `bin/rails parallel:prepare && bin/rails parallel:spec`。

验收覆盖：已发布 `/` 和 `/pricing`、HomeController 回退、两个客户的同名快捷路径、专属／共享主机及显式前缀、伪造 cid／slug／uuid 查询参数、根路径／命名空间／保留 slug、唯一索引并发冲突、双向自动／显式冲突、首页目标别名、下线／重新上线／删除、共享 Page 的客户覆盖、原有 GET／POST／媒体端点、支持 HEAD 并拒绝其他别名请求方法、语言／查询／片段保留、客户限定的管理权限、422 输入保留、禁用 JS 的创建／更新／移除，以及 EN／zh-CN 在 320／390／768／1024／1440 px 和 200% 缩放下的布局。

研究依据：`AGENTS.md`、`.cursor/agents/anysys-ux-designer.md`、既有 controller／model／component／spec；官方 [Card](https://ui.shadcn.com/docs/components/card)、[Table](https://ui.shadcn.com/docs/components/table)、[Native Select](https://ui.shadcn.com/docs/components/native-select)、用户提供的 Input 研究，以及 [Rails 8.1.2 路由 mapper](https://github.com/rails/rails/blob/v8.1.2/actionpack/lib/action_dispatch/routing/mapper.rb)。当前 harness 不提供 shadcn skill／MCP，组件设计以官方文档为依据。
