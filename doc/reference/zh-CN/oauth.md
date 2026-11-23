---
title: "OAuth"
summary: "第一方桌面客户端如何用 PKCE 取得授权码、刷新令牌，并用 Bearer 调用本应用。"
---

## 概要

本应用是 OAuth 2.0 授权服务器，只服务一个公开客户端 `anysys-desktop`。Doorkeeper 签发授权码和不透明令牌。PKCE 必须使用 S256。浏览器登录与 [身份认证](authentication) 是同一套 Devise 会话，包含多因素，这个客户端没有单独的同意页。API 调用发送 `Authorization: Bearer`，不复用 cookie 会话。

`docs/guides/OAUTH_PKCE_DESKTOP.md` 里的桌面协议与 `Oauth::Protocol` 的常量一致。若与代码不符，以代码为准。

## 流程

```text
GET /.well-known/oauth-authorization-server
        |
        v
Oauth::DiscoveryController -> Oauth::ServerMetadata
        |
        v
GET /oauth/authorize
  client_id=anysys-desktop
  code_challenge 为 S256，state 长度 >= 16，response_mode 为 query 或省略
  redirect_uri 为 http://127.0.0.1:<port>/callback 或 http://[::1]/callback
        |
        v
Oauth::AuthorizationsController#authenticate_desktop_resource_owner!
        |
        v
Oauth::AuthenticateResourceOwner
        |  :sign_in    -> /auth/sign_in（保存返回地址）
        |  :mfa_verify -> /:cid/auth/mfa/session
        |  :mfa_setup  -> /:cid/auth/mfa/setup
        |  :authorized -> Doorkeeper 签发授权码
        v
HTML 交接页（不是 302）-> 回环 ?code=&state=
        |
        v
POST /oauth/token
  authorization_code + code_verifier    或    refresh_token
        |
        v
Oauth::AccessToken（密钥经哈希，带 family_started_at）
        |
        +--> GET /oauth/userinfo                          Oauth::Userinfo
        |
        +--> Bearer API（拒绝 cookie，跳过多因素过滤）
               GET  /:cid/admin/entity_definitions
               /:cid/admin/assistant/messages
               /:cid/admin/assistant/transcriptions
               |
               Oauth::BearerAuthenticatable
               Oauth::TokenIdentity
                warden.set_user(user, store: false, run_callbacks: false)
               TenantContext 与 RouteAuthorization 仍然执行
```

`POST /oauth/revoke` 吊销提交的刷新令牌。在刷新授权里再次使用已吊销或空闲过期的刷新令牌，会吊销整个令牌族。

## 实现

### 配置

`config/initializers/doorkeeper.rb` 加载 `Oauth::Protocol`，并设置：

- `access_token_class` 为 `"Oauth::AccessToken"`
- `grant_flows` 只有 `authorization_code`。`allow_grant_flow_for_client` 另外允许 `refresh_token`，且仅当 `client.uid` 为 `Oauth::Protocol::CLIENT_ID`。
- `force_pkce`，`pkce_code_challenge_methods` 为 `%w[S256]`
- `use_refresh_token`
- `hash_token_secrets` 与 `hash_application_secrets`
- `default_scopes` 为 `:profile`，并 `enforce_configured_scopes`
- 寿命来自 `Oauth::Protocol`：授权码 `10.minutes`，访问令牌 `1.hour`
- `custom_access_token_attributes [:family_started_at]`
- 客户端 uid 为 `anysys-desktop` 时 `skip_authorization`
- `resource_owner_authenticator` 调用控制器上的 `authenticate_desktop_resource_owner!`
- `base_controller` 为 `"ApplicationController"`
- 重定向 URI 必须是回环地址（`force_ssl_in_redirect_uri` 只对回环为假，`forbid_redirect_uri` 拒绝一切非回环 URI）

`config/routes.rb` 的 `use_doorkeeper` 跳过 `:applications`、`:authorized_applications` 和 `:token_info`，把授权指到 `oauth/authorizations`，把令牌指到 `oauth/tokens`。Doorkeeper 的路由映射随后在 `oauth` 作用域下画出：`GET /oauth/authorize`（`new`）、`POST /oauth/authorize`（`create`）、`DELETE /oauth/authorize`（`destroy`）、`GET /oauth/authorize/native`（gem 的本机授权码路径；本应用的回环成功路径改为渲染交接页）、`POST /oauth/token`、`POST /oauth/revoke`。当 `allow_token_introspection` 不是 `false` 时，映射还会画出 `POST /oauth/introspect`。本初始化文件没有设置该选项。已安装的 Doorkeeper 5.9 默认值是一个 lambda，因此内省路由会被挂上。`Oauth::ServerMetadata` 不公布内省路径，也不公布 native 路径。

