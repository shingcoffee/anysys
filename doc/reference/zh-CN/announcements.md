---
title: "公告"
summary: "平台所有者发布的公告条，带有时间窗口、草稿或已发布状态，以及全体客户或分段受众。"
---

## 概要

`PlatformAnnouncement` 是平台目录记录，没有 `customer_id`。`Admin::Maintenance::Platform::AnnouncementsController` 通过 `PlatformAnnouncements::Activities::Save` 与 `PlatformAnnouncements::Contracts::Announcement` 创建和修改它。处于生效期的记录会变成管理外壳上的 `Platform::AnnouncementBannerComponent`。铃铛里的历史由 `PlatformAnnouncements::InboxResolver` 解析。关闭与标为已读位于租户管理前缀，客户管理员可以提交。

平台命名空间已限制为 `platform_owner?`。受众可筛选的客户字段见 [客户](customers)。

## 流程

```text
POST /:cid/admin/maintenance/platform/announcements
        |
        v
AnnouncementsController#save_and_respond
        |
        v
PlatformAnnouncements::Activities::Save
        |  TargetRules.parse + Contracts::Announcement
        v
PlatformAnnouncement
        |
        +-- live? -> Notifications::Stream.sync_announcement!
        |              接收者：匹配客户下处于启用状态的租户管理员
        |              若 starts_at 在未来 -> BroadcastAnnouncementJob
        +-- destroy -> discard_or_destroy!
        |
        v
管理外壳
        |
        +-- AnnouncementBannerComponent
        |     Resolver.for_viewer（跳过已关闭项，最多 3 条）
        +-- Notifications::Inbox
              InboxResolver（生效中 + 7 日历史，不看关闭记录）
```

## 实现

模型常量：`SEVERITIES` 为 `info`、`warning`、`critical`。`STATUSES` 为 `draft` 与 `published`。`AUDIENCES` 为 `all` 与 `selected`。`live?` 表示未删除、已发布，且落在 `starts_at` 与 `ends_at` 之间（任一侧为 `nil` 表示该侧不设限）。`lifecycle` 为 `:draft`、`:scheduled`、`:live` 或 `:ended`。`body_for` 在语言字符串以 `zh` 开头时返回 `body_zh`，否则返回 `body_en`。

`Save.sanitize` 把空白的 `link_url`、`starts_at`、`ends_at` 收成 nil，用 `TargetRules` 解析 `target_rules_json`。除非 `audience` 为 `selected` 或 JSON 无法解析，否则 `target_rules` 存 `TargetRules::EMPTY`。合约要求中英正文都存在（各 500 字）、标题不超过 120、以及合法的严重级别、状态和受众。`link_url` 必须匹配 `https?://`，并能解析为带主机、且没有 userinfo 的 HTTP URI。`selected` 受众必须是 `CustomerQuery` 可用的规则。空规则或不可用规则得到 `Customer.none`。

`CustomerFieldCatalog` 是编译白名单。未知／无效字段、运算符、连接、值类型或规则树会拒绝整个选定受众，不丢条件扩大范围。值经 Arel 绑定，LIKE 通配符按字面处理。`AudienceResolver` 每批 100 条 keyset 扫描，租户匹配后才限制结果。公告候选限制前按 critical／warning／info 优先，最多展示三条；收件箱按新到旧，含七日历史且忽略关闭记录。查询次数随扫描批次变化，不是全局固定预算。

`audience_preview` 提交 JSON，返回 `{ count, sample }`，样本最多五个客户；`TargetRules` 无法解析时返回 422。它只评估提交上来的规则。详情页上，`PlatformAnnouncement#matching_customers` 在记录不是分段时返回 `Customer.none`；`all_customers?` 时 `@matching_count` 为 nil。分段记录最多列出 `MATCHING_CUSTOMERS_LIMIT`（50）个名称。`AnnouncementPresenter` 负责徽章，并且不在列表页统计分段人数。

