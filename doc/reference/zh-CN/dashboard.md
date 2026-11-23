---
title: "仪表板"
summary: "管理端首页按客户已启用的模块组装指标、模块卡片和侧栏。"
---

## 概要

管理端首页是 `GET /:customer_id/admin/dashboard`。它面向 admin 或 owner，不是平台所有者专页。`Admin::DashboardsController#show` 向 `Dashboard::Home` 要一份 `Result`：计数、模块卡片、设置步骤、最近页面、最近实体和快捷动作。页面周围的侧栏是另一套对象。`SidebarContributor.registry` 向五个贡献者要节点，每个贡献者自己决定当前用户能看见什么。

会员首页是另一个控制器 `Member::DashboardsController`，路径为 `/:customer_id/member`。它不用这份 Result。

## 流程

```text
GET /:cid/admin/dashboard
        |
        v
RouteAuthorization（admin 或 owner）
        |
        v
Admin::DashboardsController#show
        |
        v
Dashboard::Home.call(customer:)
        |
        +-- LandingStats.for(customer)
        +-- Dashboard::ModuleCards.call(customer:)
        |
        v
Result
  metrics | modules | setup_items | recent_pages | recent_entities | actions

侧栏（每个管理端布局）
        |
        v
SidebarContributor.registry
  EntitiesContributor
  PagesContributor
  ModulesContributor
  SettingsContributor
  MaintenanceContributor（平台叶子仅对 81721200 的 platform_owner?）
```

## 实现

`Dashboard::Home#call` 读取 `LandingStats` 与 `ModuleCards`，在一处组装结果。指标链接到业务域页面（`/:cid/admin/domains`）、页面列表、维护模块和认证用户。文案是 `admin_misc.dashboard` 下的 `I18n.t` 键，不是冻在结果上的字符串。

`Dashboard::ModuleCards` 认识七个功能模块。`SECTIONS` 把每个 key 放进 `:records`、`:communication` 或 `:growth`。`KNOWN` 用客户 id 的 lambda 保存主路径、次路径和设置路径。客户未启用的模块不会变成卡片。卡片的主链接是记录表面，设置路径是客户设置表面。这与 [系统地图](system-map) 里的划分一致。

快捷动作（`create_entity`、`new_page`、`enable_module`、`invite_user`）只在该客户确实有对应目的地时出现。邮件、支付和短信的次级快捷方式列在 `SECONDARY_ACTIONS` 中，对应模块卡片存在时才加入。

最近页面与最近实体是 `Dashboard::RecentItem` 值（`name`、`href`、`badge`、`updated_at`）。`updated_at` 取记录本身的时间戳；`Admin::Dashboard::RecentListComponent` 通过 `admin_misc.domains.directory.updated` 与 `chrome.admin_table.time_ago` 显示为相对时间行「…前更新」，值为 nil 时不显示该行。

### 布局

`Admin::Dashboard::WorkspaceComponent` 自上而下排布：

