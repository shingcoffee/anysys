---
title: "流程图构建器"
summary: "流程图画布如何存储图、校验、版本化，并编译成 Trailblazer Activity——模板、每个过程框一个动作、仅决策／循环可分叉、元素与步骤属性表单（页签、连接上的决策分支、条件控件、就地报错）、画布编辑（放置、保存与冲突、撤销、只读子流程预览、快捷键）、测试面板、发布检查，以及 Activity 重新生成。"
---

## 概要

流程图是平台所有者的过程图。客户看不到编辑器、导航入口，也看不到「流程图」这个词。已发布的页面仍然运行编译后的 Activity。添加界面、助手提及或编辑器链接之前，先问 `FlowchartVisibility.allowed?`。HTTP 由 `RouteAuthorization` 执行：控制器路径匹配 `/flowchart/`，或 URL 位于 `/admin/maintenance/flowcharts` 下，都要求 `Authentication::User#platform_owner?`（客户 `81721200` 上的 `owner?`）。租户 `admin`，包括 `81721200` 上不是所有者的管理员，会在动作执行前被拒绝。

图是版本化属性 `configuration` 上的 JSON：`elements`、`connections`、`metadata`。`Flowchart#generate_activity` 在保存时运行，把 Ruby 写入父行的 `activity` 列。`ActivityGenerator` 遍历图，把每个节点交给 `CodeGenerators::GeneratorRegistry` 来编译这段 Ruby。没有图解释器。编译后的类如何执行，见 [流程图运行时](flowchart-runtime)。

共享流程图（`customer_id` 为 NULL）只在 `/81721200/admin/maintenance/platform/flowcharts` 上创建。租户路径上的保存，包括客户 `81721200`，只写该客户对 `configuration` 的覆盖，不改写全局 `activity` 列。

## 流程

```text
flowchart-form（新建）        flowchart-canvas（编辑）
        |                              |
        | 模板 / 实体绑定              | PATCH configuration JSON
        |                              |   + expected_head_version_id
        v                              v
Admin::Maintenance::FlowchartsController
        |  头版本已变 -> 409 Conflict（不保存）
        |  SharedResourceMode
        |  租户覆盖只允许 :configuration
        v
Flowchart#save
        |  before_save generate_activity
        |    （override_customer_id 存在时跳过）
        v
ActivityGenerator#generate
        |  名称为空或 elements 为空则返回 nil
        |  否则 DFS + GeneratorRegistry
        v
flowchart.activity   （父行上的 Ruby 源码）

configuration 正文
        |
        v
FlowchartConfigurationContent.store!
        |
        v
FlowchartVersion --> current_version_id
                 或 flowchart_customer_heads

校验按钮
        |
        v
POST .../flowcharts/:id/validation
        |
        v
FlowchartServerValidator  （内存副本，不保存）

发布
        |
        v
FlowchartInputOutputValidator
        |
        v
FlowchartServerValidator  （有错误即阻止）
        |
        v
status = launched
```

画布（`flowchart_canvas_controller.js`）不在 JavaScript 里拼租户路径。`_editor.html.erb` 把路由助手生成的地址放进 `data-flowchart-canvas-urls-value`（`update`、`versions`、`validation`、`traces`、`document`、`list`、`implicitKeys`、带 `__ACTION__` 的 `stepIoParams`、带 `__TYPE__` 的 `elementIoParams`、带 `__SOURCE__` 的 `referenceOptions`）。`flowchart/urls.js` 读取这张表（`flowchartUrl`／`flowchartShowUrl`）。平台前缀上，`PlatformPathHelper` 改写这些助手，因此保存共享流程图会更新全局行。引用选项模板是集合路径加上 `/reference_options/__SOURCE__.json`，避免把 `__SOURCE__` 代币送进 `:source` 路由约束。

校验把尚未保存的 `elements` 与 `connections` POST 到 `urls.validation`。测试面板把 `{input, configuration}` POST 到 `urls.traces`：服务端编译提交的内存图（对 `dup` 跑 `ActivityGenerator`，`status: :draft`），追踪它，不保存版本。`FlowchartTracesController#create` 随后把与 `Pages::PublicSubmission#build_context` 相同的运行时键合并到已提交的 input 之后（`bound_entity` 为被追踪流程图的实体，共享且无实体时为 nil；另有 `customer_id`、`authentication`、`current_user_id`、`current_user_role`、`audience`、`device_type`、`request_ip`、`user_agent`、`locale`、`request_id`；`ActivityTracer` 再加 `flowchart_id`），JSON 正文无法覆盖这些键。每次追踪都在 `ActiveRecord::Base.transaction(requires_new: true)` 内运行，并始终抛出 `ActiveRecord::Rollback`，因此测试运行不会持久化数据库更改。邮件、Webhook、缓存写入等外部副作用不会被抑制。过大、畸形或超时的配置返回 422（上限来自 `FlowchartServerValidator::MAX_ELEMENTS`／`MAX_CONNECTIONS`／`DRY_RUN_TIMEOUT_SECONDS`）。恢复 POST `urls.versions`，再用 `data.configuration` 重载画布。文档请求 GET `urls.document`，由 `FlowchartDocumenter` 生成。

## 实现

### 存储

`Flowchart` 通过 `Versionable` 使用 `FlowchartVersion`、`FlowchartConfigurationContent`、快照 `:configuration` 和 `flowchart_customer_heads`。`reload_definition_from_head!` 把 `resolved_current_version.content.payload` 赋给 `configuration`。

`Flowchart::ConfigurationAccessors` 读取 `elements`、`connections`、`metadata` 和 `canvas_size`（默认宽 1200、高 800）。JSON 必须包含 `elements`、`connections`、`metadata`；前两者必须是数组，metadata 必须是对象。`status` 为 `draft`、`launched` 或 `deleted`（软删除）。模型／手动创建默认 `draft`；助手新建的流程图通过校验后自动上线。`crud_type` 是可选字符串，取值 `Flowchart::CRUD_TYPES`（`create`、`read`、`update`、`delete`），不用枚举，以免和 Active Record 的方法重名。

客户自有流程图必须有 `entity_id`。共享流程图不能有。`FlowchartsController#create` 在新行是共享资源时清空 `entity_id`。`Flowchart::TemplateBuilder.new_with_defaults` 在提供 `template` 时优先于已提交的 `configuration`（新建表单不再隐藏提交图）。`blank` 是起点 → 终点。`crud_create` 是起点 → 新建模型 → 构建契约 → 校验 → 保存模型 → 终点。`crud_update` 是起点 → 查找模型 → 构建契约 → 校验 → 保存模型 → 终点。`crud_delete` 是起点 → 查找模型 → 销毁模型 → 终点。每个过程框只有一个动作。`Flowchart::TemplateBuilder::STEP_CONFIGS` 写入 `new_model { resultVar: "model" }`、`build_contract { contractClass: "EntityEntryContract", modelVariable: "model" }`、`validate_contract {}`，另有三份配置仍带当前生成器未声明的键：`find_model { findStrategy, idExpression, resultVar }`、`save_model { contractRef }`、`destroy_model { strategy, modelVariable }`。生成时忽略未声明的键并使用声明的默认值（`findBy: "id"`、`idSource: "params.id"`、`mode: "delete"`），因此模板行为符合预期。标签来自两种语言的 `flowchart_elements.template_labels`。

`launched_edit_locked?` 在行已发布、且当前请求不是在写覆盖线时为真。此时 `must_be_draft_to_edit` 阻止更新，除非设置了 `assistant_version_write`，或本次改的就是 `status`。全局行已发布时，覆盖写入仍然允许。`FlowchartCrudTypesController#update` 使用 `update_column`，重新分类不会触发该守卫。共享行的 `crud_type` 仍走 `guard_shared_global_writes`。

