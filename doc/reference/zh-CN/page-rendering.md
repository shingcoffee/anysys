---
title: "页面渲染"
summary: "已发布页面如何变成 ERB、哪种受众可以打开，以及提交在何处运行绑定的流程图。"
---

## 概要

`Page#generate_content` 委托给 `PageContentGenerator`，后者返回一段 ERB。`PageRendering#prepare_page_render` 把 `@content` 设为这段字符串，把 `@form_action` 设为 `POST /:cid/page/:uuid`。公开、会员和管理员渲染都用 `render inline: @content`。公开 UUID 的 GET 要求精确受众集合含 `public`。POST 要求访问者受众在集合中（`page.visible_to?(page_runtime_audience)`）。提交服务见 [flowchart-runtime](flowchart-runtime)。构建器里的存储见 [page-builder](page-builder)。受众路由也写在 [member-and-public](member-and-public)。报名模式与操作路由器见 [受众流程](audience-flows)。

## 流程

```text
Page#generate_content
        |
        v
PageContentGenerator#generate
        |
        |  layout == "composite" -> CompositePageRenderer#render_modules
        |  否则为向导 / 单页表单 / 纯内容 ERB
        v
@content

GET  /:cid/actions/:action_key Pages::ActionsController#show
        |  公开 URL；重定向到 page_runtime_audience 对应页
        |  公开访客 + 同一操作已有上线会员页 -> continuation=
GET  /:cid/page/:uuid          PublicPagesController#show
        |  已发布且集合含 public，否则 404
        |  访问者受众有对应页 -> 303（保留预填）
GET  /:cid/member/pages/:id    Member::PagesController#show
        |  已发布且集合含 member
GET  /:cid/admin/maintenance/pages/:id/render
        |  PageRendersController#show
        |  已发布且集合含 admin
GET  /:cid/admin/pages/:page_id/form
        |  Admin::PageFormsController#show
        |  已发布且集合含 admin
        v
prepare_page_render -> @page_prefill + render inline: @content
        |
        |  表单提交到 public_page_submit_path
        v
POST /:cid/page/:uuid          PublicPagesController#submit
        |
        |  authorize_submission! 精确集合（拒绝顺序见下）
        v
Pages::PublicSubmission.call
        |
        |  成功且 handoff? -> FeatureModules::Invocation.begin!
        v
重定向到该受众能够打开的界面
```

## 实现

公开 `Page` 也可通过指定的 URL 别名渲染，包括 `/` 和多级路径，见 [页面快捷路径](page-shortcuts)。别名 GET/HEAD 保留现有上线检查，并要求受众集合含 `public`，共享定义按所选客户解析。公开表单别名的 POST 通过同一提交授权处理。`Pages::DistributionCardComponent` 展示三个独立受众开关、操作标识、同操作其他页面，以及 `PageShortcuts::PublicPath.public_page` 按主机生成的首选公开地址，并添加 `SCRIPT_NAME` 及当前请求来源，便于分享。生成的 `@form_action` 仍为规范 UUID 提交路径。

主机选择实时读取客户上的[自定义域名](custom-domains)。平台所有者在客户资料中设置它。显式客户前缀优先；停用客户返回 404，不展示其他租户的表单。域名变更后无需重启。保存新增或变更的域名时，检查该域名直接指向 `anysys.net` 的 CNAME；失败则保留原域名。清空域名不检查 DNS。部署负责发布 DNS，并分别管理 TLS／入口路由／HostAuthorization；渲染时不重做该 DNS 校验。

生成字段在以下情况标为必填：页面配置的 `required` 为 true，或所绑定实体（含桥接实体）的属性含有对当前查看受众生效的 `presence` 校验（`EntityAttributeAudience.applying_audiences`）。`PageContentGenerator` 向表单字段组件传入 `required: true`，标签旁显示星号，并设置 HTML `required`。向导在这些字段填完之前不会进入下一步。计算字段、派生字段和只读属性不会因模式被标为必填。校验不作用于该受众时，不会出现模式带来的标记；页面自身的 `required` 仍然生效。

