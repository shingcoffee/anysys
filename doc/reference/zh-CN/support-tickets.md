---
title: "支持工单"
summary: "平台收件箱用于查看各租户的帮助工单、以所有者身份回复，以及将会话结案。"
---

## 概要

租户管理员从管理端帮助菜单开启一条 `SupportTicket`。平台所有者在 `/admin/maintenance/platform/support_tickets` 阅读全部租户的工单，以 `author_role` `"owner"` 回复，并把会话结案。请求人自己的查看与回复留在 `/:cid/admin/support_tickets` 的 `Admin::SupportTicketsController`。

两边都调用 `Help::Activities::AddMessage`；所有者结案时调用 `Help::Activities::Resolve`。列出近期工单的铃铛是 `Notifications::Inbox`，与平台列表是两条路径。角色只有三种保留角色。平台命名空间已限制为 `platform_owner?`。见 [租户与角色](tenancy-and-roles)。

同一帮助菜单也提供**文档**入口，在 `/:cid/admin/help/docs` 打开站内客户操作指南。这是面向 admin 或 owner 的只读入口，与创建工单、邮件支持及仅所有者可见的开发文档分别独立。参阅[客户使用文档](customer-documentation)。

## 流程

```text
租户管理员
  Admin::SupportTicketsController#create
        |
        v
Help::Activities::CreateRequest
  status 为 open，author_role 为 requester
  为请求人写入 SupportTicketRead
  Notifications::Stream.broadcast_help! -> 平台所有者
        |
        v
平台所有者
  Admin::Maintenance::Platform::SupportTicketsController
        |  SupportTicket.unscoped_by_tenant
        +-- show -> SupportTicketRead.record!
        +-- SupportTicketMessagesController#create
        |     Help::Activities::AddMessage，author_role 为 "owner"
        |     broadcast_help! -> 请求人
        +-- SupportTicketResolutionsController#create
              Help::Activities::Resolve（status 变为 resolved）
```

## 实现

`SupportTicket` 引入 `TenantScoped`，`STATUSES` 为 `open` 与 `resolved`。它属于一个客户和一个用户。`messages` 是 `SupportTicketMessage`，`AUTHOR_ROLES` 为 `requester` 与 `owner`。图片挂在消息上。`SupportTicketRead` 是按用户的阅读游标。`record!` 把 `customer_id` 写成工单所属客户；唯一索引冲突时改为更新 `last_read_at`，而不是抛错。

`unread_for?` 把 `platform_owner?` 查看者视为在等待 `author_role` `"requester"`。其他查看者等待 `"owner"`。对方消息新于该用户的 `last_read_at` 时为未读；还没有游标时，任意一条对方消息都算未读。

平台列表是 `SupportTicket.unscoped_by_tenant`，预加载客户、用户、阅读记录和消息，按 `newest_first` 排序，并由 `ModuleEntriesResolver` 按 `status` 过滤。`show` 为 `current_user` 记下已读，并取出 `thread_messages`。回复控制器以同样的跨租户方式找到工单，调用 `AddMessage`，`author_role` 为 `"owner"`，参数允许 `:body` 与 `images: []`。`Resolve` 把 `status` 设为 `"resolved"`；工单已经结案时返回失败结果。`AddMessage` 拒绝已结案工单和未知作者角色，再用 `Help::Contracts::Message` 校验（正文必填，最长 5000 字），然后走 `Help::AttachmentRules`（jpeg、png、gif、webp；最多 5 个文件；每个 5 MB）。

`Admin::SupportTicketsController#create` 在 `current_user.platform_owner?` 时直接重定向，提示 `help.errors.owner_cannot_notify`。否则 `CreateRequest` 为 `current_customer` 与 `current_user` 开单。租户回复控制器加载 `for_customer(current_customer_id).where(user_id: current_user.id)`，并以 `author_role: "requester"` 提交。

`Notifications::Inbox#help_scope` 使用 `inbox_visible`：未结案工单，再加上 `last_message_at` 落在 `SupportTicket::HISTORY_RETENTION`（7 天）内的已结案工单。平台所有者看到的是跨租户的这一范围。租户用户只看到自己 `user_id` 的工单。平台列表不套用 `inbox_visible`。