### 编译

`ActivityGenerator#generate` 在 `flowchart.name` 为空或 `elements` 为空时返回 `nil`。`StructureValidator` 报出的问题若不是循环拓扑错误、也不是不支持的结构类型，同样返回 `nil`；那两类会抛出 `ActivityGenerator::Error`。未知元素类型和未知步骤动作也抛出该错误（`:unknown_element_type`、`:unknown_step_action`）。

元素类型 `process`、`start`、`end` 是步骤容器（`STEP_CONTAINER_ELEMENT_TYPES`）。它们的 Ruby 来自嵌套的 `properties.steps`，每一步用 `GeneratorRegistry#find_step_action` 查找。其他类型用 `find_element_type`。见 [代码生成器](code-generators)。

`Flowchart#generate_activity` 把 `#generate` 的结果赋给 `self.activity`。`override_customer_id` 存在时立刻返回，租户分叉不会覆盖全局 Activity。`ActivityGenerator::Error` 在测试环境重新抛出，其他环境只记日志，保留原先的 `activity`。其他异常在测试环境重新抛出；测试之外，`activity` 列变成一行失败注释。`diagram` 是另一条路：`ActivityDiagramGenerator` 根据 Activity 源码画图，它不是存储中的图。

`FlowchartDefinitions::Persist` 与 `GraphValidator` 是助手应用路径（名称、CRUD 类型、ActionCatalog 动作、图形状）。画布保存走控制器的 update。助手调色板、步骤动作枚举和 `UiConfigSchema` 默认值均来自 `CodeGenerators::ActionCatalog.export`（`FlowchartDefinitions::Assistant::SchemaGenerator`）。`bin/rails ai_assistant:flowchart_schema` 写入 `structure_schema.palette.json`；快照与现场生成不一致时规格失败。提示词示例使用 `validate_contract`（空配置）、`build_contract`（`contractClass`／`modelVariable`，写入 `ctx[:contract]`）和 `save_model`（保存 `ctx[:contract].model`）。

### 每个过程框一个动作

`ActivityGenerator::StructureValidator` 拒绝 `properties.steps` 超过一个动作的过程框（`maint_core.flowcharts.structure_errors.process_multiple_actions`）。`structure_schema.json` 写明 `steps.maxItems: 1`，并把 ActionCatalog 规范键注入 `step.action.enum`。`FlowchartDefinitions::ProcessSplitter` 把多步过程拆成单动作过程链（第一个保留原 id 与入边；其余为 `{id}_2`、`{id}_3`……；最后一个接管出边；`y` 更大的下游元素下移）。`Normalizer` 调用拆分器，使助手输出符合规则；每个步骤的动作取 `Palette.canonical_key(action) || action`（目录键映射到自身，不存在别名），并把 `UiConfigSchema.defaults_for(action)` 合并到步骤配置之下。已存流程图没有转换任务：一个过程框含多个动作或带退役步骤键的已存图，在编辑器中修正前无法通过校验和生成。

`ActivityGenerator::NameDeriver` 保留 Railway 实例上的全部方法名（以及 Ruby 关键字和 `collect_errors`）。保留名变成 `"#{name}_step"`。不含 ASCII 字母的标签变成 `<type>_<n>`（`process_1`、`end_1`）。类名按任意非字母数字字符分词（`entity-entry` → `EntityEntryActivity`）。回退是 `Flowchart#{id}Activity` 或 `UnsavedFlowchartActivity`（不用随机字符）。同时传入 `flowchart:` 与 `subflow_lookup:` 时，结构校验拒绝父流程类名与已解析子流程相同、以及两个不同子流程推导出同一类名的情况（`class_name_collision`）；同一子流程被引用两次是允许的。命名与分支常量见 [代码生成器](code-generators)。

### 出边

`ActivityGenerator::StructureValidator::MULTI_OUTGOING_EXEMPT_TYPES` 为 `decision` 与 `loop`。其他元素若有多于一条出边，会被拒绝（`maint_core.flowcharts.structure_errors.multiple_outgoing`，带元素名称）。注册表支持的元素类型是 `start`、`end`、`decision`、`loop`、`subflow`。已存储的其他结构类型按 `unsupported_type` 失败，不会生成。延迟工作使用后台任务步骤动作。

### 测试面板

测试面板把 `{input, configuration}` POST 到 `urls.traces`。`FlowchartTracesController#create` 编译 `dup`，在已提交的 input 之后写入 PublicSubmission 运行时键，追踪运行，并始终回滚。JSON 含 `errors`（`ctx[:errors]`，字符串、非空、去重）。失败横幅列出这些消息；`error` 是翻译后的通用消息，不含异常文本。每条决策行显示所走分支（`node.branch`）。覆盖层只按 `element_id` 匹配画布框；没有 `element_id` 的节点（`End.failure`）不高亮任何框。顺序徽章按首次执行顺序为不同元素编号（1、2、3……）；元素颜色取最后一次状态。循环中重复访问复用第一次的编号。`trace_truncated` 为真（超过 500 个节点）时，步骤列表顶部显示截断提示（`maint_core.flowcharts.editor.test_trace_truncated_format`）。画布上任何编辑（`canvas.onchange`）都会清除覆盖层，它不会描述已经改过的图。运行时间用 `Intl.DateTimeFormat` 按应用语言（`data-flowchart-canvas-app-locale-value`）格式化，查询耗时用 `testQueryDurationFormat`（`{duration} ms`）。公开提交不绘制此覆盖层。

### 步骤表单

过程框只放一个步骤动作，在属性面板的动作选择器中选择。选择器列出 `CodeGenerators::ActionCatalog.export` 的目录（嵌在 `data-flowchart-canvas-action-catalog-value` 中），按目录顺序分组——记录、校验、数据、通信、安全、后台、文件、缓存、并发、韧性、调度、支付、提交结果、服务、工具——并在两种语言下检索标签、说明与分类（`step_picker_search_placeholder`、`step_picker_no_match_label`）。列表中已使用的 `singleUse` 动作被禁用，并标注 `step_picker_already_used_label`。每个动作的字段、角色与默认值见 [流程图步骤动作](flowchart-step-actions)。

表单为每个目录字段渲染一个控件（见下文“生成器／UI 模式检查”）。`visibleWhen` 在规则与当前配置匹配前隐藏字段，服务端对隐藏字段既不校验也不读取。校验按步骤报告配置问题，消息为 `maint_core.flowcharts.config_problems.step_invalid` 加该字段的消息；步骤名取框的标签（没有则取动作的译名），动作也显示译名，不显示动作键。

条件执行是在过程框前放一个决策：步骤本身没有条件、重试或超时设置。步骤的 `conditions` 字段（如 `query_models` 的过滤条件）与决策、循环共用同一个条件控件（见下文“条件控件”）。

HTTP 类动作（`api_call`、`send_webhook`、`download_file`、`ai_inference`、`currency_convert`、`geolocation_lookup`）显示其能力声明的共用高级字段：

- **传输错误时重试**（`retryOnTransportError`、`retryAttempts` 1–2）仅在当前配置幂等时可用——`httpMethod` 为 GET、HEAD、PUT、DELETE 或 OPTIONS，或已填写 `idempotencyKey`；`download_file` 始终幂等。否则开关被禁用并取消勾选，显示提示 `step_retry_not_idempotent_hint`。服务端执行同一规则（`retry_not_idempotent`）。
- **超时**（`connectTimeout` 1–5 秒、`readTimeout` 1–9 秒，合计不超过 10）显示提示 `step_timeout_gives_up_format`，即“N 秒后放弃”，其中 N 为 `min(10, (connectTimeout + readTimeout) × (1 + retryAttempts))`，重试次数只在开启重试时计入。
- **熔断器**（`circuitBreaker`、`breakerName`、`failureThreshold`、`resetTimeoutSeconds`）。

