---
title: "客户使用文档"
summary: "双语客户任务指南，提供直观的任务导航、保留阅读上下文的搜索、响应式阅读器及安全截图。"
---

## 概要

**帮助 → 文档**打开站内客户指南，路径为 `/:cid/admin/help/docs`，面向已登录的客户管理员及平台所有者。指南说明日常操作：熟悉工作区、管理用户与记录、使用表单与网站、操作模块、调整客户设置、查看账单，以及获取支持。

客户正文位于 `doc/customer/<locale>/<slug>.md`，使用独立的 `CustomerDocs::Catalog`。开发文档仍位于 `doc/reference/<locale>/<slug>.md`，站内入口为仅平台所有者可访问的 `/81721200/admin/maintenance/platform/developer_docs`。两类文档复用渲染基础设施，各自配置目录、内容根目录、翻译作用域和路由 helper。参阅[开发文档](overview)、[支持工单](support-tickets)、[国际化](internationalization)及[租户与角色](tenancy-and-roles)。

## 流程

```text
管理端帮助菜单 -> 文档
  GET /:cid/admin/help/docs 或 /:cid/admin/help/docs/:slug
        |
        v
ApplicationController
  TenantContext：网址所指客户；拒绝非所有者跨租户访问
  RouteAuthorization：登录、admin-or-owner 角色、CanCan 路由检查
        |
        v
Admin::Help::DocsController
  index -> overview；show -> params[:slug]
  Cache-Control: private, no-store
        |
        v
CustomerDocs::Repository < DeveloperDocs::Repository
  CustomerDocs::Catalog -> doc/customer/<locale>/<slug>.md
  page + guide_groups（仅首页；元数据不受 q 影响）
  Page.current_group：未筛选上下文；Page.groups：真实目录结果
  previous_page / next_page：Link(slug, title, path)，按目录顺序
        |
        v
DeveloperDocs::Renderer（catalog: CustomerDocs::Catalog）
  screenshot_root: /help/docs/screenshots
  Kramdown GFM -> 提示块、锚点、链接、截图图注 -> Loofah
        |
        v
DeveloperDocs::ReaderComponent
  header 插槽：中央阅读栏内的 AdminPageComponent
  translation_scope: customer_docs; locale: current_locale
  article_variant: customer; home_groups: 概览传入分组，其他页为 nil
  CustomerDocs::HomeGuidesComponent -> 分组面板内的 12 条指南链接，再展示正文
```

未知或缺少正文的 slug 渲染本地化的缺失页面，状态码为 404。文章和缺失页面的响应均设置 `Cache-Control: private, no-store`。

## 实现

### 路由与访问权限

`config/routes.rb` 在 `admin/help` 下声明只读的 `index` 与 `show` 路由，使用 `param: :slug`，并将 slug 限制为小写 kebab-case。`admin_help_docs_path(customer_id)` 打开概览；`admin_help_doc_path(customer_id, slug)` 打开文章。

`Admin::Help::DocsController` 从 `ApplicationController` 继承集中式 `TenantContext` 与 `RouteAuthorization` 守卫。匿名访问者须登录；会员不能读取这些管理端 URL；客户管理员只能在本客户内阅读。平台所有者可在其他客户的网址上下文中打开指南。控制器将 `current_customer_id` 传给仓库，不重复添加登录或角色过滤器。

`HelpMenuComponent#show_docs?` 要求 `user.admin_or_owner?` 且存在客户 id。`docs_url` 调用 `admin_help_docs_path(customer_id, locale: I18n.locale)`，菜单链接按当前生效语言在应用内跳转。入口可见性配合控制器层守卫生效。开发文档保留原有的平台所有者权限及平台导航入口。

### 客户目录与正文约定

目录包含 13 个操作指南 slug，每个均提供 `en` 与 `zh-CN` 正文：

| 分组 key（对应顶栏菜单） | Slug |
| --- | --- |
| `home` | `overview`, `getting-started` |
| `assistant` | `assistant` |
| `users` | `users` |
| `payments` | `payments` |
| `communication` | `email`, `sms` |
| `entities` | `records` |
| `content` | `forms`, `websites` |
| `settings` | `settings`, `billing`, `support` |

分组名称与 `chrome.menu_bar.items` 一致（首页、AI 助手、用户、支付、通信、实体、内容、设置）。目录顺序与顶栏从左到右一致。客户指南没有**模块**分组（各模块指南挂在对应菜单下），也没有**维护**分组（所有者专用构建器不进入本目录）。

每篇指南的 YAML 文首包含以目标为导向的 `title` 与简洁的结果摘要 `summary`。`AdminPageComponent` 用其显示完整页眉；首页条目、同组页尾链接和页尾顺序导航也保留完整标题。客户目录、文章面包屑、移动端位置栏和搜索上下文使用简短的 I18n 任务名称；简短导航链接以完整标题作为无障碍说明。正文不要添加一级标题。`CustomerDocs::Catalog::REQUIRED_HEADINGS` 规定以下二级标题，各出现一次并保持此顺序：

| 英文 | 简体中文 |
| --- | --- |
| Before you start | 开始前 |
| Steps | 操作步骤 |
| What to expect | 预期结果 |
| Troubleshooting | 常见问题 |
| Related guides | 相关指南 |

两种语言的章节、示例与提示块保持一致。指南说明客户可见的操作及前置条件，包括模块是否可用。平台实现细节与所有者专用工具放在开发文档中。客户新页面注册到 `CustomerDocs::Catalog`，而非 `DeveloperDocs::Catalog`；本实现参考页则注册在开发目录的 `operations` 分组。

### 首页元数据约定

