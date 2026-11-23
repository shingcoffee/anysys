---
title: "实体构建器"
summary: "实体结构、版本、关联、计算字段与租户记录的存储、编辑，以及管理端条目创建。"
---

## 概要

实体是租户记录的结构定义。`Entity` 把身份留在父行（`name`、`display_label`、`status`、`category`、`extended_model`、`customer_id`），把定义正文放在版本上。正文包括 `property_schema`、`default_properties`、`associations`、`attribute_groups`，以及 `icon`、`color`、`description`、`referenced_template`。加载后 `reload_definition_from_head!` 从 `Versionable#resolved_current_version` 拷贝正文：客户已有覆盖时读覆盖，否则读全局默认。

记录是 `EntityEntry`。每一行属于一个实体、一个客户。可变属性放在 JSON 列 `data` 里。计算字段与聚合字段不写入该列。代码里没有名为 rollup 的类型：聚合是 `property_schema` 中 `type` 为 `"Computed"` 的字段，由 `Entities::ComputedCompiler` 编译成 SQL。

结构编辑器在 `/:customer_id/admin/maintenance/entities`，共享行再挂到 `/:customer_id/admin/maintenance/platform/entities`。记录只走租户路径，不挂到共享资源前缀下。

## 流程

```text
管理表单（entity-form）
        |
        |  隐藏 JSON：property_schema、associations、
        |  attribute_groups、default_properties
        v
Admin::Maintenance::EntitiesController
        |  definition_scope + SharedResourceMode
        |  租户覆盖只允许定义正文
        v
Entity#save
        |  BridgeEntityManagement#sync_bridge_entities!
        |  Versionable after_save 自动提交
        v
EntityDefinitionContent.store!   （SHA-256，按内容寻址）
        |
        v
EntityVersion  -->  current_version_id
                 或 entity_customer_heads（按客户覆盖）

读取结构
        |
        v
resolved_current_version --> 虚拟属性

记录
        |
        +-- 页面提交 / 流程图 Activity
        |
        +-- Admin::EntityEntriesController  new / create / edit / update
                |
                v
            Entities::EntryForm（生效结构 + 允许的输入）
                |
                v
            Entities::Activities::CreateEntry / UpdateEntry
                |
                v
            EntityEntryContract（admin 受众 + writable_slugs）
        |
        v
EntityEntry（customer_id + entity_id + data JSON）
        |
        v
Admin::EntityEntriesController  index / show / destroy / batch_destroy
```

在共享实体的租户路径上保存，写入的是该客户的覆盖线，URL 客户为 `81721200` 时同样如此。平台前缀（`Current.shared_resources_mode`）写入全局行（`customer_id` 为 NULL）。`guard_shared_global_writes` 会拒绝在租户路径上销毁该共享行。同一路径的允许参数里没有身份列。租户清空回收站使用 `customer_id: current_customer_id`，因此 `customer_id` 为 NULL 的共享行不在这个范围内；平台前缀清空的是 `only_deleted.shared`。

`Entity` 的创建与更新包在事务里，并调用 `sync_bridge_entities!`。桥接实体保存失败则整次回滚。`Versionable` 只在快照哈希变化时提交新版本。只改身份不会增加版本。每条版本线裁剪到 `Versionable::MAX_VERSIONS`（50）。

## 实现

### 模型

`Entity` 引入 `SoftDeletable`（删除状态 `:inactive`）、`TenantScoped`、`SharedIdentity`、`BridgeEntityManagement`、`EntitySchemaValidation`、`Versionable`。`acts_as_versionable` 使用反射 `:entity_versions`、版本类 `EntityVersion`、内容类 `EntityDefinitionContent`、快照读取器 `:definition_snapshot_json`，以及客户头反射 `:entity_customer_heads`。

`category` 为 `plain`、`bridge` 或 `extension`。非桥接实体一旦设置 `extended_model` 就成为扩展；清空后回到普通实体。桥接实体不能扩展基础模型。

表单的**扩展基础模型**下拉框在两个前缀下都列出 `ExtendableModelRegistry.for_customer(current_customer_id)`，桥接实体不显示。租户路径下为选填（空选项为 `maint_core.entities.form.no_base_model`），租户管理员可借此创建客户自有的扩展实体；共享资源下为必填。在共享实体的租户覆盖上，`extended_model` 属于身份字段，下拉框以禁用状态显示。没有获准模型时，租户路径显示 `no_base_models_tenant`（指向「维护 / 模块」），平台前缀显示 `no_base_models`。`Entity#extended_model_is_approved` 会按实体的 `customer_id` 对提交的类再次校验。`name` 必填（1 至 100 个字符），不强制唯一。共享实体不能带关联（`shared_entity_has_no_associations`）。

获准 `extended_model`／字段目录仅是元数据。运行页面提交目前保存 EntityEntry，未实现基础模型写入、可写契约及认证归属适配器。唯一例外是人员实体（扩展 `Authentication::User`）：管理员可通过 `entity_entries.user_id` 将其每个条目关联到同租户的一个用户，见[人员关联](person-linking)。基础控件不渲染，非空／畸形基础输入在活动执行前拒绝，见[页面渲染](page-rendering)及[流程图运行时](flowchart-runtime)。

`property_schema` 里，`"Calculated"` 是公式，`"Computed"` 是桥接聚合。`input_fields` 排除这两者。`grouped_property_schema` 按 `attribute_groups` 排序，未分组属性放在最后。`EntitySchemaValidation` 检查名称与 slug 唯一、分组形状、重复或自关联、目标实体是否存在，以及计算字段的 `config`（`function`、`precision`、`bridge_entity_id`、来源字段、过滤条件）。计算字段只允许出现在客户自有实体上。函数来自 `Entities::ComputedCompiler::FUNCTIONS`：`avg`、`sum`、`count`、`min`、`max`。过滤运算符为 `=`、`!=`、`>`、`>=`、`<`、`<=`。数值控件为 `number` 与 `range`。精度上限为 6。

`BridgeEntityManagement#sync_bridge_entities!` 为每条关联创建或更新一个联接实体（`category: :bridge`）。关联哈希包含 `target_entity_id`、`display_field`、`bridge_entity_id`。软删除源实体时一并软删除其桥接实体；`restore` 会恢复它们。

### 实体记录下拉列表

下拉或单选属性可以列出另一个实体的记录：编辑器的“使用实体记录”模式保存 `config: { options_source: "entity_entries", entity_id:, label_field: }`。条目始终保存记录 **ID**；`label_field`（显示字段）只用作选项标签。不存在 `value_field`。

