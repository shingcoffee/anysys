# 客户主机名——客户详情下的独立管理页

日期：**2026-10-10**。状态：**READY_FOR_FRONTEND / READY_FOR_PARALLEL_BUILD**。仅包含调研、设计及实施交接。

**最终澄清——客户详情和编辑页：**第 10 节替代此前仅通过独立页面展示／入口访问的假设，并扩展文件归属／接口交接。两个客户资料页面均须提供独立、限定客户范围且带编辑控件的主机名分区；独立页面仍是主机名编辑及操作响应的目的地。

## 1. 已确定范围与调研

客户详情和编辑页均显示属于当前客户的独立主机名管理分区。分区中的「管理」及行「编辑」链接打开该客户下可收藏的独立主机名页面，主机名提交也使用其嵌套路由。独立页面仅管理该客户的主机名，并提供明确的客户详情返回入口。页面快捷路径入口使用此独立目的地。全局「客户」首页继续显示客户表格和全局主机名管理分区。

本次后续设计替代[客户上下文／DNS 方案](2026-10-10-customer-hostnames-context-dns.zh-CN.md)中仅使用合并页面的入口、绑定表单路由／隐藏目标字段及绑定返回上下文要求。已有客户绑定语义、停用客户规则、保存时 DNS 校验和锁内归属检查仍是实施基线。本切片新增路由、控制器页面编排及前端组合；**无需后端开发者修改业务层**。无需修改数据库结构、DNS／服务／Activity／Contract 或 JavaScript。

已调研：`.cursor/agents/anysys-ux-designer.md`、`AGENTS.md`、相关 `.cursor/rules/`、当前主机名管理／入口组件及规格、客户视图／控制器、主机名控制器、共享 `CustomersIndexContext`、`RouteAuthorization`、`PageShortcuts::PathPolicy`、路由、`AdminPageComponent`、`BreadcrumbsComponent`、设置页外壳、EN／zh-CN UI locale 和受影响的开发者参考。客户详情目前已传入 `@customer.id`，包含停用客户；页面快捷路径已传入其 URL 客户编号。修改共享入口目的地即可覆盖两处。

