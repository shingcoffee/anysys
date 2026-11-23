---
title: "人员关联"
summary: "人员实体的条目如何关联到同租户的一个用户账户，归属种类如何决定各受众能看到哪些行，以及关联后在管理端和会员端带来的能力。"
---

## 概要

**人员实体**指 `extended_model` 为 `EntityDefinitions::Capabilities::PERSON_MODEL`（`Authentication::User`）的实体，如学生、患者、志愿者。判断方法为 `Entity#person?`；桥接实体一律不算。一个业务域最多只有一个人员实体（见[操作 API](operations-api)）。

人员实体的每个条目可通过可空列 `entity_entries.user_id` 关联到同租户的**一个**用户。用户是登录身份（凭据、角色、MFA），条目是业务档案。关联是可选的，从不登录的人同样可以记录。

身份字段（`People::IDENTITY_KEYS`：`first_name`、`last_name`、`email`）任一时刻只存在一处：

| 条目状态 | 身份字段所在 |
|---|---|
| 未关联 | 条目的 `data`，使用保留键。扩展基础模型的实体不能声明其列，因此不会与属性标识冲突。 |
| 已关联 | 只在 `User` 上；条目中的这些键被移除。 |
| 再次取消关联 | 用户当前的值复制回条目。 |

关联不会改变角色。`People::Ownership` 也靠这条关联找出访问者自己的人员行：会员界面、引用下拉框与表单提交都通过已关联条目绑定。公开注册会写入未关联的人员条目和一条待认领记录；首次确认（或之后的登录）完成认领并记录 `person.claimed`。人员实体表单上的身份字段作为 `ctx[:identity]` 进入流程图——见[页面构建器](page-builder)与[受众流程](audience-flows)。同一动作如何为每种受众提供独立页面与流程图，见[受众流程](audience-flows)。

## 流程

1. 管理员打开人员实体的 `/:customer_id/admin/entities/:entity_id/entries/:id`。`Admin::Entities::EntryDetailComponent` 在侧栏首位渲染 `Admin::Entities::PersonLinkComponent`（账户卡片）。
2. 未关联且可写：**关联用户账户**打开 `person-link-picker` 组合框。输入防抖 250 ms、至少两个字符，请求 `GET …/entries/:entry_id/person_link/candidates?q=`，返回 `{ "users": [{ "id", "name", "email" }] }`。
3. 选中用户后在卡片内确认；**关联**将 `user_id` 提交到 `POST …/entries/:entry_id/person_link`。
4. `People::Link.link!` 在客户行锁内执行 `People::Activities::Link`：校验 `People::Contracts::Link`，写入 `user_id`，从 `data` 移除身份键，记录 `person.linked`；控制器带提示重定向回条目页。
5. 已关联：**取消关联**（`DELETE …/person_link`，Turbo 确认）执行 `People::Activities::Unlink`，将用户身份复制回 `data`，清空 `user_id`，记录 `person.unlinked`。
6. 会员在 `/:customer_id/member/` 下打开人员或归属实体的界面，`People::Ownership.scope` 只列出归属于本人的行。同租户管理员可 GET 同一界面，仍然只能看到关联到自己的行（scope 始终使用会员受众与 `current_user`）。

## 实现

**表结构。**`entity_entries.user_id` 引用 `users`，`on_delete: :nullify`。`idx_entity_entries_person_link` 在 `user_id IS NOT NULL` 时对 `(entity_id, user_id)` 唯一：同一用户在同一实体下最多关联一次，但可被不同人员实体的条目关联。`(customer_id, user_id)` 建索引供会员查询。SQLite 的复合置空外键会把 `customer_id` 一并置空，因此同租户规则由契约保证，而非复合外键。

**模型。**`EntityEntry belongs_to :user`（可选）及 `#linked?`；`Authentication::User has_many :person_entries`；删除用户前先对每个已关联条目执行 `People::Link.detach!`，条目与取消关联时一样取回身份（无操作管理员，故不记审计）。`EntityEntry#validate_data_keys` 对人员条目放行 `People::IDENTITY_KEYS`，未关联条目的身份在之后带校验的保存中得以保留。

