---
title: "代码生成器"
summary: "GeneratorRegistry 如何发现流程图生成器，步骤动作与元素类型如何用 config_schema 声明字段并导出动作目录与元素目录，遵循哪些发出辅助方法与方法体规则，决策、条件与接线如何编译，以及平台界面如何编辑这些 Ruby 文件。"
---

## 概要

`CodeGenerators::GeneratorRegistry` 是 `ActivityGenerator` 用来把流程图编译成 `Trailblazer::Activity::Railway` 类的目录。每种画布元素类型、每个过程步骤动作，都是 `app/services/code_generators/element_types` 下的一个 Ruby 类。注册表在启动时扫描目录来找到这些类。没有 `register!` 调用，也没有图解释器。编译后的 Activity 如何执行，见 [流程图运行时](flowchart-runtime)。画布如何存储图，见 [流程图构建器](flowchart-builder)。逐个动作的参考（每个字段、角色、默认值与输出）见 [流程图步骤动作](flowchart-step-actions)。

每个步骤动作都用 `config_schema ported: true` 把配置声明一次。这份声明同时驱动校验、编辑器步骤表单（经 `CodeGenerators::ActionCatalog.export`）、助手调色板，以及生成器经一小组辅助方法（`value`、`read`、`literal`、`assign`、`fail_with`、`attempt`、`body`）发出的 Ruby。标签、帮助文本、选项标签和校验消息放在 `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml`。

元素类型（`start`、`end`、`decision`、`loop`、`subflow`）以同样方式声明字段。`CodeGenerators::ElementCatalog.export` 把这些模式、连接字段（`CodeGenerators::ConnectionSchema`）和条件运算符（`CodeGenerators::ConditionOperators`）组成元素属性表单读取的目录。相关文本放在 `config/locales/flowchart_elements*.{en,zh-CN}.yml`。

平台界面是 `Admin::Maintenance::Platform::CodeGeneratorsController`，路径 `/:customer_id/admin/maintenance/platform/code_generators`。该路径在 `/admin/maintenance/platform/` 下，因此只面向 `platform_owner?`。创建或更新生成器会写入 `.rb` 文件，重新加载 Zeitwerk，并调用 `GeneratorRegistry#reload!`。

支付、验证码和邮件厂商是另一套规则：在对应模块的 provider 目录里新增一个文件。它们不是这张注册表里的行。实体页面上展示的 `ModelGenerator` 与 `ContractGenerator` 也不在这张表里。

## 流程

```text
app/services/code_generators/element_types/
        |  start end decision loop subflow     （config_schema ported: true）
        |  process/<category>/*_generator.rb   （config_schema ported: true）
        v
GeneratorRegistry#discover!
        |  step_actions 哈希 + element_types 哈希
        +--> ActionCatalog.export(locale:)     编辑器步骤表单、助手调色板
        +--> ElementCatalog.export(locale:)    元素与连接表单、运算符
        v
ActivityGenerator#generate
        |  流程图名称为空或 elements 为空则 nil
        |  find_element_type / find_step_action
        |  validate_config -> generate_body
        v
Ruby 源码写入 Flowchart#activity

平台所有者界面
        |
        v
CodeGeneratorsController
        |  SourceAssembler + GeneratorValidator
        |  在 element_types/ 下 File.write
        v
GeneratorRegistry#reload!

预览 / 测试
        |
        +-- PreviewsController     generate_step_method(sample_input)
        +-- TestRunsController     TestRunner.run
        +-- ValidationsController  GeneratorValidator.validate_source
        +-- IoParams / ElementTypeIoParams
```

流程图没有名称或没有元素时，`ActivityGenerator#generate` 返回 `nil`。找不到生成器时不会返回 `nil`：它抛出 `ActivityGenerator::Error`，代码为 `:unknown_element_type` 或 `:unknown_step_action`。

## 实现

### 注册表

`CodeGenerators::GeneratorRegistry.instance` 在 `discover!` 里建立两张哈希。

元素类型是 `app/services/code_generators/element_types` 下、名称属于 `SUPPORTED_ELEMENT_TYPES` 的子目录：`start`、`end`、`decision`、`loop`、`subflow`。这一轮会跳过 `process` 目录。

步骤动作是 `element_types/process/<category>/` 下的每个 `*_generator.rb`。分类目录为 `background`、`caching`、`communication`、`concurrency`、`data_operations`、`file_operations`、`model_operations`、`outcome`、`payments`、`resilience`、`scheduling_time`、`security`、`service_invocation`、`utility`、`validation`。新的分类目录会在下一次 `discover!` 或 `reload!` 时被扫到。加载失败的文件在非生产环境抛出，在生产环境记日志并跳过。

类只有在响应 `registered_names` 时才会被索引。`GeneratorInterface#registered_names` 返回元数据里的单个 `generator_name`，否则是去掉 `Generator` 后缀、再做 demodulize 的类名。没有别名：存储的 `step.action` 必须等于某个生成器名。重名会记一条警告，后加载的类胜出。`GeneratorRegistry.all` 是两张哈希的唯一类集合。`PathIdentity.find(slug)` 把去掉 `CodeGenerators::` 前缀并做 underscore 的 `klass.name` 与 URL slug 比对。

类名包含 `ElementTypes::Process` 时，`generator_kind` 为 `:step_action`；包含 `ElementTypes` 时为 `:element_type`。

### 基类

`CodeGenerators::BaseGenerator` 引入 `GeneratorInterface`、`Shared::CtxReader`、`Shared::ConfigFieldReader`、`Shared::IdentifierSanitizer`、`Shared::ExpressionSafety`。`#initialize` 保存元素和上下文字段。元素类型的 `extract_config` 读 `properties`，步骤动作读 `config`。

`generate_step_method` 把 `generate_body` 包进 `def <step_name>(ctx, **)`，并用 `Prism.parse` 断言结果可解析；否则抛出 `CodeGenerators::GeneratorError`，消息为 `maint_core.flowcharts.generator_error`。子类实现 `generate_body`。`generator_metadata` 经 `MetadataDSL` 记录名称、描述、分类、版本、`presentation(icon:, color:, single_use:, privileged:)` 和 `error_strategy_default`。

`ported: true` 的生成器由声明的 schema 提供 `validate_config`。78 个步骤动作和全部 5 个元素生成器均已移植。未移植分支（`GeneratorInterface#validate_config` 加 `unsafe_ctx_expression_errors`）仍留在 `BaseGenerator` 中，但已注册的生成器都不会走到。

