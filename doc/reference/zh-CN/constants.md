---
title: "常量"
summary: "具名选项列表，归客户所有或全局共享，共享行的租户保存写入该客户的选项覆盖。"
---

## 概要

`Constant` 是一份具名选项列表。`customer_id` 为 nil 表示共享（`SharedIdentity#shared?`）。客户自有行属于一个租户。共享常量在平台前缀上创建。租户保存共享常量时，写入 URL 客户的 `constant_customer_overrides`，全局 `options` 列保持不动。存在覆盖行时，读取叠上这一行。重置会删掉它。前缀见 [shared-resources](shared-resources)，选用常量的属性见 [entity-builder](entity-builder)。

## 流程

```text
平台前缀创建
        |
        |  SharedResourceMode#apply_create_identity! 把 customer_id 设为 nil
        v
constants 行（name、options）  customer_id 为 NULL

租户 URL 更新共享常量
        |
        |  Constant#writing_customer_override?
        |  restore_shared_identity! 把已存储的 name 写回
        |  stash_customer_override! 把提交的 options 留在父列之外
        v
constant_customer_overrides（constant_id、customer_id、options）

after_find / reload_options_from_override!
        |
        |  有覆盖 -> self.options = override.options
        |  无覆盖 -> constants.options
        v
Admin::Maintenance::ConstantsController 的 index / show / JSON 选择器
```

`DELETE /:cid/admin/maintenance/constants/:id/override` 调用 `Constant#reset_customer_override!`。

## 实现

`Constant` 引入 `SharedIdentity`，并 `has_many :constant_customer_overrides`。它不调用 `acts_as_versionable`。`options` 必填。`ensure_options_is_array` 存成数组。去掉空白后每一项都为空时，`options_must_not_be_blank` 添加错误。去掉空白后重复的值无法通过 `options_must_be_unique`。客户自有行的名称在 `customer_id` 范围内唯一；共享行的名称全局唯一。

`Admin::Maintenance::ConstantsController` 引入 `SharedResourceMode`。HTML 的 `index` 列出 `definition_scope(Constant).ordered`。JSON 格式是同一范围、不分页的 `as_json(only: %i[id name options])`，因为属性选择器需要每一个可访问常量。平台前缀上 `definition_scope` 是 `Constant.shared`，租户 URL 上是 `Constant.accessible`（本客户的行加上每一个共享行）。`create` 在保存前运行 `apply_create_identity!`。

`update` 允许 `name`；参数里有 `options` 键时才允许 options。缺少 `options` 键时保留已存数组。`normalize_options` 接受 JSON 字符串、参数值或数组；空白或无法解析的值变成 `[]`，随后验证失败。

租户路径更新共享行时，`writing_customer_override?` 为真（已持久化，且 `override_customer_id` 存在）。`Current.shared_resources_mode` 已设置时 `override_customer_id` 为 nil，因此平台前缀的保存写入全局列。`restore_shared_identity!` 在验证前把 `name` 设为 `attribute_in_database("name")`。`stash_customer_override!` 把提交的 options 暂存一旁，再把 `options` 设回数据库中的值，共享列因此不变。`persist_stashed_override!` 为 `Current.customer_id` 写入 `constant_customer_overrides`。尚无覆盖、且提交的数组等于全局 options 时，不插入行。

`tenant_override?` 为假时，`ConstantsController#update` 才调用 `touch`，覆盖保存不会拨动共享行的 `updated_at`。删除共享常量包在 `guard_shared_global_writes` 里。`can_copy_definition?` 允许复制客户自有行，或在平台前缀上复制共享行。

`ConstantCustomerOverride` 要求 `customer_id` 存在，并在 `constant_id` 范围内唯一，同时要求 `options`。`reset_customer_override!` 销毁该行，再从全局列重新加载 options。常量不是共享资源，或没有覆盖行时，返回 false。

`after_find :reload_options_from_override!` 为当前客户叠上覆盖。列表页经 `SharedResourceMode#preload_override_association` 预加载 `:constant_customer_overrides`。