本环境未提供 shadcn skill／MCP。沿用前一任务已查阅的官方 [shadcn Field 文档](https://ui.shadcn.com/docs/components/field)，以及前一方案中的 FieldTitle／只读内容／FieldDescription 和 FieldLabel／控件／FieldError 指引。通过项目现有 ViewComponent + Tailwind 基础组件组合 **Card／Breadcrumb／Field 模式**，使用原生 Rails 表单。本设计不引入 React 包或新控件。

## 2. 界面清单

| 界面 | 导航区域／受众 | 设计 |
|---|---|---|
| 客户详情 → 管理客户主机名 | admin → 维护 → 平台 → 客户；平台所有者 | 共享入口打开所选客户的嵌套主机名页面。 |
| 独立客户主机名 GET／编辑状态 | 同上 | 新增 `CustomerHostnames::CustomerPageComponent` 外壳，复用管理表单和限定范围的已保存列表；不显示客户表格。 |
| 嵌套 POST/PATCH/DELETE 及完整 422 页面 | 同上 | 复用现有主机名控制器；根据嵌套路径参数返回／渲染独立页面。 |
| 全局客户 GET 及全局主机名增改删 | 同上 | 保留现有合并页面及表格上下文行为。 |
| 可选查询绑定客户 GET／全局增改删 | 同上 | 继续支持原有目标绑定语义；渲染出的绑定管理控件改用嵌套 URL。不设置兼容重定向。 |
| 页面快捷路径 → 管理客户主机名 | admin → 维护 → 页面快捷路径；入口仅向所有者显示 | 共享入口打开快捷路径 URL 客户的独立主机名页面。 |

「客户」仍是平台侧栏入口。独立子页不新增侧栏项或受众。URL 属于 admin 类别，仅平台所有者可访问。

## 3. 布局规范

```text
现有响应式 dashboard 外壳／选中「维护」

维护 / 客户 / Acme / 客户主机名
管理客户主机名                                      [← 返回]
仅显示 Acme（12345678） 的主机名。

客户主机名 h2
现有公开快捷路径路由说明
┌ 添加主机名／编辑主机名 h3 ──────────────────────────────┐
│ 现有 DNS／部署说明                                      │
│ 持续显示的校验错误摘要（有错误时）                       │
│ 主机名                           客户                   │
│ [forms.acme.example          ]    Acme（12345678）       │
│ 现有提示／字段错误                只读上下文提示         │
│ 停用目标说明（适用时）                                  │
│ [添加主机名／保存] [取消，仅编辑时]                      │
└────────────────────────────────────────────────────────┘
┌ 已保存的主机名 h3 ──────────────────────────────────────┐
│ 仅显示 Acme（12345678） 的主机名。                       │
│ 现有移除说明                                           │
│ 主机名 | 客户名称＋编号 | 可用状态 | 操作                │
│ 仅 customer_id = 12345678；编辑／移除                    │
│ 现有可用状态说明                                       │
└────────────────────────────────────────────────────────┘
```

- **外壳：**由 `CustomerPageComponent` 包装，仅渲染一次 `AdminPageComponent`。沿用 dashboard 默认内容宽度和正常文档滚动。`customer_hostnames.manage` 提供唯一 h1；保留现有带标识的管理 h2 和卡片 h3。Flash 由 dashboard 布局统一展示，组件不重复渲染成功提示。
- **面包屑：**维护 → 客户 → 目标客户名称 → 客户主机名。「维护」链接 `admin_maintenance_path(81721200)`；「客户」链接 `admin_maintenance_platform_customers_path(81721200)`；客户名称链接 `admin_maintenance_platform_customer_path(81721200, target_customer.id)`；末级无链接。客户名称作为转义后的数据展示，不作为翻译标签。新增／编辑／422 状态及停用目标均使用此层级。
- **页头：**描述复用 `customer_hostnames.target_saved_hint`，其中 `%{customer}` 由 `customer_hostnames.customer_option` 生成，展示真实目标名称和编号。次要「返回」操作复用 `common.actions.back`、图标 `:back`、上述固定客户详情 helper、`data: { turbo: false }` 及 `min-h-11 w-full sm:w-auto whitespace-normal`。「返回」是确定的页面导航，不依赖浏览器历史。
- **管理主体：**复用现有两张卡片和全部字段／列表列。目标身份映射至 `Customer#name/#id`；停用状态映射至 `Customer#active?`；行映射至 `CustomerHostname#id/#hostname/#customer_id` 及已加载的客户关联。管理分区描述仍解释公开快捷路径路由。独立页不增加客户表格、搜索、排序、分页、客户选择器或改绑控件。
- **操作：**表单内「添加／保存」为主要操作，编辑时旁边显示次要「取消」；各已保存行提供次要「编辑」和危险操作「移除」。「返回」位于页头。沿用现有移除语义和说明，不新增确认交互。
- **空状态：**保留新增表单和 `EmptyStateComponent`，使用 `empty_title` 与 `target_empty_hint`。启用目标可新增首个主机名。停用目标保留身份／说明并禁用主机名／添加控件；已有记录仍可编辑／移除，编辑范围内已有绑定时启用主机名／保存，客户保持只读。
- **错误：**原生 422 渲染完整独立页面；`role="alert"` 内使用持续显示的 `AlertComponent(type: :error, auto_dismiss: false)`，保留转义后的原始尝试主机名（包括空值）、字段错误及已保存编辑身份。客户错误仍关联只读分组，基础错误放入摘要，保留已有 `aria-invalid`／`aria-describedby`。编辑身份属于其他客户或已移出范围时返回 404，不显示其他客户内容，也不静默切回新增。
- **加载：**使用正常原生导航／提交；现有有界 DNS 操作可能使保存等待。不新增加载面板、实时 DNS 状态或 JS 转圈。DNS 失败使用已有翻译后的主机名错误；移除仍不依赖 DNS。

### 响应式与无障碍规则

- 外壳包装使用 `min-w-0 [&_h1]:whitespace-normal [&_h1]:break-words`，参考 `Admin::Settings::PageComponent`。名称／编号过长时，页头身份文本转义后使用 `break-words [overflow-wrap:anywhere]` 换行。通过渲染时 helper 构造安全标记，不对客户输入调用 `html_safe`。
- 面包屑复用现有带标签 nav 和小屏局部 `overflow-x-auto`。长面包屑在该区域内滚动，不撑开视口；不重设计共享面包屑。
- 主体沿用 `space-y-6`；卡片 `p-4 sm:p-6`；表单 `space-y-5`；字段 `space-y-2`；`grid grid-cols-1 gap-4 md:grid-cols-2`；`min-w-0`；项目语义颜色／文字 token；名称／错误 `break-words`；主机名 `break-all`。卡片不设固定宽度。
- 页头和表单操作在 `sm` 以下纵向堆叠；已保存行沿用移动端块布局和字段标签，在 `md` 改为语义 `md:table`／`md:table-fixed`。移动端保留全部四列和两个行操作。触控目标使用 `min-h-11`。
- 保留真实主机名 label/input。绑定客户身份仍为不可聚焦的只读文本，通过 `role="group"` 关联标题／提示／错误，不使用禁用 select 或指向不存在控件的 label。保留原生 CSRF／方法覆盖字段、键盘链接／按钮及现有外部主机名链接的 `noopener noreferrer`。
- **Stimulus：**不新增 controller／action／value。禁用 JavaScript 时，添加／编辑／取消／保存／移除／返回仍可用。

## 4. 路由与目标解析契约

明确区分两个 URL 客户身份：

- 外层 `request.path_parameters[:customer_id]` 是平台授权 CID，必须等于字符串 `"81721200"`。
- 内层 `request.path_parameters[:hostname_customer_id]` 是主机名管理的权威目标。不能使用 Rails 默认嵌套 `:customer_id`，否则与外层 scope 冲突。

定义 `G = /81721200/admin/maintenance/platform/customers`，`N(C) = G/:hostname_customer_id/hostnames`，其中路径目标为 `C`。

| 方法／路径 | 控制器 action | Helper |
|---|---|---|
| GET `N(C)` | `admin/maintenance/platform/customer_hostnames#index` | `admin_maintenance_platform_customer_hostnames_path(81721200, target.id)` |
| POST `N(C)` | 同一控制器 `#create` | 同一集合 helper |
| PATCH `N(C)/:id` | 同一控制器 `#update` | `admin_maintenance_platform_customer_hostname_path(81721200, target.id, row)` |
| DELETE `N(C)/:id` | 同一控制器 `#destroy` | 同一记录 helper |
| GET `G` | 现有 `customers#index` | 现有 `admin_maintenance_platform_customers_path(81721200)` |
| POST `G/hostnames`；PATCH/DELETE `G/hostnames/:id` | 现有主机名增改删 action | 现有复数 `customers` 集合／记录 helper |

安全工程师在现有 admin/maintenance/platform 路由 scope 内新增显式 scope，与全局主机名增改删及 Customers resources 并列。以下路由示意固定 helper 名称，不修改普通 Customers 路由参数：

```ruby
scope "customers/:hostname_customer_id", as: :customer do
  resources :hostnames, only: %i[index create update destroy],
            controller: "maintenance/platform/customer_hostnames"
end
```

不新增全局主机名 index，也不设置独立 new/show/edit action 或控制器。编辑使用 GET `N(C)?edit_hostname=<row-id>#hostname-form`。实施时验证 helper 参数顺序和路由识别。

### 权威目标与页面模式

1. 先执行继承的认证／平台所有者／CanCan 门禁，再执行现有精确外层平台路径检查；这些检查先于目标／主机名／表格读取。
2. 根据 **`request.path_parameters` 中键是否存在**判断嵌套模式，不使用合并后的 `params`：`request.path_parameters.key?(:hostname_customer_id)`。存在时，使用现有严格 CID 策略（`PageShortcuts::PathPolicy.customer_id`，八位且首位非零）验证路径值，再由 `Customer.unscoped.find(cid)` 解析。客户不存在／无效返回 404，不回退到查询／请求体。已有停用客户仍可访问。
3. 仅在路径键不存在时，保留 concern 当前可选 `target_customer_id` 回退语义：未提供为全局；显式无效／空值／非标量／客户不存在返回 404；有效值建立查询绑定的合并上下文。这是已有路由上的持续行为，不是重定向兼容层。
4. 嵌套请求中，查询／请求体的 `target_customer_id` 和 `hostname_customer_id` 均不能覆盖真实路径目标，也不能使其失效，即使内容冲突或畸形。这些值作为路由上下文被忽略。服务端以解析出的目标覆盖 `customer_hostname[customer_id]`，包括缺失／空值／伪造值，沿用当前绑定行为。保留已有强参数白名单，不新增针对平台所有者额外字段的拒绝逻辑。
5. 列表、GET 编辑、路径选定的更新／移除记录及失败编辑恢复均使用 `hostname_scope`。增改删通过 `request.path_parameters[:id]` 选定记录，查询／请求体记录编号不可替代。记录不存在／属于其他客户时，在调用 Activity 前返回 404。继续向 Save/Destroy 传入 `expected_customer_id: @hostname_target_customer&.id`，保留锁内并发改绑防护。
6. **响应选择由路径决定：**嵌套增改删成功 → 嵌套 GET；失败 → 独立 index 视图。全局增改删成功／失败仍使用合并客户页，即使原请求携带有效查询／请求体目标。不能仅凭 `@hostname_target_customer` 选择模板。
7. 嵌套页面忽略 `q/sort/dir/page`：不准备表格、不筛选、不校验这些值、不生成隐藏字段或转发。额外键可接受，但不作为表格状态消费。嵌套返回仅保留路径目标和 `#hostname-form`，清除 `edit_hostname`。已有合并页面／全局增改删保留其标量白名单表格上下文及可选的已验证目标。

## 5. 交互与失败流程

| 起点／操作 | 结果及下一 URL |
|---|---|
| 客户详情 → 管理客户主机名 | 原生 GET `N(displayed_customer.id)#hostname-form`；显示目标名称／编号、空新增表单及仅属于该目标的记录。停用客户入口仍指定该目标。 |
| 页面快捷路径 → 管理客户主机名 | 原生 GET `N(shortcuts_url_customer.id)#hostname-form`，仍使用平台 CID 81721200。 |
| 未指定目标的入口 | 现有 GET `G#hostname-form`，打开合并全局页面。 |
| 嵌套新增 | 原生 POST `N(C)`，仅提交主机名业务字段；服务端分配 C。成功以 303 返回 `N(C)#hostname-form`，显示保存 Flash、刷新记录并恢复空新增状态。 |
| 嵌套编辑 → 保存 | GET `N(C)?edit_hostname=R#hostname-form`，随后原生 PATCH `N(C)/R`。成功以 303 返回 `N(C)#hostname-form`；保留 C，清除编辑状态。 |
| 嵌套取消 | GET `N(C)#hostname-form`；丢弃尝试值并清除编辑状态，保留目标。 |
| 嵌套移除 | 原生 DELETE `N(C)/R`；成功以 303 返回 `N(C)#hostname-form`，显示移除 Flash、刷新列表并清除编辑状态，即使当时编辑的是另一行。 |
| 保存校验／重复／DNS／冲突失败 | 在提交的嵌套操作 URL 返回 422，使用 dashboard 布局、独立外壳、限定列表、原已保存编辑身份和原始尝试值。重试表单仍指向嵌套集合／记录操作。 |
| 移除失败 | 422 独立页保留移除表单携带的另一编辑身份和尝试主机名；Destroy 仍仅操作路径选定行。在范围内重载被移除／编辑身份，移出范围或不存在时返回 404。 |
| 返回／客户面包屑 | GET `admin_maintenance_platform_customer_path(81721200, C)`；「客户」面包屑打开全局 G，不继承表格查询。 |
| 原查询绑定合并 GET | 如今仍渲染合并页；其绑定新增／编辑／取消／移除控件指向 N(C)。使用任一控件即进入独立流程。合并来源页上的表格搜索／排序／分页可继续保留其已验证旧目标。 |
| 直接调用带有效目标的原全局增改删 | 保留当前绑定范围，以及携带表格／目标上下文的合并 303／422 响应。随后渲染出的绑定重试／取消／编辑／移除控件使用嵌套 URL。 |
| 无效目标／过期或其他客户记录 | 标准 404，不包含其他客户主机名／客户内容，不回退或扩大全局范围，也不执行修改。 |
| 匿名／admin／member | 沿用 `RouteAuthorization` 的登录或授权拒绝响应，不新增拒绝界面。所有者访问错误外层 CID 时，先于目标／主机名查询返回 404。 |

移除表单保留**服务端渲染时**的主机名尝试值和可选 `edit_hostname`，用于失败恢复，包括空尝试值。这不是实时捕获浏览器尚未提交的修改。绑定模式不提交客户分配／目标／表格隐藏上下文，目标由操作路径携带。未绑定全局移除仍提交当前渲染的主机名／客户／表格值。

## 6. 精确组件／控制器接口

### 前端：新增页面外壳

```ruby
CustomerHostnames::CustomerPageComponent.new(
  target_customer: @hostname_target_customer,
  hostnames: @hostnames,
  customer_id: 81721200,
  errors: @errors || [],
  form_values: @form_values || {},
  editing_hostname: @editing_hostname
)
```

初始化契约：`target_customer:` 和 `hostnames:` 必填；`customer_id: 81721200`、`errors: []`、`form_values: {}`、`editing_hostname: nil` 可选。`target_customer` 必须是解析出的 Customer，不能使用尝试值／请求提供的哈希。外壳不执行数据库查询。它构造面包屑／标题／描述／返回操作，并将 `target_customer`、`available_customers: []`、`table_context: {}` 传给 `ManagementComponent`。保留当前标题标识默认值，只挂载一个管理分区。页面外壳不提供 `table_context` 或 `available_customers` 参数。

新增视图：`app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`。仅通过简单组件挂载传入上述已准备 assigns；布局／界面／字段均封装于组件。控制器在 GET 和 422 时显式渲染 dashboard 布局。原生链接／表单使用已有 `data-turbo="false"`；本页没有表格 frame／reload 要求。

### 前端：现有管理／入口契约

保留 `ManagementComponent` 初始化接口及 `target_customer: nil` API。在**所有**渲染位置根据该参数决定路由，包括查询绑定的合并来源页：

| 方法／标记 | 存在 `target_customer` | 无目标 |
|---|---|---|
| `index_path` | 嵌套集合 helper + `#hostname-form` | 现有 G + 标量表格上下文 + 锚点 |
| `form_path` | 嵌套集合 POST 或嵌套 `record_path` PATCH | 现有全局增改删 helper |
| `record_path(row)` | 单数 `customer` 嵌套记录 helper，参数为外层 CID、目标编号、row | 现有复数 `customers` 记录 helper |
| `edit_path(row)` | 嵌套集合 helper + `edit_hostname: row.id` + 锚点 | 现有合并 GET + 表格上下文／编辑／锚点 |
| 新增／保存隐藏路由字段 | 不含 `target_customer_id`、`hostname_customer_id`、嵌套客户编号或表格字段 | 现有标量表格字段 |
| `removal_params` | 仅渲染的 `customer_hostname[hostname]` 和可选 `edit_hostname` | 现有渲染表单状态及标量表格上下文 |

决定：**所有绑定嵌套表单／移除表单均省略重复的目标路由字段**，包括在旧查询绑定来源页上渲染时。按需移除绑定隐藏目标循环及其 helper 用法。组件可为已有调用方保留清洗后的 `table_context` reader，但绑定导航／提交不得输出它。不引入来源模式参数，不把目标上下文复制进操作查询字符串。

`ManagementLinkComponent` 保留 `initialize(current_user:, target_customer_id: nil)` 和仅所有者可见的 `render?`。有目标 → `admin_maintenance_platform_customer_hostnames_path(81721200, target_customer_id, anchor: "hostname-form")`；无目标 → 现有 `G#hostname-form`。入口组件不查询目标。客户详情和页面快捷路径挂载 API 已符合要求，模板无需重复实现路由。

### 安全：控制器／concern 契约

- 扩展 `CustomersIndexContext#prepare_hostname_target_customer`，实现上述路径优先解析；保留查询回退和现有 `hostname_scope`／`prepare_hostname_management`。使用小型共享私有判断方法，例如 `nested_hostname_request?`，直接读取路径键。
- 新增 `CustomerHostnamesController#index`，**仅处理独立嵌套 GET**。要求路径目标，加载可选且限定范围的 `edit_hostname`，初始化全新 GET 错误／表单值，再调用 `prepare_hostname_management`。显式 `render :index, layout: "dashboard"`。本页不调用 `prepare_customers_index`、`customers_table_context` 或 `ModuleEntriesResolver`，不准备 `@rows/@columns/@pagination`。
- 独立页已准备 assigns：`@hostname_target_customer`、`@hostnames`、`@available_customers = []`、`@customer_id = 81721200`、`@editing_hostname`、`@errors`、`@form_values`。保留 `prepare_hostname_management` 已有的批量／无默认作用域客户关联加载。
- 泛化现有返回／渲染 helper（例如 `hostname_return_path`、`render_hostname_failure`），Save 和 Destroy 均根据 `nested_hostname_request?` 分支。嵌套返回使用嵌套集合 helper，只包含外层 81721200、解析出的目标编号和锚点。全局返回保留现有合并 `customers_table_context`。固定 helper 忽略任意返回／重定向字段。
- 失败准备调用 `prepare_hostname_management`，不重置 `@errors`、原始 `@form_values` 或已保存 `@editing_hostname`。嵌套失败渲染 `admin/maintenance/platform/customer_hostnames/index`，`layout: "dashboard"`，状态 422；全局失败额外准备客户表格，再以相同显式布局／状态渲染现有合并 index。
- 保留 Save 失败时限定范围的已保存编号重载，以及 Remove 失败时限定范围的点击行／可选编辑重载。仅 GET 使用的初始化不得在增改删失败渲染时执行。保留权威客户载荷及现有 Activity 参数。
- `CustomersController` 的合并首页及视图保留当前查询绑定准备／表格行为。第 10 节新增资料页分区准备及本地 HTML 路径门禁；无需新增主机名控制器或修改共享授权。

## 7. 组件复用与 I18n 映射

| 区域 | 组件／职责 |
|---|---|
| 独立页组合 | **新增** `CustomerHostnames::CustomerPageComponent` |
| 面包屑／标题／描述／返回 | 现有 `AdminPageComponent`，内部使用 `BreadcrumbsComponent` 和 `ButtonComponent` |
| 表单／列表及绑定／停用／错误状态 | 现有 `CustomerHostnames::ManagementComponent` |
| 表单／列表容器 | 现有 `CardComponent(padding: :none)` |
| 持续校验摘要 | 现有 `AlertComponent(type: :error, auto_dismiss: false)` |
| 空列表／可用状态／操作 | 现有 `EmptyStateComponent`、`BadgeComponent`、`ButtonComponent` 及原生 `button_to` |
| 客户详情／页面快捷路径入口 | 现有 `CustomerHostnames::ManagementLinkComponent` |

复用以下现有成对 EN／zh-CN 翻译，无需新增文案键：

| 用途／键 | English | 简体中文 |
|---|---|---|
| 维护面包屑：`maint_platform.customers.breadcrumb.maintenance` | Maintenance | 维护 |
| 客户面包屑：`maint_platform.customers.breadcrumb.customers` | Customers | 客户 |
| 末级面包屑／分区：`customer_hostnames.title` | Customer hostnames | 客户主机名 |
| h1／入口：`customer_hostnames.manage` | Manage customer hostnames | 管理客户主机名 |
| 页头描述：`customer_hostnames.target_saved_hint` | Showing hostnames for %{customer}. | 仅显示 %{customer} 的主机名。 |
| 身份：`customer_hostnames.customer_option` | %{title} (%{id}) | %{title}（%{id}） |
| 页头操作：`common.actions.back` | Back | 返回 |

复用全部当前表单／操作／空状态／停用／DNS／Flash 键。在渲染／请求时翻译，不在常量中翻译。客户名称、编号和主机名属于转义后的记录数据。实施时若发现额外文案，必须添加双语 locale 键并保持插值变量一致；英文须与预期显示内容逐字节一致。

## 8. 独占文件归属与并行实施步骤

以下为后续实施的交接分工，不代表本设计任务派发子代理。

| 负责人 | 独占文件／交付 |
|---|---|
| 前端开发者 | 新增 `app/components/customer_hostnames/customer_page_component.{rb,html.erb}` 和 `app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`；修改 `app/components/customer_hostnames/management_component.{rb,html.erb}` 和 `management_link_component.rb`。负责外壳／响应式／原生 URL／上下文省略。负责新增 `spec/components/customer_hostnames/customer_page_component_spec.rb` 及现有 management/link 组件规格。若需 locale 修改，仅由前端维护成对 `config/locales/customer_hostnames.{en,zh-CN}.yml`；复用文案时预计无需修改。 |
| 安全工程师 | 修改 `config/routes.rb`、`app/controllers/admin/maintenance/platform/customer_hostnames_controller.rb`、`app/controllers/concerns/customer_hostnames/customers_index_context.rb`。负责路由／helper 识别、门禁顺序、权威路径目标、记录范围、独立 GET 准备及路径驱动的 303／422。负责 `spec/requests/admin/maintenance/platform/{customer_hostnames,customers,customers_hostnames_merge}_spec.rb`，以及受影响时 `spec/requests/admin/maintenance/page_shortcuts_spec.rb`、`spec/components/page_shortcuts/management_component_spec.rb`、`spec/components/admin_table_component_base_path_spec.rb` 的入口断言。若单独路由文件更合适，也负责新增路由规格。 |
| 后端开发者 | **无需修改。**沿用现有 Save/Destroy/CNAME 接口和归属检查。 |
| 集成／参考文档负责人 | 更新受影响 `doc/reference` 页的两种语言，合并两条实施分支，审阅规格／文档并执行响应式／双语／原生流程冒烟检查。并行工作完成协调后，由其负责仅集成所需的修正。 |

1. **冻结共享接口：**路由／helper 名称和位置参数；外层 `customer_id` 与内层 `hostname_customer_id`；路径键判断方法；独立页 assigns 和初始化接口；参数驱动的绑定控件 URL 与路径驱动的响应选择。确认当前后端／上下文 DNS 切片为实施基线。
2. **并行前端任务：**构建外壳／挂载，切换 ManagementComponent 绑定 helper／隐藏字段／移除上下文，更新入口目的地，新增／更新组件规格。复用现有字段／停用／错误渲染和 locale。前端使用已约定的新 helper 名称，路由就绪后完成渲染验证。
3. **并行安全任务：**新增显式 scoped 路由、路径优先目标解析、仅嵌套 GET 准备及嵌套／全局返回／失败分支。保留全局／查询绑定语义及现有 Activity 调用；新增／更新请求／路由／入口回归。安全任务不修改前端归属的模板／组件／locale。
4. **集成：**用真实路由验证渲染的表单／链接目的地及原生提交；检查嵌套与直接全局请求的响应选择，以及查询绑定来源页到独立页的转换。更新曾预期查询绑定链接、隐藏目标／表格字段，或从客户入口进入后仍显示合并 h1／表格的规格。
5. **文档与验证：**同步下列参考页，执行定向检查、重建 Tailwind，并在 EN／zh-CN、375／768／1440px 下冒烟检查，主机名流程另需禁用 JavaScript 验证。实施交接完成前审查归属／隔离和项目约定。

## 9. 验收、检查与参考文档更新

- 独立 GET 可在所选客户下收藏；只渲染一个 admin 外壳／h1、目标名称／编号、面包屑／返回、限定表单／列表，不显示客户表格／搜索／分页。GET／编辑／422 均使用完整 dashboard 布局，包含携带无关 `Turbo-Frame` 头的请求。
- 路由识别保留外层 `customer_id: "81721200"`、内层 `hostname_customer_id: C` 和修改记录 `id: R`；四种方法均分派到同一现有主机名控制器。全局路由识别／helper 保持有效。
- 每个嵌套方法均覆盖匿名、平台／租户 admin 和 member 的继承保护。所有者访问错误外层 CID 时，先于目标／主机名／表格查询失败。严格无效／前导零／不存在路径目标返回 404；有效停用目标仍可访问。
- 每个嵌套方法中，冲突／畸形查询或请求体目标字段均不能改变路径目标或响应模式。新增／更新缺失／空值／其他客户嵌套客户编号时使用 C。所有者额外字段按现有白名单忽略。嵌套修改记录编号仅由路径选定；其他客户的编辑／更新／移除／恢复编号返回 404，不修改或展示其绑定。
- 原生生成的添加／编辑／取消／保存／移除 URL 使用嵌套 helper，包括来自旧查询绑定合并渲染时。绑定表单不包含重复目标／客户／表格路由字段；移除仍携带原始渲染尝试值／可选编辑身份。未绑定全局表单／列表／表格上下文维持原行为。
- 嵌套增改删成功以 303 返回 `N(C)#hostname-form`，使用翻译后的 Flash 并清除编辑状态；失败以 422 渲染独立视图，保留原始／空尝试值、已保存 PATCH 身份、错误及绑定目标。注入的 `q/sort/dir/page`、返回 URL 和仅存在于请求体的 `hostname_customer_id` 不被转发。直接调用原全局增改删（含查询绑定请求）仍返回合并 303／422 和当前表格上下文。
- 覆盖重复／校验和 stub 的 CNAME 失败、同客户失败恢复、已改绑／删除编辑身份返回 404，以及停用新增／编辑／移除行为。使用 `CustomerHostnames::CnameVerifier.call` 边界上的确定性 stub，不依赖公开 DNS，也不重写业务层测试。
- 验证转义后的长客户名称／主机名、字段／分组／错误无障碍关联、面包屑局部滚动、移动端操作／行堆叠、双语渲染及翻译／插值完整性。组件在切换 locale 前构造，仍须在渲染时正确翻译。

建议实施定向检查（两条任务集成后运行）：

```bash
bundle exec rspec spec/components/customer_hostnames/customer_page_component_spec.rb spec/components/customer_hostnames/management_component_spec.rb spec/components/customer_hostnames/management_link_component_spec.rb spec/requests/admin/maintenance/platform/customer_hostnames_spec.rb spec/requests/admin/maintenance/platform/customers_spec.rb spec/requests/admin/maintenance/platform/customers_hostnames_merge_spec.rb spec/components/page_shortcuts/management_component_spec.rb spec/requests/admin/maintenance/page_shortcuts_spec.rb spec/components/admin_table_component_base_path_spec.rb
bin/rails tailwindcss:build
```

如新增路由规格，也纳入上述定向运行。本次仅产出调研／设计文档，未运行运行时测试或构建；上述内容是实施验收检查。

实施变更中，更新 **两种语言**的 `doc/reference/{en,zh-CN}/{customer-hostnames,customers,page-shortcuts,tenancy-and-roles,system-map,access-grants}.md`。说明嵌套路由／helper／API、独立路径编号、独立外壳／导航、权威路径范围、无隐藏路由上下文的绑定控件、路径决定的返回／422 页面，以及保留的全局／查询绑定合并行为。修正「没有独立主机名 GET」和「入口始终指向合并首页」等表述。保留已有主机名参考／目录条目；本次扩展已记录的同一功能。搜索其他参考页中冲突的入口／路由／上下文说明，并同步所有受影响的双语结果。保留前一切片准确的 DNS／并发说明。

## 10. 最终补充——客户详情和编辑页

### 必需界面与布局

- **详情：**在全部客户资料卡片之后，渲染一个独立主机名分区，包含 `ManagementLinkComponent` 和现有 `ManagementComponent`。将现有资料页顶部的管理链接移入此分区，不重复展示。保留资料页 h1，复用管理 h2／卡片 h3 层级、当前 Card／Field 模式及已有双语 I18n 文案。
- **编辑及资料更新 HTML 422：**在完整 `CustomerFormComponent` 之后渲染同一分区。**客户资料表单与主机名表单必须是同级，绝不能嵌套。**资料错误／尝试字段保留于资料表单，主机名分区提供全新新增表单和限定范围的已保存行。保存客户资料不提交或保存主机名字段。
- **控件：**两个页面均展示只读当前客户身份、主机名新增表单、已保存行及编辑／移除控件。新增 POST 和移除 DELETE 使用现有嵌套主机名路由；行编辑打开 `N(@customer.id)?edit_hostname=R#hostname-form`；管理打开 `N(@customer.id)#hostname-form`。所有主机名操作成功／422 仍到独立页面，不返回资料页。本分区忽略资料页的 `edit_hostname`／目标／表格查询参数。原生导航／提交不保存尚未提交的资料修改。
- **响应式：**将详情页仅适合桌面的页头改为 `flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between`，配合 `min-w-0`、可换行名称／徽章及堆叠／换行操作（`min-h-11`）。编辑页以 `:full`（现有 admin 默认值）替换整页 `:narrow` 覆盖；仅将资料表单自身容器限定为 `w-full max-w-3xl`，下方主机名分区使用全部可用宽度。保留 `space-y-6`、移动端主机名行／操作堆叠、`md:table`、长值换行和面包屑局部滚动。不新增页面外壳／h1、JS 或渲染时 DNS 行为。

### 冻结的数据准备与挂载接口

安全任务负责私有 `CustomersController#prepare_customer_hostname_section`：使用已加载的 `@customer`，设置 `@hostname_target_customer = @customer`，仅通过 `hostname_scope.order(:hostname, :id)` 准备 `@hostnames`，并填充各行用于展示的客户关联。不调用查询目标解析器、不准备客户表格、不执行 DNS／服务操作。保留 `@customer` 及其校验错误；即使更新失败，也由资料记录已持久化的编号确定范围。

仅在 HTML 详情／编辑 GET，以及资料更新 HTML 422 渲染编辑页之前调用准备方法。资料更新成功保留现有重定向；JSON 详情／更新响应及资料查询／JSON 接口保持原行为，**JSON 不读取主机名**。保留现有客户可编辑资格：详情使用 `Customer.unscoped`，编辑／更新继续使用当前 `Customer` 查找，不新增停用客户资料编辑权限。停用客户详情仍展示现有禁用新增／仅保留原客户的主机名行为。

将本地精确平台路径门禁扩展至 **HTML** `show/edit/update`，在继承授权之后、分区查询之前执行（建议早于 `set_customer` 和任何资料更新）。保留当前 index 门禁。读取 `request.path_parameters[:customer_id] == "81721200"`，查询／请求体值不可替代。此补充门禁不扩展至 JSON，也不修改共享 `RouteAuthorization`。

前端复用以下挂载，无需新增必需组件 API：

```ruby
CustomerHostnames::ManagementLinkComponent.new(
  current_user: current_user, target_customer_id: @hostname_target_customer.id
)
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames, available_customers: [], customer_id: 81721200,
  target_customer: @hostname_target_customer,
  errors: [], form_values: {}, editing_hostname: nil, table_context: {}
)
```

可选纯组合外壳：`CustomerHostnames::CustomerSectionComponent.new(current_user:, target_customer:, hostnames:, customer_id: 81721200)`，用自身参数替换 assigns，恰好渲染上述两个组件。不执行查询、不提供页面外壳、不解析请求目标、不引入另一种返回模式；上述直接复用是最小实现。每页仅有一个分区／表单锚点，不含隐藏目标／客户／表格路由字段，不把资料错误／参数复制到主机名状态。

### 并行归属增量与验收

- **前端新增归属** `app/views/admin/maintenance/platform/customers/{show,edit}.html.erb`：分区位置、同级表单、详情页头换行及编辑页宽度调整。若使用轻量外壳，前端还负责 `app/components/customer_hostnames/customer_section_component.{rb,html.erb}` 及其组件规格。现有资料表单／业务行为仍封装于 `CustomerFormComponent`。
- **安全新增归属** `app/controllers/admin/maintenance/platform/customers_controller.rb`：HTML 门禁／准备及资料更新失败集成；请求覆盖仍归其现有 `customers_spec.rb` 职责。业务后端仍无需修改。参考文档负责人还须在受影响参考页的两种语言中说明两个嵌入式资料分区及独立表单。
- **实施顺序：**冻结上述 assigns／挂载 → 前端挂载分区，同时安全任务准备／保护 HTML 资料界面 → 与现有嵌套操作集成 → 验证定向组件／客户／主机名请求规格，以及 375／768／1440px EN／zh-CN 冒烟检查。仅在引入可选外壳时增加其规格。
- **验收：**详情、编辑 GET 和资料 HTML 422 均显示一个限定范围的分区，提供可用的新增／编辑／移除／管理控件；即使查询目标冲突、畸形或非标量，当前身份仍正确，不显示其他客户行。资料 HTML 422 独立保留资料尝试值／错误和分区；有效资料 JSON 详情／更新不查询主机名，渲染／资料保存不执行 CNAME 校验。错误前缀 HTML 详情／编辑／更新先于主机名读取／资料修改失败，包括伪造查询／请求体 CID；继承角色门禁仍有效。检查同级表单标记及独立提交载荷、停用详情与不变的停用编辑资格、空状态、主机名独立 303／422 目的地、长名称页头换行及双语／移动端渲染。本补充未运行运行时测试。