`GET /.well-known/oauth-authorization-server` 是 `Oauth::DiscoveryController#show`。`GET /oauth/userinfo` 是 `Oauth::UserinfoController#show`。

### 客户端

`Oauth::Protocol` 是契约：`CLIENT_ID` 为 `"anysys-desktop"`，`SCOPE` 为 `"profile"`，`CALLBACK_PATH` 为 `"/callback"`，`MIN_STATE_LENGTH` 为 `16`，`RESPONSE_MODE` 为 `"query"`。`LOOPBACK_REDIRECT_URIS` 列出不带端口的 `http://127.0.0.1/callback` 与 `http://[::1]/callback`。`loopback_redirect?` 接受 Doorkeeper `URIChecker.loopback_uri?` 认定的回环主机，协议为 `http`，路径必须恰好是 `/callback`。因此 `127.0.0.1` 上的临时端口能通过这个谓词，即使它不在那两行种子字符串里。

`Oauth::DesktopClient.ensure!` 按该 uid 查找或创建 `Doorkeeper::Application`，写入名称、用换行拼起来的两个重定向 URI、`confidential: false`，以及范围 `profile`。已有的哈希密钥不会被轮换。`config/initializers/oauth_desktop_client.rb` 在初始化之后、非测试环境、且存在 `oauth_applications` 表时调用 `ensure!`。`db/seeds.rb` 也会调用。

### 授权

`Oauth::AuthorizationsController` 使用 `auth` 布局。`new`、`create`、`destroy` 上的 `require_desktop_authorize_params!` 要求 state 至少 16 字符、响应模式为空或 `query`，否则返回本地 `400 invalid_request`。拒绝授权前检查 `pre_auth.authorizable?`；未知客户端、不允许的流程及未登记／畸形地址均留在本地报错，不重定向。

`authenticate_desktop_resource_owner!` 把 `current_user` 和 `mfa_session_verified?` 交给 `Oauth::AuthenticateResourceOwner`。用户缺失、已停用，或其客户的认证模块关闭时，服务返回 `:sign_in`。它根据 `Authentication::MfaObligation` 返回 `:mfa_verify` 或 `:mfa_setup`，否则返回 `:authorized`。控制器用 Devise 保存 `request.fullpath`，并重定向到登录页，或按 `result.user.customer_id` 转到 `mfa_session_path` / `mfa_setup_path`。`oauth/authorizations` 在 `Authentication::EnforcesMfa` 的验证豁免名单里，因此这次重定向不会再被多因素门槛转走。这里会再次询问义务，授权端点不能绕过尚未完成的第二因素。

`pre_auth_param_fields` 从授权查询中去掉 `family_started_at`。`Oauth::AccessToken.create_for` 在调用方未传入时把 `family_started_at` 设为 `Time.current`。Doorkeeper 会把该属性复制到后续刷新产生的令牌上。

`redirect_or_render` 发现回环 `redirect_uri` 时渲染 `oauth/authorizations/native_handoff`，而不是让 Doorkeeper 发 302。Turbo 会丢掉指向 `127.0.0.1` 的跨源重定向。`protect_authorization_code!` 设置 `Cache-Control: no-store`、`Pragma: no-cache` 和 `Referrer-Policy: no-referrer`。授权成功后，初始化文件里的 `after_successful_authorization` 钩子审计 `:oauth_authorized`。

PKCE 由 Doorkeeper 执行，开关是 `force_pkce` 和 S256 方法列表。令牌请求必须带 `code_verifier`。本应用没有重写 S256 比较。

### 令牌、刷新与吊销

`Oauth::AccessToken` 使用表 `oauth_access_tokens` 和 Doorkeeper 的 ActiveRecord mixin。`hash_token_secrets` 开启后，密钥以哈希保存。`created_at` 早于 `Protocol::REFRESH_IDLE_TTL`（90 天），或 `family_started_at`（族时钟为空时用 `created_at`）早于 `Protocol::REFRESH_ABSOLUTE_TTL`（1 年）时，`refresh_expired?` 为真。