没有步骤级包装。`ActivityGenerator#generate_step_code` 用 `find_step_action(action)` 查找，校验后返回 `generate_body`。步骤本身没有条件、重试或超时设置：条件执行是在过程框前放一个决策，传输重试与超时是声明了它们的 HTTP 类动作的字段（见“能力声明”）。

`StartGenerator` 是最简单的元素类型：元数据、空的 `config_schema ported: true` 块（因此结构键之外的任何存储键都是 `unknown_field`），以及返回 `nil` 的 `generate_body`，因为起点在遍历中被跳过。`ActivityGenerator` 把 `process`、`start`、`end` 当作 `STEP_CONTAINER_ELEMENT_TYPES`：元素类型的 body 为 nil 时，改走嵌套的步骤动作。

### config_schema 角色与选项

`config_schema ported: true do … end` 构建一个 `CodeGenerators::ConfigSchema`。每条语句是一个角色加字段名：

| 角色 | 存储值 | 校验 | `read(:field)` 发出 |
|------|--------|------|---------------------|
| `input` | ctx 路径，如 `params.email` | 标识符路径，最多 4 段；根不得保留 | `ctx[:root]` 或 `FlowchartRuntime::Step.dig(ctx[:root], :a, 0)` |
| `output` | ctx 键 | 标识符；不得是 `OUTPUT_RESERVED` 名称 | 键本身（配合 `assign`） |
| `expression` | Ruby 源码 | 单条语句，`safe_expression?` | `(source)` |
| `literal` | 字符串 | `max_length` | 字符串字面量 |
| `template` | Liquid 源码 | 可解析 | `FlowchartRuntime::Template.render("…", ctx)` |
| `enum` | `values` 之一 | `not_in_list` | 字符串字面量 |
| `flag` | JSON 布尔值 | `not_boolean` | `true`／`false` |
| `integer`／`decimal` | 数字 | `min`／`max` | `Integer`／`Float` 字面量 |
| `list` | 数组；`item:` 角色 | 逐项 | 字符串字面量数组 |
| `mapping` | `[{ "key", "value" }]`；`key:`／`value:` 角色 | 逐对 | 哈希字面量 |
| `conditions` | 决策式条件组 | `invalid_conditions` | 条件表达式 |
| `entity_attribute` | 属性 slug；`of: :bound` | 生成器上下文有绑定实体时对照校验 | 字符串字面量 |
| `reference` | 来自 `source:` 的值 | 只查是否填写 | 字符串字面量 |
| `localized_text` | `{ "en", "zh-CN" }` | `en` 必填 | 哈希字面量 |

字段选项：`default`、`required`、`example`、`visible`（`{ field: value }` 规则）、`group`（`:main` 或 `:advanced`）、`placeholder`、`max_length`、`multiline`、`min`、`max`、`values`、`item`、`key`、`value`、`of`、`source`。未知选项或未知语句会在类加载时抛出 `ArgumentError`。`requires :field, when: { other: value }` 让字段按条件必填，同时隐含其显示条件。`validate { |cfg, errors| errors.add(:field, :code, **vars) }` 添加跨字段规则。隐藏字段既不校验也不读取，`value(:field)` 返回默认值。`sample_input` 是默认值合并各字段的 `example`。

保留名称（`CodeGenerators::ConfigSchema`）：

- `SEEDED_KEYS`：`params bound_entity customer_id authentication current_user_id current_user_role audience device_type request_ip user_agent locale request_id flowchart_id`，即运行开始时就有的键（见 [流程图运行时](flowchart-runtime)）。
- `OUTPUT_RESERVED`：`SEEDED_KEYS` 加 `errors error_details submission_outcome result`。`output` 字段不得取这些名字。
- `INPUT_FORBIDDEN_ROOTS`：`errors error_details submission_outcome result`。`input` 路径不得以它们开头。

### 能力声明：传输重试、超时、熔断器

三条语句为 HTTP 类动作追加标准的高级字段。导出把它们列在 `capabilities` 下，步骤表单据此渲染一个共用面板。

- `transport_retry(idempotent_when: { httpMethod: %w[GET HEAD PUT DELETE OPTIONS] }, or_present: :idempotencyKey)` 追加 `retryOnTransportError`（开关，默认 false）与 `retryAttempts`（整数 1–2，默认 1）。对非幂等且无幂等键的请求开启重试，校验报 `retry_not_idempotent`。`idempotent_when` 为空表示该动作始终幂等（`download_file`）。
- `timeouts(open: 3, read: 7)` 追加 `connectTimeout`（1–5）与 `readTimeout`（1–9）。两者之和不得超过 `RUN_LIMIT_SECONDS`（10），否则报 `timeout_exceeds_run_limit`，带 `cap`。
- `circuit_breaker_option` 追加 `circuitBreaker`（开关）、`breakerName`（默认为动作键）、`failureThreshold`（1–20，默认 5）、`resetTimeoutSeconds`（10–3600，默认 60）。

`api_call` 与 `send_webhook` 三者齐全；`download_file` 有重试、超时和熔断器；`ai_inference`、`currency_convert`、`geolocation_lookup` 只有超时和熔断器。运行时一侧是 [流程图运行时](flowchart-runtime) 中的 `FlowchartRuntime::Http.request`。

### 校验错误与 I18n 键

`validate_config` 返回 `ConfigSchema::ConfigError(field, code, message)`。消息在调用时依次查找 `flowchart_actions.<action>.errors.<code>`、`flowchart_actions.shared.errors.<code>`。共用代码：`required`、`invalid_identifier`、`reserved_name`、`invalid_expression`、`not_one_statement`、`too_long`、`invalid_template`、`not_in_list`、`not_boolean`、`invalid_integer`、`out_of_range`、`invalid_decimal`、`invalid_list`、`invalid_mapping`、`invalid_conditions`、`unknown_attribute`、`unknown_reference`、`en_required`、`retry_not_idempotent`、`timeout_exceeds_run_limit`。流程图服务端校验把每条包装为 `maint_core.flowcharts.config_problems.step_invalid`。

元素模式使用前缀 `flowchart_elements`：先查 `flowchart_elements.<type>.errors.<code>`，再查 `flowchart_elements.shared.errors.<code>`（`required`、`unknown_field`、`unknown_reference`、`not_in_list`、`invalid_expression`、`not_one_statement`、`invalid_conditions`）。校验器把它们包装为 `maint_core.flowcharts.config_problems.element_invalid`，并把每条错误的 `field` 带到 `element_config_invalid` 问题上。

