---
title: "页面构建器"
summary: "维护页面编辑器如何存储表单、发布，并绑定到已编译的流程图。"
---

## 概要

维护页面是一份带版本的表单定义，不是营销站点。`/:customer_id/admin/pages` 下的操作列表将此类记录称为「表单」，标题、侧栏、表格和搜索均使用表单用语。编辑器在 `/:customer_id/admin/maintenance/pages`，共享页面在 `/:customer_id/admin/maintenance/platform/pages`。访客路径是 `GET` 与 `POST /:customer_id/page/:public_uuid`，见 [页面渲染](page-rendering)。网站功能模块是另一套编排器，见 [网站构建器](website-builder)。

`Page` 把身份留在父行（`name`、`description`、`audience_admin`、`audience_member`、`audience_public`、`action_key`、`launched`、`public_uuid`、`content`、`customer_id`），把表单放在版本化属性 `configuration` 上。`reload_definition_from_head!` 从 `Versionable#resolved_current_version` 加载这份 JSON。配置对象需要 `pages`（分区数组，每项含 `fields` 数组）和 `metadata`（`entity_id`、`entity_name`）。编辑器还会写入 `form_settings`、`wizard_settings`、`rules`、`calculations`、`theme`、`captcha`。`form_settings.flowchart_id` 绑定到一份已发布的流程图。客户打不开流程图编辑器，页面仍然记下这个 id。

普通保存时，`PagesController#update` 用 `PageContentGenerator` 写入 `content`。共享页面的租户覆盖只保存 `configuration`，不动父行的 `content` 列。`PageRendering#prepare_page_render` 把表单 action 设为公开 UUID 提交路径，并把 `@content` 设为 `page.generate_content`。

## 流程

```text
page-builder（app/views/admin/maintenance/pages/_editor.html.erb）
        |
        |  PATCH page[configuration] + page[updated_at]
        v
Admin::Maintenance::PagesController#update
        |  客户端戳记过期则 409
        |  租户覆盖：只写 configuration
        |  否则同时 content = generate_content
        v
PageConfigurationContent.store!
        |
        v
PageVersion --> current_version_id
            或 page_customer_heads

发布（共享页面走平台前缀）
        |
        v
Page#launch!   （实体有效、有字段、规则与计算完整）
        |
        v
launched = true

管理端渲染 / 公开 GET
        |
        v
PageRendering#prepare_page_render
        |  @form_action = 公开页面 UUID 提交路径
        |  @content     = page.generate_content
        v
POST /:customer_id/page/:uuid
        |
        v
Pages::PublicSubmission
        |  form_settings.flowchart_id
        |  Pages::SubmissionProcess（Flowchart.accessible.launched）
        v
已编译的 Activity     见 flowchart-runtime
```

预览（`PagePreviewsController`）用 `PageContentGenerator` 渲染提交上来的配置，或使用已存的 `content`。存在 `public_uuid` 时，表单 action 同样是公开提交路径。布局为 `preview`，不要求页面已发布。

## 实现

### 模型

`Page` 引入 `Versionable`（`PageVersion`、`PageConfigurationContent`、快照 `:configuration`、`page_customer_heads`）、`PageVisibility`、`PageEntityBinding`、`PageLaunchLifecycle`、`PageConfigurationHelpers`。软删除状态为 `:inactive`。`name` 仅校验必填与长度（`1..100`），不做唯一性校验，也不生成 `name_slug`，允许多个页面同名。`before_create :assign_public_uuid` 用 `SecureRandom.uuid` 填写 `public_uuid`。`configuration_json` 把缺失的 `rules` 与 `calculations` 补成空数组。

