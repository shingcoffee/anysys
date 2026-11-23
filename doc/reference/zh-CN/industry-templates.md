---
title: "行业模板"
summary: "把客户行业映射到页面布局模板键的平台数据，按行业编辑，并可由分类默认规则生成。"
---

## 概要

`IndustryTemplateMapping` 保存 `(industry, template_key)`，没有 `customer_id`。`Admin::Maintenance::Platform::IndustryTemplatesController` 用 `Customer::INDUSTRY_GROUPS` 列出行业，并整表替换某一个行业的键。单张卡片的添加与移除是 `IndustryTemplateAssignmentsController`。卡片 HTML 由 `IndustryTemplateCardsController` 渲染。默认数据来自 `IndustryTemplateMappingSeeder`，入口是 `IndustryTemplateDefaultSeedsController` 与 `IndustryTemplateNewTemplateSeedsController`。

选择页面时，`PageLayoutTemplates.for_industry` 读取这些行。平台命名空间已限制为 `platform_owner?`。行业枚举从 `config/industries.yml` 载入 `Customer`，见 [客户](customers)。把模板应用到页面见 [页面构建器](page-builder)。

## 流程

```text
GET /:cid/admin/maintenance/platform/industry_templates
        |
        v
IndustryTemplatesController#index
  Customer::INDUSTRY_GROUPS
  IndustryTemplateMapping.group(:industry).count
        |
        +-- PATCH :id -> replace_for_industry!(industry, template_keys)
        +-- POST  :id/template_assignments -> 一条 IndustryTemplateMapping
        +-- DELETE template_assignments/:template_key
        +-- GET template_cards -> template_cards 片段，layout false
        |
        +-- POST   default_seed      -> seed_defaults!（尚无记录的行业）
        +-- DELETE default_seed      -> seed_all!（先 delete_all，再写默认）
        +-- POST   new_template_seed -> seed_new_templates!
        |
        v
PageLayoutTemplates.for_industry(industry)
  已有键 -> 这些模板
  键为空 -> PageLayoutTemplates.all
```

## 实现

`IndustryTemplateMapping` 用 `Customer.industries` 校验 `industry`，用 `PageLayoutTemplates.find` 校验 `template_key`。唯一索引是 `(industry, template_key)`。`template_keys_for` 取出键列表。`replace_for_industry!` 在事务里对该行业 `delete_all`，再对剩余每个键 `create!`。更新动作保留 `params[:template_keys]` 里的字符串和符号，去掉空白。`ActiveRecord::RecordInvalid` 会回到编辑页，并提示 `maint_platform.flash.industry_templates.invalid_template_keys`。`show` 返回 JSON `{ industry, template_keys }`。不是行业键的 id 得到 JSON 404 或 HTML 重定向。

`IndustryTemplateAssignmentsController#create` 保存一行，返回 `{ status: "added", template_key, count }`，失败则 422 并带 `errors`。`#destroy` 用 `params[:id]` 或 `params[:template_key]` 查找，返回 `"removed"` 或 404。`IndustryTemplateCardsController#show` 载入全部 `PageLayoutTemplates`，以 `layout: false` 渲染 `admin/maintenance/platform/industry_templates/template_cards`。

`IndustryTemplateMappingSeeder::UNIVERSAL_CATEGORIES`（`general`、`registration`、`contact`、`survey`、`feedback`、`scheduling`、`application`、`hr`）对应每一个行业。`CATEGORY_INDUSTRY_MAP` 把其余模板分类映射到一组行业符号。`seed_defaults!` 只对当前没有任何映射的行业做 `insert_all`，返回值是这份待插入记录数组的长度。`seed_all!` 先 `delete_all` 整张表，再对每一个 `Customer.industries` 键做同样的插入。控制器把 `seed_all!` 接在 `IndustryTemplateDefaultSeedsController#destroy`。`seed_new_templates!` 用 `PageLayoutTemplates.keys` 减去已经出现在任意映射上的键，再按 `industries_for_category` 给出的每个行业调用一次 `IndustryTemplateMapping.create`。

