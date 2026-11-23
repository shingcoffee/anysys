---
title: "操作 API"
summary: "助手以工具方式调用的版本化、自描述契约操作（实体、业务域、流程、表单处理与后台子系统构建）：注册表与 DSL、契约约定、违规项、结果、确认、幂等及审计表。"
---

## 概要

操作是一个具名、带版本、公开输入契约的工作单元：`app/services/operations/<key>.rb` 中 `Operations::Base` 的子类，配一份 JSON Schema 2020-12 文件 `app/services/operations/schemas/<key>.json`。调用方把键、输入哈希和 `Operations::Context` 交给 `Operations::Activities::Execute`，得到一个 `Operations::Outcome`。所有调用方走同一条流水线。`Operations::Context::CHANNELS` 列出 `assistant`、`api`、`system`，但目前只有 AI 助手调用操作，尚无 HTTP 端点。

已注册八个操作。其中三个面向实体结构：`create_entity` 立即生效，`update_entity` 一律等待管理员批准，`get_entity` 只读，它们取代了助手原先的自由格式实体文档。另外五个围绕这些实体补全子系统，均立即生效：`create_domain`、`list_journey_options`（只读）、`generate_journeys`、`set_page_processing`、`start_subsystem_build`（见下文《业务域、流程、页面与构建操作》）。存储模型见[实体构建器](entity-builder)，对话流程见 [AI 助手](ai-assistant)。

设计沿用业界把能力作为工具交给语言模型的通行做法：

| 阶段 | 通行做法 | Anysys |
| --- | --- | --- |
| 契约 | 每个工具一份 JSON Schema（MCP `inputSchema`、函数调用 `parameters`）；`verb_noun` 命名 | `schemas/<key>.json`，由 `Operations::Schema` 解析；键如 `update_entity` |
| 描述 | 每个属性、每个枚举值都有说明，契约就是模型的使用手册 | `description`、`x-enum-descriptions` 及源自注册表的 `x-vocabulary`，由 `Operations::SchemaLint` 强制 |
| 校验 | 先结构后语义；错误以 RFC 6901 JSON Pointer 指向输入 | 先 `json_schemer`，再走操作的 `validate`；每条失败都是一个 `Operations::Violation` |
| 执行 | 领域写入之前设防腐映射，单一事务 | `perform` 在客户锁内调用 `EntityDefinitions::Api::Mapper` 与 `EntityDefinitions::Persist` |
| 调用 | 原生工具调用；破坏性动作须人工批准（MCP `destructiveHint`） | `AiAssistant::Assistant::Tools::OperationTool`、JSON 回退约定，以及 `confirmation: :always` 配合 `Operations::Activities::Confirm` |
| 分诊 | 机器可读的错误附建议的下一步；RFC 9457 问题详情 | `resolution`、`next_step`、`attempts_remaining`；`Outcome#to_problem` |

每次调用都限定在 `context.customer`。`Operations::Authorization.allowed?` 只放行有效的平台所有者，或该客户的有效 `admin`；成员一律拒绝。实体操作只读写客户自有、有效、非桥接的实体。

## 流程

```text
调用方（助手工具调用；api 与 system 通道预留）
        |  Operations::Context：customer、actor、channel、conversation、
        |  generation、idempotency_key、dry_run、confirmed、around_write
        v
Operations::Activities::Execute.call(operation:, input:, context:)
        |  resolve             Operations.for(key)          -> invalid   operation.unknown
        |  authorize           Authorization + available?   -> forbidden permission.denied
        |  replay              幂等键 + 输入摘要            -> 存储的结果 | invalid idempotency.key_reused
        |  validate_schema     JSON Schema（按需补默认值）  -> invalid   schema.*
        |  validate_semantics  #validate                    -> invalid   entity.*、attribute.* 等
        |  plan_and_snapshot   #plan、#snapshot
        |  gate                dry_run                      -> dry_run（只返回方案）
        |                      confirmation :always         -> confirmation_required（记录挂起）
        |  perform             around_write { customer.with_lock(requires_new: true) { #perform } }
        |  record!             写入 operation_invocations
        v
Operations::Outcome -> #to_tool_payload（模型）/ #to_problem（RFC 9457）

管理员批准（助手：点「应用更改」或只回复「确认」）
        v
Operations::Activities::Confirm.call(invocation:, context:)
        |  require_pending -> resolve（同一版本）-> authorize
        |  revalidate：契约 -> stale?(snapshot) ? conflict -> #validate（confirmed）-> conflict.* ? conflict : invalid
        |  apply：客户锁 { stale?(snapshot) ? conflict : #perform }
        v
挂起记录收尾：status、result、violations、confirmed_by_id、confirmed_at
```

## 实现

### 注册表与 DSL

`Operations`（`app/services/operations.rb`）扩展 `PluginRegistry.build(label: "operation", dir: "app/services/operations", defaults: false)`。`ensure_loaded!` 对 `app/services/operations/*.rb` 中除 `base.rb` 外的每个文件执行 constantize；`outcome.rb` 等框架文件会加载，但不注册。`Operations.for(key)` 返回操作类，键未知时抛出 `ArgumentError`。`Operations.keys` 与 `Operations.all` 列出已注册的操作。助手按 `Operations.all` 组装工具列表，新增操作无需改动助手。

`Operations::Base` 的类级 DSL：

| DSL | 含义 |
| --- | --- |
| `key "update_entity"` | 工具名兼审计键。须匹配 `/\A[a-z][a-z0-9_]{2,63}\z/`，采用 `verb_noun`。 |
| `version 1` | 契约版本，默认 1。写入契约 `$id`，并随每次调用保存。提案挂起时的版本与当前不同，`Confirm` 即拒绝（`operation.version_changed`）。 |
| `title "Update entity"` | 给人看的简短标题，`SchemaLint` 要求必填。 |
| `summary "…"` | 模型读到的工具说明。写明何时使用、不做什么。 |
| `schema "update_entity.json"` | 输入契约，位于 `app/services/operations/schemas/`；`schema_root` 可改目录。 |
| `shared_defs "entity.defs.json"` | 先合并这些文件的 `$defs`，操作自身的 `$defs` 优先。 |
| `vocabulary EntityDefinitions::Api::Vocabulary` | 解析 `x-vocabulary` 与 `x-vocabulary-max` 槽位。 |
| `insert_defaults false` | 校验时不向输入补齐契约默认值；默认开启（`insert_defaults?`）。`update_entity` 声明了它：其输入携带合并补丁，补进去的默认值会覆盖已存储的值。 |
| `annotations destructive: true, confirmation: :always` | `read_only`、`destructive`、`idempotent` 提示，以及 `confirmation`（`:never` 或 `:always`）。 |
| `register!` | 把类加入注册表。 |
| `available?(context)` | 类方法，默认 `true`。返回 `false` 时助手看不到该工具，`Execute` 返回 `forbidden`。 |

实例钩子运行时已设置 `context`，收到的是**规范化后**的输入；除非操作声明了 `insert_defaults false`，契约默认值已补齐：

| 钩子 | 默认 | 约定 |
| --- | --- | --- |
| `validate(input)` | `[]` | 返回 `Operations::Violation` 数组，覆盖跨字段、引用、策略与配额规则。 |
| `plan(input)` | `nil` | 可审阅的方案，随 `dry_run` 与 `confirmation_required` 返回。 |
| `snapshot(input)` | `nil` | 保存在挂起记录上的版本锚点。 |
| `stale?(snapshot)` | `false` | 目标在 `snapshot` 之后有变动时为 `true`，由 `Confirm` 在锁内检查。 |
| `perform(input)` | 抛出 `NotImplementedError` | 经领域服务写入，返回 `Operations::Outcome`。 |