- **显示字段。** `Entities::ReferenceLabels.labelable?` 只接受文本、搜索、邮箱、电话、网址、数字和日期输入属性；计算字段、汇总字段、引用字段和 `id` 均不可用。关联的 `display_field` 遵循同一规则。`GET /:cid/admin/maintenance/entities.json` 为每个属性标注 `labelable`，编辑器只提供这些字段。
- **选项。** `Entities::ReferenceOptions` 列出当前租户中目标实体的记录，按标签再按 ID 排序，最多 200 条。没有标签的记录显示为“未命名（#id）”；重复的标签编号为“标签（#id）”。目标实体已在回收站、是桥接实体、属于其他租户，或显示字段对当前受众不可见时，列表为空。
- **定义规则。** 保存定义时，若下拉列表的目标实体不存在（`reference_target_missing`）或显示字段不可作标签（`reference_label_field_invalid`），或关联的显示字段不可作标签（`association_display_field_invalid`），保存会被拒绝。仅改变状态的保存（移入回收站、恢复）不做这些检查。
- **回收站。** 仍被其他实体引用的实体无法移入回收站，并会列出引用位置（`entity_referenced`）。`Entities::ReferenceDependents` 会在客户自有定义、共享默认定义和每个租户的覆盖中查找引用方。
- **修改显示字段。** 删除或更改其他实体正在显示的字段会被拒绝（`display_field_in_use`）；对已上线表单的受众隐藏该字段同样会被拒绝（`display_field_hidden_from_form`）。
- **可见性。** 下拉列表会向所有能打开表单的人列出每条记录的显示字段；除非表单只含管理员受众，用作显示字段的人员姓名或编号应对成员和公众隐藏。
- **归属人开关。** 目标为人员实体的引用可以带 `"owner": true`。属性弹层在“使用实体记录”区块渲染**归属人**开关（`comp_admin.attribute_modal.owner_label`／`owner_help`：「会员仅能查看和提交通过此字段归属于自己的记录。」）。`data-entity-form-person-entity-ids-value` 列出人员实体 id（含回收站中的，恢复后的 Student 仍算）。`ReferenceManager` 仅在所选目标属于该列表时显示开关；非人员目标、人员实体、桥接实体、关联附加属性均隐藏。`AttributeManager` 只在开关打开时写入 `"owner": true`，否则省略该键。`ModalManager#prefillModalWithAttribute` 会还原开／关状态。
- **归属标记规则。** `property_schema` 或 `associations` 变更时运行 `EntitySchemaValidation#validate_owner_reference`。`"owner": true` 只对指向人员实体的引用有效，且最多一个。`"owner": false` 与缺键等价。违规：`maint_core.errors.validations.entity_owner_reference_invalid`（`%{field}`：「只有引用人员实体的字段才能设为记录所有者：%{field}。」）与 `entity_owner_reference_multiple`（「只能有一个字段设为记录所有者。」）。非引用、非人员目标、人员或桥接实体上的任意属性、以及关联 `additional_attributes`（桥接靠推断）一律拒绝。助手先按名称写目标（`config` 带实体名）时，第一次 `EntityDefinitions::Persist` 保存跳过检查，第二次解析出 id 后再校验。种类见[人员关联](person-linking)，公开词汇中的 `owner` 见[操作 API](operations-api)。

`EntityDefinitions::Persist` 在客户锁内写入一组客户自有定义：先规范化，再写身份、选项来源、关联与计算字段。它不是表单的保存路径，由[操作 API](operations-api) 调用。`EntityDefinitions::Capabilities` 是注册表清单，供 `Normalizer` 及助手提示词中的能力矩阵读取。

### 通过操作编写

表单之外，实体通过[操作 API](operations-api) 编写：`create_entity` 立即生效，`update_entity` 一律等待管理员批准，`get_entity` 只读。它们接受一套公开词汇（`slug`、`kind`、`rules`、`access`、`options`、`extends`），由 `EntityDefinitions::Api::Mapper` 与本页的存储定义互相转换；`EntityDefinitions::Api::SemanticValidator` 负责跨字段规则，`Persist` 负责写入。范围仅限客户自有、有效、非桥接的实体；共享实体、桥接实体及回收站中的名称一律拒绝。

属性定义可以只写一部分，如 `{"name":"Notes","html_type":"textarea"}`。省略 `kind` 即为 `input`，映射器对省略的属性标识用 `parameterize(separator: "_")` 由名称生成，此例为 `notes`。普通输入、Calculated、Computed 及桥接字段采用同一规则，标识生成后不再改变。显式标识须匹配 `^[A-Za-z0-9_]+$`，`id` 为保留字。名称经参数化后为空（如中文名称）时须显式提供标识，否则校验报 `attribute.reserved_slug`。

更新是一组带类型的编辑器动作（`add_attribute`、`update_attribute`、`move_attribute`、`remove_group` 等），按属性标识、分组键或关联实体名定位。`update_entity` 挂起一条 `OperationInvocation`，附可审阅的 `ChangePlan` 及每个实体的 `current_line_head_version_id`。批准时运行 `Operations::Activities::Confirm`：重新校验，在客户锁内核对这些头版本，再把变更集应用到重新读取的目录文档，写入因此落在最新头版本上。`expected_version` 过期的变更在提案时即以 `conflict.version_changed` 拒绝；批准时头版本已变动则返回 `conflict`，请管理员重新提出。补丁只含所传的键，省略的设置保留已存储的值。模型无法批准自己的提案，只有管理员可以。见 [AI 助手](ai-assistant)。

实体及生成页面的额度来自[账单](billing)权限。有效订阅使用已接受的 `plan_snapshot["limits"]`，目录额度后续调高或调低均不改写该额度。尚未配置默认方案时，内置有限 Starter 回退提供 50 个页面、25 个实体和 5 个成员，读取时不创建目录行。显式配置的有限零额度仍具有最终效力。

助手新建的实体立即有效：`Entity` 默认 `status: :active`，关联桥接显式设为有效状态，实体没有单独的上线标记。助手后续成功生成表单时，将客户自有 `Page` 按列默认值上线（管理员开，会员与公开关）；表单生成／上线失败保留已应用的实体操作，并如实报告表单失败。复用页面保留原有上线状态与受众。实体更新批准流程不变。参见[页面构建器](page-builder)及 [AI 助手](ai-assistant)。

### 版本

`EntityVersionsController` 列出 `current_line_versions`。历史编辑加载选定范围内的快照／引用，并携带 `based_on_version_id`。设为默认／恢复调用 `Entities::PromoteVersion.call(entity:, version:, restore:)`：候选校验、桥接协调、完整校验后原子移动头。桥接身份修复会生成准确的新版本；拒绝时头及桥接不变。`POST .../versions/:id/page` 仍是创建页面边界；相同载荷共用内容。

### 业务域

业务域把同一业务领域的实体归在一起，例如课程、学生、学期及其桥接实体为一个业务域，客户与订单为另一个。业务域仅由平台所有者管理（`EntityDomainVisibility.allowed?`，经 `OwnerOnlySurfaces` 统一拦截），按客户存储：所有者在某租户的 URL 下整理该租户的列表。租户管理员访问任何业务域管理路由均返回 `403`，维护页只看到平铺表格；但可在 `/:cid/admin/domains` 只读浏览按业务域分组的实体。