`send_sms` 取代了旧通知动作的短信通道：`templateKey` 是可搜索的平台短信模板引用，`to` 默认 `model.phone`，`vars` 是键值映射（字面量键、表达式值），`idempotencyKey` 可选，消息 id 写入 `resultVar`（默认 `sms_message_id`）。凭证与通道模板码仍在平台短信界面配置。运行时行为与错误代码见 [流程图运行时](flowchart-runtime)；投递见 [短信](sms)。

### 元素属性表单

每个元素（开始、结束、流程、判断、循环、子流程）和每条连接都在属性侧栏（`w-full sm:w-[420px]`）中编辑。表单由 `CodeGenerators::ElementCatalog.export(locale: I18n.locale)` 生成，`_editor.html.erb` 把它嵌在画布根节点上，即 `data-flowchart-canvas-element-catalog-value`，只嵌一次。`flowchart_canvas_controller.js` 用 `setElementCatalog`（`flowchart/constants/element_registry`）安装；页签、字段控件、标题类型名、自动标签、客户端规则与画布默认值都读这份注册表。JavaScript 中没有元素模式的副本。目录结构与 Ruby 声明见 [代码生成器](code-generators)。

**页签。** 每种类型的页签由目录给出：常规，然后是步骤（流程）或分支（判断），然后是输入/输出，类型声明了 `group: :advanced` 字段时才有高级。若当前设置下这些字段都不可见，编辑器也会隐藏高级。流程打开时定位在步骤，判断定位在分支，其余定位在常规。

| 类型 | 页签 | 常规 | 高级 |
|------|------|------|------|
| 开始 | 常规、输入/输出 | 名称、备注 | — |
| 结束 | 常规、输入/输出 | 名称、响应类型、返回值、备注 | — |
| 流程 | 常规、步骤、输入/输出 | 名称、备注 | — |
| 判断 | 常规、分支、输入/输出 | 名称、路由方式、取值表达式或条件、备注 | — |
| 循环 | 常规、输入/输出、高级 | 名称、循环类型、先执行一次再检查、条件或集合＋项名称、最大循环次数、备注 | 提前停止条件、跳过该项的条件、下标名称、将处理过的项收集到 |
| 子流程 | 常规、输入/输出 | 名称、流程图、备注 | — |

名称与备注属于目录的 `chrome`，不是配置字段。备注存于 `description`，渲染为常规页末尾折叠的 `<details>`，有内容时默认展开。元素表单为单列；条件行与分支行占满整行宽度。元素字段与步骤字段走同一套角色控件（`controls/field_renderer.js`）：每项输入下方显示帮助，可选枚举带空的「无」，另有引用选择器与条件控件。

**各元素。**

- **开始**：只有名称与备注，没有触发设置。
- **结束**：响应类型为 `none`（「不返回」，默认）或 `value`（「返回一个值」）。返回值仅在 `value` 时显示且必填（表达式，占位 `ctx.result`），终点随后写入 `ctx[:response]`。`none` 终点不是步骤。
- **流程**：没有元素字段；唯一的动作在步骤页选择（见“步骤表单”）。
- **判断**：路由方式为 `condition`（「是／否」，默认）或 `value`（「取值」）。取值模式显示取值表达式，与各分支的匹配值比较；是／否模式显示条件，即一个条件组。分支在分支页编辑（见下文）。
- **循环**：循环类型为 `while`（「当条件为真时重复」，默认）或 `for_each`（「逐项遍历」）。while 显示先执行一次再检查（`runOnceFirst`）与条件（必填）。for_each 显示集合（必填，不带 `ctx.` 的上下文路径，如 `items`、`params.modes`）与项名称（`itemVariable`，默认 `item`）。最大循环次数（`maxIterations`）对两种类型均为 1–10,000，默认 100。高级页有提前停止条件（`stopWhen`，两种类型均有），以及仅 for_each 才有的跳过该项的条件（`skipWhen`）、下标名称（`indexVariable`，默认 `index`）、将处理过的项收集到（`collectInto`）。运行时行为见 [流程图运行时](flowchart-runtime)。
- **子流程**：流程图（`flowchartId`）是 `flowcharts` 来源上的可搜索引用选择器，列出 URL 客户可用的已上线流程图（本客户的加共享的）。存储数字 id，显示名称。编辑器的引用选项 URL 带有 `exclude_id`（值为正在编辑的流程图），因此流程图不会列出自身；已存储的自引用仍由 `subflow_self_reference` 规则标出。
- **连接**：名称（连接的 `label`）与备注（`properties.description`），来自目录的 `connection.fields`。没有优先级设置。

**往返。** 清空的数字字段保持为空，占位符显示默认值（`default_placeholder_format`，「默认：100」）；不存储任何值，由生成器默认值生效。表单打开期间，当前模式隐藏的字段值会保留，切回原模式即可恢复。保存只写入可见的目录字段，加上 `description`、`io_overrides`、`steps` 与 `condition`（可见时）（`flowchart/element_config.js` 的 `persistableProperties`）。除流程外，服务端把其他键一律报为 `unknown_field`（「… is not a recognized setting」）。

**自动标签。** 只有标签为空、等于翻译后的 `defaultLabel`、或等于按上一次设置推导出的标签时，标签才随设置变化。标题显示目录中翻译后的类型名。

### 决策分支

判断的分支就是它的出边，元素本身不存任何分支数据。每条连接带 `label`（分支名）、`matchValue` 与 `fromPort`（`port_N`）。分支页按端口顺序为每条出边列一行：

- **名称**：连接标签。新分支使用翻译后的 `Branch {index}` 标签（「分支 {index}」）。
- **匹配值**：取值模式下为自由文本；是／否模式下为是／否选择（`true`／`false`）。
- **其他**：勾选框，存空 `matchValue` 并隐藏匹配值控件。在一行勾选会清除其他行的勾选。

添加分支会新建一个流程框和一条指向它的连接，不带匹配值。删除只去掉该连接：框留在画布上（若因此不可达，由校验报告），因此无需确认。画出或删除判断的任意出边，都会把剩余端口重新编号为 `port_0`…`port_N`。切换路由方式会清除「其他」之外的所有匹配值，并显示带撤销的提示，撤销即可恢复。

同一套规则既在浏览器中运行（`flowchart/validation/element_rules.js`），也在 `DecisionGenerator` 中运行，字段均为 `branches`，消息在 `flowchart_elements.decision.errors.*`：

| 代码 | 规则 |
|------|------|
| `too_few_branches` | 至少两条出边 |
| `duplicate_match_value` | 去除首尾空白后匹配值不重复 |
| `multiple_otherwise` | 最多一个「其他」（空匹配值） |
| `invalid_condition_match` | 是／否模式：匹配值只能是 `true`、`false` 或空 |
| `missing_yes_branch` | 是／否模式：需有「是」分支，并有「否」或「其他」 |

取值模式下，生成器发出 `case subject.to_s`，每个匹配值一条 `when`，`else` 指向「其他」分支（没有则为最后一个分支）；是／否模式下发出三元式，返回「是」信号或「否」（没有则「其他」）信号。

### 条件控件

判断的 `condition`、循环的 `condition`／`stopWhen`／`skipWhen`，以及每个步骤的 `conditions` 字段共用一个控件（`controls/conditions.js` 加嵌套的 Stimulus 控制器 `property-editor--controls--conditions`）。它编辑一个平铺的条件组：

```json
{
  "type": "group",
  "joins": ["OR"],
  "conditions": [
    { "kind": "field", "leftOperand": "ctx.vip", "operator": "is_true", "rightOperand": "" },
    { "kind": "query_count", "queryConfig": { "entityId": 7, "conditions": { "operator": "AND", "rules": [{ "field": "status", "op": "==", "value": "open" }] } }, "countOperator": ">=", "countValue": 1 }
  ]
}
```

