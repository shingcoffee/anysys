---
title: "流程图运行时"
summary: "保存流程图时编译成每个画布框一个 Railway 步骤：Routes 信号、collect_errors 失败轨、Outputs 汇合读取，以及追踪器使用的 CANVAS 映射。步骤在 10 秒运行期限内调用 FlowchartRuntime 辅助模块，经 Step.fail 报告失败，并可设定提交结果。"
---

## 概要

没有画布解释器。`Flowchart` 的 `before_save :generate_activity` 把 Ruby 源码写入 `activity` 列。`ActivityGenerator#generate` 返回这段源码，它是 `Trailblazer::Activity::Railway` 的子类：每个框一个 `step`，决策与循环出口用 `Routes` 信号，`fail :collect_errors`，并嵌入 `CANVAS` 映射。提交时，`Pages::PublicSubmission` 用 `ActivityClassBuilder` 加载源码，再经 `ActivityTracer#call(input, trace: false)` 运行（直接 `activity_class.call`，不追踪）。编辑器测试面板走同一追踪器，但开启追踪（`Trailblazer::Developer::Trace.invoke`）。步骤方法调用 `FlowchartRuntime` 辅助模块：记录类步骤走 `FlowchartRuntime::Entries`，所有失败都走 `FlowchartRuntime::Step.fail`，它把翻译后的消息写入 `ctx[:errors]`，把结构化条目写入 `ctx[:error_details]`。步骤还可写入 `ctx[:submission_outcome]`，决定提交者跳转到哪里、是否启动支付交接。见 [flowchart-builder](flowchart-builder)、[code-generators](code-generators)、[flowchart-step-actions](flowchart-step-actions) 与 [page-rendering](page-rendering)。

## 流程

```text
保存 Flowchart
        |
        |  before_save :generate_activity
        |  override_customer_id 存在时跳过
        v
ActivityGenerator#generate
        |
        |  name 为空或 elements 为空时返回 nil
        |  否则得到 Trailblazer::Activity::Railway 源码
        v
flowcharts.activity

POST /:cid/page/:uuid
        |
        v
PublicPagesController#submit
        |
        v
Pages::PublicSubmission#execute_activity
        |
        |  Authentication::PasswordEffects.transaction
        v
ActivityTracer#call(ctx, trace: false)
        |
        |  ActivityClassBuilder#build_activity_class
        |    DynamicClassLoader#load_into
        |    Module#module_eval(activity 源码)
        v
activity_class.call([input, {}])
        |
        |  步骤方法调用 FlowchartRuntime::Entries.scope(ctx) 与 FlowchartRuntime::*
        v
Result 的 success? / signal / ctx / submission_outcome
        |
        |  成功 + 本次新建主记录 + 存在关联分区
        v
Pages::BridgeEntries（同一保存点）
        |
        |  submission_outcome.handoff（支付）-> FeatureModules::Invocation.begin!(module_key: "payment")
        |  否则 page.handoff?               -> FeatureModules::Invocation.begin!
        v
重定向：交接 URL > 结果页面 > 默认提交后路径
```

编辑器测试面板 POST 到 `FlowchartTracesController#create`，调用 `ActivityTracer#call(input)`（开启追踪），并加上 `FlowchartRuntime::QueryLogger.capture`。追踪与不追踪的运行都在 `FlowchartRuntime::RunContext.with_deadline(10)` 与 `Timeout.timeout(10)`（`ActivityTracer::EXECUTION_TIMEOUT_SECONDS`）内执行。超时是一次失败的 `Result`。`trace.success?` 为假时事务回滚。

## 实现

`ActivityGenerator#initialize` 读取 `flowchart.elements` 与 `flowchart.connections`，把 `@bound_entity` 设为 `flowchart.entity`，并构造 `DynamicClassLoader.new(bound_entity)`。`flowchart.name` 为空白或 `elements` 为空时，`generate` 返回 nil。无效循环这种结构错误会抛出 `ActivityGenerator::Error`，代码为 `:invalid_loop_topology`。不支持的结构类型抛出 `:unsupported_structural_element`。其余结构失败会记日志，然后 `generate` 返回 nil。成功时经 `CodeGenerators::GeneratorRegistry` 深度优先遍历图，生成一个 `Trailblazer::Activity::Railway` 类。

`Flowchart#generate_activity` 把 `generate` 的结果赋给 `self.activity`。`override_customer_id` 存在时先返回，因此对共享流程图的租户覆盖不会替换全局源码。见 [shared-resources](shared-resources)。测试环境里 `ActivityGenerator::Error` 会再次抛出；其他环境保留原来的 `activity`。其他 `StandardError` 在测试环境再次抛出；其他环境写入以 `# ActivityGenerator failed:` 开头的注释。

`Pages::PublicSubmission` 读取 `configuration_json["form_settings"]["flowchart_id"]`。它加载 `Flowchart.accessible.referenceable`（`status: :launched`）。`activity` 为空白时返回 `:invalid`，HTTP 状态为 `:unprocessable_entity`。页面必须有实体。客户自有流程图的 `entity_id` 与页面实体不同时返回 `:invalid`。共享流程图的 `entity_id` 为 nil（`Flowchart#entity_binding_based_on_shared_identity`），因此这条不一致检查不适用。上下文哈希见下文“上下文约定”。

`ActivityClassBuilder#build_activity_class` 创建一个匿名模块，调用 `DynamicClassLoader#load_into`，对每个子流程的 `activity` 字符串做一次 `module_eval`（`loaded_ids` 跳过已在命名空间中的子流程——两处引用同一子流程不会再次求值 `CANVAS`），再对主源码做 `module_eval`。新出现的、继承 `Trailblazer::Activity::Railway` 的常量就是要运行的类。有实体时，`DynamicClassLoader` 按 `entity.property_schema_json` 建立访问器，并用 `EntityEntryContract.build_for` 建立契约。实体为 nil 时定义 `BlueprintEntity` 与 `BlueprintEntityContract`。生成源码里的记录步骤在运行时经 `FlowchartRuntime::Entries` 使用页面实体，`new_model` 也不例外（`Entries.scope(ctx).new(customer_id: ctx[:customer_id])`）。

`FlowchartRuntime` 是这些生成方法调用的一组辅助模块（`app/services/flowchart_runtime/`）。第三阶段的约定见下面各小节：`Step`、`RunContext`、`Entries`、`Http`，以及新动作背后的辅助模块。其他辅助模块包括 `QueryBuilder`、`Authentication.session`／`.password`、`Jwt`、`Invocable.service!`／`.job!`、`ConditionInput.compare`、`Token`、`Crypto`、`SandboxPath`、`Errors.collect`、`Outputs.latest`／`.view`，以及 `Loop`／`LoopState`／`ExecutedOutputs`。`Invocable` 只解析允许名单中的类名，且方法必须定义在 `app/` 下（所有者不能是 Object／Kernel／BasicObject／Module／Class）。它拒绝 ActiveRecord 模型类和破坏性方法（`delete_all destroy_all update_all delete destroy update_column update_columns insert_all upsert_all find_by_sql connection`）。`SERVICE_NAMESPACES` 包含 `FeatureModules`，因此调用服务步骤可以调用该命名空间中的类。生成的步骤里没有调用 `FeatureModules::Invocation` 的步骤；`request_payment` 只在 `ctx[:submission_outcome]` 里挂起交接，由控制器启动（见“提交结果”）。见 [module-framework](module-framework)。