`destroy` 调用 `discard_or_destroy!`。生效中、已结束或曾经生效的行写入 `deleted_at`。从未生效的草稿和已排期行执行 `destroy!`。记录仍然存在时，会带上删除前抓到的接收者调用 `Notifications::Stream.sync_announcement!`。

## 需要特别注意

### 路由审计：受众及生效窗口不变量

选定规则要求合法目录字段／运算符、有符号 64 位整数 ID、有限数值、真实枚举及 ISO 日期，连接／深度（12）／节点（500）有上限。契约／模型／预览拒绝畸形树，历史畸形规则读取失败关闭；空规则不表示全体客户。超过 50 条其他租户新公告不会挤掉本租户较旧／关键公告。

`Notifications::ExpireAnnouncementJob.schedule` 保存精确 ends_at，在到期时刷新既有签名用户流。任务锁定／重载记录，忽略已删除／草稿／重排／结束时间不符的工作。刷新移除过期公告条但保留铃铛历史，排期开始及到期为不同任务。已读／关闭仍检查查看者／客户资格。见[后台任务](background-jobs)、[客户](customers)、[租户与角色](tenancy-and-roles)。

:::note
畸形受众、多批／严重级别及到期流回归测试已编写，本次未执行。打开中的浏览器刷新及生产队列时序尚未验证。
:::

:::attention
`AnnouncementsController` 写明 `/admin/maintenance/platform/*` 已由 `RouteAuthorization` 把关，控制器本身没有角色 `before_action`。关闭走 `Admin::PlatformAnnouncementDismissalsController`，已读走 `Admin::PlatformAnnouncementReadsController`，两者都在 `/:cid/admin/` 下，因为租户管理员必须能够 POST。
:::

:::attention
`PlatformAnnouncements::CustomerQuery` 在规则为空或不可用时不匹配任何客户。`Save` 在 `audience` 为 `all` 时也会清空 `target_rules`。分段公告在构建器为空时不能发布，也不会退回成全体客户。
:::

:::attention
`Notifications::Stream.announcement_recipients` 是匹配客户下 `Authentication::User.unscoped_by_tenant.active.by_role(:admin)` 的用户。`Stream` 的注释写明公告推送不会发给平台所有者。`AnnouncementBannerComponent` 在整页加载时仍会因 `platform_owner?` 经 `Resolver` 渲染出来。
:::

:::attention
`PlatformAnnouncementDismissal` 按用户和客户各记一条，`Resolver` 会把这些 id 从公告条里去掉。`InboxResolver` 不看关闭记录。`PlatformAnnouncementRead` 只是铃铛的已读游标。
:::

## 关键代码

```ruby
# app/models/platform_announcement.rb
def live?(now: Time.current)
  deleted_at.blank? &&
    status == "published" &&
    (starts_at.nil? || starts_at <= now) &&
    (ends_at.nil? || ends_at > now)
end
```

```ruby
# app/services/platform_announcements/activities/save.rb
def self.call(record:, params:)
  was_live = record.persisted? && record.live?
  previous_users = was_live ? Notifications::Stream.announcement_recipients(record).to_a : []
  attributes = sanitize(params)
  record.assign_attributes(attributes.slice(*ATTRIBUTES))

  contract = PlatformAnnouncements::Contracts::Announcement.new(record)
  unless contract.validate(attributes)
    return Result.new(success?: false, model: record,
                      errors: contract.errors.messages.to_h, messages: contract.errors.full_messages)
  end

  persist!(record, contract, was_live: was_live)
  Notifications::Stream.sync_announcement!(record, previous_users: previous_users)
  Result.new(success?: true, model: record, errors: {}, messages: [])
end
```

```ruby
# app/services/notifications/stream.rb
def self.announcement_recipients(announcement)
  customer_ids = announcement_customer_ids(announcement)
  return Authentication::User.none if customer_ids.blank?

  Authentication::User.unscoped_by_tenant.active.by_role(:admin).where(customer_id: customer_ids)
end
```

```ruby
# app/components/platform/announcement_banner_component.rb
def viewer_allowed?
  viewer.present? && (viewer.admin? || viewer.platform_owner?)
end
```