**契约。**`People::Contracts::Link` 要求：人员实体；条目未关联；用户未关联到同一实体的其他条目；用户按 `id`、条目的 `customer_id` 与 `status: :active` 查得。不存在、属于其他租户、已停用三种情况共用 `people.errors.user_unavailable`，外部 id 无法借此确认用户是否存在。

**活动。**`People::Activities::Link` 与 `Unlink` 为 Trailblazer railway，在 `Customer#with_lock(requires_new: true)` 内执行：重新加载条目，以 `validate: false` 保存，并通过 `Authentication::AuditLog.record` 记录审计（`entry_id`、`entity_id`、`linked_user_id`）。并发的重复关联触发唯一索引时，返回失败结果与 `people.errors.user_already_linked`。

**服务。**`People::Link` 是唯一公开写入入口：`link!(entry:, user_id:, actor:)` 与 `unlink!(entry:, actor:)` 返回含 `success?`、`entry` 及已翻译 `errors` 的结果；`candidates(entry:, query:, limit: 20)` 返回条目所属租户中未关联到该实体的有效用户，按姓名或邮箱不区分大小写匹配（`sanitize_sql_like` 配合 `ESCAPE '\'`）。会员行范围在 `People::Ownership` 上，不在 `Link` 上。

**控制器。**`Admin::EntityEntryPersonLinksController`（`create`、`destroy`、`candidates`）属管理端，由 `RouteAuthorization`（`admin_or_owner?`）把守。实体从 `Entity.where(customer_id: current_customer.id).or(Entity.shared)` 加载，非 `person?` 返回 404（写操作还要求实体有效），条目按 `customer_id` 与 `entity_id` 加载。候选接口仅支持 JSON。重定向使用 `303 See Other`；提示文案为 `admin_misc.person_link.flash.*`。

**管理端列表。**人员实体由 `Admin::Entities::ColumnsBuilder` 在时间戳之前加一列**关联账户**。单元格显示 `admin_misc.entities.columns.linked_account_value`（姓名与邮箱）；排序和搜索通过子查询读取用户邮箱，并要求 `users.customer_id = entity_entries.customer_id`。`Admin::EntitiesController#show` 预加载 `:user`。

**会员界面。**`Member::EntitySurfaceBuilder` 用 `People::Ownership.scope(..., audience: "member")` 限定每个实体界面。`Member::SurfacesController` 调用 `allow_admin_member_preview!`。详情页经 `authorize_surface_record!` 复核：`EntityEntry` 只需匹配 `current_user.customer_id`（归属行本身没有 `user_id`）；其他记录仍走 `authorize_owned!`。见[会员与公开页面](member-and-public)。

### 归属种类与行范围

`People::Ownership` 回答实体属于哪一种、访问者能看到哪些行。流程图运行时从不调用它：名额检查必须统计全部报名。

`describe(entity)` 返回 `Descriptor(kind:, owner:)`。`kind` 为 `:person`、`:owned`、`:private`、`:open` 之一。`owner` 为 `Owner(slug:, person_entity_id:)` 或 nil。`kind(entity)` 与 `owner_reference(entity)` 是简写。

| 种类 | 判定 | `owner_reference` |
|---|---|---|
| `:person` | `entity.person?` | nil |
| `:owned` | 有一个引用标了 `"owner": true`，或恰好一个引用指向人员实体 | 该引用的标识与目标 id |
| `:private` | 两个及以上人员引用且均未标记 | nil |
| `:open` | 没有人员引用 | nil |

**引用属性**指 `type: "EntityReference"`（桥接两端；目标在 `entity_id`）或 `entity_entries` 下拉（目标在 `config.entity_id`）。`person_references` 用 `Entity.unscoped` 加载目标，范围是该实体所属租户或共享（`customer_id` 为 NULL），并过滤人员模型。**已进回收站**的人员目标仍计入：把 Student 移入回收站不得把 Enrollment 变成 `:open`。

归属标记只允许加在指向人员实体的引用上，且每个实体最多一个。人员实体、桥接实体、关联附加属性、非引用、非人员目标都不能带它。编辑器不为桥接实体提供开关；Enrollment 因 `bridge_property_schema` 已有单一人员引用（`student`）而为 `:owned`。编辑器开关见[实体构建器](entity-builder)，`create_entity`／`update_entity` 上的 `owner` 见[操作 API](operations-api)。