`PageEntityBinding#entity` 按 `metadata["entity_id"]` 查找。共享页面查 `Entity.shared`。客户自有页面查自己的实体加上共享实体。`entity_id=` 把 `entity_id` 和 `entity_name` 写入 metadata。共享页面必须绑定共享实体（`shared_page_binds_shared_entity`）。创建时用 `page[layout_template]` 与 `page[theme_preset]` 调用 `Pages::ConfigurationComposer`；绑定实体能产出字段时，它会填入字段页。配额项是 `"page"`，共享资源创建跳过。

`Page#fields` 展平 `pages[].fields`。`generate_content` 委托给 `PageContentGenerator`，后者把 HTML 输入类型映射到 `FormFields::*Component` 并返回 ERB。`handoff?` 即 `form_settings.after_submit == "handoff"`。验证码开关是 `configuration_json["captcha"]["enabled"]`；实际渲染哪一家由 `Captcha::ProviderSettings.active` 决定。

`PageVisibility::AUDIENCES` 为 `%w[admin member public]`。`visible_to?(audience)` 是精确集合成员判断；未知受众为假。`visible_audiences` 按该顺序返回集合。`Page.for_audience(audience)` 是 SQL 范围。页面至少要有一个受众（`page_audiences_blank`）。`pages.action_key` 可空，须匹配 `/\A[a-z][a-z0-9_]{1,62}\z/`（`page_action_key_invalid`）；空白存为 nil。`Pages::VisibilityContract` 提交 `page[visible_audiences][]` 与 `page[action_key]`，映射到三个布尔列；已上线页面新增受众或改标识时，重新运行下拉列表、必填字段、`audience_errors` 与 `action_errors`。保存时持有 `Customer.lock.find(page.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)`，两次并发上线不能同时占同一操作槽。见[受众流程](audience-flows)。

`launch_errors` 非空时 `Page#launch!` 抛出 `ActiveRecord::RecordInvalid`：绑定实体必须处于有效状态，`fields` 不能为空，规则的条件与动作 id 必须仍存在，计算的 `target_field_id` 也必须仍存在，并通过“上线检查”中的各项检查。`take_offline!` 把 `launched` 设为 false。`PageLaunchesController` 与 `PageVisibilitiesController` 都调用 `guard_shared_global_writes`，因此共享页面的发布、下线、改可见范围只能在平台前缀上做。

### 上线检查

`launch_errors` 还会运行 `Pages::LaunchChecks`。它通过 `Page#input_fields`（分栏展开）读取字段，针对 `visible_audiences` 中的每个受众，按租户当前的实体定义检查：