`CustomerDocs::Repository#guide_groups` 按目录顺序返回 `Array<DeveloperDocs::Repository::Group>`。完整首页导航独立于文章上下文和筛选后的目录元数据：

- Group：`key: String`、`entries: Array<CustomerDocs::Repository::Guide>`。
- 不可变 Guide：`slug: String`、`title: String`、`summary: String`、`path: String`。
- 元数据使用与文章读取相同的白名单源文件及本地化文首，保留英文回退。排除 `Catalog::HOME_SLUG`，省略缺失源文件和空分组。完整发布包含八个分组、12 条指南链接；`home` 仅提供 `getting-started`。
- `q` 只筛选目录。搜索无匹配时，分组导航仍展示完整指南集合。
- `path` 使用仓库现有路由解析器，传入 URL 所指客户及生效语言：`admin_help_doc_path(C, slug, locale: L)`，例如 `/81721200/admin/help/docs/forms?locale=en`。不能携带 `q`、使用作者账户所属客户，或接受文首中的任意跳转地址。
- 元数据在文章渲染缓存外组装。新请求直接读取已保存的标题／摘要变更，无需等待文章片段缓存失效。

`Admin::Help::DocsController` 每次请求复用一个仓库实例读取文章和分组。概览入口及显式 `/docs/overview` 均传入首页分组；其他指南传入 `nil`。分组面板提供完整指南导航，概览 Markdown 仅保留简洁的导览与恢复说明，不再重复 12 篇指南列表。

### 文章上下文与导航元数据

两类仓库使用共用的请求级数据约定：

- `Page` 包含 `slug`、`title`、`summary`、`html`、`headings`、`groups`、`current_group`、`previous_page`、`next_page`、`query` 和 `search_path`。
- `Group(key, entries)` 按目录顺序包含 `Entry(slug, title, path, active)` 元数据。`Page.current_group: Group | nil` 是当前 slug 所属的完整未筛选分组，其中恰有一个当前条目。缺失源文件被省略；没有当前分组时，不显示分组面包屑及同组页尾链接。
- `Page.groups` 只包含规范化查询的真实匹配结果。不能把当前指南、同组指南或虚构的上下文分组补进结果。当前指南实际匹配时仍保留在结果中，但渲染后的结果列表不使用当前项样式或当前页语义。
- `previous_page` 和 `next_page` 为 `Link(slug, title, path) | nil`，按已发布目录顺序排列，跳过不可用源文件。slug 用于名称查找，无需解析 URL。页尾顺序导航使用这些链接，不受查询影响。
- 每次 `page` 调用只组装一次未筛选分组，选出当前所属分组，再按本地化标题、摘要和正文筛选同一批条目。复用请求级源文件元数据，仅渲染当前文章；不向组件传入第二份完整目录或复制的文章正文。独立的首页 `guide_groups` 和开发文档 `hub_groups` 始终完整。
- 目录、当前分组和顺序导航地址移除 symbol 与 string 两种 `q` 路由选项，保留既有选项，尤其是 URL 客户及客户文档的生效语言。`page.search_path` 是控制器提供的无查询条件的当前概览／文章 URL。上下文及顺序导航元数据不进入渲染片段缓存，无需调整渲染器缓存版本。

### 共用阅读器配置

`DeveloperDocs::Repository` 接受 `catalog:`、`content_root:`、`translation_scope:`、`route_helper:`、可选 `route_options: {}`，以及显式启用截图的 `screenshot_root: nil` 和可选 `screenshot_labels: nil`。默认值保持开发文档行为：`DeveloperDocs::Catalog`、`doc/reference`、`"developer_docs"`、`:admin_maintenance_platform_developer_doc_path`，不添加语言查询参数，并移除图片。`CustomerDocs::Repository` 传入 `CustomerDocs::Catalog`、`doc/customer`、`"customer_docs"`、`:admin_help_doc_path` 和 `screenshot_root: "/help/docs/screenshots"`，另在渲染时提供本地化截图文案。客户控制器传入 `locale: current_locale` 与 `route_options: { locale: current_locale }`；仓库将路由选项作为关键字参数用于目录、相关指南和上一篇／下一篇链接，包括锚点。

仓库先按注入目录验证 slug，再读取文件；检查路径仍在配置的根目录内，用 `YAML.safe_load` 解析文首，并选择请求指定的受支持语言。不支持的语言使用英文；缺少对应语言正文时回退到英文正文。提示块与锚点文案使用仓库选定的语言及翻译作用域，正文回退到英文时也如此。

`DeveloperDocs::Renderer.call` 接受 `catalog:`，默认是 `DeveloperDocs::Catalog`。站内裸 slug 链接按该目录验证，再通过仓库的路由 helper 改写。开发文档专用 slug 不会变为客户文章链接。Kramdown、Rouge、提示块、锚点与 Loofah 清洗流程均复用现有实现。

`DeveloperDocs::ReaderComponent` 接受 `page:`、`translation_scope:`（默认 `"developer_docs"`）、`locale: nil`、`article_variant: :reference`、`home_groups: nil` 和 `home_path: nil`。客户视图传入 `translation_scope: "customer_docs"`、`locale: current_locale`、`article_variant: :customer`，并以帮助文档首页作为 `home_path`。开发文档概览现在也会传入 `DeveloperDocs::Repository#hub_groups` 得到的 `home_groups`，以及平台文档首页作为 `home_path`。

阅读器提供可选的 `header` 插槽（`renders_one :header`）。两类 show 视图均在插槽中传入 `AdminPageComponent`，保留现有面包屑、文首标题／摘要、`wrap_title: true` 和 `width: "full"`。面包屑、唯一的页面一级标题、摘要、分组导航、正文及后续导航共用中央栏的左边界和阅读宽度。面包屑提供分组上下文，不再在标题旁重复显示分组徽标；不传页眉的调用仍有效。