每个动作的键放在其所属领域文件 `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml` 中：

```yaml
en:
  flowchart_actions:
    send_sms:
      label: Send SMS
      description: …
      fields:
        templateKey:
          label: …
          help: …
          placeholder: …
          options: { … }        # enum option labels, keyed by the normalized value
      errors: { … }             # action-specific validate codes
  flowchart_runtime:
    errors:
      send_sms:
        suppressed: …           # codes the emitted code passes to Step.fail
```

字段文本回退到 `flowchart_actions.shared.fields.<field>`。枚举选项键为 `value.to_s.downcase.gsub(/[^a-z0-9]+/, "_")`。分类标签为 `flowchart_actions.categories.<key>`，空选项标签为 `flowchart_actions.shared.none`（均在 `flowchart_actions_catalog`）。通用运行时代码（`record_not_found`、`timed_out`、`http_status`、`circuit_open`、`blocked_destination` 等）在 `config/locales/flowchart_runtime.{en,zh-CN}.yml`。领域文件有 `background_file`、`cache_lock_schedule`、`catalog`、`communication`、`data_collections`、`data_text`、`data_values`、`model_queries`、`model_records`、`outcome_payments`、`records_new`、`resilience`、`security`、`service_utility`、`shared`、`sms_document`、`tables_new`、`validation`。见 [国际化](internationalization)。

### ActionCatalog 导出

`CodeGenerators::ActionCatalog.export(locale:)` 返回：

- `locale`、`categories`（`[{ key, label }]`，只含用到的分类，按 `CATEGORY_ORDER`：`model validation data communication security background file caching concurrency resilience scheduling payments outcome service utility`）以及 `actions`（按分类再按键排序）。
- 每个动作：`key`、`category`、`label`、`description`、`icon`、`color`、`singleUse`、`privileged`、`fields`、`capabilities`（`transportRetry { idempotentWhen, orPresent, maxAttempts: 2 }`、`timeouts { open, read, cap }`、`circuitBreaker`）。
- 每个字段（`ActionCatalog::FieldPresenter`）：`name`、`role`、`control`、`label`、`help`、`placeholder`、`default`、`required`、`group`、`options`、`min`、`max`、`visibleWhen`、`requiredWhen`、`variablePicker`、`source`、`itemRole`、`keyRole`、`valueRole`、`multiline`、`maxLength`。可选枚举在最前面多一个 `{ value: "", label: <无> }` 选项。
- `digest`：对与语言无关的载荷（键、分类、展示属性、字段结构、选项值和能力）做 SHA-256。schema 变化时它会变，`en` 与 `zh-CN` 之间保持一致。

元数据分类按目录命名；`CATEGORY_FROM_METADATA` 把 `model_operations`→`model`、`data_operations`→`data`、`file_operations`→`file`、`scheduling_time`→`scheduling`、`service_invocation`→`service`。`customer:` 参数被接受但未使用。JSON Schema 为 `app/services/code_generators/action_catalog.schema.json`；`action_catalog_contract_spec` 用它校验 `en`、`zh-CN` 导出和夹具。

编辑器把导出嵌在 `app/views/admin/maintenance/flowcharts/_editor.html.erb` 的画布挂载点上，即 `data-flowchart-canvas-action-catalog-value`；`flowchart_canvas_controller.js` 把它交给 `setActionCatalog`（`flowchart/constants/action_registry`），步骤表单从那里读取。助手调色板由 `FlowchartDefinitions::Assistant::SchemaGenerator` 基于同一目录生成。

两个任务写入供测试比对的快照：

- `bin/rails action_catalog:fixture`：由 `ActionCatalog.sample_export`（一个仅供测试的夹具生成器，加 `find_model`、`api_call`、`assign_value`、`send_template_email`、`query_models`）写出 `spec/javascript/fixtures/action_catalog.sample.json`，供 Vitest 使用。
- `bin/rails ai_assistant:flowchart_schema`：重新生成助手的 `structure_schema.palette.json`。

### 元素模式与 ElementCatalog

元素生成器用 `config_schema ported: true` 声明各自的 `properties`，角色与选项和步骤动作相同。流程没有元素生成器，也没有元素字段；它唯一的动作在步骤页。

| 类型 | 字段 | 角色 | 默认值 | 显示条件 | 说明 |
|------|------|------|--------|----------|------|
| `start` | — | — | — | — | 只有名称与备注 |
| `end` | `responseType` | `enum` `none`／`value` | `none` | 始终 | 必填；省略时由默认值补上 |
| `end` | `returnValue` | `expression` | — | `responseType: value` | 显示时必填；写入 `ctx[:response]` |
| `decision` | `routeBy` | `enum` `value`／`condition` | `condition` | 始终 | 必填 |
| `decision` | `subject` | `expression` | — | `routeBy: value` | 显示时必填 |
| `decision` | `condition` | `conditions` | — | `routeBy: condition` | 显示时必填；平铺条件组 |
| `loop` | `loopType` | `enum` `while`／`for_each` | `while` | 始终 | |
| `loop` | `runOnceFirst` | `flag` | `false` | `loopType: while` | |
| `loop` | `condition` | `conditions` | — | `loopType: while` | 显示时必填 |
| `loop` | `collection` | `input` | — | `loopType: for_each` | 显示时必填；不带 `ctx.` 的路径 |
| `loop` | `itemVariable` | `literal` | `item` | `loopType: for_each` | |
| `loop` | `maxIterations` | `integer` 1–10,000 | `100` | 始终 | |
| `loop` | `stopWhen` | `conditions` | — | 始终 | `group: :advanced` |
| `loop` | `skipWhen` | `conditions` | — | `loopType: for_each` | `group: :advanced` |
| `loop` | `indexVariable` | `literal` | `index` | `loopType: for_each` | `group: :advanced` |
| `loop` | `collectInto` | `output` | — | `loopType: for_each` | `group: :advanced` |
| `subflow` | `flowchartId` | `reference`（`source: :flowcharts`） | — | 始终 | 必填 |

元素模式与步骤动作模式只差一条规则：`ConfigSchema#validate_unknown_keys` 把每个未声明的键报为 `unknown_field`，`STRUCTURAL_CONFIG_KEYS`（`description label steps condition io_overrides inputs outputs`）除外。步骤动作忽略多余的键。生成器在 `validate` 块中添加跨字段规则：`DecisionGenerator` 检查分支拓扑（见“决策生成器”），`LoopGenerator` 检查集合路径、`itemVariable`／`indexVariable`（`reserved_header_local`、`colliding_loop_variables`）及其条件组。

