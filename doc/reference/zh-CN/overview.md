---
title: "开发文档"
summary: "说明这套文档如何编写、如何渲染、如何按主题浏览，以及谁可以阅读。"
---

## 概要

这是 Anysys 现行实现的维护手册，面向平台所有者与修改产品的工程师。每一页对应一项能力：它是什么、一次请求或一次编辑如何穿过代码、实现落在哪里，以及哪些地方容易写错。

正文是 `doc/reference/en` 与 `doc/reference/zh-CN` 下的 Markdown。[Kramdown](https://kramdown.gettalong.org/) 的 GFM 解析器把页面转成 HTML，为标题生成锚点，并用 Rouge 高亮围栏代码。Rails 页面 `/:customer_id/admin/maintenance/platform/developer_docs` 负责承载这些 HTML。`docs/` 里的历史设计笔记如果与代码不一致，以代码为准，并回写本参考。

建议先读 [系统地图](system-map)，再打开正在修改的构建器：[实体构建器](entity-builder)、[流程图构建器](flowchart-builder) 或 [页面构建器](page-builder)。

客户管理员从**帮助 → 文档**进入独立的操作指南，路径为 `/:cid/admin/help/docs`。这些页面存放在 `doc/customer`，使用 `CustomerDocs::Catalog`，并复用本页介绍的渲染基础设施。客户指南的 admin-or-owner 权限不会授予这套仅所有者可见的开发文档权限。参阅[客户使用文档](customer-documentation)。

## 流程

```text
doc/reference/<locale>/<slug>.md
        |
        |  YAML 文首 + Markdown
        v
DeveloperDocs::Repository
        |  slug 必须在 DeveloperDocs::Catalog 中
        v
DeveloperDocs::Renderer
        |  Kramdown GFM、Rouge、提示块、标题锚点
        v
Loofah 白名单
        v
DeveloperDocs::ReaderComponent
        |  移动端吸顶目录栏 | 满高左栏（首页／搜索／上下文 + 列表）
        |  中央页眉插槽 | 分组主题导航（首页） | 正文
        |  滚动高亮的本页内容 | 未筛选本节 + 页尾顺序导航
        v
GET /:cid/admin/maintenance/platform/developer_docs/:slug
        |
        |  RouteAuthorization：仅 platform_owner?
        v
平台所有者会话
```

首页以带边框的卡片组织主题链接，每个目录分组一张卡片。两类文档的目录均以静态带标题分区（`<section aria-labelledby>` + `<h3>` + 缩进列表）显示全部分组，不再折叠。搜索时只显示仍有匹配项的分组。筛选目录不会减少两类首页导航条目。「本页内容」仅在有标题的文章上显示，内嵌目录与右侧栏始终只显示一份，并高亮正在阅读的小节。首页不预留右栏。「本节其他页面」以卡片列出未筛选的当前分组中的其余页面，搜索时也保留。上一页／下一页卡片只在正文之后出现一次，正文上方不再有顺序导航。

## 实现

`DeveloperDocs::Catalog` 是 slug 与分组的有序列表。不在目录中的 slug 返回 404，仓库也不会把它拼进文件系统路径。

`DeveloperDocs::Repository` 默认读取 `doc/reference/<locale>/<slug>.md`，解析文首，再渲染正文。语言取 `I18n.locale`，须在配置目录支持的语言中，否则回退到英文。缺少对应语言正文时也回退到英文正文。搜索匹配标题、摘要与正文，并且只过滤目录，不替换当前文章。

`Repository::Page` 的未筛选 `current_group` 独立于查询过滤的 `groups`。顺序／本节／上下文导航清除两种 `q`，保留租户及生效语言。开发地址现保留 `locale`，不再丢弃仅当前请求的语言覆盖。不能补充虚假搜索结果或另传完整目录。

仓库接受 `catalog:`、`content_root:`、`translation_scope:` 与 `route_helper:`，默认是 `DeveloperDocs::Catalog`、`Rails.root.join("doc/reference")`、`"developer_docs"` 和 `:admin_maintenance_platform_developer_doc_path`。`CustomerDocs::Repository` 传入独立目录、`doc/customer` 根目录、`"customer_docs"` 翻译作用域及 `:admin_help_doc_path`。渲染片段缓存键包含目录名称、翻译作用域、路由 helper、客户 id、选定语言、源文件路径及带亚秒精度的文件 `mtime`，隔离两套阅读器的正文与链接。保存源文件即可刷新对应渲染片段，无需重启服务。

`DeveloperDocs::Renderer` 是唯一的 Markdown 入口。它先把 `:::attention` 与 `:::note` 从正文抽出（围栏代码保持原样），用 Kramdown 渲染后再放回为侧栏提示。标题 id 在转成 HTML 之前写到 Kramdown 树上，因此目录与正文指向同一锚点。注入的 `catalog:` 默认为 `DeveloperDocs::Catalog`；目录 slug 链接通过传入的链接解析器改写，本参考指向平台路由，客户指南指向客户帮助路由。结果经 Loofah 清洗，脚本与意外属性不会留下。

`DeveloperDocs::ReaderComponent` 默认使用 `translation_scope: "developer_docs"`。客户视图传入 `"customer_docs"`，选择独立的目录、搜索、分组、导航及无障碍文案。两类阅读器共用响应式外壳、固定控件、不受查询影响的本节链接、顺序导航及 `developer-docs-nav` + `docs-reader` Stimulus 控制器。开发文档概览还会传入 `Repository#hub_groups` 得到且不受 `q` 影响的 `home_groups`，并以平台文档首页作为 `home_path`。概览入口及显式 `/developer_docs/overview` 均显示相同的完整首页导航。`home_groups: nil` 省略分组导航；`[]` 保留概览正文并显示本地化暂不可用提示。

可选的 `header` 插槽承载现有 `AdminPageComponent`（`wrap_title: true`、`width: "full"`），并置于带下边框的 `<header>` 中，使面包屑、唯一的一级标题与摘要位于正文之上。文章中央栏最多宽 704px（`max-w-[44rem]`）；首页导航放宽到 960px，卡片可三列排布，首页正文仍为 704px。阅读器在外壳留白内最多宽 1200px。视口高度 ≥640px 时，命名容器查询依据扣除应用侧栏后的实际可用宽度：达到 832px（`@min-[52rem]/docs`）时显示 240px 目录栏；达到 1056px（`@min-[66rem]/docs`）时，有标题的文章增加 192px 右栏；间距均为 40px。低于 832px 时，主滚动区顶部吸顶栏提供目录按钮及当前「分组／页面」位置；低于 1056px 有标题的文章使用可折叠的内嵌本页目录。视口高度 <640px 时，网格／侧栏／吸顶栏／抽屉／遮罩／本页目录配套切换为单列／抽屉模式，不受阅读器宽度影响。首页卡片在导航宽度达到 576px 时切为双列，达到 832px 时切为三列；「本节其他页面」卡片在 640px 时切为双列；页尾上一页／下一页卡片在 480px 时并排。

桌面目录在主滚动区顶部下方 24px 吸附并占满可用高度：`docs-reader` 将主区域 `clientHeight` 写入 `--docs-pane-height`（由 `ResizeObserver` 保持更新），侧栏高度为 `calc(var(--docs-pane-height) - 3rem)`，回退值为 `100dvh - 10rem`。页头／控件固定，`min-h-0` 列表滚动。`h-dvh` 抽屉复用分区并保留安全区留白。传入 `home_path` 时，桌面页头以文档集首页链接（书本图标 + `breadcrumb.reference`）开头，抽屉页头的同名标题也是首页链接。其后是 40px 搜索框，左侧为搜索按钮并显示 `/` 提示；搜索时显示可见的清除链接。GET 保留 80 字符规范化；两套阅读器通过搜索隐藏字段及清除／导航链接保留生效语言，不改变用户全局语言偏好。

开发文档控制器使用当前路由参数及生效的 `locale` 生成不含 `q` 的 `Page#search_path`。两处固定清除控件及空结果恢复链接共用该地址。因此，即使账户语言偏好为英文，清除中文搜索后仍停留在原中文首页或文章；两套表单也提交隐藏的语言字段。

视口高度 <640px 时，抽屉缩小间距，搜索框／搜索按钮并排，首页／清除链接同时存在时也并排，为列表保留空间。控件保留可见文字及 44px 操作区域，上下文固定，列表至少预留 64px。高度 ≥640px 时恢复常规整行堆叠控件及既有宽度容器模式。

搜索时，固定的**当前阅读**保留未筛选的分组／当前指南，并拥有该目录区域中唯一的 `aria-current="page"`／`data-docs-current-guide` 链接。**搜索结果**仅使用真实的 `page.groups` 匹配项，即使当前页面匹配，也不带当前项语义。没有查询时，常规当前列表条目承载这些语义。阅读器上下文、两类 show 视图的分组面包屑及 `section_entries` 均读取 `page.current_group`。分组链接将 `developer-doc-guide-group-<key>` 或 `customer-doc-guide-group-<key>` 附加到传入的首页 URL，客户语言参数保留在片段之前。点击当前阅读可在同一指南清除搜索；本节及顺序导航也移除 `q`。

`DeveloperDocs::ContentsNavComponent` 新增 `surface: :desktop`／`:mobile`，保留 `page:`、`translation_scope:` 和 `navigate:`。`DeveloperDocs::NavigationHelper#docs_navigation_label(slug, title:, translation_scope:)` 在渲染时查找客户 `customer_docs.nav_labels.<slug>`，缺失时回退到完整标题；开发文档链接仍使用完整元数据标题。客户目录／上下文简短链接通过区域唯一的完整标题 `aria-describedby` ID 提供说明；一级标题、首页导航及页尾保留完整标题。两个命名空间均提供 `search_results`、`current_context`、`sequence_label`、`previous`／`next`、`back_to_top`、`copy_code` 及 `copied_code`。页尾顺序导航（`data-docs-footer-sequence`）位于正文及「本节其他页面」之后；卡片不带查询条件，在完整标题上方标注上一页／下一页。

`docs-reader`（`app/javascript/controllers/docs_reader_controller.js`）提供阅读辅助。滚动高亮将阅读线（距顶部 120px）以上最后一个标题对应的本页目录链接标为 `aria-current="location"`；滚动到底时高亮最后一个标题。在可编辑字段之外按 `/`，聚焦并选中当前可见的搜索框（`aria-keyshortcuts="/"`）。正文中每个 `pre` 由 `<template>` 包裹并加上复制按钮（指针设备悬停／聚焦时显示，触屏设备常显）；优先使用 Clipboard API，纯 HTTP 来源回退到 `execCommand`，并通过 `aria-live` 播报「已复制」。右栏末尾提供指向文章 id 的**返回顶部**链接。断开连接时移除监听器、观察器、动画帧及复制计时器。

导航标记为 `data-docs-nav-header`、`data-docs-nav-list` 及规范的 `data-docs-current-guide` 链接。初始桌面布局及进入桌面模式时，仅滚动桌面列表以显示常规当前指南行，使靠后指南立即可见，不改变焦点及窗口／主区域／文章位置。抽屉的当前项显示在打开时另行执行：仅滚动可选的 `data-developer-docs-nav-target="drawerList"` 列表，关闭按钮通过 `preventScroll` 保留焦点。搜索上下文已固定在控件区，因此抽屉结果从列表顶部开始。关闭的抽屉保持 inert／aria-hidden；保留焦点循环／返回、原生跳转、滚动恢复及 resize／disconnect 清理。JS 模式仍以打开按钮实际可见性为准，包含低高度回退。

阅读器组件管理的 Tailwind 工具类替代文档专用 CSS；`.docs-page`、`.customer-doc` 和 `.developer-doc` 仅保留为语义／测试标记。两类文档在任何宽度下都使用 `font-sans` 和应用字级：一级标题 20px／27.5px，摘要 13px／19.5px，正文 14px／21px，二级标题 20px／25px，三级标题 18px／24.75px，导航 13px／19.5px。代码保持 `font-mono` 及应用 `pre` 字号。两类文档的表格与代码均局部滚动；截图保留原始比例，图注自然换行。仅修改组件布局／页眉工具类不改变渲染器 HTML 或缓存版本。完整组件、语言及截图约定参阅[客户使用文档](customer-documentation)。

`Admin::Maintenance::Platform::DeveloperDocsController` 只负责读取。index 渲染 `overview`，show 渲染 `params[:slug]`。两者都位于 `/admin/maintenance/platform/`，`RouteAuthorization` 已将其限制为 `platform_owner?`。控制器里不要再加第二道角色过滤。控制器每次请求复用一个仓库实例读取文章，并在首页 slug 上组装分组主题导航。

侧栏入口在 `MaintenanceContributor`，仅当 URL 客户为 `81721200` 且当前用户是平台所有者时出现。

### 新增一页

1. 把 slug 加进 `DeveloperDocs::Catalog::GROUPS` 的对应分组。
2. 同时添加 `doc/reference/en/<slug>.md` 与 `doc/reference/zh-CN/<slug>.md`。
3. 文首需要 `title` 与 `summary`。不要写一级标题，页眉会渲染标题。
4. 使用该语言规定的五个二级标题。
5. 把容易踩坑的地方放进 `:::attention`，并在「关键代码」中标明文件。

### 阅读器验证

使用[定向检查](customer-documentation)验证正文、组件及请求。构建 Tailwind 后，对运行中的应用执行现有浏览器 spec：

```bash
APP_BASE_URL=http://127.0.0.1:3000 npx playwright test --config config/javascript/playwright.config.js spec/e2e/documentation_reader.app.spec.js --project chromium
```

检查两类文档、两种语言在 320/390/768/1024/1440px 和 200% 缩放下的表现，包括开发文档应用侧栏展开／收起状态。核对实测容器模式、中央栏宽度上限、一级标题／正文对齐、计算后的排版、匹配／无结果搜索下首页导航完整、本页目录／导航／抽屉键盘操作，以及富内容局部滚动且页面／主区域无横向溢出。补充 390/1440px 定向导航检查：两类文档的静态分组、可见搜索按钮／Enter／清除搜索、查询独立的上下文／本节链接及页尾顺序目标；另在 1440px 检查阅读辅助（满高侧栏、滚动高亮、`/`、返回顶部、代码复制）。检查列表滚动时控件固定、保留语言的分组片段，以及 320px 靠后指南打开后可见、关闭按钮保留焦点、主区域位置不变。阅读器较宽时，H=550px 使用抽屉，H=640px 恢复容器模式。仓库／helper／组件／请求检查及修改后控制器的 100% Vitest 行／分支／函数覆盖率补充真实浏览器布局验证；参阅链接中的定向命令。未设置 `APP_BASE_URL` 而跳过的运行不能作为浏览器验证依据。

## 需要特别注意

### 路由审计：文档身份与证据

开发阅读器使用既有 Catalog 白名单、语言感知仓库／Reader 输入及 mtime 缓存。index／show 包括格式请求均要求所有者及实际外层平台 CID `81721200`。生成链接、首页／上下文／顺序及搜索保留所选语言。见[租户与角色](tenancy-and-roles)、[客户使用文档](customer-documentation)。

:::note
当前 RC-01–RC-18 API 及调用接入已在两种语言按源码记载。10 月 11 日历史待办清单对应旧快照，参考以当前实现为准。2026-10-12，开发数据库应用待执行迁移 `20261011000100`、`20261011173041`、`20261011184517`、`20261011190000` 后，`bin/rails parallel:prepare && bin/rails parallel:spec` 以 8 个工作进程运行 1,576 个 spec 文件，结果为 **25,266 个示例，0 个失败**（退出码 0，321 秒）。`npx vitest run --config config/javascript/vitest.config.js --coverage` 结果为 **290 个文件，6,956 个测试，0 个失败**，语句、分支、函数与行覆盖率均为 100%。上述结果不覆盖套件未执行的真实服务商、部署或浏览器流程。
:::

:::attention
仅固定所有者可在外层 CID `81721200` 打开该命名空间；租户管理员，包括该客户的管理员，均被中央角色门禁拒绝。
:::

:::attention
两种语言都必须存在。只有 `en` 没有 `zh-CN` 的页面是不完整的。英文与中文的五个二级标题由 `DeveloperDocs::Catalog::REQUIRED_HEADINGS` 固定，本页目录才不会漂移。
:::

:::attention
不要渲染配置目录之外的 slug。`Repository#existing_path` 还会拒绝逃出配置内容根目录（默认为 `doc/reference`）的路径，但真正的守卫是白名单。文内交叉链接必须是裸 slug，例如 `entity-builder`，不要写文件系统路径。客户指南 slug 及必需标题属于 `CustomerDocs::Catalog`；开发参考页属于 `DeveloperDocs::Catalog`。
:::

:::note
围栏代码里的提示标记只是文档，不会被当成提示块。提取器会跳过 ``` 围栏之间的行。
:::

## 关键代码

```ruby
# app/controllers/concerns/route_authorization.rb
def enforce_route_role!
  if platform_namespace? || flowchart_namespace?
    return if current_user.platform_owner?
    raise CanCan::AccessDenied, t("common.errors.authorization.platform_owner_required")
  end
  # ...
end
```

```ruby
# app/models/authentication/user.rb
PLATFORM_CUSTOMER_ID = 81_721_200

def platform_owner?
  owner? && eligible_for_owner_role?
end
```

```ruby
# app/services/developer_docs/catalog.rb
HOME_SLUG = "overview"
LOCALES = %w[en zh-CN].freeze
```
