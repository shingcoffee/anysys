---
title: "受众流程"
summary: "同一业务动作如何通过独立页面与流程图分别服务管理员、会员与公开访客，并由操作标识串联。"
---

## 概要

同一业务域面向三种受众。每种受众各有表单与流程图，任何受众都进不了另一种受众的流程，也看不到他人的记录。页面受众是精确集合（`audience_admin`、`audience_member`、`audience_public`），不是层级。共享同一 `action_key` 的页面构成一个操作；`GET /:customer_id/actions/:action_key` 把每位访问者送到其受众对应的已上线页面。

工作示例是「报名课程」：人员实体学生、实体课程，以及二者之间的报名桥接。

| 受众 | 入口 | 表单 | 流程图 | 平台信任的内容 |
|---|---|---|---|---|
| 管理员 | 学生详情、报名卡片 | 关联卡片：选择课程 | 现有的关联写入器 | URL 中的租户 |
| 会员 | 会员导航、课程目录行链接 | 绑定报名的页面，仅课程选择 | 会员报名：课程开放、不重复、锁内容量、可选支付或审批 | 学生＝该会员已关联的学生条目 |
| 公开 | 网站按钮、二维码、目录行链接 | 绑定学生的页面，含姓名、邮箱与资料字段 | 公开注册：启动会员注册并记住所选课程 | 无。邮箱确认后才关联账号与条目 |

邮箱确认后，公开访客已登录，落到会员报名表单，课程已预选。写入报名的是会员流程图，未验证邮箱不会产生报名。见下文**公开报名**。

开关与操作标识见[页面构建器](page-builder)，GET／POST 规则见[页面渲染](page-rendering)，会员链接与行操作见[会员与公开页面](member-and-public)，归属种类见[人员关联](person-linking)，`RegisterMember` 与登录落点见[身份认证](authentication)。

## 流程

```text
GET /:cid/actions/enroll
        |
        |  Pages::ActionsController（公开 URL，只重定向）
        |  audience = EntityAttributeAudience.for_user(...)
        v
Pages::ActionResolver.page_for(customer_id, "enroll", audience)
        |
        +-- 公开    -> GET /:cid/page/:uuid          （学生页）
        |              已有上线会员页时附加 continuation=
        +-- 会员    -> GET /:cid/member/pages/:id    （报名页）
        +-- 管理员  -> GET /:cid/admin/pages/:id/form
        +-- 匿名、无公开页、存在会员页
        |              保存会员路径与预填，转到登录
        +-- 其余 404
```

每种受众的流程图只为该受众编写。共用规则放在一个「报名核心」子流程。

```text
管理员
  学生详情 -> 报名卡片
        |
        v
  关联写入器（直接写报名行）
  不调用报名核心

会员
  会员导航／目录行操作
        |
        |  绑定报名的页面（仅会员）
        |  课程选择；隐藏归属引用
        v
  会员报名流程图
        |  可选支付或审批
        v
  报名核心（子流程）

公开
  网站按钮／二维码／目录链接
        |
        |  GET /:cid/actions/enroll?prefill[course]=<id>
        |  绑定学生的页面（集合含公开）
        |  已有上线会员页时带签名续接
        v
  公开注册流程图
        |  register_member（ctx[:identity]、ctx[:continuation]）
        |  从不写报名
        v
  「请查收邮件以完成注册。」
        |
        v
  确认邮件 -> 已登录 -> 认领完成
        |
        v
  会员报名页，课程已预选
```

```text
报名核心（共用子流程）
        |
        |  课程开放
        |  upsert_model 按学生与课程匹配
        |  acquire_lock 下检查容量
        v
  报名行
```

受众精确之后，会员流程图可以依赖 `ctx[:current_person_ids]`（访问者已关联的学生）。公开流程图从不写桥接。管理员仍用关联卡片。

## 实现

### 精确受众

`pages.visibility` 已移除，改为三个布尔列：`audience_admin`（默认 true）、`audience_member` 与 `audience_public`（默认 false）。页面至少要有一个受众（`maint_core.errors.validations.page_audiences_blank`：「请至少选择一个受众。」／ "Choose at least one audience."）。`PageVisibility::AUDIENCES` 为 `%w[admin member public]`。`visible_to?(audience)` 是集合成员判断；未知受众为假。`visible_audiences` 按该顺序返回集合。`Page.for_audience(audience)` 是 SQL 范围。

各处的访问者受众都是 `EntityAttributeAudience.for_user(user, customer_id:)`（`page_runtime_audience`）。其他租户的已登录用户视为**公开**。

读取：

