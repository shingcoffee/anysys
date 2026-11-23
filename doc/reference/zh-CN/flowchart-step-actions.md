---
title: "流程图步骤动作"
summary: "78 个过程步骤动作的目录参考：分类、标签、一句话说明、每个配置字段的角色、必填与默认值，以及每个动作写入的 ctx 键。"
---

## 概要

流程图画布上的过程框只放一个步骤动作。步骤动作目录不是手写的：每个动作是 `app/services/code_generators/element_types/process/<category>/` 下的一个生成器类，在 `config_schema ported: true do … end` 里把字段声明一次；`CodeGenerators::ActionCatalog.export(locale:)` 再结合 `flowchart_actions.*` 译文，生成编辑器、助手调色板和本页读取的 JSON。目录共 79 个动作、15 个分类。

下表由 `ActionCatalog.export(locale: "zh-CN")` 生成（目录摘要 `797261f4fec9c53913c96f6275f7dbf848c7fc9c12f6f32d5fafb81e1109d286`）。生成器或其语言键变更后，应从导出重新生成，不要手改某一行。Schema DSL、导出与发出辅助方法见 [代码生成器](code-generators)；步骤表单如何渲染这些字段见 [流程图构建器](flowchart-builder)；发出代码调用的运行时辅助方法见 [流程图运行时](flowchart-runtime)。

## 流程

```text
app/services/code_generators/element_types/process/<category>/<action>_generator.rb
        |  generator_metadata（分类、presentation 图标／颜色／single_use／privileged）
        |  config_schema ported: true（角色、requires、validate、能力声明）
        v
config/locales/flowchart_actions_<area>.{en,zh-CN}.yml
        |  flowchart_actions.<action>.{label, description, fields.<f>.{label, help, placeholder, options}}
        v
CodeGenerators::ActionCatalog.export(locale:)
        |  分类（CATEGORY_ORDER）+ 动作 + digest
        +--> 流程图编辑器   data-flowchart-canvas-action-catalog-value
        +--> 助手调色板     FlowchartDefinitions::Assistant::SchemaGenerator
        +--> 本页           生成的表格
```

## 实现

### 如何阅读下表

每个动作依次列出目录标签、键（存为 `step.action` 的值）、目录说明，以及每个配置字段一行：

- **字段**：存入 `step.config` 的键。
- **角色**：`config_schema` 角色，决定校验、编辑器控件以及 `read(:field)` 发出的 Ruby：`input`（ctx 路径，如 `params.email`，带变量选择器）、`output`（步骤写入的 ctx 键）、`expression`（单条安全 Ruby 表达式）、`literal`、`template`（Liquid）、`enum`、`flag`（JSON 布尔值）、`integer`、`decimal`、`list`、`mapping`（`[{ "key", "value" }]` 行）、`conditions`（决策式条件组）、`entity_attribute`（绑定实体的属性 slug）、`reference`（已注册引用来源中的记录或键）、`localized_text`（`{ "en", "zh-CN" }`，`en` 必填）。
- **必填／默认值**：声明了 `required: true` 的字段标为必填；有默认值时列出默认值。隐藏字段（其显示条件不满足）既不校验也不读取，生成器拿到的是默认值。
- **说明**：列出条件规则（必填条件、显示条件）、引用来源、列表与映射的项／键／值角色、枚举值（可选枚举在编辑器里另有空的“无”选项）以及数值范围。

`transport_retry`、`timeouts`、`circuit_breaker_option` 追加的高级 HTTP 字段（`retryOnTransportError`、`retryAttempts`、`connectTimeout`、`readTimeout`、`circuitBreaker`、`breakerName`、`failureThreshold`、`resetTimeoutSeconds`）不在各动作里重复列出，只在动作末行注明具备哪些。其范围与规则见 [代码生成器](code-generators)。

**写入**列出成功的步骤写入的 ctx 键：每个 `output` 字段（存储值覆盖默认值），以及该动作约定写入的标准键（`contract`、`submission_outcome`）。任何动作失败时都可能经 `FlowchartRuntime::Step.fail` 追加 `ctx[:errors]` 与 `ctx[:error_details]`，不再逐个重复。

### 记录（`model`）

#### 聚合查询（`aggregate_query`）

对记录做求和、平均等聚合

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `aggregations` | 聚合项 | `mapping` | 可选 | 键 `entity_attribute` → 值 `literal` |
| `aggregateFunction` | 聚合函数 | `enum` | 默认 `sum` | `sum` / `average` / `minimum` / `maximum` / `count` |
| `aggregateField` | 聚合字段 | `entity_attribute` | 默认 `amount` |  |
| `groupBy` | 分组 | `literal` | 可选 |  |
| `groupByFields` | 分组字段 | `list` | 可选 | 列表项 `entity_attribute` |
| `having` | Having | `literal` | 可选 |  |
| `resultFormat` | 结果格式 | `enum` | 默认 `scalar` | `scalar` / `hash` |
| `conditions` | 条件 | `conditions` | 默认 `{"type":"group","joins":[],"conditions":[]}` |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `aggregates` |  |

写入：`resultVar`（默认 `aggregates`）。

#### 批量操作（`batch_operation`）

对多条记录执行批量操作

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `operationType` | 操作类型 | `enum` | 默认 `find_each` | `find_each` / `in_batches` / `each_batch` / `update_all` / `destroy_all` |
| `batchSize` | 批次大小 | `integer` | 默认 `1000` | 范围 1–10000 |
| `stepBody` | 步骤正文 | `expression` | 可选 | 显示条件 `operationType` = `find_each` / `in_batches` / `each_batch` |
| `fieldAssignments` | 字段赋值 | `mapping` | 可选 | 显示条件 `operationType` = `update_all`；键 `entity_attribute` → 值 `expression` |
| `conditions` | 条件 | `conditions` | 默认 `{"type":"group","joins":[],"conditions":[]}` |  |
| `errorCollection` | 收集错误 | `flag` | 默认 `false` |  |
| `progressVar` | 进度保存为 | `output` | 默认 `progress` |  |

写入：`progressVar`（默认 `progress`）。

#### 批量导入（`bulk_import`）

批量导入记录

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `onDuplicateKey` | 遇到重复键 | `enum` | 默认 `skip` | `update` / `skip` |
| `uniqueBy` | 唯一字段 | `list` | 可选 | 列表项 `entity_attribute` |
| `resultVar` | 将结果保存为 | `output` | 默认 `import_result` |  |

写入：`resultVar`（默认 `import_result`）。

#### 复制记录（`clone_model`）

复制绑定实体中已加载的一条记录。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `clone` |  |

写入：`resultVar`（默认 `clone`）。

#### 统计记录（`count_records`）

统计匹配的记录数

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `conditions` | 条件 | `conditions` | 默认 `{"type":"group","joins":[],"conditions":[]}` |  |
| `resultAs` | 结果形式 | `enum` | 默认 `count` | `count` / `exists` / `absent` |
| `distinct` | 去重 | `flag` | 默认 `false` |  |
| `distinctField` | 去重字段 | `entity_attribute` | 可选 | 显示条件 `distinct` = `true` |
| `groupBy` | 分组 | `entity_attribute` | 可选 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `count` |  |

写入：`resultVar`（默认 `count`）。

#### 删除记录（`destroy_model`）

删除已加载的记录，或通过写入日期时间属性将其归档。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `mode` | 方式 | `enum` | 默认 `delete` | `delete` / `archive` |
| `archiveField` | 归档字段 | `entity_attribute` | 可选 | 必填条件 `mode` = `archive` |
| `archivedByField` | 归档人字段 | `entity_attribute` | 可选 | 显示条件 `mode` = `archive` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 查找记录（`find_model`）

按编号、属性或当前会员本人的人员记录加载绑定实体的一条记录（`findBy: current_person`，版本 `5.1.0`）。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `findBy` | 查找方式 | `enum` | 默认 `id` | `id` / `attribute` / `current_person`（`current_person` 为「当前会员本人的记录」） |
| `idSource` | 编号 | `input` | 默认 `params.id` | 显示条件 `findBy` = `id` |
| `findField` | 属性 | `entity_attribute` | 可选 | 必填条件 `findBy` = `attribute` |
| `findValue` | 值 | `input` | 可选 | 必填条件 `findBy` = `attribute` |
| `resultVar` | 将结果保存为 | `output` | 默认 `model` |  |

`findBy: current_person` 生成 `FlowchartRuntime::Entries.find_current_person(ctx)`。只读 `ctx[:current_person_ids]`，从不读 `params[:id]`。既有 `fail_with(:record_not_found, …)` 覆盖匿名访问者、没有关联的会员、绑定实体不是人员实体、以及条目已不存在。流程图记录查询从不按行限定范围；这次查找是可信上下文，不是 `People::Ownership.scope`。见[流程图运行时](flowchart-runtime)与[人员关联](person-linking)。

写入：`resultVar`（默认 `model`）。

#### 加载当前用户（`load_current_user`）

将本客户下已登录用户加载为只读哈希，含 `person_entries`（`{ "<人员实体 id>" => 条目 id }`）。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `resultVar` | 将结果保存为 | `output` | 默认 `current_user` |  |
| `required` | 必须登录 | `flag` | 默认 `true` |  |

写入：`resultVar`（默认 `current_user`）。

#### 新建记录（`new_model`）

为绑定实体创建一个尚未保存的新记录。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `resultVar` | 将结果保存为 | `output` | 默认 `model` |  |

写入：`resultVar`（默认 `model`）。

#### 序号（`next_sequence_number`）

