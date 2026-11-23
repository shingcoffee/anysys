# 客户与主机名合并——UX 设计与实施计划

日期：**2026-10-09**。状态：**READY_FOR_FRONTEND**。本文为设计／计划交付物；功能实施与运行验证由后续阶段完成。

## 1. 已确认需求与设计依据

产品负责人已确认最小合并方案：保留现有客户表格并置于页面顶部，下方嵌入完整的全局主机名添加／编辑表单与已保存绑定列表，整页仅使用**一个 `AdminPageComponent` 外壳**。平台侧栏仅保留「客户」作为合并界面的入口。

本文遵循 `AGENTS.md` 与 `.cursor/agents/anysys-ux-designer.md`，按要求将双语交付物保存至 `doc/plans/`，替代角色默认输出位置。以已检查的当前工作区组件、视图及控制器为实施基线，包括尚未提交的主机名功能。本文取代 `2026-10-09-customer-hostnames.*.md` 中独立主机名页面／导航的方案；既有绑定、校验、并发与公开路由行为仍为功能约定。

当前工具集没有官方 shadcn skill／MCP。编排者已在设计前查阅官方 [Card](https://ui.shadcn.com/docs/components/card) 与 [Table](https://ui.shadcn.com/docs/components/table) 文档。通过现有 Rails ViewComponent 与 Tailwind 工具类实现其标题／描述／内容／操作区及语义化 caption／header／body 组合，无需 React、自定义 CSS 或新增 JavaScript。

## 2. 界面清单

| 界面 | 导航区域 | 调整 |
|---|---|---|
| `/81721200/admin/maintenance/platform/customers` | admin → 维护 → 平台 → 客户 | 单页依次展示现有客户表格、主机名区域标题、表单卡片、已保存绑定卡片。 |
| 同一首页，带 `?edit_hostname=<id>#hostname-form` | admin → 维护 → 平台 → 客户 | 为选中的全局绑定预填嵌入式编辑表单。 |
| `/81721200/admin/maintenance/platform/customers/hostnames[/:id]` | admin → 维护 → 平台 → 客户 | 原生添加／更新／移除端点；校验失败渲染完整合并首页。 |
| 平台侧栏 | admin → 维护 → 平台 | 保留「客户」，移除独立「客户主机名」叶节点。 |
| `/:cid/admin/maintenance/page_shortcuts` | admin → 维护 → 页面快捷路径 | 现有所有者入口改为固定平台客户首页与表单锚点，可携带 URL 客户建议。 |
| `/81721200/admin/maintenance/platform/customers/:id` | admin → 维护 → 平台 → 客户 | 现有所有者入口继续建议当前展示的启用客户。 |

主机名管理仍仅允许平台所有者，并锁定 URL 客户 `81721200`。绑定列表始终为全局列表。搜索、排序与分页仅作用于客户表格，不影响主机名行或可选客户。

## 3. 布局规范

```text
现有客户面包屑
客户                                        [回收站] [新建客户]
现有客户页面说明

+ 现有客户 AdminTable -----------------------------------+
| 现有搜索、列、行操作与分页                              |
+--------------------------------------------------------+

客户主机名                                  h2，区域名称
将主机名绑定到客户，用于公开快捷路径路由。

+ 添加主机名／编辑主机名 --------------------------------+
| 部署提示                                               |
| 错误汇总，仅在操作失败后展示                            |
| 主机名输入框                   原生客户选择框          |
| 字段提示／错误                 字段提示／错误          |
| 无启用客户提示，按需展示                                |
| [添加主机名／保存]             [取消，仅编辑模式]       |
+--------------------------------------------------------+

+ 已保存的主机名 ----------------------------------------+
| 移除主机名不会删除客户及其页面。                        |
| 主机名 | 客户名称＋编号 | 可用状态 | 操作               |
| a.example | Acme（12345678） | 可用 | 编辑 移除          |
| old.example | Old（23456789） | 不可用 | 编辑 移除       |
| 可用状态反映客户是否启用，不代表 DNS／TLS 已就绪。       |
+--------------------------------------------------------+
```

### 3.1 父页面

- `app/views/admin/maintenance/platform/customers/index.html.erb` 负责唯一的 `AdminPageComponent`：保留现有面包屑、客户 h1／说明、回收站与新建客户操作。
- 将现有 `AdminTableComponent` 与主机名组件置于 `min-w-0 space-y-6` 内容容器。客户表格始终在前，保留现有列、行链接、代入客户／编辑／删除行为、搜索与分页。
- 使用表格已有的 `base_path:` 参数，显式传入固定客户首页路径。当前默认值为空的相对路径；若从主机名 CUD URL 渲染 422 页面，相对搜索／排序／分页导航会误回到写入路径。
- flash 继续由 dashboard 布局统一渲染一次。嵌入组件仅负责主机名校验错误。

### 3.2 嵌入式主机名组件：精确的最小调整

- 沿用 `CustomerHostnames::ManagementComponent`，移除其中的 `AdminPageComponent` 外壳及独立面包屑／页面标题栏。
- 根节点使用 `<section class="min-w-0 space-y-6" aria-labelledby="...">`。构造参数增加 `title_id: "customer-hostnames-title"`，对应可见 h2 的 ID，标题取自 `customer_hostnames.title`。
- 区域 h2 下展示现有 `customer_hostnames.description`。表单与已保存列表卡片标题改为 h3，保留 `section-header` 外观及既有翻译。卡片标题 ID 可由 `title_id` 派生。
- 保留两个 `CardComponent.new(padding: :none)` 卡片。表单卡片内容区保留 `id="hostname-form"`，整页此锚点仅出现一次。保留 `p-4 sm:p-6`、表单 `space-y-5` 与字段 `min-w-0` 容器。
- 保留现有原生主机名／客户表单、字段提示／错误、启用／仅可保留的客户选项、转义值、徽标、公开主机名链接、编辑操作、原生移除表单及已保存列表空状态。
- 仅增加 `table_context: {}`，承载下文规定的四个客户表格返回参数。路径辅助方法与隐藏字段均使用此已筛选参数。
- 无启用客户时，保留说明文本及禁用的新绑定控件。移除组件内返回「客户」的冗余自链接；父页面既有客户工作流仍负责客户管理。

### 3.3 响应式组合与模型字段

| 区域 | 数据 | 渲染 |
|---|---|---|
| 客户表格 | 现有 `@rows`、`@columns`、`@pagination` | 现有 AdminTable 移动端卡片与桌面表格。 |
| 主机名字段 | 提交的 `form_values[:hostname]`，否则为已保存编辑行 `hostname`，再否则为空 | 原生必填文本框；等宽字体，关闭自动大写与拼写检查。 |
| 客户字段 | 提交的 `form_values[:customer_id]`，否则为已保存编辑行 `customer_id`，再否则为有效建议／空值 | 原生必选选择框，使用本地化的名称＋编号标签。 |
| 已保存主机名 | 持久化的 `CustomerHostname#hostname` | 客户启用：新标签页打开 `https://<hostname>/`，带 `noopener noreferrer`；停用／缺失：纯文本。 |
| 已保存客户 | 持久化 `customer_id` 与批量加载的客户名称 | 名称＋编号，保留停用客户身份与已翻译的客户缺失兜底。 |
| 可用状态 | 关联客户 `active?` | 现有成功／中性徽标及已翻译的可用／不可用标签。 |
| 已保存行操作 | 持久化绑定 ID | 次要编辑链接与危险样式移除按钮。 |

- 小于 `md` 时两个字段纵向排列；从 `md` 起使用 `grid-cols-2`。小于 `sm` 时表单按钮纵向满宽，从 `sm` 起横向按内容宽度排列。
- 保留主机名表格已有的 `block w-full md:table md:table-fixed` 组合、真实 `<caption>`／`<thead>`／`<tbody>`、带 scope 的列标题及移动端字段标签。小于 `md` 时行纵向展开，四个数据／操作单元在移动端均可见。
- 长主机名使用 `break-all`，名称／错误使用 `break-words`，弹性容器使用 `min-w-0`，行操作使用 `flex-wrap gap-2`，触控目标使用 `min-h-11`。沿用项目颜色语义及 input／button／card 类。
- 主机名列表继续使用 Card 内既有语义化响应式表格。改用 AdminTable 会引入本次全局列表并未约定的搜索／分页语义。

## 4. 原生交互与状态

下文以 `C` 表示固定客户首页，以 `T` 表示当前已筛选的 `q/sort/dir/page` 查询。Rails 辅助方法负责查询值编码；片段锚点由浏览器处理。

| 流程 | 操作与结果 |
|---|---|
| 添加 | GET `C?T` → 输入主机名／选择启用客户 → 原生 POST `C/hostnames` → 保存成功 → **303** `C?T#hostname-form`，展示已翻译成功提示、空白添加表单及刷新后的全局列表。 |
| 编辑 | 已保存行「编辑」→ GET `C?T&edit_hostname=<id>#hostname-form` → 原表单预填已保存字段 → 原生 PATCH `C/hostnames/<id>` → **303** `C?T#hostname-form`，展示成功提示并回到添加模式。 |
| 取消 | 编辑表单「取消」→ GET `C?T#hostname-form`，退出编辑并展示空白添加表单。 |
| 移除 | 原生 `button_to` DELETE `C/hostnames/<id>` → **303** `C?T#hostname-form`，展示移除提示及刷新后的列表；保留客户与页面。 |
| 保存失败 | **422**，渲染完整客户首页：原表格查询／排序／页码、主机名区域、错误汇总、提交字段（含空值／被拒绝编号）及原已保存编辑身份。 |
| 移除失败 | **422**，渲染完整合并页面及已翻译基础错误，保留表格上下文和已提交的渲染表单／编辑状态。 |
| 发现入口 | 所有者链接 → `C?target_customer_id=<id>#hostname-form`，无建议时为 `C#hostname-form`；启用客户建议仅预选添加表单。 |

其他状态：

- **编辑优先：** `edit_hostname` 优先于 `target_customer_id`。建议不筛选表格／列表，也不改变平台授权上下文。
- **保留停用客户的编辑：** 仅当前编辑绑定已保存的停用客户可保留，展示其名称＋编号及不可用选项；可修改主机名或改绑启用客户。该选项不能成为其他绑定的新归属。
- **被拒绝输入：** 保留原始主机名／客户提交值；非空被拒绝编号以选中且禁用的已翻译选项展示。空选择保持为空。保留资格以已保存编辑行为依据，不以 Activity 修改后的模型为依据。
- **主机名列表为空：** 已保存卡片展示现有 EmptyState，添加表单保持可见。客户表格为空／搜索无结果不会隐藏主机名区域。
- **没有启用客户：** 禁用新绑定；保留原停用客户的编辑仍可提交。停用绑定仍可编辑／移除。
- **编辑／更新／移除 ID 缺失或已失效：** 返回标准 404，不悄然切换为添加。匿名／admin／member 使用既有认证与角色处理；所有者使用其他 URL CID 时，在访问全局主机名前返回 404。
- **加载：** 普通浏览器／整页导航，不新增骨架屏或异步区域。此处不查询域名／DNS／TLS／供应商健康状态；运行错误使用既有 Rails 处理。
- **无障碍：** 一个客户 h1、一个主机名区域 h2、卡片 h3、区域 `aria-labelledby`、显式字段标签、提示／错误 `aria-describedby`、字段 `aria-invalid`、持久 `role="alert"` 错误汇总、表格 caption／scope 列标题及包含主机名的已翻译操作标签。保留原生 Tab 顺序和可见焦点。

## 5. 组件与控制器 API 建议

### 5.1 嵌入组件参数

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames,
  available_customers: @available_customers,
  customer_id: 81721200,
  errors: @errors || [],
  form_values: @form_values || {},
  editing_hostname: @editing_hostname,
  table_context: @table_context || {},
  title_id: "customer-hostnames-title"
)
```

`hostnames`、`available_customers`、错误及原始字段优先级沿用已检查接口。`title_id` 是 HTML 标识，不是翻译文案。`table_context` 仅接收标量 `q`、`sort`、`dir`、`page`，组件边界再次筛选。不得将任意 `params`、`return_to`、`redirect`、嵌套结构或授权／客户 ID 作为返回上下文。有效排序／方向／页码继续由现有 resolver 校验。

- 添加／编辑表单：为已提供的上下文项输出顶层隐藏字段 `q`、`sort`、`dir`、`page`，放在嵌套业务数据之外。`customer_hostname` 业务参数仍仅包含 `hostname` 与 `customer_id`。
- 移除表单：包含相同上下文隐藏字段。若当前为编辑模式，携带 `edit_hostname` 及服务端当前渲染的主机名／客户值，以便移除失败后恢复表单状态；添加模式有渲染值时同样携带。它们仅供失败展示，不作为额外 Destroy 输入。原生表单仅提交自身字段；Save 的原始提交值直接取自该 Save 请求。
- 编辑 URL：已筛选表格上下文＋点击行的 `edit_hostname`＋`#hostname-form`。
- 取消与成功 CUD 返回 URL：已筛选表格上下文＋`#hostname-form`，不携带 `edit_hostname` 与 `target_customer_id`。成功或取消后不保留建议。
- 原生表单及编辑／取消／发现链接保留 `data-turbo="false"`，无需功能专属 Stimulus 控制器。