`ActivityTracer#call` 在执行前把 `input[:params]` 转成 `HashWithIndifferentAccess`，因此生成的读取（`ctx[:params][:amount]`）对公开提交（字符串键）和管理员测试面板同样有效。编辑器测试运行（`FlowchartTracesController#create`）在已提交的 input 之后写入与 `Pages::PublicSubmission#build_context` 相同的运行时键（`bound_entity` 为被追踪流程图的实体，共享且无实体时为 nil），并在始终回滚的 `ActiveRecord::Base.transaction(requires_new: true)` 内追踪。测试运行的数据库写入不会持久化；邮件、Webhook 和缓存写入不会被抑制。成功的判断是 `signal.to_h[:semantic] == :success`。信号不是成功、追踪器报错，或抛出异常时，`PublicSubmission` 记为 `:failed`。成功时，若 `ctx[:model]` 是 `EntityEntry`，就返回它。

使用 `> >= < <=` 的决策／循环条件发出 `FlowchartRuntime::ConditionInput.compare`。两侧必须是有限 Numeric 或数字字符串（`"150" > 100` 为真）。一侧非数字，或强制转换后非有限（`Infinity`、`NaN`、溢出如 `1e309`），比较为假。不支持的运算符抛出 `ArgumentError`。相等与字符串运算符仍是 Ruby 运算符。

`authorize` 只在 `userExpression`（默认 `current_user`）的值是 `Authentication::User` 时检查它；否则使用 `FlowchartRuntime::Authentication.session(context: ctx[:authentication], customer_id: ctx[:customer_id])`。`load_current_user` 写入的 Hash 从不授予访问权限。拒绝时报 `authorize.denied`。`send_template_email` 从 `ctx[:customer_id]` 解析客户。`EntityEntryContract` 把 Integer 传给 `length_minimum`／`length_maximum`。

### 生成的类形状

除起点与无步骤终点外，每个画布框对应一个 Railway `step` 和一个 `def <name>(ctx, **)`。方法体就是该动作发出的代码，别无其他：没有步骤级的条件、重试或超时包装，也不包 lambda。空过程框发出 `true`。

决策按 `fromPort` 顺序为每条出边声明一个 `Routes::<Decision>::<Branch>` 信号，并用 `Output(signal, :semantic) => Id(...)` 接线。未使用的默认成功输出接到 `Output(:success) => Track(:failure)`，决策未返回任何分支信号时明确失败。`routeBy: condition` 发出三元式，返回「是」信号或「否」（没有则「其他」）信号；`routeBy: value` 发出 `case <subject>.to_s`／`when`／`else`，`else` 指向「其他」分支（空 `matchValue`），没有则为最后一个分支。

`responseType` 为 `none` 的终点没有步骤，入边接到 `End(:success)`。`responseType` 为 `value` 的终点是一个步骤，把 `returnValue` 写入 `ctx[:response]` 后成功。每个终点都是成功终点。

子流程是 `step Subprocess(<ChildActivity>), id: :<name>`，接线规则相同。两处引用同一子流程会得到不同的步骤 id。`SubflowGenerator#generate_body` 为 nil，由编排器发出 `Subprocess` 声明。

类中嵌入 `CANVAS = { steps:, routes:, ends: }.freeze`。`steps` 把每个步骤 id 映射到元素 id。`routes` 把决策（或循环 `:done`）语义映射到连接 id。`ends` 把步骤的输出语义映射到它所到达的无步骤终点。`routes` 与 `ends` 为空时省略。追踪器与示意图从实际运行的类读取这张表。

```ruby
# frozen_string_literal: true
#
# Generated from flowchart #99 "Two Level". Do not edit; regenerate it from the flowchart editor.
# No bound entity
class TwoLevelActivity < Trailblazer::Activity::Railway
  CANVAS = {
    steps: { is_vip: "outer", is_rush: "inner", fast_path: "fast", slow_path: "slow", standard_path: "standard" },
    routes: { is_vip: { yes: "c2", no: "c3" }, is_rush: { yes: "c4", no: "c5" } },
    ends: { fast_path: { success: "end_ok" }, slow_path: { success: "end_ok" }, standard_path: { success: "end_other" } }
  }.freeze

  module Routes
    module IsVip
      Yes = Class.new(Trailblazer::Activity::Signal)
      No = Class.new(Trailblazer::Activity::Signal)
    end
    module IsRush
      Yes = Class.new(Trailblazer::Activity::Signal)
      No = Class.new(Trailblazer::Activity::Signal)
    end
  end

  step :is_vip,
    Output(Routes::IsVip::Yes, :yes) => Id(:is_rush),
    Output(Routes::IsVip::No, :no) => Id(:standard_path),
    Output(:success) => Track(:failure)
  step :is_rush,
    magnetic_to: nil,
    Output(Routes::IsRush::Yes, :yes) => Id(:fast_path),
    Output(Routes::IsRush::No, :no) => Id(:slow_path),
    Output(:success) => Track(:failure)
  step :fast_path, magnetic_to: nil, Output(:success) => End(:success)
  step :slow_path, magnetic_to: nil, Output(:success) => End(:success)
  step :standard_path, magnetic_to: nil
  fail :collect_errors

  # Is Vip
  def is_vip(ctx, **)
    (!!ctx.dig(:vip)) ? Routes::IsVip::Yes : Routes::IsVip::No
  end
  # …
end
```

页眉、命名与接线规则见 [代码生成器](code-generators)。

### 错误约定

每个生成的类以 `fail :collect_errors` 结束：

```ruby
def collect_errors(ctx, **)
  ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
end
```

`FlowchartRuntime::Errors.collect(ctx)` 返回 `ctx[:errors]` 中已有的唯一消息（由 `Step.fail` 或子流程写入），再追加每个响应 `errors.full_messages` 的顶层 ctx 值的完整消息（Reform 契约、Active Model 记录）。

### 步骤失败

`FlowchartRuntime::Step` 是生成步骤唯一的失败路径：

- `Step.fail(ctx, code, field: nil, **details)` 把 `I18n.t("flowchart_runtime.errors.#{code}", **details)` 追加到 `ctx[:errors]`（去重），把 `{ "code", "field", "details" }`（details 转字符串）追加到 `ctx[:error_details]`，再返回 `false` 让 Railway 步骤失败。代码分通用（`record_not_found`、`record_invalid`、`record_not_destroyed`、`record_busy`、`timed_out`、`transport_error`、`http_status`、`circuit_open`、`rate_limited`、`duplicate_request`、`invalid_json`、`business_error`、`unknown_attribute`、`blocked_destination`、`loop_limit`）与动作级（`register_member.public_only`、`register_member.person_entity_required`、`register_member.signup_disabled`、`register_member.unavailable`、`send_sms.quota`、`refund_payment.not_found` 等）。
- `Step.fail_message(ctx, localized, code: :business_error, field: nil)` 使用作者编写的 `{ "en", "zh-CN" }` 消息（`fail_with_error`），经 `LocalizedText.resolve` 按请求语言取值。
- `Step.attempt(ctx, code, *error_classes) { … }` 只救援列出的类，失败时 `reason:` 为去掉命名空间的类名，并把异常消息存为最后一条 `error_details` 的 `"diagnostic"`。诊断信息供追踪与日志使用；flash 只显示翻译后的消息。
- `Step.dig(value, *keys)` 是 `input` 路径编译成的嵌套读取：Hash 键不区分字符串／符号，数组用整数下标，任何一步缺失都返回 `nil`。

`ctx[:error_details]` 出现在测试运行 JSON 的 `context` 中（已消毒、脱敏），从不进入公开 flash。

### 运行期限