`scope(entity, viewer:, audience:, customer_id:)` 始终从 `EntityEntry.where(customer_id:, entity_id:)` 起步。其他租户的行不会出现。

| 种类 | admin | member | public |
|---|---|---|---|
| person | 本租户全部行 | `user_id = viewer.id` 的行 | 无 |
| owned | 本租户全部行 | 归属字段值（存成 `"12"` 或 `12`）等于访问者该人员实体已关联条目的行 | 无 |
| private | 本租户全部行 | 无 | 无 |
| open | 本租户全部行 | 本租户全部行 | 本租户全部行 |

失败即关闭：会员受众下 `viewer` 为 nil、访问者属于其他租户、未知受众字符串、会员没有已关联人员条目，对 person／owned／private 一律返回空。归属行用 `CAST(json_extract(data, '$.<slug>') AS TEXT) = ?` 匹配，slug 先经 `JsonPathValidator.safe_json_path!` 校验。

`reachable_ids(entity, ids, ...)` 返回范围内的子集（字符串），忽略非数字 id。`person_entry_ids(user)` 返回 `{ "<人员实体 id>" => 条目 id }`，只含 `user.customer_id` 内的条目；`person_entry_id(user, person_entity_id)` 是对应查找。

凡是列出另一实体行的输出都走 `scope`：`Entities::ReferenceOptions`（下拉框，传入 `viewer:`）、`Entities::EntryDisplay`（范围外的标签只显示裸 id，不泄露显示字段）、`CompositePageRenderer` 列表、`PageContentGenerator::DynamicOptionsResolver` 查询列表，以及 `Member::EntitySurfaceBuilder`。`FlowchartRuntime::QueryBuilder.for_entity` 接受可选 `scope:`；流程图调用方从不传入，因此查询步骤看到本租户全部行。

### 可信上下文

`Pages::PublicSubmission` 仅为同租户访问者把 `person_entry_ids` 写入 `ctx[:current_person_ids]`。其他租户的已登录用户在此视为公开，其本租户人员条目不会进入本次运行。匿名与未关联访问者得到 `{}`。

`FlowchartRuntime::CurrentUser.load` 返回冻结 Hash `{ id, email, name, role, person_entries }`。`person_entries` 即同一张映射。

`find_model` 在 `findBy: current_person` 时，经 `FlowchartRuntime::Entries.find_current_person(ctx)` 加载访问者在绑定人员实体上的已关联条目。只读 `ctx[:current_person_ids]`，从不读 params。绑定实体不是人员实体、没有关联、或条目已不存在时，失败为 `record_not_found`。见[流程图运行时](flowchart-runtime)与[流程图步骤动作](flowchart-step-actions)。

### 待认领

公开的 `register_member` 会在 `people_pending_claims` 写入一行，以便在任意设备上确认或登录都能完成交接。`People::PendingClaim` 很薄（`self.table_name = "people_pending_claims"`，因为 `People` 没有表前缀）：`customer_id`（租户隔离）、`user_id`（唯一，每用户一条，外键级联删除）、`entity_entry_id`（可空，删除时置空）、`continuation`（JSON）、`created_user`（布尔，默认 false）、`expires_at`（自 `People::Claim::TTL` 起 3 天）。

`People::Claim.record!(user:, entry: nil, continuation: nil, created_user:)` 按 `user_id` 更新或插入，并刷新 `expires_at`。新访客带上学生条目且 `created_user: true`；这条认领不会被替换，同一地址再次提交既不会摘掉其条目，也不会改动其续接。本租户已确认的有效会员只记续接（`entry` 为 nil，`created_user: false`）。

`People::Claim.complete!(user)` 在用户所属客户行锁内运行 `People::Activities::CompleteClaim`：

1. 按 `user_id` 查找认领。没有则返回 nil。
2. 已过期，或 `claim.customer_id != user.customer_id` 时失败即关闭。过期行留给定时任务；租户不一致时既不关联也不消费。
3. 条目仍在、尚未关联且属于用户租户时，调用 `People::Link.link!(entry:, user_id:, actor: user, event: "person.claimed")`。条目已被别人关联则跳过（不报错）。条目已删除（外键置空）仍返回续接路径。
4. 删除认领行。
5. 用续接里的 `action_key` 与 `prefill`，按**用户自己的** `customer_id` 构建 `Pages::ActionLink.path`。签名续接从不携带 URL 或客户编号，因此令牌不能指向其他租户的操作。载荷无效或缺失则返回 nil。

