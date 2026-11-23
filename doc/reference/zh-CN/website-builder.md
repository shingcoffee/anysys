---
title: "网站构建器"
summary: "网站功能模块如何用骨架、布局、页面和媒体编排租户营销站。"
---

## 概要

网站构建器是网站功能模块：每个客户一份 `Website`、多条 `WebsitePage`，以及平台级的 `WebsiteSkeleton` 与 `WebsiteLayout` 目录。它发布静态营销页。它不存储 `Page` 配置，不绑定 `form_settings.flowchart_id`，也不提交到 `/page/:uuid`。那套编辑器是 [页面构建器](page-builder)。

启用模块时运行 `FeatureModules::Website::Provisioner`，它调用 `Websites::Activities::Provision`。开通会插入一个未发布的站点，名称取自客户，套用默认骨架（配置默认值 `"presence"`），并应用该骨架配对的命名主题（`Websites::Theme.for_catalog(key).to_stored`，见 [websites](websites)）。停用模块把 `published` 设为 false，行仍然保留。模块关闭时，`Admin::Modules::Website::BaseController`、`Websites::PagesController` 和 `Websites::AssetsController` 返回 404。平台骨架与布局控制器不做这项检查。

公开 URL 无需登录。网站页面使用按主机生成的简洁路径（`/`、`/pricing` 或带客户前缀的对应路径），也可配置 `/campaign/register` 等指定别名，见 [页面快捷路径](page-shortcuts)。规范端点 `GET /:customer_id/site`、`GET /:customer_id/site/:page_slug`、`GET /:customer_id/site/media/:signed_id` 继续可用。站点或页面未发布时是空的 404。

[自定义域名](custom-domains)用客户上保存的域名确定无前缀公开请求的租户。显式客户前缀优先，停用客户返回 404。域名变更后无需重启。保存新增或变更的域名时，须配置该域名直接指向 `anysys.net` 的 CNAME；校验失败则这次保存不写入。清空域名不检查 DNS。部署负责发布 DNS，并分别管理 TLS／入口路由／HostAuthorization；域名不会自动配置这些层。

## 流程

```text
FeatureModules::Website::Registration
        |  provision! / deprovision!
        v
Websites::Activities::Provision
        |  Website + Websites::Skeletons.apply!
        v
Website（每个 customer_id 一份）
        |
        +-- WebsitePage（title、slug、sections JSON、layout_key、home、published）
        |
        +-- theme / seo / footer

租户管理员
        |
        +-- GET  /:cid/admin/modules/website         页面列表（Admin::Modules::Website::PagesController）
        +-- /:cid/admin/modules/website/pages       编排器的增删改、预览、排序
        +-- POST /:cid/admin/modules/website/media  UploadMedia
         +-- /:cid/admin/settings/modules/website    SaveSite（含发布状态）+ ReplaceSkeleton
        +-- /:cid/admin/assistant                  apply_website -> Websites::Assistant::Processor
                                                   （SavePage + ImportMedia，仅草稿）

平台所有者
        |
        +-- /:cid/admin/maintenance/platform/module_settings/website/skeletons
        +-- /:cid/admin/maintenance/platform/module_settings/website/skeletons/:key/preview
        +-- /:cid/admin/maintenance/platform/module_settings/website/layouts
        +-- /:cid/admin/maintenance/platform/module_settings/website/layouts/:key/preview
                |
                v
        Websites::Activities::SaveSkeleton / SaveLayout
        Websites::Catalog.sync!

公开访问
        |
        v
Websites::PagesController   布局 "website"
        |  已发布的站点 + 已发布的页面
        v
由 WebsitePage#sections 渲染的分区组件
```

租户页面编辑器通过 `Websites::Admin::ComposerComponent` 挂载 `website-builder`。新建页是 `identity_only`，编辑器把表单交给 `Websites::Admin::NewPageComponent`。编辑锁定结构（`structure_locked: true`）。平台布局和骨架界面传入 `structure_locked: false`。

## 实现

### 记录

`Website` 校验 `customer_id` 唯一，以及 `name`、`skeleton_key` 必填。`DEFAULT_THEME` 即 `Websites::Theme::DEFAULTS`：外观 `light`、强调色 `azure`、字体 `sans`、密度 `spacious`、圆角 `soft`、色调 `neutral`。`has_many :pages` 是按 `position` 排序的 `WebsitePage`。`home_page` 是 `home: true` 的那一行。

`WebsitePage` 属于 `website`，校验标题、站点内 slug 唯一，以及只能有一个首页。`RESERVED_SLUGS` 为 `new`、`edit`、`preview`、`site`、`media`（首页和空 slug 除外）。`layout` 是 `WebsiteLayout.find_by(key: layout_key)`。可选的 `theme_key` 须为 `Websites::ThemePresets` 中的键，由 `Websites::Contracts::Page` 经共用的 `Websites::Contracts::ThemeKey` 混入校验。分区是 JSON 数组，元素形如 `{ id, type, props }`；`props.styles` 存放设计覆盖。

分区 `props` 中以 `*_href`/`href`/`url` 结尾的键存放链接，由 `Websites::Href` 校验并解析。取值可以为空、kebab-case 的页面 slug（通过 `PageShortcuts::PublicPath.website_slug` 解析）、根相对路径（单个前导 `/`，如 `/auth/sign_up` 或 `/path?query#frag`），或绝对 `https://` URL。`resolve` 接受可选 `host:`，渲染时转换规范本地网站及公开 Page 地址；其他应用路径沿用原有处理。Addressable 保留重复查询参数及片段，公开组件保留语言，展示 helper 为挂载部署添加 `SCRIPT_NAME`。编辑器的原生表单校验同样接受这些根相对路径。协议相对（`//host`）、反斜杠逃逸（`/\host`）、`http:`、`javascript:`、`data:` 一律被拒绝。编辑器校验与 Ruby 校验、解析均在去除首尾空格或解析 URL 之前拒绝反斜杠和控制字符（包括制表符、换行符），防止浏览器将其规范化为外部主机地址；根相对路径内部不得含有空白字符。`Websites::Href.media?` 更严格——接受 `https://` 图片 URL、租户媒体路径（`/:cid/site/media/:signed_id`），以及经严格校验的 `/site-images/anysys/` 下随应用发布的 Anysys SVG 与 `anysys-photo-*.webp` 路径。任意根相对路径仍不能作为媒体。

规范表单链接（`/:cid/page/:uuid`）通过 `PageShortcuts::PublicPath.public_page_uuid` 使用不可变标量身份解析。公开渲染快照批量读取所有符合条件的本客户／共享 UUID 身份，包含未配置别名的表单，同时读取网站及快捷路径身份。网站与表单混合导航／页脚的目标增加时，查询次数仍保持有界；生成链接无需实例化 Page 或触发 after-find 定义加载。请求范围外或显式指定其他租户时，最新的标量查询仍执行可访问性检查。无别名表单保留规范路径；未知或不可访问的链接保持原样。见 [页面快捷路径](page-shortcuts)。

`WebsiteLayout` 与 `WebsiteSkeleton` 是平台行，主键风格的 `key` 匹配 `[a-z0-9]+(?:_[a-z0-9]+)*`。它们不按租户隔离。`WebsiteLayout#instantiate_sections` 调用 `Websites::Skeletons.decorate_sections`。存在对应 I18n 键时，显示名优先用 `website.layouts.<key>.name` 与 `website.skeletons.<key>.name`。

`Websites::Skeletons::KEYS` 列出起步组合（`presence`、`saas_landing`、`cinematic`、`editorial`、`studio`、`product`、`ledger`、`signal`、`atelier`、`campus`、`gazette`、`lumen`、`monograph`、`terrain`、`supper`、`clinic`、`folio`、`voyage`、`kinetic`、`voltage`、`wellspring`、`summit`、`manor`、`bloom`、`roast`、`atrium`、`canvas`、`harbor`、`calm`、`marque`、`tempo`、`quarterly`）。每个组合位于 `app/services/websites/skeletons/<key>.rb`，借鉴一家知名网站的页面范式；参考对象写在 `website.skeletons.<key>.inspired_by`，骨架图库和编辑器中显示为“灵感源自……”。品牌与文案均为虚构。`CATEGORY_BY_KEY` 为每个键指定图库分类。骨架内的站内链接只指向同一骨架的 slug，且每个骨架恰有一个首页。`pages_for` 优先取有效的 `WebsiteSkeleton` 行，否则用 Ruby 种子 `PAGES`。`apply!` 创建 `WebsitePage`；首页的 slug 为空。

`Websites::SectionKit::TYPES` 是分区词汇（`announcement`、`hero_cinematic`、`hero_split`、`hero_centered`、`product_spotlight`、`image_banner`、`ai_preview`、`statement`、`proof_strip`、`metrics`、`logo_cloud`、`showcase_tiles`、`bento_grid`、`feature_tabs`、`alternating_features`、`feature_grid`、`split_checklist`、`steps`、`timeline`、`card_grid`、`collection_rail`、`story_index`、`gallery`、`team_grid`、`quote`、`testimonials`、`pricing`、`comparison_table`、`price_list`、`listing_grid`、`agenda`、`faq`、`cta_band`、`cta_split`、`rich_text`、`split_image_text`、`contact_info`、`locations`）。每种类型由 `Websites::Sections::<Type>Component` 渲染。较新的范式：