在 `Execute` 中，`read_only` 跳过幂等重放与审计记录，`confirmation: :always` 让每次未确认的调用挂起。`destructive` 与 `idempotent` 仅作提示记录，目前没有代码据此分支。

### 契约约定

`Operations::Schema#document` 读取操作的契约文件，合并共享 `$defs`，解析词表槽位，再把 `$id` 设为 `urn:anysys:operation:<key>:v<version>`，`$schema` 设为 `https://json-schema.org/draft/2020-12/schema`。只缓存解析后的 JSON 文件，以路径加 mtime 为键（`Schema.parsed_files`，`reset_cache!` 清空）；槽位每次调用都重新解析，因此修改契约文件无需重启即生效。`#validate(input)` 运行 `json_schemer` 时，`insert_property_defaults` 取操作的 `insert_defaults?`，返回 `[violations, normalized]`。因此 `create_entity` 的钩子收到的输入已带 `kind: "input"`、`html_type: "text"`、分组 `icon: "folder"` 等创建类默认值；`update_entity` 声明了 `insert_defaults false`，补丁按原样送达。

源自注册表的列表从不写进 JSON。槽位只写列表名，每次解析契约时由 `vocabulary.resolve(name, context)` 填入：

- `"x-vocabulary": "<slot>"` 变为 `enum` 加 `x-enum-descriptions`；可空类型（如 `["string", "null"]`）另追加 `null`。`extends` 可空，没有可扩展模型的租户得到 `"enum": [null]`，`null` 表示不继承基础模型。
- `"x-vocabulary-max": "<slot>"` 变为 `maximum`，槽位须解析为整数。
- 未知槽位抛出 `ArgumentError`。

`EntityDefinitions::Api::Vocabulary` 提供实体槽位：

| 槽位 | 取值 | 来源 |
| --- | --- | --- |
| `html_types` | 21 种控件，从 `text` 到 `color` | `HtmlTypeOptions::GROUPED_HTML_TYPES` |
| `selection_html_types` | `select`、`radio`、`checkbox` | `HtmlTypeOptions::SELECTION_TYPES` |
| `attribute_kinds` | `input`、`calculated`、`computed` | `Vocabulary::ATTRIBUTE_KINDS` |
| `rule_types` | 19 种规则，从 `presence` 到 `acceptance` | `ValidatorRegistry::VALIDATOR_LABELS` |
| `rule_types_single_value`、`rule_types_range`、`rule_types_pattern`、`rule_types_list` | 分别 8、1、1、2 种规则 | `ValidatorRegistry::VALIDATOR_CONFIG_TYPES` |
| `group_icons`、`group_colors` | 12 个图标、8 个颜色标记 | `EntityAttributeGroupOptions` |
| `option_sources` | `static`、`constant`、`entity_entries` | `Vocabulary::OPTION_SOURCES` |
| `aggregate_functions`、`filter_operators` | `avg sum count min max`；`= != > >= < <=` | `Entities::ComputedCompiler` |
| `aggregate_directions` | `source`、`target` | `Vocabulary::AGGREGATE_DIRECTIONS` |
| `extendable_models` | 按租户而定 | `ExtendableModelRegistry.for_customer` |
| `aggregate_max_precision`（`x-vocabulary-max`） | 6 | `Entities::ComputedCompiler::MAX_PRECISION` |

`rule.type` 使用 `"x-vocabulary": "rule_types"`，列出全部规则类型。每条说明按「含义、取哪些值字段、允许用于哪些控件」生成，`presence` 这类规则以「every html_type」结尾。模型读到的 `length_maximum` 说明为：「Requires the text to be at most the given length, takes `value`, and is allowed on text, textarea, search, password, email, tel, and url.」语义校验器把超出控件允许范围的规则报为 `rule.not_allowed`，并附 `allowed`。

标题、摘要与描述是面向模型的 API 文档，保持英文。它们不是界面文案，不做翻译；违规项消息则走 I18n。

**投影。**`tool_definition(context)` 返回 `{name:, description: summary, parameters:}`，其中 `parameters` 为 `Operations::SchemaProjection.call(document)`。各厂商的工具方言对 `$ref`、`if`/`then`、`allOf` 的支持不一，因此模型拿到的是扁平、保守的副本，服务端仍按完整契约校验。投影会：

- 内联所有 `#/$defs/...` 的 `$ref`；`$ref` 旁的键（如 `description`）覆盖目标的同名键；
- 删除 `$schema`、`$id`、`$defs`、`$comment`、`examples` 及所有 `x-*` 键；
- 把枚举说明（去掉句末句点）追加到描述末尾，例如 ``Allowed values: `input` — A stored field the user fills in on the form; `calculated` — …``；
- 合并无条件的 `allOf` 项；把有条件的 `allOf` 项、`if`/`then`/`else`、`not`、`dependentRequired` 的描述并入父级描述后删除；
- 把 `oneOf` 改名为 `anyOf`；
- 超过 `DEFAULT_BUDGET`（JSON 32,000 字节）时抛出 `SchemaProjection::TooLarge`。实体写入工具已接近上限：`create_entity` 约 25 KB，`update_entity` 约 26.5 KB；`get_entity` 约 0.5 KB。

**契约检查。**`Operations::SchemaLint.call(operation_class, context)` 返回问题列表；`spec/services/operations/contract_lint_spec.rb` 要求每个已注册操作的列表为空。检查项：

- `title`、`summary` 与根 `description` 齐全；
- 每个文档位置都有 `description`：根节点，`properties`、`patternProperties`、`$defs`、`dependentSchemas` 下的每一项，以及数组的 `items` 与 `prefixItems`。`allOf`、`anyOf`、`oneOf` 的分支沿用父级描述；
- 除 `null` 外，每个 `enum` 值都有 `x-enum-descriptions` 条目；
- 每个有条件的 `allOf` 项都有 `description`；
- 每个对象契约都声明 `additionalProperties: false`，`then`、`else` 分支本身除外；
- 根 `examples` 的每一项都能通过校验；
- 投影不超预算。

### 违规项

`Operations::Violation` 有四个字段：

- `pointer`：指向输入的 RFC 6901 JSON Pointer，由 `Operations::Pointer.join` 生成（`~`、`/` 分别转义为 `~0`、`~1`），如 `/updates/0/changes/2/slug`。在变更后文档上发现的语义违规项，指向引入该项的那条变更。
- `code`：稳定的点分标识，如 `schema.enum`、`entity.not_found`、`conflict.version_changed`。
- `details`：插值变量与机器提示，如 `allowed`、`candidates`（最多三条 `DidYouMean` 建议）、`expected`、`property`。
- `resolution`：告诉调用方下一步怎么做（见下表）。

`Violation#message` 为 `I18n.t("operations.violations.<code>")`，以 `details` 插值，缺键时回退到 `operations.violations.generic`。任何代码只要 `details["candidates"]` 非空，都会追加 `operations.violations.did_you_mean`（「你是否指：%{candidates}？」），因此 `schema.unknown_property` 显示为「未知属性。」或「未知属性。你是否指：color？」。框架消息位于 `config/locales/operations.{en,zh-CN}.yml`，实体消息位于 `config/locales/operations_entity.{en,zh-CN}.yml`，流程、表单处理与构建消息分别位于 `operations_journey`、`operations_page`、`operations_subsystem`（`.{en,zh-CN}.yml`）。调用方收到的是 `as_json`：