- **字段行**：左操作数、运算符、右操作数。左操作数可填任意上下文路径，并提示上游输出与绑定实体字段。右操作数是字面量，除非以 `ctx.` 开头。一元运算符（`is_true`、`is_false`、`is_empty`、`is_not_empty`、`is_nil`）隐藏右操作数。每行都必须选运算符，没有空选项。
- **计数行**：实体（来自 `entities` 引用来源）、可选的 WHERE 过滤、限于 `== != > >= < <=` 的计数比较，以及计数值。
- **连接词**：每个间隔有一个 AND／OR 选择，写入 `joins`（每个间隔一项）。无法构建嵌套组，服务端也会拒绝。

运算符及其译名来自目录（`operators`，每项 `{ value, label, unary, count }`）。服务端由 `CodeGenerators::ConditionRules` 检查各行，按条件组所在字段报告 `flowchart_elements.conditions.errors.*` 代码（`empty_condition`、`nested_group`、`missing_left`、`missing_operator`、`unknown_operator`、`missing_right`、`invalid_regex`、`missing_entity`、`unknown_count_operator` 等）。

### 就地报错

客户端规则（`element_rules.js`）与服务端 `element_config_invalid` 问题都带 `field`。`applyElementFieldProblems` 在对应的 `[data-element-field]` 包装下绘制 `data-field-error` 消息，并为其输入设置 `aria-invalid="true"`；编辑该字段即清除错误。打开编辑器时只就地绘制当前问题，不离开打开时的页签（条件为空的判断仍定位在分支页，错误显示在常规页的条件下）。保存被阻止时，才切到字段所在页签，并展开所在的 `<details>` 或步骤折叠区。当前元素存在严重级别为 `error` 的字段问题时，保存被阻止；警告（如空流程框）从不阻止。规则消息针对字段且已翻译：画布挂载点以 `data-flowchart-canvas-validation-*-value` 属性传入（取自 `flowchart_elements.*.errors` 及共用的 `required` 消息）。编辑器在字段下直接显示原文；问题面板则用 `maint_core.flowcharts.config_problems.element_invalid`（“{label}（{type}）：{message}”，与服务端同一格式）在前面标明元素。问题面板中带 `field` 的行会定位到同一包装，并切到其页签、展开折叠区；分支问题会打开“分支”页签。客户端规则如下：

- 结束为 `value` 却没有返回值（`end_no_return_value`，字段 `returnValue`）。
- 流程框没有步骤（`empty_process`，警告）。
- 判断：上表中的分支代码；`routeBy: "condition"` 时条件组必填（`condition_invalid`，`condition`）。
- 循环：while 循环没有条件行（`empty_loop_condition`，`condition`）；for_each 循环没有集合（`loop_no_collection`）或集合以 `ctx.`／`ctx[` 开头（`loop_invalid_collection`），均在 `collection`；`itemVariable`／`indexVariable` 使用循环头保留名（`loop_reserved_variable`）或两者同名（`loop_colliding_variables`）。
- 条件组（判断 `condition`，循环 `condition`／`stopWhen`／`skipWhen`）与 `CodeGenerators::ConditionRules` 一致，在所属字段上报告 `condition_invalid`：先要求扁平条件组，再按行报告首个问题，依次为 `invalid_row`、`nested_group`、`missing_entity`、`unknown_count_operator`、`missing_left`、`missing_operator`、`unknown_operator`、`missing_right`。消息取自 `flowchart_elements.conditions.errors`，带 `{index}`／`{operator}`；已知、一元及计数运算符取自目录。正则语法以 Ruby 为准，`invalid_regex` 仅由服务端报告。
- 子流程没有目标（`subflow_no_target`），或指向正在编辑的流程图（`subflow_self_reference`），字段均为 `flowchartId`。

服务端消息使用 `maint_core.flowcharts.config_problems.element_invalid`，带元素标签、翻译后的类型名和生成器翻译后的消息。

### 生成器／UI 模式检查

步骤动作与元素类型的模式都写在生成器上（`config_schema ported: true`）。步骤动作由 `CodeGenerators::ActionCatalog` 导出（字段参考见 [流程图步骤动作](flowchart-step-actions)）；元素类型、连接与条件运算符由 `CodeGenerators::ElementCatalog` 导出（见 [代码生成器](code-generators)）。没有 JavaScript 模式副本，也没有镜像任务。步骤表单与元素表单按目录 `control` 种类渲染：`toggle`（开关）、`list`（增删行；`entity_attribute` 项角色用绑定实体列选择）、`mapping`（按 key/value 角色的键值行）、`conditions`（结构化 `{type:"group",joins,conditions}` 行）、`attribute_picker`（绑定实体列）、`reference_picker`（可搜索组合框，每个 source 只请求一次 `urls.referenceOptions`）、`localized_text`（`en` 必填，`zh-CN` 可选）。每项输入下方显示帮助。可选枚举带空的「无」；必填枚举显示默认值，绝不默默选第一项。`variablePicker: false` 的字段不出现插入变量按钮。映射与条件行在移动端单列，自 `sm:` 起成对排列。

```sh
bundle exec rspec spec/services/code_generators/element_catalog_spec.rb spec/services/code_generators/element_i18n_keys_spec.rb spec/config/flowchart_elements_locale_spec.rb
bundle exec rspec spec/scripts/audit_generator_ui_spec.rb spec/services/code_generators/contract_parity_spec.rb spec/services/code_generators/generator_inventory_spec.rb spec/services/code_generators/generator_conformance_spec.rb spec/services/code_generators/element_types/process/communication/semantic_conformance_spec.rb spec/services/flowchart_runtime/facade_contract_spec.rb
```

`GeneratorUiAudit` 按 `json_or_expression` 编辑器实际序列化结果比较默认值。未设置 UI 默认值的可选字段留空时被省略，后端声明的默认值随之生效，审计不会要求编辑器预填 `{}`。对象默认值与对象 JSON 文本按相同类型化值比较。显式冲突的默认值、畸形 JSON、序列化后仍为字符串的数组、普通文本字段以及必填空白字段仍报告偏差。静态模式提取保留 `{}` 的哈希类型，不将其视为字符串。一致性探针使用满足依赖条件的配置验证类型化对象和上下文表达式，不跳过新字段类型，也不把缺少短信模板误算为有效的字段变化。

短信公共运行时封装将错误边界交给 `Sms::Errors::Error`，保留 Gateway 异常及其已记录的受理信息，不定义 SDK 专属错误包装或别名。语义一致性测试对共享台账执行真实的 Gateway 接收、重放、模块／凭证失败、冲突与抑制。审计测试使用临时输出文件，验证时不覆盖受版本控制的报告产物。

### 校验与发布

编辑器的本地检查在 `ValidationMixin` 和 `flowchart/validation_service.js`（起点与终点、可达性、不支持的结构类型），各元素的规则在 `flowchart/validation/element_rules.js`（见“就地报错”）。服务端检查是 `Admin::Maintenance::Flowcharts::ValidationsController#create`：把提交的哈希交给 `FlowchartServerValidator`，作用在内存副本上（`assign_attributes` 再加 `configuration_json=`）。校验器不保存。子流程展开期间，本地与服务端检查都针对已存的折叠图运行（见“子流程预览”）。面板如何合并两路结果，见“校验面板”。