- `showcase_tiles`：通栏产品陈列块，含标题与两个链接；`size` 取 `full` 或 `half`（`TILE_SIZES`），`tone` 取 `light` 或 `dark`。
- `timeline`：竖向时间轴上的纪年里程碑。
- `story_index`：头条加标题列表，适合新闻中心和报纸首页。
- `comparison_table`：最多四列方案（`COMPARISON_COLUMNS`）与功能行；窄屏下横向滚动。
- `listing_grid`：带价格、元信息、评分和角标的图片卡片；`aspect` 取 `square`、`portrait` 或 `landscape`（`ASPECTS`）。
- `agenda`：按时间排列的日程，可带分会场标签。
- `locations`：门店或场馆卡片，含地址、营业时间和链接。

品牌参考分区，各取一家知名网站的标志性版式：

- `announcement`（Vercel / Linear）：纤细胶囊公告，含 `badge`、`body` 与箭头链接（`link_label`、`href`）。
- `product_spotlight`（Apple）：居中展示，下接带边框的大图 `image_url`，再列至多四项 `specs`（`{ value, label }`）。
- `image_banner`（Nike / Patagonia）：通栏大图，遮罩上叠白色文案；`height` 为 `tall` 或 `medium`（`BANNER_HEIGHTS`），`placement` 为 `bottom` 或 `center`（`PLACEMENTS`）。
- `metrics`（Stripe）：至多四组超大 `{ value, label, body }` 数据。
- `feature_tabs`（Linear / Notion）：至多五个 `{ label, title, body, image_url }` 标签页，由 `website_feature_tabs_controller.js` 切换；服务端渲染时首个标签处于激活状态，无 JavaScript 亦可阅读。
- `split_checklist`（Mailchimp / Shopify）：介绍与按钮旁列出至多八项勾选的 `{ title, body }`。
- `collection_rail`（Spotify / Airbnb）：横向吸附滚动的 `{ title, meta, image_url, href }` 卡片行；`aspect` 复用 `ASPECTS`。
- `cta_split`（Airbnb）：收尾面板，图片位于 `image_side`，另一侧为两个按钮。

#### 分区样式覆盖

每个分区在内容之外还接受可选的外观属性。`Websites::SectionFields.style_fields(type)` 列出这些属性，`full_schema_for(type)`（内容 + 样式）是 `PropSchema`、`Contracts::Section`、助手 `SchemaValidator` 及其分区目录提示表共用的 schema；`schema_for` 仅含内容。

| 属性 | 取值（`SectionKit`） | 效果 |
| --- | --- | --- |
| `surface` | `SURFACES`：`default`、`muted`、`contrast`、`accent` | 分区背景带。`contrast` 以反转的明暗外观渲染分区（`Theme#for_surface`）；`muted` 使用 `band_class`；`accent` 为柔和的主题色底。 |
| `spacing` | `SPACINGS`：`default`、`tight`、`roomy` | 通过 `SectionComponent#spacing_class` 覆盖上下留白；通栏类型（`UNSPACED`）不提供。 |
| `align` | `ALIGNS`：`default`、`start`、`center` | 通过 `SectionComponent#header_align` 设置标题对齐；仅限带标题头的类型（`ALIGNABLE`）。 |

空值或未知值按 `default` 处理（`SectionKit.style_value`）。`Websites::PageComponent#section_wrapper` 添加背景带样式与 `data-section-surface`；平台营销展示的专用分区忽略 surface。编辑器中，这些字段以分段控件形式位于分区**设计**面板顶部，从检查器页头的画笔图标打开（平台营销展示下隐藏）。

#### 设计覆盖（`props.styles`）

`styles`（`Websites::SectionStyles::PROP`）是保留属性，用于重设单个分区内各部分的样式，结构为 `{ target => { attribute => value } }`。`SectionStyles.targets_for(type)` 依据 `SectionFields.schema_for` 推导目标：

| 目标 | 类别 | 属性 |
| --- | --- | --- |
| `section` | section | `background`（十六进制）、`heading_font`、`body_font`、`scale` |
| 每个文本字段，如 `headline` | element | `color`、`font`、`size`、`weight`、`italic`、`align` |
| `buttons`（含按钮文案的类型） | buttons | `shape`、`fill`、`text` |
| 每个列表，如 `items` | items | `background`、`text` |
| 列表项内的每个文本字段，如 `items.title` | element | 同 element |

文本字段指链接、图片 URL、按钮文案以外的 string 与 textarea 字段。取值：颜色为主题记号（`COLOR_TOKENS`：`accent`、`ink`、`body`、`muted`、`inverse`；列表项背景用 `BACKGROUND_TOKENS`：`band`、`accent_soft`、`accent`、`ink`、`canvas`）或 `#rrggbb` 十六进制；分区背景仅接受十六进制。字体为 `Websites::Fonts` 的键；`size`／`scale` 为 `xs`、`sm`、`lg`、`xl`、`2xl`；`weight` 为 `regular` 至 `bold`；`italic` 为 `italic`／`normal`；`align` 为 `start`／`center`／`end`；`shape` 为 `pill`／`rounded`／`square`。空值表示「沿用主题」，构建器不会写入。

`PropSchema` 合并 `SectionStyles.json_schema(type)`（不允许未知目标或属性），`Contracts::Section` 再用 `SectionStyles.valid_value?` 逐值复核，未经校验的 CSS 文本不会进入模板。助手的 `SchemaValidator` 只保留清洗后的样式。

`Websites::StyleResolver` 把校验后的值转成内联 CSS。模板用 `SectionComponent#el_attrs(target)` 与 `#item_attrs(array)` 标记可设样式的节点，输出 `data-site-el` 与解析后的 `style`；`SectionHeaderComponent` 标记 `kicker`／`heading`／`subhead`，`SectionButtonsComponent` 标记 `buttons`。主题记号经 `Theme#color` 解析，随页面主题变化。字号覆盖按比例缩放 `--text-site-*` 变量，响应式层级不变。自定义分区背景按 WCAG 亮度翻转分区明暗（`StyleResolver.section_appearance`），默认文字保持可读；按钮填充色会自动配上对比色文字。平台营销展示的专用分区忽略样式。

以下产品展示分区可供所有网站复用：

- `ai_preview` 归入选择器的 `showcase` 分组。属性为 `kicker`、`heading`、`subhead`、`example_label`、`prompt_label`、`prompt`、`review_note`、`output_label`，以及元素为 `{ title, body, status }` 的 `items`。编辑器与助手的字段定义规定 1–4 项。渲染时省略空的可选标签，列表为空则隐藏成果区域。紫色需求面板与中性色成果卡片在小屏幕上纵向排列；所有有效文案来自 props，装饰图标对辅助技术隐藏，示意区不执行实时 AI 交互。
- `hero_centered.media_mode` 接受 `image` 或 `none`（`MEDIA_MODES`）。未提供或留空时按 `image` 处理，保留图片或占位画框。`none` 渲染紧凑的纯文字主视觉，缩小标题字号与留白；即使存有 `image_url`，也不显示整个媒体画框。
- `pricing.featured_label` 覆盖 `highlight` 为 `featured` 的方案角标文案。未提供或留空时，按请求语言使用 `website.public.pricing.featured`。普通方案不显示角标。

`SectionEditorComponent` 仅将完整的 `primary_label`/`primary_href`、`secondary_label`/`secondary_href`、`button_label`/`button_href` 配对视为按钮。其他标签（包括预览标签和 `featured_label`）仍归入文案字段，并使用各自的翻译标签。`media_mode` 等选择字段归入选项。助手的分区目录表从同一字段定义生成属性、选项及列表数量范围；用途说明涵盖静态预览、纯文字主视觉和推荐角标覆盖规则。

`Websites::SectionFields.schema_for` 描述各类型的字段，供编辑器、AI 提示词和校验共用。`Websites::Contracts::Section` 校验 props，包括上述可选值。`Websites::Theme` 把存储的记号（`APPEARANCES`、`ACCENTS`、`TYPES`、`DENSITIES`、`CORNERS`、`NEUTRALS`）映射到 Tailwind 类和 `<html>` 上的 CSS 变量，不用 `dark:` 媒体查询。`TYPES` 的每一项是一组字体搭配。目录预览按该行配对的预设渲染（`Theme.for_catalog`／`Theme.for_record`）；编排器按 `Theme.for_page` 渲染页面。记号、预设与配对见 [websites](websites)。

`Websites::Media` 用 `images.unsplash.com` 填补空白的库存图片 URL。配图方案取版式键或骨架键中 `_` 之前的前缀。方案可为主视觉、功能、陈列块、文章、列表和门店各自列出图片；未列出的集合回落到该方案的其他场景图，列表项依次循环使用这些 URL。`fill_sections` 按页面记录已放置的图片 id：单图分区（`SINGLE_SLOTS`）的首选图未被使用时才采用，否则按 `SHOT_FALLBACKS` 顺序取第一张未用图；列表先循环未用图，再重复页面上已有的图。只替换空白或图库 URL，自定义图片保持不变。租户上传是另一条路：`Websites::Activities::UploadMedia`（JPEG、PNG、WebP、GIF，最大 8 MB）写入带 `customer_id` 的 `ActiveStorage::Blob`，并返回 `/:customer_id/site/media/:signed_id`。`Websites::AssetsController#show` 只在签名 id 有效且 `blob.customer_id` 与 URL 客户一致时发送文件。

`Websites::Catalog.sync!` 用 Ruby 目录播种布局和骨架行。已有行保留所有者写过的文案；空白媒体从 `Websites::Media` 填入。

当 `media_mode` 为 `none` 时，`Websites::Media.fill("hero_centered", props, palette)` 跳过全部图片填充与替换：缺失的图片键不会补入，已有的空值、图库图片或自定义图片值均原样保留。`fill_sections` 与 `fill_pages` 沿用该行为。媒体模式未提供、留空或为 `image` 时，仍按配图方案正常填充；相邻图片分区照常处理。

