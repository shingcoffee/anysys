---
title: "系统地图"
summary: "租户、URL、构建器、共享资源与功能模块如何拼在一起。"
---

## 概要

Anysys 是多租户 Rails 应用。客户拥有自己的记录。三个保留角色（`owner`、`admin`、`member`）决定已登录用户能打开哪一类 URL。产品的数据模型不是一组写死的业务表。客户用实体构建器描述记录，用流程图构建器描述行为，用页面构建器描述界面。支付、邮件等功能模块各自用一个注册文件接到这套核心上。

平台客户 `81721200` 是特殊的。该客户的所有者可以跨租户，并且是唯一能打开平台维护区的用户，包括本参考与流程图构建器。

## 流程

```text
请求
  |
  +-- /:cid/admin/...                         admin 或 owner
  |     +-- /admin/maintenance/platform/...   仅平台所有者
  |     +-- /admin/maintenance/flowcharts...  仅平台所有者
  +-- /:cid/member/...                        member（admin 可预览 GET）
  +-- 其他路径                                公开
        |
        v
RouteAuthorization  ->  TenantContext（Current.customer）
        |
        v
客户数据（customer_id）
        |
        +-- Entity（结构） ---- EntityEntry（property_data）
        +-- Flowchart ---------- ActivityGenerator --> Trailblazer::Activity
        +-- Page --------------- generate_content --> ERB，经公开 UUID 提交
        +-- Constant
        |
        +-- FeatureModules::* 按客户启用
              记录 | 设置 | 维护开关 | 平台设置
```

已发布的页面提交到 `PublicPagesController`。提交会跑该页面绑定的流程图。流程图不是在请求时逐步解释的。`ActivityGenerator` 遍历图，向 `CodeGenerators::GeneratorRegistry` 要 Ruby，再变成 Trailblazer activity。

## 实现

### 租户与角色

几乎每条持久化记录都有 `customer_id`。`Authentication::User::PLATFORM_CUSTOMER_ID` 是 `81721200`。只有该用户同时拥有保留角色 `owner` 时，`platform_owner?` 才为真。`owner` 角色本身只能授给该客户下的 `lingercoffee@gmail.com`（`eligible_for_owner_role?`）。

`Customer` 上也有一个名为 `role` 的枚举（`owner`、`admin`、`member`）。这一列不是已登录用户的角色。用户角色在 `Role` 与 `UsersRole` 上。

`TenantScoped` 在创建时填入 `customer_id`，并提供 `for_current_customer` / `for_customer`。它没有 `default_scope`。调用方自己限定范围之前，`Model.all` 是全部租户。`app/models/concerns/tenant_scoped.rb` 文件头里把 `Flowchart.all` 写成已经按租户过滤的注释已经过时。

`RouteAuthorization` 按路径分类。admin 前缀要求 `admin_or_owner?`。member 前缀要求 `member?`，另有一个显式例外：member 控制器可以调用 `allow_admin_member_preview!`，让同一租户的 admin 或 owner 用 GET 预览 member 界面。平台路径与流程图路径要求 `platform_owner?`。随后仍会跑 CanCan。平台所有者得到 `can :manage, :all`。租户管理员可以管理自己的租户，然后被一份显式的平台 subject 列表排除。

没有第四种角色。不要在控制器或复选框里发明一种。

### URL 分类与模块表面

每条路由只属于 admin、member 或 public。功能模块的管理界面再分成四个位置：

| 表面 | 路径 | 谁 |
| --- | --- | --- |
| 记录 | `/:customer_id/admin/modules/<module_key>` | 有模块权限的客户用户 |
| 客户设置 | `/:customer_id/admin/settings/modules/<module_key>` | 客户管理员 |
| 启用 / 停用 | `/:customer_id/admin/maintenance/modules` | 客户 admin 或 owner |
| 平台设置 | `/:customer_id/admin/maintenance/platform/module_settings` | 平台所有者，客户 `81721200` |

已注册的模块是 `authentication`、`payment`、`email`、`sms`、`captcha`、`ai_assistant` 与 `website`。每一个都是 `FeatureModules::<Name>::Registration`。计费、语音转写、公告与支持工单是真实产品表面，但不是功能模块注册。本参考里对应的页面会写明它们属于哪一类。