为本客户分配下一个序号

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sequenceName` | 序号名称 | `literal` | 必填 |  |
| `prefix` | 前缀 | `literal` | 可选 |  |
| `padding` | 补零宽度 | `integer` | 默认 `6` | 范围 1–12 |
| `resetEvery` | 重置周期 | `enum` | 默认 `never` | `never` / `year` / `month` |
| `resultVar` | 将结果保存为 | `output` | 默认 `sequence_number` |  |

写入：`resultVar`（默认 `sequence_number`）。

#### 查询记录（`query_models`）

按条件查询当前实体的记录

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `conditions` | 条件 | `conditions` | 默认 `{"type":"group","joins":[],"conditions":[]}` |  |
| `select` | 选取字段 | `list` | 可选 | 列表项 `entity_attribute` |
| `returns` | 返回内容 | `enum` | 默认 `records` | `records` / `values` |
| `pageVariable` | 页码变量 | `input` | 默认 `page` |  |
| `pageSize` | 每页条数 | `integer` | 可选 | 范围 1–200 |
| `limit` | 上限 | `integer` | 可选 | 范围 1–1000 |
| `orderBy` | 排序字段 | `literal` | 可选 |  |
| `orderDirection` | 排序方向 | `enum` | 默认 `asc` | `asc` / `desc` |
| `distinct` | 去重 | `flag` | 默认 `false` |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `models` |  |
| `paginationVar` | 分页信息保存为 | `output` | 默认 `pagination` |  |

写入：`resultVar`（默认 `models`），`paginationVar`（默认 `pagination`）。

#### 关联记录（`related_record`）

通过关联查找、创建或更新一条记录。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `association` | 关联 | `reference` | 必填 | 来源 `entity_associations` |
| `operation` | 操作 | `enum` | 默认 `find` | `find` / `create` / `update` |
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `conditions` | 条件 | `conditions` | 默认 `{"type":"group","joins":[],"conditions":[]}` | 显示条件 `operation` = `find` |
| `assignments` | 赋值 | `mapping` | 可选 | 显示条件 `operation` = `create` / `update`；键 `entity_attribute` → 值 `expression` |
| `resultVar` | 将结果保存为 | `output` | 默认 `related_record` |  |

写入：`resultVar`（默认 `related_record`）。

#### 保存记录（`save_model`）

通过绑定实体持久化 Reform 合约中的模型。

无配置字段。

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 设置记录字段（`set_record_fields`）

向已加载的记录写入属性，但不保存。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `assignments` | 赋值 | `mapping` | 可选 | 键 `entity_attribute` → 值 `expression` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 更新记录（`update_model`）

将合约或参数应用到已加载的记录并保存。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `changesVar` | 将变更保存为 | `output` | 可选 |  |

写入：`changesVar`。

#### 更新或插入记录（`upsert_model`）

按匹配条件查找绑定实体的记录并更新；若不存在则新建。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `matchFields` | 匹配字段 | `list` | 必填 | 列表项 `entity_attribute` |
| `resultVar` | 将结果保存为 | `output` | 默认 `model` |  |
| `createdVar` | 将新建标记保存为 | `output` | 默认 `created` |  |

写入：`resultVar`（默认 `model`），`createdVar`（默认 `created`）。

### 校验（`validation`）

#### 构建契约（`build_contract`）

构建包装主实体模型的 Reform 契约

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `contractClass` | 契约类 | `literal` | 默认 `EntityEntryContract` |  |
| `modelVariable` | 模型变量 | `input` | 默认 `model` |  |

写入：`ctx[:contract]`。

#### 业务失败（`fail_with_error`）

以本地化消息结束在失败轨

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `message` | 消息 | `localized_text` | 必填 |  |
| `field` | 字段 | `literal` | 可选 |  |

写入：`ctx[:errors]`，`ctx[:error_details]`。

#### 校验（`validate_contract`）

针对 ctx[:params] 校验 Reform 契约

无配置字段。

写入：不写入 ctx 键，步骤只返回成功或失败。

### 数据（`data`）

#### 赋值（`assign_value`）

将值写入上下文变量

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `resultVar` | 将结果保存为 | `output` | 默认 `assigned` |  |
| `valueType` | 值类型 | `enum` | 默认 `expression` | `string` / `integer` / `float` / `boolean` / `array` / `hash` / `expression` / `null` / `ctx_ref` / `random` / `first_present` |
| `valueExpression` | 值表达式 | `expression` | 可选 | 必填条件 `valueType` = `expression` |
| `stringValue` | 字符串值 | `literal` | 可选 | 显示条件 `valueType` = `string` |
| `integerValue` | 整数值 | `integer` | 默认 `0` | 显示条件 `valueType` = `integer` |
| `floatValue` | 浮点值 | `decimal` | 默认 `0.0` | 显示条件 `valueType` = `float` |
| `booleanValue` | 布尔值 | `flag` | 默认 `false` | 显示条件 `valueType` = `boolean` |
| `arrayValue` | 数组值 | `list` | 可选 | 显示条件 `valueType` = `array`；列表项 `literal` |
| `hashValue` | 哈希值 | `mapping` | 可选 | 显示条件 `valueType` = `hash`；键 `literal` → 值 `literal` |
| `ctxRefVariable` | 上下文引用变量 | `input` | 可选 | 必填条件 `valueType` = `ctx_ref` |
| `randomType` | 随机类型 | `enum` | 默认 `uuid` | 显示条件 `valueType` = `random`；`uuid` / `hex` / `int` / `float` |
| `randomLength` | 随机长度 | `integer` | 默认 `0` | 显示条件 `valueType` = `random`；范围 0– |
| `candidates` | 候选路径 | `list` | 可选 | 必填条件 `valueType` = `first_present`；列表项 `input` |
| `literalCandidates` | 字面候选 | `list` | 可选 | 显示条件 `valueType` = `first_present`；列表项 `literal` |
| `predicate` | 判定条件 | `enum` | 默认 `nil` | 显示条件 `valueType` = `first_present`；`nil` / `blank` / `false_or_nil` |
| `blankDefinition` | 空白定义 | `enum` | 默认 `nil` | 显示条件 `valueType` = `first_present`；`nil` / `empty` / `whitespace` |

写入：`resultVar`（默认 `assigned`）。

#### 计算（`calculate`）

对集合做汇总计算

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `operation` | 运算 | `enum` | 默认 `count` | `sum` / `count` / `avg` / `min` / `max` / `product` / `concat` / `custom` |
| `fieldName` | 字段名 | `literal` | 可选 | 显示条件 `operation` = `sum` / `avg` / `min` / `max` / `product` / `concat` |
| `customExpression` | 自定义表达式 | `expression` | 可选 | 必填条件 `operation` = `custom` |
| `resultVar` | 将结果保存为 | `output` | 默认 `total` |  |
| `emptyCollectionBehavior` | 空集合行为 | `enum` | 默认 `zero` | `zero` / `nil` |
| `emptyCollectionDefault` | 空集合默认值 | `literal` | 可选 |  |
| `ignoreNils` | 忽略空值 | `flag` | 默认 `true` |  |
| `nullFilter` | 空值过滤 | `flag` | 默认 `false` |  |
| `precision` | 精度 | `integer` | 默认 `0` | 范围 0–12 |
| `roundingMode` | 舍入模式 | `enum` | 默认 `half_up` | `half_up` / `half_even` / `floor` / `ceiling` |

写入：`resultVar`（默认 `total`）。

#### 集合变换（`collection_manipulate`）

对集合做映射、抽取、分组、排序、去重、分块、展平或拉链

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `operation` | 操作 | `enum` | 默认 `map` | `map` / `pluck` / `group` / `sort` / `unique` / `chunk` / `flatten` / `zip` |
| `sourceVariable` | 来源 | `input` | 可选 | 必填条件 `operation` = `map` / `pluck` / `group` / `sort` / `unique` / `chunk` / `flatten` |
| `sources` | 来源列表 | `list` | 可选 | 必填条件 `operation` = `zip`；列表项 `input` |
| `resultVar` | 将结果保存为 | `output` | 默认 `collection` |  |
| `fieldMappings` | 字段映射 | `mapping` | 可选 | 必填条件 `operation` = `map`；键 `literal` → 值 `literal` |
| `keyFormat` | 键格式 | `enum` | 默认 `symbol` | 显示条件 `operation` = `map`；`symbol` / `string` |
| `compactResult` | 压缩结果 | `flag` | 默认 `false` | 显示条件 `operation` = `map` |
| `preserveNilElements` | 保留空条目 | `flag` | 默认 `true` | 显示条件 `operation` = `map` |
| `fields` | 字段 | `mapping` | 可选 | 必填条件 `operation` = `pluck`；键 `literal` → 值 `literal` |
| `flattenSingle` | 展平单字段 | `flag` | 默认 `false` | 显示条件 `operation` = `pluck` |
| `includeSourceIndex` | 包含源下标 | `flag` | 默认 `false` | 显示条件 `operation` = `pluck` |
| `groupField` | 分组字段 | `literal` | 可选 | 显示条件 `operation` = `group` |
| `groupByExpression` | 分组表达式 | `expression` | 可选 | 显示条件 `operation` = `group` |
| `includeCount` | 包含计数 | `flag` | 默认 `false` | 显示条件 `operation` = `group` |
| `sortGroups` | 分组排序 | `enum` | 默认 `none` | 显示条件 `operation` = `group`；`none` / `key_asc` / `key_desc` / `count_asc` / `count_desc` |
| `sortField` | 排序字段 | `literal` | 可选 | 必填条件 `operation` = `sort` |
| `sortDirection` | 排序方向 | `enum` | 默认 `asc` | 显示条件 `operation` = `sort`；`asc` / `desc` |
| `nullsFirst` | 空值在前 | `flag` | 默认 `false` | 显示条件 `operation` = `sort` |
| `uniqField` | 去重字段 | `literal` | 可选 | 显示条件 `operation` = `unique` |
| `keepStrategy` | 保留策略 | `enum` | 默认 `first` | 显示条件 `operation` = `unique`；`first` / `last` |
| `chunkMode` | 分块模式 | `enum` | 默认 `size` | 显示条件 `operation` = `chunk`；`size` / `predicate` / `field` |
| `chunkSize` | 块大小 | `integer` | 默认 `100` | 显示条件 `operation` = `chunk`；范围 1– |
| `includeRemainder` | 包含余数 | `flag` | 默认 `true` | 显示条件 `operation` = `chunk` |
| `chunkPredicate` | 分块谓词 | `expression` | 可选 | 必填条件 `chunkMode` = `predicate`；显示条件 `operation` = `chunk` |
| `chunkField` | 分块字段 | `literal` | 可选 | 必填条件 `chunkMode` = `field`；显示条件 `operation` = `chunk` |
| `depth` | 深度 | `integer` | 默认 `1` | 显示条件 `operation` = `flatten`；范围 0– |
| `removeNilElements` | 移除空元素 | `flag` | 默认 `false` | 显示条件 `operation` = `flatten` |
| `zipStrategy` | 拉链策略 | `enum` | 默认 `shortest` | 显示条件 `operation` = `zip`；`strict` / `longest` / `shortest` |
| `resultShape` | 结果形态 | `enum` | 默认 `tuples` | 显示条件 `operation` = `zip`；`tuples` / `hashes` |
| `fillValue` | 填充值 | `expression` | 可选 | 显示条件 `operation` = `zip` |

写入：`resultVar`（默认 `collection`）。

#### 比较数据（`compare_data`）

比较两个值

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 左侧 | `input` | 必填 |  |
| `otherVariable` | 右侧 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `diff` |  |
| `mode` | 模式 | `enum` | 默认 `keys` | `keys` / `values` / `deep` |
| `comparisonType` | 比较类型 | `enum` | 默认 `equality` | `equality` / `deep_equal` / `schema_match` / `diff` |
| `ignoreKeys` | 忽略的键 | `list` | 可选 | 列表项 `literal` |
| `caseInsensitive` | 忽略大小写 | `flag` | 默认 `false` |  |
| `numericTolerance` | 数值容差 | `decimal` | 默认 `0` | 范围 0– |

写入：`resultVar`（默认 `diff`）。

#### 日期时间计算（`date_time_calc`）

加减、求差、格式化、解析时间，或转换时区。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `operation` | 操作 | `enum` | 默认 `now` | `add` / `subtract` / `difference` / `format` / `parse` / `now` / `convert_timezone` |
| `resultVar` | 将结果保存为 | `output` | 默认 `datetime` |  |
| `sourceVariable` | 来源变量 | `input` | 可选 | 必填条件 `operation` = `add` / `subtract` / `difference` / `format` / `parse` / `convert_timezone` |
| `endVariable` | 结束变量 | `input` | 可选 | 必填条件 `operation` = `difference` |
| `amount` | 数量 | `integer` | 默认 `1` | 必填条件 `operation` = `add` / `subtract`；范围 0–10000 |
| `unit` | 单位 | `enum` | 默认 `days` | 必填条件 `operation` = `add` / `subtract`；`seconds` / `minutes` / `hours` / `days` / `weeks` / `months` / `years` |
| `formatString` | 格式字符串 | `literal` | 默认 `%Y-%m-%d` | 必填条件 `operation` = `format` |
| `inputFormat` | 输入格式 | `literal` | 可选 |  |
| `outputFormat` | 输出格式 | `literal` | 可选 |  |
| `businessDays` | 仅工作日 | `flag` | 默认 `false` |  |
| `timezoneAware` | 时区感知 | `flag` | 默认 `false` |  |
| `timezone` | 时区 | `literal` | 可选 | 显示条件 `timezoneAware` = `true` |
| `dstPolicy` | 夏令时策略 | `enum` | 默认 `preserve_wall` | `preserve_wall` / `preserve_utc` |
| `sourceTimezone` | 源时区 | `literal` | 默认 `UTC` |  |
| `targetTimezone` | 目标时区 | `literal` | 可选 | 必填条件 `operation` = `convert_timezone` |
| `preserveLocalTime` | 保留本地时间 | `flag` | 默认 `false` |  |
| `dstBehavior` | 夏令时歧义 | `enum` | 默认 `prefer_later` | 显示条件 `preserveLocalTime` = `true`；`raise_on_ambiguous` / `prefer_earlier` / `prefer_later` |

写入：`resultVar`（默认 `datetime`）。

#### 过滤集合（`filter_collection`）

按条件筛选集合中的条目

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `returns` | 返回内容 | `enum` | 默认 `items` | `items` / `split` / `first` / `last` / `index` / `count` / `any` / `all` / `none` |
| `resultVar` | 将结果保存为 | `output` | 默认 `filtered` |  |
| `rejectedVar` | 未匹配保存为 | `output` | 默认 `rejected` | 显示条件 `returns` = `split` |
| `filterMode` | 过滤模式 | `enum` | 默认 `single` | `single` / `multi` |
| `filterField` | 过滤字段 | `literal` | 可选 | 必填条件 `filterMode` = `single` |
| `filterOperator` | 过滤运算符 | `enum` | 默认 `eq` | 显示条件 `filterMode` = `single`；`eq` / `ne` / `gt` / `lt` / `gte` / `lte` / `includes` / `blank` / `present` |
| `filterValue` | 过滤值 | `literal` | 可选 | 显示条件 `filterMode` = `single` |
| `conditions` | 条件 | `list` | 可选 | 必填条件 `filterMode` = `multi` |
| `conditionOperator` | 条件运算符 | `enum` | 默认 `AND` | 显示条件 `filterMode` = `multi`；`AND` / `OR` |
| `rejectMode` | 反向筛选 | `flag` | 默认 `false` |  |
| `nilHandling` | 空值处理 | `enum` | 默认 `treat_as_false` | `include` / `exclude` / `treat_as_false` |
| `secondaryFilter` | 附加过滤 | `expression` | 可选 |  |
| `defaultValue` | 默认值 | `expression` | 可选 |  |

写入：`resultVar`（默认 `filtered`），`rejectedVar`（默认 `rejected`）。

#### 生成 ID（`generate_id`）

生成唯一标识符

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `idType` | 标识类型 | `enum` | 默认 `uuid` | `uuid` / `ulid` / `nanoid` / `hash` / `custom_pattern` / `hex` / `base58` / `urlsafe_base64` / `secure_random` |
| `resultVar` | 将结果保存为 | `output` | 默认 `id` |  |
| `length` | 长度 | `integer` | 默认 `21` | 显示条件 `idType` = `hash` / `hex` / `base58` / `urlsafe_base64` / `secure_random`；范围 1–256 |
| `size` | 大小 | `integer` | 默认 `21` | 显示条件 `idType` = `nanoid`；范围 1–256 |
| `alphabet` | 字母表 | `literal` | 可选 | 显示条件 `idType` = `nanoid` |
| `pattern` | 模式 | `literal` | 可选 | 显示条件 `idType` = `custom_pattern` |
| `prefix` | 前缀 | `literal` | 可选 |  |
| `separator` | 分隔符 | `literal` | 可选 |  |
| `uppercase` | 大写 | `flag` | 默认 `false` |  |

写入：`resultVar`（默认 `id`）。

#### 哈希操作（`hash_manipulate`）

操作哈希/字典数据

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `hash` |  |
| `operation` | 操作 | `enum` | 默认 `pick` | `pick` / `omit` / `keys` / `values` / `deep_merge` / `merge` / `diff` / `rename_keys` / `invert` / `deep_dup` / `symbolize_keys` / `stringify_keys` / `transform_keys` / `transform_values` / `compact` / `set_keys` / `flatten` |
| `keys` | 键 | `list` | 可选 | 必填条件 `operation` = `pick` / `omit`；列表项 `literal` |
| `otherVariable` | 另一哈希 | `input` | 可选 | 必填条件 `operation` = `deep_merge` / `merge` / `diff` |
| `renameMap` | 重命名映射 | `mapping` | 可选 | 必填条件 `operation` = `rename_keys`；键 `literal` → 值 `literal` |
| `transformExpression` | 转换表达式 | `expression` | 可选 | 必填条件 `operation` = `transform_keys` / `transform_values` |
| `computedFields` | 计算字段 | `mapping` | 可选 | 必填条件 `operation` = `set_keys`；键 `literal` → 值 `expression` |
| `flattenSeparator` | 展平分隔符 | `literal` | 默认 `_` | 显示条件 `operation` = `flatten` |
| `caseInsensitive` | 忽略大小写 | `flag` | 默认 `false` | 显示条件 `operation` = `pick` / `omit` |
| `mergeStrategy` | 合并策略 | `enum` | 默认 `shallow` | 显示条件 `operation` = `merge`；`shallow` / `deep` / `replace` / `append` |
| `arrayMergeMode` | 数组合并方式 | `enum` | 默认 `concat` | 显示条件 `operation` = `merge`；`concat` / `replace` / `unique_union` |
| `onConflict` | 冲突处理 | `enum` | 默认 `last` | 显示条件 `operation` = `merge`；`first` / `last` |

写入：`resultVar`（默认 `hash`）。

#### 日志（`log`）

写入日志或审计跟踪

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `logLevel` | 日志级别 | `enum` | 默认 `info` | `debug` / `info` / `warn` / `error` / `fatal` |
| `messageTemplate` | 消息模板 | `literal` | 必填 |  |
| `logger` | 记录器 | `enum` | 默认 `rails` | `rails` / `stdout` / `file` |
| `filePath` | 文件路径 | `literal` | 可选 | 必填条件 `logger` = `file` |
| `tags` | 标签 | `mapping` | 可选 | 键 `literal` → 值 `input` |
| `includeBacktrace` | 包含堆栈（仅错误） | `flag` | 默认 `false` |  |
| `structured` | 结构化（JSON） | `flag` | 默认 `false` |  |
| `maxMessageLength` | 最大消息长度 | `integer` | 默认 `0` | 范围 0– |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 映射值（`map_value`）

通过查找表映射值

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源变量 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `mapped_value` |  |
| `matchMode` | 匹配方式 | `enum` | 默认 `exact` | `exact` / `regex` / `range` |
| `mappings` | 映射 | `mapping` | 可选 | 必填条件 `matchMode` = `exact`；键 `literal` → 值 `literal` |
| `rules` | 规则 | `mapping` | 可选 | 必填条件 `matchMode` = `regex` / `range`；键 `literal` → 值 `literal` |
| `defaultValue` | 默认值 | `literal` | 可选 |  |
| `fallbackStrategy` | 回退策略 | `enum` | 默认 `default` | `default` / `pass_through` / `raise` |
| `multiMatch` | 多重匹配 | `flag` | 默认 `false` |  |
| `caseSensitive` | 区分大小写 | `flag` | 默认 `true` |  |

写入：`resultVar`（默认 `mapped_value`）。

#### 数学运算（`math_operation`）

对数值执行加减乘除及其他标量运算。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `operation` | 操作 | `enum` | 默认 `add` | `abs` / `floor` / `ceil` / `round` / `sqrt` / `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` / `random` |
| `sourceVariable` | 来源 | `input` | 可选 | 必填条件 `operation` = `abs` / `floor` / `ceil` / `round` / `sqrt` / `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` |
| `otherVariable` | 另一操作数 | `input` | 可选 | 必填条件 `operation` = `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` |
| `resultVar` | 将结果保存为 | `output` | 默认 `number` |  |
| `precision` | 精度 | `integer` | 可选 | 范围 0–20 |
| `divideByZero` | 除零策略 | `enum` | 默认 `raise` | 显示条件 `operation` = `divide` / `modulo`；`raise` / `nil` / `zero` / `infinity` / `nan` |
| `minValue` | 最小值 | `integer` | 默认 `0` | 显示条件 `operation` = `random` |
| `maxValue` | 最大值 | `integer` | 默认 `100` | 显示条件 `operation` = `random` |

写入：`resultVar`（默认 `number`）。

#### 解析数据（`parse_data`）

把 JSON、CSV、XML、YAML、TOML 或 properties 文本解析为结构数据。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源变量 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `data` |  |
| `format` | 格式 | `enum` | 默认 `json` | `json` / `csv` / `xml` / `yaml` / `toml` / `properties` |
| `csvHeaders` | CSV 表头 | `flag` | 默认 `true` | 显示条件 `format` = `csv` |
| `csvDelimiter` | CSV 分隔符 | `literal` | 默认 `,` | 显示条件 `format` = `csv` |
| `quoteChar` | 引号字符 | `literal` | 默认 `"` | 显示条件 `format` = `csv` |
| `skipRows` | 跳过行数 | `integer` | 默认 `0` | 显示条件 `format` = `csv`；范围 0–10000 |
| `encoding` | 编码 | `enum` | 默认 `utf-8` | 显示条件 `format` = `csv`；`utf-8` / `utf-16` / `ascii` / `iso-8859-1` |
| `colTypes` | 列类型 | `mapping` | 可选 | 显示条件 `format` = `csv`；键 `literal` → 值 `literal` |
| `xmlRoot` | XML 根 | `literal` | 可选 | 显示条件 `format` = `xml` |
| `strictMode` | 严格模式 | `flag` | 默认 `false` |  |
| `symbolizeKeys` | 符号键 | `flag` | 默认 `false` | 显示条件 `format` = `json` / `yaml` / `toml` |