`FlowchartRuntime::RunContext` 是基于 `CurrentAttributes` 的期限。`ActivityTracer` 用 `with_deadline(10)` 设置它；`RunContext.remaining` 返回剩余秒数（未设置期限时为 10，如单元测试）。HTTP 辅助模块把超时裁剪到该值。步骤动作不得自行调用 `Timeout.timeout` 或 `sleep`（BodyLint，见 [code-generators](code-generators)）。

### 上下文约定

运行以 `ConfigSchema::SEEDED_KEYS` 开始。`Pages::PublicSubmission#build_context` 写入 `params`（经 `FormParams.permit_parts` 与 `Pages::AudienceGuard` 后的主实体扁平属性）、`association_params`（按分区 slug 分组的关联分区，仅在表单声明关联字段时写入）、`bound_entity`（页面实体）、`customer_id`、`authentication`（`FlowchartRuntime::Authentication.from_request`）、`current_user_id`、`current_user_role`、`audience`、`device_type`（去掉 nil 值）和 `current_person_ids`（同租户访问者的 `{ "<人员实体 id>" => 条目 id }`，来自 `People::Ownership.person_entry_ids`；匿名、未关联或其他租户访问者为 `{}`），再写入 `request_ip`（`Current.ip_address`）、`user_agent`、`locale`、`request_id`、`identity` 与 `continuation`。`ActivityTracer#call` 给每次运行合并 `flowchart_id: flowchart.id`，覆盖任何提交上来的值。`FlowchartTracesController#create` 为测试运行写入同样的键（`request.remote_ip`、`request.request_id`）。

`ctx[:identity]` 是字符串键哈希，只含页面上已放置、`source: "identity"` 的身份字段（`People::IDENTITY_KEYS`：`first_name`、`last_name`、`email`）。`FormParams.permit_identity` 仅对人员实体页、且仅对公开与管理员受众放行；会员得到 `{}`。未知键（包括 `identity[password]`）会被丢掉。身份从不进入 `ctx[:params]`。通用记录步骤（`save_model`、`Entries.assign`、`ActivitySteps::PopulatePrimary`）从不写这些键；只有 `FlowchartRuntime::Registration` 会把它们抄到未关联的人员条目上。

`ctx[:continuation]` 为符号键 `{ action_key:, prefill: }` 或 nil。`Pages::Continuation.verify` 读取提交的 `_continuation`（purpose `page_continuation`，3 天）。令牌不带 URL，也不带客户编号。被篡改、过期、用途不符或过大的令牌校验为 nil，提交仍然成功。见[页面渲染](page-rendering)。

`output` 字段不得取预置键或 `errors`、`error_details`、`submission_outcome`、`result`（`OUTPUT_RESERVED`）；`submission_outcome` 由 `set_submission_outcome`、`request_payment` 与 `register_member` 写入（仅在尚未设置 preset 时写入 `registration_pending`）。`input` 路径不得以 `errors`、`error_details`、`submission_outcome` 或 `result` 开头。

### 记录

`FlowchartRuntime::Entries` 是记录辅助模块：

- `scope(ctx)`：对 `ctx[:bound_entity]` 返回 `EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)`，未绑定实体时返回 `EntityEntry.none`。`scope_for(ctx, entity)` 对另一个实体做同样的事，前提是 `EntityResolver.accessible?`，否则抛出 `Entries::Error`。这些 scope **不**经过 `People::Ownership`：名额检查必须统计全部报名。
- `find_current_person(ctx, entity_id:)`：访问者在绑定人员实体上的已关联条目。只读 `ctx[:current_person_ids]`（`{ "<人员实体 id>" => 条目 id }`），从不读 params。条目仍存在于运行租户且属于绑定实体时返回该条目。绑定实体不是人员实体、映射缺失或没有关联时返回 nil。`find_model` 在 `findBy: current_person` 时调用它，nil 则失败为 `record_not_found`。
- `find_by`／`where`：`id` 用列谓词；其他键对 `data.<slug>` 用 `json_extract`（经 `JsonPathValidator` 校验）。未知 slug 抛出 `Entries::UnknownAttribute`。
- `assign(entry, attributes, strict: false)`：只写可写属性 slug；忽略 `INTERNAL_COLUMNS`（`id customer_id entity_id entity_version_number user_id data created_at updated_at`），`strict: true` 时遇到未知键抛错。
- `save(ctx, entry)`：拒绝其他客户的条目；校验失败时把 `errors.full_messages` 追加到 `ctx[:errors]`，附 `record_invalid` 明细，返回 false。
- `upsert(ctx, match:, attributes:)`：对匹配摘要的租户作用域键取单次 `Lock`（否则 `record_busy`），返回 `[entry, created]`。
- `destroy(ctx, entry)`（`record_not_destroyed`）与 `archive(ctx, entry, field:, by_field:)`（写入 `Time.current` 与 `current_user_id`）。
- `query`、`tally`、`aggregate`、`filter`、`where_attributes` 支撑查询类动作。

#### 共用模型与契约的写入边界

`EntityEntry.build_for(entity)` 跳过与 `EntityEntry.column_names + %w[entity customer]` 匹配的结构标识，保留实际 AR 列及这两个关联的权威访问器。Calculated／Computed 结构属性有读取方法，不生成写入方法。匿名运行时子类返回 `EntityEntry.model_name`，供 Rails／I18n 校验错误及 `RecordInvalid` 使用，同时沿用父类表名及 STI 身份。该保护属于运行时工厂，不是对独立 `ModelGenerator`／`attribute_accessor` DSL 的修改。

`EntityEntryContract.build_for(entity, audience: nil, writable_slugs: nil)` 保留已声明属性的读取方法及既有按受众生效的校验。只有 `presence`（及 `acceptance`）会拒绝空值；其他校验器都附加 `allow_blank: true`（`ValidatorRegistry::REQUIRING_VALIDATIONS`），因此可选的数字、列表选项或邮箱可以留空，填写后才校验。`schema_property_options` 为 `type: "Calculated"`、`type: "Computed"` 或 `storage: "computed"` 的属性设置 Reform 2.6 的 **`writeable: false, parse: false`**。`parse: false` 忽略提交值，`writeable: false` 阻止 `sync` 与 `save` 调用模型写入方法，因此派生值不写入 `data`。这些选项不计算缺失值，也不移除校验；适用的校验器仍可拒绝模型派生值／当前值。

非 nil 的 `writable_slugs` 允许名单（由工厂统一转为字符串）对所有排除属性施加相同限制，保留已有值，防止整表单同步为隐藏属性写入 nil 键。为 `nil` 时，普通属性沿用原有反序列化／同步行为；受众限定校验范围，本身不建立此写入允许名单。`ContractGenerator.new(entity, writable_slugs: nil)` 调用同一个选项辅助方法，经 `property_accessor(name, validates: nil, **property_options)` 生成完全一致的标记，并保留受众校验守卫。

管理端**创建条目**通过 `Entities::Activities::CreateEntry` 使用管理员契约及表单写入允许名单。它解析客户生效结构，在自己的保存点内只保存一条租户主条目，不写派生字段、桥接记录或基础模型。它不执行流程图，也不调用 `ActivitySteps::SaveAll`；后者保留独立的主记录加桥接记录事务。HTTP 入口、默认值、支持的控件及授权见[实体构建器](entity-builder)。

### 步骤动作背后的运行时辅助模块