`PageLayoutTemplates.for_industry` 在行业为空，或 `template_keys_for` 为空时返回 `all`。否则只保留 `:key` 落在该列表中的模板。`category_counts_for_industry` 统计过滤后的集合。

## 需要特别注意

### 路由审计：替换输入不变量

行业更新在替换前要求字符串／符号模板键数组。畸形容器／项返回可控错误并保留映射；显式 `[]` 仍清空行业并恢复既有全部模板回退。中央平台门禁对全部格式要求外层 CID `81721200`。见[客户](customers)、[租户与角色](tenancy-and-roles)。

:::note
分类按钮及卡片徽章在两种语言渲染时调用 `PageLayoutTemplates.category_label`。畸形容器与分类标签回归已包含在 2026-10-12 并行套件中（**25,266 个示例，0 个失败**）。下述独立种子计数语义保持不变。
:::

:::attention
`IndustryTemplatesController` 继承中央平台角色／路径门禁。`Ability#platform_owner_subjects` 包含 `platform_industry_templates`，路由授权另使用 route 主体。映射表为全局表，没有 `customer_id`。
:::

:::attention
`PageLayoutTemplates.for_industry` 把「该行业没有任何 `IndustryTemplateMapping`」理解成展示全部模板。`IndustryTemplateMapping.replace_for_industry!` 在 `template_keys` 为空数组时会删掉该行业的行，于是走到这条退回路径。`seed_defaults!` 只填补尚无记录的行业，因此会把刚被清空的行业重新填上。
:::

:::attention
`IndustryTemplateDefaultSeedsController#create` 调用 `seed_defaults!`。`#destroy` 调用 `seed_all!`，后者先 `IndustryTemplateMapping.delete_all` 整张表，再插入默认行。`IndustryTemplateNewTemplateSeedsController#create` 调用 `seed_new_templates!`，不会替换已经存在的映射。
:::

:::attention
`IndustryTemplateMappingSeeder#seed_new_templates!` 在每一次 `IndustryTemplateMapping.create` 之后都把返回计数加 1。`create` 在校验失败时不抛异常，所以提示 `maint_platform.flash.industry_templates.new_mappings_created` 里的数字可能包含没有插入的调用。`seed_defaults!` 与 `seed_all!` 使用 `insert_all`，会跳过模型校验。
:::

## 关键代码

```ruby
# app/models/industry_template_mapping.rb
def self.replace_for_industry!(industry, template_keys)
  transaction do
    for_industry(industry).delete_all
    template_keys.each do |key|
      create!(industry: industry.to_s, template_key: key.to_s)
    end
  end
end
```

```ruby
# app/services/page_layout_templates.rb
def for_industry(industry)
  return all if industry.blank?

  allowed_keys = IndustryTemplateMapping.template_keys_for(industry)
  return all if allowed_keys.empty?

  allowed_set = allowed_keys.to_set
  all.select { |t| allowed_set.include?(t[:key]) }
end
```

```ruby
# app/controllers/admin/maintenance/platform/industry_template_default_seeds_controller.rb
def create
  count = IndustryTemplateMappingSeeder.seed_defaults!
  redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
              notice: t("maint_platform.flash.industry_templates.defaults_seeded", count: count)
end

def destroy
  IndustryTemplateMappingSeeder.seed_all!
  redirect_to admin_maintenance_platform_industry_templates_path(current_customer_id),
              notice: t("maint_platform.flash.industry_templates.reset_to_defaults")
end
```

```ruby
# app/services/industry_template_mapping_seeder.rb
def seed_new_templates!
  mapped_keys = IndustryTemplateMapping.distinct.pluck(:template_key)
  all_keys = PageLayoutTemplates.keys
  new_keys = all_keys - mapped_keys

  return 0 if new_keys.empty?

  templates = new_keys.map { |k| PageLayoutTemplates.find(k) }.compact
  count = 0

  templates.each do |template|
    industries = industries_for_category(template[:category])
    industries.each do |industry|
      IndustryTemplateMapping.create(industry: industry.to_s, template_key: template[:key])
      count += 1
    end
  end

  count
end
```
