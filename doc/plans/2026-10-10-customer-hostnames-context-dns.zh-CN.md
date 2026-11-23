# 客户主机名——客户上下文与保存前 DNS 校验

日期：**2026-10-10**。状态：**READY_FOR_FRONTEND / READY_FOR_PARALLEL_BUILD**。本文件仅包含研究、设计与实施计划；运行验证在构建阶段完成。

## 1. 已确认范围与研究依据

`target_customer_id` 从预选建议改为持续保留的**客户限定管理模式**。未提供该参数时，客户首页保留全局主机名表单、下拉框和列表。每次通过基础校验的保存都须在持久化前验证直接指向 `anysys.net` 的 CNAME，包括主机名未变和仅修改客户的保存。沿用现有路由、数据库结构及原生表单；无需新增 JavaScript 或 gem。

已阅读 `.cursor/agents/anysys-ux-designer.md`、项目规范、`CustomerHostnames::ManagementComponent`／`ManagementLinkComponent`、客户首页／详情视图、`AdminTableComponent`、Card／Button／Alert 基础组件、两个控制器、`CustomersIndexContext`、Save／Destroy Activity、Reform 合约及现有上下文／并发测试。本计划取代 2026-10-09 计划中的「仅预选建议」与「不校验 DNS」约定；合并页面结构继续作为实施基线。

