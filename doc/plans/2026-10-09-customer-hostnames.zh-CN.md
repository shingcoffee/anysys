# 客户主机名——需求简报、UX 契约与实施计划

状态：**READY_FOR_IMPLEMENTATION**。本次仅完成研究与规划；应用实现及验证属于后续工作。日期：2026-10-09。

> 下文的独立管理页面／侧栏提案已由[客户与主机名合并计划](2026-10-09-customers-hostnames-merge.zh-CN.md)替代。保留此历史简报，作为绑定、校验、并发及公开路由的契约；当前管理 URL 和页面组合以合并计划及开发者参考为准。

本计划遵循 `AGENTS.md`，依次采用产品负责人和 UX 设计师角色文件的流程。按用户要求，将下游需求、设计与计划合并到双语 `doc/plans/` 文件，不使用角色默认的 UX 文档路径。保留现有全部未提交的快捷路径、网站、验证码、路由、数据库结构、翻译、参考文档及测试工作。本决策仅替代 `2026-10-08-page-shortcuts.*.md` 中由部署配置主机映射的提案；其他行为以本次查阅的现有源码为基线。

## 1. 产品负责人需求简报

### 1. 问题陈述

平台所有者需要在数据库中保存并管理各客户的快捷路径主机名，使客户选择规则无需修改进程配置即可立即生效。一个客户可绑定多个主机名，但每个主机名只能对应一个客户。现有快捷路径功能已支持按主机路由；本次为映射提供持久化存储和仅平台所有者可用的管理入口，并保留既定公开路由与租户隔离规则。

### 2. 用户故事

- **S1：**作为 **owner**，我希望添加、编辑和移除主机名与客户的绑定，以便集中管理专属快捷地址。
- **S2：**作为 **owner**，我希望查看停用客户的已保存绑定，并从相关页面进入管理，以便排查和维护映射。
- **S3：**作为 **member**，我希望已发布的快捷地址始终选择预期客户，以便按既定访问规则进入正确的公开内容。

### 3. 验收标准

| 故事 | 可观察标准 |
|---|---|
| S1 | 仅平台所有者可在 `/81721200/admin/maintenance/platform/customer_hostnames` 读取或修改映射。一个客户可绑定多个全局唯一的规范主机名。新增或改绑仅提供已存在且已启用的客户，标签包含名称与编号。无效提交返回 422 并保留输入；成功操作返回 303 并显示翻译后的反馈。 |
| S2 | 停用客户的绑定仍显示已保存主机名、客户名称与编号，以及“不可用”状态。此类绑定可移除或改绑到启用客户。平台侧栏、快捷路径管理及客户详情提供仅所有者可见的入口。客户软删除或恢复会改变显示状态及路由，无需删除、重建绑定。 |
| S3 | 无客户前缀的路径使用精确主机绑定的客户；未绑定时使用默认客户 `81721200`。显式八位客户前缀优先于主机选择。绑定客户停用时返回 404，不提供其他客户的内容。已提交的映射变更在下一请求生效，无需重启；公开 GET/HEAD 及符合条件的公开表单 POST 保持既定行为。 |

### 4. 边界与错误场景

- 匿名访问沿用登录处理；admin/member 被拒绝；即使所有者访问其他客户的平台前缀，也不能管理映射。查询参数或请求体中的客户编号不能替代 URL 授权上下文。
- 映射为空、无启用客户选项、长主机名或客户名称、新增或更新失败、编辑或移除已不存在的记录，以及保留停用客户选项，都须清晰呈现。
- 规范化后重名，包括并发提交，返回主机名错误，不发生部分改绑。保存期间客户停用或永久删除须重新检查并处理；数据库不可用时不得改选其他租户。
- 子域名不继承父域绑定。协议、端口、路径、用户信息、通配符、无效标签及非规范客户编号均按既有规则拒绝。

### 5. 明确不在范围内

DNS 记录、域名所有权验证、证书与 TLS、入口路由配置、自动更新 Rails HostAuthorization、通配主机名、批量导入、租户自行配置主机及新增角色均不属于本功能。不保留环境变量或内存映射兼容路径，也不自动导入旧配置。