- `CurrentUser.load(ctx)`：在 `ctx[:customer_id]` 范围内为 `ctx[:current_user_id]` 返回冻结 Hash `{ id, email, name, role, person_entries }`，找不到时为 nil。`person_entries` 为 `People::Ownership.person_entry_ids` 的 `{ "<人员实体 id>" => 条目 id }`（与 `ctx[:current_person_ids]` 同一张映射）。`load_current_user` 把它写入 `ctx[:current_user]`。该 Hash 不授予访问权限（`authorize` 把它当作无主体）。
- `QueryBuilder.for_entity(entity, customer_id:, scope:)`：可选 `scope:` 替换默认租户关系。页面列表与查询选项来源传入 `People::Ownership.scope`。流程图调用方从不传入，因此查询／计数／聚合步骤看到本租户全部行。
- `Constants.options(ctx, id)`／`label(ctx, id, value)`：按 `ctx[:customer_id]`（从不用 `Current`）读取常量选项。共享常量有该客户的 `ConstantCustomerOverride` 时用覆盖；其他租户的常量抛出 `Constants::Error`。供 `read_setting` 使用。
- `LocalizedText.resolve(value, locale:)`：取对应语言文本，回退到 `en`。
- `Payments.request(ctx, amount:, currency:, subject:)`：见“提交结果”。失败代码为 `request_payment.invalid_order`（无客户、主题为空，或经 `Payments::Money.normalize` 后金额非正）或 `request_payment.module_disabled`（支付模块不存在、不支持交接或该客户未启用）。
- `Payments.refund(ctx, payment:, amount:, reason:)`：支付必须属于运行客户（否则 `refund_payment.not_found`）；在 `Current.set(customer:)` 下运行 `Payments::Activities::Refund`。`RefundNotAllowed` 映射为 `refund_payment.<code>`（`not_captured`、`non_positive`、`exceeds_remainder`、`billing_collection`），其他支付错误映射为 `refund_payment.failed`。
- `Sequence.next(ctx, name:, period:, prefix:, padding:)`：`flowchart_sequences` 中按客户计数；`period` 为 `never`、`year`（分桶 `%Y`）或 `month`（分桶 `%Y-%m`）；位数 1–12（默认 6）。行用 `create_or_find_by!` 创建，在事务内以 `UPDATE … last_value + 1` 递增。
- `RateLimiter.allow?(ctx, name, capacity:, window:)`：固定窗口计数器，按客户、名称、窗口时长与当前窗口起点分桶，基于 `Authentication::Throttle#hit!`（共享缓存中的原子自增），并发运行不会同时抢到最后一个名额。从不休眠；`rate_limiter` 按 `onExceed` 以 `rate_limited` 失败或跳过。名称为空、`capacity`／`window` 非正数时抛出 `RateLimiter::Error`。
- `Notifications.create(ctx, recipient:, title:, body:, page_id:)`：收件人必须是该客户的 `Authentication::User`（否则 `create_notification.recipient_not_found`）；页面只有已上线且为自有或共享时才保留。
- `Audit.write(ctx, event_type:, …, severity:)`：级别为 `debug info warn error critical`；有 `customer_id` 时插入一行 `flowchart_audit_events`（带 `ctx[:flowchart_id]`），并记一行 `[AUDIT]` JSON 日志。该行属于运行事务，随之回滚。
- `SmsDelivery.deliver(ctx, customer:, to:, template_key:, vars:, idempotency_key:)`：见“短信发送”。
- `Document.pdf(title:, body:, filename:, rows:, columns:, customer_id:)`：用 Prawn 渲染（`##` 行成为标题，rows 渲染为 ` | ` 表格），存为带 `customer_id` 元数据的 ActiveStorage blob，返回 `{ blob_id, signed_id, filename, content_type, byte_size, checksum, customer_id }`。错误抛出 `Document::Error`，`generate_document` 用 `Step.attempt` 包住。只有内容含中日韩文字时才使用中日韩字体；字体回退顺序见 [flowchart-step-actions](flowchart-step-actions)。
- `Authentication.token(raw:, expected:, type: "bearer")` 与 `api_key(raw:, expected:)`：`authenticate` 使用的恒定时间比对。
- `Registration.call(ctx, person:)`：`register_member` 的辅助方法。规则顺序：（1）受众不是公开则失败为 `register_member.public_only`；（2）绑定实体不是人员实体则失败为 `register_member.person_entity_required`；（3）认证模块未启用或 `Authentication::Settings#signup_enabled?` 为假则失败为 `register_member.signup_disabled`（由步骤把关，`RegisterMember` 本身不检查）；（4）身份无效（只查必填与格式；忽略唯一性 `:taken`，以免已有地址在此失败）→ 与 `save_model` 相同的 `record_invalid`；（5）规范化邮箱属于任一已有用户时不保存——若该用户是本租户已确认的有效会员，则发登录链接（与登录链接页共用按地址计数的防轰炸限额，超限后不再发信）并只记续接认领，否则什么都不做（未确认会员原有的认领保持不变）；结果 `{ "status" => "existing" }`；（6）否则注册无密码、未确认的会员，把身份写入人员条目的 `data` 且 `user_id` 为 nil，并记 `created_user: true` 的认领；结果 `{ "status" => "created" }`；（7）会员配额已满时不保存任何内容，按（5）的方式返回 `{ "status" => "existing" }`（并记录警告日志）；客户不存在 → `register_member.unavailable`；（8）流程图尚未设置 preset 时，把提交结果设为 `registration_pending`。`created` 与 `existing` 对浏览器显示同一闪讯。已有地址的分支经 `Authentication::NotifyExistingMember` 处理，与注册表单共用。步骤在查询邮箱前写入 `ctx[:uniform_timing_started_at]`；提交事务完成后，`Pages::PublicSubmission` 用 `Authentication::UniformTiming` 补齐响应耗时，使三个分支的最短耗时一致（见[认证](authentication)）。不要按 `registration.status` 分支——那会暴露哪些邮箱已有账号。

### 提交结果

`ctx[:submission_outcome]` 是运行回传给页面控制器的唯一通道。`set_submission_outcome` 写入 `preset`（`submitted`、`saved`、`thank_you`、`custom`）、可选的本地化 `message`（`custom` 时必填）、`flash`（`notice`／`alert`）和 `target`（`{ type: "form" }` 或 `{ type: "page", page_id }`），并保留已有的 `handoff`。`request_payment` 追加 `handoff: { module_key: "payment", input: { amount, currency, subject } }`。`register_member` 在尚未设置 preset 时写入 `registration_pending`；该值不在 `set_submission_outcome` 的枚举里。`Pages::PublicSubmission::Result#submission_outcome` 返回其深度字符串化版本，传给 `PublicSubmission.call` 的块在业务保存点内收到 `(entry, outcome)`。

`PublicPagesController#submit` 按以下顺序处理：

1. **支付交接**：`outcome.handoff.module_key == "payment"` → `FeatureModules::Invocation.begin!(module_key: "payment", input: handoff["input"], …)`。随后由结账（`Payments::CheckoutsController`）创建订单；运行本身不创建订单。
2. **页面交接**：否则，`Page#handoff?`（`form_settings.after_submit == "handoff"`）为真时调用 `start_page_handoff`。
3. **结果页面**：没有交接 URL 时，`target.type == "page"` 跳转到该页面，前提是它已上线、属于当前客户且对访问者可见；否则忽略。
4. **默认**：`post_submit_path`。

未设置 preset 时 flash 为 `public_views.flash.response_submitted`（notice）。设置了 preset 时用本地化的 `message`，否则用 `public_views.flash.outcomes.<preset>`（回退到 `response_submitted`）；`flash == "alert"` 时以 alert 显示。

### 运行时数据表

