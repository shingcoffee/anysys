---
title: "网站"
summary: "网站功能模块为租户开通站点、在公开路由上发布，并保存命名主题、骨架选择与单页主题覆盖；页面编排器在 website-builder。"
---

## 概要

网站是功能模块。`FeatureModules::Website::Registration` 使用键 `website`，通过 `FeatureModules::Website::Provisioner` 开通，并贡献页面入口和站点设置链接。四个表面遵循 [module-framework](module-framework)：页面列表、客户站点设置、维护里的启用开关，以及平台骨架与版式目录。

本页讲模块本身：站点行如何创建、主题与发布如何生效、公开站点走哪些 URL。分区编辑、编排器和版式字段在 [website-builder](website-builder)。

`Website` 每个客户一行（`customer_id` 唯一）。`WebsitePage` 属于该站点和同一个客户。`WebsiteSkeleton` 与 `WebsiteLayout` 是平台目录，不按租户划分。

## 流程

```text
启用模块「website」
        |
        v
FeatureModules::Website::Provisioner
        |
        v
Websites::Activities::Provision
        |  Website published: false
        |  Websites::Skeletons.apply!（页面同样未发布）
        v
/:cid/admin/settings/modules/website
        |  SaveSite（名称、主题、SEO、页脚、published）
        |  ReplaceSkeleton（删除页面，套用骨架）
/:cid/admin/modules/website/pages/:id/edit
        |  编排器 — 见 website-builder
        v
GET /:cid/site
GET /:cid/site/:page_slug
        |
        |  模块已启用，且 Website#published?，且页面已发布
        v
Websites::PagesController（否则 head 404）
```

## 实现

`Provisioner.call` 委托给 `Websites::Activities::Provision`。已有的 `Website.for_customer` 原样返回。否则先 `Catalog.sync!`，再创建站点：客户名称、`published: false`、空的 `seo` 与 `footer`，以及一个骨架键。键来自模块配置字段 `default_skeleton_key`（默认 `"presence"`）；该键为空或未知时用 `"presence"`。主题令牌来自 `Websites::Theme.for_catalog(key).to_stored`，即该骨架配对的命名主题（见下文「主题」）。`Websites::Skeletons.apply!` 把骨架页面复制到站点。每个新页面都是 `published: false`。`Provisioner.deprovision` 把 `published` 设为 false，行仍保留。

客户设置是 `Admin::Settings::Modules::Website::SitesController`，路径 `/:customer_id/admin/settings/modules/website`。`Websites::Activities::SaveSite` 写入 `name`、`tagline`、`published`、`theme`、`seo`（`title`、`description`）、`footer` 和 `default_layout_key`。主题键被裁到 `Websites::Theme::TOKENS`：`appearance`、`accent`、`type`、`density`、`corners`、`neutral`；`preset` 为已知的 `Websites::ThemePresets` 键时一并保留。令牌值不在 `Theme::OPTIONS` 内时，`Contracts::Site` 拒绝保存。未知的版式键会被丢掉。更换起步套装是对设置里骨架资源的 `POST`，由 `Admin::Settings::Modules::Website::SkeletonsController` 调用 `Websites::Activities::ReplaceSkeleton`。该事务删除站点上的全部页面，套用新骨架，并替换 `skeleton_key`、`default_layout_key` 和 `theme`。

设置页是 `Websites::Admin::SettingsFormComponent`，各卡片依次为：

1. 发布设置：状态卡片，其中的 `website[published]` 开关在点击「保存」后生效。地址由 `PageShortcuts::PublicPath.website_home` 按主机生成（`/`、`/:customer_id/` 或指定的有效别名），站点已发布时显示为链接，并提供「管理页面快捷路径」次要入口。
2. 网站信息。
3. 外观：先是预设主题画廊（`website[theme][preset]` 单选项，每张卡片按该预设的字体、配色和圆角绘制迷你预览），其后是「微调」，每个主题记号都是可视化单选项（`ThemeOptionComponent`），旁边是 `ThemePreviewSwatchComponent`。选中预设会勾选其全部记号（`website-theme-picker#applyPreset`）；之后改动任一记号，已选预设上显示「已自定义」徽标。该卡片加载 `Websites::Fonts` 的全部字族，字样均以真实字体呈现。
4. 搜索展示。
5. 页脚栏目，以可排序卡片呈现。
6. 页面默认设置：`default_layout_key` 下拉框，按 `Websites::LayoutFamily` 分成若干 `<optgroup>`。
7. 起步模板：`SkeletonReplaceComponent`。它显示当前起步套装及缩略图；展开后每个起步套装一张卡片，附该套装目录主题下的首页缩略图，各有独立的 `ReplaceSkeleton` 表单。