`FlowchartServerValidator` 把载荷限制在 1,000 个元素和 5,000 条连接以内，然后在 10 秒超时内做子流程存在性检查（缺失的 id 与其他租户的 id 使用同一句提示）和配置检查。只有这两项没有报出严重级别为 `error` 的问题时，才运行 `ActivityGenerator` 试运行：试运行只在图本身有效时才有意义，跳过它也避免同一个问题再以 `codegen_failed` 报一遍。超出上限时只返回一条 `server_check_unavailable` 警告（`maint_core.flowcharts.server_validation.payload_too_large`）；超时只返回一条 `codegen_check_timeout` 警告（`check_timeout`，带 `%{seconds}`）。这些提示以及它们包装的结构校验文案走 `maint_core.flowcharts.structure_errors` 与 `maint_core.flowcharts.server_validation` 的 `I18n.t`，因此面板跟随请求语言。不可访问的子流程，对缺失 id 和其他租户的 id 仍使用同一句提示。

发布是 `FlowchartLaunchesController#create`。已发布则拒绝，然后运行 `FlowchartInputOutputValidator`（引脚来自 `CodeGenerators::IoExtractor`；提示 `maint_core.flash.flowchart_launches.launch_failed`），再对重新加载的已存配置副本运行 `FlowchartServerValidator`（校验器会把配置写到传入的记录上，因此从不把要发布的记录交给它）。只要有严重级别为 `error` 的问题，发布即被阻止，提示 `maint_core.flash.flowchart_launches.problems_found`（「请先在编辑器中修复 %{count} 个问题，再上线。」，按单复数取文案）。被阻止时重定向回编辑器并带 `show_validation=true`，由此设置 `data-flowchart-canvas-auto-validate-value`，编辑器加载后自动运行校验并列出问题。全部通过后才 `update!(status: :launched)`。`destroy` 把 `status` 设回 `draft`。两个动作都使用 `guard_shared_global_writes`，因此共享流程图的上线与下线只能在平台前缀上操作。

表单依赖已发布的流程图。只要存在 `Page.bound_to_flowchart(id).launched`，无论流程图已发布还是草稿，`Flowchart#soft_delete` 都会拒绝，并列出这些表单（`maint_core.errors.validations.flowchart_in_use`）；`FlowchartsController#destroy` 以该提示重定向。`Page.bound_to_flowchart` 以文本比较 `form_settings.flowchart_id`，覆盖全局头版本及各租户的覆盖头版本；客户自有流程图只涉及共享页面和该租户自己的页面。流程图仍可下线，提示会追加 `maint_core.flash.flowchart_launches.forms_stopped`，说明在重新发布前无法接收提交的已上线表单数量。这些表单显示“无法提交”，流程图下线期间表单也无法上线；见 [页面构建器](page-builder)。

版本控制器是 `FlowchartVersionsController`（`index`、`show`、`create`、`edit`、`destroy`、`PUT default`）。画布版本面板请求 `urls.versions`。展示的是 `current_line_versions`。`MAX_VERSIONS` 为 50。`getConfiguration()` 不再写入新的 `created_at`，只回传已加载的 metadata。`Versionable#commit_version!` 在内容寻址哈希与头指针相同时报空操作，因此未改动的保存不产生版本。恢复前确认 `restore_version_confirm_format`：「恢复版本 {version}？将以其内容创建新的当前版本，原当前版本仍保留在版本历史中。」恢复不额外打快照：`restore_as_new!` 把所选内容写成新的头版本，原头版本仍在列表中。恢复（`POST …/versions`）返回已恢复的 `configuration`（`resolved_current_version.content.payload`）和 `version_id`（新的线头版本）。画布先退出子流程预览，把 `version_id` 记为期望头版本（见“保存与冲突”），调用 `loadConfiguration`（会重置缩放与平移），清除未保存状态，并重置撤销基线。只读画布不执行恢复。失败时，响应为 JSON 则弹出服务端 `message`，否则弹出 `restore_failed_http_format`（「恢复失败（HTTP {status}）」）；网络异常弹出 `network_error_format`。

助手创建走 `FlowchartDefinitions::Persist::Writer#create!`：将规范化图赋给尚未保存的客户自有候选记录，先运行 `FlowchartInputOutputValidator`，再将深复制配置交给独立内存记录上的 `FlowchartServerValidator`。会修改输入的校验器副本不保存。缺失输入及严重级别为 `error` 的服务端问题，成为已翻译的 `Persist::Result#errors`，供处理器既有有限修复循环使用（最多两次）。警告不阻止上线。全部通过后，写入器才设置 `status: :launched`，保存候选、编译后的 Activity 及首个版本；无效创建不留下记录／版本。保存返回 false 时，即使回调未提供原因，也会返回错误（`ai_assistant.assistant.apply_errors.flowchart_save_failed`）。更新保留已有状态，仍须确认；模型从不提供 `status`。该策略仅适用于助手新建的租户自有资源，不改变手动默认值，也不改变共享全局资源上线须走平台前缀的要求。参见 [AI 助手](ai-assistant)。

### 控制器与 Stimulus

`Admin::Maintenance::FlowchartsController` 同时挂在 `/:customer_id/admin/maintenance/flowcharts` 和 `.../platform/flowcharts`。普通更新允许 `name`、`description`、`configuration`；`tenant_override?` 只允许 `configuration`。嵌套路由包括复制、恢复、回收站、隐式键、步骤与元素的 I/O 参数、引用选项、追踪和文档。`GET …/flowcharts/reference_options/:source`（`FlowchartReferenceOptionsController#show`）仅返回 JSON，门禁与编辑器相同（仅 owner）；按 URL 客户从 `CodeGenerators::ReferenceSources` 列出 `{value, label}` 选项。

`flowchart_canvas_controller.js`（`app/views/admin/maintenance/flowcharts/_editor.html.erb` 上的 `flowchart-canvas`）掌管画布。它委托给 `SubflowManager`、`UndoRedoManager`、`ExportManager`、`SearchManager`、`MinimapManager`、`TestRunnerManager`，以及校验、版本历史、搜索、底部面板等 mixin。`readOnlyValue` 为真时 `save` 直接返回。已有保存在进行时忽略再次点击，避免两次 PATCH 生成两个版本。

### 编辑器画布

打开属性面板时快照 `{label, properties, elements, connections}`。取消、关闭按钮和 Escape 恢复该快照；图结构变化走 `canvas.replaceGraph`（不重置缩放／平移）。未改动就关闭时，不更新画布、不记撤销、不点未保存标记。`unsavedChangesCache` 已删除。

双击任意元素（含子流程）打开属性面板。有目标的子流程节点带展开／折叠开关（`[data-subflow-toggle]`），点击即就地展开为只读预览（见“子流程预览”）；只读（已发布）流程图不绘制该开关。应用内导航（`turbo:before-visit`）在有未保存更改时确认 `unsavedChangesConfirm`，拒绝则留在本页。

快捷键见“快捷键与选择”。粘贴在重映射 id 之前对每个剪贴板元素做 `structuredClone`。从决策新连出的边成为一个分支，带翻译后的 `Branch {index}` 标签，不带匹配值（因此在设定匹配值前它是「其他」分支）。新分支紧跟在拖出端口所属分支之后（`port_k` → 第 k+1 位；见 `flowchart/dynamic_ports.js` 的 `orderedDecisionBranches`），之前的分支保持原端口；随后决策的出边重新编号为 `port_0`…`port_N`。在边上插入元素时，上游边保留端口、标签、匹配值与属性，并重新同步决策分支。连入起点或从终点连出，在创建、重连和端点改接上都被拒绝（`connectionIntoStartRejected`／`connectionOutOfEndRejected`）。`destroy` 与 Escape 会解绑文档级拖拽监听。条件行左侧操作数初始为空；未配置的决策因无条件而校验失败。