- **存储。** `EntityDomain`（`customer_id`；`name` 在同一客户内不区分大小写唯一；`description`；`color` 取自 `EntityDomain::COLORS`）与 `EntityDomainMembership`（`customer_id`、`entity_domain_id`、`entity_id`，`customer_id` + `entity_id` 唯一）。每个客户下一个实体至多属于一个业务域。归属是关联行，因此归类共享实体不会改动共享行；删除业务域或实体只级联删除归属。
- **桥接实体。** 没有显式归属的桥接实体，若两端实体（`EntityDomains::Catalog.bridge_ends`，即桥接 `property_schema` 中前两个 `entity_id`）属于同一业务域，则自动跟随，并标为「自动」。显式归属优先；清除后重新跟随两端。
- **写入。** `EntityDomains::Activities::Save` 用 `EntityDomains::Contracts::EntityDomain` 校验，并在同一事务内替换成员列表（`EntityDomains::Memberships.replace!` 会把实体移出原业务域）。`Assign` 移动单个实体，`Destroy` 删除业务域，其中实体变为未分组。实体编号必须属于该客户，或是该客户可见的共享实体。
- **列表。** 在租户实体 URL 下，所有者默认看到「业务域」视图；`?view=table` 保留分页平铺表格。`EntityDomains::Layout` 编排分组（业务域按名称排序，未分组置后），`Admin::Maintenance::Entities::DomainIndexComponent` 渲染业务域导航、搜索框、类型筛选（`?kind=entity|bridge`），以及按业务域分组行的单张表格。`?domain_id=<id|ungrouped>` 只显示一个业务域。未启用搜索或类型筛选时，空业务域仍会列出。共享资源前缀与 JSON 目录不受影响。
- **按业务域浏览。** `GET /:cid/admin/domains`（`Admin::DomainsController#index`，admin 或 owner）是「业务域」菜单（菜单键 `:entities`）的落地页，显示第一个业务域；`GET /:cid/admin/domains/:id`（`#show`）显示单个业务域，`:id` 为业务域 ID 或 `ungrouped`（`Admin::Domains::Directory::Section#key`），不属于该客户可浏览分区的键返回 `404`；不再有实体索引路由，`/:cid/admin/entities/:id` 仍是条目列表。`Admin::Domains::Directory` 基于 `EntityAssociationGraph#all_entities` 为每个可浏览（非桥接）实体生成卡片，含本租户条目数与最近活动，并用 `EntityDomains::Layout` 分组：业务域按名称排序，未分组实体置后，没有可浏览实体的业务域不显示。`?sort=name|recent|entries` 对卡片排序；`?layout=grid|list` 切换卡片与列表行，两者的链接均保持在当前业务域的 URL 上。`Admin::Domains::DirectoryComponent` 先渲染所选业务域的概览卡片：顶部色条、按业务域颜色着色的图层图标块、名称与说明，以及条目总数与最近活动（`Section#entry_count` / `#last_entry_at`）；其下为工具栏，显示记录类型数量及排序与布局切换，再下为该业务域的卡片；列表布局在各行上方显示「名称／条目／最近更新」表头。本页不设独立搜索框，由侧栏搜索筛选业务域与记录类型；`Admin::Domains::EntityCardComponent` 渲染单个实体。没有业务域时，实体显示为一个不含概览卡片的分区。本页、「业务域」菜单及其侧栏面向客户的文案不使用「实体」一词：菜单显示「业务域」，记录页使用「记录类型」。本页对所有人只读（含所有者）：不显示跨业务域的汇总行，也不提供业务域操作，业务域只在所有者的维护页管理。仅所有者在页头及空状态中可见「创建实体」。侧栏（`EntitiesContributor`）不设概览链接，只在「业务领域」标题下列出业务域。每个业务域是可折叠节点，名称链接到 `/:cid/admin/domains/:key`，图标块按业务域颜色着色（`SidebarTone.domain`），其下按名称平铺所属实体；未分组实体归入「其他」，使用中性色收件箱图标。第一个业务域同时匹配 `/:cid/admin/domains`（`match_paths`），因此在落地页上它是选中且唯一展开的节点；点击其他业务域会打开该业务域页面，并只展开该业务域。在记录页上，展开的是该记录类型所在的业务域。没有业务域时，实体在「记录类型」标题下平铺。每个实体行带有与业务域页面卡片一致的小图标块：颜色、图标与首字母均来自与 `Admin::Domains::EntityCardComponent` 共用的 `EntityGlyph`；当前打开实体的图标块在强调色底板上改为白底。

| 路由 | 用途 |
| --- | --- |
| `GET .../entity_domains/new`、`POST .../entity_domains` | 新建业务域（名称、颜色、描述、成员） |
| `GET .../entity_domains/:id/edit`、`PATCH`／`DELETE .../entity_domains/:id` | 编辑或删除业务域 |
| `GET .../entities/:entity_id/domain_membership/edit`、`PATCH .../entities/:entity_id/domain_membership` | 将单个实体移至某业务域、「无业务域」，或（桥接实体）恢复「自动」 |

`...` 即 `/:cid/admin/maintenance`。

### 记录

`EntityEntry` 的 `data` 必须是 JSON 对象，拒绝畸形／标量及非输入键，包括 Calculated／Computed。`stamp_entity_version` 以 `entity.resolved_current_version.version_number` 覆盖客户端来源戳记，共享实体记录因此注明生效的客户头版本。

`EntityEntry.build_for(entity)` 为 Trailblazer Activity 生成带结构访问器的运行时子类。工厂跳过 `EntityEntry.column_names + %w[entity customer]` 中的标识，避免 JSON 访问器覆盖实际列或这两个关联。Calculated／Computed 访问器保留读取方法，不生成写入方法。匿名子类通过返回 `EntityEntry.model_name` 支持 Rails／I18n 错误处理，沿用父类表名及 STI 身份，并在初始化后绑定实体。`ModelGenerator` 生成 `EntityEntry.class_eval` 与 `attribute_accessor`；该列名冲突保护仅用于 `build_for`。`[]` / `[]=` 和 `method_missing` 是另外两条访问路径。`Admin::Maintenance::EntitiesController#show` 会渲染 `ModelGenerator` 与 `ContractGenerator` 的结果供查看。这两个类不属于 `CodeGenerators::GeneratorRegistry`。

`EntityEntryContract.build_for(entity, audience: nil, writable_slugs: nil)` 为所有带标识的结构属性声明契约属性。Calculated／Computed 及任意 `storage: "computed"` 属性使用 Reform 2.6 的确切选项 `writeable: false, parse: false`：不反序列化提交值，`sync`／`save` 从不调用其模型写入方法。非 nil 的 `writable_slugs` 对写入集合之外的属性施加相同限制，但保留读取方法、已有模型值及按受众生效的校验。`nil` 时普通属性仍可写，包括普通隐藏属性；可见性本身并非全局写入允许名单。`ContractGenerator.new(entity, writable_slugs: nil)` 通过 `schema_property_options` 生成相同选项，`property_accessor(name, validates: nil, **property_options)` 负责转发。只有 `presence` 与 `acceptance` 会拒绝空值：`build_validation_options` 为其他校验器附加 `allow_blank: true`，`ContractGenerator` 生成相同的源码（如 `numericality: { allow_blank: true }`），因此未设必填的字段可以留空，填写后才校验。参见[流程图运行时](flowchart-runtime)。