迁移 `20261019133000_create_flowchart_runtime_tables` 新增三张租户作用域表（模型 `FlowchartSequence`、`FlowchartAuditEvent`、`FlowchartNotification`，均为 `TenantScoped`）：

| 表 | 列 | 写入者 |
|----|----|--------|
| `flowchart_sequences` | `customer_id`、`name`、`period`、`last_value`（默认 0）；唯一 `(customer_id, name, period)` | `next_sequence_number` |
| `flowchart_audit_events` | `customer_id`、`flowchart_id`、`event_type`、`resource_type`、`resource_id`（字符串）、`actor_user_id`、`ip`、`user_agent`、`severity`（默认 `info`）、`metadata`（JSON）、`created_at` | `audit_log` |
| `flowchart_notifications` | `customer_id`、`user_id`、`title`（JSON）、`body`（JSON）、`page_id`、`read_at`、时间戳 | `create_notification` |

目前没有页面读取审计事件或通知。

公开提交走到失败轨时，用这些已收集字符串填充 `public_views.flash.response_save_error`（按请求语言做 `to_sentence`）。没有已收集消息，或运行抛出异常时，仍用通用的 `common.errors.dynamic.activity_execution_failed`。异常文本不会进入 flash。测试运行 JSON 含 `errors`（`ctx[:errors]`，字符串、非空、去重）。

### HTTP 助手

`FlowchartRuntime::Http.request` 是流程图步骤（`api_call`、`send_webhook`、`download_file`、`ai_inference`、`currency_convert`、`geolocation_lookup`）唯一的出站 HTTP 路径。它以 `public_only: true` 调用 `OutboundHttp.request`；设置了 `max_bytes` 时改用 `OutboundHttp.stream`，超限响应体在传输中途即中止，不会先整体缓冲；唯一例外是 `ai_inference` 的 `ollama` 提供方，其端点为固定的本地常量 `FlowchartRuntime::Ai::OLLAMA_URL`（从不取自步骤输入）。

签名：`Http.request(ctx, method, url, headers:, query:, body:, form:, open_timeout: 3, read_timeout: 7, retries: 0, breaker: nil, follow_redirects: false, max_redirects: 3, max_bytes: nil, public_only: true)`。2xx 返回响应；其余结果都返回 `Step.fail`：

- **超时**：`open_timeout`／`read_timeout` 来自步骤的 `connectTimeout`／`readTimeout`，并裁剪到 `RunContext.remaining`。首次尝试前剩余不足 1 秒时，步骤以 `timed_out` 失败。
- **传输重试**：`retries`（开启 `retryOnTransportError` 时取自 `retryAttempts`；最多额外 2 次）只针对 `OutboundHttp::TransportError`，立即重试（无退避），且仅在剩余至少 1 秒时进行。编辑器只允许对幂等请求开启（见 [code-generators](code-generators)）。HTTP 状态码从不重试。
- **熔断器**：传入 `breaker: { name:, threshold:, reset_seconds: }` 时，按客户与名称键入的 `CircuitBreaker.evaluate` 把关；熔断打开时以 `circuit_open`（`name`）失败。传输错误、5xx 响应与超大响应体计为失败；2xx 计为成功。
- **状态与传输**：非 2xx 以 `http_status`（`status`）失败；无效请求、重定向错误、重试后仍失败的传输错误以及超过 `max_bytes` 的响应体以 `transport_error`（`reason`）失败。`max_bytes` 在流式读取时逐块校验（`OutboundHttp::ResponseTooLargeError`，reason 为 `ResponseTooLargeError`）。

#### 公网地址守卫

对初始 URL 以及随后每一跳重定向，`OutboundHttp.request` 与 `OutboundHttp.stream`（均传 `public_only: true`）解析 URI、要求 `http`／`https`、解析主机（`Resolv.getaddresses`，字面 IP 同样处理），在没有地址或任一地址非公网单播时抛出 `OutboundHttp::BlockedDestinationError`。拦截范围包括回环、RFC1918 私网、链路本地（含 EC2 元数据地址 `169.254.169.254`）、未指定地址与 IPv4 兼容 IPv6（`0.0.0.0`／`::/96`）、组播、CGNAT `100.64.0.0/10`、`0.0.0.0/8`、`192.0.0.0/24`、`198.18.0.0/15`、`240.0.0.0/4`、广播 `255.255.255.255`、IPv6 唯一本地 `fc00::/7`、内嵌 IPv4 非公网的 IPv4 映射 IPv6，以及 NAT64 `64:ff9b::/96`。`Http.request` 将其映射为 `Step.fail(ctx, :blocked_destination)`（`flowchart_runtime.errors.blocked_destination`），不重试、不记入熔断失败。放行的跳次把 TCP 连接钉在已校验的公网 IP 上（`Net::HTTP#ipaddr=`），避免检查之后 DNS 重绑定改写套接字目标。支付、短信、验证码等供应商调用不传 `public_only`，行为不变。

### 汇合读取

互斥分支上的写入共享同一个 ctx 键。`ConflictResolver` 仅在同一键的另一写入者是其祖先时才重命名（循环回边不计）。没有显式输入覆盖或墓碑的 `ctx[:pin]` 读取，取实际跑过的写入者：只有一个候选时用其生效键；多个候选且最新者支配读者时用该键；否则编译为 `FlowchartRuntime::Outputs.latest(ctx, :key_a, :key_b, …)`（第一个已存在的键，含显式 `nil`）。`ctx.dig`／`fetch`／`key?` 把接收者换成 `FlowchartRuntime::Outputs.view(ctx, :pin, …)`，以保持 Hash 语义。隐含的 `FlowchartRuntime::Entries.scope(ctx)` 读取不会被改写。

```ruby
  def merge(ctx, **)
    ctx[:summary] = "{{status}}/{{reviewer}}".gsub("{{status}}") { (FlowchartRuntime::Outputs.latest(ctx, :status_ff6b, :status) || '').to_s }.gsub("{{reviewer}}") { (ctx[:reviewer] || '').to_s }
    true
  end
```

`status` 在决策前写入，并在一条分支上被覆盖（`status_ff6b`）；互斥的 `reviewer` 写入者共用原键。解析器与改写器约定见 [代码生成器](code-generators)。

### 追踪器

`ActivityTracer` 通过 `<ActivityClass>::CANVAS` 把电路节点 id 映射到画布元素，不再重新运行生成器。追踪运行遇到没有 `CANVAS` 的类时直接拒绝，返回 `flowchart_elements.trace.errors.must_regenerate`。列出的每个节点是 `{ id, element_id, label, status, signal, branch, ctx_snapshot }`。仅路由信号带 `branch`（连接标签，否则为语义）。`ctx_snapshot` 尽力而为（有上限、已脱敏；`ContextSanitizer` 去掉所有 `_` 开头的键）。状态：Right → `success`，Left → `failure`，路由信号 → `success` 并带 `branch`。`trace_nodes` 按执行顺序最多保留 `ActivityTracer::MAX_TRACE_NODES`（500）个节点；列表被截断时，`Result#truncated` 与追踪 JSON 的 `trace_truncated` 为真。

`Result#error` 是翻译后的通用消息（`flowchart_elements.trace.errors.no_activity_code`、`failed_to_build`、`execution_failed`、`timed_out`、`must_regenerate`）。异常类与消息只写日志，不进入追踪 JSON。