### 6. 待确认问题

无阻塞问题。默认采用全局列表、按主机名排序、同页原生编辑表单；已有记录可保留原停用客户；永久删除客户时级联删除绑定。

```text
## RETURN
problem_statement: 持久化精确客户主机绑定，提供即时查询及仅所有者可用的管理入口。
user_stories:
  - S1：所有者集中管理主机绑定。
  - S2：所有者维护不可用绑定并从相关页面进入管理。
  - S3：成员按既定访问规则进入预期客户的公开内容。
acceptance_criteria:
  story_1: [所有者及精确平台前缀授权, 规范唯一的增改删, 启用客户选项, 303/422 反馈]
  story_2: [保留停用绑定, 可移除或改绑, 三处发现入口, 恢复后更新状态]
  story_3: [精确主机或默认客户选择, 显式前缀优先, 停用绑定返回 404, 下一请求生效]
edge_cases: [越权访问, 空状态, 规范化与并发重名, 客户生命周期]
out_of_scope: [DNS/TLS/入口配置, 自动主机授权, 通配符或导入, 租户主机管理]
open_questions: []
ready_for_brainstorm: true
notes: 上游技术决策已确定；进入下述 UX 与实施契约。
```

## 2. 研究结论与已确定的技术契约

- `PageShortcuts::Hosts` 当前使用 Addressable 规范化，并通过 `parse` 将 `PUBLIC_PAGE_HOSTS` 转为冻结的 `config.x.page_shortcuts.hosts`。仅替换映射机制：保留 `normalize`、`customer_id(host)`、`dedicated?(host)`、`prefix` 和 `path` 接口。
- 新增 `CustomerHostname`：`hostname` 非空、最多 253 字节，值由 `PageShortcuts::Hosts.normalize` 规范化；`customer_id` 为非空 bigint，索引外键指向 `customers`；包含时间戳；**对 `hostname` 建全局唯一索引**，不使用 `(customer_id, hostname)` 唯一索引。一个客户可有多条绑定；不增加映射状态或启用字段。
- 模型保持精简，仅承载规范化与持久化约束；管理业务使用 Reform 契约及 Trailblazer Save/Destroy 活动。复用 Addressable，不增加解析器。新增或更新检查规范主机名唯一性，排除编辑记录本身；并发冲突以唯一索引为最终约束。
- `Hosts.customer_id(host)` 规范化输入后，直接从 `CustomerHostname` 读取标量 `customer_id`；未命中则返回 `config.x.page_shortcuts.default_customer_id`，仍为 `81721200`。`dedicated?` 判断精确映射是否存在。无效或 nil 主机视为未绑定。查询不关联或筛选启用客户，也不得捕获数据库错误后回退到默认租户。
- 查询实时读取数据库，不使用进程或全局缓存、记忆化哈希或 Rails 缓存。必要时使用 uncached 查询，确保同一进程修改后重复调用也能看到最新记录。解析器原有按请求、按主机和路径缓存仍是路由解析快照；展示快照不得变成主机名注册表。
- 删除 `Hosts.parse`、仅用于 JSON 的依赖、环境变量读取、`to_prepare` 映射赋值，以及所有运行时 `config.x.page_shortcuts.hosts` 用法。保留默认客户初始化设置。启动或绘制路由时不得查询映射。不增加旧配置回退或导入逻辑。
- `Resolver.resolve` 已先提取显式客户前缀再查询主机，并检查 `Customer.exists?`；`unavailable_root?` 已将专属主机对应的停用客户视为终止条件。保留职责划分：绑定存在就选择该 CID，即使客户已停用；再由可用性检查返回 404，绝不切换默认或其他客户。未绑定共享主机且默认客户尚不存在时，保留根路径既有初始化行为。
- `Customer` 通过 `default_scope { visible }` 隐藏停用记录。可选客户使用正常启用作用域；已保存绑定的标签与状态使用明确的无默认作用域关联，或批量 `Customer.unscoped` 查询。展示时不得丢失停用客户身份，也不得逐行查询。
- 新增或改绑要求客户已存在且已启用，并通过 `PageShortcuts::PathPolicy.customer_id` 严格解析八位编号。已有绑定若保持原停用客户不变，可在修改主机名时保留该身份。软删除保留绑定；恢复后重新具备路由资格。增加 `Customer#customer_hostnames`，使用 `dependent: :destroy` 和外键 `on_delete: :cascade` 处理永久删除；不存在的客户编号不能保存。
- 映射提交后立即影响路由查询；**DNS、TLS、入口路由与 Rails HostAuthorization 仍由部署独立管理**。保存绑定不会将主机加入 Rails 允许列表，也不证明网络可达。不得自行实现 HostAuthorization 层。