### 活动

这些是带 `.call` 和 `Result` 的普通类，不是 `Trailblazer::Activity` 图。

- `Provision`：只创建一次站点；再次调用返回已有行。
- `SaveSite`：`name`、`tagline`、`published`、`theme`、`seo`、`footer`、`default_layout_key`，由 `Websites::Contracts::Site` 校验。`skeleton_key` 不在 `SaveSite::KEYS` 里。
- `ReplaceSkeleton`：销毁该站点的全部页面，运行 `Skeletons.apply!`，并重写 `skeleton_key`、`default_layout_key`、`theme`。
- `SavePage`：`Websites::Contracts::Page`。`structure_editable: false`（租户控制器的默认值）时，已保存页面保留 `layout_key`，`locked_sections` 先按现有分区的 id 和 type 覆盖传入 `props`，再补充媒体。载荷里的新分区 id 会被丢掉。仅改元数据时保留区块；新页面、区块变更及显式 `published: true` 完整校验内容。未修改的无效存量内容仍可取消发布。不能就地把首页改成非首页；设为首页会清空 slug，并取消原来的首页。`DestroyPage` 拒绝删除首页。
- 页面校验、自动 slug 生成、旧首页降级和持久化均在 `PageShortcuts::Collisions.with_customer_lock` 内执行，与快捷路径保存共用写入边界，防止并发网站／快捷路径写入争用同一客户相对路径；写入失败会回滚旧首页降级。写入边界及可信记录编号分派见[页面快捷路径](page-shortcuts)。
- `ReorderPages`：按 `ordered_ids` 重写 `position`，再把未列出的页面接在后面。
- `SaveSkeleton` / `SaveLayout`：写平台目录。
- `UploadMedia`：租户图片上传。
- `ImportMedia`：把已有 blob（AI 助手的附件）复制到租户网站媒体，类型与大小规则同 `UploadMedia`。副本在元数据中记下 `assistant_source_blob_id`，同一来源再次导入时直接返回第一份副本。副本内容由 `Websites::ImageFit.rendition` 在导入时一次生成：长边已达 1920 像素时保留附件原字节，否则按比例放大（最多 4 倍，不裁切、不缩小）；附件本身保持原样。`Websites::FittedPhotoComponent` 完整显示这些照片，空余处用模糊副本铺满。

`Websites::CurrentSite#call_website_activity` 将 `Websites::Activities::<name>` 常量化后调用。

### AI 助手

模型返回 `apply_website` 文档时，[AI 助手](ai-assistant) 通过 `Websites::Assistant::Processor` 写入网站页面。保存前，`Websites::Assistant::SchemaValidator` 按 `SectionKit` 与 `SectionFields` 逐页校验。由于分区列表由助手自行编排，页面以 `structure_editable: true` 经 `SavePage` 保存。新页面都是未发布的草稿，已发布页面不会被修改。上传的照片以 `upload:<attachment id>` 标记引用，经 `ImportMedia` 导入后，以 `/:customer_id/site/media/:signed_id` URL 存进 `sections`，与编排器上传得到的形式相同。管理员可在助手的产物面板中查看草稿，或在页面编辑器中打开，再按常规流程发布。在此之前，只要相关页面之后未被编辑或发布，回复上的「撤销」按钮（`Websites::Assistant::Undo`）即可删除该回复新建的页面，并恢复它修改过的页面。

### 平台官网源码恢复

`Websites::HomeSite` 是**仅限客户 81721200** 使用的可复现官网源码。营销重设计编排五个已发布、可由构建器编辑的公开页面，默认在共享主机上通过 `/` 及简洁 slug 展示（规范 `/81721200/site` 端点继续可用）。主题记号仍为 `light / violet / sans / compact`；分区类型和顺序如下：

| 页面 | 数量 | 已保存源码分区顺序 | 源码用途后缀 |
|---|---:|---|---|
| 首页 | 11 | `hero_centered, proof_strip, logo_cloud, ai_preview, feature_grid, card_grid, feature_grid, split_image_text, steps, faq, cta_band` | `hero, stats, industries, preview, assistant, desktop, capabilities, website, steps, faq, cta` |
| 平台 | 9 | `hero_centered, ai_preview, feature_grid, card_grid, feature_grid, split_image_text, comparison_table, steps, cta_band` | `hero, preview, assistant, desktop, capabilities, website, comparison, steps, cta` |
| 价格 | 5 | `hero_centered, pricing, feature_grid, faq, cta_band` | `hero, plans, foundation, faq, cta` |
| 关于 | 6 | `hero_centered, proof_strip, rich_text, feature_grid, split_image_text, cta_band` | `hero, stats, mission, principles, craft, cta` |
| 联系我们 | 3 | `hero_centered, rich_text, cta_band` | `hero, availability, cta` |

源码 id 为 `home_site_<page>_<role>`；首页的已保存 slug 为空，但页面键为 `home`。id 标识源码用途，不用于选择展示样式。已保存的 `{ id, type, props }` 仍是可编辑的渲染契约。关于页与联系页主视觉使用 `media_mode: "image"` 及内置照片；首页、平台页和价格页使用 `media_mode: "none"`。首页和关于页提供“免费开始构建”及“了解平台”；平台页提供“免费开始构建”及“查看价格”；价格页和联系页的两组主视觉操作均存为空字符串。所有收尾区域均以“免费创建工作空间”链接至注册。

源码文案与图片路径位于配对的 `config/locales/website_home_site.en.yml` 和 `.zh-CN.yml`，命名空间为 `website.home_site.*`。`definition(locale: :en)` 在调用时通过 I18n 返回一份新的确定性哈希，不执行文件系统／网络 IO，也不访问数据库。`apply!(locale: :en)` 显式通过现有活动保存定义，包括导航标题、页脚和 SEO。此前文案更新中的共用标语、SEO、页脚定位及插画翻译键继续保留。不属于已保存属性的装饰文案——首页主视觉角标（“New”／“全新”）、信任条、关于／联系页主视觉标签、图文故事标签、产品示意界面及联系页入口说明——在请求时从 `website.home_site.{hero_badge,trust,hero_chips,story_chips,mockup,contact.routes}` 翻译。

#### 营销文案与关联草稿

文案采用自信、富有感染力的宣传语气。各页主标题均保存有意设置的换行：首页 `Describe your business.\nAI builds the rest.`／`说出你的业务，\n其余交给 AI。`，平台页 `Everything your business runs on.\nOne brilliant workspace.`／`业务所需的一切，\n尽在一个出色的工作空间。`，价格页 `Simple pricing.\nLimitless ambition.`／`定价简单，\n雄心无限。`，关于页 `We build tools for\npeople who build.`／`我们为创造者，\n打造创造的工具。`，联系页 `Let's build something\nremarkable together.`／`携手共创，\n成就非凡。`。不存 HTML，也不新增强调文字属性。专用渲染器逐行转义为块级 span，并以单个换行连接，使标题文本内容与保存值一致；多行标题末行使用紫—品红—天蓝渐变，所有者的单行标题保持白色。目标页面编排器用文本域编辑原有 `headline` 字段，使保存时保留换行。

两大主打功能是 **AI 助手**与**本地托管的 Windows 桌面应用**。首页主视觉眉标（“AI assistant built in · Windows desktop app coming soon”／“内置 AI 助手 · Windows 桌面应用即将推出”）、副标题、信任条（“AI assistant built in”／“内置 AI 助手”）、SEO 及页脚简介均同时点明二者。首页依次呈现主视觉与产品示意界面、四项数据条、行业滚动条、关联草稿示意、六卡 AI 助手展示区（`home_site_home_assistant`）、即将推出的 Windows 面板、能力索引、单幅网站故事、三步流程、五个常见问题（含“AI 助手能做什么？”）和收尾区域。平台页通过会员示例展开同一助手展示区与 Windows 面板，随后为能力、网站故事、“Anysys”与“常见的拼凑方案”的七行对比（含“托管在自己的电脑上”→“即将推出”）及流程。两页共用同一份 `website.home_site.assistant` 定义，与共用 Windows 面板的方式一致。价格页紧接方案保留 `home_site_pricing_foundation`（“More than a plan. A complete, connected workspace.”／“不止一个方案，更是完整贯通的工作空间。”），介绍各方案均包含的能力——AI 助手；记录、表单与网站；会员、支付与消息——不表示方案权益。

助手展示区只描述已上线的 [AI 助手](ai-assistant)能力：打字、语音或照片下达需求，并可用 `@` 引用记录；创建带字段、关联与计算值的记录类型，修改已有类型前需确认；基于记录类型生成表单页面；起草最多五个网站页面并安置附带照片；未发布、未编辑的网站草稿可一键撤销；未经管理员操作不发布任何内容；支持中英文，对话可随时续接。不点名任何模型厂商，因为服务商由平台配置。

关于页以照片主视觉和两个操作开篇，随后为数据条、两段使命说明、三项理念，以及作为 `split_image_text` 图文故事、带独立照片的 `home_site_about_craft`。联系页以照片主视觉开篇，随后的渠道说明引导现有客户使用工作空间“帮助”菜单（“在工作空间中打开‘帮助’菜单即可发起支持对话”），最后是下一步入口卡片。首页不展示方案卡片，仅价格页比较方案。

数据条数字（“3”种向助手下达需求的方式、“5 分钟内”从需求到关联草稿、“0”行代码、“100%”的 AI 草稿经你审核、“∞”种塑造方式）及行业列表均为以普通属性保存的营销文案，并非实测指标或客户标志。用于推广前请先核实。