除发布设置外，每张卡片都是 `SettingsSectionComponent`，注册为 `website-theme-picker` 的分区。“本页导航”在 `xl` 及以上是固定的右侧栏，以下是固定的标签条。

浏览列表由 `Admin::Modules::Website::PagesController#index` 在 `/:customer_id/admin/modules/website`（也包括 `/pages`）渲染；此路径同时是 `Registration` 的 `entry_path`、模块卡片、模块侧栏及「内容 → 网站页面」快捷入口。增删改、预览、排序和媒体上传均在该模块命名空间下；`/admin/pages/website` 不再指向网站操作（通用页面的展示路由对该 id 返回 404）。仅当网址所指客户已启用网站模块时才显示快捷入口。`edit` 是编排器；该屏幕见 [website-builder](website-builder)。`website` 模块未启用时，`Admin::Modules::Website::BaseController` 返回 404。站点发布由 `Admin::Settings::Modules::Website::SitesController` 在 `PATCH /:customer_id/admin/settings/modules/website/site` 接收 `website[published]` 并调用 `SaveSite`；页面列表及模块页面不提供发布或设置快捷入口。

公开网站无需登录，支持 GET/HEAD。`PageShortcuts::PublicPath` 为设置、工作室、编辑器和导航生成简洁路径及指定别名，包括多级路径。符合条件的网站页面或公开表单均可映射到指定地址，包括 `/`，并非仅用于替换首页。[自定义域名](custom-domains)是客户上的可选域名，实时读取且无需重启；停用客户返回 404。保存新增或变更的域名时，须配置该域名直接指向 `anysys.net` 的 CNAME；失败则这次保存不写入，清空域名不检查 DNS。部署负责发布 DNS，并分别管理 TLS／入口路由／HostAuthorization。客户前缀、冲突及下线行为见 [页面快捷路径](page-shortcuts)。网站别名不接收 POST。以下规范端点继续可用：

- `GET /:customer_id/site` → `Websites::PagesController#home`
- `GET /:customer_id/site/:page_slug` → `#show`（`page_slug` 为小写片段，用连字符分隔）
- `GET /:customer_id/site/media/:signed_id` → `Websites::AssetsController#show`

`PagesController` 只在模块已启用、`current_website` 的 `published?` 为真、且页面 `published?` 为真时渲染。规范首页用 `Website#home_page`，规范内页 slug 忽略首页。快捷路径请求则按可信的已解析记录编号，在当前客户及网站内加载，并重新检查发布状态；并发 slug 复用或首页切换不会改变目标身份。其余情况是空正文的 `head :not_found`。导航链接是已发布且 `nav_visible` 的页面。页面按 `Websites::Theme.for_page(website:, page:)` 渲染：页面设有 `theme_key` 预设时用它，否则用站点主题。`Websites::Theme` 把令牌映射为 Tailwind 类，以及 `<html>` 上的 CSS 变量（`root_style`）。外观是存下的令牌。类注释写明不要使用 `dark:` 媒体查询，也不要复用 `ThemeResolver`。

## 主题

一个主题由六个令牌组成，取值见 `Websites::Theme::OPTIONS`：

| 令牌 | 取值 |
|------|------|
| `appearance` | `light`、`dark` |
| `accent` | `azure`、`ink`、`gold`、`forest`、`rose`、`violet`、`copper`、`indigo`、`teal`、`crimson`、`plum`、`olive` |
| `type` | `sans`、`serif`、`display`、`grotesk`、`classic`、`modern`、`geometric`、`elegant`、`gallery`、`technical`、`expressive` |
| `density` | `spacious`、`compact` |
| `corners` | `sharp`、`soft`、`round` |
| `neutral` | `neutral`、`warm`、`cool` |