有两个注册不走记录路径。验证码没有模块列表。助手界面是 `/:customer_id/admin/assistant`，不是 `/:customer_id/admin/modules/ai_assistant`。网站列表与编辑器均在 `/:customer_id/admin/modules/website` 下。公开网站和公开表单通过 [页面快捷路径](page-shortcuts) 使用按主机生成的简洁路径或指定别名；规范 `/:customer_id/site` 和表单 UUID 端点继续可用。客户映射在 `/:customer_id/admin/maintenance/page_shortcuts` 管理。

### 自定义域名

[自定义域名](custom-domains)是每个客户可选的 `customers.domain`，与组织名称一起在客户资料中编辑。「客户」是唯一的所有者专属平台侧栏入口。没有域名管理页面。实时查询为无前缀的公开请求选择租户，显式前缀优先，停用客户返回 404。新增或变更域名须配置应答区中直接指向 `anysys.net` 的 CNAME。`CustomDomains::CnameVerifier.call` 返回 `:verified` 或 `:unverified`。提交后无需重启即可生效；部署负责发布 DNS，并分别管理 TLS、入口和主机授权。

### 构建器

[实体构建器](entity-builder) 保存结构。条目保存必须符合该结构的 JSON 值。[流程图构建器](flowchart-builder) 保存绑定到实体的图。[页面构建器](page-builder) 保存布局，字段经流程图提交。[网站构建器](website-builder) 是面向公开站点的功能模块，与维护区页面不是同一套编辑器。[代码生成器](code-generators) 是流程图编译器允许发出的词汇表。

### 共享资源

实体、页面、流程图与常量可以是共享的（`customer_id` 为 NULL）。创建、改名、发布与删除全局行只能发生在 `/81721200/admin/maintenance/platform/...`。租户维护 URL 上的保存写入该客户的覆盖，不改全局定义。读取走 `resolved_current_version`：优先客户头指针，否则用全局默认。详见 [共享资源](shared-resources)。

### 外壳

管理端首页是 [仪表板](dashboard)。侧栏由 `SidebarContributor` 的子类贡献（`MaintenanceContributor`，以及模块、设置、页面、实体的贡献者）。平台叶子只在客户 `81721200` 的平台所有者会话里出现。

### 生产容器

生产镜像基于 `ruby:3.2.8-alpine`，由根目录 `Dockerfile` 构建。`docker build`／`docker run`、必填的 `RAILS_MASTER_KEY` 与 `APP_HOST`，以及 `/rails/storage` 数据卷，见 [Docker 镜像](docker-image)。

## 需要特别注意

:::attention
当你想表达「这个客户看到的定义」时，不要对共享的实体、页面或流程图读 `current_version`。`Versionable#resolved_current_version` 会套用覆盖头指针。租户路径上的保存，包括平台所有者在 URL 客户为 `81721200` 时的保存，写的是覆盖线，不是全局默认。全局身份变更只属于平台前缀。
:::

:::attention
流程图没有名称或没有元素时，`ActivityGenerator#generate` 返回 `nil`；结构校验失败时也可能再返回 `nil`。调用方必须把 `nil` 当成「没有 activity」，而不是空字符串。不支持的结构元素类型会抛出 `ActivityGenerator::Error`。
:::

:::attention
流程图界面即使挂在租户 URL 上也只允许所有者。`FlowchartVisibility` 与 `RouteAuthorization#flowchart_namespace?` 同时生效。藏起侧栏链接不是授权检查。公开表单在提交时仍会执行这张流程图。客户可以跑他们打不开的图。
:::

:::attention
新的模块 URL 必须落在上面四个表面之一。支付、验证码或邮件的新供应商是该模块 provider 目录下的一个新文件，不是一张新表，也不是一块新的设置屏幕。
:::

## 关键代码

```ruby
# app/models/concerns/versionable.rb
def resolved_current_version(cid = Current.customer_id)
  line_cid = override_customer_id(cid)
  return current_version if line_cid.nil?
  customer_head_for(line_cid)&.current_version || current_version
end
```

```ruby
# app/services/activity_generator.rb
def generate
  return nil if flowchart.name.blank? || elements.empty?

  validation_errors = validate_structure
```

```ruby
# app/controllers/concerns/page_rendering.rb
def prepare_page_render(page)
  @form_action = public_page_submit_path(customer_id: params[:customer_id], uuid: page.public_uuid)
  @content = page.generate_content
end
```