写入：`resultVar`（默认 `data`）。

#### 读取常量（`read_setting`）

读取常量的选项，或某个值的标签；优先使用本客户的覆盖项。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `constant` | 常量 | `reference` | 必填 | 来源 `constants` |
| `returns` | 返回内容 | `enum` | 默认 `options` | `options` / `label` |
| `value` | 值 | `expression` | 可选 | 必填条件 `returns` = `label` |
| `resultVar` | 将结果保存为 | `output` | 默认 `constant_options` |  |

写入：`resultVar`（默认 `constant_options`）。

#### 正则提取（`regex_extract`）

用正则表达式提取、检测或替换文本。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源变量 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `match` |  |
| `pattern` | 模式 | `literal` | 必填 |  |
| `operation` | 操作 | `enum` | 默认 `match` | `match` / `scan` / `test` / `replace` |
| `flags` | 标志 | `enum` | 默认 `none` | `i` / `m` / `x` / `none` |
| `regexFlags` | 正则标志组合 | `literal` | 可选 |  |
| `returnType` | 返回类型 | `enum` | 默认 `first` | 显示条件 `operation` = `match`；`first` / `all` / `named_hash` |
| `captureGroup` | 捕获组 | `integer` | 默认 `0` | 显示条件 `returnType` = `first`；范围 0–99 |
| `replacement` | 替换为 | `literal` | 可选 | 必填条件 `operation` = `replace` |
| `fallbackValue` | 回退值 | `expression` | 默认 `nil` | 显示条件 `operation` = `match` |