HTML 列表与 CSV 导出在确定结果条目后构建 `::Entities::EntryDisplay`（`Admin::EntitiesController#columns_for`），并传给 `Admin::Entities::ColumnsBuilder`；单元格与徽标读取 `EntryDisplay#text`，排序、搜索和筛选只读取各列的 `sql:`。派生值来自 `Entities::DerivedValues`：一次查询选出 `entity_entries.id` 与每个 `Entities::DerivedExpressions` 表达式，与列表排序及 `FlowchartRuntime::QueryBuilder` 使用同一 SQL，因此以数字保存父记录 ID 的关联行在各处计数一致。开头的 `::` 指向顶层服务命名空间，而非 `Admin::Entities`。创建条目后 303 跳转的浏览器 GET 走同一读取路径。派生值只用于显示，不会写入新条目的 `data`，也不会生成关联记录。

维护路由仍为 `index` 与 `destroy`，路径是 `/:customer_id/admin/maintenance/entities/:entity_id/entries`。浏览路径 `/:customer_id/admin/entities/:entity_id/entries` 提供 `new`、`create`、`show`、`edit`、`update`、`destroy`，以及集合 `DELETE .../entries/batch`（`batch_destroy`）；参见「管理端创建条目」下的「编辑条目」。两边都用 `Admin::EntityEntriesController`：按路径实体 ID 从当前客户或共享实体中查找，再同时按 `customer_id: current_customer.id` 与 `entity_id` 限定已有条目。实体及条目 ID 取自 `request.path_parameters`，请求正文／查询参数不能覆盖。页面提交与流程图 Activity 仍可创建条目；参见[页面渲染](page-rendering)及[流程图运行时](flowchart-runtime)。

`PATCH /:customer_id/admin/entities/:entity_id/index_setting` 更新 `EntityIndexSetting`。平台实体路由不嵌套记录。

### 管理端条目列表

`/:cid/admin/entities/:id` 在 `entity-entries-table` Turbo 框架中渲染 `Admin::Entities::EntriesTableComponent`，页头显示实体的配色图标（`attribute_group_icon_path`）。共享的 `Admin::ListToolbarComponent` 提供防抖搜索（`admin-table` 控制器，框架重绘后恢复焦点与已输入文字）、按 `Admin::Entities::FiltersBuilder` 生成的筛选下拉框，以及在有搜索或筛选时出现的**重置**。工具栏右侧插槽放置**列**选择器（`Admin::Entities::ColumnPickerComponent`，以 `data-turbo-frame="_top"` 提交，以便显示提示消息）和舒适／紧凑密度切换。可排序表头使用 `Admin::SortableHeaderComponent` 并设置 `aria-sort`；切换排序会回到第 1 页。

通过 `row-link` 控制器，点击行内任意位置即打开条目的完整详情页（`/:cid/admin/entities/:entity_id/entries/:id`，`_top` 链接）；复选框、按钮和文字选择不受影响。选中的行会高亮，并以批量操作栏（**清除**、**删除所选**）替换工具栏。行内编辑与删除图标默认弱化，悬停时才突出。移动端卡片以首个非 ID 列为标题，最多再显示三个字段。`Admin::PaginationComponent`（`summary: true`）始终显示结果数，并提供页码和每页行数菜单（`10 / 25 / 50 / 100`）。`per_page` 与 `density` 查询参数按客户和实体保存在 `EntityIndexSetting` 中。

**显示文本。** `Entities::EntryDisplay.new(entity:, entries:, customer_id:, audience:, viewer:)` 为列表、CSV 导出、条目详情页（管理员受众）和成员页面（成员受众）把保存值转为文本：空值显示“—”；下拉、单选和复选框选项显示其标签，多个以“, ”连接；`entity_entries` 引用显示被引用记录的显示字段（为空时为“未命名（#id）”，记录不存在时为“记录不存在（#id）”，显示字段对该受众不可见或该行不在访问者 `People::Ownership.scope` 内时为原始 ID）；计算字段和汇总字段显示其值；无选项的复选框或开关显示“是 / 否”；其他值（包括日期）按原样显示。重复标签只在下拉列表中编号，这里不编号。计算字段可与汇总字段一样选为列，并按其显示所用的同一表达式排序。成员页面通过 `EntryDisplay.prime!` 挂载显示对象，描述符中的 lambda 读取 `EntityEntry#display_text(slug)`；日期与金额保留原值，交由 `Member::Formatters` 格式化。

### 管理端创建条目

`/:cid/admin/entities/:id` 浏览页为有效、非桥接实体提供主操作**创建条目**，排在**导出 CSV**之前；表格为空或当前搜索无结果时也会显示。入口打开完整仪表板页面。

| 方法 | URL | 动作／辅助方法 |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/new` | `Admin::EntityEntriesController#new` / `new_admin_entity_entry_path(cid, entity)` |
| `POST` | `/:cid/admin/entities/:entity_id/entries` | `Admin::EntityEntriesController#create` / `admin_entity_entries_path(cid, entity)` |

POST 要求 `entry` 与 `entry[data]` 均为对象。缺失、标量、null 或数组包装返回 **400**；空 data 对象有效，会应用允许的默认值。控制器仅把内部 Hash／Parameters 交给 Activity；表单服务逐项读取允许的键，不使用 `permit!` 或无约束批量赋值。成功以 **303** 跳转至 `admin_entity_path(cid, entity)`，并显示本地化提示。输入边界、契约校验或保存失败时，以 **422** 渲染 `new`，复用同一个表单对象，保留本次输入及按字段归集的错误。GET 和失败重绘均使用仪表板布局；`Turbo-Frame` 为快速新增框架 `entity-quick-add-frame-<depth>` 的请求除外（见下文）。动作只提供 HTML；获准请求若协商 JSON 等不支持的响应格式，在执行写入前返回 **406**。

#### 生效结构、分组与默认值

`Entities::EntryForm.new(entity:, customer:, params: nil)` 在 `Current.set(customer: customer, shared_resources_mode: false)` 内重新读取实体。每次 POST 都重新解析定义；共享实体读取该客户的 `resolved_current_version` 覆盖，无覆盖时使用全局默认。结构、分组、默认值、校验及创建时版本戳记均取自这份生效定义；固定平台所有者访问其他客户 URL 时也遵循同一规则。

字段描述保留 `grouped_property_schema` 的分组顺序及组内字段顺序；空分组省略，未分组字段最后显示，标题使用本地化的**其他字段**。标签取 `display_label.presence || name`，帮助说明取 `description`；结构作者提供的文字经转义展示，不自动翻译。仅考虑管理员可见字段。Calculated、Computed、`storage: "computed"`、`readonly: true`、`EntityReference`、实际条目列及 `entity`／`customer` 均从控件、默认值和输入中排除。被排除的不支持字段不影响就绪状态。`available?` 只表示存在受支持的可写字段且无阻断项，不负责授权。

只有写入集合中的字段接收 `default_properties_json`。显式默认键优先于静态选项的 `default: true`；没有显式键时，这些标记提供单选或多选默认值。select／radio 若有多个默认选项且无显式默认键，则阻止创建。提交值按**键是否存在**覆盖默认值，保留 false、零、null、空字符串及空数组；未提交的键仍可使用默认值。`params: nil` 是 GET／默认值模式，`{}` 则是已提交的空对象。默认值与提交值共用形状及字面值校验。未知、隐藏、内部、只读、引用及派生键被丢弃，不会重新出现在表单中。