`ai_preview` 继续使用 `kicker`、`heading`、`subhead`、`example_label`、`prompt_label`、`prompt`、`review_note`、`output_label` 及 `items[{title,body,status}]`。两个源码示意区的 kicker／subhead 均为空。共用标签为 “Illustrative example”／“产品示意”、“Your brief”／“你的需求”、“Connected drafts”／“关联草稿”和 “Draft”／“草稿”。审核提示为 “AI proposes. You review the details and decide what goes live.”／“AI 提出方案，由你审核细节、决定何时发布。” 各项正文是两行拟议字段／页面提纲，经转义后保留换行展示，不代表已部署记录、交互表单或可用应用链接。

所有营销文案继续放在配对语言定义中，作为普通可编辑 props 保存。操作文案为 Start building free／免费开始构建、Explore the platform／了解平台、Create your free workspace／免费创建工作空间、See pricing／查看价格。AI 提出可审核的草稿，由用户完善并主动发布。平台页明确限定语音输入需配置语音服务，支付及消息服务也需完成相应配置。源码不虚构客户评价、客户标志、联系方式或实时演示控件。

#### 专用展示与编辑器契约

已实现的前端集成接口为 `Websites::HomeSite::Presentation.for(website:, page:)`，返回展示对象或 nil，提供 `role`、`component_class(type)`、`variant_for(type, id: nil)`、`header_class`、`footer_class`；`matches_page?(page)` 重新校验页面身份，`nav_pages(pages)` 筛选传入的已保存导航。校验后的上下文用于公开展示、同页管理端预览及目标页面编排器。

- 两条实际记录均须满足 `customer_id == HomeSite::CUSTOMER_ID`。有保存身份时，website id 必须非空且 `page.website_id == website.id`；本地化／预览副本即使 `persisted?` 为 false，也遵守此规则。真正未保存的页面必须关联传入的 website 对象。资格不依赖 Current、URL 子串、分区 id 或文案。
- `:home` 仅由 `page.home?` 判定；其他有效 slug 为 `platform`、`pricing`、`about`、`contact`。额外页面和其他客户使用通用分区及导航页脚。显式传入展示对象也不能绕过身份检查。
- `PageComponent` 先检查 `SectionKit.known?`，再选择专用映射类或通用组件。按已保存顺序遍历，保留所有者插入的已知类型，跳过未知类型；不合成分区、不耦合相邻分区、不写记录，也不在读取时恢复源码。
- 公开展示与同页管理端预览传递实际站点／页面上下文、本地化只读副本，以及按已保存顺序筛选的同站点已发布且导航可见页面。联系页收尾按该顺序展示平台／价格入口卡片，最后展示已保存的注册操作。页面标题及注册文案／href 以保存值为准。每卡只有一个链接，配运行时本地化说明及装饰箭头；未发布／导航隐藏的目标、无效／空白注册操作均省略，其余卡片自然重排，不留占位。说明在请求时读取 `website.home_site.contact.routes.{platform,pricing,workspace}`，不新增已保存属性。注册是下一步入口，不代表提交咨询。
- 专用 Header／Footer 和 MobileNavSheet 复用现有语言及 href 辅助方法、已保存的站点名称／页脚与移动导航控制器。桌面导航和抽屉包含运行时翻译的注册操作；抽屉仍放在带模糊效果的吸顶页头旁边。限定范围的 Tailwind 像素字号工具、响应式堆叠布局、原生 FAQ details 和现有媒体方法构成展示层。页头和页脚的品牌标志为 `Branding::SapphireLogoComponent`，与 `/81721200/admin/dashboard` 相同的紫色菱形钻石，以 `h-7` 装饰图形放在已保存的站点名称旁。
- 编辑视图将 `presentation:` 经 Composer → ComposerSections 传至每个 SectionEditor。仅目标页面原有的顶层 `headline` 控件在新建字段定义副本中改为文本域。所有 `[data-prop]` 控件、值及字段键均保留，不修改共用 SectionFields 元数据；通用编辑器继续使用原有控件。

| 已保存类型 | `Websites::HomeSite` 下的专用组件 | 使用的 props／内部变体 |
|---|---|---|
| `hero_centered` | `HeroComponent` | 原有 eyebrow／headline／subhead、媒体与操作配对；首页／平台 `:lead`（渲染 `ProductMockupComponent` 及信任条），价格 `:pricing`，关于 `:about`、联系 `:contact`（照片分栏布局） |
| `proof_strip` | `StatsComponent` | `items[{value,label}]`；`:stats`，一至四列数据条 |
| `logo_cloud` | `MarqueeComponent` | `heading, items[{name}]`；`:marquee`，无缝滚动的行业条，重复的一轮带 `aria-hidden` |
| `comparison_table` | `ComparisonComponent` | `kicker, heading, subhead, column_1..n, rows[{title,value_n}]`；`:comparison`，首个命名列高亮 |
| `ai_preview` | `DraftComponent` | 原有示意标签、需求、审核提示及草稿项 |
| `feature_grid`, `steps` | `IndexComponent` | `kicker, heading, subhead, items[{title,body}]`；能力／理念／foundation／流程变体，以及页面 `home_site_<page>_assistant` 分区专用的 `:assistant`（浅紫便当格：六张卡片在桌面端铺满四列，深色极光首卡与紫—品红渐变末卡各占两列；其他数量使用均分网格） |
| `split_image_text`, `rich_text` | `StoryComponent` | `heading, body`，可选 `image_url, image_side`；`:story`、`:editorial`、`:contact_note`；图文故事最多附加两个取自 `website.home_site.story_chips.<role>` 的装饰标签 |
| `card_grid` | `PerspectiveComponent` | `kicker, heading, subhead, cards[{title,body,image_url,href}]` |
| `pricing` | `PlansComponent` | `kicker, heading, subhead, featured_label, tiers` 及原有价格／功能／操作字段 |
| `faq` | `FaqComponent` | `kicker, heading, items[{question,answer}]`；原生 details |
| `cta_band` | `CtaComponent` | `headline, body, button_label, button_href`；`:closing` 或携带本地化导航上下文的 `:contact_next_steps` |

专用基类接受 `props:, theme:, customer_id:, variant: nil, page_role: nil, nav_pages: []`。变体是内部 Ruby 符号，不是新增的已保存营销属性。空的可选内容、空列表及缺失／无效媒体自然省略；无效 CTA 目标显示普通文案。路由、数据结构、控制器及全局主题沿用现有契约。移动模态导航优化扩展现有 `website_nav_controller.js`，不新增控制器。

所有主视觉均为深色 `bg-slate-950` 舞台，叠加模糊的紫／品红／天蓝极光光斑及错落的淡入上浮动画。首页／平台的 `:lead` 主视觉另含本地化的装饰性 `ProductMockupComponent`（带侧栏、数据卡和记录表的工作空间窗口，对辅助技术呈现为一张带标签的图片；其中 SVG 均带 `aria-hidden` 与 `focusable="false"`）。关于页与联系页主视觉左右分栏，配发光照片画框及浮动标签；移动端先文字后照片。能力面板使用循环渐变图标块；草稿示意、流程轨道、渐变数据、滚动条及对比表沿用同一紫色系。价格页居中主视觉之后为四张等高方案卡；推荐卡置于紫—品红—天蓝渐变边框（`p-0.5`）内，深靛蓝背景配白色文字，桌面端上浮，并带“最受欢迎”角标。foundation 为浅色三卡分区。联系页使用渠道说明面板和三张入口卡。共用收尾为深色品牌背景／白色文字并附信任条，页脚保留已保存栏目及“即将推出”。样式按页面用途和分区类型选择，不以文案或位置选择。唯一与 ID 相关的是助手展示区：`variant_for("feature_grid", id:)` 仅在源码用途 id 恰为 `home_site_<page>_assistant` 时返回 `:assistant`，所有者新增或不透明 id 的功能网格仍沿用页面用途变体。

动画（`animate-marquee`、`animate-float`、`animate-aurora`、`animate-fade-up`）在 `app/assets/tailwind/application.css` 中以 Tailwind v4 `@utility` 声明，因此 `motion-reduce:animate-none` 能够覆盖。减少动态效果时，滚动条停止，列表在视口内换行居中，并移除边缘遮罩。

小屏卡片自然堆叠；三卡组按响应式断点呈现一／二／三列，方案卡在桌面端为四列。两列对比表在手机上保持在视口内（图标与文字上下堆叠、内边距收窄、高亮列标题不显示标志），仅在超过两列时横向滚动。320／390／768／1024／1440 px 及 200% 缩放下，保持至少 44 px 操作目标、清晰正文、可见焦点与足够对比度。装饰图形／图标不参与交互，对无障碍树隐藏，不新增图片赋值、客户评价或产品控件。已保存的分区顺序及所有者编辑的 props 始终为准。

#### 原生移动导航与验证

`Websites::HomeSite::MobileNavSheetComponent` 在页头旁渲染原生 `<dialog>`。透明对话框覆盖整个视口；内部抽屉靠右，宽度为 `min(20rem,88vw)`，导航区域可滚动。已保存的站点名称通过 `aria-labelledby` 提供标题，翻译后的关闭按钮带 `autofocus`。已发布的导航页面与注册入口仍是携带语言参数的普通链接。通用 `Websites::MobileNavSheetComponent` 继续使用 div 面板与独立遮罩。