每个 `type` 对应 `Theme::PAIRINGS` 中的一组字体搭配（标题、正文、强调字族，以及标题字重与字距）。`Websites::Fonts` 收录 15 个字族、各自的回退字体栈，以及 `fonts.bunny.net` 样式表地址。`Theme#root_style` 写入 `--font-site-heading`、`--font-site-body`、`--font-sans`、`--font-serif`，按 `corners` 写入一组 `--radius-*`；`warm`／`cool` 时另把 `--color-neutral-*` 色阶换成 stone 或 slate。分区模板使用 `font-site-heading`、`font-site-body`、`rounded-*` 与 `neutral-*` 工具类，因此换主题即可重塑所有分区，模板无需分支。公开布局只链接一个样式表，涵盖主题字族及分区样式中选用的字体（`websites_font_stylesheet`）。

`Websites::ThemePresets` 注册 27 个命名主题（`DEFAULT_KEY` 为 `"meridian"`），每个含一组令牌及本地化的 `website.themes.<key>.name`、`.description`。`Theme.preset(key)` 构建预设；`Theme#to_stored` 附带 `"preset"`，设置页据此标出站点起步时的预设，`Theme#customized?` 判断是否已偏离。

`Websites::ThemePairing` 为每个骨架和版式配上最合适的预设。从骨架切出的版式沿用骨架的预设，独立版式自带预设。平台所有者可在每行上用 `website_skeletons.theme_key`／`website_layouts.theme_key` 改配其他预设（骨架与版式编辑器中的「主题」下拉框；留空即沿用配对）。`Websites::Contracts::Layout` 与 `Websites::Contracts::Skeleton` 经 `Websites::Contracts::ThemeKey` 混入校验改配的键。`#theme_preset_key` 返回改配的键或配对键，`Theme.for_catalog(key)`／`Theme.for_record(record)` 据此解析。卡片循环一次性预载各行，以 `Theme.for_catalog(key, records:)` 传入，避免每张卡片各查一次。目录缩略图、开通和 `ReplaceSkeleton` 均使用该预设。

`website_pages.theme_key` 是可选的单页覆盖，由 `Websites::Contracts::Page` 按 `ThemePresets.keys` 校验。页面编辑器的「主题」下拉框提供「网站主题」（留空）及全部预设；新建页面表单另有「布局搭配的主题」，即 `SavePage::LAYOUT_THEME` 标记值 `"layout"`，`SavePage` 在校验前把它解析为所选版式的 `theme_preset_key`。草稿预览会采用尚未保存的 `theme_key`。

公开营销页面也允许其他租户的已登录用户访问。站点／页面仍按 URL 或可信快捷路径所选租户查询，不使用访问者所属租户或伪造查询参数；受保护的管理路由继续执行租户门禁。

`AssetsController` 要求模块启用、签名 ID 有效及 `MediaPolicy.public_image?(blob, customer_id:)`：租户匹配、显式网站媒体分类、大小大于零且不超过 8 MB、光栅 MIME。下载后重查字节大小及 Marcel MIME，再内联发送并加 `X-Content-Type-Options: nosniff`；私有／未分类／外租户／非光栅／存储缺失均为空 404。站点发布不作为媒体门禁。

平台目录在 `/:customer_id/admin/maintenance/platform/module_settings/website/skeletons` 和 `.../layouts`，由平台路径前缀限制为所有者。`Admin::Maintenance::Platform::Website::SkeletonsController` 和 `LayoutsController` 调用 `Websites::Catalog.sync!`。`sync!` 插入缺失的键；已存在的行保留名称、描述和分区文案，只补空白媒体。`Catalog.refresh!` 用 Ruby 种子覆盖平台骨架和版式行，不改租户的 `Website` 行。骨架键是 `Websites::Skeletons::KEYS`（从 `presence` 到 `quarterly`）。借鉴知名网站的起步组合 `voltage`、`wellspring`、`summit`、`manor`、`bloom`、`roast`、`atrium`、`canvas`、`harbor`、`calm`、`marque`、`tempo`、`quarterly` 分别归入产品、公益、活动、商业、零售、酒旅、文化、产品、零售、健康、产品、文化、编辑类别。版式行还包括 `Catalog::EXTRA_LAYOUTS` 里的额外键（`article`、`manifesto`、`gallery`、`longform`、`launch`、`pricing`、`portfolio`、`menu`、`journal`、`process`、`showcase`、`compare`、`newsroom`、`listings`、`stores`、`heritage`、`conference`、`spotlight`、`campaign`、`tour`、`impact`、`why_us`、`launch_note`）。由于 `sync!` 保留已有行，已有骨架或版式的种子改动只能通过 `refresh!` 或所有者编辑进入数据库。