1. **页头**：`LandingHeaderComponent` 渲染带柔和强调光晕的 `rounded-2xl` 卡片横幅，在欢迎标题上方显示客户名称胶囊与日历日期，下方显示 `admin_misc.dashboard.subtitle`。块内容是页头操作：`WorkspaceComponent::HEADER_ACTION_KEYS`（`new_page`，其后 `create_entity` 为主按钮）从 `actions` 中取出，在此渲染。
2. **指标卡片**：每个指标一张 `rounded-2xl` 链接卡片（`data-dashboard-metric="<key>"`），通过 `WorkspaceComponent::METRIC_THEMES` 提供顶部渐变色条与语义图标底板，含标签、带千位分隔的数值（nil 显示为 0）、可选 `sub_label` 状态指示，页脚显示 `admin_misc.dashboard.stats.view`。手机两列，`xl` 起四列。
3. **主区网格**：`data-dashboard-region="recents"` 放两个 `RecentListComponent` 列表卡片（`md` 及 `xl` 起并排，`lg` 时上下堆叠），卡片头含语义图标与数量胶囊，列表行纵向均匀分布。`lg` 起其右侧为 `aside[data-dashboard-region="rail"]`，包含「快速上手」（仅在设置未完成时显示）与「快捷操作」（未提升到页头的动作，使用带 `ACTION_ICON_CLASSES` 语义配色的紧凑 `QuickActionCardComponent` 渲染，`md` 时两列）。侧栏为空时不渲染；`lg` 以下排在最近列表之后。
4. **已启用的模块**：分区图标、数量徽标、指向 `/:cid/admin/modules` 的「查看全部」链接，以及带启用状态圆点的 `ModuleCardComponent` 卡片（一至四列）。默认变体把主链接渲染为强调色胶囊（`data-module-link="primary"`），次级链接为描边胶囊（`data-module-link="secondary"`）；模块目录的 `:rich` 变体不变。

本页不挂载 Stimulus 控制器。

### 共用管理页页头

`AdminPageComponent` 提供共用的面包屑／标题／操作外壳。组件带有标题且视图尚未设置文档标题时，会把该标题写入 `content_for :title`（去掉标签），使浏览器标签与页面一致。没有标题的页面仍使用后台布局的回退标题「仪表盘」。可选 `wrap_actions: true` 使标题与操作在 `lg` 以下上下排列，`lg` 起允许横排及换行。操作区在手机上占满宽度、按钮上下排列，`sm` 起使用可换行的横排，`lg` 起操作容器改为自动宽度。默认值为 `wrap_actions: false`。实体条目浏览页启用 `wrap_title: true, wrap_actions: true`，主操作**创建条目**排在次操作**导出 CSV**之前，操作样式为 `min-h-11 w-full sm:w-auto`。创建入口及行内／抽屉中的**编辑**均以 `_top` 打开整页；新建与编辑表单使用默认全宽及 `wrap_title: true`，并带实体图标块，与后台页面表单（`/:cid/admin/pages/:page_id/form`）一致：单个 `card` 内置居中的 `max-w-4xl` 面板。结构及写入边界参见[实体构建器](entity-builder)。

`SidebarContributor.registry` 是手写数组，不是 `descendants`。顺序为实体、页面、模块、设置、维护。使用维护分区时，`MaintenanceContributor#contribute` 会添加客户资料、常量、模块、实体和页面。只有 `FlowchartVisibility.allowed?` 时才加流程图。只有 `customer_id` 为 `81721200` 且 `current_user.platform_owner?` 时才加平台分组。开发文档叶子在这个平台分组里。

`SettingsContributor` 在规范任务叶子上通过精确的 `match_paths` 匹配通用模块别名：`/modules/email` 与 `/modules/emails` 选中邮件限额，`/modules/sms` 选中短信限额，`/modules/ai_assistants` 选中 AI 助手，`/modules/authentications` 选中账户安全；以上路径均位于 `/:cid/admin/settings` 下。规范链接保持原目的地。精确别名不会覆盖更深的页面：模板变量、角色及其他具体设置仍通过各设置菜单共用的 `SidebarNodeComponent.selected_key` 匹配，只选中各自唯一的任务项。概览面包屑以无链接的「设置」标明当前页；子页面链接回设置概览，页面保留一个设置外壳及一个一级标题。

`SettingsContributor#decorate` 将这些别名追加至贡献节点原有的 `match_paths`，保留权限键、规范路径及既有导航匹配。`#module_description(fm)` 在调用时解析 `admin_settings.catalog.modules.<key>`，并以已本地化的 `admin_settings.catalog.modules.fallback`、`name: fm.display_name` 作为默认值；未来模块无需专用翻译，也能获得清晰的本地化说明。`spec/services/settings_contributor_spec.rb` 覆盖回退说明、未来模块贡献／权限筛选及唯一选中叶子矩阵；下文配套导航浏览器验证契约继续保留。