`by_refresh_token` 在令牌仍然有效时返回该行。已吊销或刷新已过期的行会调用 `revoke_family!` 并返回 nil，这是 RFC 9700 的重用响应。`revoke_family!` 给同一 `application_id`、`resource_owner_id`、`family_started_at` 下尚未吊销的行写入 `revoked_at`。`family_started_at` 为空时只吊销这一行，避免一个空族时钟把其他空族会话一并登出。

`Oauth::TokensController#refresh_token` 只服务于 RFC 7009 的吊销查找。它用 `find_by_plaintext_token(:refresh_token, params["token"])` 找到行，再包进 `Doorkeeper::RevocableTokens::RevocableRefreshToken`。它不调用 `by_refresh_token`，因此吊销一个已经吊销的刷新令牌仍是空操作 `200`，不会把仍在使用的链整族吊销。

`revoke_all_for` 跨令牌族／应用吊销资源所有者的全部有效令牌。`Authentication::CredentialLifecycle` 在密码、已有密钥、邮箱或客户身份变更事务中调用它，并吊销未兑换授权码；这与刷新重用处理是不同路径。

授权码已过期／吊销，或账户查询无法解析所有者时，返回结构化 `400 invalid_grant`，不签发令牌。已安装的 Doorkeeper `InvalidGrant` 继承 `BaseResponseError`，构造时必须传入响应对象；兑换与刷新门禁使用 `Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)`。凭据变更吊销的未兑换授权码也遵循同一错误契约。

```ruby
raise Doorkeeper::Errors::InvalidGrant.new(
  Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
)
```

### 用户信息与 Bearer API

`Oauth::UserinfoController` 为 API 控制器，响应 no-store 并校验 profile 范围。`TokenIdentity` 要求有效第一方桌面令牌及 `user.active_for_authentication?`，明确拒绝停用、未确认或锁定账户。无效身份返回 `401 invalid_token`，范围不足为 `403 insufficient_scope`。Userinfo 返回 sub／email／email_verified／name／customer_id／role。

`Oauth::BearerAuthenticatable` 在实体定义及桌面助手／消息／转写控制器前置令牌认证。强制 JSON，TokenIdentity 检查后调用 `warden.set_user(user, scope: :user, store: false, run_callbacks: false)`。不运行 Trackable／Rememberable，不修改浏览器历史或会话 Cookie，仅 Cookie 请求仍无效。Bearer 跳过 Cookie CSRF／MFA 及现代浏览器门槛，租户／admin 授权仍执行。

这些控制器仍继承 `ApplicationController`，因此 Bearer 登录之后 `TenantContext` 与 `RouteAuthorization` 仍会运行。`/:cid/admin/...` 的客户若不是令牌所有者的客户，除非 `platform_owner?`，否则会被拒绝。管理端角色门槛和 `authorize_route!` 仍然有效。cookie 不参与：`store: false`，且该过滤始终要求 Bearer 令牌。

`Oauth::ServerMetadata` 公布 `issuer`、`authorization_endpoint`、`token_endpoint`、`revocation_endpoint`、`userinfo_endpoint`、响应类型 `code`、响应模式 `query`、授权类型 `authorization_code` 与 `refresh_token`、S256、令牌与吊销的客户端认证方法 `none`、范围 `profile`、可用语言，以及 `authorization_response_iss_parameter_supported: false`。设置了 `ENV["APP_HOST"]` 时，签发方就是该源。否则签发方为 `request.base_url`，发现文档带 `Vary: Host` 和 `Cache-Control: public, max-age=3600`。

## 需要特别注意

### 路由审计：签发、兑换及刷新不变量

签发使用 `CredentialLifecycle.with_current(current_resource_owner)`。授权码响应使用 `Oauth::AuthorizationCodeExchange.call(code:)`；刷新消费使用 `Oauth::RefreshTokenConsumption`。均先锁用户，再锁授权码／令牌，并检查持久化状态。重用吊销在失败消费的保存点之外执行，`invalid_grant` 不会将其回滚。客户端／PKCE 校验及 RFC 7009 空操作吊销仍由 Doorkeeper 负责。

Native GET 仅展示传入代码，内省已挂载并受 gem 授权但未在发现文档公布。无回调 Bearer 主体保留浏览器跟踪，账户资格由显式 Devise 检查提供。见[身份认证](authentication)及[租户与角色](tenancy-and-roles)。