#### 支持的输入与校验

| 结构 `html_type` | 输入边界 |
|---|---|
| `text`, `search`, `tel`, `url`, `email`, `textarea` | JSON 安全标量；省略 `html_type` 时回退为 `text` |
| `number` | 非空时须符合有限十进制／指数形式；无效输入绝不转换成零 |
| `date` | 空值／null，或严格 `YYYY-MM-DD` 格式且年份为正的真实日期字符串 |
| `datetime-local` | 空值／null，或 `datetime-local` 输入提交的无时区本地时间字符串：`YYYY-MM-DDTHH:MM`，可带 `:SS` 及最多 3 位小数秒；日期须真实、时间须在有效范围内，不接受时区后缀。按提交原值保存 |
| `select`, `radio` | 静态 `config.options` 中的标量选项，或 `entity_entries` 来源的记录 ID |
| `multi-select` | 标量选项数组（静态或 `entity_entries`）；移除隐藏空字符串哨兵，保留显式空选项集合 |
| `checkbox`, `switch` | 无选项列表的布尔控件；隐藏 `"0"` 加选中时的 `"1"` |

标量仅含 null、字符串、布尔值、整数及有限浮点数。对象、上传文件、标量控件收到数组或嵌套数组，均产生按字段归集的形状错误。选项可为标量或 `{ "label", "value" }` 对象，值统一转为字符串；非空值必须匹配允许的选项**值**，不依赖是否配置 inclusion 校验器。支持 `entity_entries` 来源的下拉、单选和多选属性：选项来自面向管理员受众的 `Entities::ReferenceOptions`，条目契约会校验提交的每个 ID 都是本客户中目标实体的记录（`common.errors.dynamic.association_target_missing`）。目标实体已在回收站或其显示字段无法为管理员作标签时，该属性会阻止创建；复选框引用始终阻止创建。支持已物化的常量选项，但表单不实时查询常量。其他实体绑定、非 `entity_entries` 的动态选项源、带选项列表的复选框及不支持的控件（含文件、富文本、range、time、month、week），只要可见且本应可写，即使选填也会阻止创建。受支持字段仍在阻断提示旁展示，创建按钮禁用，POST 不写入记录。没有可写控件的结构同样不可用。

布尔真值接受 `true`、`1`、`"1"`、`"true"`、`"on"`；假值接受 `false`、`0`、`"0"`、`"false"`、`"off"`，分别规范化为 `"1"`／`"0"`。其他字面值（含空值／null）报错。数字／日期检查保留本次原始标量。Reform 负责配置的必填、范围、长度等校验，按固定 admin 受众的 `visibility` ∩ `validator_apply` 生效；省略的受众标记默认为启用。必填标记及 HTML 约束仅使用管理员适用的校验器。禁止写入的属性仍可能触发适用的契约校验；未渲染字段的错误继续显示在汇总中。

#### 主记录保存与展示

`Entities::Activities::CreateEntry.call(customer:, actor:, entity:, params:)` 返回 `[signal, ctx]`，语义为 `:success`、`:failure` 或 `:forbidden`；上下文含 `:form`、`:model`、已构建时的 `:contract` 及按字段归集的 `:errors`。Activity 重新授权目标，构建生效表单与 `EntityEntry.build_for` 模型，拒绝未就绪／形状／字面值错误，再以 `writable_slugs: form.writable_slugs` 构建管理员契约并校验，在 `EntityEntry.transaction(requires_new: true)` 内调用 `contract.save`。保存返回 false 时回滚，`RecordInvalid`／`RecordNotSaved` 汇入字段错误路径；没有错误详情时使用本地化的保存失败提示。客户与实体绑定自可信参数，`before_create` 记录生效版本。此路径只保存一条租户主条目，不写计算／派生字段，不创建桥接／Enrollment 行或扩展基础模型记录，也不执行 Page、流程图或 `ActivitySteps::SaveAll`。

`Admin::Entities::EntryFormComponent` 与 `EntryFieldComponent` 通过固定 `FormFields` 类映射消费字段描述。适配层用 `input_only: true` 及显式控件 ID 负责标签、帮助／错误和 ARIA；共用 base、radio、toggle 模板在该模式下转发输入属性。分组渲染为无边框 fieldset，标题带左侧强调线，分组间以分隔线隔开（不再每组一张卡片），与后台页面表单的分区一致；字段在手机上单列、`md` 起两列，textarea／radio／multi-select 跨两列。输入框为 `text-sm`、`rounded-lg`，手机上高 44px，`sm` 起 40px。警示汇总链接至可见字段；无效数字／日期／日期时间字面值改用文本控件重绘，被拒绝的 select 值保留为已转义且选中的错误选项，被拒绝的 radio 值显示在行内错误中，均不加入允许选项。创建／取消按钮在手机上占满宽度，`sm` 起并排；页头、表单及取消链接均以 `_top` 为目标，取消返回浏览页。平台文案使用两份 `admin_misc` 语言文件。页头换行规则参见[仪表板](dashboard)。

#### 从引用下拉框快速新增

创建条目表单中的单选引用字段（`config.options_source: "entity_entries"`）末项为**+ 新增**；后台页面渲染中基于实体的下拉框同样如此（见[页面渲染](page-rendering)）。选中后，`Admin::Entities::QuickAddDialogComponent` 打开被引用实体的创建条目表单。多选与单选按钮引用不提供该选项。

引用字段的 `EntryForm::Field` 带有 `reference`，即 `EntryForm::Reference`，包含被引用的 `entity`（引用无法为选项生成标签时为 nil）及 `label_field` 字段标识。`EntryForm#customer` 为 URL 租户。`EntryFormComponent.new(..., quick_add_depth:)` 为每个有实体的单选引用生成打开配置，取自 `QuickAddDialogComponent.opener(entity:, customer_id:, label_field:, depth:)`，返回 `{ url:, label:, title:, dialog: }`。`url` 为 `new_admin_entity_entry_path(cid, entity, label_field:)`，`dialog` 为出口选择器 `#entity-quick-add-dialog-<depth>`。组件在 `<form>` 之后渲染该层对话框，不放在表单内，因为对话框内还会承载另一个表单。`new.html.erb` 传入 `quick_add_depth: 0`；depth 为 nil 时既无选项也无对话框。