### 流程图步骤：read_setting

`read_setting` 步骤动作从流程图读取常量。`constant`（必填）引用 `constants` 来源（本客户常量及共享常量）。`returns: "options"` 写入选项列表；`returns: "label"` 写入 `value`（表达式，该模式下必填）对应的标签。它调用 `FlowchartRuntime::Constants.options`／`.label`，按 `ctx[:customer_id]` 解析，从不使用 `Current`：共享常量有该客户的 `ConstantCustomerOverride` 时使用覆盖，其他租户的常量抛出 `Constants::Error`，步骤报 `read_setting.failed`。结果写入 `resultVar`（默认 `constant_options`）。见 [流程图步骤动作](flowchart-step-actions)。

## 需要特别注意

:::attention
`Constant#override_customer_id` 与 `Versionable` 同一条规则：`Current.shared_resources_mode` 中为 nil，共享行在其他情况下取当前客户 id。`/:cid/admin/maintenance/constants` 上的 `Admin::Maintenance::ConstantsController` 因此为 `cid` 保存覆盖，客户 `81721200` 也一样。全局 `name` 与 `options` 在 `/admin/maintenance/platform/constants` 上修改。
:::

:::attention
客户还没有覆盖、且提交的 options 等于全局数组时，`Constant#persist_stashed_override!` 跳过 `find_or_initialize_by`。租户上的无改动保存不会把该客户钉死，从而脱离以后的全局修改。真正的差异才会插入 `ConstantCustomerOverride`。
:::

:::attention
`writing_customer_override?` 为真时，`Constant#restore_shared_identity!` 在 `before_validation` 运行。已存储的 `name` 会在唯一性检查之前写回，租户更新不能重命名共享常量。删除仍经过 `guard_shared_global_writes` 与 `PlatformPathHelper#reject_shared_global_mutation!`。
:::

:::attention
`ConstantsController#index` 的 JSON 渲染 `definition_scope(Constant).ordered`，没有分页。`SharedIdentity.accessible` 是当前客户的行，或 `customer_id` 为 nil 的行。平台前缀请求只用 `Constant.shared`。
:::

## 关键代码

```ruby
# app/models/constant.rb
  def override_customer_id(cid = Current.customer_id)
    return nil unless shared?
    return nil if cid.blank? || Current.shared_resources_mode

    cid
  end
```

```ruby
# app/models/constant.rb
  def persist_stashed_override!
    return if @stashed_override_options.nil?

    incoming = Array(@stashed_override_options)
    # A tenant Save that matches the global default must not pin an override;
    # otherwise a no-op resubmit forks the customer off later global edits.
    if override_for(Current.customer_id).nil? && incoming == Array(options)
      self.options = incoming
      @stashed_override_options = nil
      return
    end

    constant_customer_overrides
      .find_or_initialize_by(customer_id: Current.customer_id)
      .update!(options: incoming)
    self.options = incoming
    @stashed_override_options = nil
  end
```

```ruby
# app/models/constant.rb
  def reset_customer_override!(cid = Current.customer_id)
    return false unless shared? && cid.present?

    ov = override_for(cid)
    return false unless ov

    ov.destroy
    reload_options_from_override!
    true
  end
```

```ruby
# app/controllers/admin/maintenance/constants_controller.rb
    def update
      if @constant.update(constant_params)
        # Reflect every Save in the "last updated" time. Rails only bumps
        # updated_at when an attribute actually changed; an identical resubmit
        # would otherwise leave the timestamp stale, so touch when nothing else
        # moved it. Tenant-path overrides must not touch the shared parent row.
        unless tenant_override?(@constant)
          @constant.touch unless @constant.saved_change_to_updated_at?
        end
```

```ruby
# app/models/constant_customer_override.rb
class ConstantCustomerOverride < ApplicationRecord
  belongs_to :constant

  validates :customer_id, presence: true, uniqueness: { scope: :constant_id }
  validates :options, presence: true
end
```