共用部件：

- `CodeGenerators::ConnectionSchema`：`literal :label` 与 `literal :description, multiline: true`（文本在 `flowchart_elements.connection.fields.*`）。它只描述连接表单，服务端不按它校验连接属性。`matchValue` 与 `fromPort` 是分支页写入的连接属性，不是模式字段。
- `CodeGenerators::ConditionOperators`：`BINARY`（`== != > >= < <= contains starts_with ends_with matches_regex in_range is_type`）、`UNARY`（`is_true is_false is_empty is_not_empty is_nil`）和 `COUNT`（`== != > >= < <=`，用于记录数比较）。标签为 `flowchart_elements.operators.<key>`。生成的记录数条件通过 `FlowchartRuntime::EntityResolver.find(id, customer_id: ctx[:customer_id])` 加载实体，其他租户的实体会抛错而不会被计数。
- `CodeGenerators::ConditionRules.errors(condition, field:, required:)`：为判断的 `condition` 和循环的 `condition`／`stopWhen`／`skipWhen` 校验平铺条件组，通过校验的条件组一定能构建。代码在 `flowchart_elements.conditions.errors` 下：`invalid_condition`、`empty_condition`、`invalid_row`、`nested_group`、`missing_entity`、`unknown_count_operator`、`missing_left`、`missing_operator`、`unknown_operator`、`missing_right`、`invalid_regex`。空值与非 Hash 值交给模式处理（`required`、`invalid_conditions`）。
- `Shared::ConditionBuilder` 把条件组编译成 Ruby。遇到未知运算符、未知计数运算符或嵌套组时抛出 `ArgumentError`，不再回退到 `==`。`is_true` → `!!left`，`is_false` → `!left`，`is_empty`／`is_not_empty` → `blank?`／`present?`，`is_nil` → `nil?`；`> >= < <=` 经 `FlowchartRuntime::ConditionInput.compare`。

`CodeGenerators::ElementCatalog.export(locale:)` 返回：

- `locale` 与 `types`，按 `TYPE_ORDER`（`start end process decision loop subflow`）排列；每种类型含 `type`、`label`、`defaultLabel`、`tabs`、`fields`。
- `tabs`：`general`，然后 `steps`（流程）或 `branches`（判断），然后 `io`，任一字段带 `group: "advanced"` 时再加 `advanced`（目前只有循环）。
- `fields`：与步骤字段相同的 `ActionCatalog::FieldPresenter` JSON（`name`、`role`、`control`、`label`、`help`、`placeholder`、`default`、`required`、`group`、`options`、`min`、`max`、`visibleWhen`、`requiredWhen`、`variablePicker`、`source` 等），以 `i18n_prefix: "flowchart_elements"` 生成。流程导出 `[]`。
- `connection.fields`（来自 `ConnectionSchema`）、`operators`（`ConditionOperators.export`：`{ value, label, unary, count }`）与 `chrome`（`label` 与 `notes`，后者的存储 `key` 为 `description`）。元素与连线 `description` 字段的“备注”标签共用 `common.labels.notes`。
- `digest`：对与语言无关的结构（类型、页签、字段结构、选项值、连接字段、运算符值）做 SHA-256；`en` 与 `zh-CN` 相同。

已注册的元素生成器若不是 `config_schema ported: true`，导出时抛出 `ArgumentError`。`app/views/admin/maintenance/flowcharts/_editor.html.erb` 把导出嵌在画布根节点上，即 `data-flowchart-canvas-element-catalog-value`，只嵌一次；`flowchart_canvas_controller.js` 把它交给 `flowchart/constants/element_registry.js` 的 `setElementCatalog`（`elementFields`、`elementTabs`、`elementLabel`、`elementDefaultLabel`、`connectionFields`、`conditionOperators`、`chrome`）。之所以嵌在画布而不是属性编辑器上，是因为画布也要预置元素默认值。编辑器没有 JavaScript 模式文件：原先的 JS 模式副本、它的 Ruby 镜像任务和 CI 一致性检查都已删除，Ruby 模式是唯一来源。Vitest 读取 `spec/javascript/fixtures/element_catalog.sample.json`（一份 `en` 导出），用 `bin/rails element_catalog:fixture` 重新生成；与新导出不一致时 `element_catalog_spec.rb` 会失败。

助手使用同一套模式：其调色板按目录列出每种元素的 `config_fields`（角色、必填、默认值、选项、min/max、`visibleWhen`），`FlowchartDefinitions::Palette::ELEMENT_DOCS` 只补充模式无法表达的行为（连线规则、决策分支在连线上、条件组结构、循环语义）。`FlowchartDefinitions::UiConfigSchema` 用 `ConfigSchema#visible_defaults` 预置元素默认值（只取默认值下可见的字段，因此终点只预置 `responseType: "none"`），`FlowchartDefinitions::Normalizer` 用当前语言的 `flowchart_elements.<type>.defaultLabel` 为新元素命名。

元素文本分布在四对语言文件中，`en` 与 `zh-CN` 的键和 `%{}` 变量完全一致：

- `flowchart_elements.{en,zh-CN}.yml`：`chrome`、`shared`（`none`、`errors`）、各类型的 `label`／`defaultLabel` 及开始／结束／子流程字段、`connection.fields`、`template_labels`、`trace`。
- `flowchart_elements_conditions.*`：`operators` 与 `conditions.errors`。
- `flowchart_elements_decision.*` 与 `flowchart_elements_loop.*`：对应类型的 `fields` 与 `errors`。

字段键为 `flowchart_elements.<type>.fields.<field>.{label,help,placeholder,options.<value>}`。`element_i18n_keys_spec` 检查每个导出键在两种语言中都存在；`spec/config/flowchart_elements_locale_spec.rb` 检查每对 `flowchart_elements*.yml` 的键与 `%{}` 一致。修改元素字段的步骤：改生成器的 `config_schema`，在两种语言中补齐键，更新生成器测试，然后运行 `element_catalog_spec`、`element_i18n_keys_spec`、`flowchart_elements_locale_spec` 与 `bin/rails ai_assistant:flowchart_schema`，并刷新 JS 夹具。

### 发出辅助方法

已移植的生成器用辅助方法拼装 `generate_body`，不直接拼接配置字符串：