### 5.2 共用控制器准备逻辑

**安全工程师负责两个控制器及共用控制器 concern**，包括迁移既有准备逻辑；前端负责组件／视图／locale 集成。建议 concern 路径为 `app/controllers/concerns/customer_hostnames/customers_index_context.rb`，最终命名可遵循局部约定。

提供简洁准备接口，例如 `prepare_customers_index`，职责为：

1. 按 `q/sort/dir/page` 标量白名单生成 `@table_context`。
2. 沿用现有首页作用域与 resolver，准备客户 `@columns`、`@customers`、`@rows`、`@pagination`。
3. 按主机名／编号准备全部绑定，批量加载含停用客户的身份，并按名称／编号准备启用 `@available_customers`。
4. 初次 HTML GET 在精确平台路径校验后解析 `params[:edit_hostname]`；非编辑时仅应用有效的启用 `target_customer_id` 建议。
5. CUD 失败渲染接收已设置的错误／原始表单值／已保存编辑身份，不重置、不重新套用 GET 建议。更新身份由写入路由 `:id` 确定，请求体／查询 ID 不能更换实际更新或删除的记录。

沿用现有 `CustomerHostnamesController` 执行 CUD，挂载于**客户集合路径作用域**，而非 `/customers/:customer_id` 下。建议辅助方法为 `admin_maintenance_platform_customers_hostnames_path(81721200)` 与 `admin_maintenance_platform_customers_hostname_path(81721200, hostname)`。生成路径必须为 `/customers/hostnames[/:id]`，通过作用域命名区分主机名集合与既有客户资源。