`home_groups: nil` 省略首页区域；`[]` 在中性面板内显示本地化的指南暂不可用提示，并保留概览正文。`CustomerDocs::HomeGuidesComponent` 必须接收 `groups:`，并接受可选的 `translation_scope:`（默认 `"customer_docs"`）。它渲染本地化导航标题／导语，每个目录分组使用一个圆角 `CardComponent`：分隔线上方为分组标题及说明，下方为以细分隔线区分的原生指南链接行。每行保留标题／摘要 ID、以标题为无障碍名称、以完整摘要（不截断）为说明的关联、同标签页跳转、装饰箭头、可见焦点和自然换行。卡片带浅阴影，悬停时加深，被片段定位时显示描边，顶部对齐、高度随内容自然伸展。各面板提供稳定的 `customer-doc-guide-group-<key>` 或 `developer-doc-guide-group-<key>` ID 及标题滚动偏移。分组面包屑和固定上下文把该片段附加到视图传入的 `home_path`，语言查询参数位于片段之前，例如 `/81721200/admin/help/docs?locale=zh-CN#customer-doc-guide-group-content`。嵌套的 `@container/hub` 按导航宽度切换网格，间距 16px：默认单列，达到 576px 为双列，达到 832px 为三列。组件不查询数据库／模块状态，也不构造路由。

共用阅读器在现有外壳留白内最多宽 1200px（`@container/docs`）；文章中央栏最多宽 704px，首页导航最多宽 960px（概览正文仍为 704px）。W 指扣除应用侧栏和外壳留白后的阅读器容器实际宽度。视口高度 H ≥640px 时，W 低于 832px 使用单列、带目录按钮及「分组／页面」位置的吸顶栏和目录抽屉；达到 832px 后显示 240px 目录栏，间距 40px；达到 1056px 后，有标题的文章再显示 192px 本页标题栏，额外间距同为 40px。宽度模式使用命名容器查询。H <640px 时，无论 W 多宽，均使用单列、吸顶栏、目录抽屉及文章内嵌本页目录；配套高度条件覆盖网格、两侧栏、吸顶栏、抽屉、遮罩及本页目录可见性。高度充足时保留原有容器模式。侧栏在可滚动主区域顶部下方 24px 吸附。首页及无标题文章不预留右栏。分组面板位于 Markdown 容器外、概览正文之前；`page.headings` 仍只描述正文标题。有标题的文章恰好显示一份本页目录：右栏不可用时使用内嵌原生 `details`，否则使用右栏；首页均不显示。两处本页目录均以 `aria-current="location"` 标记正在阅读的小节（见下文 `docs-reader` 控制器），右栏末尾提供**返回顶部**。

两类文档使用应用字级和 `font-sans`（与 `body` 同一字体族）。字号不随阅读器宽度变化。以下字号和行高均以像素计：

| 元素 | 字号／行高 |
| --- | --- |
| 页面一级标题（`text-subtitle`） | 20 / 27.5 |
| 摘要、分组导语、指南摘要（`text-body-sm`） | 13 / 19.5 |
| 正文、列表、表格、提示正文（`text-base`） | 14 / 21 |
| Markdown 二级标题（`text-2xl`，行高 1.25） | 20 / 25 |
| Markdown 三级标题及分组导航二级标题（`text-xl`，行高 1.375） | 18 / 24.75 |
| 首页分组标题（`text-md`，行高 1.375） | 15 / 20.625 |
| 首页指南标题（`text-base`，中等字重） | 14 / 19.25 |
| 目录、本页内容、顺序导航标题、面包屑（`text-sm`） | 13 / 19.5 |
| 目录分组名称（`text-xs`，半粗） | 11 / 14.67 |
| 代码块（`text-sm`，行高 1.625，`font-mono`） | 13 / 21.125 |

搜索框使用 `input-field`（14px）：桌面目录栏高 40px，抽屉内高 44px。抽屉链接的操作区域至少高 44px。`docs-reader` 为正文代码块加上**复制**按钮；表格与行内代码使用 `bg-surface` 及浅边框。提示标签使用 `text-sm`，保持正常大小写。阅读器工具类将这些字号锁定在全局段落默认值和渲染器类之上。行内代码保持应用的 `0.9em` 与 `font-mono`。`.docs-page`、`.customer-doc` 和 `.developer-doc` 仅保留为语义／测试标记；`app/assets/tailwind/application.css` 内的文档专用 CSS 改由组件工具类替代。标题 ID／固定链接、列表标记、文章链接和语法高亮保持可用。客户和开发文档的表格均使用 `block max-w-full overflow-x-auto`；代码块局部滚动，不拆分长词。`min-w-0` 和长词换行限制正文／导航宽度，面包屑可局部滚动。截图保留原始比例，图注／原图链接自然换行。

目录采用高度受限的 flex 列布局，控件区固定，列表独立滚动。桌面面板占满主滚动区：`docs-reader` 将主区域 `clientHeight` 写入 `--docs-pane-height`，目录栏高 `calc(var(--docs-pane-height) - 3rem)`（回退值 `100dvh - 10rem`）；控件区使用 `shrink-0`，只有 `min-h-0 flex-1 overflow-y-auto overscroll-contain` 列表滚动。抽屉使用 `h-dvh`，首选宽度为 320px、上限为 85vw，提供 16px 内边距及安全区留白。文档集标题（传入 `home_path` 时为首页链接）、关闭按钮和搜索固定在列表上方。桌面页头以同一文档集首页链接（书本图标 + `breadcrumb.reference`）开头。两处页头都不显示“目录”标题。桌面目录栏的提交控件是字段内左侧的图标按钮，无障碍名称为**搜索**；搜索框为空时显示 `/` 快捷键提示。抽屉保留可见文字提交按钮，与搜索框上下排列；视口高度低于 640px 时该按钮与搜索框并排。其后是条件显示的**清除搜索**、条件显示的**当前阅读**，最后是细分隔线。输入框及提交按钮至少高 44px；清除链接桌面至少高 32px、抽屉至少高 44px。清除链接依据已应用的规范化查询显示，不随未提交的输入变化。