共用设置请求 spec 将桌面完整侧栏、移动抽屉及设置对话框作为三个**完整任务菜单**检查。收起后的图标轨也以“设置”为无障碍名称，但分组按钮用于展开分区，不逐一复制叶子链接。辅助方法仅排除图标轨的稳定 `[data-sidebar-collapsible-target="rail"]` 容器，并另行检查其短信分区控件及选中样式。完整菜单的目的地、深层链接、别名、未来模块及授权断言继续保留。

### 客户设置浏览器验证

`spec/e2e/customer_settings_support.js` 将外壳检查限定在 `#main-content`，设置页一级标题取 `[data-settings-page]` 之外的标题。网站预览卡片可能包含自己的标题和嵌套 `main`，不属于设置页页眉。文档／主区域横向溢出及可见控件边界仍须检查，包括展开折叠区之后。导航清单保留真实 GET 参数，例如账单 `plan_code` 和排序方向；仅 `locale` 由中英文测试矩阵替换。页面访问等待 DOM 和字体就绪，交互测试等待实际挂载的 Stimulus 控制器。原生设置菜单验证模态状态、背景焦点隔离、Escape／焦点归还及目标页面跳转完成。

独立测试库导出器 `spec/system/admin/settings/customer_settings_browser_fixtures_spec.rb` 使用正常工厂、校验及开通器，渲染同租户管理员获准访问的响应。共生成 24 个 JSON 文件：`role-edit`、`role-grants`、`token-edit`、`website-footer`、`invoice-list`、`invoice-detail`、`invoice-download`、`payment-providers`、`payment-sandbox`、`payment-production`、`public-protection` 和 `user-access`，每项均有 `en`、`zh-CN` 两份。准备专用 `storage/e2e*.sqlite3` 测试库后，通过 `node spec/e2e/helpers/bootstrap.js export` 导出；先取消继承的浏览器专用 `RUBYOPT` 预加载。浏览器辅助函数校验来源及语言，以 `text/html; charset=utf-8` 提供响应，并确认 `document.characterSet` 为 UTF-8。导出租户编号仅解析到已注册的导出响应；所有浏览器写请求均在 context 层拦截。

场景遵循实际设置约定：保留角色 member 的权限始终锁定，名称／动作／已授权筛选可用；AI 语言和账户安全须显式保存；邮件／短信限额由平台管理；新增个性化字段使用 `email-template-token-bulk` 及翻译后的数量模板。支付夹具先将 Stripe 设为平台可用，再为租户开通两种环境，验证开关失败回滚、已保存连接反馈、凭据保存及环境切换。公开页面防护夹具使用正常校验的租户自有公开 Page。用户权限的拦截载荷始终只选三个保留角色中的一个。参见[访问授权](access-grants)、[支付](payments)、[验证码](captcha)及[邮件](email)。

2026-10-12，导出器通过 **14 个示例，0 个失败**；三个客户设置浏览器 spec 使用四个工作进程，通过 **64 个用例，0 个失败，0 个跳过**，涵盖此前失败的 36 个设置变体。证据见 `docs/audits/2026-10-12-settings-browser-followup.md` 和 `/tmp/opencode/settings-followup.json`。同日后续并行 RSpec 通过 **25,266 个示例，0 个失败**；该结果不替代上述浏览器证据。`SETTINGS_BROWSER_ARTIFACTS` 可指定新的截图／清单目录，不改变导出目录。