HTML 失败以 422 渲染 `admin/maintenance/platform/customers/index`，提前准备完整页面变量。保留现有 Customers JSON 响应，以及客户添加／详情／编辑／删除／回收站／恢复／代入客户工作流。合并首页必须在准备主机名前检查精确平台 CID；CUD 保留既有继承所有者门禁与显式路径校验。

### 5.3 保持表格上下文最新，无需修改共用表格

已检查的 AdminTable 自带 `turbo-frame#admin-table`，在推进浏览器历史记录时仅替换表格。搜索／排序／分页后，旁边主机名组件的隐藏返回上下文会因此过期。

建议在本合并 HTML 首页模板使用标准 Rails **`turbo_page_requires_reload`** 辅助方法，使表格导航刷新完整页面与两个区域的状态，无需修改 `AdminTableComponent` 或其现有 JavaScript。同时显式传入上述 `base_path:`。取舍是客户列表导航改为整页刷新，而非仅更新表格。

**重要集成细节：** `ApplicationController#dashboard_layout` 当前对 `Turbo-Frame` 请求返回 `false`。安全工程师负责的 Customers HTML 首页渲染须显式使用 dashboard 布局，包括 frame 发起的请求，使 `yield :head` 输出辅助方法生成的 `turbo-visit-control=reload` 指令。完整 422 渲染同样使用此布局。仅在无布局响应内调用辅助方法无法解决问题。此显式渲染选择限定于合并页面。