对话框按被引用实体逐层嵌套。第 N 层的 id 为 `entity-quick-add-dialog-N`、`entity-quick-add-title-N` 与 `entity-quick-add-frame-N`。`QuickAddDialogComponent.depth_of(turbo_frame_request_id)` 从框架 id 读出 N；其他框架、无后缀 id 或超过 `MAX_DEPTH`（10）时返回 nil。对快速新增框架的请求，`new` 与失败的 `create` 不带布局渲染 `quick_add`，置于 `turbo-frame#entity-quick-add-frame-N` 内。该视图渲染同一个 `EntryFormComponent`，设 `frame: true`、`quick_add_depth: N + 1` 与 `id_prefix: "entry_quick_add_N"`，被引用表单自身的引用下拉框即打开下一层对话框。该前缀替换控件、标签、帮助、错误及错误摘要标题 id 中的 `entry`（`EntryFieldComponent.field_id(slug, prefix)`），嵌套表单不会与页面上已有的 id 重复。表单留在本层框架内，取消改为关闭本层的按钮（`entity-quick-add-dialog#close`）。超过 `MAX_DEPTH` 时 `opener` 返回 nil，最深一层不再提供该选项。创建 URL 保留 `label_field`。框架内 `create` 成功时不再重定向，而是在同层框架中渲染 `quick_add_created`：带 `data-entry-id` 与 `data-entry-label` 的 `role="status"` 标记。本层对话框控制器响应该标记，关闭对话框，并把记录交给上一层的下拉框。标签遵循 `Entities::ReferenceLabels`：显示字段可为管理员作标签时使用该字段；已有其他记录显示相同文本时编号为“标签（#id）”；否则为“未命名（#id）”。授权、租户范围、`CreateEntry` 与校验均与完整页面相同。

#### 编辑条目

条目列表每行在删除图标前有**编辑**图标；条目详情页标题栏提供**删除**（`turbo_method: :delete` 链接，确认提示与行内图标一致）和主操作**编辑**。只有有效、非桥接的实体才提供编辑：`admin/entities/show.html.erb` 仅在此时向 `EntriesTableComponent` 传入 `edit_path:`，`admin/entity_entries/show.html.erb` 也仅在此时添加编辑操作，因此桥接条目的详情页只有删除。

**条目详情页。** `GET /:cid/admin/entities/:entity_id/entries/:id` 渲染完整仪表板页面（不使用抽屉或 Turbo frame）：`AdminPageComponent` 显示面包屑**业务域 › 实体名 › 条目 #id**、实体图标与颜色色块，以及上述删除／编辑操作。正文为 `Admin::Entities::EntryDetailComponent.new(entity:, entry:, display:, associations:, writable:)`，由主栏和侧栏组成（`lg:` 18rem，`xl:` 20rem；`lg` 以下上下堆叠）。主栏每个属性分组一张卡片，其后每个关联一张卡片（见下文**关联记录**），按 `grouped_property_schema` 顺序排列，未分组属性置于最后的**其他字段**；没有属性的分组不显示。卡片标题显示分组颜色上的分组图标、分组名称和字段数；正文为两列描述列表（手机为单列），`textarea` 与 `multi-select` 值横跨两列并保留换行。取值来自 `Entities::EntryDisplay`（管理员受众），空值显示为弱化的“—”。侧栏在 `lg` 及以上吸顶显示，包含**记录信息**（ID、实体、创建与更新时间）；卡片（分组加关联）不少于两张时另有**分组导航**页内锚点链接（`lg` 及以上）。实体没有属性时显示空状态卡片。

| 方法 | URL | Action／helper |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/:id/edit` | `Admin::EntityEntriesController#edit` / `edit_admin_entity_entry_path(cid, entity, entry)` |
| `PATCH` | `/:cid/admin/entities/:entity_id/entries/:id` | `Admin::EntityEntriesController#update` / `admin_entity_entry_path(cid, entity, entry)` |

`edit.html.erb` 与 `new` 共用仪表盘外壳和 `EntryFormComponent`，传入 `http_method: :patch`（组件默认 `:post`），提交按钮文案随之变为**保存更改**／**正在保存…**。请求体形状规则与 POST 相同（`entry[data]` 缺失或不是对象返回 **400**；JSON 返回 **406**）。成功后以 **303** 重定向到 `admin_entity_path(cid, entity)` 并显示本地化提示；任何失败都以 **422** 渲染 `edit`，保留本次输入与按字段归集的错误。编辑与创建一样要求实体有效且非桥接；条目按 `customer_id: current_customer.id` 与路径 `entity_id` 限定，其他租户或其他实体的条目返回 **404**。

`Entities::EntryForm.new(entity:, customer:, entry:, params: nil)` 用于编辑已有记录（`persisted?` 为 true）。条目已保存的 `data`（去掉 nil 值）取代 `default_properties_json` 与选项默认值。GET 预填会为展示而规范化保存值（布尔值转为 `"1"`／`"0"`，无效数字／日期字面值以文本显示），但丢弃其字段错误，只保留就绪性错误：保存值在管理员提交时才校验，已不在选项中的保存值显示为空。PATCH 时，提交中省略的键保留已保存值，而不是默认值。

`Entities::Activities::UpdateEntry.call(customer:, actor:, entity:, entry:, params:)` 与 `CreateEntry` 一样返回 `[signal, ctx]`。授权、校验、保存与错误归集步骤通过 `Entities::Activities::EntryWriter` 共用；另加 `find_entry`（条目须属于 URL 客户及该实体，否则为 `:forbidden`），并以 `writable_slugs: form.writable_slugs` 的管理员契约保存 `EntityEntry.build_for` 记录。隐藏、只读及派生字段不在写入集合内，保存值不变；`entity_version_number` 是创建时的戳记，不会改变。兜底错误为 `errors.update_failed`。模型错误（例如 `validate_data_keys` 拒绝已不在结构中的保存键）显示在错误摘要中。

#### 关联记录

条目所属实体声明的每个关联（`associations_list`，仅源端）在条目详情页属性分组下方各占一张卡片，列出链接本条目的桥接行，例如学生的选课记录及其状态与成绩。`Entities::EntryAssociations.new(entity:, customer:)` 负责解析关联：`#all` 为桥接实体（`category: :bridge`、有效、属于本客户或共享）与目标实体（有效、非桥接）均存在的每个关联返回一个 `Association`。`Association` 含 `bridge`、`target`、`source_slug`（桥接实体指回本实体的 `EntityReference`）和 `columns`（桥接实体中管理员受众可见的其余属性，目标引用在前）。`#find(bridge_id)` 查找单个关联。`#rows(association, entry)` 限定为当前客户中 `source_slug` 值（按文本比较）等于条目 ID 的桥接条目，按创建时间升序。`#sections(entry)` 另附这些行的 `EntryDisplay` 及仍存在的目标记录 ID。

`Admin::Entities::AssociationSectionComponent` 渲染卡片：标题为目标实体的图标、颜色与名称，并显示条目数。`sm` 及以上为表格，手机为堆叠卡片，首列为关联记录。引用的记录仍存在时链接到其详情页；记录不存在时显示“记录不存在（#id）”。锚点为 `entry-association-<bridge_id>`，同时列入**分组导航**。实体可写（有效、非桥接）时，卡片标题栏提供**添加**，每行提供**编辑**与**删除**（需确认）。被关联实体自身的条目不显示反向卡片。

| 方法 | URL | 动作／辅助方法 |
|---|---|---|
| `GET` | `/:cid/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries/new` | `Admin::EntityAssociationEntriesController#new` / `new_admin_entity_entry_association_entry_path(cid, entity, entry, bridge_id)` |
| `POST` | `/:cid/admin/entities/:entity_id/entries/:entry_id/associations/:association_id/entries` | `#create` / `admin_entity_entry_association_entries_path(...)` |
| `GET` | `…/associations/:association_id/entries/:id/edit` | `#edit` / `edit_admin_entity_entry_association_entry_path(..., row)` |
| `PATCH` | `…/associations/:association_id/entries/:id` | `#update` / `admin_entity_entry_association_entry_path(..., row)` |
| `DELETE` | `…/associations/:association_id/entries/:id` | `#destroy` |