共用顶部菜单（`MenuRegistry`、`MenuBarComponent` 与移动端 `DrawerComponent`）在 AI 助手之后依次显示**用户**、**支付**和**通信**折叠菜单。用户链接至 `/:cid/admin/modules/authentication/users`，支付链接至 `/:cid/admin/modules/payments/transactions`；通信下的邮件链接至 `/:cid/admin/modules/emails/send_activities`，短信链接至 `/:cid/admin/modules/sms/campaigns`。这些都是既有管理路由的快捷入口，不增加路由或侧栏分区。注册表按管理员或平台所有者身份及**网址所指客户**的可用模块筛选：认证对应用户、支付对应支付，邮件或短信对应通信子项。未启用的子项不显示；两者均不可用时隐藏通信。进入对应模块页面后，顶部菜单高亮快捷入口而非模块；模块侧栏仍使用原有分组。除「模块」「通信」「实体」「设置」「维护」默认展开外，其余顶部菜单项的左侧栏默认收起为图标轨。展开或收起的选择按顶部菜单项分别记在本次浏览器会话中。桌面折叠菜单复用定位控制器，避免被可横向滚动的顶部菜单裁切；移动端抽屉显示相同的获准链接。

`spec/e2e/top_navigation.app.spec.js` 检查中英文的 768／1440px 桌面菜单及 390px 移动抽屉。测试先等待首次 importmap 加载、实际 `menu-placement` 控制器和字体就绪，再核对固定定位、视口及触发器边界，随后点击「通信 → 邮件」。点击必须产生已完成、状态为 200 的同源 GET 请求，进入真实目标 URL，完成 Turbo 加载及预览渲染，并选中对应菜单项。每条流程的 90 秒预算涵盖共用服务器启动加载；布局和选中链接断言仍为必检项。配套阅读器检查见[客户使用文档](customer-documentation)。

顶部的**内容**折叠菜单包含**表单**（`/:cid/admin/pages`），以及仅在网址所指客户已启用网站模块时显示的**网站页面**（`/:cid/admin/modules/website`）。表单列表标题为「全部表单」，记录列称为「表单」；侧栏、搜索和空状态也采用表单用语。网站列表与编辑器仍在模块命名空间下；进入这些路径时，桌面菜单和移动端抽屉选中「内容 → 网站页面」，模块侧栏继续提供记录导航。表单侧栏只列出表单记录。「内容」内部菜单 key 仍为 `:pages`。桌面菜单和移动端抽屉显示本地化的「内容」。收起左侧栏后，图标轨的无障碍名称仍是「内容」；每个目的地保留图标，名称在提示中显示，分组图标会展开完整侧栏并打开该分组。

表单与实体侧栏采用与模块、设置相同的可搜索布局（`SidebarComponent::SEARCHABLE_MENU_ITEMS`、`SidebarNodeComponent::SOFT_MENU_ITEMS`）。「搜索表单…」／「搜索实体…」输入框通过 `list-filter` 控制器在前端筛选；子实体匹配时，父实体保持可见，其分组在搜索期间展开；无结果时显示对应菜单的 `chrome.sidebar.search_empty_titles.*` 提示。与设置、模块不同，这两个侧栏在 `md` 断点即显示。`PagesContributor` 先列出跨实体视图：「全部表单」，以及存在未归属表单时显示的「未分类」（使用独立的收件箱图标）；其后在「按实体」标题（`section_root` 类型的 `SidebarNode`，图标栏中显示为分隔线）下列出各实体。`EntitiesContributor` 不设概览链接，只在「业务领域」标题下列出业务域：每个业务域一个按其颜色着色、链接到 `/:cid/admin/domains/:key` 的节点，其下为所属实体，未分组的归入「其他」；客户没有业务域时，实体在「记录类型」标题下平铺。带子项的分组在其自身或某个子项为选中行时展开（`SidebarNodeComponent#open?`），因此只展开当前显示的业务域（在 `/:cid/admin/domains` 上为第一个）。子行只有带 `tone` 时才显示小图标块，因此设置与模块的子菜单仍为纯文字；`SidebarTone` 解析 `domain.<color>` 与 `entity.<color>`，其他取值回退到 `module_color_classes`。没有图标的图标块显示节点的 `monogram`。该菜单显示为「业务域」。数字徽标显示为行尾的低调计数，为 0 时淡化，选中行显示强调色；文字徽标仍为胶囊样式。记录名称单行截断，完整名称见 `title` 提示。可搜索菜单的图标栏额外提供搜索按钮（`sidebar-collapsible#expandSearch`），点击后展开完整侧栏并聚焦搜索框。