共用 `website-nav` 控制器识别支持 `showModal`／`close` 的 DIALOG，在浏览器模态顶层打开，并同步触发按钮的 `aria-expanded` 与翻译标签值。原生模态焦点首先落在关闭按钮，背景控件不可交互，程序调用也无法将焦点移至背景。Tab／Shift+Tab 不进入背景控件；顺序导航到边界时，焦点可转至浏览器界面，不使用手写焦点陷阱。Escape 触发原生 `cancel`；`cancel->website-nav#close:prevent` 经控制器清理状态和滚动锁，避免文档 keydown 再次关闭。关闭按钮及直接命中透明 dialog 本体的点击会关闭；抽屉内部点击不触发遮罩关闭。

打开时锁定 `<html>` 并保存原有内联 overflow 值；关闭时恢复该值，并在触发按钮可见时将焦点归还。视口调整至桌面断点（1024 px）会关闭并解锁，较窄尺寸变化则保持打开。断开连接时移除全局监听器；即使 Stimulus targets 已不可用，也通过保留的原生 dialog 引用关闭并解锁根元素，防止背景持续无法交互。非 dialog 面板沿用显隐切换、遮罩关闭和文档 keydown Escape 行为。

`spec/javascript/controllers/website_nav_controller.test.js` 的单元验证契约要求 `npx vitest run --coverage` 达到**行、分支、函数均 100%**，覆盖原生 API／状态／清理及通用面板行为。模拟 dialog API 仅验证打开状态，不代表浏览器焦点保证。`spec/e2e/website_native_dialog.app.spec.js` 通过 Playwright 访问 `APP_BASE_URL`：在 EN／zh-CN、320／390／768 px 下验证真实 `:modal` 状态、关闭按钮自动聚焦、背景拒绝焦点、顺序 Tab／Shift+Tab 及 Escape／焦点归还；另覆盖仅遮罩本体关闭、内部点击保持打开、关闭按钮、桌面尺寸变化，以及控制器断开后恢复背景交互。浏览器规格允许原生 Tab 转至浏览器界面的边界行为，并阻止非 GET／HEAD 请求。

#### 发布评审后的视觉优化

应用的 `text-base/sm/xs/lg/xl/2xl` 是管理端紧凑字号，并非 Tailwind 标准字号。因此，专用营销展示使用明确的像素字号：正文／操作 16 px，导语及卡片标题 18 px，辅助／导航／页脚文案 14 px，角标／版权 12 px，品牌名称 20 px，紧凑分区标题 24 px。价格页参考说明使用清晰的 16 px 正文。常规宽度下，主视觉标题为 36–66 px（`:lead` 主视觉在桌面端达 84 px），分区标题为 30–52 px。主视觉及深色收尾标题显式使用 `text-white`；不调整全局字号或主题记号。

容器继续保持 1280 px，移动端边距为 20 px。首页、平台、价格、关于与联系页共用该容器的内容宽度：主视觉文案、分区导语、卡片栅格、常见问题条目、编辑正文列、联系页入口卡片和收尾条带左右边界一致。常见问题标题位于列表上方，条目因此与方案卡、能力卡及收尾条带对齐。主视觉为通栏深色舞台，内容仍限定在该容器内；数据条为白底，配渐变数字及桌面端分隔线；浅色分区与页脚使用相同内容宽度。页头底部分隔线与内容列同宽。主要分区及收尾使用 `py-16 lg:py-24`，数据条 `py-14 lg:py-20`，滚动条 `py-12 lg:py-14`。草稿面板和页脚收紧内边距；方案卡片采用 `gap-4`，移动端简介按内容自然增高，额度明细为 14 px、行高 20 px、间隔 6 px。页脚在 380 px 起为三列、280 px 起为两列，更窄时单列；每个链接至少为 44×44 px。低于 280 CSS 像素时，页头完整品牌名称独占首行，控件可换行且高度自适应；标题／价格字号适当降低，嵌套面板减小内边距，通过 `min-w-0`／`overflow-wrap:anywhere` 重排，不隐藏内容。

专用原生 details 语言菜单在常规宽度下保持 `right-0`。低于 280 CSS 像素时，`max-[280px]:-right-12` 补偿相邻的 44 px 菜单按钮及 4 px 间隔，使受视口约束的面板保留两侧 20 px 边距，完整显示语言名称，并支持键盘访问 GET 链接。原生抽屉的标题／关闭行在低于 240 px 时使用 12 px 边距，240 px 起为 20 px，`sm` 起为 32 px，使平板关闭按钮与页头触发按钮对齐。`spec/e2e/website_language_popup.app.spec.js` 在两种语言、150／160／195 CSS 像素下检查打开菜单的面板、链接及文字边界，并验证键盘切换语言，同时阻止非 GET／HEAD 请求；现有平板响应式测试覆盖关闭／触发按钮对齐。

价格页主视觉副标题承载参考说明：**“Start free and upgrade only when you're ready to grow. Reference monthly prices in USD — plans, trials, currency and charges are confirmed in workspace billing.”／“免费起步，准备好增长时再升级。以下为美元月度参考价格，具体方案、试用、币种与费用以工作空间账单为准。”** 主视觉底部加大留白，使方案卡上移叠压在深色主视觉上。仅更新文案叶节点无法新增数据条、滚动条、对比表或照片；本次重设计须在重新比对内容／媒体后显式应用结构。重建资源后，发布环节须重新截图，验证首屏、按内容自然增高的页面长度及缩放重排。

#### 随应用发布的照片与插画

重设计使用 `public/site-images/anysys/` 下六张内置 **WebP 照片**，通过 `/site-images/anysys/anysys-photo-<name>.webp` 提供，两种语言共用路径：

| 照片 | 默认用途 |
|---|---|
| `anysys-photo-studio-owner.webp` | 首页网站故事 |
| `anysys-photo-team-collab.webp` | 平台页网站故事 |
| `anysys-photo-desktop-night.webp` | 首页与平台页 Windows 面板 |
| `anysys-photo-about-team.webp` | 关于页主视觉 |
| `anysys-photo-craft.webp` | 关于页 craft 图文故事 |
| `anysys-photo-contact.webp` | 联系页主视觉 |

`Websites::Href.media?` 通过 `Websites::Href::BUNDLED_PHOTO_PATH`（`/site-images/anysys/anysys-photo-[a-z0-9-]+.webp`，完整匹配，不带查询参数或片段）接受这些照片。`SectionComponent#valid_media?` 另外要求文件存在于 `public/` 下；照片缺失时省略画框，不显示破图。照片以原生 `<img>` 渲染，不经 `IllustrationComponent`。

源码共有 **11 处图片赋值／6 张不同照片**：网站故事、关于页主视觉、关于页 craft 和联系页主视觉各一张；两个 Windows 面板在各自三个 `cards[*].image_url` 字段中显式重复 `anysys-photo-desktop-night.webp`，防止 `Media.fill` 将空白卡片图片填为图库照片。全部卡片 href 为空。foundation、能力、助手展示区、理念、流程、数据条、滚动条、对比表及首页／平台／价格主视觉均无配图。

专用前端的默认预算为 **7 处实际展示**：首页 2、平台 2、价格 0、关于 2、联系 1。每个 Windows 面板仅显示第一幅重复图片。图文故事、面板及分栏主视觉使用 4:3 画框；主视觉图片即时加载。Windows 后续卡片中不同的所有者上传／HTTPS 图片仍作为有意义的补充媒体保留。默认预算不限制自定义内容。

全部 **15 个**原创 SVG 插画仍保留在 `public/site-images/anysys/`，通过 `/site-images/anysys/<filename>.svg` 提供，但重设计默认不再赋值，所有者仍可选用。静态底图不含文字、脚本、外部资源、嵌入文本或转为轮廓的字形。上传／导入仍接受 JPEG、PNG、WebP、GIF（最大 8 MB），不接受 SVG。资源安全检查覆盖所有文件。

| SVG 文件名 | 画中标签（zh-CN） |
|---|---|
| `anysys-home-workspace-hero.svg` | 记录；网站 |
| `anysys-platform-workspace-hero.svg` | 记录 |
| `anysys-pricing-growth-hero.svg` | 套餐 |
| `anysys-about-idea-hero.svg` | 想法 |
| `anysys-contact-conversation-hero.svg` | 想法；目标 |
| `anysys-ai-draft.svg` | 草稿 |
| `anysys-website-draft.svg` | 草稿 |
| `anysys-brand-studio.svg` | 主题 |
| `anysys-review-publish.svg` | 预览 |
| `anysys-records-forms.svg` | 记录；表单 |
| `anysys-members-payments.svg` | 会员；支付 |
| `anysys-email-sms.svg` | 邮件；短信 |
| `anysys-local-desktop.svg` | 本地数据 |
| `anysys-record-control.svg` | 记录 |
| `anysys-local-privacy.svg` | 本地数据 |

通过 `Href.media?` 校验后，`SectionComponent#render_media` 仅在路径精确匹配完整的 15 场景映射时选择 `IllustrationComponent.new(src:, alt:, css_class:, eager: false)`。HTTPS 图片及上传继续使用原生图片或 `FittedPhotoComponent`。渲染不读取或内联所有者提供的 SVG。组合画框根据原始 viewBox 和居中裁切，对齐原生 `<img>` 与 SVG 铭牌覆盖层；已保存的 src／alt、加载方式和 `decoding="async"` 均保留。覆盖层无交互，带 `aria-hidden="true"`、`focusable="false"`；原生图片是唯一的图片无障碍节点，必要信息由相邻 HTML 和替代文本提供。

全部 15 个覆盖层定义及 **20 个标签**继续保留。元数据存放稳定 I18n 键，每次请求翻译并转义，包括 `website.home_site.illustration.local_data`（“Local data”／“本地数据”）、`.idea`（“Idea”／“想法”）、`.goals`（“Goals”／“目标”）及 `preview.draft`。标签独立于已保存文案／顺序，不新增实时状态、价格或隐私保证。覆盖层渲染不写记录、不播种、不恢复源码。