`:association_id` 为桥接实体 ID。每个动作都要求：当前客户（或共享）的有效、非桥接实体；该实体在当前客户中的条目；以及该实体声明的关联。桥接行还须属于 `#rows(association, entry)`。否则返回 **404**；路径由 `RouteAuthorization` 按管理员路径守卫。

**添加一条或多条。** `new` 渲染 `Admin::Entities::AssociationEntriesFormComponent`：若干行卡片（`AssociationEntryRowComponent`），每行是一个桥接 `EntryForm`，字段以 `rows[<index>][<slug>]` 提交。空白行模板（`rows[__ROW__]…`）供 `association-rows` Stimulus 控制器添加行（**再添加一条**）和移除行（至少保留一行），并重新编号行标题（`row_heading` 模板以 value 传入）。目标引用为下拉框，带**+ 新增**（比表单高一层的快速新增对话框：完整页面上为第 0 层，条目页对话框内为第 1 层）。`create` 调用 `Entities::Activities::CreateAssociationEntries.call(customer:, actor:, entity:, entry:, association_id:, rows:)`，接受 1 至 `MAX_ROWS`（50）行。每行先经表单边界检查，再经管理员契约校验；所有行都会校验，以便一次显示全部错误，并在同一事务中全部保存或全部不保存。成功时以 **303** 重定向到条目详情页的关联锚点，并显示 `association_entries.created`（按数量变化）。失败时以 **422** 重新渲染，基础错误显示在摘要中，各行错误显示在行内。`rows` 不是对象时返回 **400**。

**桥接行表单。** `Entities::EntryForm.new(..., links: { slug => id })` 构建桥接行表单。`links` 中的参与方引用从不显示，始终按给定值写入，因此提交中伪造的反向引用会被忽略。桥接实体中其余来源为 `entity_entries` 的 `EntityReference` 属性显示为引用下拉框。不传 `links` 时，参与方引用仍像以前一样排除。`links` 计入 `writable_slugs`，但不计入 `available?`。

**编辑／删除。** `edit` 与 `update` 复用 `EntryFormComponent`（PATCH、`entry[data]`），调用 `Entities::Activities::UpdateAssociationEntry.call(customer:, actor:, entity:, entry:, association_id:, row:, params:)`；它通过 `Entities::Activities::AssociationEntryWriter` 共用 `EntryWriter` 的校验、保存与错误归集步骤。隐藏的桥接字段保留原值。`destroy` 调用 `Entities::DeleteEntry`。两者均返回关联锚点并显示翻译后的提示。

**对话框内操作。** 实体可写且有关联时，`EntryDetailComponent` 渲染 `QuickAddDialogComponent.new(depth: 0)`，每张卡片挂载 `association-dialog` Stimulus 控制器，并以该对话框为 outlet。**添加**与**编辑**在对话框中打开表单而不跳转，标题为 `association_entries.new_title`／`edit_title`。链接保留完整页面的 `href`，因此在新标签页中打开，或页面没有对话框时，仍显示完整页面。链接带有 `data-turbo-prefetch="false"`：Turbo 会把悬停时预取的响应用于之后同一 URL 的任何 GET 请求，预取到的完整页面会顶替对话框的 frame 请求，使对话框空白。`Turbo-Frame` 请求头为 `entity-quick-add-frame-<depth>` 的请求得到不带布局的 `new_dialog`／`edit_dialog` 视图：表单位于该 frame 内并提交到其中，**取消**关闭对话框。保存失败时在 frame 内以 **422** 重新渲染。保存成功时设置 flash 提示并渲染 `saved_dialog`，其中的 `created` 标记通知对话框关闭；随后控制器以 `Turbo.visit(..., { action: "replace" })` 重新加载条目页并滚动回该卡片。`destroy` 不经对话框，仍照常重定向。

可复用控件 API 及适配层职责见[页面渲染](page-rendering)。

### 控制器与授权

`Admin::Maintenance::EntitiesController` 引入 `SharedResourceMode`。`definition_scope` 在平台前缀上是 `Entity.shared`，在租户路径上是 `Entity.accessible`（并预加载客户头）。创建时调用 `apply_create_identity!`（平台前缀 `customer_id` 为 NULL，否则为当前客户），并用 `Billing::Quota::Guard` 检查配额项 `"entity"`；共享资源创建跳过配额。

允许的参数：

- 定义正文，始终允许：`icon`、`color`、`description`、`default_properties`、`property_schema`、`attribute_groups`、`referenced_template`。
- 身份，仅当本次保存不是租户覆盖：`name`、`display_label`、`extended_model`、`associations`。

`template_fields` 对 `PageLayoutTemplates.find` 的结果运行 `TemplateFieldExtractor`。`base_model_fields` 返回 `EntityDefinitions::Capabilities.base_model_fields(customer_id, class_name)`：仅当 `ExtendableModelRegistry.for_customer` 允许该类且其为 `ApplicationRecord` 时返回列名。`create_entity` 保留同样的列（`attribute.reserved_by_base_model`）。集合路由还包括回收站与清空回收站。

将实体移入回收站时，会在同一事务中、在状态变更之前将其已上线表单下线：`soft_delete` 对每个 `Page.for_entity(id).launched` 调用 `take_offline!`，共享实体即覆盖所有租户的表单。`Page.for_entity` 以文本比较存储的绑定，因此 JSON 数字或字符串均能匹配。`forms_taken_offline` 记录下线数量，数量大于零时 `destroy` 在提示后追加 `maint_core.flash.entities.forms_taken_offline`。任一表单无法下线时，移入回收站整体回滚。恢复实体不会重新上线表单：`EntityRestorationsController#restored_notice` 会追加 `maint_core.flash.entity_restorations.offline_forms`，列出该租户中绑定此实体且仍处于下线状态的表单名称。

租户维护实体要求 admin／owner；平台前缀另要求固定所有者资格及实际外层 CID `81721200`，member 均不能访问。

浏览页 new／create／edit／update 继承 `ApplicationController` 的 `TenantContext`、`RouteAuthorization`、CanCan 及 MFA 守卫。GET 检查路由读取权限，POST 检查创建权限，PATCH 检查更新权限。匿名用户须登录；成员及其他租户管理员由既有处理器拒绝。创建目标须为当前客户自有或共享实体，且有效、非桥接；缺失、外租户、停用及桥接目标返回 **404**。直接调用 `CreateEntry` 另要求客户已持久化、`actor.admin_or_owner?`，以及同客户归属或固定 `actor.platform_owner?`；不可访问／停用／桥接实体返回 `:forbidden`。即使所有者跨租户访问，全部写入仍以 URL 客户为准。正文／查询参数中的客户 ID、实体 ID、受众及来源戳记不能替代可信绑定。创建与编辑仅挂在浏览嵌套路由，不挂在维护或平台嵌套路由。

### Stimulus

