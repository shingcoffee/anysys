---
title: "国际化"
summary: "英文与简体中文由 SetLocale 按请求选定，文案放在按区域命名的语言文件里，JavaScript 文案走 Stimulus 值。"
---

## 概要

应用有两种语言：`:en`（默认）与 `:"zh-CN"`。`SetLocale` 用 `I18n.with_locale` 包住每一次请求。`LocalesController` 把切换结果写进 cookie；已登录时同时写入 `Authentication::User#locale`。面向用户的文案都走 `I18n`。每一条新文案都要同时有两种语言文件。JavaScript 从 Stimulus 值读取文案：英文 `default` 与英文翻译一致，服务器再把当前语言写到挂载元素上。

`config.i18n.fallbacks` 为 true，因此缺少的 `zh-CN` 键会回退到英文。开发文档与客户操作指南均提供这一对语言，各自使用独立的 Markdown 根目录及翻译作用域。参阅[概览](overview)和[客户使用文档](customer-documentation)。

## 流程

```text
请求
        |
        v
SetLocale#resolved_locale   （around_action，命中即停）
        |
        1. params[:locale]          且必须是可用语言
        2. current_user.locale
        3. cookies[:locale]
        4. Current.customer.locale  （租户默认；未设置则跳过）
        5. Accept-Language          compatible_language_from(available_locales)
        6. I18n.default_locale      （:en）
        |
        v
I18n.with_locale
        |
        v
t(...) / I18n.t(...)  来自 config/locales/<area>.en.yml
                        与 config/locales/<area>.zh-CN.yml

PATCH /locale
        |
        v
LocalesController#update
  cookies[:locale] 保存一年
  已登录时 current_user.update_column(:locale)
  同源来源页：将已有 locale 查询参数替换为受支持的新语言
  来源页缺失、格式错误或不同源：返回根路径
```

## 实现

`config/application.rb` 设置 `config.i18n.available_locales = [:en, :"zh-CN"]`、`config.i18n.default_locale = :en`、`config.i18n.fallbacks = true`，并把 `config/locales/**/*.{rb,yml}` 追加到加载路径。`SetLocale#available` 只接受符号已在 `I18n.available_locales` 中的值。其余值一律忽略，包括 `?locale=xx`。`from_customer` 读取 `Current.customer&.locale`，也就是 `Customer` 上的可选列（空白会规范成 nil）。租户值位于个人选择之下、`Accept-Language` 之上。没有租户时 `Current.customer` 为 nil，这一步跳过。

`LocalesController#update` 是公开动作：不要求租户，也不要求登录。它写入 `cookies[:locale]`，`same_site: :lax`，有效期一年；已登录用户再 `update_column(:locale)`。路由是 `PATCH /locale`。跳转返回同源来源页时，将已有的 `locale` 查询参数替换为经过校验的新语言，避免旧请求参数覆盖已保存的偏好。不含语言参数的来源 URL 保持不变。请求未知语言时，不写 cookie 或用户列，安全的来源 URL 也保持不变，包括其中显式指定的语言。

`locale_redirect_location` 使用 `URI` 解析 URL，通过 `Rack::Utils.parse_query` / `build_query` 处理查询参数。接受以根路径开头的相对 URL；绝对 HTTP(S) URL 必须与请求的协议、主机及端口一致，且不能包含用户信息。来源页缺失、格式错误或不同源时，回退到 `root_path`；请求不受支持的语言时也遵循此规则。替换语言参数时，保留租户与文章路径、搜索条件、其他查询键值（包括重复值及嵌套键）和片段锚点。`redirect_to` 同时设置 `allow_other_host: false`。

文案放在 `config/locales/` 下按区域成对的文件里。每个区域有 `<area>.en.yml` 与 `<area>.zh-CN.yml`，顶层键就是区域名（`maint_platform`、`member`、`help`、`common`、`auth`、`customers`，以及 `comp_*`、`settings_*`、`website_*`、`code_generator_*`）。控制器和视图调用 `t`。模型、Activity 以及其他非控制器 Ruby 在调用时使用 `I18n.t`。常量可以保存键名，不能保存 `t` 或 `I18n.t` 的结果，否则会冻住加载时的语言。英文句子是原文。`zh-CN` 是简体中文，使用全角标点，而不是逐词对译。两边的插值变量保持一致。