写入：`resultVar`（默认 `match`）。

#### 序列化数据（`serialize_data`）

把数据写成 JSON、XML、YAML 或 MessagePack。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源变量 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `serialized` |  |
| `format` | 格式 | `enum` | 默认 `json` | `json` / `xml` / `yaml` / `msgpack` |
| `pretty` | 美化输出 | `flag` | 默认 `false` | 显示条件 `format` = `json` |
| `jsonMaxDepth` | JSON 最大深度 | `integer` | 默认 `0` | 显示条件 `format` = `json`；范围 0–100 |
| `includeRoot` | 包含根节点类型 | `flag` | 默认 `false` | 显示条件 `format` = `xml` |
| `rootElement` | 根元素 | `literal` | 默认 `data` | 显示条件 `format` = `xml` |
| `excludeNils` | 排除空值 | `flag` | 默认 `false` |  |

写入：`resultVar`（默认 `serialized`）。

#### 字符串处理（`string_manipulate`）

对文本执行拆分、拼接、大小写和 Base64 等操作。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `text` |  |
| `operation` | 操作（单项） | `enum` | 默认 `strip` | `split` / `join` / `strip` / `pad_left` / `pad_right` / `truncate` / `upcase` / `downcase` / `capitalize` / `camelize` / `underscore` / `reverse` / `replace` / `gsub` / `unicode_normalize` / `html_escape` / `html_unescape` / `base64_encode` / `base64_decode` |
| `operations` | 操作流水线 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `regexEscape` | 正则转义 | `flag` | 默认 `false` |  |
| `encoding` | 编码 | `enum` | 默认 `utf8` | `utf8` / `ascii` / `latin1` |
| `delimiter` | 分隔符 | `literal` | 默认 `,` | 显示条件 `operation` = `split` / `join` |
| `length` | 长度 | `integer` | 默认 `10` | 显示条件 `operation` = `pad_left` / `pad_right` / `truncate`；范围 1–10000 |
| `padChar` | 填充字符 | `literal` | 默认 ` ` | 显示条件 `operation` = `pad_left` / `pad_right` |
| `pattern` | 模式 | `literal` | 可选 | 显示条件 `operation` = `replace` / `gsub` |
| `replacement` | 替换为 | `literal` | 可选 | 显示条件 `operation` = `replace` / `gsub` |
| `urlSafe` | URL 安全 | `flag` | 默认 `false` | 显示条件 `operation` = `base64_encode` / `base64_decode` |
| `stripPadding` | 去除填充 | `flag` | 默认 `false` | 显示条件 `operation` = `base64_encode` |
| `inputEncoding` | 输入编码 | `enum` | 默认 `utf8` | 显示条件 `operation` = `base64_encode`；`utf8` / `binary` |
| `lineWidth` | 行宽 | `integer` | 默认 `0` | 显示条件 `operation` = `base64_encode`；范围 0–1000 |

写入：`resultVar`（默认 `text`）。

#### 类型转换（`type_cast`）

将值转换为其他类型

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `cast_value` |  |
| `targetType` | 目标类型 | `enum` | 默认 `string` | `string` / `integer` / `float` / `boolean` / `date` / `datetime` / `array` / `hash` / `big_decimal` / `rational` / `complex` / `symbol` / `time` / `date_time` / `json` |
| `format` | 格式 | `literal` | 可选 |  |
| `timezoneAware` | 时区感知 | `flag` | 默认 `false` |  |
| `strictBoolean` | 严格布尔 | `flag` | 默认 `false` |  |
| `timezone` | 时区 | `literal` | 可选 |  |

写入：`resultVar`（默认 `cast_value`）。

### 通信（`communication`）

#### HTTP 请求（`api_call`）

向外部服务发起 HTTP 请求。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `httpMethod` | HTTP 方法 | `enum` | 默认 `GET` | `GET` / `HEAD` / `POST` / `PUT` / `PATCH` / `DELETE` / `OPTIONS` |
| `url` | URL | `expression` | 必填 |  |
| `headers` | 请求头 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `queryParams` | 查询参数 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `bodyTemplate` | 请求体 | `expression` | 可选 | 显示条件 `httpMethod` = `POST` / `PUT` / `PATCH` |
| `bodyFormat` | 请求体格式 | `enum` | 默认 `json` | 显示条件 `httpMethod` = `POST` / `PUT` / `PATCH`；`json` / `form` / `text` / `xml` / `binary` |
| `authType` | 认证方式 | `enum` | 默认 `none` | `none` / `bearer` / `basic` / `apiKey` |
| `authToken` | 认证令牌 | `expression` | 可选 | 必填条件 `authType` = `bearer` / `apiKey` |
| `authUsername` | 用户名 | `expression` | 可选 | 必填条件 `authType` = `basic` |
| `authPassword` | 密码 | `expression` | 可选 | 必填条件 `authType` = `basic` |
| `apiKeyHeader` | API 密钥头 | `literal` | 默认 `X-API-Key` | 显示条件 `authType` = `apiKey` |
| `responseFormat` | 响应格式 | `enum` | 默认 `json` | `json` / `text` / `binary` |
| `responseParseKey` | 解析路径 | `literal` | 可选 |  |
| `followRedirects` | 跟随重定向 | `flag` | 默认 `true` |  |
| `maxRedirects` | 最大重定向次数 | `integer` | 默认 `5` | 显示条件 `followRedirects` = `true`；范围 0–20 |
| `idempotencyKey` | 幂等键 | `expression` | 可选 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `api_response` |  |

写入：`resultVar`（默认 `api_response`）。

高级 HTTP 选项：传输重试，超时，熔断器。

#### 创建通知（`create_notification`）

为本客户的用户创建站内通知

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `recipient` | 接收人 | `expression` | 默认 `ctx[:current_user_id]` |  |
| `title` | 标题 | `localized_text` | 必填 |  |
| `body` | 正文 | `localized_text` | 必填 |  |
| `page` | 页面 | `reference` | 可选 | 来源 `pages` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 发送短信（`send_sms`）

使用已审核的短信模板发送短信。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `templateKey` | 模板 | `reference` | 必填 | 来源 `sms_templates` |
| `to` | 收件人 | `input` | 默认 `model.phone` |  |
| `vars` | 模板变量 | `mapping` | 可选 | 键 `literal` → 值 `expression` |
| `idempotencyKey` | 幂等键 | `expression` | 可选 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `sms_message_id` |  |

写入：`resultVar`（默认 `sms_message_id`）。

#### 发送模板邮件（`send_template_email`）