`collect_errors` 与子流程自身的终点不列入。`Start.default` 带画布起点元素 id。`End.success` 带到达的终点：无步骤终点走 `CANVAS[:ends]`；最后执行的步骤本身是带响应的终点时，用该步骤的元素。带响应的终点步骤在成功时从 `trace_nodes` 省略，使该元素只作为 `End.success` 出现一次；失败的终点步骤仍可见。终点标签走翻译（`flowchart_elements.trace.*`）。步骤抛出时保留部分追踪，抛出步骤标为 `failure`。

公开提交调用 `ActivityTracer#call(input, trace: false)`：超时内执行 `activity_class.call`，`trace_nodes` 为空，不要求 `CANVAS`。所有者测试运行保留追踪。

`ActivityDiagramGenerator` 同样读取 `CANVAS`。决策边用分支标签，省略决策未使用的默认成功／失败边，带响应的终点画成一个带该终点标签的终止节点，并从标签中去掉 Mermaid 特殊字符（控制字符、括号、引号、竖线、`;`、`#`、反引号、`&`、`%%`、`:::`）。

### 循环

本小节摘录对应当前循环生成器（`LoopGenerator` 与 `FlowchartRuntime::Loop`／`LoopState`／`ExecutedOutputs`）。若页眉方法体或写入辅助模块有变，需重新同步。

循环页眉是普通步骤。循环体紧接其后声明。每个循环体尾部接线 `Output(:success) => Id(:<loop>)`。页眉的 Done 信号接到出口：

```ruby
  step :init_total
  step :each_item, Output(Routes::EachItem::Done, :done) => Id(:report)
  step :add_item, Output(:success) => Id(:each_item)
  step :report, magnetic_to: nil
  fail :collect_errors
```

`CANVAS[:routes]` 记录页眉的 `:done` 连接。迭代状态放在一个短键下（`:_each_item`、`:_repeat` 等，即 `:_<步骤名>`）。`FlowchartRuntime::Loop.enter(ctx, :_<方法>, execution: "_loop_io", pins: [...], initializers: {...})` 创建它；`Loop.leave` 删除它并返回 nil，方法再返回 `Routes::<Loop>::Done`。`collect_errors` 也会删除该键，避免复用 ctx 时泄漏。槽位键由页眉方法名派生（`:_loop_each_item_total`）。

有画布循环体时，页眉是一段直线代码：离开、到达上限即失败，或开始下一轮，然后返回 `true`。只有无循环体（页眉直连终点）才在页眉内写真正的 `loop do`／`while`。有循环体的 **for_each** 若要跳过项，用 `while (<skipWhen>)` 前进（或离开、或到达上限即失败），不用外层迭代循环。

```ruby
  def repeat(ctx, **)
    # While loop with max iterations safety limit
    state = FlowchartRuntime::Loop.enter(ctx, :_repeat) { { count: 0 } }
    ctx[:_loop_iteration_count] = state[:count]
    return FlowchartRuntime::Loop.leave(ctx, :_repeat, {}) || Routes::Repeat::Done unless (FlowchartRuntime::ConditionInput.compare(ctx.dig(:count), "<", 3))
    return FlowchartRuntime::Loop.fail_limit(ctx, :_repeat, max: 5, exports: {}) if state[:count] >= 5
    state[:count] += 1
    ctx[:_loop_iteration_count] = state[:count]
    true
  end

  def collect_errors(ctx, **)
    ctx.delete(:_repeat)
    ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
  end
```

遍历 `items`、带一行跳过该项的条件（`ctx.item` 为空）、使用默认上限的 for_each 页眉：

```ruby
    state = FlowchartRuntime::Loop.enter(ctx, :_each_item) { { items: Array(ctx[:items]), index: 0, count: 0 } }
    ctx[:_loop_iteration_count] = state[:count]
    return FlowchartRuntime::Loop.leave(ctx, :_each_item, {}) || Routes::EachItem::Done if state[:index] >= state[:items].size
    return FlowchartRuntime::Loop.fail_limit(ctx, :_each_item, max: 100, exports: {}) if state[:index] >= 100
    item = state[:items][state[:index]]
    index = state[:index]
    state[:index] += 1
    ctx[:item] = item
    ctx[:index] = index
    while (ctx.dig(:item).blank?)
      # same leave / fail_limit / bind lines for the next item
    end
    state[:count] += 1
    ctx[:_loop_iteration_count] = state[:count]
    true
```

无出处的写入保持 `ctx[:pin] = value`（`item`、`index`、`_loop_iteration_count`）。受追踪的循环数据用 `FlowchartRuntime::LoopState.write(ctx, :pin, value, slot:, producer:)` 与 `FlowchartRuntime::ExecutedOutputs.fetch(ctx, :pin, candidates: [...])`。`itemVariable`／`indexVariable` 不能是 `state` 或 `ctx`（`flowchart_elements.loop.errors.reserved_header_local`），也不能同名（`colliding_loop_variables`）。

语义（字段见 [流程图构建器](flowchart-builder)）：

- **while**（`loopType: while`）每轮前检查 `condition`，为假时经 Done 离开。开启 `runOnceFirst` 时第一轮不检查（`started`），条件与上限从下一次进入页眉起生效。
- **for_each** 用 `Array()` 包装 `collection`，把 `itemVariable`／`indexVariable` 写入 `ctx`，逐项遍历全部条目。`skipWhen` 跳过当前项；被跳过的项同样推进下标。`collectInto` 把每个处理过（未跳过）的项追加到该 ctx 数组。
- `stopWhen`（两种类型均有）为真时经 Done 离开，在上限之后检查。
- **上限。** `maxIterations` 取 1–10,000，两种类型默认均为 100；空值或 0 按 100 处理，`LoopGenerator::MAX_LOOP_ITERATIONS` 把它封顶在 10,000。while 循环在跑满 `maxIterations` 轮后条件仍为真即失败。for_each 循环在下标达到 `maxIterations` 后仍有剩余项即失败（被跳过的项也计数）；长度恰好为 `maxIterations` 的集合正常结束。集合绝不会被截断。
- **到达上限即失败。** `FlowchartRuntime::Loop.fail_limit(ctx, key, max:, exports:)` 先离开循环（发布导出并删除状态键），再返回 `Step.fail(ctx, :loop_limit, max:)`。页眉步骤失败，`ctx[:errors]` 写入 `flowchart_runtime.errors.loop_limit`（「循环在完成 %{max} 次后仍未结束，本次运行已失败。」），运行沿失败轨道结束。条件为假、集合遍历完或 `stopWhen` 为真，则经 Done 正常离开。
- `ctx[:_loop_iteration_count]` 是最近运行的那个循环的已完成轮数（for_each 只计处理过的项）。它是一个共用的 ctx 键，不按循环重命名：`ActivityGenerator::ElementIoIndex::RUNTIME_PIN` 把它（以及 `_route_N` 键）排除在写入者输出之外，因此 `ConflictResolver` 从不给它加后缀。两个先后执行的循环结束后，它保存的是第二个循环的轮数；需要时在循环内读取，或在循环结束后立即复制。

循环区域内的读取走执行出处，循环内或循环后读到的是实际发生过的最近写入。无循环元素仍用 B2 的 `Outputs.latest`。生成源码引用 `FlowchartRuntime::`，不引用 `ActivityGenerator::`。

追踪三次 for_each 时，页眉与循环体各出现一次：`Start.default`、`repeat`、`work`、`repeat`、`work`、`repeat`、`work`、`repeat`、`after`、`End.success`。公开提交仍不追踪。

### 短信发送（send_sms）