`config/locales/en.yml` 与 `config/locales/app.zh-CN.yml` 是没有按 `<area>.en.yml` / `<area>.zh-CN.yml` 命名的那一对。它们存放 `member.security.mfa` 与 `authentication.mfa_recovery`。`layout_catalog.en.yml` 是页面布局选择器的目录（`layout_catalog.templates`、`layout_catalog.categories`、`layout_catalog.groups`）。`validation_copy.en.yml` 补充 `maint_core.pages.configuration_errors` 以及 `maint_core.flowcharts.structure_errors` / `server_validation`；Rails 会把这些键并入 `maint_core`。

Stimulus 控制器把面向用户的字符串声明为带英文 `default` 的值。挂载元素用 `data-<controller>-<name>-value` 传入翻译。`GrantsEditorController` 是这个写法：`savingLabel` 的默认值是 `"Saving..."`，`grants_editor_component.html.erb` 用 `t("comp_admin.grants_editor.saving")` 设置 `data-grants-editor-saving-label-value`。`"{count} change"` 这类 ICU 模板在 JavaScript 里用 `.replace()` 替换。`spec/javascript` 可以不带 data 属性构造控制器，仍然读到英文默认值。

文档的文章标题、摘要和正文放在成对的 Markdown 文件中：开发文档位于 `doc/reference/{en,zh-CN}`，客户指南位于 `doc/customer/{en,zh-CN}`。`CustomerDocs::Catalog` 包含 13 个操作指南 slug，并规定面向任务的必需标题，与开发目录的实现说明标题分开。每套目录的文件和章节都须在两种语言间保持一致；本地化导航标题及页眉取自文首。

`DeveloperDocs::Repository` 在目录、内容根目录和路由 helper 之外接受 `translation_scope:`。默认的 `"developer_docs"` 使用 `config/locales/developer_docs.en.yml` 与 `developer_docs.zh-CN.yml`；`CustomerDocs::Repository` 传入 `"customer_docs"`，对应 `customer_docs.en.yml` 与 `customer_docs.zh-CN.yml`。提示块及锚点文案显式使用仓库选定的语言；缺少对应语言 Markdown 而回退到英文正文时也如此。缓存键包含选定语言及翻译作用域，隔离这些文案。

`DeveloperDocs::ReaderComponent#reader_text` 默认使用 `translation_scope: "developer_docs"`，在渲染时翻译。客户视图传入 `"customer_docs"`，用于目录、搜索、分组、首页／本节导航、上一页／下一页链接及无障碍文案。同一查找方式将本地化的打开／关闭标签传给 `developer-docs-nav` Stimulus 值。首页卡片也从该作用域读取 `home.*` 与 `group_descriptions.*`。帮助菜单的文档标签及客户指南副标题仍在成对的 `chrome.help_menu.docs` 键下。

显式请求语言不会保存为用户偏好；只有 `LocalesController#update` 执行持久化。客户指南导航因此显式保留生效语言：控制器将 `route_options: { locale: current_locale }` 传给仓库，面包屑和返回链接使用 `current_locale`，帮助入口使用 `I18n.locale`。搜索和清除搜索的 URL 仅携带语言查询参数；`ReaderComponent` 接收 `locale: current_locale`，在两个 GET 表单中添加隐藏字段，因为浏览器提交时会替换 action 的查询字符串。仓库缓存键包含路由选项，以隔离带不同语言参数的文章链接。仓库默认的 `route_options: {}` 和阅读器默认的 `locale: nil` 使开发文档链接及搜索表单保持不额外添加语言参数的行为。

两套文档阅读器均通过 `DeveloperDocs::Highlighter` 处理行内代码和围栏代码块。Kramdown 的 gem 级语法高亮注册表不会随 Rails 开发环境重载而清空，因此 `Highlighter.install!` 在每次 Markdown 渲染时注册当前的 `Formatter`。已保留的格式化回调显式解析 `DeveloperDocs::Highlighter.highlight` 与 `DeveloperDocs::Highlighter::PRE_CLASS`，避免经由已卸载的词法父级查找常量。`spec/services/developer_docs/highlighter_spec.rb` 中的重载回归测试执行两次真实 Rails 重载，并验证每次重载前保留的回调仍能处理代码。

### 流程图动作键