通过邮件网关发送预定义邮件模板

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `templateId` | 模板 | `reference` | 必填 | 来源 `email_templates` |
| `to` | 收件人 | `input` | 必填 |  |
| `vars` | 模板变量 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `cc` | 抄送 | `expression` | 可选 |  |
| `bcc` | 密送 | `expression` | 可选 |  |
| `replyTo` | 回复地址 | `expression` | 可选 |  |
| `idempotencyKey` | 幂等键 | `expression` | 可选 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `email_message_id` |  |

写入：`resultVar`（默认 `email_message_id`）。

#### 发送 Webhook（`send_webhook`）

向外发送 Webhook POST 请求

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `url` | URL | `expression` | 必填 |  |
| `payloadExpression` | 载荷 | `expression` | 必填 |  |
| `headers` | 请求头 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `secretExpression` | 签名密钥 | `expression` | 可选 |  |
| `hmacAlgorithm` | HMAC 算法 | `enum` | 默认 `sha256` | `sha256` / `sha512` / `sha1` |
| `signatureHeader` | 签名头 | `literal` | 默认 `X-Signature` |  |
| `idempotencyKey` | 幂等键 | `expression` | 可选 |  |
| `contentType` | 内容类型 | `enum` | 默认 `application/json` | `application/json` / `application/x-www-form-urlencoded` |
| `resultVar` | 将结果保存为 | `output` | 默认 `webhook_response` |  |

写入：`resultVar`（默认 `webhook_response`）。

高级 HTTP 选项：传输重试，超时，熔断器。

### 安全（`security`）

#### 认证（`authenticate`）

校验用户或请求的凭据

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `authMethod` | 认证方式 | `enum` | 默认 `password` | `password` / `token` / `api_key` / `session` |
| `credentialSource` | 凭据来源 | `enum` | 默认 `ctx` | `ctx` / `params` |
| `sourceVariable` | 来源 | `input` | 可选 | 必填条件 `authMethod` = `password` / `token` / `api_key` |
| `resultVar` | 将结果保存为 | `output` | 默认 `authenticated_user` |  |
| `userVariable` | 用户变量 | `input` | 默认 `user` | 显示条件 `authMethod` = `password` |
| `tokenType` | 令牌类型 | `enum` | 默认 `bearer` | 显示条件 `authMethod` = `token`；`bearer` / `basic` / `custom` |
| `expectedKeyVariable` | 期望密钥 | `input` | 可选 | 必填条件 `authMethod` = `token` / `api_key` |

写入：`resultVar`（默认 `authenticated_user`）。

#### 授权（`authorize`）

按角色或 CanCanCan 能力校验是否允许继续

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `authType` | 授权类型 | `enum` | 默认 `role_check` | `role_check` / `ability_check` / `multi_role` |
| `userExpression` | 用户 | `input` | 默认 `current_user` |  |
| `roleName` | 角色名 | `enum` | 默认 `admin` | 显示条件 `authType` = `role_check`；`owner` / `admin` / `member` |
| `abilityAction` | 能力动作 | `literal` | 可选 | 必填条件 `authType` = `ability_check` |
| `abilityResource` | 能力资源 | `input` | 可选 | 必填条件 `authType` = `ability_check` |
| `roleList` | 角色列表 | `list` | 可选 | 必填条件 `authType` = `multi_role`；列表项 `literal` |
| `roleMode` | 匹配方式 | `enum` | 默认 `any_of` | 显示条件 `authType` = `multi_role`；`any_of` / `all_of` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 注册会员（`register_member`）

将公开访客注册为无密码会员

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `personVar` | 人员 | `input` | 默认 `model` |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `registration` |  |

安全分类，版本 `1.0.0`，`single_use: true`，`privileged: false`。发出 `FlowchartRuntime::Registration.call(ctx, person: <personVar>)`。规则顺序，以及 `created`／`existing` 对浏览器完全相同的响应，见[流程图运行时](flowchart-runtime)。写入 `resultVar`（`{ "status" => "created" | "existing" }`）；若尚未设置 preset，则把 `ctx[:submission_outcome]` 设为 `registration_pending`（「请查收邮件以完成注册。」／ "Check your email to finish signing up."）。该预设**不**在 `set_submission_outcome` 的枚举里。

失败：`register_member.public_only`（「仅未登录的访客可以注册。」）、`register_member.person_entity_required`（「注册需要使用人员实体的表单。」）、`register_member.signup_disabled`（「注册功能已关闭。」）、`register_member.unavailable`（「暂时无法完成注册，请稍后再试。」），文案在 `config/locales/flowchart_actions_security.*.yml`。会员配额已满不算失败：按已有账号的地址处理，响应不会暴露哪些邮箱已注册。身份无效走 `record_invalid`，与 `save_model` 相同。

写入：`resultVar`（默认 `registration`）；未设置时写入 `ctx[:submission_outcome]`。

#### 解密数据（`decrypt_data`）

解密已加密的数据

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `decrypted` |  |
| `algorithm` | 算法 | `enum` | 默认 `aes-256-gcm` | `aes-256-gcm` |
| `keySource` | 密钥来源 | `enum` | 默认 `credentials` | `credentials` / `env` / `ctx` / `derived` |
| `keyPath` | 密钥路径 | `literal` | 可选 | 必填条件 `keySource` = `env` / `ctx`；显示条件 `keySource` = `credentials` / `env` / `ctx` |
| `deriveKeyFrom` | 派生口令 | `input` | 可选 | 必填条件 `keySource` = `derived` |
| `deriveKeySalt` | 派生盐值 | `literal` | 可选 | 显示条件 `keySource` = `derived` |
| `encoding` | 编码 | `enum` | 默认 `base64` | `hex` / `base64` / `base64url` / `raw` / `binary` |

写入：`resultVar`（默认 `decrypted`）。

#### 加密数据（`encrypt_data`）

加密敏感数据

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `encrypted` |  |
| `algorithm` | 算法 | `enum` | 默认 `aes-256-gcm` | `aes-256-gcm` |
| `keySource` | 密钥来源 | `enum` | 默认 `credentials` | `credentials` / `env` / `ctx` / `derived` |
| `keyPath` | 密钥路径 | `literal` | 可选 | 必填条件 `keySource` = `env` / `ctx`；显示条件 `keySource` = `credentials` / `env` / `ctx` |
| `deriveKeyFrom` | 派生口令 | `input` | 可选 | 必填条件 `keySource` = `derived` |
| `deriveKeySalt` | 派生盐值 | `literal` | 可选 | 显示条件 `keySource` = `derived` |
| `encoding` | 编码 | `enum` | 默认 `base64` | `hex` / `base64` / `base64url` / `raw` |

写入：`resultVar`（默认 `encrypted`）。

#### 生成令牌（`generate_token`）

生成认证令牌

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `tokenType` | 令牌类型 | `enum` | 默认 `jwt` | `jwt` / `hmac` / `numeric_otp` |
| `resultVar` | 将结果保存为 | `output` | 默认 `token` |  |
| `tokenLength` | 令牌长度 | `integer` | 默认 `6` | 显示条件 `tokenType` = `numeric_otp`；范围 4–12 |
| `dataVariable` | 数据变量 | `input` | 可选 | 必填条件 `tokenType` = `hmac` |
| `digest` | 摘要算法 | `enum` | 默认 `sha256` | 显示条件 `tokenType` = `hmac`；`sha1` / `sha256` / `sha512` |
| `payloadVariable` | 载荷变量 | `input` | 可选 | 显示条件 `tokenType` = `jwt` |
| `issuer` | 签发方 | `literal` | 可选 | 显示条件 `tokenType` = `jwt` |
| `audience` | 受众 | `literal` | 可选 | 显示条件 `tokenType` = `jwt` |
| `notBefore` | 生效时间 | `expression` | 可选 | 显示条件 `tokenType` = `jwt` |
| `expiresIn` | 有效期 | `literal` | 可选 | 显示条件 `tokenType` = `jwt` |
| `claims` | 声明 | `mapping` | 可选 | 显示条件 `tokenType` = `jwt`；键 `literal` → 值 `expression` |
| `keyId` | 密钥编号 | `literal` | 可选 | 显示条件 `tokenType` = `jwt` |
| `algorithm` | 算法 | `enum` | 默认 `HS256` | 显示条件 `tokenType` = `jwt`；`HS256` / `HS384` / `HS512` / `RS256` |
| `secretSource` | 密钥来源 | `enum` | 默认 `credentials` | 显示条件 `tokenType` = `jwt`；`credentials` / `env` / `ctx` |
| `secretVariable` | 密钥变量 | `literal` | 可选 | 必填条件 `tokenType` = `jwt` / `hmac` |

写入：`resultVar`（默认 `token`）。

#### 哈希数据（`hash_data`）

生成哈希摘要

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `hashed` |  |
| `algorithm` | 算法 | `enum` | 默认 `sha256` | `bcrypt` / `scrypt` / `argon2` / `pbkdf2` / `sha256` / `sha512` / `md5` |
| `cost` | 成本（bcrypt） | `integer` | 默认 `12` | 显示条件 `algorithm` = `bcrypt`；范围 4–31 |
| `iterations` | 迭代次数 | `integer` | 默认 `100000` | 显示条件 `algorithm` = `pbkdf2` / `scrypt`；范围 1000–1000000 |
| `salt` | 盐值 | `input` | 可选 |  |
| `pepper` | 胡椒值 | `input` | 可选 |  |
| `encoding` | 编码 | `enum` | 默认 `hex` | 显示条件 `algorithm` = `sha256` / `sha512` / `md5` / `pbkdf2`；`hex` / `base64` / `base64url` |

写入：`resultVar`（默认 `hashed`）。

#### 掩码数据（`mask_data`）

对敏感字段做展示掩码

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `masked` |  |
| `maskType` | 掩码类型 | `enum` | 默认 `custom` | `last4` / `first1_last1` / `email` / `phone` / `ssn` / `credit_card` / `full` / `custom` |
| `visibleStart` | 起始可见 | `integer` | 默认 `0` | 显示条件 `maskType` = `last4` / `first1_last1` / `phone` / `ssn` / `credit_card` / `custom`；范围 0– |
| `visibleEnd` | 末尾可见 | `integer` | 默认 `0` | 显示条件 `maskType` = `last4` / `first1_last1` / `phone` / `ssn` / `credit_card` / `custom`；范围 0– |
| `maskChar` | 掩码字符 | `literal` | 默认 `*` |  |
| `preserveFormat` | 保留格式 | `flag` | 默认 `true` | 显示条件 `maskType` = `phone` / `ssn` / `credit_card` / `last4` / `first1_last1` |
| `regexPattern` | 正则 | `literal` | 可选 | 显示条件 `maskType` = `custom` |