H <640px 时，抽屉缩小间距，将搜索框与仍可见的文字搜索按钮并排；首页与清除链接同时存在时也并排显示。DOM／表单顺序及 44px 控件保持不变；当前阅读固定在列表上方，列表至少预留 64px 高度。H ≥640px 时恢复常规整行堆叠控件及既有宽度容器模式。这是 Tailwind 高度回退，不增加客户端搜索状态。

`DeveloperDocs::ContentsNavComponent` 接受 `page:`、`translation_scope:`、`navigate: false` 和 `surface: :desktop`（抽屉使用 `:mobile`）。两类文档的每个分组均渲染为 `<section aria-labelledby>`，包含 `h3` 名称及左侧细线上的缩进 `ul/li/a` 列表，所有已发布条目无需展开操作即可访问；搜索时仅保留有匹配项的分组。常规当前链接使用强调样式、`aria-current="page"` 及 `data-docs-current-guide`。分组名称是浅色小标题。当前页面为带短标记的强调色胶囊，与应用侧栏一致。本页标题共用一条引导线，下级标题缩进并使用三级文字色。存在查询时，固定的**当前阅读**区域拥有各目录区域中唯一的当前链接；独立的**搜索结果**列表只使用 `page.groups`，不带当前项样式、语义或标记。客户结果显示简短任务名称；与完整标题不同时，同时显示完整标题。无结果时使用中性描边提示，并提供可见的、不含搜索条件的清除链接。完整首页导航、当前文章和上下文仍可使用。

`ReaderComponent#current_group` 直接使用 `page.current_group`；文章分组面包屑及 `section_entries` 均读取该未筛选分组。客户文章面包屑保留帮助上下文、**全部指南**、带链接的分组及纯文本的简短当前名称。开发文档保留维护／开发文档上下文及完整标题。搜索时，当前阅读将分组链接到首页对应面板，将当前指南链接到仓库生成的不含查询条件的路径；点击指南会在同一文章清除搜索。分组不可用时，以当前 slug／标题及 `page.search_path` 提供恢复入口。无查询时省略固定上下文，由常规目录条目承载当前页语义。桌面与移动端在 DOM 中各可有一个当前链接；唯一性按可见目录区域检查，关闭的抽屉保持 inert／隐藏。

上一篇／下一篇只出现一次，位于正文及**本节其他指南**之后的**阅读顺序**页尾导航（`data-docs-footer-sequence`）；文章上方不再有顺序导航。每个目标是带边框的卡片，完整标题上方标注上一篇／下一篇；下一篇靠末尾侧，缺少上一篇时仍占第二列。首页和文章均指向不含查询条件的目录相邻页面。缺失端点不渲染禁用链接或占位元素。中央栏低于 480px 时卡片纵向排列（`@container/hub`）。**本节其他指南**位于细顶部分隔线之后，以完整标题卡片列出 `page.current_group.entries.reject(&:active)`（640px 起双列），搜索期间也保留；仅没有其他条目时省略。

`docs-reader`（`app/javascript/controllers/docs_reader_controller.js`）与 `developer-docs-nav` 一同挂载在 `.docs-page` 上。它依据最近的 `main` 设置 `--docs-pane-height`；对本页目录链接（`tocLink` target）执行滚动高亮，将阅读线（距顶部 120px）以上最后一个标题（滚动到底时为最后一个标题）标为 `aria-current="location"`；在可编辑字段之外按下不带修饰键的 `/` 时，聚焦并选中第一个可见的 `search` target；并用 `copyTemplate` 克隆包裹 `prose` target 中的每个 `pre`。复制使用 `navigator.clipboard.writeText`，非安全来源回退到隐藏 textarea 加 `execCommand("copy")`，将 `aria-live` 文案切换为 `copied_code`，2 秒后恢复。文案通过 `data-docs-reader-copy-label-value`／`copied-label-value` 传入。没有 `main` 祖先时，仅启用快捷键和复制按钮。

标记约定为 `data-docs-nav-header`、`data-docs-nav-list`，以及各目录区域中的一个 `data-docs-current-guide` 链接。抽屉列表另带 `data-developer-docs-nav-target="drawerList"`。简短导航链接以可见名称作为无障碍名称，通过完整标题 `aria-describedby` 补充说明：目录使用 `<audience>-doc-nav-<surface>-<slug>-title`，固定上下文使用 `<audience>-doc-context-<surface>-<slug>-title`（`audience` 为 `customer` 或 `developer`）。说明 ID 在不同区域间保持唯一。完整标题仍显示在一级标题、完整首页导航、客户搜索结果、同组页尾及页尾顺序导航中，不依赖悬浮提示。

初始桌面布局及阅读器进入桌面模式时，`developer-docs-nav` 仅滚动桌面目录列表，使常规当前指南行可见。因此，位于目录末尾的当前指南也能立即显示。此显示操作保留当前焦点及窗口／主区域／文章滚动位置；抽屉的当前项显示则在打开抽屉时执行，两者时机不同。搜索期间，当前上下文仍固定在结果上方，不补成虚假结果。