## 3. UX 契约

### 3.1 页面清单与发现入口

| 页面 | 导航区域 | 行为 |
|---|---|---|
| `/81721200/admin/maintenance/platform/customer_hostnames` | 后台 → 维护 → 平台 → 客户主机名 | 全局列表及新增或编辑表单；仅平台所有者可用。 |
| 平台侧栏 | 后台 → 维护 → 平台 | 在既有所有者 + `81721200` 条件内，于“客户”旁增加“客户主机名”。 |
| `/:cid/admin/maintenance/page_shortcuts` | 后台 → 维护 → 页面快捷路径 | 仅所有者可见的次要“管理客户主机名”链接；指向固定平台 URL，当前客户启用时预选该客户。 |
| `/81721200/admin/maintenance/platform/customers/:id` | 后台 → 维护 → 平台 → 客户 | 在详情内容旁复用小型入口组件；指向固定平台 URL，所展示客户启用时预选该客户。 |

管理首页始终显示全局列表。可选 `?for_customer=<cid>#hostname-form` 仅预选启用客户，不缩小授权范围，也不替换平台 URL 中的 CID。建议客户不可用时显示提示并保持选择为空，不自动选择其他客户。

### 3.2 布局与数据

```text
维护 / 平台 / 客户主机名
客户主机名                                [标准后台外壳]
将主机名绑定到客户，用于公开快捷路径路由。

[ 添加主机名 / 编辑主机名                                ]
[ 出错时显示错误摘要                                    ]
[ 主机名输入框           客户原生下拉框                  ]
[ 字段提示与错误         名称（12345678）                ]
[ 添加主机名 / 保存      取消（仅编辑时）                ]

[ 已保存的主机名                                        ]
[ 主机名 | 客户名称及编号 | 可用状态 | 操作               ]
[ example.com | Acme（12345678） | 可用 | 编辑 移除       ]
[ old.example | Legacy（23456789） | 不可用 | ...        ]
[ 移除主机名不会删除客户及其页面。                       ]
```

- 复用 `AdminPageComponent`，提供翻译后的面包屑、标题、说明及后台宽度。内部采用 `min-w-0 space-y-6`，放置两个全宽 `CardComponent(padding: :none)`，区域间距为 `p-4 sm:p-6`。Flash 仅由现有后台外壳渲染一次。
- 表单采用 `grid grid-cols-1 gap-4 md:grid-cols-2`；显式标签；主机名文本框使用 `font-mono`、`autocapitalize="none"`，关闭拼写检查；客户原生下拉框使用 `[label, cid]` 选项。沿用 `form-label` / `input-field min-h-11 w-full`。操作在手机端纵向全宽排列，从 `sm` 起按内容宽度展示。
- 列表按规范主机名及记录 ID 排序。从 `md` 起采用相邻快捷路径组件的语义表格；低于 `md` 使用卡片式堆叠行，显示翻译后的移动端标签，客户名称换行，主机名使用 `break-all`。列包含已保存主机名、客户名称及数字编号、派生可用状态、编辑与移除。主机名显示为文本；状态仅表示客户是否启用，不代表 DNS/TLS 或页面发布状态。
- 复用 `ButtonComponent`、`BadgeComponent`、`EmptyStateComponent` 和 `AlertComponent(auto_dismiss: false)`。可用使用成功徽标，停用客户使用中性“不可用”徽标。编辑与取消为次要操作，移除为危险操作，保存或添加为主要操作。停用绑定保留所有行操作。