`send_sms` 步骤动作取代了旧通知动作的短信通道。它读取 `templateKey`（平台短信模板引用）、`to`（默认 `model.phone`）、`vars`（字面量键 → 表达式值）及可选的 `idempotencyKey`，调用 `FlowchartRuntime::SmsDelivery.deliver(ctx, customer:, to:, template_key:, vars:, idempotency_key:)`。该辅助模块调用 `FlowchartRuntime::Sms.send_template`，后者委托 `Sms::Gateway.send`，与其他调用方共用模块门禁、号码归一、变量校验、抑制、限额及租户幂等策略。凭证和发送方配置从不来自步骤或请求。

```ruby
message = FlowchartRuntime::Sms.send_template(
  customer: customer,
  to: "+8613800138000",
  template_key: "verify_code",
  vars: { "code" => "1234" },
  idempotency_key: "verification-42"
)
```

成功时步骤把 `Sms::Message` 的 id 写入 `resultVar`（默认 `sms_message_id`）。接受不等于送达：返回的消息只要状态不是 `suppressed` 就走成功轨，步骤从不等待回执。失败经 `Step.fail` 使用 `send_sms.*` 代码：`suppressed`（`Sms::Errors::Suppressed`，或返回消息状态为 `suppressed`）、`quota`（`RateLimited`、`DailyCapExceeded`）、`credentials_missing`、`module_disabled`、`idempotency_conflict`、`marketing_ineligible`、`template_missing`、`api_error`、`invalid_number`／`template_missing`／`provider_code_missing`／`invalid_vars`（来自 `TemplateVarsInvalid`，按其消息文本匹配），其他 `Sms::Errors::Error` 一律为 `failed`。相同幂等键的真实重放返回同一行。

公开提交时，短信接收参与业务保存点；后续步骤失败或交接被拒绝，会回滚 queued 行且不入队投递。成功时，任务交接等待最外层提交，入队失败仍留下可由周期恢复处理的持久行。默认一小时到期；`send_sms` 没有到期字段。步骤内不调用厂商。

派发后，任务仅对带隔离条件的台账完成写入重试，语句／连接故障每次转换最多尝试三次，绝不重复厂商发送。结果不明的部分应答可保留已校验厂商 ID 及应答／审计哈希，供 unknown 查询或提前回执关联。对账宽限／最大年龄使用派发时间，历史行回退至接受／接收时间。这些后台事实不将已返回的工作流成功变为送达证明，应查看已记录消息及回执。投递时钟与完成写入约定见[短信](sms)。

短信结果、歧义及 `Sms::Errors` 不触发跨通道兜底。已接收消息或结果不明的外部尝试，不得导致另一通道再发通知。`send_sms` 字段及异步状态处理见[短信](sms)、[后台任务](background-jobs)和[流程图步骤动作](flowchart-step-actions)。

## 需要特别注意

### 路由审计：生效定义及子流程不变量

`Pages::PublicSubmission::RuntimeFlowchart` 固定 `resolved_current_version` 配置。共享覆盖经请求内 RuntimeGenerator 编译到匿名执行命名空间，不修改全局 `activity`、版本或头；普通全局／自有定义仍使用已存源码。运行子流程要求可访问且已上线，并分别使用其生效定义；缺失／下线／外租户子流程、循环或深度 32 均失败关闭。构建器编写不属于本次路由审计。

`ActivityTracer` 对直接执行应用同一包装器。未发布的所有者预览父流程使用 `RuntimeFlowchart.new(record, preview: true)` 保留已准备定义，子流程仍须租户可访问、已上线并使用生效版本。ActivityClassBuilder 的图表／结构检查是独立边界。`extended_model` 仅提供获准元数据，不授予基础记录写入；生成步骤创建／校验／保存 EntityEntry，旧路由／赋值／持久化辅助步骤拒绝基础输入及非 EntityEntry 的实际 ActiveRecord 目标。

业务执行及成功交接准备共用含 PasswordEffects 的 `requires_new` 保存点。追踪失败或交接拒绝时，新增／更新及调用状态一起回滚。Warden 认证仍限单次请求，上下文用户 ID 仅为元数据。见[页面渲染](page-rendering)、[模块框架](module-framework)、[共享资源](shared-resources)。

`ActivitySteps::SaveAll.call(ctx, **)` 同样以新保存点包住主 EntityEntry 及桥接记录保存。基础模型目标被拒绝或 Reform 的 `save` 返回 false 时，返回失败；后续桥接校验失败会回滚主记录及已保存的桥接记录。调用方须以位置哈希传入 `ctx`。运行子流程查找测试使用真实 RuntimeFlowchart 包装器，不在验证型替身上声明不存在的方法。嵌套循环校验断言本地化的 `code_generator_validation.loop_topology.nested_loop` 消息。

:::note
2026-10-11 的定向运行验证通过 28 个文件、508 个用例，包含租户／全局覆盖执行、所有者预览、已上线子流程可访问性、真实 SaveAll 持久化／回滚及公开提交交接失败。专用数据库为 `storage/runtime_final_verify.sqlite3`；完整命令及结果见 `docs/audits/2026-10-11-rspec-verification.md` 和 `/tmp/opencode/runtime_final_verify.log`。
:::

:::attention
`flowchart.name` 为空白或 `elements` 为空时，`ActivityGenerator#generate` 返回 nil；不属于循环拓扑或不支持元素的结构验证失败时，同样返回 nil。`Flowchart#generate_activity` 会把这个 nil 赋进去，从而清空 `activity`。随后 `Pages::PublicSubmission#validation_error` 因 `@flowchart.activity.blank?` 拒绝提交。
:::

:::attention
覆盖保存不改全局编译源码。公开提交将 RuntimeFlowchart 传给 ActivityTracer，可执行源码及追踪标签均跟随生效覆盖，不再为该覆盖执行全局类。
:::

:::attention
`ActivityClassBuilder#build_activity_class` 把 `flowchart.entity` 传给 `DynamicClassLoader`。共享流程图不能存储 `entity_id`，加载器因此定义 `BlueprintEntity`。持久化步骤使用 `ctx[:bound_entity]`，`Pages::PublicSubmission#build_context` 把它设为页面的实体。这些步骤调用的工厂是 `EntityEntry.build_for`。
:::

:::attention
`FlowchartRuntime::Invocable` 拒绝任意 `const_get`。`method!` 只允许 `app/` 下由应用定义的方法，并拒绝 ActiveRecord 类与破坏性方法。`InvokeServiceGenerator` 在编写期做同样检查。`SERVICE_NAMESPACES` 列出 `Sms`、`Emails`、`Payments`、`Captcha`、`FeatureModules`、`Member` 与 `Billing`。页面交接是活动成功之后，`PublicPagesController#start_page_handoff` 里的 `FeatureModules::Invocation.begin!`。
:::

:::attention
`ActivityTracer#call` 让每次运行的 `params` 都是 indifferent-access。决策／循环的 `> >= < <=` 比较走 `ConditionInput.compare`，非有限数字视为非数字。`authorize` 检查 `Authentication::User` 或会话封装，从不信任载入的用户 Hash；`send_template_email` 读 `ctx[:customer_id]`。
:::

:::attention
流程图运行时从不调用 `People::Ownership.scope`。不带 `scope:` 的 `QueryBuilder.for_entity` 仍返回本租户全部行。名额或重复检查若使用会员行范围，会少计。可信人员身份来自 `ctx[:current_person_ids]`，经 `find_current_person` 读取，从不来自 params。注册身份来自 `ctx[:identity]`，不在 `ctx[:params]`。
:::

:::attention
不要按 `registration.status` 分支流程图。`created` 与 `existing` 共用同一条 `registration_pending` 闪讯，访客无法据此判断邮箱是否已有账号。
:::