```json
{
  "pointer": "/entities/0/attributes/0/html_type",
  "code": "schema.enum",
  "message": "Value must be one of: text, textarea, search, password, hidden, select, radio, checkbox, number, range, date, time, datetime-local, month, week, email, tel, url, file, image, color.",
  "resolution": "fix_payload",
  "allowed": ["text", "textarea", "search", "password", "hidden", "select", "radio", "checkbox", "number", "range", "date", "time", "datetime-local", "month", "week", "email", "tel", "url", "file", "image", "color"]
}
```

| 处理方式 | 下一步 | 默认用于 | 另行指定于 |
| --- | --- | --- | --- |
| `fix_payload` | 自行修正调用后重试，不打扰用户 | 其余各行未列出的所有代码，含 `schema.*` | 有候选时的 `entity.not_found`、`attribute.not_found`、`group.not_found`、`association.not_found` |
| `ask_user` | 在一轮内向用户提问，每项一个问题（助手以问题卡片呈现） | — | `entity.name_in_trash`；无候选时的上述四个 `not_found` 代码 |
| `refresh` | 用 `get_entity` 重新读取目标，再重建调用 | `conflict.*` | — |
| `blocked` | 说明原因后停止，不要重试 | `permission.*`、`quota.*` | `entity.not_editable`、`attempts.exhausted`、`proposal.already_pending` |

契约错误按关键字映射：

- `required` 变为 `schema.required`，指针延伸到缺失的属性，`details` 含 `property`；
- `enum` 与 `const` 变为 `schema.enum`，附 `allowed`；
- `type` 变为 `schema.type`，附 `expected`；
- `additionalProperties: false` 变为 `schema.unknown_property`，`candidates` 取自同级属性名；
- `pattern`、`format`、`minLength`、`maxLength`、`minItems`、`maxItems`、`minimum`、`maximum`、`uniqueItems`、`minProperties`、`maxProperties` 变为 `schema.<关键字的 snake_case 形式>`，附 `expected`；
- 其余变为 `schema.invalid`。

经 `allOf`、`if`、`then` 包裹报出的错误只保留最深层的具体错误；按指针与代码去重，上限为 `Operations::Schema::MAX_VIOLATIONS`（25）。语义校验器采用同一上限。

### 结果与工具载荷

| 状态 | `ok?` | HTTP | 载荷键 | 产生条件 |
| --- | --- | --- | --- | --- |
| `succeeded` | 是 | 200 | `data` | `perform` 成功 |
| `confirmation_required` | 是 | 202 | `plan` | `confirmation: :always` 且尚未确认；记录已挂起 |
| `dry_run` | 是 | 200 | `plan` | `context.dry_run` 为真；不写入任何数据 |
| `invalid` | 否 | 422 | `errors` | 未知操作、键被复用、契约或语义违规、`domain.invalid` |
| `conflict` | 否 | 409 | `errors` | `Confirm` 发现 `stale?` 为真，或重新校验报出 `conflict.*` 代码 |
| `forbidden` | 否 | 403 | `errors` | `Authorization` 或 `available?` 拒绝 |
| `failed` | 否 | 500 | `errors` | 意外异常（`internal.error`） |

`Outcome#to_tool_payload(attempts_remaining:)` 是返回给模型的 JSON（节选）：

```json
{
  "ok": false,
  "status": "invalid",
  "operation": "create_entity",
  "errors": [
    {
      "pointer": "/entities/0/attributes/0/html_type",
      "code": "schema.enum",
      "message": "Value must be one of: text, textarea, search, …",
      "resolution": "fix_payload",
      "allowed": ["text", "textarea", "search", "…"]
    }
  ],
  "attempts_remaining": 2,
  "next_step": "Correct the fix_payload items and call create_entity again; do not mention them to the user. Attempts remaining: 2."
}
```

`next_step` 取自 `operations.guidance.*`。`invalid` 时按每种不同的处理方式各拼接一句（`guidance.fix_payload`、`guidance.ask_user` 等），一种都没有则回退到 `guidance.invalid`；传入尝试次数时再追加 `guidance.attempts_remaining`。其他状态使用 `guidance.<status>`。`%{operation}` 插入各句，`%{attempts}` 只插入尝试次数一句。

`Outcome#to_problem` 把同一结果渲染为 RFC 9457 问题文档，供将来的 HTTP 通道使用：`type`（`urn:anysys:problem:<status>`）、`title`（`operations.problems.<status>`）、`status`（HTTP 状态码）、`detail`（`next_step` 文本，不含尝试次数一句）、`operation` 与 `errors`。目前没有控制器输出它。

### Execute、Confirm 与审计表

`Operations::Activities::Execute` 是 `Trailblazer::Activity::Railway`。某一步失败时写入结果并离开轨道；`record!` 总在最后运行。

1. `resolve` 查找 `Operations.for(key)`，也接受直接传入类。键未知时返回 `invalid`，代码 `operation.unknown`，附 `available`。
2. `authorize` 要求 `Authorization.allowed?(actor:, customer:)` 与 `available?(context)` 同时成立，否则返回 `forbidden`，代码 `permission.denied`。
3. `replay` 处理幂等（见下文）；只读操作与空键跳过此步。
4. `validate_schema` 运行 `input_schema(context).validate(input)`。
5. `validate_semantics` 运行操作的 `validate(normalized)`。
6. `plan_and_snapshot` 保存 `plan(normalized)` 与 `snapshot(normalized)`。
7. `gate`：`dry_run` 时返回方案；`confirmation: :always` 且 `context.confirmed` 为假时，创建 `awaiting_confirmation` 记录并返回 `confirmation_required`。
8. `perform` 调用 `Execute.perform_atomically`。

**幂等。**设置了 `context.idempotency_key` 时，`replay` 执行 `OperationInvocation.find_by(customer_id:, idempotency_key:)`。存储的 `input_digest`（输入按键递归排序后所得 JSON 的 SHA-256）一致时，原样返回存储的结果，`replayed: true`，不写入；摘要不同则返回 `invalid`，代码 `idempotency.key_reused`。只有成功或挂起的记录保留幂等键（`Execute.replayable?`）；被拒绝或失败的调用以空键记录，同样的调用之后会再次执行，例如所缺的实体建好之后。唯一索引 `idx_operation_invocations_idempotency`（`(customer_id, idempotency_key)`）为此兜底；两次重叠的同键调用都通过查找时，`create_audit!` 为后一次记录空键，而不是抛出 `RecordNotUnique`。助手使用 `gen-<generation id>-<operation key>-<input digest>`，回复任务重试也不会重复写入。

**乐观并发。**`update_entity` 有两道检查：

- `expected_version` 即 `get_entity` 返回的 `version`（`display_current_version.version_number`）。`validate` 将其与线上版本比较，不一致时在 `/updates/<i>/expected_version` 报出，附 `expected` 与 `got`。这只在提案时检查：批准时 `validate` 带着 `context.confirmed` 运行并跳过此项，因为下面的快照检查更严格。该字段可省略。
- `snapshot` 在挂起记录上保存 `{entity name => current_line_head_version_id}`。`Confirm` 在重新校验前调用一次 `stale?`，并在客户锁内、紧挨 `perform` 之前再调用一次；任一头版本有变动即返回 `conflict`，代码 `conflict.version_changed`。