### 3.3 组件契约与复用

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: hostnames,
  available_customers: available_customers, # [[translated_name_and_id_label, cid], ...]
  customer_id: 81721200,                   # 平台 URL 上下文，不是选中的客户
  errors: [], form_values: {}, editing_hostname: nil
)
CustomerHostnames::ManagementLinkComponent.new(
  current_user: current_user, target_customer_id: target_customer_id
)
```

初始化必需参数为 `hostnames:` 和 `available_customers:`；默认值为 `customer_id: 81721200`、`errors: []`、`form_values: {}` 及 `editing_hostname: nil`。`form_values` 包含 `hostname` 与 `customer_id`；提交值优先于编辑记录，新增时未提供的值保持为空。`errors` 同时支持字段消息哈希和基础消息数组，与 `PageShortcuts::ManagementComponent` 一致。`hostnames` 提供已保存记录及批量或预加载的客户身份，包括停用记录。`available_customers` 仅包含启用客户，按名称及编号排序，标签格式通过 I18n 显示名称与编号。

小型 `ManagementLinkComponent` 封装现有次要按钮或链接样式，仅在 `current_user.platform_owner?` 时渲染，固定链接到平台 CID `81721200`，提供目标客户时附加 `for_customer`。在快捷路径管理和客户详情挂载；侧栏继续使用既有 contributor 模式。该组件不查询主机映射。`Admin::Maintenance::Platform::SettingsLinkCardComponent` 可作为入口样式参考，但这两处现有页面更适合紧凑次要链接。

### 3.4 原生交互流程与状态

- 新增：首页 → 输入主机名并选择客户 → 原生 POST → 原子保存成功 → 303 首页及翻译后的 Flash。编辑：行内编辑 → GET 首页 `?edit=<id>#hostname-form` → 同一表单预填 → 原生 PATCH → 303 首页。取消为普通 GET 首页。移除使用 `button_to`，通过隐藏方法字段提交原生 DELETE → 303 首页；客户及页面保持完整。不增加确认弹窗。
- 写入参数仅为 `customer_hostname[hostname]` 和 `customer_hostname[customer_id]`。首页 `edit` 必须在授权后按全局受管记录查询。路由仅提供 `index/create/update/destroy`，不增加独立新增或编辑页面。
- 验证失败：以 422 渲染完整首页，保留尝试提交的值及编辑身份，展示错误摘要和关联字段错误；已保存记录不变。并发重名归入主机名错误。编辑、更新或移除的记录不存在时返回 404。
- 编辑停用客户绑定：在启用客户列表之外，仅补充该记录原客户的不可用保留选项。修改主机名时可保持原客户，或改绑至启用客户；不能用于新增绑定或其他绑定的改绑。失败后不得自动选择其他客户。
- 列表为空：保留表单并显示“暂无主机名”。无启用客户：说明状态并链接平台“客户”页；禁止提交新增分配。已有停用绑定仍可移除，也可在保留客户不变时修改主机名。
- 加载采用正常浏览器导航，不增加动态骨架屏或功能专用 JavaScript。运行故障沿用 Rails 错误处理；页面不探测 DNS/TLS 或供应商状态。权限不足沿用既有鉴权处理；所有者访问错误平台 CID 时，在任何映射查询或写入之前返回 404。
- 无障碍：唯一字段 ID 与标签、必填属性、`aria-invalid`、通过 `aria-describedby` 关联提示与错误、`role="alert"` 摘要、表格 caption 和 scoped headers、可见焦点、含主机名的翻译操作标签，以及至少 44 px 点击区域。全部管理表单及编辑、取消链接设置 `data-turbo="false"`，并在禁用 JavaScript 时验证。

### 3.5 双语文案与设计参考

使用成对 `config/locales/customer_hostnames.en.yml` / `.zh-CN.yml`，侧栏键放入成对 `chrome` 文件。完全相同的操作或状态文案复用现有公共键。其余标题、提示、验证、Flash、选项格式及无障碍标签均在调用时通过 I18n 翻译，插值变量保持一致。