`PageConfigurationHelpers#generate_content` 即 `PageContentGenerator.new(self).generate`。`configuration` 为空白时 `generate` 返回 `""`。`configuration_json["layout"]` 为 `"composite"` 时，`generate_composite` 用 `configuration_json["modules"]` 和 `customer_id: tenant_customer_id`（`Current.customer_id` 或 `page.customer_id`）构造 `CompositePageRenderer`。然后对每个磁贴调用 `PageContentGenerator::CompositeRenderer#render_module`。否则读取 `pages` 与 `form_settings`（没有时回退到 `settings`）。`pages` 为空，或单页的 `fields` 为空时，返回 `""`。没有输入字段时生成纯内容 ERB。多于一页时生成向导。只有一页时生成单个表单。`wrap_with_runtime_controller` 把这段标记包进 `data-controller` 为 `condition-runtime` 的 `div`，并把页面的 `rules` 与 `calculations` JSON 放在 data 属性上。

`CompositePageRenderer` 按显式客户解析自有／共享实体，再仅查询该客户记录。它把 `scope: People::Ownership.scope(...)` 传给 `FlowchartRuntime::QueryBuilder`，按访问者受众限定行：会员页上归属实体的组合列表只显示访问者自己的行，公开页上人员／归属／私有实体则列出空。列及排序字段使用生效受众可见结构。组合宽度在 `md` 以下纵向堆叠。流程图查询步骤从不传入 `scope:`，见[流程图运行时](flowchart-runtime)。

独立组合页面测试通过 `Current.set` 设置 `Current.customer`、清空查看者及共享资源模式，并在结束后恢复传入上下文。真实实体／记录夹具验证公开列过滤、同租户管理员专属值，以及当前渲染租户与页面实体租户不同时返回空结果。测试保留 `Current.customer_id` 的预期优先级，不让渲染器忽略所访租户。

`PublicPagesController`、`Member::PagesController`、`Admin::Maintenance::PageRendersController` 与 `Admin::PageFormsController` 都引入 `PageRendering`。`prepare_page_render(page, return_to: nil, quick_add: false, prefill: {})` 设置：

`@form_action` 为 `public_page_submit_path(customer_id:, uuid: page.public_uuid, return_to:)`；`return_to` 为 nil 时不附加查询参数

`@content` 为 `page.generate_content`

`@page_quick_add` 为 `quick_add`，生成的 ERB 通过辅助方法 `page_quick_add_enabled?` 读取

`@page_prefill` 为 `Pages::Prefill.values` 的哈希（或传入的 `prefill`）。生成的输入调用 `page_prefill_value(slug)`。控制器传入 `Pages::Prefill.values(page:, params:, audience: page_runtime_audience, viewer: page_runtime_user)`。预填只保留该受众可见的字段；引用值须在访问者可选范围内；从不预填归属引用；畸形参数不抛错。提交校验不变：预填不授予任何权限。

身份字段（`source: "identity"`）渲染为 `identity[<key>]`（`PageContentGenerator::FormFields`）。邮箱使用 `html_type: email`。`FormParams#visible_field?` 只对公开与管理员显示；会员没有身份输入（`permit_identity` 为 `{}`）。生成的表单在 `@page_continuation` 存在时还输出隐藏的 `_continuation`（`hidden_field_tag :_continuation, @page_continuation`）。`PublicPagesController#assign_page_continuation`（GET 的 `continuation`，验证码重渲染的 `_continuation`）仅在 `Pages::Continuation.verify` 成功后保留令牌，伪造查询串不会变成 HTML。

`@content` 存在时，`public_pages/show.html.erb`、`member/pages/show.html.erb`、`admin/maintenance/page_renders/show.html.erb` 与 `admin/page_forms/show.html.erb` 用 `render inline: @content` 渲染这段 ERB。公开控制器使用布局 `public_page`。

### 后台填写表单