**原子性。**`Execute.perform_atomically` 先运行 `context.around_write`（助手传入 `GenerationWriteGuard.wrap(write_guard)`），在其中获取 `context.customer.with_lock(requires_new: true)`，设置 `Current.with_customer` 后运行 `perform`。`rescue_into_outcome` 把 `ActiveRecord::RecordInvalid` 转为 `invalid`（代码 `domain.invalid`，`details` 含 `errors`），把其他 `StandardError` 记录日志后转为 `failed`（代码 `internal.error`）。结果不成功时抛出 `ActiveRecord::Rollback`，部分写入绝不提交。`Confirm#apply` 复用同一方法。此前各步（契约校验、`validate`、`plan`、`snapshot`）在 `Execute.guarded` 中运行，`StandardError` 记录日志后转为 `failed`（代码 `internal.error`）。

**确认。**`Operations::Activities::Confirm.call(invocation:, context:)` 分五步：

1. `require_pending`：记录处于 `awaiting_confirmation`、属于 `context.customer`，且若挂起于某个对话，须从该对话批准；否则返回 `invalid`，代码 `proposal.not_pending`。
2. `resolve`：操作类仍存在（`operation.unknown`），且版本与挂起时的 `operation_version` 相同（`operation.version_changed`）。
3. `authorize`：同 `Execute`，针对批准人。
4. `revalidate`：先对存储的输入重跑契约，再调用 `stale?(invocation.snapshot)`，最后以 `confirmed: true` 运行 `validate`。契约失败时记录以 `invalid` 收尾。目标已变动时在 `validate` 之前即以 `conflict` 收尾，因此因目标变动而无法再应用的挂起变更（如要删除的属性已不存在）属于 `conflict`，而非 `invalid`。语义失败时，只要有代码以 `conflict.` 开头即以 `conflict` 收尾，否则以 `invalid` 收尾。
5. `apply`：以 `confirmed: true` 调用 `perform_atomically`。锁内 `stale?(invocation.snapshot)` 为真则返回 `conflict`，否则运行 `perform`。

挂起记录最终写入 `status`、`result`、`violations`、`confirmed_by_id` 与 `confirmed_at`。新提案取代旧提案时，`Confirm.supersede!(invocation)` 把旧记录标为 `superseded`。管理员放弃方案时，`Confirm.decline!(invocation, actor:)` 把记录标为 `declined`，并写入 `confirmed_by_id` 与 `confirmed_at`。

**审计表。**`OperationInvocation`（`operation_invocations`，`TenantScoped`）每条已记录的调用占一行：

| 列 | 内容 |
| --- | --- |
| `customer_id`、`user_id` | 租户与执行用户 |
| `operation`、`operation_version`、`channel` | 执行了什么、依据哪版契约、来自哪个通道 |
| `status` | `awaiting_confirmation`、`succeeded`、`invalid`、`conflict`、`forbidden`、`failed`、`superseded` 或 `declined` |
| `idempotency_key`、`input_digest` | 重放身份；只有成功或挂起的记录保留幂等键 |
| `input`、`plan`、`snapshot` | 规范化输入、可审阅方案、版本锚点 |
| `result`、`violations` | `Outcome#as_stored_result` 与违规项列表 |
| `conversation_id`、`generation_id` | 助手来源，不设外键 |
| `confirmed_by_id`、`confirmed_at` | 挂起提案的定局者（批准或放弃）及时间 |
| `duration_ms` | `Execute` 耗时 |

除幂等索引外，还有 `idx_operation_invocations_directory`（`(customer_id, operation, created_at)`），以及 `conversation_id`、`generation_id` 上的索引。目前没有页面展示这张表。

### 实体操作

实体操作使用一套公开词汇。`EntityDefinitions::Api::Mapper` 是它与存储定义（表单和运行时读取的格式）之间的防腐层，模型因此接触不到 `property_schema`、`validators`、`bridge_entity_id`。

| 公开字段 | 存储定义 |
| --- | --- |
| `name`、`display_label`、`description` | `Entity` 上的同名列 |
| `extends`（类名，或 `null` 表示无） | `extended_model` |
| `settings.icon`、`settings.color`、`settings.default_values` | `icon`、`color`、`default_properties` |
| `attribute_groups[].key` | `attribute_groups[].id` |
| `attributes[]` | `property_schema[]` |
| `slug` | `name_slug`；省略时由 `name` 经 `parameterize(separator: "_")` 生成，此后不可变 |
| `group` | `group_id` |
| `kind: "input"` | 不写 `type` |
| `kind: "calculated"` 加 `formula` | `type: "Calculated"`、`formula`、`readonly: true`、`storage: "computed"` |
| `kind: "computed"` 加 `aggregate` | `type: "Computed"`、`html_type: "number"`、`readonly: true`、`storage: "computed"` 及 `config` |
| `aggregate.related_entity`、`source_attribute`、`direction`、`filter` | `config.target_entity_name`、`source_slug`、`bridge_role`、`filter`（`attribute`、`operator` 改为 `slug`、`op`） |
| `rules[]`：`type` 加 `value`、`min`/`max`、`pattern` 或 `values` | `validators[]`：`type` 加 `config` |
| `access.visible_to`、`access.rules_apply_to` | `visibility`、`validator_apply`（存为与 `visibility` 的交集）；新属性未给 `access` 时各开关均为 `true` |
| `options`：`source: "static"` 加 `values` | `config.source: "manual"`，`config.options` 为 `{label, value, default}` 列表 |
| `options`：`source: "constant"` 加 `constant` | `config.source: "constant"`、`constant_id`、`constant_name`、`options`；客户自有常量优先于共享常量 |
| `options`（`source: "entity_entries"`、`entity`、`label_field`（必填）） | `config.options_source: "entity_entries"`、`entity_id`（写入时由 `entity` 解析）和 `label_field`；保存值始终为记录 ID |
| `owner`（布尔；为 false 时省略） | 为 true 时写入 `property_schema[].owner`。仅当 `entity_entries` 引用的目标是人员实体时有效，每个实体最多一个。`Serializer` 只在为 true 时回显。`update_attribute` 接受 `set.owner`；`false` 清除标记。人员实体、桥接、非引用、非人员目标均无效。 |
| `file.accept`、`file.multiple` | `config.accept`、`config.multiple`（总会写入，默认 `false`） |
| `associations[]`：`related_entity`、`display_field`、`display_field_label`、`bridge_attributes` | `associations[]`：`associated_entity_name`、`display_field`、`display_field_label`（默认为显示字段的标题形式）、`additional_attributes`；写入时另建桥接实体 |

`create_entity` 与 `update_entity` 的契约版本为 2：`options.value_field` 已移除（`schema.unknown_property`），`source: "entity_entries"` 时必须提供 `label_field`（`schema.required`）。以版本 1 挂起的提案会以 `operation.version_changed` 被拒绝。`label_field` 和关联的 `display_field` 必须是文本、搜索、邮箱、电话、网址、数字或日期属性（`options.label_field_not_labelable`、`association.display_field_not_labelable`）。更新时，其他实体或已上线表单依赖的显示字段不可删除、不可更改类型（`attribute.display_field_in_use`），也不可对这些表单的受众隐藏（`attribute.display_field_hidden`）。

`get_entity` 与助手的 `list_catalog` 返回 `Mapper#from_entity`：形状相同，另加 `version` 及每条关联的 `bridge_entity`。