- `value(:f)`：原始存储值，或默认值。
- `read(:f)`：角色表中对应的 Ruby。无法安全发出的值抛出 `GeneratorError`，消息为 `maint_core.flowcharts.generator_unsafe_value`。
- `literal(v)`：`v.inspect`。
- `assign(:outputField, expr)`：检查键是安全标识符后发出 `ctx[:<存储的键>] = expr`。
- `fail_with(code, field:, unless:, **details)`：`return FlowchartRuntime::Step.fail(ctx, :code, field: :f, …) unless expr`。动作级代码要带引号传入，如 `attempt('"clone_model.failed"', …)`，符号即为 `:"clone_model.failed"`。
- `attempt(code, *error_classes) { lines }`：`FlowchartRuntime::Step.attempt(ctx, :code, Classes) do … end`，只救援列出的类。
- `body(*lines)`：拼接非 nil 行。

```ruby
# app/services/code_generators/element_types/process/payments/refund_payment_generator.rb
          def generate_body
            args = [
              "payment: #{read(:payment)}",
              "amount: #{read(:amount)}"
            ]
            args << "reason: #{read(:reason)}" if value(:reason).to_s.strip.present?
            body("FlowchartRuntime::Payments.refund(ctx, #{args.join(', ')})")
          end
```

### 方法体规则（BodyLint）

`CodeGenerators::BodyLint.check(body, outputs:)` 是全目录的规则集。它在测试中运行（`ported_catalog_spec` 逐个检查每个动作的示例方法体，含每个枚举变体），生成时不运行：

- 非空行最多 `MAX_LINES`（12）行；
- 禁止：`ctx[:result]`、已退役的私有“上次错误”键、`Timeout.timeout`、`sleep`、`rescue => e`、`rescue StandardError`、`rescue Exception`、`I18n.t`；
- 不得出现裸局部变量 `params` 或 `model`（用 Prism 检测），要从 `ctx` 读取；
- `unchecked_fallible`：在 `.save`、`.destroy`、`.update`、`.deliver*`、`Http.request`、`Entries.save|upsert|destroy` 或 `Gateway.send` 之后以 `true` 结尾；
- `undeclared_output`：每个 `ctx[:key] =` 必须是已声明的输出或 `STANDARD_WRITES`（`model contract errors error_details submission_outcome current_user`）之一。

`runtime_facade_emission_spec` 另外要求：对会抛错的运行时门面（如 `FlowchartRuntime::Document.pdf`）的调用，必须包在带该门面 `Error` 的 `Step.attempt` 里。

### 引用来源

`reference` 字段指向 `CodeGenerators::ReferenceSources` 中的来源：`email_templates`、`sms_templates`、`constants`、`entities`、`entity_associations`、`pages`、`flowcharts`、`job_classes`、`service_classes`。每个来源实现 `options(customer:, query:, limit: 50, **filters)`（`entity_associations` 按 `entity_id` 过滤；`flowcharts` 排除 `exclude_id`）。`constants`、`entities`、`pages`、`flowcharts` 经 `accessible(relation, customer)` 过滤，即 `where(customer_id: [customer.id, nil])`，无客户时为 `none`（`pages` 与 `flowcharts` 只列已上线的行）。`flowcharts` 为子流程的 `flowchartId` 选择器提供选项，返回 `{ value: id, label: name }`。`email_templates` 列出本客户已启用的模板，`sms_templates` 列出已启用的平台模板（按键），`job_classes` 列出 `app/jobs` 下的 `ApplicationJob` 子类，`service_classes` 列出 `Invocable::SERVICE_ALLOWLIST`。

步骤表单从 `GET /:cid/admin/maintenance/flowcharts/reference_options/:source.json`（平台前缀：`/81721200/admin/maintenance/platform/flowcharts/reference_options/:source.json`）加载选项，由 `Admin::Maintenance::FlowchartReferenceOptionsController#show` 提供。它与编辑器其余部分一样只对所有者开放（`RouteAuthorization` 加 `FlowchartVisibility`）。只响应 JSON（其他格式 406）；未知来源返回 404，消息为 `maint_core.flowcharts.reference_options.unknown_source`；`q` 截到 100 个字符，结果最多 50 条，接受整数 `entity_id` 与整数 `exclude_id`（只有 `flowcharts` 读取；编辑器目前不发送），响应 `{ options: [{ value, label }] }`。路由把 `source` 约束为 `/[a-z][a-z0-9_]*/`。编辑器用 `urls.referenceOptions` 中带 `__SOURCE__` 占位符的模板拼出 URL。

### 如何新增步骤动作

1. 新增一个文件 `app/services/code_generators/element_types/process/<category>/<action>_generator.rb`：继承 `BaseGenerator`，带 `generator_metadata`（名称、分类、展示属性）、`config_schema ported: true`，以及用发出辅助方法拼装且通过 BodyLint 的 `generate_body`。
2. 在一对语言文件 `config/locales/flowchart_actions_<area>.{en,zh-CN}.yml` 中补齐键：标签、描述、每个字段的标签（用到时还有帮助、占位符、选项标签）、每个动作级 `validate` 代码，以及方法体传给 `Step.fail` 的每个运行时代码（放在 `flowchart_runtime.errors.<action>`）。两种语言的键与 `%{}` 变量必须一致。
3. 新增生成器测试，再运行 `action_i18n_keys_spec`（每个目录键在两种语言中以 `fallback: false` 存在；运行时代码须为字面量或显式展开）、`runtime_facade_emission_spec`、`ported_catalog_spec`、`generator_inventory_spec`（预期键列表）和 `action_catalog_contract_spec`。
4. 快照包含该动作时重新生成：`bin/rails action_catalog:fixture` 与 `bin/rails ai_assistant:flowchart_schema`。
5. 把动作补进 [流程图步骤动作](flowchart-step-actions)。

测试环境设置了 `config.i18n.raise_on_missing_translations = true`，缺键会让渲染它的测试失败。

### ActivityGenerator 如何委托

对非容器元素，`method_body` 调用 `find_element_type(type)`，构造 `generator_class.new(element, context)`，并使用 `generate_body`。对过程元素，`generate_process_body` 映射 `properties.steps`。`generate_step_code` 查找 `find_step_action(action)`，然后 `validate_generator!`。过程框最多一个动作（`StructureValidator`／`steps.maxItems: 1`）。该动作体就是步骤方法体，不再包 lambda。空过程发出 `true`。动作返回 false 或 nil 时，Railway 步骤失败。

`Flowchart#generate_activity` 赋这个结果；保存若是租户覆盖，则在赋值前直接返回。见 [流程图构建器](flowchart-builder)。编译后的 Railway 形状（每框一步、`CANVAS`、`collect_errors`）见 [流程图运行时](flowchart-runtime)。