`developer-docs-nav` 抽屉关闭时设为 `inert` 和 `aria-hidden`。打开时使用 `preventScroll` 聚焦关闭按钮，再通过可选的 `drawerList` target 显示规范的当前指南标记。标记位于列表内时，仅滚动该列表，使整行刚好可见；行高超过列表视口时，保持行首可见。搜索将标记固定在控件区时，结果列表从顶部开始。缺少 target 或标记不影响打开对话框。不能使用不受限制的 `scrollIntoView`、转移焦点到指南或改变主区域／文章滚动位置。Tab／Shift+Tab 仅在实际显示且可操作的控件间循环。Escape、关闭按钮及遮罩将焦点移回打开按钮；首页／清除／上下文／指南链接关闭抽屉并保留原生跳转。关闭时恢复 body 原有的 overflow。`ResizeObserver` 观察阅读器，并检查打开按钮是否实际可见：切换到桌面目录栏时关闭抽屉，若打开按钮已隐藏，则将焦点移至目录栏。低高度模式不新增 JS 数值断点。控制器断开时取消待执行动画／定时器，移除监听器及观察器，并解除滚动锁定。

`reader_text` 在渲染时翻译导航及无障碍文案，成对语言文件为 `config/locales/customer_docs.en.yml` 和 `customer_docs.zh-CN.yml`。传入语言时，桌面／移动端 GET 搜索表单添加隐藏语言字段；开发默认不添加。抽屉文案通过 data 值传给 `developer-docs-nav` Stimulus 控制器，复制文案传给 `docs-reader` 控制器。首页／图注新增键为 `customer_docs.home.guides_title`、`home.guides_intro`、`home.guides_empty`、`screenshots.full_size` 和 `screenshots.open`（`%{caption}`）。本节导航使用 `home_link`、`more_in_section` 和 `group_descriptions.*`。客户面包屑的首页项使用 `customer_docs.home_link`，分组项使用 `customer_docs.groups.*`，文章末项通过 `DeveloperDocs::NavigationHelper#docs_navigation_label` 显示简短名称。

`customer_docs` 与 `developer_docs` 均添加成对的 `search_results`（**Search results**／**搜索结果**）、`current_context`（**Reading now**／**当前阅读**）、`sequence_label`（**Reading order**／**阅读顺序**）、`back_to_top`（**Back to top**／**返回顶部**）、`copy_code`（**Copy**／**复制**）和 `copied_code`（**Copied**／**已复制**）。顺序卡片使用既有的 `previous`／`next` 文案（客户：上一篇／下一篇；开发文档：上一页／下一页）。文档集首页链接使用 `breadcrumb.reference`。复用既有的 `search_submit`、`search_clear`、`search_empty` 及导航键。

客户专用的 `customer_docs.nav_labels` 映射由 `app/helpers/developer_docs/navigation_helper.rb` 中的 `DeveloperDocs::NavigationHelper#docs_navigation_label(slug, title:, translation_scope:)` 在渲染时解析，供阅读器、目录和视图共用。客户名称缺失时回退到传入的完整标题；开发文档及其他作用域保留完整标题。不需要翻译常量、重复映射或解析 URL。每个已发布客户 slug 均须具备两种语言键：

| Slug | 英文名称 | 简体中文名称 |
| --- | --- | --- |
| `overview` | Guide overview | 指南概览 |
| `getting-started` | Get started | 快速入门 |
| `assistant` | Use the assistant | 使用助手 |
| `users` | Manage users | 管理用户 |
| `payments` | Take payments | 收款管理 |
| `email` | Send email | 发送邮件 |
| `sms` | Send SMS | 发送短信 |
| `records` | Find records | 查找记录 |
| `forms` | Review forms | 查看表单 |
| `websites` | Publish website | 发布网站 |
| `settings` | Workspace settings | 工作区设置 |
| `billing` | Subscription & invoices | 订阅与账单 |
| `support` | Get help | 获取帮助 |

搜索将 `q` 去除首尾空白后截至 80 个字符，按本地化标题、摘要和正文筛选目录；简短任务名称不引入另一套搜索引擎。当前文章、未筛选上下文、同组页尾及按目录顺序排列的上一篇／下一篇保持不变。控制器用概览或文章路由 helper 构建 `search_path`，只传入 `locale: current_locale`，因此清除搜索会移除 `q`，同时保留语言。桌面与移动端 GET 表单保留不同的输入 ID、`maxlength=80`、`autocomplete=off` 及可见原生提交控件。浏览器提交 GET 表单时会用表单字段替换 action 中的查询字符串，所以必须提供语言隐藏字段。客户面包屑及缺失页面的返回链接同样带有 `locale: current_locale`。

显式的 `?locale=zh-CN` 仅对当前请求生效；`SetLocale` 不会将其保存到用户或 cookie。客户指南导航持续携带生效语言，使偏好英文的管理员仍能连续阅读中文，直到主动选择其他语言。英文同样显式保留；请求语言缺失或不受支持时，使用解析后实际生效的语言。

全局 `LocaleSwitcherComponent` 提交 `PATCH /locale`。`LocalesController` 校验请求语言，将其保存到 cookie 及已登录用户的个人资料，并替换同源返回 URL 中已有的 `locale` 查询参数。因此，文章从英文切换为中文、再切回英文时，保留 URL 中的租户、文章、搜索及其他查询值和片段锚点，同时按新选择的语言渲染。不支持的语言不会改变偏好或安全的返回 URL；来源页缺失、格式错误或不同源时，回退到根路径。跳转约定参阅[国际化](internationalization)。

### 帮助菜单布局