`GET /:cid/admin/pages/:page_id/form`（`admin_page_form_path(cid, page)`）是管理员填写表单的入口。`Admin::PageFormsController#show` 从 `Page.accessible`（租户自有及共享页面）加载，`launched? && visible_to?(:admin)` 不成立时返回 404，随后调用 `prepare_page_render(@page, return_to: PageRendering::ADMIN_FORM_RETURN, quick_add: true)`。视图以 `AdminPageComponent` 和后台布局包裹生成的 ERB：面包屑为**表单** → 页面名称，标题为页面名称，下方显示页面描述（无描述时显示本地化填写提示），图标取自 `Admin::Pages::OpsTableComponent::FORM_ICON`。卡片内边距为 `p-4 sm:p-6`；渲染逻辑与维护区渲染一致，向导、规则、计算和实体下拉框行为相同。对管理员受众必填的字段，标签旁显示星号，规则见上文生成器说明。

表单仍提交到 `PublicPagesController#submit`，并携带 `return_to=admin_form`。仅当 `admin_form_return?` 成立时，`post_submit_path` 才把管理员送回 `admin_page_form_path`：该令牌等于 `ADMIN_FORM_RETURN`、访问者在同一租户下 `admin_or_owner?`（或为平台所有者），且页面 `visible_to?(:admin)`。该参数只是符号令牌而非 URL，无法用作开放重定向；其他取值沿用原有受众规则。

### 下拉框快速新增实体记录

`entity_entries` 下拉列表的选项由生成模板中的 `Entities::ReferenceOptions.call` 渲染，面向当前访问租户（`Current.customer_id`，缺省时使用页面所属客户）、访问者受众，以及 `viewer: Current.user`。行来自 `People::Ownership.scope`。选项值为记录 ID，标签遵循 `Entities::ReferenceLabels`。因此会员页上指向人员实体的下拉只列出该会员自己的条目；公开页上指向人员、归属或私有实体的下拉没有选项；开放实体（课程目录）列出本租户全部行。`query` 列表（`PageContentGenerator::DynamicOptionsResolver`）把同一 `scope:` 传给 `QueryBuilder`。`Entities::EntryDisplay` 使用同一访问者：范围内的引用显示其显示字段，范围外只显示裸 id（不泄露标签）。管理员受众的输出不限定范围。页面构建器预览（`GET /:customer_id/admin/maintenance/pages/:page_id/field_options/:field_id`，以及 `maintenance/platform/pages` 下的同一路径）可在页面任意位置（包括分栏内）找到字段，并以 URL 租户管理员身份预览两种来源。见[人员关联](person-linking)。

`dynamic_options.options_source` 为 `entity_entries` 的下拉框，在后台渲染（`/form` 与维护区渲染，均为 `quick_add: true`）时末项为**+ 新增**。`PageContentGenerator::FormFields` 为这类下拉框输出 `quick_add: page_entity_quick_add(entity_id, label_field)`，字段边界为只读时除外；多选下拉框忽略该参数。`PageEntityQuickAddHelper#page_entity_quick_add` 在 `page_quick_add_enabled?` 为假或 `current_user.admin_or_owner?` 不成立时返回 nil；否则在当前客户自有及共享、启用且非桥接的实体中解析该实体（每次渲染缓存），返回 `Admin::Entities::QuickAddDialogComponent.opener(..., depth: 0)`：`{ url:, label:, title:, dialog: }`，其中 `url` 为 `new_admin_entity_entry_path(cid, entity, label_field:)`，`dialog` 为 `#entity-quick-add-dialog-0`。公开页与会员页渲染从不设置该标志，标记保持不变。

带 `quick_add:` 的 `FormFields::SelectFieldComponent` 会在其他选项之后追加一个值为空、带 `data-quick-add-option` 的选项，并用 `<div class="contents" data-controller="entity-quick-add">` 包裹下拉框，挂上 URL、标题和 `quick_add[:dialog]` 出口。下拉框是 `select` 目标，并声明 `change->entity-quick-add#change`。“新增”项从不作为默认值：它位于末尾；没有其他选项时，即使 `include_blank` 为 false 也保留空占位项。未启用 JavaScript 时，选中该项提交空值。