当前工具集没有 shadcn skill／MCP。父级已查阅官方 [Field 文档](https://ui.shadcn.com/docs/components/field)，本计划也已核对：纵向 FieldTitle／只读内容／FieldDescription；可编辑字段采用 FieldLabel／控件／FieldDescription／FieldError；响应式分组与无障碍校验。通过现有 ViewComponent + Tailwind 实现。DNS 研究依据：[Ruby 3.2 Resolv::DNS](https://docs.ruby-lang.org/en/3.2/Resolv/DNS.html) 与 [Ruby 3.2.8 源码](https://github.com/ruby/ruby/blob/v3_2_8/lib/resolv.rb)。

## 2. 界面清单与布局

| 界面 | 导航区域 | 设计 |
|---|---|---|
| 客户详情 → 管理客户主机名 | admin → 维护 → 平台 → 客户 | 现有链接打开固定平台客户首页，携带所展示客户的编号及 `#hostname-form`，包括停用客户。 |
| 不带目标的客户首页 | 同上 | 现有客户表格之后，展示全局主机名表单及已保存列表。 |
| 带 `target_customer_id=C` 的客户首页 | 同上 | 现有客户表格之后，展示限定客户的主机名表单／列表；客户表格搜索、排序和分页不改变目标。 |
| 现有主机名 POST／PATCH／DELETE 端点及整页 422 | 同上 | 原生写入／失败流程保留模式、表格上下文、尝试输入的主机名及已保存编辑身份。 |
| 现有所有者入口，包括页面快捷路径 | admin → 维护 → 页面快捷路径 | 携带目标即进入客户限定模式；不带目标则进入全局模式。 |

```text
客户 h1 + 现有页面操作
现有客户表格／搜索／排序／分页

客户主机名 h2 + 现有说明
┌ 添加主机名／编辑主机名 h3 ──────────────────────────────┐
│ DNS／部署说明；持续显示的错误汇总                       │
│ 主机名                         客户                    │
│ [forms.example.com       ]     Acme (12345678)          │
│ 完整主机名及 CNAME 提示／错误   客户限定模式说明         │
│ 目标客户停用说明，按需显示                             │
│ [添加主机名／保存] [取消，仅编辑模式]                   │
└────────────────────────────────────────────────────────┘
┌ 已保存的主机名 h3 + 指定客户的列表说明 ─────────────────┐
│ 主机名 | 客户名称及编号 | 可用状态 | 操作               │
│ 仅包含 customer_id = C 的绑定；编辑／移除               │
└────────────────────────────────────────────────────────┘
```

- 复用一次 `AdminPageComponent`、`AdminTableComponent`、现有两个 `CardComponent(padding: :none)`、`ButtonComponent`、`AlertComponent(type: :error, auto_dismiss: false)`、`BadgeComponent` 和 `EmptyStateComponent`。新增组件：**无**。
- 客户限定模式以只读文本组替换客户下拉框：翻译后的「客户」标题（`form-label` 样式）、转义后的 `target_customer.name` 与编号（使用 `customer_hostnames.customer_option`）及上下文提示。采用 `role="group"`、`aria-labelledby`、`aria-describedby` 关联标题／提示／错误；不存在输入控件时，不使用 `<label for>`。不显示禁用下拉框或可聚焦的伪控件。客户身份始终取自服务端目标，不能取自尝试提交的嵌套字段。
- 保留主机名标签／输入／提示／错误及 `aria-invalid`／`aria-describedby`；客户校验错误显示在只读身份下方，并加入 `role="alert"` 汇总。基础冲突错误显示在汇总中。
- 保留 `p-4 sm:p-6`、`space-y-5`、字段 `space-y-2`、`grid grid-cols-1 gap-4 md:grid-cols-2`、`min-w-0`、项目文字／颜色令牌、名称及错误的 `break-words`、主机名的 `break-all` 和操作的 `min-h-11`。低于 `sm` 时操作纵向全宽排列；已保存列表保留语义化移动端堆叠／`md:table` 布局及全部操作。
- 目标客户存在但停用：展示名称／编号及翻译后的说明；新增模式禁用主机名／新增控件和提交按钮。限定范围内的现有绑定可保留该停用客户并编辑主机名，允许保存及移除。限定模式不提供重新分配界面。全局模式保留现有启用客户选项及停用客户仅可保留的编辑规则。
- 限定列表为空：复用 EmptyState，并显示上下文说明；新增表单仍可见。客户搜索无结果时也保留限定分区。可用状态继续表示客户是否启用，不表示实时 DNS／TLS 状态。
- 加载采用原生页面导航。保存可能等待有时限的 DNS 查询；不新增加载动画或单独检查操作。失败以完整 422 页面呈现持续显示的汇总及主机名行内错误。TLS、入口路由和 HostAuthorization 仍须由部署配置。

## 3. 状态与导航约定

`C` 表示 `/81721200/admin/maintenance/platform/customers`，`T` 表示已清理的标量 `q/sort/dir/page`，`B` 表示限定模式下经验证的 `target_customer_id`。

| 流程 | 必需结果 |
|---|---|
| 详情入口 | `C?target_customer_id=<所展示客户编号>#hostname-form`；不能因客户停用而省略编号。 |
| 新增／编辑 | 原生 POST `C/hostnames` 或 PATCH `C/hostnames/:id` 携带 T 和 B；编辑 GET 另带被点击行的 `edit_hostname` 及锚点。 |
| 保存／移除成功 | 303 返回 `C?T&B#hostname-form`；清除 `edit_hostname`，展示翻译后的提示、刷新后的限定列表及空白新增表单，保留只读客户。 |
| 取消 | GET `C?T&B#hostname-form`；清除编辑状态，保留目标与表格状态。 |
| 校验／DNS／移除失败 | 使用 dashboard 布局返回整页 422，保留 T／B、错误、原始主机名输入（包括空值）及已保存编辑身份。失败准备逻辑不得重置模式或应用旧建议逻辑。 |
| 客户表格搜索／排序／分页 | 保留 B。搜索沿用现有重置页码规则；排序／分页沿用现有行为。客户表格自身仍为全局范围。 |
| 无效目标／记录不可用 | 显式目标格式错误、为空、非标量或不存在，以及编辑／更新／移除记录缺失或属于其他客户时，返回标准 404。完全不提供目标参数属于合法全局模式。 |

原生移除表单保留 T／B 和当前服务端渲染的编辑／表单状态，仅供移除失败时恢复显示；Destroy 接收路由选定记录，不接收这些展示字段。删除成功即清除编辑状态，即使此前正在编辑另一行。表格导航无需保留 `edit_hostname`，但必须保留客户限定模式。全局模式成功／取消仍返回全局新增状态。

## 4. 已约定的前端／控制器 API

```ruby
CustomerHostnames::ManagementComponent.new(
  hostnames: @hostnames, available_customers: @available_customers,
  customer_id: current_customer_id, target_customer: @hostname_target_customer,
  errors: @errors || [], form_values: @form_values || {},
  editing_hostname: @editing_hostname, table_context: @table_context || {}
)
```

### 前端边界

- 组件新增 `target_customer: nil`。`customer_id` 继续表示平台 URL 客户，与目标客户区分。组件 `table_context` 继续**仅保留 q/sort/dir/page**。
- 从 `target_customer.id` 派生独立目标上下文哈希，合并到 `index_path`、`edit_path`、写入路径辅助方法和 `removal_params`。保存及移除提交各包含且仅包含一个**顶层**隐藏字段 `target_customer_id`；写入路径带查询参数时也避免重复隐藏控件。
- 限定模式保存可省略嵌套 `customer_hostname[customer_id]`，由控制器权威设置。客户编号展示／表单辅助方法在限定模式优先使用目标；原始主机名尝试值及全局模式原始客户输入仍按现有规则处理。
- 客户首页传入 `target_customer: @hostname_target_customer`。其中 `AdminTableComponent` 接收由安全工程师准备的 `@table_context`，含 T 及已验证 B。
- **AdminTable 无需新增上下文 prop：**原生 GET 表单已将搜索／筛选／page／sort／dir 以外参数输出为隐藏字段（`admin_table_component.html.erb:41–43`），排序／分页辅助方法合并 `params`。固定 `base_path`、`turbo_page_requires_reload` 与显式 dashboard 布局已保证同级表单上下文及时刷新，包括 frame 请求和 422 页面。验证现有行为即可。
- 客户详情当前传入 `@customer.active? ? @customer.id : nil`；改为传入 `@customer.id`。共享链接目标和 API 已满足设计。

### 安全／控制器边界

- 先保留继承的认证／平台所有者授权，再检查精确 `request.path_parameters[:customer_id] == "81721200"`，**随后才可查询目标、表格或主机名**。首页及主机名增改删采用局部准备逻辑，不修改共享授权或其他客户流程。
- concern 新增 `prepare_hostname_target_customer`：区分未提供键与提供无效值；通过 `PageShortcuts::PathPolicy.customer_id` 要求严格八位标量编号，再用 `Customer.unscoped.find` 查询，使停用但存在的客户仍可访问。设置 `@hostname_target_customer`；无效／不存在目标抛出 `RecordNotFound`。在共享表格准备和限定记录查询前运行，包括携带目标的 JSON 首页请求。
- concern 新增 `hostname_scope`：存在目标 → `CustomerHostname.where(customer_id: @hostname_target_customer.id)`；否则为全局 relation。列表、GET `edit_hostname`、路由指定更新／移除记录、保存失败后的已保存编辑重载、移除失败后的可选编辑恢复均使用此范围。写入身份仍由 `request.path_parameters[:id]` 决定；查询／请求体记录编号不能覆盖。
- 限定模式保存以目标编号覆盖已许可的嵌套 `customer_id`，即使该字段缺失、为空或被伪造。保留原始主机名用于错误展示。准备限定行并批量加载停用客户身份；下拉选项仅供全局模式使用。
- 安全工程师负责 `@table_context`：白名单标量 T 加规范化、已验证 B。`ModuleEntriesResolver` **仅接收** `@table_context.slice("q", "sort", "dir", "page").symbolize_keys`；目标属于 UI／导航状态，不能作为客户表格筛选条件。固定返回辅助方法保留 T／B、清除编辑状态并保留 `#hostname-form`。
- 并发交接：向 Save／Destroy 传入可选 `expected_customer_id: @hostname_target_customer&.id`。后端须在写入锁内与已保存绑定比较；范围查询后发生归属变化时返回翻译后的 `binding_changed`，不得改回原客户或删除其他客户的行。初始外部编号由控制器返回 404。编辑身份仍可在限定范围内解析时，Activity 冲突渲染 422；若记录已转移／消失，限定范围内的失败准备返回 404，不能渲染外部行或悄然切换为新增。

## 5. DNS 服务与持久化顺序

在 `app/services/customer_hostnames/cname_verifier.rb` 实现薄封装 `CustomerHostnames::CnameVerifier`，使用 Ruby 标准库 `Resolv`，单一公开接口 `call(hostname:)` 返回 `:verified` 或 `:unverified`。模型／Reform 合约、渲染、Destroy 及加锁事务不执行 DNS。保留现有 Save Result／错误结构。

1. Save 的早期 Reform 校验使用最新已保存基线，并捕获规范化候选主机名。语法／客户／唯一性失败在网络 I/O 前按现有方式返回。
2. 持久化事务开始前，对绝对候选名称（`"#{normalized_hostname}."`）查询 `Resolv::DNS::Resource::IN::CNAME`。每次调用创建 resolver，设置有限重试（`timeouts = [1]`）及 **3 秒整体查询时限**，覆盖多 nameserver 和 TCP 回退／连接／读取。所有退出路径均关闭 resolver／请求资源；时限处理限定在此纯 I/O 封装内。
3. 只接受 answer 区中 owner 精确匹配所查询主机名的 CNAME，其唯一规范化目标必须为 `anysys.net`（忽略大小写及一个末尾点）。不接受 A／AAAA、IP 相同、后缀匹配、扁平化别名或链中后续跳转至 `anysys.net`。通过 `fetch_resource` 的 reply 及 answer 条目保留 owner 身份；高层资源对象隐藏此身份，提取逻辑还遍历其他区域。复用标准库解码／请求处理，不手写 DNS 协议。
4. 空回答、NXDOMAIN、错误／混合目标、损坏回答、resolver 错误及时限／传输失败均返回 `:unverified`，绝不持久化或失败放行。用单一主机名本地化错误说明直接 CNAME 要求和重试方式。每次保存使用新 resolver，不设置应用层成功缓存，不因主机名未变而跳过。
5. 验证成功后保留请求内证据 `(normalized_hostname, verified)`。沿用父行优先、按编号排序的锁、重载、启用／仅保留／唯一性／外键校验及双字段原子保存。在 sync／save 前比较加锁合约的**最终规范主机名**与已验证候选；不一致返回现有本地化 `binding_changed`，不在锁内重新查询 DNS。这可防止省略主机名／仅修改客户时，其他写入者在 DNS 查询期间改动已保存主机名。
6. 如上在锁内重查限定 `expected_customer_id`。Destroy 同样在删除前锁定／重载并检查归属，不依赖 DNS。最终主机名证据仍匹配时，保留现有全局过期写入及停用客户保留规则；并发主机名证据不一致则要求重新加载并重试。

此门禁仅确认保存时所需的 DNS 配置；已保存可用状态徽标不是 DNS 缓存状态，检查也不会配置部署基础设施。

## 6. 本地化约定

前端负责成对 `config/locales/customer_hostnames.en.yml`／`.zh-CN.yml`；后端负责成对 `customer_hostname_errors.en.yml`／`.zh-CN.yml`。复用现有客户身份、操作、可用状态、空标题和提示键。新增／更新下列建议键，两种语言保持键及插值集合一致，并在渲染／请求时翻译：

| `customer_hostnames` 下的键 | English | 简体中文 |
|---|---|---|
| `target_customer_hint` | Hostnames on this page belong to this customer. | 本页主机名仅属于此客户。 |
| `target_inactive_hint` | This customer is inactive. Existing hostnames can be edited or removed; new hostnames cannot be added. | 此客户已停用。可编辑或移除现有主机名，无法新增。 |
| `target_saved_hint` | Showing hostnames for %{customer}. | 仅显示 %{customer} 的主机名。 |
| `target_empty_hint` | No hostnames are assigned to %{customer} yet. | %{customer} 尚未绑定主机名。 |
| `hostname_hint` | Enter an exact hostname without a scheme, port or path. Its direct CNAME must point to anysys.net; checked on every Save. | 请输入不含协议、端口或路径的完整主机名。其直接 CNAME 必须指向 anysys.net，每次保存均会校验。 |
| `deployment_hint` | Configure a direct CNAME to anysys.net before saving. TLS, ingress and Rails HostAuthorization are configured separately by deployment. | 保存前请将直接 CNAME 配置为 anysys.net。TLS、入口路由及 Rails HostAuthorization 仍由部署单独配置。 |
| `errors.cname_unverified` | The hostname must have a direct CNAME to anysys.net. Check DNS configuration and try saving again. | 主机名必须配置直接指向 anysys.net 的 CNAME。请检查 DNS 配置后重新保存。 |

`%{customer}` 使用本地化名称／编号标签。`availability_hint` 继续准确说明：客户状态不能保证当前 DNS／TLS 就绪。

## 7. 文件归属与协作

| 负责人 | 独占文件／职责 |
|---|---|
| 后端开发 | 新增 `app/services/customer_hostnames/cname_verifier.rb`；`app/services/customer_hostnames/activities/{save,destroy}.rb`；成对 `customer_hostname_errors` locale；`spec/services/customer_hostnames/cname_verifier_spec.rb` 及 Activity 测试。负责 DNS 时限／直接性、最终值证据及可选 `expected_customer_id` 写入约束。Reform 合约保持纯校验，仅在规范化接口需要时修改。 |
| 安全工程师 | `app/controllers/concerns/customer_hostnames/customers_index_context.rb`；`app/controllers/admin/maintenance/platform/{customers,customer_hostnames}_controller.rb`。负责门禁、目标解析、`hostname_scope`、权威客户输入、resolver 参数切片、303／422／404 及恢复范围。 |
| 前端开发 | `app/components/customer_hostnames/management_component.{rb,html.erb}`；`app/views/admin/maintenance/platform/customers/{index,show}.html.erb`；成对 `customer_hostnames` UI locale。负责目标 prop、只读字段、停用状态、隐藏字段／上下文／路径保留及表格参数接入。预计无需修改共享表格实现。 |
| QA 工程师 | 主机名组件／链接测试；客户／主机名／合并流程请求测试；AdminTable 原生隐藏上下文专项回归；按需覆盖入口测试。负责授权、伪造／外部编号、停用模式及原生上下文／DNS 错误渲染集成。在 verifier 边界 stub，测试不得依赖公网 DNS。 |
| 父级／集成文档负责人 | 成对参考文档更新及最终合并审查。后端／前端提供 API／文案变更说明；安全工程师提供上下文／门禁说明。 |
| 发布工程师 | 执行限定范围测试、重建 Tailwind，并进行响应式／双语／原生浏览器冒烟验证；如需重启，遵循项目资源／服务器约定。 |

并行构建前统一 `target_customer`、`@hostname_target_customer`、`@table_context` 中规范 B、仅 T 的 resolver 输入、verifier 结果／错误键及可选 Save／Destroy `expected_customer_id:`。UI／错误 locale 与测试文件按上表划分，避免交叉编辑。现有断言「丢弃目标」「外部编辑优先」「停用客户详情进入全局」的测试须改为新约定，不保留兼容行为。

顺序：冻结上述接口 → 后端／安全／前端并行实施 → QA 集成原生／DNS／竞争回归，参考文档负责人同步两种语言 → 发布工程师执行限定检查及浏览器冒烟验证 → 父级审查规范与正确性。

## 8. 验收、检查与参考文档更新

- 限定行／身份不得泄露其他客户；嵌套客户编号缺失或伪造时由服务端覆盖。初始外部编辑／更新／移除及显式目标格式错误／为空／非标量／不存在均返回 404。不带目标进入全局模式；停用但存在的目标仍可见，禁用新增，允许仅保留式编辑及移除。
- 使用实际输出的原生新增／编辑／取消／保存／移除控件及 CSRF，验证 303 和 422 保留 T／B；搜索 GET 隐藏目标、排序和分页保持限定模式，包括无搜索结果和 frame 来源整页响应。覆盖主机名未变时 DNS 失败，以及移除失败保留原始主机名／编辑状态。
- Verifier 测试覆盖精确／混合大小写／末尾点成功；错误目标、无 CNAME、仅 A、CNAME 链、无关 owner／区域、冲突目标、损坏／超时／resolver／传输失败、有限重试／整体时限和资源清理。采用确定性的标准库 reply fixture／伪 resolver I/O。
- Activity 测试覆盖每次通过基础校验的保存、主机名未变／仅修改客户、Save 自身获取的数据库锁内无 DNS、加锁最终值不匹配、并发目标归属变化、原子失败及现有唯一性／外键／停用保留竞争。DNS 不可用时仍可移除。
- 运行受影响的 service／Activity／contract、主机名组件／链接、AdminTable 回归和 `spec/requests/admin/maintenance/platform/{customers,customer_hostnames,customers_hostnames_merge}_spec.rb` 及相关入口测试。重建 Tailwind，并在 375／768／1440px、EN／zh-CN 下进行浏览器冒烟验证；关闭 JavaScript 后主机名流程仍可用。本设计文档阶段未运行测试。
- 实施变更中更新 `doc/reference/{en,zh-CN}/{customer-hostnames,customers,page-shortcuts,tenancy-and-roles,system-map,access-grants}.md` 的**两种语言**：替换仅建议／编辑优先／清除目标的描述，补充限定范围、停用行为、表格上下文、API 及 DNS／并发门禁。检索其他参考页面中矛盾的 DNS 描述。现有界面无需新增目录条目。