屏幕宽度低于 `sm`（640px）时，帮助菜单根元素使用 `static` 定位，使绝对定位的下拉面板以现有的相对定位 Topbar 页眉为基准。面板位于页眉下方，上外边距为 0.5rem，左右各留 1rem，宽度自动填充且不超过 `calc(100vw - 2rem)`。从 `sm` 起，根元素使用 `relative` 定位，面板恢复为以帮助按钮为基准、宽 20rem 的右对齐下拉菜单；左侧及顶部定位值重置为 `auto`。布局由 Tailwind 响应式工具类实现。

### 截图编写与安全渲染

文件存放于 `public/help/docs/screenshots/<locale>/<basename>.png`，访问地址不含 `public`。每张图使用独立的 Markdown 图片段落，填写有意义且非空的替代文字，并用带引号的 title 作为可见图注：

```markdown
![Form access panel with launch status and member and public audience controls.](/help/docs/screenshots/en/forms-publishing.png "Check launch status and audience before sharing a form link.")

![表单访问面板中的上线状态及会员、公开访问控件。](/help/docs/screenshots/zh-CN/forms-publishing.png "分享表单链接前，先核对上线状态和访问范围。")
```

每种语言包含六个主题：getting-started 中的 `workspace-help.png`、records 中的 `records-list.png`、forms 中的 `forms-publishing.png`、websites 中的 `website-publishing.png`、email 中的 `email-audience.png`，以及 payments 中的 `payment-settings.png`。图片放在对应操作旁。邮件若使用新建列表截图，应放在创建受众处，不能配在声称已解析发送活动收件人的文字旁。

`DeveloperDocs::Renderer.call` 接受 `screenshot_root: nil` 和 `screenshot_labels: nil`。未启用根目录时，沿用移除图片行为。唯一支持的显式根目录为 `"/help/docs/screenshots"`；启用后须提供本地化 `full_size` 与 `open` 文案。有效的独立 Markdown 图片生成语义化 `figure`，包含图片链接、`img`、`figcaption` 及原生**查看原图**链接。两个链接使用相同的已校验图片地址，在同一标签页打开；浏览器返回即可回到指南。图片链接的无障碍名称包含图注。渲染器控制 `loading="lazy"` 与 `decoding="async"`；替代文字和图注按文本转义，不作为可信 HTML，也不只依赖悬浮提示。

渲染前及清洗时，原始地址必须整串匹配：

```text
\A/help/docs/screenshots/(?:en|zh-CN)/[a-z0-9]+(?:-[a-z0-9]+)*\.png\z
```

不接受外部、协议相对、data/blob、SVG、相对、嵌套、查询参数、片段、百分号编码、首尾空白、反斜杠或目录穿越地址。不能解码已拒绝输入使其变为可接受路径，也不能抓取远程图片。按标签清洗只保留适用的图、图片和链接属性；类名／loading／decoding 受控，作者提供的事件、style 和 srcset 被移除。原始 HTML 图片不作为合格图注来源。不安全或错误图片仅保留已转义的替代文字，不生成图片／原图链接。截图链接是独立白名单静态资源类别，不是指南 slug，也不表示所有根相对地址均被允许。

有效路径对应的 PNG 缺失时，浏览器仍可能加载失败。发布检查要求文件存在，且每种语言使用自己的图片目录。图注须说明实际控件及状态，包括空白或停用状态；所有关键操作均在相邻文字中提供。静态 PNG 可公开访问：使用真实管理员角色会话、本地化界面和可公开的演示数据，不显示所有者专用导航、凭据、恢复码或支付资料。不能虚构成功或已有数据的状态。

`script/capture_help_doc_screenshots.mjs` 通过 Playwright Chromium 访问正在运行的服务，把六个截图主题写到 `tmp/help-doc-screenshots/<locale>/`（可用 `SCREENSHOT_DIR` 覆盖）。脚本使用 `DOCS_CAPTURE_EMAIL` 与 `DOCS_CAPTURE_PASSWORD`，经真实的 `/auth/sign_in` 表单登录 `DOCS_CAPTURE_CUSTOMER_ID` 指定的客户管理员演示工作区。不要对 `SKIP_AUTH=1` 服务运行：该桩即使访问其他租户地址，也可能解析为平台所有者。「管理访问」抽屉链接不带 `?locale=`，因此脚本通过真实的语言切换器切换语言。可选的 `DOCS_CAPTURE_ENTITY`（默认 `Workshop registrations`）与 `DOCS_CAPTURE_PROVIDER`（默认 `Stripe`）分别指定记录列表和要打开测试环境的收款服务商。传入语言（`en`、`zh-CN` 或 `both`）及可选的主题文件名，可只重新截取部分图片。

截图使用 1440 × 1600 CSS 像素的浅色视口，设备像素比取 `DOCS_CAPTURE_SCALE`（默认 **2**）。阅读器会把图片拉伸至整个正文栏（最宽 704px），较窄区域的 1× 截图会被放大而发虚；2× 截图在正文栏、高密度屏幕及**查看原图**中都能保持文字清晰。裁剪区域按实时元素测量（面包屑、目标卡片或抽屉，外加 24px 边距），不使用固定坐标，布局变化时不会截掉控件。每次截图前先将鼠标移离目标，避免出现悬浮提示。核对后再覆盖 `public/help/docs/screenshots`。设置 `APP_BASE_URL` 后，`spec/e2e/documentation_reader.app.spec.js` 会检查阅读器外壳（分组导航、本节链接、移动端抽屉）。

### 编辑流程与定向验证

仓库搜索的无结果夹具使用文档正文中不存在、带命名空间的确定性唯一标记，长度小于仓库的 80 字符查询上限。指南更新后，普通措辞可能成为合法搜索内容。仓库测试仍覆盖标题／摘要／正文的正向匹配、不受查询影响的首页主题卡片，以及混合执行顺序下的导航／缓存检查。