### 决策生成器

`DecisionGenerator`（版本 2.0.0）读取 `routeBy`：`condition`（默认）用 `Shared::ConditionBuilder` 编译 `condition` 条件组；`value` 用 `read(:subject)` 与各分支的匹配值比较。分支数据从不从元素读取：分支就是出边，由 `ActivityGenerator::NameDeriver.outgoing_branches` 按 `fromPort`（`port_N`，其次原始顺序）排序。

没有流程图拓扑时（代码生成器预览、独立测试运行、I/O 提取），`generate_body` 返回求值后的条件或取值表达式的 `.to_s`：

```ruby
(!!ctx.dig(:vip) || FlowchartRuntime::ConditionInput.compare(ctx.dig(:total), ">=", 500))
(ctx[:tier]).to_s
```

有拓扑时（`context[:flowchart_topology][:outgoing_branches]`，每项 `{ "signal", "semantic", "matchValue" }`）返回所选分支的信号。是／否模式发出三元式，指向 `true` 分支与 `false` 分支（没有则「其他」）；取值模式发出 `case`／`when`，`else` 指向「其他」分支（空匹配值），没有则为最后一个分支。

```ruby
  def is_vip(ctx, **)
    ((!!ctx.dig(:vip) || FlowchartRuntime::ConditionInput.compare(ctx.dig(:total), ">=", 500))) ? Routes::IsVip::Yes : Routes::IsVip::No
  end

  def tier(ctx, **)
    case (ctx[:tier]).to_s
    when "gold" then Routes::Tier::Gold
    else Routes::Tier::Otherwise
    end
  end
```

有拓扑时，`validate` 追加分支规则，字段均为 `branches`，消息在 `flowchart_elements.decision.errors`：`too_few_branches`（少于两条）、`multiple_otherwise`、`duplicate_match_value`（去除首尾空白后），以及是／否模式下的 `invalid_condition_match`（只能是 `true`、`false` 或空）和 `missing_yes_branch`（需有「是」，并有「否」或「其他」）。`ConfigValidator` 会传入拓扑，因此编辑器的校验也会报告这些规则。

### 终点与子流程

`EndGenerator` 读取 `responseType`（`none` 或 `value`）。`none` 发出 `true`，但 `ActivityGenerator` 会跳过该终点（`stepless_end?`），把入边接到 `End(:success)`。`value` 用 `returnValue` 写入 `ctx[:response]`，是真正的步骤。

`SubflowGenerator` 只声明一个字段 `flowchartId`（`reference`，`source: :flowcharts`，必填）。`generate_body` 返回 nil。`ActivityGenerator` 发出 `step Subprocess(<ChildActivity>), id: :<name>`，以及页眉行 `# Subflows: <Class> (#<id> "<name>"), …`。两处引用同一子流程会得到不同的 id。`ActivityClassBuilder#load_subflow_activities` 对每个子流程源码只求值一次（`loaded_ids`）。

### 生成的页眉

`ActivityGenerator::HeaderBuilder` 发出与语言无关的英文注释：

```text
# frozen_string_literal: true
#
# Generated from flowchart #<id> "<name>". Do not edit; regenerate it from the flowchart editor.
# Bound entity: <label>
```

未保存时没有 `#<id>`（`# Generated from flowchart "…"`）。绑定实体的三种写法：`# Bound entity: <label>`、`# Bound entity: supplied at runtime (shared flowchart)`，或 `# No bound entity`。用户文本经 `ActivityGenerator.safe_comment_text` 消毒。没有 Trigger、Multi-source、Model class、Contract class 行。每个步骤方法前有 `# <元素标签>`。

### NameDeriver

`ActivityGenerator::NameDeriver` 保留 Railway 实例方法、Ruby 关键字和 `collect_errors`（`initialize` → `initialize_step`）。不含 ASCII 字母的标签变成 `<type>_<n>`。类名按 `/[^A-Za-z0-9]+/` 分词。同时提供 `flowchart:` 与 `subflow_lookup:` 时，结构校验的 `class_name_collision` 比较父流程类名与每个已解析子流程。

分支标识来自连接的 `matchValue`：`true` → `Yes`／`:yes`，`false` → `No`／`:no`，空 → `Otherwise`／`:otherwise`；其他匹配值按 ASCII 词驼峰化（`high` → `High`／`:high`，`value_3` → `Value3`／`:value_3`）；前导数字加 `Value` 前缀；没有 ASCII 字母或数字 → `Branch<n>`／`:branch_<n>`（从 1 计）；语义 `success` 与 `failure` 变成 `success_branch`／`failure_branch`；同一决策内重复则加数字后缀。决策模块名是步骤名的驼峰形式，在 `Routes` 内唯一。循环出口绑定 `Routes::<Loop>::Done`／`:done`。

### ConflictResolver

`CodeGenerators::ConflictResolver` 仅在同一引脚的另一写入者是数据流图中的祖先时才重命名（循环回边不计）。互斥分支上的写入者以及终点保持原键。重命名格式为 `<pin>_<sha1(element_id:pin)[0..3]>`（冲突时加长前缀）。编辑器的计算覆盖使用同一规则。不安全的作者 `renamed_to` 会被忽略，且不阻止自动重命名。

### EmissionRewriter

`CodeGenerators::EmissionRewriter.call_element` 按 B2 解析 `ctx[:pin]` 读取：

1. 显式输入覆盖（`override_key`）。
2. 墓碑（`""`）——读取保持 `ctx[:pin]`。
3. 候选写入者 = 读者自身若也写该引脚，再加上游写入者，按拓扑从近到远。一个候选 → 其生效键。多个候选 → 最新者支配读者且不是读者自身时用该键；否则 `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b, …)`。
4. `ctx.dig`／`fetch`／`key?(:pin)` 走同一决定：单个其他键只换符号；选择则只把 `ctx` 接收者换成 `FlowchartRuntime::Outputs.view(ctx, :pin, …)`。
5. 隐含的 `FlowchartRuntime::Entries.scope(ctx)` 读取由 `BodyAnalyzer` 标为 `implied: true`，不会被改写。

通过 `safe_target?` 的已存作者 `outputs.renamed_to` 会并入生效键映射。

### WiringPlanner

`ActivityGenerator::WiringPlanner` 是纯规划器。输入为深度优先顺序的步骤列表；输出是 `magnetic`／`outputs` 以及 `CANVAS` 的 `routes`／`ends` 映射。