写入：`resultVar`（默认 `masked`）。

#### 净化输入（`sanitize_input`）

净化用户提交的内容

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `sanitized` |  |
| `sanitizer` | 净化器 | `enum` | 默认 `strip_tags` | `strip_tags` / `escape_html` / `rails` / `loofah` / `scrubber` |
| `scrubberVariable` | Scrubber 变量 | `input` | 可选 | 必填条件 `sanitizer` = `scrubber` |
| `allowedTags` | 允许的标签 | `list` | 可选 | 显示条件 `sanitizer` = `rails`；列表项 `literal` |
| `allowedAttributes` | 允许的属性 | `list` | 可选 | 显示条件 `sanitizer` = `rails`；列表项 `literal` |
| `stripTags` | 再去标签 | `flag` | 默认 `false` |  |
| `removeNullBytes` | 去除空字节 | `flag` | 默认 `true` |  |
| `maxLength` | 最大长度 | `integer` | 默认 `0` | 范围 0– |

写入：`resultVar`（默认 `sanitized`）。

#### 校验令牌（`verify_token`）

校验令牌是否有效

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `secretKey` | 密钥 | `input` | 必填 |  |
| `algorithm` | 算法（回退） | `enum` | 默认 `HS256` | `HS256` / `HS384` / `HS512` / `RS256` |
| `algorithmAllowlist` | 算法允许列表 | `list` | 可选 | 列表项 `literal` |
| `verifyIssuer` | 校验签发方（iss） | `literal` | 可选 |  |
| `verifyAudience` | 校验受众（aud） | `literal` | 可选 |  |
| `leewaySeconds` | 时钟容差（秒） | `integer` | 默认 `0` | 范围 0– |
| `requiredClaims` | 必填声明 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `resultVar` | 将结果保存为 | `output` | 默认 `claims` |  |

写入：`resultVar`（默认 `claims`）。

### 后台（`background`）

#### 运行后台任务（`enqueue_job`）

立即、定时、延迟或按周期将任务加入队列。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `jobClass` | 任务类 | `reference` | 必填 | 来源 `job_classes` |
| `when` | 执行时机 | `enum` | 默认 `now` | `now` / `at` / `after` / `recurring` |
| `jobArgs` | 任务参数 | `expression` | 可选 |  |
| `queueName` | 队列 | `enum` | 默认 `default` | `default` / `low` / `high` / `mailers` |
| `priority` | 优先级 | `integer` | 可选 | 范围 0–1000 |
| `runAt` | 运行时间 | `expression` | 可选 | 必填条件 `when` = `at` |
| `waitSeconds` | 延迟秒数 | `integer` | 可选 | 必填条件 `when` = `after`；范围 0–2592000 |
| `cronExpression` | Cron 表达式 | `literal` | 可选 | 显示条件 `when` = `recurring` |
| `timezone` | 时区 | `literal` | 默认 `UTC` | 显示条件 `when` = `recurring` |
| `intervalSeconds` | 间隔秒数 | `integer` | 默认 `3600` | 显示条件 `when` = `recurring`；范围 1–86400 |
| `recurrenceLimit` | 周期次数 | `integer` | 默认 `1` | 显示条件 `when` = `recurring`；范围 1–100 |
| `resultVar` | 保存为 | `output` | 默认 `enqueued_job_id` |  |

写入：`resultVar`（默认 `enqueued_job_id`）。

### 文件（`file`）

#### 压缩文件（`compress_files`）

将文件压缩为归档

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `entries` | 条目 | `mapping` | 必填 | 键 `literal` → 值 `literal` |
| `literalEntries` | 字面条目 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `format` | 格式 | `enum` | 默认 `zip` | `zip` / `tar` / `gz` / `tar_gz` |
| `compressionLevel` | 压缩级别 | `integer` | 可选 | 范围 0–9 |
| `includeHidden` | 包含隐藏项 | `flag` | 默认 `false` |  |
| `resultVar` | 保存为 | `output` | 默认 `archive` |  |

写入：`resultVar`（默认 `archive`）。

#### 解压文件（`decompress_files`）

从归档中提取文件

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 保存为 | `output` | 默认 `extracted` |  |
| `format` | 格式 | `enum` | 默认 `auto` | `auto` / `zip` / `tar` / `gz` / `tar_gz` |
| `filter` | 过滤（fnmatch） | `literal` | 可选 |  |

写入：`resultVar`（默认 `extracted`）。

#### 下载文件（`download_file`）

从远程地址下载文件

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `url` | URL | `literal` | 可选 |  |
| `urlVariable` | URL 变量 | `input` | 可选 |  |
| `resultVar` | 保存为 | `output` | 默认 `file_content` |  |
| `destination` | 目标 | `enum` | 默认 `ctx_var` | `ctx_var` / `temp_file` / `active_storage` |
| `maxSizeBytes` | 最大字节数 | `integer` | 可选 | 范围 1–104857600 |
| `followRedirects` | 跟随重定向 | `flag` | 默认 `true` |  |
| `maxRedirects` | 最大重定向次数 | `integer` | 默认 `3` | 显示条件 `followRedirects` = `true`；范围 0–10 |
| `headers` | 请求头 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `validateChecksum` | 校验和 | `literal` | 可选 |  |

写入：`resultVar`（默认 `file_content`）。

高级 HTTP 选项：传输重试，超时，熔断器。

#### 生成文档（`generate_document`）

根据标题、正文和可选表格生成 PDF 文档。

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `title` | 标题 | `template` | 必填 |  |
| `body` | 正文 | `template` | 必填 |  |
| `sourceVariable` | 表格数据 | `input` | 可选 |  |
| `columns` | 表格列 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `filename` | 文件名 | `template` | 默认 `document.pdf` |  |
| `resultVar` | 将结果保存为 | `output` | 默认 `document` |  |

写入：`resultVar`（默认 `document`）。

#### 生成文件（`generate_file`）

生成 PDF/CSV/Excel/JSON/XML/TXT

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `resultVar` | 保存为 | `output` | 默认 `generated_file` |  |
| `fileType` | 文件类型 | `enum` | 默认 `csv` | `csv` / `xlsx` / `pdf` / `json` / `xml` / `txt` |
| `outputDestination` | 输出位置 | `enum` | 默认 `ctx_var` | `ctx_var` / `active_storage` |
| `columns` | 列 | `mapping` | 可选 | 显示条件 `fileType` = `csv` / `xlsx`；键 `literal` → 值 `literal` |
| `sheetName` | 工作表名 | `literal` | 默认 `Sheet1` | 显示条件 `fileType` = `xlsx` |
| `autoFilter` | 自动筛选 | `flag` | 默认 `false` | 显示条件 `fileType` = `xlsx` |
| `pageSize` | 页面大小 | `enum` | 默认 `letter` | 显示条件 `fileType` = `pdf`；`letter` / `a4` / `legal` |
| `pretty` | 美化 | `flag` | 默认 `false` | 显示条件 `fileType` = `json` |
| `rootElement` | 根元素 | `literal` | 默认 `root` | 显示条件 `fileType` = `xml` |
| `lineEnding` | 换行 | `enum` | 默认 `lf` | 显示条件 `fileType` = `txt`；`lf` / `crlf` |
| `filenameTemplate` | 文件名 | `literal` | 可选 |  |
| `encoding` | 编码 | `enum` | 默认 `utf-8` | 显示条件 `fileType` = `csv`；`utf-8` / `utf-16` / `ascii` / `iso-8859-1` |
| `delimiter` | 分隔符 | `literal` | 默认 `,` | 显示条件 `fileType` = `csv` |
| `headerRow` | 表头行 | `flag` | 默认 `true` | 显示条件 `fileType` = `csv` |
| `quoteStrings` | 强制引号 | `flag` | 默认 `false` | 显示条件 `fileType` = `csv` |
| `includeBom` | 包含 UTF-8 BOM | `flag` | 默认 `false` | 显示条件 `fileType` = `csv` |
| `nestedSeparator` | 嵌套分隔符 | `literal` | 默认 `.` | 显示条件 `fileType` = `csv` |

写入：`resultVar`（默认 `generated_file`）。

#### 上传文件（`upload_file`）

将文件上传到 Active Storage

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `service` | 服务 | `enum` | 默认 `active_storage` | `active_storage` |
| `attachmentName` | 附件名 | `literal` | 必填 |  |
| `sourceVariable` | 来源 | `input` | 必填 |  |
| `modelVariable` | 记录 | `input` | 默认 `model` |  |
| `filenameVariable` | 文件名变量 | `input` | 可选 |  |
| `contentTypeVariable` | 内容类型变量 | `input` | 可选 |  |
| `maxSizeBytes` | 最大字节数 | `integer` | 可选 | 范围 1–104857600 |
| `allowedTypes` | 允许的 MIME 类型 | `list` | 可选 | 列表项 `literal` |

写入：不写入 ctx 键，步骤只返回成功或失败。

### 缓存（`caching`）

#### 删除缓存（`cache_delete`）

删除缓存中的值

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `scope` | 范围 | `enum` | 默认 `key` | `key` / `pattern` / `namespace` / `all` / `tagged` |
| `cacheKey` | 缓存键 / 模式 / 命名空间 | `literal` | 可选 | 必填条件 `scope` = `key` |
| `tags` | 标签 | `list` | 可选 | 必填条件 `scope` = `tagged`；列表项 `literal` |
| `confirmPattern` | 模式数量保护 | `flag` | 默认 `true` | 显示条件 `scope` = `pattern` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 读取并回填缓存（`cache_fetch`）