#### 本地化与已保存内容

`HomeSiteLocalization` 为客户 81721200 创建只读 Website／WebsitePage 副本。当前英文／中文源码定义提供精确匹配的翻译，覆盖页面／导航标题、分区叶节点、标语、页脚及 SEO。页面按已保存 slug 匹配；分区按类型和稳定源码 id 匹配，保留的旧 id 可回退到同类型内无歧义的文案匹配。嵌套列表按字段路径和源码文本匹配，不按下标。翻译冲突及不同于两种源码的所有者文案保持原文。id、URL、控制值、主题、已保存顺序、新增／删除项及标记均不改写。

符合专用展示条件的管理端预览在控制器套用 POST 草稿后，将上述只读副本赋给视图的 `@website` 和 `@page`。因此，普通预览与嵌入式预览的文档布局均使用本地化的页面标题、SEO 标题和元描述，所有者自定义文案仍保持原文。渲染不写入记录；其他租户及不符合条件的页面继续沿用原有元数据行为。

**部署源码文件不会更新已保存的旧文案或组合。** 旧版文本若不匹配当前任一种源码语言，则继续按原文显示。结构调整通过显式应用更新已保存内容；此前仅替换文案叶节点的脚本不能调整分区组合。构建器编辑已保存字符串；专用管理端预览契约与公开展示一样，仅本地化内存副本，两条路径均不保存或恢复内容。

原生语言切换 GET 链接保留完整可访问语言名称。请求显式选择有效语言，或语言不同于默认值时，`PublicComponent#href_for` 将语言传至首页／导航、分区／页脚操作及注册入口，因此显式英文能覆盖旧中文 Cookie。Addressable 只合并一次参数，保留其他查询值和片段；外部 HTTPS 目标／媒体保持原样，已保存 URL 不改写。

#### 显式结构应用与身份保留

```ruby
# 预览任一种源码语言，不写数据库：
Websites::HomeSite.definition(locale: :en)
Websites::HomeSite.definition(locale: :"zh-CN")

# 内容／媒体评审后，显式执行完整恢复：
Websites::HomeSite.apply!(locale: :en)
```

`apply!` 也接受 `locale: :"zh-CN"`，不接受 `customer_id:`。平台客户与已启用的全局网站模块须事先存在。模块缺失／停用错误不会启用或注册模块，也不会修改全局配置；`Current.customer` 不改变目标。

客户锁在一个事务中覆盖站点保存、分配启用、开通及五个页面保存。`SaveSite` 在开通前创建缺失站点，避免生成起步页面；分配配置保持原样。每页通过 `SavePage(..., structure_editable: true)` 校验。**完整源码恢复会有意重置**五个源码页面的文案、结构、源码顺序、发布／导航标记及源码站点元数据／主题。Website／WebsitePage 行身份、现有站点骨架／默认布局及页面布局键保留；缺失的源码页面会重建。额外页面的完整内容、标记及位置保持不变，其他租户与媒体 blob 不被修改。后续任一校验失败，整次恢复回滚。

分区 ID 保留限定在当前页面内，不依赖位置或文案：

1. 先保留所有精确源码 ID 匹配，包括已改变类型的分区；再在任何类型回退前保留匹配的语义源码用途。用途提取仅接受带已知页面前缀的实际 `home_site_<page>_<role>` id；任意所有者／不透明 id 的后缀不作为语义依据。
2. 不同或已移除用途的已知源码 ID，不能仅因类型相同而被其他用途借用。首页 `home_site_home_website` 在 `bento_grid` → `split_image_text` 后保留，`home_site_home_hero` 在 `hero_cinematic` → `hero_centered` 后保留。关于页 `home_site_about_craft` 在 `rich_text` → `split_image_text` 后保留，不占用 mission 身份。新增用途（`home_site_home_stats`、`home_site_home_industries`、`home_site_home_assistant`、`home_site_platform_assistant`、`home_site_platform_comparison`、`home_site_about_stats`）使用各自源码 id；原有方案／foundation／FAQ／CTA ID 保留映射。
3. 仅剩余且无歧义的不透明前身可按当前类型或明确的旧类型回退：首页电影感主视觉／网站拼贴、平台能力拼贴／交错流程、关于理念拼贴／craft 富文本。该类型必须只有一个候选及一个剩余用途。关于页两处未匹配富文本用途不能猜测同一不透明富文本前身的归属。有歧义时采用稳定源码 id，在应用报告中记录以供评审。
4. 每个前身 id 只使用一次。源码 ID 预留，不参与类型回退；空 id 排除，重复旧 id 不会在结果中出现两次。重复应用保持 id 唯一且结果确定。

对于已评审的现有站点，发布／内容操作必须：

1. 写入前导出站点元数据、五个源码页面、额外页面快照、分区用途／id 及全部自定义媒体引用，对照备份核对有意重置和移除区域。
2. 显式应用已批准源码，并在同一个外层事务中通过 SavePage 迁移已评审的自定义媒体。映射保留的网站／桌面／关于／联系用途；默认照片取代此前的 SVG 赋值，自定义图片须明确指定已评审的去向。应用前解决媒体映射歧义；保留 blob、布局键，在报告中记录已移除区域的引用。
3. 报告应用前后用途／ID／媒体映射及有意重置／移除项。核对源码默认值、无新增图库照片、站点／页面 ID 稳定、分区 ID 唯一，以及额外页面／其他租户未变。重复应用检查应在规格／可丢弃数据中执行，不要覆盖已评审的线上自定义媒体。
4. 以两种语言预览已保存内容，验证构建器多行保存／重载、联系页按发布状态提供链接、响应式页面长度及七处默认配图预算。仅检查源码哈希不能证明线上外观。

`db:seed` 仅在客户 81721200 存在且 Website 缺失时恢复。已有站点、所有者编辑及个别缺失页面保持原样。迁移或公开读取不会自动应用重设计。

#### 方案参考与可用状态限定

仅价格页从 `Billing::StandardPlans::CATALOG` 生成方案，首页不展示。所有价格、page／entity／member 额度及试用期均取自该目录，沿用现有带插值的 I18n 额度／试用键。两种请求语言都展示美元，不按语言切换币种。

| 方案 | 美元／月 | 页面构建器页面 | 自定义记录类型 | 会员席位 | 试用 |
|---|---:|---:|---:|---:|---|
| Free | $0 | 10 | 5 | 1 | 无 |
| Starter | $29 | 50 | 25 | 5 | 14 天 |
| Pro | $99 | 500 | 200 | 25 | 14 天 |
| Enterprise | $499 | 不限 | 不限 | 不限 | 14 天 |

可见主视觉副标题说明价格为美元月度参考价，以工作空间账单为准。方案分区的 kicker／heading／subhead 均为空，卡片紧接主视觉展示。方案名称为 Free／免费版、Starter／入门版、Pro／专业版、Enterprise／企业版，各配一句宣传简介；Starter 为 `highlight: "featured"`，带“Most popular”／“最受欢迎”角标。四个 CTA 文案均为“Start building free”／“免费开始构建”，仅链接 `/auth/sign_up`，不携带方案参数，不表示已选方案或购买。

免费／试用数字仅为参考资料。实际账单计 Page／表单而非 WebsitePage 营销页，计实体定义而非记录，计 member 账户而非 admin。受理套餐／币种／试用／限额以工作空间账单为准，HomeSite 不读取／更新实际方案，也不在读取时创建种子。源码 FAQ 仍写管理员计数，与已执行会员计数不同，见下文说明。

Windows 面板（“Windows desktop app · Coming soon”／“Windows 桌面应用 · 即将推出”）、首页主视觉、SEO 描述、平台页对比行及页脚凡提及桌面应用，均明确标注**即将推出**。共用面板说明即将推出应用可在客户自管的 Windows 电脑上本地部署、记录掌控，以及旨在让本地部署记录对 Anysys 保持私密的设计。首页常见问题明确表示目前不提供下载，并说明 AI 连接、外部服务及备份详情将在发布前提供，不承诺离线能力、发布日期，也不提供下载或候补登记。联系页引导现有客户通过工作空间“帮助”菜单发起支持对话，引导新访客注册；不收集咨询，不虚构邮箱、电话或地址。收尾提供已发布的平台／价格导航与注册入口。

### 控制器

`FeatureModules::Website::Registration` 的 key 是 `"website"`。条目路径、模块卡片、模块侧栏及「内容 → 网站页面」快捷入口均指向 `/:customer_id/admin/modules/website`。列表、新建页和编辑器在顶部菜单选中「内容 → 网站页面」，记录侧栏仍归属模块；表单侧栏只列出表单记录。仅当网址所指客户的「网站」模块可用时才显示网站页面入口。设置指向 `/:customer_id/admin/settings/modules/website`。`entries_for("pages")` 列出 `WebsitePage.for_current_customer`。列表每行显示由 `PageShortcuts::PublicPath.website_page` 解析的公开地址（叠加 `SCRIPT_NAME`），与编辑器所示一致；例如客户 81721200 显示 `/` 与 `/pricing`，而非 `/81721200/site` 与 `/81721200/site/pricing`。

`Admin::Modules::Website::PagesController#index` 在 `/admin/modules/website` 与 `/admin/modules/website/pages` 渲染列表；`/admin/pages/website` 不再指向网站操作（通用页面的展示路由对该 id 返回 404）。`Admin::Modules::Website::BaseController` 在 `FeatureModules::Website::Registration.enabled_for?(current_customer_id)` 为假时返回 404。角色检查留在 `RouteAuthorization`：这些 admin URL 面向 `admin` 或 `owner`。平台目录在 `/admin/maintenance/platform/` 下，只面向 `platform_owner?`。