选择**+ 新增**时，`entity_quick_add_controller.js` 恢复先前的选择，并调用出口的 `open({ url, title, onCreated })`。两个后台渲染视图各在第 0 层渲染一次 `Admin::Entities::QuickAddDialogComponent`，即带 `entity-quick-add-dialog` 控制器的原生 `<dialog>`。控制器把 URL 加载到本层的 `entity-quick-add-frame-<depth>` Turbo 框架，并显示加载模板。仅当本层框架触发 `turbo:frame-missing` 时才换成失败模板；从嵌套层框架冒泡上来的该事件会被忽略。按 Esc、点击遮罩或取消即关闭，关闭时清空框架。浏览器异步派发 `close` 事件；若事件到达前对话框已重新打开，则不作处理。对话框手机端全屏，`sm` 起为 `max-w-3xl` 卡片。框架渲染出创建成功标记后，对话框关闭；`onCreated({ id, label })` 选中已有同值选项，或在**+ 新增**之前插入新选项，再派发冒泡的 `change` 事件，使规则与计算重新执行。快速新增表单自身的引用下拉框会打开更深一层的嵌套对话框。嵌套方式与框架响应见[实体构建器](entity-builder)。

`PageVisibility::AUDIENCES` 是 `%w[admin member public]`。`visible_to?(audience)` 是精确集合成员判断。未知受众为假。仅面向公开的页面对 `member` 或 `admin` 不可见。

`PublicPagesController#find_launched_page` 按 `public_uuid` 加载 `Page.accessible.launched`。`show` 调用 `authorize_public_view!`，`visible_to?(:public)` 为假时抛出 `RecordNotFound`。集合不含 `public` 的页面，任何会话访问 `GET /:cid/page/:uuid` 都是 404。访问者受众在同一操作下另有对应页时，`redirect_to_audience_counterpart!` 以 303 转到该界面并保留已清洗的 `prefill`。`submit` 调用 `authorize_submission!`。`page_visible_to_current_viewer?` 即 `page.visible_to?(page_runtime_audience)`。其他租户的管理员或会员视为公开。访问者受众不在集合中时不写入，并按第一条匹配规则处理：

1. 该操作有面向访问者受众的页面：重定向过去，提示 `public_views.actions.continue_here`（「请在适用于您账号的表单中继续。」）；
2. 访问者匿名，且集合含 `member` 或 `admin`：保存 `stored_submission_return_path`（页面含会员则用会员界面，否则用管理员渲染）并转到登录；
3. 集合含 `public`：回到该页，提示 `public_views.actions.not_for_your_account`（「此表单不适用于您的账号。」）；
4. 否则 404。

`post_submit_path` 把访问者送到其受众界面：会员 → `member_page_path`，管理员 → `admin_page_form_path`，其余为首选公开地址。

`submit` 在 `Invocation.with_submission` 内运行 `Pages::PublicSubmission`。`FormParams.permit_parts` 之后，`Pages::AudienceGuard` 绑定归属人并检查其余提交的引用（见下文**归属绑定**）。`:rejected` 结果不写入任何内容，带守卫文案重定向回去（`common.errors.dynamic.profile_required`、`reference_not_allowed` 或 `sign_in_required`）。流程图缺失为 method-not-allowed；其他无效／失败结果带本地化保存错误重定向。交接在提交保存点完成前的活动完成块中映射输入并开启调用。`start_page_handoff` 经同一守卫重新放行（`guarded_handoff_params`），伪造的归属引用不会进入模块映射；拒绝时不交接任何内容。拒绝时回滚业务新增／更新、恢复先前会话调用，再带模块错误重定向，绝不删除返回的既有记录。见[模块框架](module-framework)。

### 归属绑定

`Pages::FormParams#visible_field?`（以及 `#required_field?`）对会员受众隐藏归属引用，因此会员的作业表单不会渲染学生字段。提交边界由服务端填写。