- **下拉列表。** `entity_entries` 字段的目标实体不存在或已在回收站时，阻止上线（`reference_target_inactive`）；显示字段无法为某个受众作选项标签时，同样阻止上线（`reference_label_hidden`，消息中写明受众）。
- **必填字段。** 带有 `presence` 或 `acceptance` 校验、且该校验适用于某受众（`EntityAttributeAudience.applying_audiences`）的属性，表单上必须有对应字段（`required_field_missing`）。实体自身的属性按 `property_slug` 匹配来源既非 `base_model`、`bridge` 也非 `identity` 的字段。表单上至少有一个字段的关联实体，按其 `source_section`（关联的 ID 或名称）检查，跳过指回本实体的引用（`required_link_field_missing`）。计算字段和汇总字段不计入；默认值不能满足检查，因为提交不会应用默认值。会员受众下归属引用豁免（`owner_filled_for?`）：`FormParams` 隐藏它，提交边界负责填写。
- **归属受众。** `LaunchChecks#audience_errors` 在上线时运行，也在已上线页面新增受众时运行。绑定归属桥接的页面只能面向会员（`bridge_page_member_only`：「关联实体的表单仅限会员使用」）。绑定 `owned` 或 `private` 实体的页面，或带有已填写的归属／私有桥接分区的页面，不得包含公开受众（`owned_entity_public_audience`，`%{entity}`：「%{entity}记录归属于会员，公开访客无法提交此表单」）。仅管理员、或管理员加会员的集合允许。目标为 `person`、`owned` 或 `private` 的引用出现在含公开受众的页面上，或目标为 `private` 的引用出现在含会员受众的页面上，失败为 `reference_private_for_audience`（`%{field}`、`%{target}`、`%{audience}`：「%{field}：%{audience}看不到%{target}记录，下拉列表将为空」）。指向开放实体的引用对所有受众通过。受众是精确的 `Page#visible_audiences` 集合。
- **操作槽。** `LaunchChecks#action_errors` 拒绝同一所有者下第二个已上线、同 `action_key` 与受众的页面（`action_audience_taken`，`%{audience}`、`%{action}`：「操作 %{action} 已有面向%{audience}的上线表单」）。租户页与共享页可以共用标识，解析时租户页优先。页面下线后槽位释放。回收站中的页面保留上线状态，槽位被其他上线页面占用时，恢复会以同一消息被拒绝。
- **身份字段。** `LaunchChecks#identity_errors` 在任一 `source: "identity"` 字段出现在非人员实体页面上时失败为 `identity_field_not_person`（`maint_core.errors.page_launch.identity_field_not_person`：「姓名和邮箱字段仅可用于人员实体的表单」／ "Name and email fields need a form on a person entity"）。身份检查计入 `Page#launch_errors`（`VisibilityContract` 仅扩大受众时不重跑）。见下文**身份字段（账号）**。
- **提交流程。** 设置了 `form_settings.flowchart_id` 的页面，该流程图必须能通过 `Pages::SubmissionProcess` 解析，即 `Pages::PublicSubmission` 使用的查找（`Flowchart.accessible.launched`，客户流程图还需符合实体一致规则）。否则以 `submission_process_offline` 阻止上线。这些消息面向租户管理员，因此都不提“流程图”。

`Page#submission_blockers` 即必填字段与提交流程两部分（不含归属受众错误或操作冲突）。通过 `Pages::VisibilityContract` 扩大已上线页面的受众时，会针对新增受众重新运行下拉列表、必填字段、`audience_errors` 与 `action_errors`（改标识时对全部受众跑 `action_errors`），任一失败即拒绝修改。缩小受众及未上线页面不做检查。`AiAssistant::Assistant::GeneratePage` 会把未通过这些检查的生成表单报告为已跳过，并附原因。

### 生成的布局

`EntityFieldOrganizer` 在生成的表单和构建器面板中略去计算字段和汇总字段，实体自身和关联实体均如此。`PageFieldPopulator` 把属性的 `description` 复制到 `help_text`，并以关联实体的显示名称标注每个关联分节。`PageTemplateApplier::FieldGrouper` 与 `LayoutElementBuilder` 在生成时翻译所写入的标题和布局标签（`maint_core.pages.generator.*`）。无论按来源还是按属性分组，关联字段始终单独成为“关联：<实体>”分节。`LayoutElementBuilder.element_defaults` 对 `divider`、`spacer`、`heading` 以外的类型抛出 `ArgumentError`。

### 身份字段（账号）

绑定实体为人员实体时，编辑器侧栏（`app/views/admin/maintenance/pages/_editor.html.erb`）增加**账号**分组（`maint_core.pages.editor.identity_group`「账号」／ "Account"；说明 `identity_group_help`「用于创建会员登录账号。」／ "Creates the member's sign-in account."），含名字、姓氏与邮箱（`People::IDENTITY_KEYS`；标签来自 `member.profiles.show.fields.<key>`）。每项 `source: "identity"`，渲染为 `identity[<key>]`。课程等非人员页面不显示该分组。`EntityFieldOrganizer` 从不把人员实体的账号列（`Authentication::User` 上的 `first_name`、`last_name`、`email`）作为基础模型字段提供——这些列只能作为身份字段进入表单。

身份字段出现在非人员页面上时，上线失败为 `identity_field_not_person`。`Pages::LaunchChecks#identity_errors` 计入 `Page#launch_errors`。