- 步骤到其唯一后继的成功边，仅当后继是下一个已声明步骤且被它吸引时才可省略；否则显式写出 `Output(:success) => Id(:<next>)`，后继是无步骤终点时则为 `Output(:success) => End(:success)`。
- 前一个声明是决策，或前一个声明不会隐式流入本步骤时，本步骤带 `magnetic_to: nil`。
- 不是最后一个声明的终端步骤带 `Output(:success) => End(:success)`。
- 每个决策还带 `Output(:success) => Track(:failure)`。
- 从循环体进入循环页眉的边始终显式（`Output(:success) => Id(:<loop>)`）。页眉的 Done 信号是 `Output(Routes::<Loop>::Done, :done) => Id(:<exit>)`（或 `End(:success)`）。无循环体的页眉另加 `Output(:success) => Track(:failure)`。
- 作为元素 id 的后继只经元素 id 映射解析（字符串不会先被当成步骤 id）。

### 租户作用域的模型操作

记录类动作都调用 `FlowchartRuntime::Entries`（见 [流程图运行时](flowchart-runtime)），没有一个自建 `EntityEntry` 查询：

- `new_model`：`Entries.scope(ctx).new(customer_id: ctx[:customer_id])`，写入 `resultVar`（默认 `model`）。
- `save_model`：`Entries.save(ctx, ctx[:contract].model)`；没有字段，保存 `build_contract`／`validate_contract` 准备好的契约模型。
- `update_model`：有契约时 `ctx[:contract].sync`，否则 `Entries.assign(model, ctx[:params])`；随后 `Entries.save`。`changesVar` 可选，捕获 `saved_changes`。
- `upsert_model`：按 `matchFields` 调用 `Entries.upsert(ctx, match: { … }, attributes: ctx[:params])`，写入 `resultVar` 与 `createdVar`。
- `destroy_model`：`mode` 为 `delete`（`Entries.destroy`）或 `archive`（`Entries.archive`，写入 `archiveField`，可选写 `archivedByField`）。
- `clone_model`：在 `attempt("clone_model.failed")` 内调用 `FlowchartRuntime::Clone.copy`。
- `query_models`：`Entries.query`，支持 `conditions`、`select`、`returns`（`records`／`values`）、分页、`limit`、`orderBy`（经 `ConditionInput.safe_column?` 检查）、`distinct`。
- `count_records`：`Entries.tally`，`resultAs` 为 `count`、`exists` 或 `absent`。
- `aggregate_query`：`Entries.aggregate`；`having` 必须匹配 `QueryBuilder::SAFE_HAVING_RE`。
- `bulk_import`：`FlowchartRuntime::BulkImport.run`（`MAX_ROWS` 1000，`onDuplicateKey` 为 `update`／`skip`，`uniqueBy` 不得包含内部列）。
- `batch_operation`：`FlowchartRuntime::Batch.run`；来源不兼容时报 `batch_operation.incompatible_scope`。
- `find_model`、`set_record_fields`、`related_record`、`load_current_user`、`next_sequence_number` 见 [流程图步骤动作](flowchart-step-actions)。

### 表达式安全与调用

`expression` 字段必须是通过 `ExpressionSafety#safe_expression?` 的单条语句；`input` 字段必须是点分标识符路径。`ActivityGenerator` 在每次 `generate_body` 之前都会运行 `validate_config`，因此在编辑器外改过的值同样要过校验；`read` 发出前还会复查 `input`／`output` 标识符。元素类型使用同样的角色：结束的 `returnValue` 与判断的 `subject` 是 `expression` 字段，循环的 `collection` 是 `input` 路径，`collectInto` 是 `output` 键。

`FlowchartRuntime::Invocable` 只解析允许名单中的类名。它拒绝 ActiveRecord 模型类和 `FORBIDDEN_METHODS`（`delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection`）。`method!` 要求方法由应用定义，`source_location` 位于 `Rails.root.join("app")` 下，且所有者不是 Object／Kernel／BasicObject／Module／Class。仅当 `initialize` 由应用定义时，才允许 `Class#new`。`invoke_service` 与 `enqueue_job`（`Invocable.job!`）在运行时使用它。

### 预置默认值

`authorize` 从 `userExpression`（默认 `current_user`）读取用户。只检查 `Authentication::User`；其他值（包括 `load_current_user` 写入的普通 Hash）都回退到 `FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`。载入的用户 Hash 本身从不授予访问权限。`send_template_email` 用 `Customer.find_by(id: ctx[:customer_id])` 查找客户。

### 平台界面

`Admin::Maintenance::Platform::CodeGeneratorsController`：

- `index` / `show`：`IndexPresenter` 展示 `step_action_generators` 与 `element_type_generators`，可按 `category`、`kind`、`element_type` 过滤。
- `new` / `create`：`FormDataExtractor` 与 `SourceAssembler` 生成文件。`build_file_path` 拒绝空名称、`..` 和斜杠。元素类型写到 `element_types/<type>/<name>_generator.rb`。步骤动作写到 `element_types/process/<category>/<name>_generator.rb`。路径必须留在 `app/services/code_generators` 之内。
- `edit` / `update`：`FormDataExtractor#extract` 读取文件。若 `generate_body` 发生变化，`MetadataDSL.bump_patch` 改写 `version` 字符串，注册表再加载一次。
- `destroy`：删除文件并重新加载注册表。

`save_generator` 在 `File.write` 之前运行 `GeneratorValidator.validate_source`。同一资源上的嵌套路由：

- `CodeGenerators::ValidationsController#create`：对提交的 `source_code` 返回 `{ valid, errors }`。
- `CodeGenerators::PreviewsController#show`：用 `sample_input` 调用 `generate_step_method`。slug 含 `..` 则 400。
- `CodeGenerators::TestRunsController#create`：用 `sample_config` JSON 调用 `CodeGenerators::TestRunner.run`。
- `CodeGenerators::SourcePreviewsController#create`：组装源码但不写盘。
- `IoParamsController` 与 `ElementTypeIoParamsController`：POST 查看生成器的输入输出。流程图编辑器上有同样的只读 POST，它们不执行生成的代码。

资源的 slug 约束是 `%r{[^.]+}`。`set_generator_info` 在 slug 含 `..` 时返回 400；`PathIdentity.find` 或文件不存在时返回 404。

## 需要特别注意