`Admin::Modules::Website::PagesController` 经 `SavePage` 创建和更新。请求头 `X-Website-Composer: 1` 得到 JSON `{ ok: true }` 或 422。`preview` 把 POST 正文里的分区套到内存中的页面上（`apply_draft_preview`），并用布局 `website` 渲染。`reorder` 调用 `ReorderPages`，`destroy` 调用 `DestroyPage`；排序或删除后返回模块列表。

`MediaController#create` 直接调用 `UploadMedia`，返回 `{ url }` 或 422。网站发布由 `Admin::Settings::Modules::Website::SitesController#update` 保存 `website[published]`；`/admin/modules/website/publication` 不再有路由。

`Admin::Settings::Modules::Website::SitesController` 更新站点，包括发布开关。`SkeletonsController#create` 用 `skeleton_key` 调用 `ReplaceSkeleton`。更换骨架会删掉当前页面。网站页面的状态栏只展示站点状态与页面数，不再提供站点设置或发布操作。

平台侧：`Admin::Maintenance::Platform::Website::SkeletonsController`（`show`、`edit`、`update`、`preview`）和 `LayoutsController`（`index`、`new`、`create`、`edit`、`update`、`preview`）。索引或展示时都会调用 `Websites::Catalog.sync!`。布局表单以 `structure_locked: false` 渲染 `ComposerComponent`。

`preview`（经 `Websites::CatalogPreview#render_catalog_preview`）以 `website` 布局全尺寸渲染目录条目，套用 `Theme.for_catalog(key)` 主题，顶部为所有者工具栏（`Websites::Admin::CatalogPreviewBarComponent`：返回、名称、页面切换、编辑）。骨架预览接受 `?page=<slug>`（未知 slug 回退到首页），`Websites::Admin::CatalogPreviewNavComponent` 使导航链接留在预览内。`Website` 仅在内存中构建，不写入任何数据。目录卡片在“编辑”旁提供“预览”（新标签页打开）。两条路由均位于仅限所有者的 `/admin/maintenance/platform/` 前缀下。

### 后台界面

新建页（`/:customer_id/admin/modules/website/pages/new`）分两步并排展示。`lg` 及以上，信息卡片固定在版式库旁；`lg` 以下，排在版式库之后。

- 第一步是 `Websites::Admin::LayoutPickerComponent`。它用 `Websites::LayoutFamily.group` 为目录版式分组：站点自己的起步套装排最前，独立版式排最后，归入“通用页面”。`LayoutFamily.of` 把版式键映射到作为其前缀的最长起步键（`saas_*` 映射为 `saas_landing`），其余键为 `standalone`。
- 筛选标签依次为：
  - 推荐：站点的 `default_layout_key` 加上其起步套装的版式。只要非空，即为初始筛选。
  - 全部。
  - `Websites::Skeletons.categories` 中的各分类，外加通用。
- 每张卡片是 `<label>` 内的一个 `website_page[layout_key]` 单选框。缩略图是 `CatalogThumbnailComponent`，以站点自身主题渲染前三个分区。缩略图带 `aria-hidden`，预览部分带 `inert`：读屏软件不会把其中文案读作单选框名称，键盘焦点也会跳过其中的链接。
- 第二步是一张卡片，内含 `PageIdentityComponent`（仅基本信息）、`LayoutSummaryComponent`（名称、说明、分区列表）和提交按钮。

编辑页：

- 页头由页面标题、一枚“已发布／草稿”标记和 `Websites::Admin::PageAddressComponent`（公开路径）组成，右侧为“预览”和“保存”。只有站点和页面都已发布时，路径才变成在新标签页打开的链接。同一路径经 `ComposerComponent` 的 `public_path:` 标注预览框；预览框置于 `bg-canvas` 上，配仅图标的设备切换。
- 锁定工作区的侧栏分两级。默认是纵向大纲（`[data-workspace-outline]`）：先是“页面设置”行，再是每个分区一行，带序号、类型和一行摘要。点选某行即进入该分区（或页面信息）的检查器。
- `ComposerSectionsComponent#step_for` 向 `SectionEditorComponent` 传入 `step: { number:, total:, previous:, next: }`。检查器页头含返回按钮（`website-builder#showOutline`）、类型名（其后以弱化样式内联“X / N”，`data-section-position`；类型说明作为其 `title` 提示）、调用 `website-builder#focusSection` 的上／下“上一个”“下一个”按钮（`data-section-step`）、区块设计入口，以及重置。
- **检查器保持简洁。** 工作区字段块（`[data-field-section]`）之间仅以浅分隔线区分，不显示分组标题；次要控件默认隐藏。使用鼠标（`pointer-fine`）时，以下控件仅在悬停或获得焦点时淡入：字段与列表的设计图标（所在 `group/design` 元素）、列表项的移动／复制／删除工具栏（`group/item`，仅宽面板）、图片的“移除”与链接按钮（`group/media`）、链接字段的“选择页面”（`group/link`）。富文本提示仅在该字段获得焦点时显示。触屏设备始终显示全部控件；已展开（`aria-expanded`）或已修改（`data-edited`）的图标保持可见。
- **设计入口紧邻各元素。** `SectionEditorComponent` 为每个元素构建一个 `StylePanelComponent`；`FieldHeaderComponent` 在标签行最右侧渲染其 `StyleTriggerComponent`（画笔图标，`reveal: true`）：每个文本字段（`field_design`）、第一个按钮文字字段（共享的 `buttons` 目标）、每个列表标题（`list_design`：`items` 目标及各列表项文本字段，每项一个折叠行，位于添加按钮之后）。区块设计入口（`section_design`）位于检查器页头且始终可见，其面板直接展开于页头下方。所有图标尺寸一致（`size-7`，触屏 `size-9`）；元素已有覆盖时显示强调色圆点（`data-edited`）。`FieldHeaderComponent` 统一各标签行最小高度，使图标纵向对齐。
- 每个面板是元素下方默认隐藏的内联卡片，含目标名称、「重置设计」（仅重置本面板；重置内容不影响样式）与关闭按钮。分区面板还包含 `SectionFields.style_fields` 的 `surface`、`spacing`、`align` 分段控件，其后是「自定义背景」、字体与文字比例。颜色使用 `StyleColorFieldComponent`：主题默认色块、按页面主题真实颜色绘制的主题记号、16 色调色板，以及自定义取色器。字号、斜体、对齐与按钮形状为分段控件；字体与字重为下拉框。平台官网专用展示不显示设计面板。布局与骨架编辑器（非工作区编辑器）使用相同面板，分区图标位于各分区的摘要行。
- 页面设置含「主题」下拉框（`website_page[theme_key]`；平台版式为 `website_layout[theme_key]`），说明见 [websites](websites)。
- 未锁定的编辑器（平台目录）没有步进导航。

### Stimulus

`website_builder_controller.js`（`website-builder`）让 `website_page[sections_json]` 与可排序分区列表保持一致（除非 `structureLockedValue`，否则使用 SortableJS），重新加载预览 iframe，把图片上传到 `uploadUrl`，并在设为新首页前确认。目标包括 `list`、`row`、`json`、`previewFrame`、`previewStage`。服务器通过 Stimulus value 传入文案。锁定工作区中，`focusSection` 把侧栏切到检查器一级，并把 `[data-workspace-inspector]` 滚回顶部；`showOutline` 返回大纲并聚焦刚编辑分区的行；`focusIdentity` 打开页面设置。若点击来自 `data-section-step` 按钮，焦点也会移到对应的分区标签，因为被点击的按钮此时已隐藏。AJAX 保存后检查器保持打开。

设计控件位于 `[data-style-target]` 分组内，使用 `data-style-prop` 而非 `data-prop`；`#propsFromRow` 把已勾选或已选择的非空值并入 `props.styles`，全部为空时省略该键。每个 `[data-style-panel]` 初始为 `hidden`；`toggleStyle` 按所点按钮的 `aria-controls` 打开或关闭面板，同步其 `[data-style-trigger]` 的 `aria-expanded`，展开外层折叠的 `<details>`，从面板内关闭时把焦点还给图标。`pickStyleColor` 把取色器的值写入同组的自定义单选项，`resetStyles` 把所在面板的设计控件恢复为主题默认，`markDirty` 同步列表折叠行圆点与图标的 `data-edited` 标记。每次预览加载后，`#bindPreviewPicking` 在同源 iframe 文档上添加一次捕获阶段的点击监听：点击 `[data-site-el]` 节点会打开该分区检查器，打开对应的设计面板（及列表折叠行）并聚焦首个控件，同时以 `highlightColorValue` 描边该节点。点击未标记的节点或没有设计分组的目标时，事件照常传递。

实时预览 POST 携带当前完整表单，但不写入记录。每次内容编辑立即使先前的预览响应失效，防抖等待期间也如此。只有当前修订的响应可以替换 iframe 或结束其加载状态，较慢的旧响应不能恢复未包含全部编辑的草稿。修订计数器仅在 Stimulus `initialize()` 中初始化一次，同一控制器实例重连后继续递增。重新加载已保存预览及控制器断开连接时，会使待处理的草稿 HTML 失效并取消防抖计时器；重连不能让上次连接的响应重新生效，失败状态响应、网络异常及响应正文读取错误也不能干扰当前预览。生命周期单元回归通过真实断开／重连与延迟响应验证该边界，并验证图片上传的独立保护机制在失败及无效 JSON 下仍保留当前操作状态。编排器浏览器回归验证匹配的 POST 成功、区块载荷完全一致、iframe 包含全部已编辑区块，以及重载后恢复已保存值。