`WebsitePage` 保留 slug `new`、`edit`、`preview`、`site`、`media`，首页除外，首页 slug 可以为空。每个站点只能有一个首页。

## 需要特别注意

### 路由审计：目录、slug 及媒体不变量

完整骨架／布局写入在媒体补充及持久化前，经 `Contracts::Skeleton`、`Layout`、`Sections` 及 JSONSchemer `PropSchema` 校验。骨架必须恰有一首页、唯一合法 slug、已知布局及合法分区／props／选项／列表；畸形 JSON 拒绝，不归一为空内容。开通／直接应用／替换共用客户快捷路径锁，在删除旧页前检查结构及全部 slug 冲突。替换失败可控，保留现有网站／页面。`SavePage` 在锁内重新加载限定租户／站点的持久状态，显式取消发布应用于最新行，结构锁使用当前模板。

`SavePage` 先解析已保存区块的 ID／类型再补充媒体，忽略的传入类型不会注入无关图片属性。仅修改元数据时保留原区块，不重填模板／媒体；未改动的无效存量内容仍可下线。新页面、区块内容变更及显式发布继续完整校验区块。数组数量错误返回本地化字段／上下限文案；助手已有精确归一化错误时不再追加重复错误。

上传／导入及公开服务共用实际字节光栅分类、租户及网站媒体身份，通用签名附件不是公开网站媒体。provisioner 将失败 Result 转为 ProvisioningError，启用可回滚。AI 文档在会话→客户→有序页面锁内重查草稿并取得独立 Undo 快照；撤销在同一客户边界重载消息／来源并验证指纹。见[网站构建器](website-builder)、[页面快捷路径](page-shortcuts)、[AI 助手](ai-assistant)。

:::note
网站服务、请求、模型、模块钩子及存储隔离回归已在独立数据库／上传目录中定向通过 572 个用例，零失败，包含真实 MIME 字节、Disk 下载、目录、过时保存和助手属性校验。测试存储准备及按进程安全清理见[后台任务](background-jobs)。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。浏览器结果仍须单独运行证明。
:::

:::attention
`Websites::PagesController` 在 `website` 的 `FeatureModules::Module` 未启用、`Website#published?` 不为真、或 `WebsitePage` 未发布时返回空 404。模块关闭、站点未发布和 slug 不存在共用这一响应，从而不泄露标题和站点名称。
:::

:::attention
`ReplaceSkeleton` 先检查完整替换及快捷路径预留，再由 `Skeletons.apply!(site, key, replace: true)` 在事务内删除／重建。成功替换仍移除编辑文案，拒绝替换则保留；停用仅取消站点发布。
:::

:::attention
`Website` 校验 `customer_id` 唯一，因此一个租户只有一个站点。`WebsiteSkeleton` 和 `WebsiteLayout` 没有 `customer_id`。`Websites::Catalog.sync!` 保留这些平台行上的所有者修改。`Catalog.refresh!` 用代码覆盖平台行，不动租户站点。
:::

:::attention
`Websites::Activities::Provision` 和 `Websites::Skeletons.apply!` 创建的页面 `published` 为 false。`Admin::Settings::Modules::Website::SitesController` 通过 `Websites::Activities::SaveSite` 发布站点。站点已发布时，自身 `published` 为 false 的页面仍然隐藏。编辑分区的编排器在 [website-builder](website-builder)。
:::

## 关键代码

```ruby
# app/services/websites/activities/provision.rb
site = Website.create!(
  customer_id: customer.id,
  name: customer.name,
  skeleton_key: default_skeleton_key,
  default_layout_key: default_layout_key_for(default_skeleton_key),
  theme: Websites::Theme.for_catalog(default_skeleton_key).to_stored,
  seo: {},
  footer: {},
  published: false
)
Websites::Skeletons.apply!(site, site.skeleton_key)
```

```ruby
# app/controllers/websites/pages_controller.rb
def public_site_available?
  return false unless website_module_enabled?

  @website = current_website
  @website&.try(:published?)
end
```

```ruby
# app/services/websites/activities/replace_skeleton.rb
result = Websites::Activities::ReplaceSkeleton.call(site: site, skeleton_key: key)
# result.success? / result.errors; invalid replacement preserves current pages.
```

```ruby
# app/services/feature_modules/website/provisioner.rb
def self.deprovision(customer)
  site = ::Website.for_customer(customer.id).first
  site&.update!(published: false)
  site
end
```