**创建。**`create_entity` 接受 1 至 10 个实体，彼此可按名称引用（关联、`entity_entries` 选项来源、聚合）。`SemanticValidator.for_create` 负责校验，`Mapper#to_definition` 逐个映射，`EntityDefinitions::Persist` 在同一事务内全部写入。一个真实调用（`create_entity.json` 的第一个示例）：

```json
{
  "entities": [
    {
      "name": "Course",
      "attribute_groups": [{ "key": "basics", "name": "Basics", "icon": "folder", "color": "indigo" }],
      "attributes": [
        { "name": "Title", "group": "basics" },
        {
          "name": "Level",
          "html_type": "select",
          "group": "basics",
          "options": { "source": "static", "values": ["Beginner", "Intermediate", "Advanced"] }
        }
      ]
    },
    {
      "name": "Student",
      "attributes": [
        { "name": "Email", "html_type": "email" },
        { "name": "Courses Taken", "kind": "computed", "aggregate": { "related_entity": "Course", "function": "count" } }
      ],
      "associations": [
        {
          "related_entity": "Course",
          "display_field": "title",
          "bridge_attributes": [{ "name": "Enrolled On", "html_type": "date" }]
        }
      ]
    }
  ]
}
```

校验为 `Title` 补齐 `kind: "input"` 与 `html_type: "text"`，映射器加上列出三个级别的 `inclusion` 规则。成功时 `data` 含 `created`（每个实体的 `name`、`slug`、`version`，以及 `{name, slug}` 形式的 `attributes`）与 `bridges`，此例为 `["assoc_student_course"]`。

**更新。**`update_entity` 接受 1 至 10 条 `updates`，每条含 `entity`、可选的 `expected_version`，以及按顺序执行的 1 至 100 条 `changes`。`update_entity.json` 的第一个示例新增一个字段、对公众隐藏一个字段、删除另一个字段：

```json
{
  "updates": [
    {
      "entity": "Student",
      "expected_version": 7,
      "changes": [
        { "op": "add_attribute", "attribute": { "name": "Phone", "html_type": "tel" }, "position": { "after": "email" } },
        { "op": "update_attribute", "slug": "email", "set": { "access": { "visible_to": { "public": false } } } },
        { "op": "remove_attribute", "slug": "fax" }
      ]
    }
  ]
}
```

`validate` 定位每个实体、比较 `expected_version`，用 `EntityDefinitions::Api::ChangeSet` 把变更集应用到该实体的 `EntityDefinitions::Catalog` 文档，再校验结果。未改动的属性逐字节保持不变。此处校验不补默认值（`insert_defaults false`），补丁只含所传内容，省略的键保留已存储的值；变更集新建内容的默认值由映射器提供。补丁改了 `kind` 或 `html_type` 时，继承来的、已不适用的 `options`、`file`、`formula` 或 `aggregate` 会像编辑器那样被丢弃；补丁本身为不适用的形态设置了其中某项，则报 `options.not_applicable`、`file.not_applicable`、`formula.not_applicable` 或 `aggregate.not_applicable`。映射器还会清除最终 kind 与 html_type 不再使用的配置项。调用挂起并返回 `ChangePlan`（示意；`id` 与各行取决于已存储内容）：

```json
{
  "ok": true,
  "status": "confirmation_required",
  "operation": "update_entity",
  "plan": [
    {
      "name": "Student",
      "id": 42,
      "breaking": true,
      "rows": [
        { "kind": "attribute", "action": "added", "name": "Phone", "html_type": "tel", "breaking": false },
        { "kind": "attribute", "action": "modified", "name": "Email", "field": "visibility", "before": { "admin": true, "member": true, "public": true }, "after": { "admin": true, "member": true, "public": false }, "breaking": false },
        { "kind": "attribute_removed", "action": "removed", "name": "Fax", "breaking": true }
      ],
      "omitted_rows": 0
    }
  ],
  "next_step": "Wait for the administrator to review and apply the plan. Do not claim the change is applied."
}
```

批准后，`perform` 重新读取目录文档，再次应用同一变更集，经 `Persist`（`replace: true`）写入：属性与分组列表按给定内容写入，聚合字段回到原位置，关联保留桥接 id。`data` 含 `updated`（`name`、`slug`、`version`）与 `bridges`。

共 16 种变更操作。按属性标识、分组键或关联实体名定位，从不使用数组下标；`set` 是 JSON Merge Patch（RFC 7396）：`null` 清除字段，数组整体替换。

| 操作 | 字段 | 编辑器对应 | 行为 |
| --- | --- | --- | --- |
| `set_details` | `display_label`、`description`、`extends` | 基本信息卡片 | 只改所传的键；`extends: null` 去掉基础模型。 |
| `set_settings` | `icon`、`color`、`default_values` | — | `default_values` 整体替换默认值映射。 |
| `add_attribute` | `attribute`、`position` | 添加属性 | 追加到末尾，或插到某个属性标识的 `before`／`after`。 |
| `update_attribute` | `slug`、`set` | 编辑属性 | 对属性的公开形式做合并补丁，省略的键保留已存储的值，属性标识不变。改 `kind` 或 `html_type` 时，丢弃不再适用的选项、文件设置、公式或聚合；显式设置其中之一则报 `<field>.not_applicable`。`set.owner` 为替换用的归属标记（`false` 清除）。 |
| `remove_attribute` | `slug` | 删除属性 | 只要同级公式仍引用该标识，即以 `attribute.in_use` 拒绝。它在 `settings.default_values` 中的条目随之删除。 |
| `move_attribute` | `slug`、`to_group`、`position` | 拖动行 | `to_group: null` 取消分组。 |
| `add_group` | `group`、`position`、`attributes` | 新建分组 | 插入分组；`attributes` 在该组内新建并追加到末尾。 |
| `update_group` | `key`、`set` | 编辑分组 | 合并补丁 `name`、`description`、`icon`、`color`，分组键不变。 |
| `remove_group` | `key`、`move_attributes_to` | 删除分组 | 把组内属性移到 `move_attributes_to`，未指定则取消分组。 |
| `reorder_groups` | `order` | 拖动分组 | 须恰好列出每个现有分组键一次，否则报 `group.order_mismatch`。 |
| `add_association` | `association` | 添加关联 | 新增关联，写入时创建桥接实体。 |
| `update_association` | `related_entity`、`set` | 编辑关联 | 修改 `display_field` 或 `display_field_label`；`bridge_attributes` 整体替换桥接字段列表。 |
| `remove_association` | `related_entity` | 删除关联 | 写入时软删除承载关联记录的桥接实体。 |
| `add_bridge_attribute` | `related_entity`、`attribute`、`position` | 关联属性弹窗 | 在桥接上新增一个输入字段。 |
| `update_bridge_attribute` | `related_entity`、`slug`、`set` | 关联属性弹窗 | 合并规则同 `update_attribute`。 |
| `remove_bridge_attribute` | `related_entity`、`slug` | 关联属性弹窗 | 删除该桥接字段。若有聚合属性经此关联（方向 `source`）聚合，并以该标识作为来源或过滤属性，则以 `attribute.in_use` 拒绝。 |

`position` 只能指定 `before` 或 `after` 之一；目标不存在时报 `change.position_target_not_found`。

**范围规则。**`SemanticValidator.locate` 在客户范围内按名称解析每个目标：

- 客户自有、有效、非桥接的实体可编辑；
- 同名实体在回收站中：`entity.name_in_trash`（`ask_user`）；
- 桥接实体或共享实体（`customer_id` 为 NULL）：`entity.not_editable`（`blocked`）；
- 其余情况：`entity.not_found`，附 `candidates`。