官方行为参考：[Turbo Frames：跳出 frame](https://turbo.hotwired.dev/handbook/frames#%E2%80%9Cbreaking-out%E2%80%9D-from-a-frame)。QA 须在真实浏览器中执行搜索／排序／分页后再操作主机名，验证返回的是最新上下文。

## 6. 组件复用与本地化

| 区域 | 现有组件／组合 |
|---|---|
| 页面外壳 | Customers 首页中的唯一 `AdminPageComponent`。 |
| 客户列表 | `AdminTableComponent`，保留现有控件与响应式组合，使用已有 `base_path:` 参数。 |
| 主机名区域 | 调整现有 `CustomerHostnames::ManagementComponent`，提供自己的 h2／说明及两个 Card。 |
| 表单与已保存列表卡片 | `CardComponent(padding: :none)`，在内容块中组合标题／说明、内容及操作区。 |
| 错误汇总 | `role="alert"` 内的 `AlertComponent(type: :error, auto_dismiss: false)`。 |
| 提交／编辑／取消／发现 | `ButtonComponent`，沿用主要／次要样式。 |
| 移除 | 现有原生 `button_to`，项目危险样式、CSRF 与 DELETE 隐藏方法字段。 |
| 可用状态／空列表 | `BadgeComponent`／`EmptyStateComponent`。 |
| 所有者发现入口 | `CustomerHostnames::ManagementLinkComponent`，始终固定至客户首页＋锚点，无建议时也带锚点。 |

新增组件：**无**。共用基础组件 API 变更：**无**。

复用成对 `config/locales/customer_hostnames.en.yml`／`.zh-CN.yml` 中全部主机名标签、说明、提示、选项、无障碍标签及 flash 键。例如：`title` → “Customer hostnames”／“客户主机名”；`add_heading` → “Add hostname”／“添加主机名”；`edit_heading` → “Edit hostname”／“编辑主机名”；`saved_heading` → “Saved hostnames”／“已保存的主机名”。通用操作与可用状态标签沿用现有键。翻译在渲染／请求时求值。

侧栏叶节点移除后，`chrome.sidebar.maintenance.customer_hostnames` 不再使用；确认引用后从两份 chrome locale 中同时移除。CUD 控制器资源仍为 `customer_hostnames`，因此保留 `customer_hostnames.title` 及其授权路由标签映射。实施新增文案均须保持 EN／zh-CN 键与插值一致。

## 7. 实施顺序与文件归属

| 负责人 | 文件／职责 |
|---|---|
| 安全工程师 | `config/routes.rb`；`app/controllers/admin/maintenance/platform/customers_controller.rb`；`customer_hostnames_controller.rb`；`app/controllers/concerns/customer_hostnames/` 下新共用 concern。负责路由重挂载／移除、门禁、共用准备、完整 HTML 渲染、上下文及 303／422 行为。 |
| 前端开发 | `app/views/admin/maintenance/platform/customers/index.html.erb`；`app/components/customer_hostnames/management_component.{rb,html.erb}`；`management_link_component.rb`；移除旧主机名独立首页模板；`app/services/maintenance_contributor.rb` 侧栏展示；按需调整成对 customer_hostnames／chrome locale。通过共享链接组件保留客户详情／快捷路径页面的挂载。 |
| 后端开发 | 核对现有 `CustomerHostname`、Save／Destroy Activity 与 Reform contract，确认启用／仅可保留及原始错误展示语义。本合并无需 schema／业务规则变更。与安全工程师明确已保存编辑身份语义；控制器／concern 由安全工程师编辑。 |
| QA 工程师 | 更新既有主机名组件／链接、Customers／主机名请求、路由与侧栏 spec；保留授权、CSRF、保留停用客户及客户工作流覆盖，增加有效的合并页面／上下文回归。 |
| 发布工程师 | 执行对应检查，为模板变更重建 Tailwind，并在移动／平板／桌面尺寸及 EN／zh-CN 下冒烟验证。重启时遵循项目资源／服务器指令。 |
| 编排者指定的参考文档负责人 | 在实施变更中更新受影响的成对 `doc/reference` 页面，同步 URL／组件／API 示例与发现入口说明。 |

建议实施顺序：

1. 安全工程师公布路由辅助方法名、concern 变量及表格上下文结构；前端可按此约定并行实施。
2. 前端嵌入主机名区域并调整发现入口／侧栏；安全工程师切换 GET 准备与 CUD 整页渲染，移除旧路由／index action。
3. QA 验证成功／失败／上下文／授权及保留的客户工作流；文档负责人同步两种语言。
4. 发布执行针对性套件与响应式／原生浏览器冒烟；技术负责人／代码审查者核对最小合并约定。

## 8. 验收与后续验证

- 整页恰有一个 AdminPage／客户 h1；现有客户表格位于完整、具名的主机名表单及全局已保存列表之前。
- 客户搜索／排序／分页及所有既有客户工作流可用。客户零搜索结果不移除全局绑定或启用客户选项。
- 编辑使用 `edit_hostname` 且优先于建议。发现入口始终固定 CID `81721200` 与 `#hostname-form`，可携带启用客户建议；客户详情保留建议行为。
- 原生 POST／PATCH／DELETE 使用 `/customers/hostnames[/:id]`。成功以 303 返回客户首页＋当前四字段表格上下文＋表单锚点，清除编辑／建议状态。
- 无效添加／更新及移除失败返回 422，包含完整合并页面、原表格上下文、翻译错误、全部已提交字段及适用的已保存编辑身份。重复／被拒绝／空值／保留停用客户语义保持一致。
- 移除独立主机名侧栏入口／首页视图／index action 及旧 `/platform/customer_hostnames` GET／CUD 路由，不提供兼容重定向；不新增主机名 new／show／edit 页面。
- 匿名／admin／member、伪造查询／请求体 ID 及所有者错误前缀不能读取／修改全局绑定；保留现有 CSRF／方法语义。
- 两种语言下控件、区域标签、caption／header／body、操作标签与错误关联正确；375px、768px、1440px 下长主机名／名称／错误换行且无整页溢出。
- 真实浏览器回归：改变客户 q／sort／dir／page，再执行编辑／取消／保存／移除；成功与 422 后 URL、表格结果、隐藏上下文一致。`Turbo-Frame: admin-table` 请求的首页响应也必须包含 reload 指令。
- 禁用 JavaScript 后，主机名添加／编辑／取消／移除／发现可通过原生导航／表单完成；客户搜索保留原生 GET 提交行为。

建议针对性套件：`spec/components/customer_hostnames/management_component_spec.rb`、`management_link_component_spec.rb`、`spec/requests/admin/maintenance/platform/customers_spec.rb`、`customer_hostnames_spec.rb`、`customer_restorations_spec.rb`、`spec/requests/platform/customer_contexts_spec.rb`、`spec/routing/customer_hostnames_routing_spec.rb`、`spec/services/maintenance_contributor_spec.rb` 及相关快捷路径发现／请求 spec。若修改授权标签映射，执行 `grant_route_label_spec.rb`。如编排者决定修改共用授权而非局部门禁，须按 AGENTS.md 扩大授权测试范围。

## 9. 受影响的开发者参考页面

实施时同时更新 `doc/reference/en/<slug>.md` 与 `doc/reference/zh-CN/<slug>.md`：

- **`customer-hostnames`**：合并客户页面组合、h2／参数、`edit_hostname`、上下文隐藏字段、整页导航／渲染、新 CUD 辅助方法、303／422 流程、发现入口及移除独立界面。保留功能参考页及目录项，主机名行为仍需独立文档。
- **`customers`**：表格下嵌入全局区域、详情发现入口、查询上下文及既有客户生命周期行为。
- **`page-shortcuts`**：所有者发现目标改为客户首页＋锚点；建议仅作用于表单，不筛选全局列表。
- **`tenancy-and-roles`**：合并首页／CUD 精确路径锁定、继承所有者门禁，以及建议与上下文的区别。
- **`system-map`**：客户作为唯一侧栏／首页界面，全局主机名区域及 CUD 路径。
- **`access-grants`**：区分客户 GET 界面与主机名 CUD 控制器／授权身份；移除独立侧栏／首页描述，保留双语主机名资源标签。

最终审查前搜索 `doc/reference/` 中旧 URL／辅助方法名、`?edit=` 与独立导航文案，同步其他受影响的 EN／zh-CN 引用。公开主机名解析及客户生命周期说明须与既有行为保持一致。