`Pages::AudienceGuard.call(entity:, primary:, sections:, viewer:, audience:, customer_id:)` 在放行之后、活动之前运行。管理员受众为空操作。未知受众以 `sign_in_required` 拒绝。

- **会员。** 主实体以及每个已填写桥接分区的归属引用会从已放行输入中剔除，并设为 `People::Ownership.person_entry_id(viewer, person_entity_id)`。没有已关联条目：以 `common.errors.dynamic.profile_required` 拒绝（`%{entity}` 为人员实体的显示名称：「您的账号尚未关联%{entity}资料。」）。页面绑定人员实体、且桥接分区的归属人就是指向该新行的反向引用时（学生页上的报名分区），仍由 `Pages::BridgeEntries` 写入新主记录 id，守卫不覆盖。其余已提交、目标为人员／归属／私有实体的引用必须落在 `People::Ownership.reachable_ids` 内，否则以 `common.errors.dynamic.reference_not_allowed` 拒绝（`%{field}`：「%{field}：无权选择该记录。」）。指向开放实体的引用除现有租户校验外不再检查。桥接分区的反向引用会被剔除，伪造 id 到不了流程图或模块交接。
- **公开。** 种类为 `owned` 或 `private` 的主实体以 `common.errors.dynamic.sign_in_required`（「请登录后提交此表单。」）拒绝；已填写且种类相同的桥接分区同样拒绝。空的桥接分区忽略，主记录仍可保存——因此公开学生页不会创建报名。已填写的引用遵循同一 `reachable_ids` 规则；人员／归属／私有在公开受众下范围为空，这些选择以 `reference_not_allowed` 拒绝。
- **管理员。** 不绑定，也不做额外检查。

`Pages::PublicSubmission` 仅为同租户访问者把 `People::Ownership.person_entry_ids` 写入 `ctx[:current_person_ids]`。其他租户的已登录用户在此视为公开，其本租户人员条目不会进入本次运行。匿名与未关联访问者得到 `{}`。见[人员关联](person-linking)与[流程图运行时](flowchart-runtime)。

同时从 `FormParams.permit_identity` 写入 `ctx[:identity]`（字符串键；仅人员实体页上已放置的身份字段；只对公开与管理员；会员为 `{}`），从 `Pages::Continuation.verify(params[:_continuation])` 写入 `ctx[:continuation]`（符号键 `{ action_key:, prefill: }` 或 nil）。身份从不进入 `ctx[:params]`。缺失、被篡改、过期、用途不符或过大的令牌为 nil，提交仍然成功。

`post_submit_path` 按 `page_runtime_audience`：会员 → `member_page_path`，管理员 → `admin_page_form_path`，其余为首选公开地址。`return_to=admin_form` 仍标记填写入口提交；它是符号标记，不是 URL。

`Member::PagesController` 引入 `allow_admin_member_preview!`，按 id 加载已发布且可访问的页面，并要求 `visible_to?(:member)`。`PageRendersController#show` 使用 `definition_scope(Page)`，并要求 `launched?` 与 `visible_to?(:admin)`。

`Admin::Pages::OpsTableComponent` 与条目列表共用工具栏、可排序表头和页脚（结果数、页码、每页行数；`per_page` 为 URL 参数）。每行有一个主操作：页面 `launched? && visible_to?(:admin)` 时为**填写**，在当前标签页打开 `admin_page_form_path`；否则为**预览**，在新标签页打开（`target="_blank"`、`rel="noopener noreferrer"`）。点击行（经 `row-link`）或页面名称即执行该操作，操作列另以带边框的图标按钮重复提供，`lg` 起显示文字（`aria-label` 为“填写「<名称>」”）。桌面端列宽设在 `th` 上：页面列占据剩余宽度，含表单图标、名称及实体副标题；受众列 `md` 起显示，状态列为 `w-28`，更新时间列 `lg` 起显示。`md` 以下各行改为卡片，保留图标、主链接、状态、受众和时间。状态以“已上线／草稿”标签显示。