1. 保留五个必需二级标题及其顺序，添加任务三级标题。提供起始页面、准确操作标签、编号字段子步骤、实用示例、就近结果核对和可执行的恢复方法。
2. 翻译前，根据控制器／服务核对重要行为，根据语言文件／组件核对操作标签。两种语言的章节、示例、相关链接目标、提示块和截图主题一致。
3. 保存／启用／发布区别及测试证据使用就近 `:::note`，重要已支持操作使用 `:::attention`。支付宝／微信探测不证明真实厂商流程。测试邮件使用 current_user；租户 MFA 适用于 admin／owner，账户超时／失败上限经 Settings／TenantSecurityPolicy 执行。页面保存、页面上线及站点发布保持明确区分，见[身份认证](authentication)。
4. 对照截图核查图注；使用真实替代画面时保留稳定文件名。非空替代文字／title 与独立段落是编写要求，不能证明画面中的业务操作成功。
5. 运行正文／仓库／渲染器／组件／请求定向检查，再检查两类文档、两种语言在 320/390/768/1024/1440px 和 200% 缩放下的表现，包括开发文档应用侧栏展开／收起状态。测量容器宽度对应的侧栏模式、704px 阅读宽度上限、一级标题／正文对齐及排版；检查匹配／无结果查询下首页导航完整、文章只有一份本页目录、指南／原图链接键盘操作、图片打开与返回、移动目录、搜索／语言恢复，以及表格／代码局部滚动且页面／主区域无横向溢出。
6. 检查两类文档无需展开即可跨组跳转。查询包含／排除当前文章及无结果时，分组面包屑、各可见目录区域唯一的当前链接、同组页尾及页尾顺序目标均保留。在 1440px 下检查满高侧栏、滚动高亮、`/` 快捷键、返回顶部及代码复制。验证可见的搜索按钮、Enter、清除搜索、保留语言的分组片段、固定控件／独立列表滚动，以及靠后指南打开抽屉后可见、关闭按钮保留焦点、主区域位置不变。W 较宽时，检查 H=550px 的单列／抽屉模式及 H=640px 恢复容器模式。

`spec/services/customer_docs/published_guides_spec.rb` 覆盖全部源文件、元数据、必需标题、相关链接／锚点一致性，以及截图语言／路径／替代文字／图注／文件检查。仓库 spec 覆盖 12 条指南元数据、回退、缺失／空分组、查询独立性、URL 客户／语言链接、元数据更新及缓存策略隔离。渲染器 spec 检查两种语言路径、图注／替代文字转义、错误及恶意 URL／属性、相同原生链接和默认移除图片。首页／阅读器／目录组件 spec 覆盖正常／空状态、分组链接行的无障碍关联、可选中央页眉、本页目录显示条件、导航及语言约定。请求 spec 覆盖首页和显式概览分组、非首页省略、租户／角色守卫、本地化导航、搜索和 404 恢复。实际布局及计算后的排版由浏览器验证。

导航验证新增仓库检查：未筛选 `current_group`、真实结果、缺失同组页面、相邻 slug 及 symbol／string `q` 移除；helper 检查渲染时名称、回退及语言键完整性；组件／请求检查固定控件、唯一说明 ID、两类文档的静态分组、查询独立的上下文／本节／页尾目标及阅读辅助接线。`developer-docs-nav` 的 Vitest 覆盖可选列表／标记路径、显示当前项的判断及对话框生命周期；`docs-reader` 的 Vitest 覆盖面板测量、滚动高亮、`/` 快捷键、代码包裹及两种复制路径。整行实际可见、侧栏高度与主区域位置不变须由应用浏览器 spec 验证。两个控制器在配置的覆盖率运行中均须保持行、分支及函数 100%。这些是本次范围的定向检查，不要求运行完整 Rails 测试套件。

应用浏览器检查为每条操作流程预留 90 秒，先等待外壳首次 importmap 预加载完成，再执行交互。目录搜索使用原生 GET 表单，而非防抖式客户端筛选：按 Enter 必须向表单 action 发出同源请求，完成携带 `q` 和 `locale` 的 200 响应，更新地址栏，并完成最终 Turbo 渲染及控制器挂载。仍检查两个输入框的值、完整首页导航、本地化结果和清除搜索。延迟加载截图先滚入视野，等待 `HTMLImageElement.decode()`，再要求原始尺寸为正且宽高比保持不变；缺失或无效图片会导致解码失败。这样可避免把排队中的请求误判为查询参数丢失或 PNG 损坏。文档与[顶部导航](dashboard)两个浏览器文件使用 `--workers=4` 一起运行，指定独立输出目录，并保持共用应用及静态服务器运行。

```bash
bundle exec rspec spec/services/customer_docs spec/services/developer_docs/renderer_spec.rb spec/services/developer_docs/repository_spec.rb spec/helpers/developer_docs/navigation_helper_spec.rb spec/components/customer_docs/home_guides_component_spec.rb spec/components/developer_docs/reader_component_spec.rb spec/components/developer_docs/contents_nav_component_spec.rb spec/requests/admin/help/docs_spec.rb spec/requests/admin/maintenance/platform/developer_docs_spec.rb
npx vitest run --config config/javascript/vitest.config.js spec/javascript/controllers/developer_docs_nav_controller.test.js spec/javascript/controllers/docs_reader_controller.test.js
npx vitest run --config config/javascript/vitest.config.js --coverage
bin/rails tailwindcss:build
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
git diff --check
```

## 需要特别注意

:::attention
授权由管理端 URL 前缀及继承的集中式守卫执行。隐藏帮助入口不能代替授权。客户文档不能暴露仅所有者可见的开发文档，也不能绕过租户检查。开发文档控制器继续放在 `/admin/maintenance/platform/` 下。
:::