`HelpMenuComponent#show_docs?` 要求用户为 admin 或 owner 且存在客户 id；`docs_url` 调用 `admin_help_docs_path(customer_id)` 在应用内跳转。`Admin::Help::DocsController` 依赖集中式 `RouteAuthorization` 与 `TenantContext` 守卫，经 `CustomerDocs::Repository` 渲染 `doc/customer` 中的 Markdown，并为文章及缺失页面响应设置 `Cache-Control: private, no-store`。客户管理员不能打开其他客户的指南 URL。开发文档仍位于仅平台所有者可访问的维护命名空间。

## 需要特别注意

### 路由审计：回复与结案不变量

`Help::Activities::AddMessage` 与 `Resolve` 均在 `request.with_lock` 内重新加载状态，过时 open 实例不能在结案后提交回复。消息、附件、最后消息时间及作者阅读游标一起保存；回复通知经 `ActiveRecord.after_all_transactions_commit` 发送。拒绝不写消息／阅读副作用，也不推送回复。

请求人路由仍仅开单人可见，同租户其他 admin 也不能读取；平台所有者仅在 owner／81721200 门禁下跨租户读取，没有重新打开路由。见[租户与角色](tenancy-and-roles)、[公告](announcements)、[后台任务](background-jobs)。

:::note
过时实例回复／结案回归测试已编写，本次未执行。实际锁竞争、这些写入以外的阅读游标竞争及队列／浏览器通知仍待验证。
:::

:::attention
`Admin::Maintenance::Platform::SupportTicketsController` 查询 `SupportTicket.unscoped_by_tenant`。`TenantScoped` 不安装 default scope；这里显式 unscope，是为了让收件箱不走 `for_customer(current_customer_id)`。租户控制器仍限制 `for_customer` 与 `user_id: current_user.id`。
:::

:::attention
`Help::Activities::AddMessage` 的 `author_role` 来自控制器参数：平台消息控制器传 `"owner"`，`Admin::SupportTicketMessagesController` 传 `"requester"`。`SupportTicket#unread_for?` 用 `user.platform_owner?` 对调对方角色。角色写错，未读就会算到另一边。
:::

:::attention
`SupportTicketRead.record!` 把 `customer_id` 设为 `support_ticket.customer_id`，也就是工单所属租户。平台所有者在代管其他客户时，游标仍落在这一行。URL 上的代管见 [客户](customers)。
:::

:::attention
`Help::Activities::Resolve` 只把 `status` 更新为 `"resolved"`。之后 `AddMessage` 会返回 `help.errors.resolved`。平台结案控制器没有重新打开的动作。`Notifications::Inbox` 在 `HISTORY_RETENTION` 之后不再列出已结案工单；平台列表仍会继续列出它们。
:::

## 关键代码

```ruby
# app/controllers/admin/maintenance/platform/support_tickets_controller.rb
def index
  result = ModuleEntriesResolver.call(
    scope:   SupportTicket.unscoped_by_tenant.includes(:customer, :user, :reads, :messages).newest_first,
    columns: index_columns,
    filters: index_filters,
    params:  index_params
  )
  # ...
end
```

```ruby
# app/controllers/admin/maintenance/platform/support_ticket_messages_controller.rb
def create
  request = SupportTicket.unscoped_by_tenant.find(params[:support_ticket_id])
  result = Help::Activities::AddMessage.call(
    request: request,
    user: current_user,
    author_role: "owner",
    params: message_params
  )
  # ...
end
```

```ruby
# app/models/support_ticket.rb
def unread_for?(user)
  return false if user.blank?

  cutoff = reads.find { |row| row.user_id == user.id }&.last_read_at
  counterpart = user.platform_owner? ? "requester" : "owner"
  unseen = messages.select { |msg| msg.author_role == counterpart }
  unseen = unseen.select { |msg| msg.created_at > cutoff } if cutoff
  unseen.any?
end
```

```ruby
# app/services/help/activities/resolve.rb
result = Help::Activities::Resolve.call(request: ticket)
# Persisted state is rechecked under the ticket lock.
```