收起／展开：`sidebar-collapsible` 控制器只切换外层容器的 `data-state`（`expanded`／`collapsed`），宽度在图标栏（4.25rem）与侧栏断点宽度（`SidebarComponent.expanded_shell_classes`）之间以 200ms 过渡，两个面板交叉淡入淡出（遵循 `prefers-reduced-motion`）；隐藏的面板设为 `inert`。触发方式：标题栏按钮以及 ⌘B／Ctrl+B（焦点在输入框、文本域或富文本编辑区时不拦截）。按钮使用双箭头图标（`SidebarToggleIconComponent`），方向即侧栏移动方向：展开时显示「«」用于收起，图标栏中显示「»」用于展开。侧栏边框不可点击或拖动，避免误触收起。按钮提示显示快捷键（`chrome.sidebar.shortcut`）。焦点所在面板被隐藏时，焦点移至新面板的切换按钮。状态按顶部菜单项保存在会话 Cookie `sidebar_state_<菜单键>` 中，服务端据此直接渲染，整页刷新不会闪烁；连接时控制器会重读 Cookie，以同步 Turbo 缓存快照。移动端抽屉中的表单与实体菜单也使用同一个可搜索的 `SidebarComponent`。

仪表板顶栏左侧只保留无底板、无边框的标志链接，不显示品牌名称或客户名称；大屏居中显示搜索，中小屏使用紧凑操作区。桌面菜单（`nav[data-menu-bar]`）是顶栏下方的白色标签栏：每个入口由图标加文字组成，悬停时显示浅色底；当前入口文字加深，图标与下划线使用强调色。分组入口（通信、内容）展开自动定位的面板，每个子项显示图标、名称及一行说明，说明文案取自 `chrome.menu_bar.descriptions`（通过 `MenuItem#description_key` 指定）。主要入口放不下时可横向滚动，`xl` 以下右侧以渐隐提示还有更多入口。设置和仅所有者可见的维护入口以分隔线隔开，始终固定在右侧（`[data-menu-bar-utility]`）；`xl` 以下只显示图标，名称保留为悬停提示和读屏文本。手机端抽屉复用获准的菜单项，提供图标分组、展开列表和各分区首页链接。文案来自中英文 `chrome` 翻译。

`Branding::SapphireLogoComponent` 保留蓝宝石标志原有的切面路径和每次渲染独立的渐变 ID，配色改为与平台网站主按钮一致的紫色系（`#7f22fe`）。顶栏和移动端抽屉只显示无边框的标志；顶栏链接仍保留本地化的仪表板可访问名称。公共页面及登录页面共用同一标志，可访问名称取自 `chrome.topbar.brand_name` 翻译。`/icon.svg` 与 `/icon.png` 提供配套的紫色浏览器图标和触控图标。客户 `81721200` 的平台营销站页头和页脚使用同一标志；因站点名称已作为可见文字出现，该标志对无障碍树隐藏。

`MenuRegistry` 仅在 `current_user.platform_owner?` 为真时，才在桌面菜单和移动端抽屉显示**维护**；平台所有者查看其他客户的仪表板时也会显示。普通客户管理员（包括客户 `81721200` 的管理员）均看不到此入口。这只调整导航可见性；租户维护 URL 及其现有授权规则不变，详见[租户与角色](tenancy-and-roles)。