| English copy | 简体中文 |
|---|---|
| Customer hostnames | 客户主机名 |
| Manage customer hostnames | 管理客户主机名 |
| Add hostname / Edit hostname / Saved hostnames | 添加主机名／编辑主机名／已保存的主机名 |
| Hostname / Customer / Availability | 主机名／客户／可用状态 |
| Choose a customer | 请选择客户 |
| `%{name} (%{id})` | `%{name}（%{id}）` |
| Available / Unavailable | 可用／不可用 |
| Enter an exact hostname without a scheme, port or path. | 请输入完整主机名，不含协议、端口或路径。 |
| Availability reflects customer status, not DNS or TLS readiness. | 可用状态仅反映客户是否启用，不代表 DNS 或 TLS 已就绪。 |
| DNS, TLS, ingress and Rails HostAuthorization are configured separately by deployment. | DNS、TLS、入口路由及 Rails HostAuthorization 允许列表由部署单独配置。 |
| Removing a hostname keeps the customer and its pages. | 移除主机名不会删除客户及其页面。 |
| No hostnames yet / No active customers available. | 暂无主机名／暂无可选的启用客户。 |
| This hostname is already assigned to a customer. | 此主机名已绑定客户。 |
| Choose an existing active customer. | 请选择已存在且已启用的客户。 |

