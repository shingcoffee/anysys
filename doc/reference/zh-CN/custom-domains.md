---
title: "自定义域名"
summary: "每个客户有一个可选域名，与组织名称一起在客户资料中编辑。新增或变更域名时，必须配置直接指向 anysys.net 的 CNAME。"
---

## 概要

每个客户最多一个自定义域名，保存在 `customers.domain`。每个域名只属于一个客户。平台所有者在客户创建和编辑表单的「组织资料」中设置它，方式与组织名称相同。客户资料在同一位置显示该域名。清空字段即移除域名。没有单独的域名列表、专属域名页面或「管理域名」入口。

域名用于为公开快捷路径选择客户。它不发布页面，也不改变授权。见[客户](customers)、[租户与角色](tenancy-and-roles)和[页面快捷路径](page-shortcuts)。

## 流程

```text
平台所有者 + URL 客户 81721200
  维护 → 平台 → 客户 → 编辑客户
    组织资料
      组织名称
      域名
    保存更改
      空白 → customers.domain = null
      未变更 → 不检查 DNS
      新增或变更 → 规范化 → 唯一 → 直接 CNAME anysys.net → 写入 customers.domain
      无效 → 在同一资料表单上返回 422

公开请求
  显式八位客户前缀 → 该客户
  否则精确域名 → Customer.domain_owner_id
  否则 → 默认客户 81721200
  选中的客户已停用 → 404，不会落到其他租户
```

## 实现

`customers.domain` 是可空字符串，最长 253 个字符，并有唯一索引。空白表示客户没有自定义域名。校验前，`Customer` 用 `PageShortcuts::Hosts.normalize` 规范化取值（小写、国际化域名，不含协议、端口或路径）。无效值会被拒绝，表单保留用户输入的原文。`Customer.domain_owner_id` 读取该列。没有 `customer_hostnames` 表，也没有域名控制器。

`customer_params` 与其他资料字段一起允许 `:domain`。创建和更新走 `Customer#save` / `#update`。

当规范化后的域名有值，且与已保存的值不同时，保存会调用 `CustomDomains::CnameVerifier.call(hostname:)`。校验器只返回 `:verified` 或 `:unverified`，并且只接受应答区中直接指向 `anysys.net` 的 CNAME。别名链不算通过。未通过时添加 `custom_domains.errors.cname_unverified`，不修改 `domain`。保存其他资料字段，或清空域名，不检查 DNS。

`PageShortcuts::Hosts.customer_id` 和 `dedicated?` 读取 `Customer.domain_owner_id`。停用客户仍然可被解析，因此公开路由会失败关闭，而不会落到其他租户。查询不使用查询缓存。数据库失败不会被转换成另一个租户。

## 需要特别注意

:::attention
软删除保留 `customers.domain`。停用客户域名上的公开请求返回 404。恢复后该域名重新可路由。永久删除客户时，域名随该行一起删除。
:::

:::attention
DNS、TLS、入口和 Rails 主机授权仍由部署负责。保存域名只记录绑定，不会把该主机加入 Rails 允许列表。假定已终止 SSL 的容器见 [Docker 镜像](docker-image)。
:::

## 关键代码

```ruby
customer.update!(domain: "forms.acme.example")
```

```ruby
Customer.domain_owner_id("forms.acme.example")
```