`Admin::Pages::RowMenuComponent` 按以下顺序渲染行菜单：**管理访问**（`page-publishing` 侧滑面板），然后是**预览**与**在新标签页打开**，最后是**上线**或**下线**（红色）。**在新标签页打开**仅对可填写的页面显示，使用 `target="_blank"`、`rel="noopener noreferrer"` 和 `data-turbo-frame="_top"` 打开 `admin_page_form_path`。自有页面和共享页面均保留当前所访客户前缀；共享页面按该客户的生效定义渲染。草稿仍可通过**预览**打开。

`PageLaunchLifecycle` 里的 `Page#launch!` 在 `launch_errors` 非空时抛出 `ActiveRecord::RecordInvalid`，然后把 `launched` 设为 true。`take_offline!` 把 `launched` 设为 false。共享页面的发布和受众更新若离开平台前缀，会被 `guard_shared_global_writes` 拒绝。见 [shared-resources](shared-resources)。

### 身份字段与续接

人员实体表单上的账号字段不是实体属性。它们以 `identity[first_name]`、`identity[last_name]`、`identity[email]` 提交，只进入 `ctx[:identity]`。通用记录步骤从不写这些键。见[页面构建器](page-builder)与[流程图运行时](flowchart-runtime)。

`Pages::Continuation` 以 purpose `page_continuation`、3 天有效期签名 `{ action_key, prefill }`。令牌不带 URL，也不带客户编号。仅当公开访客被送到同时拥有上线会员页的操作的公开页时，`Pages::ActionsController` 才附加 `continuation=`。确认或登录后，`People::Claim.complete!` 在**该用户**的租户下拼出 `/:cid/actions/:key`。公开报名全程见[受众流程](audience-flows)。

`PublicPagesController` 引入 `CaptchaProtectable`，并定义 `handle_captcha_rejection`，它重新赋值续接并重新渲染 `:show`。这个类没有调用 `protect_with_captcha`。`PageContentGenerator` 不引用 captcha。`Captcha::UrlMatcher` 返回规则时，URL 限流由 `Captcha::RackGate` 负责。`Page#captcha_enabled?` 读取 `configuration_json["captcha"]["enabled"]`。收集邮箱的公开注册页应开启验证码（页面开关，再加上 `/:cid/page/<public_uuid>` 的 URL 限流）。见[验证码](captcha)。

### 可复用字段组件 API

`FormFields::BaseFieldComponent` 接受 `input_only: false` 及额外 HTML 属性。显式 `id:` 优先于自动生成的 `field_<parameterized field_name>` ID。启用 `input_only: true` 时，base 模板只渲染控件，不输出外层容器／标签，`input_attributes` 也不添加默认主题输入样式。使用方适配层负责传入 `class:`、无障碍标签或 legend、帮助／错误标记，以及 `invalid`、`describedby` 等 `aria:` 属性。

- `CheckboxFieldComponent` 使用合并后的输入属性、显式 `checked:` 参数及 `value: "1"` 渲染单个复选框。
- `RadioFieldComponent` 保留各选项标签，转发合并后的输入属性，并将选中值统一按字符串比较。首个选项使用字段 ID，后续依次为 `<id>_1`、`<id>_2` 等；适配层负责分组 fieldset／legend。
- `ToggleFieldComponent` 保留开关外观，将合并后的属性传给复选框，设置 `value: "1"`，由 `checked?` 决定选中状态，输入样式固定使用 `sr-only peer`。此模式不显示默认标题／说明；传入 `aria: { invalid: "true" }` 时为开关轨道标记无效状态。

布尔控件的隐藏 `"0"` 输入及多选的空字符串哨兵由使用方表单提供，不由这些控件生成。`Admin::Entities::EntryFieldComponent` 通过此 API 负责关联标签、帮助及错误，见[实体构建器](entity-builder)。`input_only` 仅控制展示，不负责输入过滤或授权。

## 需要特别注意

### 路由审计：渲染控件、参数形状及计算