查阅项目组件之前，已获取官方 shadcn [Input](https://ui.shadcn.com/docs/components/input)、[Card](https://ui.shadcn.com/docs/components/card)、[Native Select](https://ui.shadcn.com/docs/components/native-select) 和 [Table](https://ui.shadcn.com/docs/components/table) 文档。通过项目 ViewComponent/Tailwind 规范落地其标签、提示与错误关联、卡片区域、移动端原生选择及语义表格模式。本环境不提供 shadcn skill/MCP；这些官方资料作为本次设计咨询依据。

```text
## RETURN
ux_doc: doc/plans/2026-10-09-customer-hostnames.zh-CN.md
surfaces:
  - name: 客户主机名管理
    nav_area: admin
    new_components: [CustomerHostnames::ManagementComponent]
    reused_components: [AdminPageComponent, CardComponent, ButtonComponent, BadgeComponent, EmptyStateComponent, AlertComponent]
  - name: 快捷路径管理及客户详情的所有者入口
    nav_area: admin
    new_components: [CustomerHostnames::ManagementLinkComponent]
    reused_components: [ButtonComponent]
  - name: 平台侧栏入口
    nav_area: admin
    new_components: []
    reused_components: [MaintenanceContributor, SidebarNode]
overall: READY_FOR_FRONTEND
notes: 使用用户指定的计划路径；原生表单、响应式行与既有后台外壳已确定实施方式。
```

## 4. 实施顺序与文件清单

1. **后端——存储与验证。**新增 `db/migrate/<next_timestamp>_create_customer_hostnames.rb`、`app/models/customer_hostname.rb`、`spec/factories/customer_hostnames.rb`；扩展 `app/models/customer.rb`；重新生成 `db/schema.rb`，保留待提交的 PageShortcut 迁移及结构。新增 `app/services/customer_hostnames/contracts/hostname.rb`、`activities/save.rb`、`activities/destroy.rb`。验证及持久化前规范化；校验严格 CID、启用客户分配或原停用客户保留；事务更新；保存时重新检查客户状态；将唯一索引或外键并发失败转换为稳定错误。模型及活动测试覆盖数据库唯一性、外键、软删除、恢复和永久删除。
2. **后端——实时主机查询。**按第 2 节修改 `app/services/page_shortcuts/hosts.rb` 和 `config/initializers/page_shortcuts.rb`。保留解析器、公开路径、验证码接口及路由顺序。将测试中所有配置映射 stub 或赋值替换为真实 `CustomerHostname` 记录；仅保留既有测试需要的默认 CID 覆盖。删除两份 `page_shortcut_errors` 文件中废弃的 parse/`invalid_hosts` 翻译键。全仓搜索 `PUBLIC_PAGE_HOSTS`、`config.x.page_shortcuts.hosts`、`config.hosts` 赋值或 stub，以及 `Hosts.parse`；区分部署使用的 Rails `config.hosts` 与已移除的快捷路径映射。
3. **安全——路由与控制器。**在 `config/routes.rb` 既有 platform scope 内新增 `resources :customer_hostnames, only: %i[index create update destroy], controller: "maintenance/platform/customer_hostnames"`。新增 `app/controllers/admin/maintenance/platform/customer_hostnames_controller.rb`，继承 `ApplicationController` 并设置 `dashboard_menu_item :maintenance`。复用 `RouteAuthorization` 的认证、平台所有者与 CanCan 流程；为全部操作添加局部精确 **URL** 检查 `request.path_parameters[:customer_id].to_s == "81721200"`，不符返回 404，且先于绑定访问。不得使用合并后的查询或请求体参数、请求体选中客户或当前代管客户替代，也不全局修改其他平台控制器策略。授权后按绑定 ID 全局查询，因为映射由所有者集中管理。仅允许两个嵌套字段；建议或选中客户单独查询。使用 `admin_maintenance_platform_customer_hostnames_path` 和 `admin_maintenance_platform_customer_hostname_path` helper，固定平台 CID；成功返回 303，验证失败渲染 422。
4. **前端——管理与发现入口。**新增 `app/components/customer_hostnames/{management_component,management_link_component}.{rb,html.erb}` 和 `app/views/admin/maintenance/platform/customer_hostnames/index.html.erb`。在 `app/components/page_shortcuts/management_component.html.erb` 及 `app/views/admin/maintenance/platform/customers/show.html.erb` 挂载小型入口组件；仅在 `app/services/maintenance_contributor.rb` 既有所有者且精确平台客户分支增加侧栏项。新增双语功能文件及对应侧栏翻译。遵循第 3 节组件接口、启用选项、无默认作用域的已保存身份、无 JS 增改删及响应式、无障碍状态。
5. **文档——与实现同批完成。**新增 `doc/reference/{en,zh-CN}/customer-hostnames.md`，保持 front matter 及必需的概要、流程、实现、需要特别注意、关键代码章节对齐；在 `app/services/developer_docs/catalog.rb` 的 `customers` 旁登记 `customer-hostnames`。同步更新两种语言的 `page-shortcuts.md`，将环境或哈希配置改为数据库管理并说明 HostAuthorization 独立配置；更新 `customers.md` 的入口及生命周期、`tenancy-and-roles.md` 的精确前缀授权，以及 `system-map.md` 的新页面。涉及主机选择的网站或公开渲染参考文档补充交叉链接。清理参考文档中的旧配置说明；旧计划明确为历史或已被替代，不作为运行时兼容指令。
6. **QA、发布与评审。**按下方验收矩阵执行，再构建资源并以真实所有者登录进行指定视口冒烟检查。路由或授权变化需在定向检查后运行全量回归。若重启，遵循 `AGENTS.md` 资源遮蔽与重启要求；授权测试须使用真实角色。完成规范及安全评审并报告真实结果，由人工提交。

获得实施授权后，将对应任务交给 anysys 后端、前端及安全角色，再进入 QA、发布及技术负责人、代码评审流程。本次规划变更仅创建用户指定的两份文档。

## 5. 验收测试与验证

| 测试位置 | 必需断言 |
|---|---|
| `spec/models/customer_hostname_spec.rb`、`spec/models/customer_spec.rb` | 大小写、末尾点及 Addressable IDN 规范化；合法标签与 253 字节上限；拒绝无效输入；跨客户规范主机名全局唯一；一个客户多主机；索引外键拒绝不存在的客户；停用保留、恢复及永久删除级联。 |
| `spec/services/customer_hostnames/contracts/hostname_spec.rb`、`activities/{save,destroy}_spec.rb` | 新增或改绑仅启用客户；原停用 CID 可保留不变；规范化更新排除自身；真实唯一索引约束及活动并发错误处理；持久化时客户缺失或停用；原子失败后旧绑定不变。 |
| `spec/services/page_shortcuts/hosts_spec.rb` | 精确匹配、无通配继承、无效或 nil 返回默认、默认 81721200、一个客户两个主机、停用专属绑定仍返回保存 CID/true；新增、修改、改绑或删除后重复查询可看到已提交数据库状态，无需清缓存。 |
| `spec/requests/admin/maintenance/platform/customer_hostnames_spec.rb` | 每个操作拒绝匿名、admin 和 member；所有者在精确平台 CID 可全局管理；所有者访问其他启用客户的平台前缀时，在读写前拒绝；伪造请求体或查询编号不能绕过检查；原生新增、编辑、PATCH、DELETE，303 Flash、422 保留字段、缺失 ID 返回 404，停用记录可见且可移除。 |
| `spec/components/customer_hostnames/{management_component,management_link_component}_spec.rb`，既有快捷组件、客户请求及侧栏测试 | 组件接口与默认值、`[名称 + 编号, cid]` 启用选项、停用编辑保留选项、空列表或无启用客户状态、标签转义、错误摘要与字段 ARIA、CSRF/方法/原生表单、响应式类、仅所有者可见且固定平台地址的入口及可选预选；两种语言及键集一致。 |
| 既有 `spec/services/page_shortcuts/{resolver,public_path,public_path_integration,public_path_lookup}_spec.rb` 和 `spec/requests/page_shortcuts*_spec.rb` | 真实绑定替代哈希；前缀优先、默认或共享主机、下一请求即时反映映射及公开链接前缀变化、停用客户根及非根路径返回 404，即使默认客户有可用首页也不回退；恢复、GET/HEAD/公开 Page POST、挂载路径、规范端点、共享覆盖及租户隔离。 |
| 既有验证码快捷路径测试及 `spec/requests/route_authorization_spec.rb` | 别名限流与重放按实时绑定重新解析；映射不放宽 admin/member 授权、可信目标身份或既有跨租户规则。不新增主机授权中间件。 |
| `spec/services/developer_docs/repository_spec.rb` | 两种语言的新参考页均进入目录，渲染必需章节且交叉链接有效；相关参考不再要求环境或哈希配置。 |

原 `page_shortcuts_review_spec.rb` 通过哈希插入不存在的 CID。新增外键后，改为真实客户在启用时绑定、随后软删除；另行断言不存在 CID 的保存或外键失败。保留独立的共享主机初始化测试：平台客户 81721200 尚不存在且没有主机绑定。

先运行每个修改层及更新主机 fixture 的定向测试，包括通过配置映射搜索定位到的全部快捷路径与验证码集成文件。随后在支持时运行 `bin/rails parallel:prepare && bin/rails parallel:spec`，否则使用 `bundle exec rspec`。通过 `bin/rails tailwindcss:build` 重建 Tailwind。本功能不计划新增 JavaScript；若实施时修改 JS，须同步镜像测试并运行 `npx vitest run --coverage`，确保修改文件的行、分支及函数覆盖率均为 100%。

浏览器验收：禁用 JavaScript 后，所有者可新增、编辑及移除；EN 与 zh-CN 在 320/390/768/1024/1440 px 和 200% 缩放下可用；长规范主机名与名称正确换行；键盘标签及焦点可用；验证停用绑定与失败编辑。对已由部署允许的主机，确认映射变更无需重启即可生效；另行演示或记录：保存未被允许的主机不会修改 Rails HostAuthorization、DNS、TLS 或入口路由。

## 6. 交接清单

- [ ] 已实现数据库结构、规范唯一性及外键行为。
- [ ] 已移除运行时环境或哈希映射，并验证实时接口、默认客户与显式前缀优先。
- [ ] 已验证仅所有者且精确平台前缀的增改删、停用绑定保留及三处入口。
- [ ] 已实现响应式原生管理组件及成对 I18n。
- [ ] 已同步双语开发参考及目录，说明部署边界。
- [ ] 已记录定向、全量检查及浏览器验收的真实结果，并保留原有未提交工作。