- `GET /:cid/page/:uuid`：集合含 `public` 时渲染；若访问者受众在同一操作下另有对应页，则 303 过去并保留预填。
- `GET /:cid/member/pages/:id` 要求 `member`。管理员 GET 预览（`allow_admin_member_preview!`）不变。
- `GET /:cid/admin/pages/:id/form` 与维护渲染要求 `admin`。维护预览仍可渲染任意页面。

写入：`POST /:cid/page/:uuid` 要求访问者受众在集合中，否则不写入。拒绝顺序为：对应页 → 匿名登录回跳 → 公开 `not_for_your_account` → 404。见[页面渲染](page-rendering)。

受众与操作标识属于身份。共享页面只能在平台前缀上修改（`PageVisibilitiesController` 上的 `guard_shared_global_writes`）。

### 归属

`People::Ownership.kind(entity)` 为 `:person`、`:owned`、`:private` 或 `:open`。桥接在编辑器里没有归属开关；报名因只有一个人员引用（`student`）而为 `:owned`。行范围：

| 种类 | 管理员 | 会员 | 公开 |
|---|---|---|---|
| person | 本租户全部行 | 已关联到访问者的行 | 无 |
| owned | 本租户全部行 | 归属引用指向访问者已关联条目的行 | 无 |
| private | 本租户全部行 | 无 | 无 |
| open | 本租户全部行 | 本租户全部行 | 本租户全部行 |

流程图运行时从不使用该范围：容量检查必须统计全部报名。完整规则见[人员关联](person-linking)。

绑定归属桥接的页面只能面向会员（`maint_core.errors.page_launch.bridge_page_member_only`：「关联实体的表单仅限会员使用」／ "A form on a link entity can only be opened by members"）。维护实体选择器列出种类为 `:owned` 的租户桥接；共享资源模式不列（共享实体不能带关联）。`grouped_entity_options` 保留绑定到归属桥接的流程图。

### 操作与路由器

`pages.action_key` 可空，须匹配 `/\A[a-z][a-z0-9_]{1,62}\z/`（`page_action_key_invalid`：「操作标识须以字母开头，且只能包含小写字母、数字和下划线。」／ "The action key must start with a letter and use only lowercase letters, numbers and underscores."）。空白存为 nil。

同一所有者（某客户自有页面，或共享页面）下，每个操作标识与受众最多一个已上线、有效的页面。上线或改受众若冲突，失败为 `action_audience_taken`（`%{audience}`、`%{action}`：「操作 %{action} 已有面向%{audience}的上线表单」／ "Another live form already handles %{audience} for action %{action}"）。租户页优先于同标识、同受众的共享页。`launch!`、`Pages::VisibilityContract#save` 及从回收站恢复已上线页面（`Page#restore`，冲突时以同一消息拒绝）均在事务内持有 `Customer.lock.find(page.customer_id || Authentication::User::PLATFORM_CUSTOMER_ID)` 后再检查槽位（共享页锁定平台客户）。

查找只走 `Pages::ActionResolver`：

- `page_for(customer_id:, action_key:, audience:)` — 有效、已上线、`for_audience`；租户页先于共享页。
- `counterpart(page:, audience:, customer_id: page.customer_id)` — 同一标识；页面没有对应页、或对应页就是自身时为 nil。`PublicPagesController` 传入当前访问的租户，因此共享页会让位于该租户同受众的页面。
- `siblings(page)` — 同一标识、同一所有者下的其他有效页面，不论是否上线（发布卡片用）。

`GET /:customer_id/actions/:action_key`（`page_action`，公开 URL，`Pages::ActionsController#show`）没有鉴权过滤器，只做重定向；目标界面各自把关。`prefill[<slug>]=<scalar>` 会传到目标页：最多 10 个键，标识须匹配 `Pages::FormParams::SLUG`，值最长 200 字符（`Pages::ActionLink`）。

### 预填与行操作

`Pages::Prefill.values(page:, params:, audience:, viewer:)` 只保留该受众可见的字段；引用值须在访问者可选范围内；从不预填归属引用。生成的 ERB 读取 `page_prefill_value(slug)`。提交校验不变：预填不授予任何权限。

设置／会员：实体界面可配置行操作（操作标识、目标字段、可选按钮文字；默认 `member.entity_surfaces.row_action_default`「打开」／ "Open"）。每行链到 `Pages::ActionLink.path`，并带 `prefill[<field>]=<行 id>`。组合列表块接受同样键的 `config.row_action`，并渲染末列链接（`public_views.composite.row_action_default`）。

### 公开报名

未登录访客打开 `/:cid/actions/enroll?prefill[course]=<id>`。