收集邮箱的公开注册页应开启验证码（页面开关加 URL 限流）。见[验证码](captcha)与[页面渲染](page-rendering)。公开报名全程见[受众流程](audience-flows)。

### 状态标记

表单列表（`Admin::Pages::OpsTableComponent`，卡片和表格行）与页面标题最多显示一个来自 `Pages::FormHealth` 的标记：

- **无法提交**（`variant: :danger`）：页面已上线且 `submission_blockers` 非空，提示中列出阻止原因。
- **版本过旧**（`variant: :warning`）：否则，当 `Page#entity_out_of_date?` 为真，即 `entity_version_id` 与租户当前看到的实体版本不同时显示。手动构建的页面没有 `entity_version_id`，不会标记为版本过旧。

整个列表共用一个 `Pages::LaunchChecks::Lookup`，查询次数随不同实体和流程图的数量增长，而非随行数增长。

### 助手生成的表单

`AiAssistant::Assistant::GeneratePage` 是仅用于助手的策略边界：显式 `generate_page` 工具，以及实体创建成功／批准更新后自动生成表单，均经过它。封装以 `shared: false` 调用 `Pages::Activities::CreateFromEntityVersion`，成功后调用 `Page#launch!`。新行沿用列默认值（管理员开，会员与公开关），因此上线后的表单仅供管理员／所有者使用。

创建（含恢复／重建可回收的停用页面）、版本生成、受众与上线都在 `Page.transaction(requires_new: true)` 内执行；即使生成已处于外层事务，上线失败仍会整体回滚。Activity 返回其他失败结果时也回滚。`ActiveRecord::RecordInvalid` 或 `RecordNotSaved` 返回 `ok: false`、`skipped: :launch_failed`，并以 `ai_assistant.assistant.apply_page_skipped` 给出校验原因；未提供原因时使用 `apply_errors.page_launch_failed`。失败后封装不返回页面或已创建名称；已完成的实体操作仍保留。

`:page_exists` 只复用 `customer_id` 与 `entity_version_id` 精确匹配的有效页面，不改变其上线状态或受众。实体须属于同一客户。共用 `CreateFromEntityVersion` Activity 仍将表单绑定到已上线的共享 **Create Entity Entry** 流程图；其手动实体版本页面创建不采用助手自动上线策略。共享全局资源的上线／受众仍仅限平台路径。网站营销页面是独立的 `WebsitePage` 资源，保留自身发布流程。参见 [AI 助手](ai-assistant)。

### 控制器

`Admin::Maintenance::PagesController` 使用 `SharedResourceMode`。租户覆盖只允许 `:configuration`。完整保存允许 `name`、`description`、`configuration`、`entity_id`、`captcha_enabled`。`page[updated_at]` 缺失、无法解析，或早于当前行（留 0.001 秒余量）时，`stale_client_edit?` 为真。JSON 响应状态为 `conflict`（409），并带上 `server_updated_at`。

`entity_flows` 返回某实体已发布的流程图（`Flowchart.for_current_customer.where(entity_id:).launched`）以及 `Flowchart.shared.launched`。编辑器的 `TabManager` 请求这份 JSON。编辑动作还会加载 `Flowchart.accessible.referenceable` 供绑定控件使用。`PageManager#_buildFlowchartBindingHtml` 把选中的 id 写入 `configuration.form_settings.flowchart_id`。

其他维护路由：