流程图步骤动作的文案放在 `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`（每个领域一对，如 `flowchart_actions_communication`、`flowchart_actions_sms_document`、`flowchart_actions_outcome_payments`），共用字段标签与代码在 `flowchart_actions_shared`，分类与空选项标签在 `flowchart_actions_catalog`，通用运行时消息在 `flowchart_runtime.{en,zh-CN}.yml`。每个动作有 `flowchart_actions.<action>.{label, description, fields.<field>.{label, help, placeholder, options}, errors.<code>}`，其发出代码传给 `Step.fail` 的代码放在 `flowchart_runtime.errors.<action>.<code>`。`ActionCatalog.export(locale:)` 在调用时解析这些键，`Step.fail` 按请求语言翻译运行时代码。文件布局与查找顺序见 [代码生成器](code-generators)。

测试环境设置了 `config.i18n.raise_on_missing_translations = true`（`config/environments/test.rb`），视图、组件或 `t` 调用遇到缺失键会让对应测试失败。`spec/services/code_generators/action_i18n_keys_spec.rb` 检查目录中的每个动作：标签、说明、字段标签与选项标签、`validate` 代码和运行时代码必须在两种语言中以 `I18n.exists?(key, locale, fallback: false)` 存在；运行时代码须为字面量或显式展开，以便测试逐一列举；`en` 与 `zh-CN` 的 `%{}` 变量必须一致。

## 需要特别注意

:::attention
`SetLocale#resolved_locale` 在第一个受支持的值处停止。已登录用户的 `Authentication::User#locale` 优先于 `Customer#locale`，也优先于 `Accept-Language`。`LocalesController` 同时写 cookie 和用户列，并替换返回 URL 中旧的显式语言参数。因此，跳转后的请求在含语言参数时于第 1 步使用新选择的语言；不含语言参数时先命中第 2 步，再考虑 cookie。
:::

:::attention
`SetLocale#available` 丢掉 `I18n.available_locales` 以外的任何语言。增加第三种语言要改 `config/application.rb` 并补上两个文件。`LocalesController` 已经检查 `I18n.available_locales`，不必再为它单独加分支。只加了 `en`、没有在 `zh-CN` 放上同一键和同一组插值变量的条目，运行时会回退到英文，这一改动仍然不完整。
:::

:::attention
`GrantsEditorController` 把英文放在 `static values` 的默认值里，并读取 `this.savingLabelValue` 以及其他标签值。翻译后的字符串只来自 `Admin::Settings::Modules::Authentication::GrantsEditorComponent` 用 `t` 渲染的 `data-grants-editor-*-value`。写在控制器函数体里的字面量是语言切换改不了的硬编码。
:::

:::attention
`Customer` 把空白 `locale` 规范为 nil，并校验其属于 `I18n.available_locales`。这一列是 `SetLocale#from_customer` 里的租户默认语言。它不会覆盖 `params[:locale]`、`current_user.locale` 或 `cookies[:locale]`。
:::

:::attention
Markdown 正文回退不能满足双语完整性。每篇客户指南都须提供两种语言，并包含「开始前」「操作步骤」「预期结果」「常见问题」「相关指南」，或 `CustomerDocs::Catalog::REQUIRED_HEADINGS` 规定的英文对应标题。不要在 Ruby 常量中翻译，也不要硬编码阅读器文案；在渲染时选择正确的翻译作用域。
:::

## 关键代码

```ruby
# config/application.rb
config.i18n.available_locales = [:en, :"zh-CN"]
config.i18n.default_locale    = :en
config.i18n.fallbacks         = true
config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}")]
```

```ruby
# app/controllers/concerns/set_locale.rb
def resolved_locale
  from_params ||
    from_current_user ||
    from_cookie ||
    from_customer ||
    from_header ||
    I18n.default_locale
end
```

```ruby
# app/controllers/locales_controller.rb
def update
  locale = requested_locale

  if locale
    cookies[:locale] = { value: locale.to_s, expires: 1.year, same_site: :lax }
    current_user&.update_column(:locale, locale.to_s) if user_signed_in?
  end

  redirect_to locale_redirect_location(locale), allow_other_host: false
end
```

```javascript
// app/javascript/controllers/grants_editor_controller.js
    dirtyCountSingularFormat: { type: String, default: "{count} change" },
    dirtyCountPluralFormat: { type: String, default: "{count} changes" },
    grantedCounterFormat: { type: String, default: "{granted} / {total} granted" },
    discardConfirmFormat: { type: String, default: "Discard {count} change(s)?" },
    savingLabel: { type: String, default: "Saving..." },
    saveGrantsLabel: { type: String, default: "Save grants" },
```