`Flowcharts::ToolbarComponent` 确保编辑控件位于视口内：低于 Tailwind 的 `sm` 断点时，流程图名称独占一行，超长内容截断；缩放、操作及保存／撤销／重做控件组按需换行。保存按钮始终完整可见并右对齐，移动端隐藏装饰分隔线。从 `sm` 断点起，工具栏采用单行布局。浏览器在 320px 和 1440px 下检查保存按钮、所有可见工具栏控件，以及页头、编辑器、元素面板和画布区域，确保页面无横向溢出。

`flowchart_form_controller.js`（`flowchart-form`）按 `shared` 值显示或隐藏实体绑定，并选择模板卡片（默认 `blank`）。`flowchart_list_controller.js` 在索引页做客户端过滤。

校验控制器的注释写着 admin 路径按 admin 或 owner 放行。`RouteAuthorization#flowchart_namespace?` 仍会先要求 `platform_owner?`，因为控制器路径包含 `flowchart`。

### 放置与布局

连线保持笔直。`AlignmentMixin`（`flowchart/connection_manager/alignment.js`）把竖直连线（下→上或上→下）的终点框移到起点框的 X，把水平连线（右→左或左→右）的终点框移到起点框的 Y；下→左这类斜向组合不处理。它在 `loadConfiguration`（`alignAllElements`）、每次 `createConnection`（画线、自动连线、放下、插入）、端点改接以及拖拽结束时运行。从判断引出的新连线还会把目标框吸附到该判断其他分支框所在的行（`_alignNewBranchToRow`：取出现最多的 Y，并列时取最上方；只移动新框）。

各操作的放置方式：

- **面板放到空白画布**：框落在松手处，按 15 px 网格（`GRID_SIZE`）吸附，不连线。
- **面板放到已有框上**：新框放在目标框放下一侧一个间距（`DEFAULT_ELEMENT_SPACING`）处，与目标对齐并相连。目标该侧已有连线时，新框插入其中，远端框连同其子树（`shiftElementAndSubTree`）外移腾出位置。
- **双击面板项**：画布把框叠放在最后一个元素下方一个间距处，并从最后一个元素连线过来；最后一个元素是结束或已有出边时不连线。
- **拖拽**：单个元素带着其下游子树一起移动。松手在另一个框上时，放到该框旁并相连（该侧已有连线则插入其中，远端框及其子树按被拖组的范围外移）；松手在别处时，对齐到其入边。其子元素随之重新对齐。多选按同一个吸附后的位移整体移动，随后所有连线重新对齐。按 Escape 还原元素及其子树。

整理布局、对齐与分布按钮，以及分支页（添加分支会排布分支行，并带着各分支的下游链一起移动）仍是显式命令。面板放置指示按客户端坐标相对画布容器定位。

粘贴逐次错开：同一剪贴板第 n 次粘贴偏移 30 px × n（吸附到网格），复制会把 n 归零，因此复制副本（先复制再粘贴）总是偏移 30 px。`ZoomPanManager` 用 `ResizeObserver` 观察 SVG，容器尺寸变化（面板开合、窗口缩放）时重算 viewBox；`destroy()` 时断开。

**连线上的「+」。** 鼠标悬停在连线上时，其中点显示「+」按钮（`edge_insert_button`，「插入元素」；Enter 或空格也可打开）。点击后弹出菜单（`edge_insert_menu`），列出除开始、结束外的面板类型——流程、判断、循环、子流程，名称取 `elementLabel(type)`；方向键切换，Escape 关闭。选中类型后把该框放在 A 沿该边一侧一个间距处，B 连同其子树外移腾出位置，并经由边上插入的同一路径改接为 A→新框→B（原边的端口、标签、匹配值与属性留在第一段），然后选中新框并打开其属性编辑器。只记一条撤销。`canMutate()` 为假时不显示该按钮。

**整理布局**（`comp_misc.toolbar.tidy_layout`；`LayoutManager#autoLayout`）从开始节点自上而下分层。层级取从开始出发的最长路径，忽略循环回边，因此汇合点总在所有到达它的分支之下；子节点按源端口序号（即决策分支顺序）排列；父节点居中于首末分支之上。开始节点位置不变，开始不可达的元素排成一行放在下方，最后视图适配内容。只记一条撤销。

### 保存与冲突

`_editor.html.erb` 输出 `data-flowchart-canvas-head-version-id-value` = `@flowchart.current_line_head_version_id`（取线头版本，租户覆盖线同样适用）。画布每次保存都在 PATCH 中带上 `expected_head_version_id`，版本编辑模式下另带 `based_on_version_id`。参数存在且与 `current_line_head_version_id` 不同（说明其他标签页或用户在此期间保存过）时，`FlowchartsController#update` 不保存，返回 `409 Conflict`，正文为 `{ status: "conflict", message:, head_version_id: }`（`maint_core.flash.flowcharts.save_conflict`；HTML 请求带同一提示重定向回原页）。不带该参数的请求不做此检查。

成功响应新增 `version_id`，即新的线头版本。画布把它写入 `headVersionIdValue`，版本编辑模式下也写入 `basedOnVersionIdValue`，下次保存的版本谱系才正确，内容未变时仍走空操作。出于同样原因，控制器忽略等于头版本的 `based_on_version_id`。

收到 409 时，编辑器显示冲突横幅（`saveConflictBanner`，`role="alert"`），展示服务端消息和两个按钮：「重新加载」（`save_conflict_reload`）撤掉未保存提醒后刷新页面；「覆盖」（`save_conflict_overwrite`）把 `expected_head_version_id` 设为返回的 `head_version_id` 后重新保存。保存成功即隐藏横幅。

只有 `content-type` 含 `json` 时才解析错误正文；否则报 `save_failed_http_format`（「保存失败（HTTP {status}）」），代理或崩溃页面不会变成脚本错误。请求异常报 `network_error_format`。Ctrl/Cmd+S 在编辑页任何位置（包括属性字段）都会保存，并阻止浏览器的「保存网页」对话框；只读流程图则改为提示 `readOnlySaveToast`。子流程展开期间，保存写入的是已存的折叠图。

### 撤销与重做

`UndoRedoManager` 按画布顺序保存整图快照（50 条；最近 10 条存入 `sessionStorage`，刷新后仍在，按流程图与所编辑版本分键）。元素与连接的编辑都经过 `onBeforeChange`／`onchange`：`updateConnectionProperties`（侧栏的连接名称与备注、分支行）与 `updateElementProperties` 一样可撤销，并点亮未保存标记。

连续提交的合并键（`canvas.undoCoalesceKey`）相同时，替换栈顶快照而不新增；若编辑回到了「之前」的状态，则丢弃该条。属性编辑器在 `focusin` 时把键设为 `<元素或连接 id>:<字段>`，`focusout` 时清空，因此在一个获得焦点的字段里输入只算一条，一段文字不再挤掉整个历史。方向键微移使用 `nudge:<选中 id>`，空闲 500 ms 或按下其他键即结束这一轮。「添加结束元素」对新终点及其连线使用同一个键。

撤销与重做通过 `canvas.restoreGraph` 恢复：静默替换元素与连接，保留缩放、平移、已加载的 metadata、连线路由方式，以及仍存在的元素的选中状态；不重新对齐、不合并默认值，也不触发变更回调。撤销、重做与清空都会先退出子流程预览；只读画布上撤销与重做不起作用。恢复前会丢弃已打开的属性编辑器，防止它把过期元素写回画布。

### 子流程预览