顶栏的 `HelpMenuComponent` 在用户为 admin 或 owner 且存在客户 id 时显示**文档**。入口通过 `admin_help_docs_path(customer_id)`（`/:cid/admin/help/docs`）在应用内打开，客户指南文案取自 `chrome.help_menu.docs` 翻译。客户阅读器使用仪表板外壳、集中式角色与租户授权，并将 HTML 响应设为 `private, no-store`。帮助入口提供操作指南；开发文档叶子仍在仅所有者可见的平台分组中。参阅[客户使用文档](customer-documentation)及[支持工单](support-tickets)。

## 需要特别注意

`spec/system/search_palette_spec.rb` 将交互限定在响应式布局中当前可见的 `inline-search` 实例。打开时正向等待展开面板内的可见输入框；Capybara 在限定时间内同步重试，且仅在该实例触发按钮仍可见时再次点击。仅断言隐藏面板不存在并不足够，因为 Capybara 默认排除隐藏元素。真实浏览器测试仍验证实时结果跳转及 Escape 收起，不使用固定等待，也不因浏览器缺失而跳过。

### 路由审计：导航与表单操作

`EntityAssociationGraph` 保留循环关系，并为不可达组件增加根；`EntitiesContributor` 遇到已访问祖先停止递归。旧循环不会耗尽栈或隐藏整个组件。访问仍由控制器租户／模块门禁决定，不依赖菜单可见性。

`PATCH /:cid/admin/pages/batch` 仅允许 activate／deactivate／launch／take_offline，校验 ID 形状，选取去重后的自有匹配行，在事务内调用带校验的生命周期。重新激活包含 inactive 行，并重新校验原已上线表单。任一失败整批回滚；JSON 为 422，HTML 为警示，成功统计实际唯一匹配数，不批量修改共享全局行。

`uncategorized.html` 正确选择未分类分支。全部表单列表选择及侧栏数量均使用 `Admin::Pages::BrowseScope.call(customer_id:, entity_id: nil, uncategorized: false)`，共用生效客户覆盖绑定及失效／桥接／无头分类；其他租户独立保留全局回退。见[实体构建器](entity-builder)、[页面渲染](page-rendering)、[共享资源](shared-resources)。

:::note
图／侧栏、生效列表／数量及批量 API 已按源码记载。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**；配置好的 Vitest 覆盖率运行通过 **6,956 个测试**，行与分支覆盖率均为 100%。本阅读器的移动端与语言渲染检查仍须单独的浏览器运行。
:::

:::attention
`SidebarContributor.registry` 是手写的。新的贡献者如果没有追加进这个数组，类存在也不会运行。仅平台可见的叶子必须放在 `MaintenanceContributor` 的 `platform_owner?` 分支里，不要放进每个租户管理员都会收到的贡献者。
:::

:::attention
`Dashboard::ModuleCards::KNOWN` 里的路径才是真正的入口 URL。只加了模块注册、没有 `KNOWN` 条目时，模块可以启用，首页却没有卡片。路径 lambda 必须留在四个模块表面上，不要指向 `/admin/maintenance/platform`。
:::

:::attention
首页指标和卡片文案在调用时经 `I18n.t` 翻译。不要把已经翻译好的字符串放进常量。`METRIC_ICONS` 与 `ACTION_ICONS` 是 SVG 路径，不是面向用户的文案。
:::

## 关键代码

```ruby
# app/controllers/admin/dashboards_controller.rb
def show
  @home = ::Dashboard::Home.call(customer: current_customer)
end
```

```ruby
# app/services/dashboard/home.rb
def call
  stats = LandingStats.for(@customer).to_h
  modules = ModuleCards.call(customer: @customer)
  Result.new(
    metrics: metrics(stats),
    modules: modules,
    setup_items: setup_items(stats),
    recent_pages: recent_pages,
    recent_entities: recent_entities,
    actions: actions(modules)
  )
end
```

```ruby
# app/services/sidebar_contributor.rb
def self.registry
  [
    EntitiesContributor,
    PagesContributor,
    ModulesContributor,
    SettingsContributor,
    MaintenanceContributor
  ]
end
```