缓存未命中时用回退路径计算并写入

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `cacheKey` | 缓存键 | `literal` | 必填 |  |
| `fallbackExpression` | 回退表达式 | `input` | 必填 |  |
| `resultVar` | 结果变量 | `output` | 默认 `cached` |  |
| `ttl` | 存活时间 | `integer` | 可选 | 范围 1–86400 |
| `raceConditionTtl` | 竞态存活时间（秒） | `integer` | 可选 | 范围 1–3600 |
| `forceRefresh` | 强制刷新 | `flag` | 默认 `false` |  |
| `skipNilCache` | 跳过空值缓存 | `flag` | 默认 `true` |  |
| `versionKey` | 版本键 | `literal` | 可选 |  |

写入：`resultVar`（默认 `cached`）。

#### 读取缓存（`cache_read`）

从缓存读取值

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `cacheKey` | 缓存键 | `literal` | 必填 |  |
| `resultVar` | 结果变量 | `output` | 默认 `cached` |  |
| `namespace` | 命名空间 | `literal` | 可选 |  |
| `decompressOnRead` | 读取时解压 | `flag` | 默认 `false` |  |
| `versionCheck` | 版本校验 | `literal` | 可选 |  |
| `onMiss` | 未命中时 | `enum` | 默认 `nil` | `nil` / `default` |
| `defaultValue` | 默认值 | `literal` | 可选 | 必填条件 `onMiss` = `default` |

写入：`resultVar`（默认 `cached`）。

#### 写入缓存（`cache_write`）

将值写入缓存

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `cacheKey` | 缓存键 | `literal` | 必填 |  |
| `action` | 动作 | `enum` | 默认 `write` | `write` / `write_if_absent` |
| `sourceVariable` | 源变量 | `input` | 默认 `data` |  |
| `ttl` | 存活时间（秒） | `integer` | 可选 | 范围 1–86400 |
| `compress` | 压缩 | `flag` | 默认 `true` |  |
| `raw` | 原始存储 | `flag` | 默认 `false` |  |
| `race_condition_ttl` | 竞态存活时间（秒） | `integer` | 可选 | 范围 1–3600 |
| `namespace` | 命名空间 | `literal` | 可选 |  |
| `version` | 版本 | `literal` | 可选 |  |
| `tags` | 标签 | `list` | 可选 | 列表项 `literal` |

写入：不写入 ctx 键，步骤只返回成功或失败。

### 并发（`concurrency`）

#### 获取锁（`acquire_lock`）

获取分布式锁

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `lockKey` | 锁键 | `literal` | 可选 |  |
| `lockKeyVariable` | 锁键变量 | `input` | 可选 |  |
| `holderIdentity` | 持有者标识 | `literal` | 可选 |  |
| `ttl` | 存活时间（秒） | `integer` | 默认 `30` | 范围 1–3600 |
| `onConflict` | 冲突时 | `enum` | 默认 `fail` | `fail` / `raise` / `skip` |
| `lockKeyVar` | 将锁键保存为 | `output` | 默认 `_cache_lock_key` |  |
| `tokenVar` | 将锁令牌保存为 | `output` | 默认 `_lock_token` |  |

写入：`lockKeyVar`（默认 `_cache_lock_key`），`tokenVar`（默认 `_lock_token`）。

#### 释放锁（`release_lock`）

释放分布式锁

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `lockKey` | 锁键 | `literal` | 可选 |  |
| `lockKeyVariable` | 锁键变量 | `input` | 可选 |  |
| `holderIdentity` | 持有者标识 | `literal` | 可选 |  |
| `onMissing` | 锁不存在时 | `enum` | 默认 `ignore` | `ignore` / `fail` / `log` |

写入：不写入 ctx 键，步骤只返回成功或失败。

### 韧性（`resilience`）

#### 幂等检查（`idempotency_check`）

确保同一键只执行一次

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `keyStrategy` | 键策略 | `enum` | 默认 `ctx_field` | `ctx_field` / `hash_of_inputs` / `explicit` |
| `ctxField` | 上下文字段 | `input` | 可选 | 必填条件 `keyStrategy` = `ctx_field` |
| `explicitKey` | 显式键 | `literal` | 可选 | 必填条件 `keyStrategy` = `explicit` |
| `ttlSeconds` | 有效期（秒） | `integer` | 默认 `3600` | 范围 1–2592000 |
| `resultVar` | 将结果保存为 | `output` | 默认 `idempotency_result` |  |

写入：`resultVar`（默认 `idempotency_result`）。

#### 限流（`rate_limiter`）

按租户限制操作频率

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `limiterName` | 限流器名称 | `literal` | 必填 |  |
| `capacity` | 容量 | `integer` | 默认 `100` | 范围 1–100000 |
| `window` | 窗口 | `integer` | 默认 `60` | 范围 1–86400 |
| `onExceed` | 超限处理 | `enum` | 默认 `fail` | `fail` / `skip` |
| `resultVar` | 将结果保存为 | `output` | 默认 `throttle_state` |  |

写入：`resultVar`（默认 `throttle_state`）。

### 调度（`scheduling`）

#### 检查营业时间（`business_hours_check`）

检查当前是否处于营业时间

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `schedule` | 每周时间表 | `mapping` | 必填 | 键 `literal` → 值 `literal` |
| `holidays` | 假日 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `timezone` | 时区 | `literal` | 默认 `UTC` |  |
| `timeVariable` | 时间变量 | `input` | 可选 |  |
| `resultMode` | 结果模式 | `enum` | 默认 `bool` | `bool` / `next_open` / `minutes_until_open` |
| `resultVar` | 结果变量 | `output` | 默认 `hours_status` |  |

写入：`resultVar`（默认 `hours_status`）。

#### 检查截止时间（`deadline_check`）

检查截止时间是否已过

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `deadlineVariable` | 截止时间变量 | `input` | 默认 `deadline` |  |
| `deadlineFormat` | 截止时间格式 | `enum` | 默认 `auto` | `iso8601` / `rfc2822` / `auto` |
| `referenceTime` | 参照时间 | `input` | 可选 |  |
| `gracePeriodSeconds` | 宽限（秒） | `integer` | 默认 `0` | 范围 0–31536000 |
| `behaviorOnBreach` | 逾期行为 | `enum` | 默认 `mark` | `mark` / `raise` |
| `resultVar` | 结果变量 | `output` | 默认 `deadline_status` |  |
| `breachedVar` | 逾期变量 | `output` | 默认 `deadline_breached` |  |

写入：`resultVar`（默认 `deadline_status`），`breachedVar`（默认 `deadline_breached`）。

### 支付（`payments`）

#### 退款（`refund_payment`）

对本客户已入账的支付退款

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `payment` | 支付 | `expression` | 必填 |  |
| `amount` | 金额 | `expression` | 必填 |  |
| `reason` | 原因 | `expression` | 可选 |  |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 请求支付（`request_payment`）

提交完成后交接至结账，由结账创建支付订单

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `amount` | 金额 | `expression` | 必填 |  |
| `currency` | 币种 | `expression` | 必填 |  |
| `subject` | 主题 | `expression` | 必填 |  |

写入：`ctx[:submission_outcome]["handoff"]`。

### 提交结果（`outcome`）

#### 设置提交结果（`set_submission_outcome`）

设置公开页闪讯与提交后去向

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `preset` | 预设 | `enum` | 默认 `submitted` | `submitted` / `saved` / `thank_you` / `custom`。`registration_pending` 由 `register_member` 写入，不在此列表。 |
| `message` | 消息 | `localized_text` | 可选 | 必填条件 `preset` = `custom` |
| `flash` | 闪讯样式 | `enum` | 默认 `notice` | `notice` / `alert` |
| `target` | 去向 | `enum` | 默认 `form` | `form` / `page` |
| `page` | 页面 | `reference` | 可选 | 必填条件 `target` = `page`；来源 `pages` |

写入：`ctx[:submission_outcome]`。

### 服务（`service`）

#### 调用服务（`invoke_service`）

调用外部或内部服务

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `serviceClass` | 服务类 | `reference` | 必填 | 来源 `service_classes` |
| `invocationStyle` | 调用方式 | `enum` | 默认 `call` | `call` / `new_and_call` / `class_method` / `instance_method` |
| `methodName` | 方法名 | `literal` | 可选 | 必填条件 `invocationStyle` = `class_method` / `instance_method` |
| `args` | 位置参数 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `kwargs` | 关键字参数 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `resultVar` | 保存结果为 | `output` | 默认 `service_result` |  |

写入：`resultVar`（默认 `service_result`）。

### 工具（`utility`）

#### AI 推理（`ai_inference`）

运行 AI/ML 推理

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `provider` | 提供商 | `enum` | 默认 `openai` | `openai` / `anthropic` / `cohere` / `ollama` |
| `model` | 模型 | `literal` | 默认 `gpt-4o` |  |
| `promptTemplate` | 提示词模板 | `literal` | 必填 |  |
| `systemPrompt` | 系统提示 | `literal` | 可选 |  |
| `maxTokens` | 最大 Token 数 | `integer` | 默认 `1024` | 范围 1–128000 |
| `temperature` | 温度 | `decimal` | 默认 `0.7` | 范围 0–2 |
| `tools` | 工具 | `list` | 可选 | 列表项 `literal` |
| `outputFormat` | 输出格式 | `enum` | 默认 `text` | `text` / `json` / `structured` |
| `resultVar` | 保存结果为 | `output` | 默认 `ai_response` |  |

写入：`resultVar`（默认 `ai_response`）。

高级 HTTP 选项：超时，熔断器。

#### 审计日志（`audit_log`）

写入审计日志

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `eventType` | 事件类型 | `literal` | 必填 |  |
| `resourceType` | 资源类型 | `literal` | 可选 |  |
| `resourceId` | 资源 ID（上下文键） | `input` | 可选 |  |
| `actorId` | 操作者 ID（上下文键） | `input` | 默认 `current_user_id` |  |
| `actorType` | 操作者类型 | `literal` | 可选 |  |
| `metadata` | 元数据 | `mapping` | 可选 | 键 `literal` → 值 `input` |
| `ipAddress` | IP 地址（上下文键） | `input` | 默认 `request_ip` |  |
| `userAgent` | User Agent（上下文键） | `input` | 默认 `user_agent` |  |
| `severity` | 严重级别 | `enum` | 默认 `info` | `debug` / `info` / `warn` / `error` / `critical` |

写入：不写入 ctx 键，步骤只返回成功或失败。

#### 生成条码（`barcode_generate`）