:::attention
`CodeGenerators::GeneratorRegistry#discover!` 就是注册机制。文件加载后，类按 `registered_names` 进入索引。不要在 `BaseGenerator` 上寻找 `register!` 类方法。不在 `element_types/<受支持类型>/` 或 `element_types/process/<分类>/` 下的生成器不会进入哈希，`ActivityGenerator` 随后抛出 `:unknown_element_type` 或 `:unknown_step_action`。仍引用已退役动作的已存流程图不做转换，在编辑器中替换该步骤前无法生成。
:::

:::attention
`flowchart.name` 为空或 `elements` 为空时，`ActivityGenerator#generate` 在任何生成器运行之前返回 `nil`。`Flowchart#generate_activity` 把这个 nil 写入 `activity`（若本次保存是覆盖，则更早返回）。绑定到该流程图的页面稍后会在 `Pages::PublicSubmission` 里得到 Activity 未生成的结果。
:::

:::attention
`Admin::Maintenance::Platform::CodeGeneratorsController#save_generator` 把 Ruby 写到磁盘上的 `app/services/code_generators`，并重新加载自动加载器。`build_file_path` 拒绝 `..` 和绝对路径片段；`set_generator_info` 拒绝含 `..` 的 slug。这个界面不是数据库 CRUD，也不是支付、验证码或邮件的单文件厂商投放处。
:::

:::attention
`reference` 字段只检查是否填写。`ReferenceSources::<Source>.valid?` 存在，但生成时不调用，因此失效的模板 id 或页面 id 由步骤调用的运行时辅助方法在运行时发现，而不是在保存时。`entity_attribute` 字段只在生成器上下文带绑定实体时（生成 Activity 时）对照校验；编辑器的校验按钮和不带上下文的 `validate_config` 会跳过这一检查。
:::

:::attention
对 `conditions` 字段调用 `read`，会把存储的条件组输出为 Ruby 数据字面量（`Hash#inspect`），绝不输出为 Ruby 源码；由运行时查询层（`FlowchartRuntime::Entries.query`）解释。`ConfigSchema` 在生成前拒绝非 Hash 值（`invalid_conditions`）。Decision 与 Loop 元素在 `ConditionRules` 校验条件组之后，改用 `Shared::ConditionBuilder` 构建 Ruby 条件；规则会拒绝的内容（未知运算符、未知计数运算符、嵌套组），构建器一律抛错。
:::

:::attention
元素类型生成器读 `properties`，步骤动作读 `config`。把这两个键对调后，`extract_config` 看到的是空哈希。步骤动作只通过 `value`／`read` 读配置、只通过 `fail_with`／`attempt` 报失败；方法体若直接取 `config[...]` 或写入未声明的 ctx 键，目录测试会失败。
:::

## 关键代码

```ruby
# app/services/code_generators/generator_registry.rb
    SUPPORTED_ELEMENT_TYPES = %w[start end decision loop subflow].freeze

    def discover!
      ELEMENT_TYPES_PATH.children.select(&:directory?).each do |type_dir|
        next if type_dir.basename.to_s == "process"
        next unless SUPPORTED_ELEMENT_TYPES.include?(type_dir.basename.to_s)

        scan_directory(type_dir, @element_types)
      end

      if PROCESS_PATH.exist?
        PROCESS_PATH.children.select(&:directory?).each do |category_dir|
          scan_directory(category_dir, @step_actions)
        end
      end
    end
```

```ruby
# app/services/code_generators/base_generator.rb
    def fail_with(code, field: nil, **details)
      unless_expr = details.delete(:unless)
      args = [":#{code}"]
      args << "field: :#{field}" if field
      details.each { |key, source| args << "#{key}: #{source}" }
      line = "return FlowchartRuntime::Step.fail(ctx, #{args.join(', ')})"
      unless_expr ? "#{line} unless #{unless_expr}" : line
    end
```

```ruby
# app/services/code_generators/element_types/end/end_generator.rb
        config_schema ported: true do
          enum :responseType, %w[none value], default: "none", required: true
          expression :returnValue, placeholder: true, visible: { responseType: "value" }
          requires :returnValue, when: { responseType: "value" }
        end
```

```ruby
# app/services/code_generators/action_catalog.rb
      def digest_for(catalog)
        payload = {
          "categories" => catalog["categories"].map { |category| { "key" => category["key"] } },
          "actions" => catalog["actions"].map { |action| digest_action(action) }
        }
        Digest::SHA256.hexdigest(JSON.generate(payload))
      end
```

```ruby
# app/services/code_generators/body_lint.rb
    MAX_LINES = 12
    STANDARD_WRITES = %w[
      model contract errors error_details submission_outcome current_user
    ].freeze
```

```ruby
# app/services/activity_generator.rb
    generator_class = @registry.find_step_action(action)
    unless generator_class
      raise Error.new(
        code: :unknown_step_action,
        message: I18n.t("maint_core.flowcharts.structure_errors.unknown_step_action", action: action.inspect),
        element_id: element_id,
        action: action
      )
    end

    generator = generator_class.new(step, ctx)
    validate_generator!(generator, step.fetch("config", {}), element_id: element_id, action: action)
    generator.generate_body
```

```ruby
# app/controllers/admin/maintenance/platform/code_generators_controller.rb
    def save_generator(file_path, source)
      validation_errors = ::CodeGenerators::GeneratorValidator.validate_source(source)
      if validation_errors.any?
        @errors   = validation_errors
        @kind     = params[:kind]
        @category = params[:category]
        @form_data = ::CodeGenerators::FormDataExtractor.new(params).form_data_from_params
        action     = File.exist?(file_path) ? :edit : :new
        render action, status: :unprocessable_entity
        return
      end

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, source)
      Rails.autoloaders.main.reload
      ::CodeGenerators::GeneratorRegistry.instance.reload!

      yield
    end
```

```ruby
# app/services/activity_generator/wiring_planner.rb
    def decision_outputs(descriptor)
      branches_for(descriptor).map { |branch|
        ["Output(#{branch[:signal]}, :#{branch[:semantic]})", wire_target(branch[:target])]
      } + [["Output(:success)", "Track(:failure)"]]
    end
```

```ruby
# app/services/code_generators/emission_rewriter.rb
        ast[:reads].each do |r|
          next if r[:implied]

          replacement = bracket_read_replacement(r[:pin], input_map)
          edits << splice(r, replacement) if replacement
        end
```

相关页面：[流程图步骤动作](flowchart-step-actions)、[流程图构建器](flowchart-builder)、[流程图运行时](flowchart-runtime)、[国际化](internationalization)、[页面构建器](page-builder)、[实体构建器](entity-builder)。