生成 Ruby 参数同时转义 Ruby 插值及 ERB 分隔符，组合 ID／监听事件进行 HTML 转义。运行控件保留 password／hidden 类型，不回显密码值或隐藏控件标签；保留多选／多文件 `[]` 名称、禁用计算字段、表单／向导 multipart 编码及合法向导提交按钮。

`Pages::FormParams` 按可访问结构及所访租户受众过滤渲染／提交，包含嵌套列。字段通过 `Page#input_fields` 读取（分栏展开，布局元素除外）。对会员受众，归属引用与身份字段的 `visible_field?` 均为 false（归属引用由服务端填写）。主 `entity[slug]` 及已声明桥接 `assoc[section][slug]` 仅接受可写标量／数组／上传形状。身份以 `identity[<key>]` 提交，由 `permit_identity` 单独放行，从不并入 `permit_parts`。`FormParams.permit_parts` 返回 `[primary, sections]`；`Pages::AudienceGuard` 随后改写归属标识，并可能在写入前拒绝提交。Activity 始终在 `ctx[:params]` 中收到（可能已改绑的）扁平主实体属性，在 `ctx[:association_params]` 中收到关联分区；运行新建主记录后，由 `PublicSubmission` 自行写入关联行（见[流程图运行时](flowchart-runtime)）。目标缺失或属于其他租户时以 `common.errors.dynamic.association_target_missing` 失败；关联分区无法解析时以 `association_unavailable` 失败。基础模型字段仅为元数据，不渲染；非空／畸形 `base[...]` 在执行前以 `base_model_submission_not_supported` 拒绝，尚无基础记录解析／写入适配器。动态选项标签／值／排序及组合列执行同一受众策略与归属行范围，不可访问来源为空，实体下拉最多 200 条。

未绑定实体的 UI 预览仅在禁用的 fieldset 内渲染未指定来源的控件，不接受任何提交值。元数据绑定无法解析或控件明确指定实体来源时，不能回退为预览。生成器 UI 测试通过 `PageRuntimeHelpers#build_runtime_ui_page` 绑定真实租户自有实体，为声明的输入（含嵌套列）建立结构；安全测试独立设置结构，确保未知、隐藏及外租户属性仍由生产边界处理。

`PageContentGenerator#generate_fields` 会去掉访问者一个字段都看不到的分节。字段在每个 `section` 元素处切分为若干段；某段至少有一个输入字段（分栏内字段也计入），且 `Pages::FormParams#visible_field?` 对其全部为 false 时，该段连同分节标题、紧挨其前的分隔线及段内布局元素一并移除。没有输入字段的段照常渲染。该处理在每次请求时按访问者受众进行。分隔线标签若为生成器默认值（任一语言下的 `maint_core.pages.generator.layout.divider`），渲染时不显示标签。

`Pages::RulesEngine#apply` 先移除客户端计算目标，再按拓扑依赖使用服务端结果计算，单调移除隐藏输入并重算依赖。循环／重复／缺失依赖保持无结果，不信任提交的中间值。提交执行生效租户流程图及已上线可访问子流程；见[流程图运行时](flowchart-runtime)、[共享资源](shared-resources)、[会员与公开页面](member-and-public)。

:::note
2026-10-11 的定向运行验证在 `storage/runtime_final_verify.sqlite3` 上通过 28 个文件、508 个用例，执行了生成 ERB、真实活动／子流程加载、提交及交接回滚、上传字节保留、公开受众隔离和设置操作流程。系统操作流程使用 RackTest；表单条件系统测试检查配置及生成标记，不执行浏览器 JavaScript。命令及证据见 `docs/audits/2026-10-11-rspec-verification.md` 和 `/tmp/opencode/runtime_final_verify.log`。
:::

:::attention
`EntityAttributeAudience.for_user(user, customer_id:)` 仅在显式所访租户内或固定平台所有者时授予角色受众。外租户 admin／member 及租户身份缺失均按 public 处理，覆盖渲染、嵌套字段、下拉、组合列表、校验及保留数据交接。`PageRendering#page_runtime_user` 过滤提交归属，PublicSubmission 也过滤直接传入查看者。真实会话操作者保留，供 Warden、页面授权及请求审计使用。表单 action 使用已解析 `current_customer_id`，别名也一样。
:::