`People::ExpirePendingClaimsJob`（`config/recurring.yml` 中的 `people_expire_pending_claims`，生产环境每天 5:00）按 500 条一批处理过期认领，每条都在该客户行锁内。它删除认领行。对仍未确认的 `created_user` 认领，还会销毁未关联的条目和该用户。之后已确认的用户、以及已经关联的条目予以保留。不会触碰其他租户的行。

**界面。**`PersonLinkComponent` 有三种状态：未关联、已关联（用户停用时显示“已停用”徽标）与只读（实体无效或为桥接）。文案位于 `comp_admin.person_link.*`；Stimulus 控制器 `person_link_picker_controller.js` 的所有文案都来自组件传入的 value。

## 需要特别注意

:::attention
不得在 `People::Link` 之外写 `entity_entries.user_id`。身份字段只存一处、审计留痕，都靠这些活动保证。`user_id` 已列入 `FlowchartRuntime::Entries::INTERNAL_COLUMNS`，`Entries.assign`、批量更新与 `ActivitySteps::PopulatePrimary`（表单提交）都会跳过它，助手也不能声明 `user_id` 属性。
:::

:::attention
候选接口与每次关联写入都通过 URL 租户的条目限定范围。平台所有者在其他租户的 URL 上操作时，同样只能看到并关联该租户的用户。
:::

:::attention
邮箱全局唯一保持不变：一个用户只属于一个租户。后续的邀请流程遇到属于其他租户的地址时，必须返回笼统的提示。
:::

:::note
Devise 配置为 `reconfirmable = false`，用户之后修改邮箱不会经过验证。`register_member` 在注册时写入认领；`signed_in_destination` 在首次确认（或之后通过邮件链接登录）时完成它。之后改邮箱不会再开一条认领。
:::

:::note
`person.linked`、`person.unlinked` 与 `person.claimed` 经 `Authentication::Instrumentation` 持久化，但不在 `Authentication::Event::EVENTS` 中，认证事件筛选暂不列出。
:::

:::attention
流程图运行时从不调用 `People::Ownership.scope`。不带 `scope:` 的 `QueryBuilder.for_entity` 仍返回本租户全部行。名额或重复检查若走会员行范围，会少计。
:::

:::attention
归属无法解析时——没有访问者、访问者属于其他租户、未知受众、或缺少归属关联——会员与公开 scope 返回空。不要把空列表当成“显示全部”。
:::

## 关键代码

```ruby
# app/services/people/ownership.rb
def describe(entity)
  return Descriptor.new(kind: :person, owner: nil) if entity.person?

  references = person_references(entity)
  owner = owner_from(references)
  kind = owner ? :owned : (references.empty? ? :open : :private)
  Descriptor.new(kind: kind, owner: owner)
end

def scope(entity, viewer:, audience:, customer_id:)
  rows = EntityEntry.where(customer_id: customer_id, entity_id: entity.id)
  return rows if audience.to_s == EntityAttributeAudience::ADMIN
  # open + 已知受众 → 本租户全部行；否则仅限会员且同租户，
  # 再按 person（user_id）／owned（json_extract 归属标识）／空
end
```

```ruby
# app/services/people/contracts/link.rb
def linkable_user
  return @linkable_user if defined?(@linkable_user)

  id = user_id.presence
  @linkable_user = id && Authentication::User.find_by(
    id: id,
    customer_id: model.customer_id,
    status: :active
  )
end
```

```ruby
# config/routes.rb
resource :person_link, only: %i[create destroy], controller: "entity_entry_person_links" do
  get :candidates
end
```

```ruby
# app/services/people/claim.rb
    TTL = 3.days

    def self.record!(user:, created_user:, entry: nil, continuation: nil)
      # 按 user_id 更新或插入；expires_at = 3.days.from_now
      # created_user 认领原样返回，不会被替换
    end

    def self.complete!(user)
      Activities::CompleteClaim.call(user: user)
    end
```