`create_entity` 还会拒绝：同一请求中重复的名称（`entity.duplicate_in_request`）、以 `assoc_` 开头的名称（`entity.name_reserved`）、已存在的名称（`entity.already_exists`）或回收站中的名称，以及超出配额的新实体（`quota.exceeded`，依据 `Billing::Quota.for(customer).allow?("entity", by:)`）。写入时 `Persist` 再用 `Billing::Quota::Guard` 检查一次配额。其 `perform` 在客户锁内再查一次名称，并以 `create_only: true` 写入，因此校验后被他人占用的名称会以 `entity.already_exists` 拒绝，而不是被更新。`update_entity` 拒绝同一请求中针对同一实体的第二个变更集（`entity.duplicate_in_request`，位于 `/updates/<i>/entity`）。

**人员实体。**一个业务域最多只有一个人员实体（如学生、患者、志愿者），且它就是主实体。其扩展的基础模型为 `EntityDefinitions::Capabilities::PERSON_MODEL`（`Authentication::User`）；仅当租户可扩展该模型时，`Capabilities.person_model(customer_id)` 才返回它。在 `create_entity` 中，第一个 `extends: "Authentication::User"` 的实体即人员实体：

- 同一调用中再有实体扩展该模型：`extends.person_not_unique`，位于 `/entities/<i>/extends`；
- 人员实体必须位于下标 0，否则为 `entity.person_not_first`，位于 `/entities/<i>`；
- 本次调用的关联须声明在人员实体上，其他新实体的 `associations` 指向它时以 `association.person_not_primary` 拒绝，位于 `/entities/<i>/associations/<j>/related_entity`。指向目录中已有人员实体的关联不受限制。

`create_entity` 中凡设置了 `extends` 的实体，其属性标识若与该基础模型的列同名，以 `attribute.reserved_by_base_model` 拒绝；这些列与实体编辑器通过 `base_model_fields` 保留的列相同，二者都读取 `Capabilities.base_model_fields(customer_id, class_name)`。`update_entity` 对所更新的实体做同样的列检查；上述人员实体的顺序与唯一性检查仅在创建时执行。`id` 与 `user_id` 在所有实体上均为保留标识（`attribute.reserved_slug`）。

**归属标记。** 引用属性上的 `owner: true` 标明一行归属于哪个人（`People::Ownership`）。`EntityDefinitions::Api::SemanticValidator#validate_owner_flags` 报告：

- `attribute.owner_invalid`（`%{slug}`）：「只有引用人员实体的属性才能设为记录所有者：%{slug}。」指针指向该属性的 `owner` 字段。与编辑器相同的情形：非引用、非人员目标、人员实体上的任意属性、或 `bridge_attributes` 字段（桥接靠推断；Enrollment 因 `bridge_property_schema` 已有单一人员引用而为 `:owned`）。
- `entity.owner_multiple`（`%{name}`）：「实体 %{name} 有多个属性设为所有者，请只保留一个。」

`owner: false` 与缺键等价。种类见[人员关联](person-linking)，编辑器开关见[实体构建器](entity-builder)。

**与编辑器一致。**映射器写出的内容与实体编辑器相同：

- `select`、`radio`、`checkbox` 使用静态或常量选项时，手写的 `inclusion` 规则会被替换为列出全部选项值（取 `value`，否则取标签）的规则。
- 静态选项可以是裸字符串，也可以是 `{label, value, default}`，一律存为完整对象。
- 计算字段（calculated）只读，存储方式为 computed；聚合字段（computed）另外强制为 `html_type: "number"`。
- 规则只在字段可见处生效：`validator_apply` 存为 `rules_apply_to` 与 `visible_to` 的交集。
- 新属性未给 `access` 时对所有受众可见、也都校验，因为编辑器总会写入三个开关。`file` 对象总会存储 `multiple`（默认 `false`）；分组图标或颜色缺失或无效时，`AttributeGrouper` 以 `folder` 或 `slate` 补上。

### 业务域、流程、页面与构建操作

这五个操作让助手在实体建好后补全子系统。客户的任何管理员都可调用（均未覆盖 `available?`），成员和其他租户由 `Authorization` 拒绝。它们的契约与消息只说“表单处理”，从不说“流程图”，因为模型转述的内容会被租户管理员看到。

| 操作 | 确认 | 作用 | 成功时的 `data` |
| --- | --- | --- | --- |
| `create_domain` | 无需 | 经 `EntityDomains::Activities::Save` 新建客户自有的 `EntityDomain`；`create_entity` 需要已有业务域。名称已占用时返回 `entity_domain.already_exists`。 | `domain`：`name`、`description`、`color` |
| `list_journey_options` | 只读 | 列出某业务域的 `EntityDomains::JourneyPlanner` 候选（`Journeys::DomainCandidates`）。 | `domain`、`journeys`（各行见下） |
| `generate_journeys` | 无需 | 用 `Journeys::Activities::Generate` 构建所选候选，新建或复用其页面，并发布通过发布检查的流程。 | `domain`、`journeys`：`key`、`name`、`status`、`reused`、`audiences`、`pages`（操作键）、`launch_blockers` |
| `set_page_processing` | 无需 | 经 `Pages::Activities::BindFlowchart` 设置客户自有页面提交时运行的处理。 | `page`、`audience`、`processing` |
| `start_subsystem_build` | 无需 | 记录一条 `AiAssistant::SubsystemBuild` 并入队 `AiAssistant::SubsystemBuildJob`；任务生成流程、编写并设置处理、发布就绪的流程，并在对话中汇报。 | `build`、`status`、`domain`、`journeys`、`processing`（名称）、`warnings` |

**流程候选。**`list_journey_options` 的每一行包含：

- `key`，如 `create-12`，供 `generate_journeys` 与 `start_subsystem_build` 使用；
- `kind`：`create`（管理员新建记录及其下属行）、`record`（管理员在已有记录页面上添加某类关联行）、`member`（已登录成员添加自己名下的记录）或 `public`（访客注册）；
- `audience`、`name`、`starts_with`、`adds`（步骤标签）、`continues_to`、`generated`。

`generate_journeys` 接收 `domain`、1 到 10 个 `journeys` 键和 `launch`（默认 `true`）。未知键返回 `journey.option_not_found` 并附 `candidates`；生成器拒绝时返回 `journey.generation_failed`（`blocked`）。此前已生成的键以 `reused: true` 报告，草稿若已通过检查则会发布。租户关闭注册时，`public` 候选保持草稿（`launch_blockers` 中为 `operations.journeys.sign_up_disabled`）。

**表单处理。**`set_page_processing` 接收 `page`（`generate_journeys` 报告的操作键）、`audience` 和 `processing`。`processing` 是名称：客户自有的处理（助手的 `list_catalog` 在 `processing` 下返回），或共享处理，如“Save page record”；重名时客户自有优先。违规代码为 `page.not_found`、`processing.not_found`（附 `candidates`），以及 `Pages::ProcessingContract` 拒绝时的 `page.processing_refused`。拒绝原因 `errors` 视调用者而定：

- 平台所有者得到 `BindFlowchart::Result#errors`，即代码生成器的原因，会点名流程图及其步骤；
- 其他人得到 `#reasons`：“此页面无法使用该表单处理。”（`maint_core.errors.validations.page_processing_unavailable`）、下线提示，或 `Flowcharts::Compatibility.errors`。