源码中，`initialize()` 仅设置一次 `previewRevision = 0`，`connect()` 不重置它。`markDirty()` 调用的 `#scheduleLivePreview` 在防抖前递增修订；`reloadPreview()` 与 `disconnect()` 再次递增并清除计时器。`#pushLivePreview` 在 fetch 前保存修订，读取 HTML 后检查是否仍为当前修订；非成功响应／异常也先检查修订，再调用 `previewLoaded()` 清理。2026-10-12 跟进新增 8 个真实生命周期／上传回归：控制器测试通过 175／0，行、分支、函数均为 100%；已完成的完整 JS 运行通过 6,956／0。准确证据文件见 `docs/audits/2026-10-11-javascript-verification.md`；最终合并 RSpec／Playwright 结果以各执行报告为准。

单个图片字段的预览与列表项缩略图按 `Websites::Href.media?` 的规则一致接受随应用发布的插画与照片：原始值须完整匹配 `/site-images/anysys/anysys-[a-z0-9-]+.svg`（后缀固定为 `.svg`），或内置照片 `/site-images/anysys/anysys-photo-[a-z0-9-]+.webp`（后缀固定为小写 `.webp`），不得带首尾空白、控制字符、反斜杠、路径穿越、嵌套目录、查询参数或片段标识。HTTPS 与租户媒体预览继续沿用原有的首尾空白处理方式。

`website_layout_picker_controller.js`（`website-layout-picker`）驱动新建页的版式库：

- 按筛选标签（`filterValue`：`all`、`suggested` 或分类）和小写的 `data-layout-search` 文本筛选卡片。
- 隐藏筛选后为空的套装分组；无结果时显示空状态和重置按钮。
- 按 `countFormatsValue`（含 `{count}` 的 `{ one, other }` 模板）写入可见数量。
- 把选中卡片的 `data-layout-*` 值写入各 `summary*` 目标。
- 按 Esc 清空搜索。

`website_theme_picker_controller.js` 在设置页预览主题记号（把所选字体搭配、圆角与色调的 CSS 变量写到预览上），按预设的 `data-tokens` JSON 套用整组记号（`applyPreset`），记号偏离已选预设时切换「已自定义」徽标，并驱动“本页导航”的滚动高亮。`xl` 以下，该导航是横向标签条，`revealNav` 会把当前标签滚入可视区，页面本身不会滚动。`website_nav_controller.js` 按上述规则处理专用原生模态导航与通用 div 抽屉，并在桌面尺寸变化／断开连接时清理。打开／关闭标签通过翻译后的 Stimulus value 传入，默认值为英文。

## 需要特别注意

### 路由审计：校验写入与实际字节媒体

`SaveSkeleton`／`SaveLayout` 及目录模型现于补充媒体前校验完整结构。`Contracts::Sections` 检查已知类型、唯一 ID 及 JSONSchemer props 形状／列表上限／选项；骨架须恰有空 slug 首页、唯一合法内页 slug 及已知布局。应用／开通／替换在同一客户锁内、删除前检查全部快捷路径预留。`SavePage` 先重新加载当前范围状态再赋入字段，显式 false 发布及锁定模板合并不再依赖 stale 脏跟踪。HomeSite 源码恢复在重载后显式恢复页面排序。

锁定区块在解析已保存类型前不补充传入类型的媒体：将引用区块的传入类型改为主视觉，不能向引用区块注入图片字段。仅修改元数据时，内容及空模板保持原样；存量内容即使无效，也能在未改动内容的情况下下线。Page 契约的 `validate_sections:` 选项由服务端按新记录、区块脏状态及显式发布决定，提交参数不能关闭校验。

数组越界或缺少必需列表通过 `website.errors.array_count` 返回本地化数量／范围错误；属性形状错误使用 `website.errors.invalid_props`。助手属性校验保留精确字段／数量错误，不追加第二条通用契约错误。测试上传使用按进程划分的目录及明确标记租户的源文件，见[后台任务](background-jobs)。

上传／导入识别实际光栅字节并设置租户／网站媒体身份。公开 AssetsController 执行 MediaPolicy，验证下载大小／MIME，以 nosniff 提供已验证光栅内容，拒绝通用／旧版未分类签名 blob。provisioner 对失败 Result 抛 ProvisioningError。AI 在会话→客户→有序页面锁内检查最新草稿并取得深复制 Undo 状态；撤销在同一写入边界重载来源及检查冲突。见[网站](websites)、[AI 助手](ai-assistant)、[模块框架](module-framework)。

营销参考价格仍为目录美元月付数据，不选择订阅。账单现仅统计 member 角色账户；已有保存／源码 FAQ 将 admin 计为账户的文案已过时，仍待整合。种子套餐仍按月，年付目录由所有者创建，并须匹配支持的账单供应商。见[账单](billing)。

:::note
网站服务／请求／模型／模块钩子及存储隔离的定向组合已通过 572 个用例，零失败，覆盖真实 Disk 存储和 MIME 字节、目录契约、锁定覆盖、过时取消发布及助手校验。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。浏览器结果仍须单独验证。
:::

:::attention
`Websites::Admin::ComposerComponent` 和 `website_builder_controller.js` 编辑的是 `WebsitePage` 分区。它们不写 `Page#configuration`，也不写 `form_settings.flowchart_id`。维护表单留在 [页面构建器](page-builder)。公开表单提交留在 [页面渲染](page-rendering)。
:::

:::attention
`Websites::Activities::SavePage` 默认 `structure_editable: false`。`locked_sections` 保留布局的分区 id 和 type，只替换 `props`。`Admin::Modules::Website::PagesController` 不会传入 `structure_editable: true`。租户编辑视图把 `ComposerComponent` 设为 `structure_locked: true`。新增分区类型属于平台布局或骨架编辑（`SaveLayout`、`SaveSkeleton`），那里的编排器未锁定。租户侧传入 `structure_editable: true` 的调用方只有两个：`Websites::Assistant::Processor`，且只在 `SchemaValidator` 接受整份文档之后；以及 `Websites::Assistant::Undo#revert!`，它只恢复页面在助手回复修改之前的分区。仅限平台客户的 `Websites::HomeSite.apply!` 源码恢复也会显式传入此标记。
:::

:::attention
`ReplaceSkeleton` 在 `Skeletons.apply!(..., replace: true)` 删除旧页前检查结构／冲突。`SaveSite` 仍排除 `skeleton_key`，设置中的骨架 POST 执行替换。
:::

:::attention
`FeatureModules::Website::Provisioner.deprovision` 把 `published` 设为 false。之后 `Websites::PagesController` 返回 404，且不渲染站点名称。`Websites::AssetsController` 仍然要求 `blob.customer_id` 与 URL 一致，即使签名 id 无法猜测。
:::

:::attention
`Websites::NavComponent` 把 `website-nav` 挂在 `contents` 包裹层上，移动抽屉渲染在 `<header>` 旁。通用 fixed div 抽屉必须留在模糊页头之外，否则页头的包含块会将其高度限制为页头高度。专用原生 dialog 也保持同级，但 `showModal()` 将其放入覆盖视口的浏览器顶层。控制器锁定 `<html>` 而非 `<body>`，关闭／断开连接时恢复根元素原有 overflow。布局在 `<html>` 设置 `overflow-x-clip`，仅锁定 body 无法控制视口滚动。
:::

## 关键代码

```ruby
# app/services/feature_modules/website/registration.rb
      def self.module_key         = "website"
      def self.module_name        = "Website"
      def self.module_description = "Customer introduction and marketing website — static pages, no forms"

      def self.provision!(customer)   = Provisioner.call(customer)
      def self.deprovision!(customer) = Provisioner.deprovision(customer)
```

```ruby
# app/models/website.rb
  has_many :pages, -> { order(:position) },
           class_name: "WebsitePage",
           dependent: :destroy,
           inverse_of: :website

  validates :customer_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :skeleton_key, presence: true
```

```ruby
# app/services/websites/activities/save_page.rb
        unless structure_editable
          if page.persisted? && page.layout_key.present?
            attrs.delete(:layout_key)
          elsif page.persisted? && attrs.key?(:sections)
            inferred = Websites::Catalog.infer_layout_key(page.sections)
            if inferred.present?
              attrs[:layout_key] = inferred
            else
              attrs.delete(:layout_key)
            end
          elsif page.persisted?
            attrs.delete(:layout_key)
          else
            attrs[:layout_key] = resolve_layout_key(page, attrs)
          end
          attrs[:sections] = locked_sections(page, attrs) if attrs.key?(:sections) || !page.persisted?
        end

        if attrs.key?(:sections) && (!page.persisted? || attrs[:sections] != page.sections)
          attrs[:sections] = Websites::Skeletons.decorate_sections(attrs[:sections])
        end

        page.assign_attributes(attrs)
        validate_sections = !page.persisted? || page.will_save_change_to_sections? || attrs[:published] == true
        contract = Websites::Contracts::Page.new(page, validate_sections: validate_sections)
```

```ruby
# app/services/websites/activities/replace_skeleton.rb
result = Websites::Activities::ReplaceSkeleton.call(site: site, skeleton_key: key)
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
# app/controllers/concerns/websites/current_site.rb
    def call_website_activity(name, **kwargs)
      "Websites::Activities::#{name}".constantize.call(**kwargs)
    end
```

相关页面：[模块框架](module-framework)、[网站](websites)、[页面构建器](page-builder)、[成员与公开](member-and-public)。