:::attention
GET 上 `PublicPagesController#authorize_public_view!` 要求 `Page#visible_to?(:public)`。集合不含 `public` 的页面，任何会话访问 `GET /:cid/page/:uuid` 都是 404。这些受众使用 `Member::PagesController#show` 与 `Admin::PageFormsController#show`（或维护渲染）。操作对访问者另有对应页时，GET 是 303，不是 404。
:::

:::attention
已登录的管理员不能提交仅面向公开的页面。`page_runtime_audience` 为 `admin`，不在集合中，POST 不写入，走拒绝规则（有管理员对应页则 `continue_here`，否则 `not_for_your_account`）。测试公开表单请退出登录，或把管理员加入受众。
:::

:::attention
`PageRendering#prepare_page_render` 总是把 `@form_action` 设为 `public_page_submit_path`。会员屏和管理员屏都提交到 `PublicPagesController#submit`。`authorize_submission!` 使用 `page.visible_to?(page_runtime_audience)`。符合规则 2 的匿名失败会重定向到登录，并存储 `stored_submission_return_path`。`return_to=admin_form` 只决定符合条件的管理员提交成功后的落点，不授予任何访问权限。
:::

:::attention
共享定义查找允许 NULL 客户实体，但全部记录查询仍限定显式运行租户。共享页面使用 `Current.customer_id`；租户缺失不会扩大记录权限。
:::

:::attention
`PublicSubmission` 要求已上线可访问流程图及非空生效活动。`AudienceGuard` 在放行之后、活动之前运行：`:rejected` 结果不写入任何内容。交接在活动成功后、业务提交前运行；`start_page_handoff` 经守卫重新放行。拒绝回滚新增或既有记录变更，不通过删除返回记录补偿。
:::

:::attention
不要把会员或公开下拉为空当成“显示全部”。`People::Ownership.scope` 失败即关闭：没有访问者、访问者属于其他租户、未知受众、或缺少归属关联时返回空。流程图运行时从不使用该 scope。
:::

:::attention
被篡改或过期的续接为 nil，不是错误。注册仍然成功；确认后会员落到默认路径，而不是记住的操作。不要把缺失的 `_continuation` 当成提交失败。
:::

## 关键代码

```ruby
# app/controllers/concerns/page_rendering.rb
  def prepare_page_render(page, return_to: nil, quick_add: false, prefill: {})
    @form_action = public_page_submit_path(customer_id: current_customer_id, uuid: page.public_uuid,
                                           return_to: return_to)
    @page_quick_add = quick_add
    @page_prefill = prefill
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
# app/models/concerns/page_visibility.rb
  AUDIENCES = %w[admin member public].freeze

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end
```

```ruby
# app/services/pages/form_params.rb
Pages::FormParams.permit(page: page, entity: page.entity,
                       params: params, audience: :public)
Pages::FormParams.permit_identity(page: page, entity: page.entity,
                                  params: params, audience: :public)
```

```ruby
# app/controllers/public_pages_controller.rb
  def assign_page_continuation
    token = params[:continuation].presence || params[:_continuation]
    return unless token.is_a?(String)

    @page_continuation = token if Pages::Continuation.verify(token)
  end
```

```ruby
# app/services/pages/continuation.rb
  def self.verify(token)
    # { action_key:, prefill: } 或 nil — 从不抛错
  end
```

```ruby
# app/services/composite_page_renderer.rb
  def resolve_entity(entity_id)
    return nil unless entity_id && @customer_id
    Entity.find_by(id: entity_id, customer_id: [@customer_id, nil])
  end
```

```ruby
# app/controllers/member/pages_controller.rb
    allow_admin_member_preview!

    def show
      @page = Page.accessible.launched.find(params[:id])
      raise ActiveRecord::RecordNotFound unless @page.visible_to?(:member)

      prepare_page_render(@page)
    end
```