展开的子流程是整个画布的只读预览。首次展开时，控制器保存折叠状态的配置（`_collapsedPreviewConfiguration`，即 `getConfiguration()` 的副本），并设置 `canvas.previewMode`。预览期间，保存、校验（客户端与服务端）和撤销快照都使用这份已存的图，绝不用展开后的图（`_previewAwareConfiguration`）。收起最后一个展开项时，经 `restoreGraph` 原样恢复该图，位置也不变。展开与收起不记撤销，也不标记为未保存。预览期间显示提示 `preview_subflow_notice`（「正在预览子流程，收起后可继续编辑」；目标 `previewNotice`，`role="status"`）。清空、撤销、重做与版本恢复都会先退出预览并恢复折叠状态的图；即使取消清空、无可撤销步骤或恢复失败，展开的图也不会残留在画布上。指向当前正在编辑的流程图的子流程不会展开（`subflowSelfReferenceToast`）。

所有编辑命令共用一道守卫：`canvas.canMutate()` 即 `!isReadOnly && !previewMode`。拖拽、缩放尺寸、连线、端点改接、删除、粘贴、复制副本、方向键微移、连线标签就地编辑、对齐／分布、整理布局、切换路由、面板放置与双击、连线上的「+」、自动修复（单行与「全部修复」）、撤销／重做、版本恢复，以及属性编辑器的保存与实时同步，都先检查它。为假时隐藏对齐工具栏、自动修复按钮和连线上的「+」。仍可使用的有：展开／收起开关与收起图标（只检查 `isReadOnly`，因此预览总能收起）、选择、复制、全选、缩放、平移、搜索、校验和保存。

### 快捷键与选择

快捷键监听在 `document` 上。除 Ctrl/Cmd+S 外，焦点在 input、textarea、select 或 contenteditable 元素中时一律忽略，且只在事件目标为 `document.body` 或位于画布容器内时生效。单字符键统一按小写比较，大写锁定不影响；Ctrl 与 Cmd 等效。

| 按键 | 作用 |
|------|------|
| Ctrl/Cmd+S | 保存（属性字段中同样有效；只读流程图弹出提示） |
| Ctrl/Cmd+Z | 撤销 |
| Ctrl/Cmd+Y、Ctrl/Cmd+Shift+Z | 重做 |
| Ctrl/Cmd+C | 复制选中元素及其之间的连线 |
| Ctrl/Cmd+V | 粘贴（逐次错开） |
| Ctrl/Cmd+D | 复制副本 |
| Ctrl/Cmd+A | 全选元素 |
| Ctrl/Cmd+F | 搜索 |
| Ctrl/Cmd+= 或 +、Ctrl/Cmd+-、Ctrl/Cmd+0 | 放大、缩小、适配内容 |
| Delete、Backspace | 删除选中的连线，否则删除选中的元素 |
| 方向键 | 按一个网格步长（15 px）微移选中项；按住 Shift 为 5 步 |
| 空格（按住） | 拖动平移 |
| Escape | 取消元素拖拽 |

粘贴、复制副本、删除、微移、撤销与重做需要 `canMutate()`；复制、全选、缩放、搜索与平移不需要。一轮微移只记一条撤销，空闲 500 ms、按下其他键或销毁时结束。

Shift+点击与 Ctrl/Cmd+点击一样，切换元素的选中状态；框选时按住 Shift、Ctrl 或 Cmd 则追加到当前选择。删除后隐藏尺寸手柄。从问题面板跳转时，经画布选择助手选中元素并清除已选连线，此时按 Delete 删除的是该元素而非残留的连线；连线问题则选中该连线（`selectConnection`），并让两端进入视野。

### 校验面板

每个问题只列一次。`validate()` 先丢弃客户端已覆盖的服务端问题——`elementId` 与 `field` 相同，或对不带字段的元素级问题，`elementId` 与 `type` 相同——再按 `(elementId, connectionId, type, field)` 去重。加上服务端在图无效时跳过试运行，一处错误的步骤配置不会再同时以客户端规则、`element_config_invalid` 和 `codegen_failed` 出现三次。

新元素自动获得不重复的默认名称。`uniqueLabel(elements, base, format)`（`flowchart/labels.js`）在没有元素使用 `base`（不区分大小写）时直接返回它，否则按翻译后的 `maint_core.flowcharts.editor.unique_label_format`（`{label} {n}`：「结束 2」「结束 3」）从 2 起取第一个空闲名称；已是该格式的名称从词根重新编号（「结束 2」→「结束 3」）。面板添加与放置、在旁插入、连线上的「+」以及粘贴／复制副本都使用它，指定的名称也一样（例如同一子流程第二次放入），因此新框不会被标为重名。「重命名为唯一标签」自动修复也用这个助手。

与结束相关的自动修复从末端元素中取源：从开始可达、不是开始／结束／判断、且没有出边的元素，按从开始出发的广度优先顺序排列。「添加结束元素」（`missing_end`）在最后一个末端元素下方一个间距处新建结束元素并从它连入，只记一条撤销。「从末尾步骤连入」（`orphan_end`）从最后一个末端元素连向孤立的结束元素。没有末端元素时不提供这两项修复；`canMutate()` 为假时不提供任何自动修复。

### 可读性

节点文字为 11 px（判断为 10 px）。`truncateLabel` 按宽度估算把标签截到框宽（CJK 与全角字符计 1 em，其余计 0.6 em），末尾加「…」；被截断的标签在 SVG `<title>` 中保留全文，悬停即可查看。编辑元素后，`_rerenderElement` 重绘整个分组（形状、标签、备注圆点、子流程开关、尺寸），并保留其层叠位置、选中与搜索样式、校验环和收起图标。

版本时间用 `Intl.DateTimeFormat(appLocale, { dateStyle: "medium", timeStyle: "short" })` 格式化，版本标签为 `version_label_format`（`v{number}`）。元素页签显示翻译后的类型名（`elementLabel(type)`）和 `element_connections_format`（「入 {incoming} / 出 {outgoing}」），并转义标签、类型和 id。小地图用 `ResizeObserver` 按容器尺寸设置 SVG（`sm` 以下 160×120 px，`sm` 起 200×140 px），层级为 `z-30`，位于底部面板之上。载荷过大与超时的服务端警告已翻译（见“校验与发布”）。画布 JavaScript 不含内联英文兜底：所有文案都是带英文默认值的 Stimulus value，由编辑器传入翻译后的 `data-flowchart-canvas-*-value` 覆盖。

## 需要特别注意

### 路由审计：运行边界

`spec/scripts/audit_generator_ui_spec.rb` 的生成器／UI 报告测试在独立子进程中执行真实审计，将 `OUTPUT_PATH` 指向每个用例独有的 `Tempfile`。测试检查报告及缺陷门禁，结束后自动清理临时输出。测试运行不会删除或覆盖 `docs/superpowers/specs/2026-04-19-generator-ui-audit-data.yml`；独立审计命令仍使用原有输出位置。

公开提交现按生效版本编译共享覆盖，不改全局已存产物，运行子流程须可访问且已上线。编辑器仍仅所有者可写；受保护平台前缀还要求实际外层 CID `81721200` 及所有者固定邮箱／客户身份。见[流程图运行时](flowchart-runtime)、[共享资源](shared-resources)、[租户与角色](tenancy-and-roles)。

:::note
此处说明共用授权／运行源码变更。构建器路由及生成执行不属于 10 月 11 日审计，已编写运行回归测试本次未执行。
:::

:::attention
`FlowchartVisibility.allowed?` 只认 `platform_owner?`。`RouteAuthorization#enforce_route_role!` 把这道门加在租户流程图 URL 和平台前缀上。不要在 `FlowchartsController` 上再加一层角色过滤，也不要把编辑器开放给租户管理员。已绑定的页面仍然可以提交，它们不需要这个界面。见 [页面构建器](page-builder)。
:::

:::attention
`ActivityGenerator` 做的是编译。流程图没有名称或没有元素时，`#generate` 返回 `nil`；结构校验失败且未抛异常时也返回 `nil`。`Flowchart#before_save` 把返回值写入 `activity`。之后 `activity` 为空会使 `Pages::PublicSubmission` 拒绝该页面。运行时不会靠遍历 `elements` 决定下一步。
:::