:::attention
目录注入必须同时传到仓库和渲染器。客户站内交叉链接使用 `getting-started` 等客户目录 slug，不能使用开发目录 slug 或文件系统路径。共用渲染器仍支持安全的 HTTP(S) 外链；注入目录负责约束站内文章链接。
:::

:::attention
渲染片段缓存与 HTTP 缓存是两层机制。`Renderer::CACHE_VERSION` 为 `documentation/v6`；缓存键包含 `SCREENSHOT_POLICY_VERSION`（`screenshots/v1`）、截图根目录及本地化文案、目录名称、翻译作用域、路由 helper／选项、客户 id、语言、源文件路径及亚秒精度 `mtime`。策略变更不能复用旧的已移除图片或不同许可策略的输出。仅修改组件页眉／布局／Tailwind 不改变渲染器输出的 HTML，无需调整缓存版本。保存 Markdown 即可使对应片段失效，无需重启；首页元数据在此缓存外组装。客户 HTML 仍为 `private, no-store`。
:::

:::attention
语言回退只便于运行，不代替完整发布。每个客户 slug 都须具备两种语言正文及五个必需标题。`spec/services/customer_docs/published_guides_spec.rb` 校验已发布正文约定；开发仓库 spec 按独立的开发文档标题约定校验本实现参考页。
:::

## 关键代码

```ruby
# app/services/developer_docs/repository.rb — shared customer/developer metadata
Page = Data.define(
  :slug, :title, :summary, :html, :headings, :groups, :current_group,
  :previous_page, :next_page, :query, :search_path
)
Group = Data.define(:key, :entries)
Entry = Data.define(:slug, :title, :path, :active)
Link = Data.define(:slug, :title, :path)
```

```ruby
# app/helpers/developer_docs/navigation_helper.rb
def docs_navigation_label(slug, title:, translation_scope:)
  return title unless translation_scope == "customer_docs"

  I18n.t("#{translation_scope}.nav_labels.#{slug}", default: title)
end
```

```ruby
# app/services/customer_docs/repository.rb
class Repository < DeveloperDocs::Repository
  def initialize(customer_id:, locale: I18n.locale,
                 screenshot_root: DeveloperDocs::Renderer::SCREENSHOT_ROOT, **options)
    super(
      customer_id:, locale:, catalog: Catalog,
      content_root: Rails.root.join("doc/customer"), translation_scope: "customer_docs",
      route_helper: :admin_help_doc_path, screenshot_root:, **options
    )
  end
end
```

```ruby
# app/controllers/admin/help/docs_controller.rb
def render_page(slug)
  response.headers["Cache-Control"] = "private, no-store"
  repository = CustomerDocs::Repository.new(
    customer_id: current_customer_id, locale: current_locale, route_options: { locale: current_locale }
  )
  @page = repository.page(
    slug,
    query: params[:q],
    search_path: search_path
  )
  if @page
    @guide_groups = @page.slug == CustomerDocs::Catalog::HOME_SLUG ? repository.guide_groups : nil
    render :show
  else
    render :missing, status: :not_found
  end
end

def search_path
  if action_name == "index"
    helpers.admin_help_docs_path(current_customer_id, locale: current_locale)
  else
    helpers.admin_help_doc_path(current_customer_id, params[:slug], locale: current_locale)
  end
end
```

```erb
<%# app/views/admin/help/docs/show.html.erb %>
<%
  current_group = @page.current_group
  home = @page.slug == CustomerDocs::Catalog::HOME_SLUG
  home_path = admin_help_docs_path(current_customer_id, locale: current_locale)
  doc_crumbs = [
    { label: t("chrome.help_menu.help") },
    { label: t("customer_docs.home_link"), path: home_path }
  ]
  if current_group && !home
    doc_crumbs << { label: t("customer_docs.groups.#{current_group.key}"), path: "#{home_path}#customer-doc-guide-group-#{current_group.key}" }
  end
  doc_crumbs << { label: docs_navigation_label(@page.slug, title: @page.title, translation_scope: "customer_docs") } unless home
%>
<%= render DeveloperDocs::ReaderComponent.new(
  page: @page, translation_scope: "customer_docs", locale: current_locale,
  article_variant: :customer, home_groups: (home ? @guide_groups : nil),
  home_path: home_path
) do |reader| %>
  <% reader.with_header do %>
    <%= render AdminPageComponent.new(
      breadcrumbs: doc_crumbs, title: @page.title, description: @page.summary,
      wrap_title: true, width: "full"
    ) %>
  <% end %>
<% end %>
```

目录及标题约定位于 `app/services/customer_docs/catalog.rb`。共用配置与链接验证位于 `app/services/developer_docs/repository.rb` 和 `renderer.rb`；阅读器翻译作用域在 `app/components/developer_docs/reader_component.rb` 及其模板中选择。帮助入口位于 `app/components/help_menu_component.rb` 及其模板。定向检查包括 `spec/services/customer_docs/`、`spec/services/developer_docs/repository_spec.rb`，以及帮助菜单和阅读器的组件 spec。`spec/requests/admin/help/docs_spec.rb` 用偏好英文的账户跟随实际生成的中文指南链接，提交两种搜索表单时不复用 action 查询参数，再清除搜索，并跟随缺失页面返回链接及帮助入口。该 spec 还连续提交实际渲染的全局语言切换表单，从英文切到中文再切回，跟随每次跳转，验证本地化正文及保留的 URL 上下文，并检查不支持的语言请求。`spec/requests/locales_spec.rb` 覆盖查询参数保留及不安全来源页的根路径回退。