- `FieldTemplatesController`：经 `FieldTemplates::Create`、`Update`、`Delete` 对 `FieldTemplate`（`customer_id`、`built_in`）做 JSON CRUD。内置行拒绝删除。画布命令面板和字段管理器请求 `.../pages/field_templates`。
- `PageTemplateApplicationsController`：把 `PageLayoutTemplates.find(template_key)` 应用到已有页面。`all` 与 `find` 在调用时按 `layout_catalog.templates.<key>` 翻译模板的 `name` 和 `description`。分类与分组标签使用 `layout_catalog.categories` 和 `layout_catalog.groups`。各模板 `DEFINITION` 里的英文仍是原文。预览行里的示例字段标签留在该定义中。
- `PageFieldOptionsController#show`：`dynamic_options.options_source` 为 `"query"` 的字段选项。
- `PageModuleDataController#show`：用 `CompositePageRenderer` 渲染 `configuration_json["modules"]` 中的一项。
- `PageRendersController#show`：已发布且对 `:admin` 可见的页面，然后 `prepare_page_render`。
- 版本：`PageVersionsController`，按版本线隔离，上限 50。

租户页面 URL 面向 `admin` 或 `owner`。平台前缀只面向 `platform_owner?`。从这个编辑器链出去的流程图界面仍然只有所有者能开，见 [流程图构建器](flowchart-builder)。

### Stimulus

现行编辑器是 `page_builder_controller.js`（`page-builder`）。它委托给 `UndoRedoManager`、`ViewportManager`、`TabManager`、`DragDropManager`、`FieldManager`、`PageManager`、`PropertyManager`、`SaveManager`、`KeyboardManager`、`SelectionManager`、`InserterManager`、`RulesManager`、`CalculationsManager`、`InlineEditManager`、`ClipboardManager`、`ResizeManager`、`CommandPaletteManager`、`ZoomManager`、拖放辅助对象和 `ContextMenuManager`。`SaveManager` PATCH 配置 JSON，并发送 `updated_at` 与 `If-Unmodified-Since`。预览通过 `previewForm` 提交当前配置。

`page_settings_controller.js` 只切换设置弹层里的面板。`page_visibility_controller.js` 把三个受众开关视为独立；只剩一个开启时禁用该开关，原因来自服务端传入的 `data-page-visibility-last-audience-value`（`comp_misc.distribution.last_audience`：「表单须至少面向一个受众。」）。隐藏输入保证禁用的最后一项仍能提交（`page[visible_audiences][]`）。发布卡片同时提交 `page[action_key]`，列出 `Pages::ActionResolver.siblings`，并为每个已启用受众显示 URL 行。管理员是普通开关。`page_list_controller.js` 过滤索引。

`page_canvas_controller.js` 与 `page_toolbar_controller.js` 的源码写明它们没有 ERB 挂载点，已由 `page-builder` 取代。`entity_selector_controller.js` 与 `property_palette_controller.js` 仍会查询 `page-canvas` 元素。

### 行操作

设置／会员可为实体界面配置行操作：操作标识（下拉列出已有已上线会员页的标识）、目标字段（slug）与可选按钮文字（默认 `member.entity_surfaces.row_action_default`「打开」）。每行链到 `Pages::ActionLink.path`，并带 `prefill[<field>]=<行 id>`。组合列表块接受同样键的 `config.row_action`，并渲染末列链接。预填仅用于展示；见[受众流程](audience-flows)与[会员与公开页面](member-and-public)。

### 公开提交

`PublicPagesController` 引入 `PageRendering`。`show` 按 `public_uuid` 加载已发布页面，集合不含 `public` 则 404；访问者受众在同一操作下另有对应页时 303 过去。`submit` 要求访问者受众在集合中（`page_visible_to_current_viewer?` 即 `page.visible_to?(page_runtime_audience)`），然后调用 `Pages::PublicSubmission`。该服务读取 `form_settings.flowchart_id`，通过 `Pages::SubmissionProcess` 解析（`Flowchart.accessible.launched`，与上线检查使用同一查找），并拒绝空白 `activity`、缺失实体，或实体与流程图不一致的情况。放行之后，`Pages::AudienceGuard` 绑定归属引用，可能返回 `:rejected` 且不写入任何内容；见[页面渲染](page-rendering)。Activity 如何运行见 [流程图运行时](flowchart-runtime)。`prepare_page_render` 始终把表单指到该页 UUID 的 `public_page_submit_path`，并设置 `@content = page.generate_content`。