:::attention
上线时的输入输出检查从 `config/flowchart_validation.yml`（`implicit_context_keys`）读取隐式键，而不是 `ConfigSchema::SEEDED_KEYS`。该列表包含 `SEEDED_KEYS` 的全部条目，外加 `current_user`（可选：为 nil 时 `authorize` 回退到会话用户）与 `current_customer`。两份列表须保持一致：保留默认值的 `audit_log` 步骤（`ipAddress: request_ip`、`userAgent: user_agent`）能通过上线检查，正是因为列出了 `request_ip` 与 `user_agent`。
:::

:::attention
`Step.attempt` 只救援生成器列出的类。意外异常仍会逃出步骤；`ActivityTracer` 把它变成通用的 `execution_failed` 结果，公开 flash 显示 `common.errors.dynamic.activity_execution_failed`。异常消息只进入 `error_details[].diagnostic` 与日志，从不进入 flash。
:::

:::attention
`ActivityTracer` 在 `EXECUTION_TIMEOUT_SECONDS`（10）处中止，并为 HTTP 辅助模块设置同一个 `RunContext` 期限。`Pages::PublicSubmission#execute_activity` 在 `Authentication::PasswordEffects.transaction` 内调用 `ActivityTracer#call(ctx, trace: false)`，`trace.success?` 为假或关联行未保存时抛出 `ActiveRecord::Rollback`。

关联行由运行时写入，而非生成的步骤。运行成功、且 `ctx[:model]` 是本次提交新建的页面实体 `EntityEntry`（`previously_new_record?`）时，`Pages::BridgeEntries` 在同一保存点内为每个关联分区写入一行。关联实体从页面实体的 `associations_list` 中按关联实体 id 或 `SectionSlug` 解析，范围限于本租户与共享实体。所有目标引用（指向其他实体的关联 `EntityReference`）都为空时跳过该分区。`EntityEntryContract` 会校验每个目标引用：每个 ID 都必须是本客户中目标实体的记录，否则该行以 `common.errors.dynamic.association_target_missing` 失败，整个提交回滚。指回主条目的引用以 ID 字符串保存，从不读取提交值。该行用 `EntityEntryContract.build_for(bridge, audience:, writable_slugs:)` 校验。任何拒绝都会返回对应消息，回滚主记录与交接，并以这些消息记为 `:failed`。更新类流程图的既有记录不新增关联行。失败轨上若已收集 `ctx[:errors]`，flash 使用这些消息；抛出或列表为空时使用通用的 Activity 失败文案。`FlowchartRuntime::Authentication.from_request` 读取 Warden 的用户，并且只在本次请求内有效。上下文里的 `current_user_id` 是元数据。
:::

## 关键代码

```ruby
# app/contracts/entity_entry_contract.rb
    def schema_property_options(attr, writable_slugs: nil)
      derived = %w[Calculated Computed].include?(attr["type"]) || attr["storage"] == "computed"
      excluded = writable_slugs && !writable_slugs.include?(attr["name_slug"].to_s)
      # Reform 2.6 uses :writeable for model sync and :parse for deserialization.
      derived || excluded ? { writeable: false, parse: false } : {}
    end
```

```ruby
# app/services/activity_generator.rb
  def generate
    return nil if flowchart.name.blank? || elements.empty?
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
# app/services/pages/public_submission.rb
          trace = ActivityTracer.new(@flowchart).call(ctx, trace: false)
```

```ruby
# app/services/activity_tracer.rb
    if trace
      execute_with_trace(activity_class, input)
    else
      execute_without_trace(activity_class, input)
    end
```

```ruby
# app/services/activity_tracer.rb
          Trailblazer::Developer::Trace.invoke(
            activity_class,
            [input, { stack: stack }]
          )
```

```ruby
# app/services/pages/public_submission.rb
    def build_context
      prepare_input unless defined?(@guard_result)
      # The boundary-supplied authentication object is the session credential.
      # current_user_id/current_user_role remain metadata, never proof of login.
      # current_person_ids is the same-tenant viewer's linked person entries only.
      {
        params:             @primary,
        association_params: @bridge_sections.presence,
        bound_entity:       @entity,
        customer_id:        @customer_id,
        authentication:     @authentication,
        current_user_id:    @current_user&.id,
        current_user_role:  @current_user&.primary_role_key,
        audience:           audience,
        device_type:        Pages::DeviceType.call(@user_agent),
        current_person_ids: current_person_ids,
        identity:           @identity || {}
      }.compact.merge(
        request_ip: Current.ip_address,
        user_agent: @user_agent,
        locale: I18n.locale.to_s,
        request_id: Current.request_id,
        continuation: verified_continuation
      )
    end
```

```ruby
# app/services/flowchart_runtime/step.rb
    def fail(ctx, code, field: nil, **details)
      raise Error, "error code is required" if code.to_s.strip.empty?

      append(
        ctx,
        I18n.t("flowchart_runtime.errors.#{code}", **details),
        code,
        field,
        details
      )
      false
    end
```

```ruby
# app/controllers/public_pages_controller.rb
  def start_submission_handoff(entry, outcome)
    if payment_handoff?(outcome)
      start_payment_handoff(entry, outcome)
    elsif @page.handoff?
      start_page_handoff(entry)
    end
  end

  def complete_submission(handoff_url, result)
    return redirect_to(handoff_url) if handoff_url

    outcome = result.submission_outcome || {}
    path = outcome_page_path(outcome) || post_submit_path
    type, text = outcome_flash(outcome)
    redirect_to path, type => text
  end
```

```ruby
# app/services/flowchart_runtime/errors.rb
    def collect(ctx)
      existing = Array(ctx[:errors]).map { |message| message.to_s }.reject(&:empty?)
      extras = ctx.each_with_object([]) do |(key, value), messages|
        next if key == :errors
        next unless value.respond_to?(:errors)

        errors = value.errors
        next unless errors.respond_to?(:full_messages)

        messages.concat(Array(errors.full_messages).map { |message| message.to_s })
      end
      (existing + extras).uniq
    end
```

```ruby
# app/services/flowchart_runtime/outputs.rb
    def latest(ctx, *keys)
      keys.each do |key|
        return ctx[key] if ctx.key?(key)
      end
      nil
    end

    def view(ctx, pin, *keys)
      pin = pin.to_sym
      keys.each do |key|
        return { pin => ctx[key] } if ctx.key?(key)
      end
      {}
    end
```

```ruby
# app/services/concerns/activity_class_builder.rb
    namespace.module_eval(activity_code)

    # Find the NEWLY defined activity class (not pre-existing subflow classes)
    new_constants = namespace.constants - existing_constants.to_a
    new_constants
      .map { |c| namespace.const_get(c) }
      .find { |k| trailblazer_activity?(k) }
```

```ruby
# app/services/flowchart_runtime/entries.rb
    def scope(ctx)
      entity = ctx[:bound_entity]
      return EntityEntry.none unless entity

      EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)
    end
```

```ruby
# app/services/flowchart_runtime/condition_input.rb
    def compare(left, operator, right)
      op = operator.to_s
      unless %w[> >= < <=].include?(op)
        raise ArgumentError, "unsupported comparison operator: #{op.inspect}"
      end
```

```ruby
# app/services/dynamic_class_loader.rb
  def load_into(namespace)
    if entity.present?
      build_entity_model(namespace)
      build_entity_contract(namespace)
    else
      build_blueprint_model(namespace)
      build_blueprint_contract(namespace)
    end
```

```ruby
# app/services/code_generators/element_types/process/model_operations/new_model_generator.rb
              assign(:resultVar, "FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")
```