:::attention
`override_customer_id` 存在时，`Flowchart#generate_activity` 在编译前返回。覆盖线通过 `resolved_current_version` 把配置存在 `flowchart_customer_heads`。全局 `activity` 列保持平台默认。`launched_edit_locked?` 阻止对已发布全局行的定义编辑，不阻止覆盖写入。
:::

:::attention
`FlowchartServerValidator#call` 改的是内存副本，返回问题哈希。`ValidationsController` 把它们渲染成 JSON；意外错误会被接住，以 422 返回空问题列表。发布先运行 `FlowchartInputOutputValidator`，再对已存配置的另一份副本运行同样的服务端检查，两者都没有错误时才持久化 `status`。编辑器里校验通过并不等于流程图已发布；发布检查的是已保存的图，不含画布上未保存的修改。
:::

:::attention
新增的画布编辑命令必须检查 `canvas.canMutate()`（`!isReadOnly && !previewMode`），而不是 `isReadOnly`，并在其为假时隐藏对应按钮。子流程展开时，画布上显示的是预览：凡是保存、校验或打快照的代码，都读 `_previewAwareConfiguration()`（已存的折叠图），绝不直接读 `canvas.getConfiguration()`。
:::

:::attention
画布保存会带上 `expected_head_version_id`；头版本已变即返回 `409 Conflict`，不保存任何内容。不带该参数的 PATCH 跳过此检查。每次保存或恢复后都要采用返回的 `version_id`：`headVersionIdValue` 过期会让下一次保存与编辑器自己上一次的保存冲突。
:::

:::attention
每个过程框只有一个动作。`steps` 多于一条时，`StructureValidator` 报告 `process_multiple_actions`。助手的 Normalizer 在持久化前运行 `ProcessSplitter`。已存储的多动作图不做转换，校验时直接报错。
:::

:::attention
决策分支只存在出边上（`label`、`matchValue`、`fromPort`）；空匹配值即「其他」。删除分支行只删除连接，绝不删除目标框。开始、结束、判断、循环、子流程的 `properties` 只能包含目录字段，以及 `description`、`label`、`steps`、`condition`、`io_overrides`、`inputs`、`outputs`；其他键在校验和生成时都以 `unknown_field` 失败。
:::

:::attention
生成器变更后，先运行 `DRY_RUN=1 bin/rails flowcharts:regenerate_activities`，然后去掉 `DRY_RUN` 再跑一遍。已存 Activity 源码必须符合当前类形状（`CANVAS`、`Routes`、`collect_errors`）；所有者测试运行遇到没有 `CANVAS` 的类时，以「必须重新生成活动」中止。
:::

:::attention
测试面板追踪提交的内存 `configuration`。`FlowchartTracesController` 编译 `dup`，在已提交的 input 之后写入 PublicSubmission 的运行时键，并始终回滚 `requires_new` 事务，从不 `save` 版本。外部副作用不会被抑制。恢复返回 `configuration`，画布可直接 `loadConfiguration`，无需再取一次。构建器请求使用 `data-flowchart-canvas-urls-value`，不硬编码 `/:cid/admin/maintenance/flowcharts`。
:::

## 关键代码

```ruby
# app/services/flowchart_visibility.rb
  def allowed?(user)
    user.respond_to?(:platform_owner?) && user.platform_owner?
  end
```

```ruby
# app/models/flowchart.rb
  def generate_activity
    # `activity` is a compiled column on the parent row. A tenant override
    # must not overwrite the global default; runtime still reads this column.
    return if override_customer_id.present?

    self.activity = ActivityGenerator.new(self).generate
  rescue ActivityGenerator::Error => e
    # Invalid generator config must never wipe a prior activity or persist a
    # failure stub as activity source. Raise in test; elsewhere leave the
    # previous activity untouched so the configuration edit can still save.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator::Error: #{e.message}")
  rescue StandardError => e
    # Unexpected codegen bugs must never block save — otherwise the user loses
    # in-progress edits. Preserve the raise in test so we still catch
    # regressions; elsewhere annotate the activity field and move on.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator raised: #{e.class}: #{e.message}")
    self.activity = "# ActivityGenerator failed: #{e.class}: #{e.message}"
  end
```

```ruby
# app/services/activity_generator.rb
  def generate
    return nil if flowchart.name.blank? || elements.empty?
```

```ruby
# app/services/activity_generator.rb
    generator_class = @registry.find_element_type(type)
    if generator_class
      generator = generator_class.new(element, generator_context(element, ctx))
      result = generator.generate_body
      return rewrite_element_body(element, result) if result
    elsif !STEP_CONTAINER_ELEMENT_TYPES.include?(type)
      raise Error.new(
        code: :unknown_element_type,
        message: I18n.t("maint_core.flowcharts.structure_errors.unknown_element_type", type: type.inspect),
        element_id: element["id"],
        element_type: type
      )
    end
```

```ruby
# app/models/flowchart/configuration_accessors.rb
  def elements
    configuration_json&.dig("elements") || []
  end

  def connections
    configuration_json&.dig("connections") || []
  end

  def metadata
    configuration_json&.dig("metadata") || {}
  end
```

```ruby
# app/services/flowchart_server_validator.rb
  def call
    elements = Array(@configuration["elements"])
    return [] if elements.empty?
    return [payload_too_large_problem] if payload_too_large?(elements)

    Timeout.timeout(DRY_RUN_TIMEOUT_SECONDS) do
      apply_submitted_configuration!

      problems = subflow_validator.call(elements) +
                 config_validator.call(elements, Array(@configuration["connections"]))
      # The dry run only means something on an otherwise valid graph.
      next problems if problems.any? { |problem| problem[:severity] == "error" }

      problems + codegen_validator.call(@flowchart)
    end
  rescue Timeout::Error
    [validation_timeout_problem]
  end
```

```ruby
# app/controllers/admin/maintenance/flowcharts_controller.rb
    def stale_head?
      params.key?(:expected_head_version_id) &&
        params[:expected_head_version_id].to_s != @flowchart.current_line_head_version_id.to_s
    end
```

```js
// app/javascript/flowchart/canvas.js
  canMutate() {
    return !this.isReadOnly && !this.previewMode
  }
```

```ruby
# app/models/flowchart/template_builder.rb
    def new_with_defaults(attributes = {})
      attributes = attributes.to_h.dup
      template_key = attributes.delete("template") || attributes.delete(:template)
      if template_key.present?
        attributes.delete("configuration")
        attributes.delete(:configuration)
      end
```

```ruby
# app/services/activity_generator/structure_validator.rb
    MULTI_OUTGOING_EXEMPT_TYPES = %w[decision loop].freeze
```

```ruby
# app/services/code_generators/element_catalog.rb
      def tabs_for(type, fields)
        tabs = ["general"]
        tabs << "steps" if type == "process"
        tabs << "branches" if type == "decision"
        tabs << "io"
        tabs << "advanced" if fields.any? { |field| field["group"] == "advanced" }
        tabs
      end
```

```ruby
# app/services/activity_generator/structure_validator.rb
        if el["type"] == "process" && process_steps(el).size > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.process_multiple_actions", label: el["label"])
        end
        if !MULTI_OUTGOING_EXEMPT_TYPES.include?(el["type"]) &&
           @connections.count { |connection| connection["from"] == el["id"] } > 1
          errors << I18n.t("maint_core.flowcharts.structure_errors.multiple_outgoing", label: el["label"])
        end
```

相关页面：[代码生成器](code-generators)、[流程图运行时](flowchart-runtime)、[共享资源](shared-resources)、[实体构建器](entity-builder)。