**子系统构建。**`start_subsystem_build` 接收 `domain`、1 到 10 个不重复的 `journeys` 键，以及至多 5 项 `processing` 需求，每项为 `{name, journey, step, purpose, values: [{label, value}]}`，`step` 可省略。`validate` 在第一组失败处停止：

1. 没有本客户的对话时返回 `subsystem.conversation_required`；对话中已有运行或等待中的构建时返回 `subsystem.build_active`（均为 `blocked`）；
2. `entity_domain.not_found`；
3. `journey.option_not_found`；
4. 逐项需求：`subsystem.journey_not_chosen`、`subsystem.signup_processing`（`public` 候选保留共享的注册流程图）、`subsystem.step_not_found`（`step` 须为 `adds` 中的标签；省略即该候选的第一个页面）、`subsystem.duplicate_processing`、`subsystem.processing_name_taken`（客户自有或共享流程图已用此名）；
5. `subsystem.preflight_blocked`（`blocked`），每个 `AiAssistant::Subsystems::Preflight` 阻断项一条：页面配额，或 `member` 候选所需的用户账号无法启用。

`perform` 再次检查有无进行中的构建，保存构建蓝图（业务域 id、各键，以及每项需求解析出的 `page_index`、`audience` 和实体）与预检警告，然后入队任务；`enqueue_after_transaction_commit` 保证写入提交后才入队。构建本身见 [AI 助手](ai-assistant)中的《子系统构建》。

### 新增操作

示例：`create_flowchart` 操作。

1. **契约。**新增 `app/services/operations/schemas/create_flowchart.json`。根须有 `title`、`description`、`type: "object"`、`additionalProperties: false`、`required`，每个属性和枚举值都要有 `description`，并提供有效的 `examples`。源自注册表的枚举用 `"x-vocabulary": "<slot>"`，不写字面列表；多个操作共用的定义放进 `<area>.defs.json`：

   ```json
   {
     "title": "Create flowchart",
     "description": "Create one customer-owned flowchart. Applies immediately.",
     "type": "object",
     "additionalProperties": false,
     "required": ["name"],
     "properties": {
       "name": { "type": "string", "minLength": 1, "maxLength": 100, "description": "Unique flowchart name in this tenant." },
       "first_step": { "type": "string", "x-vocabulary": "step_actions", "description": "Palette action the flowchart starts with." }
     },
     "examples": [{ "name": "Enrol student", "first_step": "build_contract" }]
   }
   ```

2. **词表。**契约含槽位时，新增 `FlowchartDefinitions::Api::Vocabulary` 一类的类：`self.resolve(name, context)` 从注册表（此例为 `FlowchartDefinitions::Palette.canonical_keys`）读取并返回 `{values:, descriptions:}`（`x-vocabulary-max` 则返回整数），名称未知时抛出 `ArgumentError`。

3. **类。**新增 `app/services/operations/create_flowchart.rb`：

   ```ruby
   module Operations
     class CreateFlowchart < Base
       key "create_flowchart"
       version 1
       title "Create flowchart"
       summary "Create one customer-owned flowchart. Use for new flowcharts only. Applies immediately."
       schema "create_flowchart.json"
       vocabulary FlowchartDefinitions::Api::Vocabulary
       annotations destructive: false, confirmation: :never

       register!

       def self.available?(context)
         FlowchartVisibility.allowed?(context.actor)
       end

       def validate(input)
         # Cross-field, reference and quota rules -> [Operations::Violation, ...]
       end

       def perform(input)
         # Call the domain writer; return Outcome.succeeded(operation: self.class.key, data:, effects:)
         # or Outcome.invalid(...) for a refused write.
       end
     end
   end
   ```

   `perform` 委托给现有领域写入，不要另写一套。破坏性变更声明 `destructive: true, confirmation: :always`，并实现 `plan`、`snapshot`、`stale?`：管理员批准的是可审阅的方案，过期的批准会被拒绝。输入携带合并补丁时，声明 `insert_defaults false`。`available?` 把工具挡在不应看到它的调用方之外；流程图仅平台所有者可见。

4. **消息。**每个新代码加在 `config/locales/operations_<area>.en.yml` 与 `.zh-CN.yml` 的 `operations.violations.<area>` 下，两种语言的键与 `%{...}` 变量保持一致，并在 `details` 中传入每个变量。把 `contract_lint_spec.rb` 的一致性检查扩展到新文件。

5. **测试。**契约检查已覆盖所有已注册操作。另写经 `Operations::Activities::Execute.call` 的操作测试：成功、每个违规代码、成员及其他租户管理员的 `forbidden`、租户隔离、幂等重放、`dry_run`。挂起类操作还要覆盖 `Confirm`：批准、并发编辑后的 `conflict`、`operation.version_changed`。

6. **接入助手。**仅凭注册表，新操作即可作为原生工具提供（并列给使用 JSON 约定的厂商），且自动获得校验、分诊、预算内重试、幂等、挂起与批准以及审计。不要改动 `OperationTool`、`Execute`、`Confirm`、`PendingConfirmation` 或审计表。只需补充与功能相关的部分：
   - **提示词指引：**在 `app/services/ai_assistant/assistant/prompt/` 下新增领域文档与分区，说明如何为该功能建模，并附 `{"tool": …, "arguments": …}` 示例；`tool_examples_contract_spec.rb` 会按契约校验这些示例。在 `Prompt::Composer::OUTLINES` 中处理该功能的提示词模式里，同时列入该分区与 `Sections::OperationTools`；操作分区目前只在 `entity` 模式中。
   - **方案行**（仅挂起型操作）：`plan(input)` 返回 `[{ "name", "breaking", "rows" => [{ "kind", "action", "name", "field", "before", "after", "breaking" }] }]`。新的行类型需加入 `AiAssistant::ProposedChangesComponent::ACTIONS`，并在两种语言中补上 `ai_assistant.assistant.plan.rows.<kind>_<action>`；未知行会退回到面向实体措辞的 `plan.rows.other` 标签。
   - **进度标签**（可选）：在 `Tools::Session` 中把操作键映射到进度步骤；目前只有实体操作会上报实体步骤。

   非实体操作的结果通过模型的最终回复告知管理员，批准后的回复使用通用的 `operation_applied` 或 `operation_stale` 文案。页面生成与实体变更清单只针对 `Tools::Session::ENTITY_OPERATIONS`。

## 需要特别注意

:::attention
修改后的契约文件立即生效，已挂起的提案也一样：`Confirm` 按当前文件重新校验。若改动改变了输入的含义，请提升 `version`，`Confirm` 会以 `operation.version_changed` 拒绝按旧契约挂起的提案。
:::

:::attention
输入携带合并补丁的操作必须声明 `insert_defaults false`。`update_entity` 已声明，因此 `{"access": {"visible_to": {"public": false}}}` 只改 `public`，省略的键都保留已存储的值。变更集新建内容的默认值改由映射器提供：新属性未给 `access` 时各受众开关均为 `true`，`file` 总会存储 `multiple`（默认 `false`），分组图标或颜色缺失时由 `AttributeGrouper` 以 `folder` 或 `slate` 补上。
:::

:::attention
每个 `$ref` 位置都要有自己的 `description`：契约检查把每个具名属性视为文档位置，而投影时 `$ref` 旁的描述会取代目标的描述。描述、标题与摘要是面向模型的英文，不做翻译。
:::