1. **路由器。** `Pages::ActionsController` 解析公开学生页并以 303 转到该页。同一操作已有上线会员页时，附加 `continuation=`——签名的 `{ action_key: "enroll", prefill: { "course" => "<id>" } }`（purpose `page_continuation`，3 天）。令牌不带 URL，也不带客户编号。
2. **公开学生页。** 表单显示名字、姓氏与邮箱（`identity[<key>]`），以及任意资料字段。课程不在此表单上：公开学生页从不写报名（`AudienceGuard` 忽略空的桥接分区）。生成的 ERB 从 `@page_continuation` 提交隐藏的 `_continuation`。
3. **`register_member`。** 公开流程图读取 `ctx[:identity]` 与 `ctx[:continuation]`。新邮箱会创建无密码、未确认的会员、未关联的学生条目，以及认领（`created_user: true`）。本租户已确认的有效会员会收到登录链接（受登录链接防轰炸限额约束）和仅续接的认领。其他已有账号什么都不做，未确认会员的首条认领保持不变。会员配额已满时同样处理，不保存任何内容。浏览器始终看到 `registration_pending`（`public_views.flash.outcomes.registration_pending`：「请查收邮件以完成注册。」／ "Check your email to finish signing up."）。不要按 `registration.status` 分支流程图。
4. **确认。** Devise 在最外层提交之后发送确认邮件。`Authentication::ConfirmationsController#show` 让会员登录（`SignInFlow.complete` 然后 `finish_sign_in`）。
5. **认领。** `signed_in_destination` 先运行 `People::Claim.complete!`（关联学生条目，审计 `person.claimed`），然后落点＝安全的已存位置 → 认领续接 → `LandingPath`。续接路径始终是**该用户**租户下的 `/:cid/actions/:key`。
6. **会员报名。** 已登录会员再次经过操作路由器，打开会员报名页，课程已预选。提交该表单才写入报名。未验证邮箱不会产生报名。

被篡改或过期的续接为 nil；注册仍然成功，确认后会员落到默认路径，课程不会预选。公开学生页应开启验证码（页面开关加 URL 限流）。见[验证码](captcha)、[身份认证](authentication)、[人员关联](person-linking)、[流程图运行时](flowchart-runtime)。

## 需要特别注意

:::attention
已登录的管理员不能提交仅面向公开的页面。`page_runtime_audience` 为 `admin`，不在集合中，POST 走拒绝规则且不写入。测试公开表单请退出登录，或把管理员加入受众。其他租户的已登录会员在此视为公开。
:::

:::attention
`Pages::ActionsController` 属于公开 URL，没有鉴权 `before_action`，只做重定向。不要在此控制器写入；会员与管理员目标各自保留守卫。
:::

:::attention
同一操作标识与受众的两次并发上线不能同时通过：`launch!` 与可见性契约在 `action_errors` 之前持有所属客户行锁。页面下线后槽位释放。
:::

:::attention
流程图仅平台所有者可见。客户看不到编辑器，也看不到「流程图」一词。已绑定页面仍通过 `form_settings.flowchart_id` 提交。增加界面或链接前先问 `FlowchartVisibility.allowed?`。见[流程图构建器](flowchart-builder)。
:::

:::attention
不要按 `registration.status` 分支公开流程图。`created` 与 `existing` 共用同一条 `registration_pending` 闪讯，访客无法据此判断邮箱是否已有账号。
:::

## 关键代码

```ruby
# app/models/concerns/page_visibility.rb
  AUDIENCES = %w[admin member public].freeze

  def visible_to?(audience)
    key = audience.to_s
    return false unless AUDIENCES.include?(key)

    public_send("audience_#{key}")
  end
```

```ruby
# app/services/pages/action_resolver.rb
  def page_for(customer_id:, action_key:, audience:)
    scope = Page.where(action_key: action_key, launched: true).for_audience(audience)
    scope.find_by(customer_id: customer_id) || scope.find_by(customer_id: nil)
  end
```

```ruby
# config/routes.rb
    get  "actions/:action_key", to: "pages/actions#show", as: :page_action,
         constraints: { action_key: /[a-z][a-z0-9_]{1,62}/ }
```

```ruby
# app/controllers/pages/actions_controller.rb
    def show
      page = ActionResolver.page_for(
        customer_id: current_customer_id,
        action_key: params[:action_key],
        audience: page_runtime_audience
      )
      if page
        prefill = sanitized_action_prefill
        path = audience_surface_path(page, prefill: prefill)
        path = with_public_continuation(path, prefill) if public_continuation?
        redirect_to path, status: :see_other
        return
      end
      # 匿名 + 会员页 -> 保存回跳并登录；否则 404
    end
```

相关：[页面构建器](page-builder)、[页面渲染](page-rendering)、[会员与公开页面](member-and-public)、[人员关联](person-linking)、[身份认证](authentication)、[验证码](captcha)。