:::note
PKCE、兑换／刷新及无回调 Bearer API 已按源码记载。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。超出该套件的浏览器与锁竞争证据仍须单独确认。
:::

:::attention
`Oauth::AccessToken.revoke_family!` 只覆盖一个 `(application_id, resource_owner_id, family_started_at)` 三元组。凭据变更由 `CredentialLifecycle` 使用 `revoke_all_for`；只吊销一族会留下其他桌面会话。
:::

:::attention
`Oauth::TokensController#refresh_token` 用 `find_by_plaintext_token` 查找吊销目标。`by_refresh_token` 是重用检测，会做族吊销。吊销动作不能走那条查找。
:::

:::attention
`Oauth::AuthorizationsController#pre_auth_param_fields` 去掉 `family_started_at`。时钟由 `Oauth::AccessToken.create_for` 在服务端写入。授权查询里的客户端值会在 Doorkeeper 写入授权之前被丢弃。
:::

:::attention
`Oauth::BearerAuthenticatable` 跳过 `Authentication::EnforcesMfa`。第二因素在 `GET /oauth/authorize` 的 `Oauth::AuthenticateResourceOwner` 里要求，它使用 `Authentication::MfaObligation`。多因素打开之前签发的 Bearer 令牌会一直有效，直到被吊销、过期，或 `refresh_expired?` 失败。
:::

:::note
`Oauth::UserinfoController` 没有引入 `TenantContext`。它只凭令牌识别用户。租户检查从引入 `Oauth::BearerAuthenticatable`、并继承 `ApplicationController` 的管理端 Bearer 控制器开始。
:::

## 关键代码

```ruby
# config/initializers/doorkeeper.rb
  grant_flows %w[authorization_code]
  default_scopes :profile
  enforce_configured_scopes
  force_pkce
  pkce_code_challenge_methods %w[S256]
  use_refresh_token
  hash_token_secrets
  hash_application_secrets

  # Single source of truth: Oauth::Protocol is what docs/guides/OAUTH_PKCE_DESKTOP.md
  # documents to the desktop client, and Oauth::AccessToken#refresh_expired?
  # reads the refresh lifetimes from the same place.
  authorization_code_expires_in Oauth::Protocol::AUTHORIZATION_CODE_TTL
  access_token_expires_in Oauth::Protocol::ACCESS_TOKEN_TTL

  custom_access_token_attributes [:family_started_at]
```

```ruby
# app/services/oauth/protocol.rb
    CLIENT_ID = "anysys-desktop"
    CLIENT_NAME = "Anysys Desktop"
    SCOPE = "profile"
    CALLBACK_PATH = "/callback"
    MIN_STATE_LENGTH = 16

    # The loopback handoff always navigates with the code in the query string.
    # Doorkeeper's authorization_code flow would also accept fragment and
    # form_post, neither of which can deliver a code to a loopback listener.
    RESPONSE_MODE = "query"

    ACCESS_TOKEN_TTL = 1.hour
    REFRESH_IDLE_TTL = 90.days
    REFRESH_ABSOLUTE_TTL = 1.year
    AUTHORIZATION_CODE_TTL = 10.minutes
```

```ruby
# app/models/oauth/access_token.rb
    def self.by_refresh_token(refresh_token)
      token = super
      return if token.nil?
      return token unless token.revoked? || token.refresh_expired?

      revoke_family!(token)
      nil
    end
```

```ruby
# app/controllers/oauth/tokens_controller.rb
    def refresh_token
      token = Oauth::AccessToken.find_by_plaintext_token(:refresh_token, params["token"])
      return unless token

      Doorkeeper::RevocableTokens::RevocableRefreshToken.new(token)
    end
```

```ruby
# app/controllers/concerns/oauth/bearer_authenticatable.rb
    def authenticate_oauth_bearer!
      request.format = :json

      user = TokenIdentity.call(Doorkeeper.authenticate(request))
      unless user
        render json: { error: "invalid_token" }, status: :unauthorized
        return
      end

      # TokenIdentity performs account eligibility; suppress browser callbacks.
      warden.set_user(user, scope: :user, store: false, run_callbacks: false)
    end
```

```ruby
# app/services/oauth/authenticate_resource_owner.rb
    def pending_mfa_action
      case Authentication::MfaObligation.for(user: @user, verified: @mfa_verified)
      when Authentication::MfaObligation::VERIFY then :mfa_verify
      when Authentication::MfaObligation::ENROLL then :mfa_setup
      end
    end
```