生成条码

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `sourceVariable` | 源 | `input` | 必填 |  |
| `format` | 条码格式 | `enum` | 默认 `code128` | `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar` / `qr` |
| `width` | 宽度（模块） | `integer` | 默认 `2` | 显示条件 `format` = `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar`；范围 1–32 |
| `height` | 高度 | `integer` | 默认 `100` | 显示条件 `format` = `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar`；范围 1–1000 |
| `margin` | 边距 | `integer` | 默认 `10` | 范围 0–100 |
| `outputFormat` | 输出格式 | `enum` | 默认 `png` | `png` / `svg` / `jpg` / `base64` / `ascii` |
| `includeText` | 包含文本 | `flag` | 默认 `true` | 显示条件 `outputFormat` = `svg` |
| `textFont` | 文字字体 | `enum` | 默认 `Helvetica` | 显示条件 `outputFormat` = `svg`；`Helvetica` / `Arial` / `DejaVuSans` / `FreeSans` |
| `size` | 尺寸 | `integer` | 默认 `4` | 显示条件 `format` = `qr`；范围 1–40 |
| `errorCorrection` | 纠错级别 | `enum` | 默认 `M` | 显示条件 `format` = `qr`；`L` / `M` / `Q` / `H` |
| `colorDark` | 深色 | `literal` | 默认 `#000000` | 显示条件 `format` = `qr` |
| `colorLight` | 浅色 | `literal` | 默认 `#FFFFFF` | 显示条件 `format` = `qr` |
| `resultVar` | 保存结果为 | `output` | 默认 `barcode_image` |  |

写入：`resultVar`（默认 `barcode_image`）。

#### 货币换算（`currency_convert`）

在不同货币之间换算

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `amount` | 金额 | `input` | 必填 |  |
| `fromCurrency` | 源货币 | `literal` | 默认 `USD` |  |
| `toCurrency` | 目标货币 | `literal` | 必填 |  |
| `rateSource` | 汇率来源 | `enum` | 默认 `fixed` | `ctx` / `ctx_key` / `config` / `fixed` / `external` |
| `fixedRate` | 固定汇率 | `decimal` | 可选 | 必填条件 `rateSource` = `fixed`；范围 0– |
| `rounding` | 舍入 | `enum` | 默认 `half_up` | `half_up` / `half_even` / `floor` / `ceiling` |
| `precision` | 精度 | `integer` | 默认 `2` | 范围 0–12 |
| `cacheRates` | 缓存汇率 | `flag` | 默认 `true` | 显示条件 `rateSource` = `external` |
| `ratesVariable` | 汇率变量 | `input` | 默认 `exchange_rates` | 显示条件 `rateSource` = `ctx` / `ctx_key` |
| `staticRates` | 静态汇率 | `mapping` | 可选 | 显示条件 `rateSource` = `config`；键 `literal` → 值 `literal` |
| `rateApiUrl` | 汇率接口地址 | `literal` | 默认 `https://api.exchangerate.host/latest` | 显示条件 `rateSource` = `external` |
| `resultVar` | 保存结果为 | `output` | 默认 `converted` |  |

写入：`resultVar`（默认 `converted`）。

高级 HTTP 选项：超时，熔断器。

#### 地理定位查询（`geolocation_lookup`）

查询地理位置数据

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `mode` | 模式 | `enum` | 默认 `ip_to_location` | `ip_to_location` / `distance` |
| `sourceVariable` | 源 | `input` | 必填 |  |
| `otherVariable` | 另一值 | `input` | 可选 | 必填条件 `mode` = `distance` |
| `provider` | 提供商 | `enum` | 默认 `google` | 显示条件 `mode` = `ip_to_location`；`google` / `mapbox` |
| `lookupKey` | 查找键 | `enum` | 默认 `ip` | 显示条件 `mode` = `ip_to_location`；`ip` / `postal` / `address` / `coords` |
| `fieldsToReturn` | 返回字段 | `list` | 可选 | 显示条件 `mode` = `ip_to_location`；列表项 `literal` |
| `fallbackProvider` | 回退提供商 | `enum` | 可选 | 显示条件 `mode` = `ip_to_location`；`google` / `mapbox` |
| `cacheResults` | 缓存结果 | `flag` | 默认 `true` | 显示条件 `mode` = `ip_to_location` |
| `resultVar` | 保存结果为 | `output` | 默认 `location` |  |

写入：`resultVar`（默认 `location`）。

高级 HTTP 选项：超时，熔断器。

#### I18n 翻译（`i18n_translate`）

使用 I18n 翻译文本

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `key` | 翻译键 | `literal` | 必填 |  |
| `locale` | 语言区域 | `literal` | 可选 |  |
| `fallbackLocale` | 回退语言区域 | `literal` | 可选 |  |
| `interpolations` | 插值 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `scope` | 作用域 | `literal` | 可选 |  |
| `default` | 默认值 | `literal` | 可选 |  |
| `count` | 数量 | `input` | 可选 |  |
| `raiseOnMissing` | 缺失时失败 | `flag` | 默认 `false` |  |
| `resultVar` | 保存结果为 | `output` | 默认 `translated` |  |

写入：`resultVar`（默认 `translated`）。

#### 渲染模板（`template_render`）

用数据渲染模板

| 字段 | 标签 | 角色 | 必填 / 默认值 | 说明 |
|---|---|---|---|---|
| `template` | 模板 | `literal` | 必填 |  |
| `variables` | 变量 | `mapping` | 可选 | 键 `literal` → 值 `literal` |
| `strictVariables` | 严格变量 | `flag` | 默认 `false` |  |
| `resultVar` | 保存结果为 | `output` | 默认 `rendered` |  |

写入：`resultVar`（默认 `rendered`）。

## 需要特别注意

:::attention
不要按 `registration.status`（`created` 与 `existing`）分支流程图去显示不同结果，那会暴露哪些邮箱已有账号。两种状态都留下相同的 `registration_pending` 闪讯。身份在 `ctx[:identity]`（字符串键，仅人员实体页上已放置的身份字段，只对公开与管理员；会员得到 `{}`）。续接在 `ctx[:continuation]`（符号键 `{ action_key:, prefill: }` 或 nil）。二者都不在 `ctx[:params]`。通用记录步骤从不写身份键。见[流程图运行时](flowchart-runtime)。
:::

:::attention
`request_payment` 不在提交内创建 `Payments::Order`。`FlowchartRuntime::Payments.request` 校验并规范化金额、币种和主题，检查运行客户已启用支持交接的支付模块，然后在 `ctx[:submission_outcome]["handoff"]` 里挂起交接（`module_key: "payment"`，`input: { amount, currency, subject }`）。运行成功后，`PublicPagesController` 启动支付模块交接，由结账（`Payments::CheckoutsController#start` → `build_order_from`）创建唯一的订单。提交事务内不发生扣款。
:::

:::attention
只有当生成器上下文带有绑定实体时（即生成 Activity 时），`set_record_fields` 才会拒绝不属于绑定实体的赋值键（`unknown_attribute`，报出属性与实体）。编辑器的校验按钮调用 `validate_config` 时不带该上下文，因此未知 slug 在生成 Activity 时才暴露，不会出现在步骤表单里。
:::

:::attention
`generate_document` 渲染 PDF 并存为 ActiveStorage blob，步骤把 `{ blob_id, signed_id, filename, content_type, byte_size, checksum, customer_id }` 写入输出键。目前不会把 blob 挂到记录上；挂到 `file_upload` 属性是后续工作。中日韩文字优先用 `vendor/fonts/` 或 `app/assets/fonts/` 下的 `DroidSansFallbackFull.ttf`，否则用系统路径 `/usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf`；都不存在时 PDF 使用 Helvetica，并把中日韩字符替换为 `?`。是否内置字体（Noto Sans SC）待所有者决定。
:::

:::attention
`audit_log` 写入 `flowchart_audit_events` 行，`create_notification` 写入 `flowchart_notifications` 行，两者都在运行事务内。目前没有管理端或会员端页面读取这两张表；读取界面是后续工作。
:::

:::attention
`validate_config` 对 `reference` 字段只检查是否填写。每个 `CodeGenerators::ReferenceSources::<Source>` 都定义了 `valid?(value, customer:)`，但生成时不会调用。被引用记录的租户范围由步骤调用的运行时辅助方法在运行时把关（`FlowchartRuntime::Constants` 遇到其他租户的常量会抛错，`Notifications` 丢弃不可访问的页面，提交结果跳转忽略外租户页面）。
:::

## 关键代码

```ruby
# app/services/code_generators/action_catalog.rb
    CATEGORY_ORDER = %w[
      model validation data communication security background file
      caching concurrency resilience scheduling payments outcome
      service utility
    ].freeze
```

```ruby
# app/services/code_generators/action_catalog/field_presenter.rb
      ROLE_CONTROLS = {
        input: { "control" => "text", "variablePicker" => true },
        output: { "control" => "text", "variablePicker" => false },
        expression: { "control" => "code" },
        literal: { "control" => "text" },
        template: { "control" => "textarea", "multiline" => true },
        enum: { "control" => "select" },
        flag: { "control" => "toggle" },
```

```ruby
# app/services/code_generators/element_types/process/model_operations/find_model_generator.rb
          config_schema ported: true do
            enum :findBy, %w[id attribute current_person], default: "id"
            input :idSource, default: "params.id", visible: { findBy: "id" }
            entity_attribute :findField, of: :bound, example: "email", visible: { findBy: "attribute" }
            input :findValue, example: "params.email", visible: { findBy: "attribute" }
            output :resultVar, default: "model"
            requires :findField, when: { findBy: "attribute" }
            requires :findValue, when: { findBy: "attribute" }
          end
```

```ruby
# app/services/flowchart_runtime/payments.rb
    def write_handoff(ctx, amount:, currency:, subject:)
      outcome = (ctx[:submission_outcome] || {}).to_h.stringify_keys
      outcome["handoff"] = {
        "module_key" => MODULE_KEY,
        "input" => { "amount" => amount, "currency" => currency, "subject" => subject }
      }
      ctx[:submission_outcome] = outcome
    end
```

相关：[代码生成器](code-generators)、[流程图构建器](flowchart-builder)、[流程图运行时](flowchart-runtime)、[支付](payments)、[短信](sms)、[邮件](email)、[常量](constants)。