`entity_form_controller.js`（`entity-form`）是 `app/views/admin/maintenance/entities/_form.html.erb` 上的编排器。它把工作交给 `app/javascript/controllers/entity_form/` 下的 `TypeManager`、`ValidatorManager`、`TemplateBuilder`、`SchemaManager`、`ModalManager`、`ConstantsManager`、`ReferenceManager`、`AttributeManager`、`AssociationManager`、`GroupManager`、`DndManager`、`ComputedManager`。`ReferenceManager`：“使用实体记录”模式，只加载一次 `entities.json`，仅提供可作标签的显示字段，校验两个下拉框，仅在目标为人员实体时显示归属人开关，并返回 `{ options_source, entity_id, label_field }`，开关打开时另加 `owner: true`。提交时 `collectAttributes` 填入控制器允许的隐藏 JSON 字段。

基础模型下拉框的 `required` 属性由服务端渲染。选择变化时，`entity-form#extendedModelChanged` 请求 `base_model_fields`，并在属性编辑器中将这些列名设为保留字段。

`association_rows_controller.js`（`association-rows`）在关联的**添加**表单中添加和移除桥接行（见**关联记录**）。`add` 以下一个 `rows[<index>]` 键克隆行模板（`__ROW__` 只在属性中替换，选项文字保持原样）并聚焦首个字段；`remove` 至少保留一行；`refresh` 按 `heading` value（默认 `Entry {number}`）重新编号行标题，且仅在多于一行时显示移除按钮。

`association_dialog_controller.js`（`association-dialog`）挂载在每张可写的关联卡片上。`open` 把所点链接的 `href` 以 `title` action 参数为标题载入 `entity-quick-add-dialog` outlet；没有 outlet 时不作处理，链接照常跳转。对话框报告保存后，`reload` 以 `Turbo.visit(..., { action: "replace" })` 重新访问当前路径与查询串，并在下一次 `turbo:load` 时把卡片滚动到可见位置。没有 Turbo 时退回 `location.reload()`。

`entity_selector_controller.js` 会查找同级的 `page-canvas` 控制器。现行页面编辑器是 `page-builder`，见 [页面构建器](page-builder)。

## 需要特别注意

### 路由审计：定义、提升及删除不变量

生成器／表单使用前，定义 JSON 检查语法、数组／对象容器、对象项、必需 slug 及配置／引用形状。扩展写入要求所有者批准的注册表及具体 ActiveRecord 子类，不能仅凭常量名。复制保留关联显示字段，不复制桥接身份。删除共享目标检查租户引用方；源／桥接软删除及恢复原子执行，失败如实反馈。

`Entities::DeleteEntry.call(entry:)` 返回 success／entry／errors。控制器按客户与实体限定记录，并将批量删除包在事务中；模型置空模块日志链接，仅删除同租户引用该参与者的桥接行，以访问集合限制循环级联，不删除其他参与者。CSV 标题／文本防止公式前缀，数值保持数值。关联导航可处理循环；见[仪表板](dashboard)、[共享资源](shared-resources)、[页面渲染](page-rendering)。

:::note
2026 年 10 月 11 日，AI／实体定义／语音转文字／LLM 定向测试在 `storage/ai_verify.sqlite3`、结构版本 `20261011190000` 上通过：1,666 个用例，零失败。覆盖部分字段规范化、无效 slug 严格回滚、版本来源、确认快照及配额快照不变性。核心版本提升／删除、CSV 和其他生命周期请求不在本次范围内。完整范围与命令见 `docs/audits/2026-10-11-ai-stt-targeted-verification.md`。
:::

:::attention
定义及记录来源通过 `resolved_current_version` 读取；`current_version` 仍是全局头。既有客户分叉保持固定，直到 `reset_customer_override!`。
:::

:::attention
`Admin::Maintenance::EntitiesController` 把 `associations` 当作身份。共享实体在租户路径上的保存不能改关联、名称、显示标签或 `extended_model`。`Entity#shared_entity_has_no_associations` 也会拒绝共享行上的关联。桥接实体和 `Computed` 字段存在于客户自有实体。`EntitySchemaValidation` 在非 `customer_owned?` 时拒绝计算字段。
:::

:::attention
`Entities::ComputedCompiler.compile` 返回子查询字符串或 `nil`，不抛异常。结构类型是 `"Computed"`，没有 rollup 这个类型。`EntityEntry#validate_data_keys` 在 `data` 含有这些字段时拒绝保存；需要聚合结果时使用编译出的 SQL（`compile_all`）。
:::

:::attention
不要到 `/admin/maintenance/platform/entities` 下找记录。路由注释和控制器挂载把 `EntityEntry` 留在租户侧。`find_entry` 始终加上 `customer_id: current_customer.id`。销毁共享实体只在 `:destroy` 上走 `guard_shared_global_writes`；租户路径仍可编辑定义正文。
:::

## 关键代码

```ruby
# app/models/entity.rb
  def reload_definition_from_head!
    payload = resolved_current_version&.content&.payload
    snap = payload.present? ? JSON.parse(payload) : {}
    self.icon                = snap.fetch("icon", "custom")
    self.color               = snap.fetch("color", "#6366f1")
    self.description         = snap["description"]
    self.referenced_template = snap["referenced_template"]
    # Use the *_json= setters so json_attribute's memoized parse is cleared.
    self.property_schema_json    = snap["property_schema"]    || []
    self.default_properties_json = snap["default_properties"] || {}
    self.associations_json       = snap["associations"]       || []
    self.attribute_groups_json   = snap["attribute_groups"]   || []
    # The loaded state is the baseline for Dirty tracking, so a subsequent edit
    # is diffed against the head content (BridgeEntityManagement relies on this).
    clear_changes_information if persisted?
    self
  end
```

```ruby
# app/controllers/admin/maintenance/entities_controller.rb
    DEFINITION_KEYS = %i[icon color description default_properties property_schema
                         attribute_groups referenced_template].freeze
    IDENTITY_KEYS = %i[name display_label extended_model associations].freeze

    def permitted_entity_keys
      return DEFINITION_KEYS if tenant_override?(@entity)

      DEFINITION_KEYS + IDENTITY_KEYS
    end
```

```ruby
# app/models/entity_entry.rb
  def stamp_entity_version
    self.entity_version_number = entity&.resolved_current_version&.version_number
  end
```

```ruby
# app/services/entities/activities/create_entry.rb
        contract = ctx[:contract] = EntityEntryContract.build_for(
          form.entity, audience: "admin", writable_slugs: form.writable_slugs
        ).new(model)
        contract.validate(form.filtered_input)
```

```ruby
# app/services/entities/computed_compiler.rb
    FUNCTIONS = %w[avg sum count min max].freeze
    FILTER_OPS = %w[= != > >= < <=].freeze
    NUMERIC_HTML_TYPES = %w[number range].freeze
    MAX_PRECISION = 6
```

```ruby
# app/models/concerns/versionable.rb
  def resolved_current_version(cid = Current.customer_id)
    line_cid = override_customer_id(cid)
    return current_version if line_cid.nil?
    customer_head_for(line_cid)&.current_version || current_version
  end
```

相关页面：[共享资源](shared-resources)、[页面构建器](page-builder)、[流程图构建器](flowchart-builder)、[常量](constants)、[操作 API](operations-api)。