## 需要特别注意

:::attention
`PageRendering#prepare_page_render` 是管理端与公开 GET 的渲染接缝。它把 `@form_action` 设为 `page.public_uuid` 的 `public_page_submit_path`，并把 `@content` 设为 `page.generate_content`。预览可以把未保存的配置交给 `PageContentGenerator`；没有 `public_uuid` 时 action 回落到 `"#"`。不要把表单指到维护更新 URL。
:::

:::attention
`Admin::Maintenance::PagesController#update` 只在提交了 configuration 且 `tenant_override?` 为假时写入 `content`。客户分叉，包括客户 `81721200` 在租户 URL 上的保存，通过 `resolved_current_version` 把正文存在 `page_customer_heads`，共享行的 `content` 列保持不动。该共享行的发布与受众由 `PageLaunchesController` 和 `PageVisibilitiesController` 上的 `guard_shared_global_writes` 把守。租户实体选择器还会列出归属桥接（`People::Ownership.kind` 为 `:owned`）；共享资源模式不列。
:::

:::attention
`Pages::PublicSubmission` 只有在 `form_settings.flowchart_id` 解析到一份已发布、且 `activity` 非空的流程图时才会执行。无名或空图会使 `ActivityGenerator#generate` 返回 `nil`，因此页面可以已发布却仍无法执行。绑定控件列出的是 `referenceable` 流程图（`status: launched`）。
:::

:::attention
`page_canvas_controller.js` 解析的是扁平 `fields` 数组，文件头写明它没有 ERB 挂载点。实际上线的编辑器是 `_editor.html.erb` 上的 `page-builder`，而 `Page#configuration_json` 要求 `pages` 数组。按旧的扁平形状保存，会丢掉 `Page` 所校验的结构。
:::

## 关键代码

```ruby
# app/controllers/concerns/page_rendering.rb
  def prepare_page_render(page)
    @form_action = public_page_submit_path(customer_id: params[:customer_id], uuid: page.public_uuid)
    @content = page.generate_content
  end
```

```ruby
# app/models/concerns/page_configuration_helpers.rb
  def generate_content
    PageContentGenerator.new(self).generate
  end
```

```ruby
# app/controllers/admin/maintenance/pages_controller.rb
        if params.dig(:page, :configuration).present? && !tenant_override?(@page)
          unless @page.update(content: @page.generate_content)
            raise ActiveRecord::Rollback
          end
        end
```

```ruby
# app/models/concerns/page_launch_lifecycle.rb
  def launch_errors
    msgs = []
    msgs << I18n.t("maint_core.errors.page_launch.entity_missing") unless entity&.active?
    msgs << I18n.t("maint_core.errors.page_launch.no_fields") if fields.empty?
    msgs.concat(orphan_rule_errors)
    msgs.concat(orphan_calculation_errors)
    checks = Pages::LaunchChecks.new(self)
    msgs.concat(checks.reference_errors)
    msgs.concat(checks.audience_errors)
    msgs.concat(checks.identity_errors)
    msgs.concat(checks.action_errors)
    msgs.concat(checks.submission_blockers)
    msgs
  end
```

```ruby
# app/services/pages/public_submission.rb
    def bind_flowchart_and_entity!
      record = SubmissionProcess.flowchart_for(@page)
      @flowchart = record && RuntimeFlowchart.new(record)
      @entity = @page.entity
    end
```

```ruby
# app/models/concerns/page_visibility.rb
  AUDIENCES = %w[admin member public].freeze

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end
```

相关页面：[页面渲染](page-rendering)、[受众流程](audience-flows)、[流程图构建器](flowchart-builder)、[实体构建器](entity-builder)、[共享资源](shared-resources)、[网站构建器](website-builder)。