:::attention
`conflict.version_changed` 会以两种状态出现。提案时，`expected_version` 不一致是 `validate` 违规项，结果为 `invalid`，处理方式 `refresh`。批准时跳过这项检查，`Confirm` 在锁内 `stale?` 为真或重新校验发现 `conflict.*` 违规项时返回 `conflict`，助手据此给出「提案后已变更」的回复。请按 `code` 或 `resolution` 分支，不要只看 `status`。
:::

:::attention
`UpdateEntity#snapshot` 按实体名记录 `current_line_head_version_id`。不产生新定义版本的编辑（如只改显示名称）不会让提案过期；改名则会。`perform` 重新读取目录文档并再次应用变更集，写入基于批准时的头版本，而不是模型当时看到的文档。
:::

:::attention
只有 `around_write` 自身抛出的错误（如 `GenerationWriteGuard::Rejected`）会向外传播。校验或规划阶段的 `StandardError` 变为 `failed`。锁内 `perform` 抛出的 `StandardError`（包括返回值不是 `Outcome`）会变成 `failed` 或 `invalid` 并回滚。`NotImplementedError`（操作未实现 `perform`）不是 `StandardError`：它会穿出 `Execute.call`，且不留审计记录。客户锁上的 `requires_new: true` 不可去掉：助手的守卫已持有事务，在合并进来的事务中抛出 `ActiveRecord::Rollback` 什么也撤销不了。
:::

:::attention
以下情况不写 `operation_invocations`：重放、`idempotency.key_reused`、`operation.unknown`、只读操作（如 `get_entity`）以及试运行。只有成功或挂起的调用保留幂等键，因此重复一次被拒绝或失败的调用会重新执行，而不是重放当初的拒绝。
:::

:::attention
`operations.violations.*` 消息中的每个 `%{name}` 都必须出现在违规项的 `details` 里；缺少时，构建工具载荷会抛出 `I18n::MissingInterpolationArgument`。数组值以 `", "` 连接；哈希值不参与插值，非 JSON 安全的值不会进入 `as_json`。
:::

:::attention
容易踩坑的实体规则：配额在校验时与写入时各查一次；以 `assoc_` 开头的名称归桥接实体专用；只要同级公式仍引用某个属性标识，`remove_attribute` 就会被拒绝，经该关联的聚合仍读取某个桥接字段时，`remove_bridge_attribute` 同样被拒绝；选择类控件使用静态或常量选项时，映射器会用选项值替换手写的 `inclusion` 规则。
:::

:::attention
在助手中，`Tools::Session::MAX_ATTEMPTS`（3）统计一轮内同一操作被拒绝的次数。成功的调用不计入，`get_entity` 读取和挂起的 `update_entity` 都不算；也只有被拒绝的载荷才带 `attempts_remaining`。被拒三次后，下一次调用直接得到 `attempts.exhausted`，不再执行。`update_entity` 挂起后，再调用任何 `confirmation: :always` 的操作都会得到 `proposal.already_pending`，即使针对另一个实体。见 [AI 助手](ai-assistant)。
:::

:::attention
模型从 `set_page_processing`、`start_subsystem_build` 和 `list_catalog` 转述的内容会被租户管理员看到，因此它们的摘要、契约和违规消息从不出现“flowchart”。共享定义同样算数：`entity.defs.json` 是 `create_entity` 的一部分。租户管理员拿到的任何工具含有该词时，`spec/services/ai_assistant/assistant/tools/session_spec.rb` 会失败；其实体提示词含有该词时，`prompt_builder_spec.rb` 会失败。详细的绑定原因只给平台所有者。
:::

## 关键代码

```ruby
# app/services/operations/create_entity.rb
key "create_entity"
version 2
title "Create entity"
summary "Create one or more related customer-owned entities atomically. Use for new entities only. Associations, option sources, and aggregates may name other entities in the same call. Applies immediately."
schema "create_entity.json"
shared_defs "entity.defs.json"
vocabulary EntityDefinitions::Api::Vocabulary
annotations destructive: false, confirmation: :never

register!
```

```ruby
# app/services/operations/activities/execute.rb
def self.perform_atomically(context:, operation_key:)
  outcome = nil
  context.around_write.call do
    context.customer.with_lock(requires_new: true) do
      outcome = Current.with_customer(context.customer) { rescue_into_outcome(operation_key) { yield } }
      raise ActiveRecord::Rollback unless outcome.ok?
    end
  end
  outcome
end
```

```ruby
# app/services/operations/activities/confirm.rb
def apply(ctx, invocation:, context:, instance:, normalized:, operation_class:, **)
  outcome = Execute.perform_atomically(context: confirmed_context(context), operation_key: operation_class.key) do
    if instance.stale?(invocation.snapshot)
      Outcome.conflict(operation: invocation.operation, violations: [Violation.new(code: "conflict.version_changed")])
    else
      instance.perform(normalized)
    end
  end

  finish_row!(invocation, context, outcome)
  outcome.invocation = invocation
  ctx[:outcome] = outcome
  outcome.ok?
end
```

```ruby
# app/services/operations/schema.rb
def apply_vocabulary_slot!(schema)
  source = vocabulary_source(schema["x-vocabulary"])
  unless source.is_a?(Hash)
    raise ArgumentError, "vocabulary #{schema['x-vocabulary'].inspect} must resolve to values/descriptions"
  end

  values = Array(source[:values] || source["values"]).dup
  descriptions = (source[:descriptions] || source["descriptions"] || {}).stringify_keys
  values << nil if nullable?(schema) && !values.include?(nil)
  schema["enum"] = values
  schema["x-enum-descriptions"] = descriptions
end
```

```ruby
# app/services/operations/violation.rb
def default_resolution(code)
  name = code.to_s
  return "blocked" if name.start_with?("permission.", "quota.")
  return "refresh" if name.start_with?("conflict.")

  "fix_payload"
end
```

```ruby
# app/services/operations/activities/confirm.rb (revalidate)
instance = operation_class.new(context: confirmed_context(context))
if instance.stale?(invocation.snapshot)
  outcome = Outcome.conflict(operation: invocation.operation, invocation: invocation,
                             violations: [Violation.new(code: "conflict.version_changed")])
  finish_row!(invocation, context, outcome)
  ctx[:outcome] = outcome
  return false
end

semantic = Array.wrap(instance.validate(normalized))
if semantic.any?
  builder = semantic.any? { |violation| violation.code.start_with?("conflict.") } ? :conflict : :invalid
  outcome = Outcome.public_send(builder, operation: invocation.operation, violations: semantic, invocation: invocation)
  finish_row!(invocation, context, outcome)
  ctx[:outcome] = outcome
  return false
end
```

```ruby
# app/services/operations/activities/execute.rb
def self.replayable?(outcome)
  outcome.nil? || outcome.ok?
end
```

```ruby
# app/services/operations/outcome.rb
def next_step(attempts_remaining: nil)
  interpolations = { operation: operation }
  return I18n.t("operations.guidance.#{status}", **interpolations) unless status == "invalid"

  resolutions = violations.map(&:resolution).uniq.select { |item| Violation::RESOLUTIONS.include?(item) }
  text = if resolutions.empty?
    I18n.t("operations.guidance.invalid", **interpolations)
  else
    resolutions.map { |item| I18n.t("operations.guidance.#{item}", **interpolations) }.join(" ")
  end
  return text if attempts_remaining.nil?

  text + I18n.t("operations.guidance.attempts_remaining", attempts: attempts_remaining)
end
```

相关页面：[实体构建器](entity-builder)、[AI 助手](ai-assistant)、[模块框架](module-framework)、[账单](billing)。
