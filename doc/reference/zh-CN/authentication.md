---
title: "身份认证"
summary: "邮箱与密码、邮件链接、客户注册，以及 TOTP 门槛如何建立 Authentication::User 会话。"
---

## 概要

`Authentication::User` 是 Devise 模型（表 `users`）。邮箱全局唯一，登录不要求填写客户编号。密码摘要由 Devise 使用 bcrypt 生成。第一因素通过后会轮换会话，再由 `Authentication::MfaObligation` 放行、要求验证 TOTP，或要求管理员与所有者去登记。该用户所属客户必须启用 `authentication` 功能模块，否则这次尝试会表现为密码错误。

OAuth 持票调用是另一套会话，见 [OAuth](oauth)。登录之后谁可以打开 `/admin` 与 `/member`，见 [租户与角色](tenancy-and-roles)。

## 流程

```text
POST /auth/sign_in
  邮箱 + 密码              intent=sign_in_link -> IssueSignInLink
        |
        v
Authentication::Throttle     signin:<ip>  5 分钟 20 次
        |
        v
Authentication::SignInFlow
        |  User.find_for_database_authentication（仅活跃用户，只按邮箱）
        |  FeatureModules::Module.enabled?(key: "authentication")
        |  PasswordVerification -> valid_for_authentication? / valid_password?
        v
Authentication::FinishesSignIn
        |  reset_session、sign_in(:user)、mark_mfa_verified!(verified: result.mfa_verified)
        v
next_action
        |  :mfa_required        GET/POST /:cid/auth/mfa/session
        |  :mfa_setup_required  GET/POST /:cid/auth/mfa/setup
        |  :authenticated       signed_in_destination（先完成认领；再按已保存地址、续接或 LandingPath）
        v
后续请求
ApplicationController 引入 Authentication::EnforcesMfa
        |
        v
Authentication::MfaObligation.for(user:, verified: mfa_session_verified?)
        |  :verify -> /:cid/auth/mfa/session
        |  :enroll -> /:cid/auth/mfa/setup
        |  :none   -> 控制器
```

无密码的第一因素（`GET /auth/sign_in_link`、`GET /auth/confirmation`、`GET /auth/sign_up/confirm`）调用 `SignInFlow.complete`，随后仍走同一个 `finish_sign_in`。

## 实现

### Devise 模型

`Authentication::User` 启用 Devise 的 `:database_authenticatable`、`:registerable`、`:recoverable`、`:confirmable`、`:rememberable`、`:trackable`、`:lockable`、`:timeoutable`。没有启用 `:validatable`。邮箱必填、格式、全局唯一，以及密码长度，都写在模型上。`config/initializers/devise.rb` 把 `authentication_keys` 设为 `[:email]`，`password_length` 为 `8..128`，`stretches` 在测试环境为 `1`、其余为 `12`，`maximum_attempts` 为 `10`，`unlock_strategy` 为 `:time`，`unlock_in` 为 `30.minutes`，`reset_password_within` 为 `6.hours`，`confirm_within` 为 `3.days`，`allow_unconfirmed_access_for` 为 `0.days`，`timeout_in` 为 `30.minutes`，`paranoid` 为 `true`，`sign_out_via` 为 `:delete`。

`find_for_database_authentication` 丢掉任何 `customer_id` 条件，用 `active.find_by_normalized_email` 加载。唯一索引是 `LOWER(email)`。`active_for_authentication?` 是 Devise 的检查再加 `active?`（`status` 枚举）。停用用户会在下一次请求被登出，此时 `inactive_message` 为 `:deactivated`。

路由在 `config/routes.rb`。Devise 挂在 `/auth`，会话、找回密码和确认被替换。注册与解锁被跳过，由下面的控制器接管。多因素路由带租户且属于公共路径：`/:customer_id/auth/mfa/setup`、`mfa/session`、`mfa`（`DELETE`）和 `mfa_recovery`。

### 密码摘要

账户密码存在 `users.encrypted_password`。应用侧的入口是 `Authentication::PasswordVerification`：它调用 `user.valid_for_authentication?`，块内再调用 `user.valid_password?`。这是 Devise 锁定计数的钩子。单独调用 `valid_password?` 只比对摘要，不会增加失败次数。已安装的 `devise` gem 中，`Devise::Encryptor` 用 `BCrypt::Password.create` 按 `klass.stretches` 做哈希，并用 `BCrypt::Engine.hash_secret` 比较。本初始化文件没有设置 `config.pepper`。

`bcrypt`、`scrypt`、`argon2` 三者同时出现在 `FlowchartRuntime::PasswordHash`，供流程图的 `hash_data` 生成器调用。该模块不写 `Authentication::User#encrypted_password`。其中 bcrypt 的默认成本同样是 `12`。

`Authentication::CredentialLifecycle.around_update` 在用户行上串行处理密码、已有 MFA 密钥、邮箱及客户身份的变更。过时快照会被拒绝；同一事务删除可信设备、吊销 OAuth 访问／刷新令牌及尚未兑换的授权码，并清空邮件登录令牌。首次空密钥登记不撤销既有授权；密钥变更重置 `last_otp_at`。`allow_blank_password` 允许创建无密码创办人；提供密码确认值时会校验一致性。

无密码账户的有效性测试应显式关联已持久化的客户。FactoryBot 的 `build(:user)` 也会构建客户关联；未保存客户的随机 ID 仅在创建时分配，因此用户的 `customer_id` 仍为空。无密码标志不豁免租户身份要求，夹具也不应依赖外部 `Current.customer` 才能通过校验。

`Authentication::Settings#timeout_in(default:)` 读取正整数分钟 `session_timeout`，`#maximum_attempts(default:)` 读取正整数 `max_login_attempts`。`Authentication::User::TenantSecurityPolicy` 通过账户实例的 `timeout_in`、`maximum_attempts` 及 Devise 受保护的 `attempts_exceeded?`／`last_attempt?` 应用策略。缺失、畸形或未启用设置回退到上述当前 Devise 类默认值，不修改进程全局配置。Settings 也读取 MFA、注册及重置开关。

普通 Cookie 登录／读取会运行 Devise 回调，并维护 Warden 作用域会话中的 `last_request_at`。GET 会话到期时，已安装的 Devise FailureApp 先清除认证，再重定向回尝试访问的路径；下一次未认证请求转到 `/auth/sign_in`。验收应检查认证作用域已清空及完整跳转过程，不能把第一次重试视为会话仍有效。仅无状态 Bearer 主体抑制回调。

### 密码登录

`Authentication::SessionsController` 在 `create` 上跳过 Devise 的 `allow_params_authentication!`，避免 Warden 再计一次失败。`POST /auth/sign_in` 且 `params[:intent] == "sign_in_link"` 时交给 `Authentication::IssuesSignInLink`。否则先读取受信任设备 cookie，再调用 `Authentication::SignInFlow`，以免会话轮换把 cookie 清掉。

`SignInFlow#call` 要求用户处于活跃状态、`password_set?`、`FeatureModules::Module.enabled?(key: "authentication", customer_id:)` 为真，并且 `PasswordVerification` 通过。模块关闭、密码为空、账户锁定或摘要不符，都返回 `:invalid_credentials`。控制器在 `access_locked?` 时审计 `:locked_out`，否则审计 `:login_failed`，并用 `devise.failure.invalid` 以状态 `422` 重新渲染登录页。`Authentication::Throttle` 的键 `signin:<ip>` 在 5 分钟内超过 20 次后返回 `429`。`hit!` 对每次尝试计数，成功也计入。

成功后 `post_auth_action` 决定下一步：

- `mfa_required?`（`otp_required_for_login` 且已有密钥）得到 `:mfa_required`。若 `Authentication::TrustedDevice.authenticate` 接受该 cookie，则直接为 `:authenticated`。
- 否则，用户不是纯成员，且 `Authentication::Settings#mfa_enabled?` 为真时，结果为 `:mfa_setup_required`。
- `mfa_configured?`（已有密钥，但登录尚未强制）同样是 `:mfa_setup_required`。
- 其余为 `:authenticated`。

`FinishesSignIn#finish_sign_in` 将 flash 和返回地址带过 `reset_session`，登录用户，并按结果设置 MFA 验证标志。登录历史由 Devise Trackable 钩子更新一次，concern 不再重复更新。只有 `:authenticated` 会把会话标成已验证。需要多因素验证或登记时，重定向到对应路径，此时不会完成待认领的人员条目。会话完全建立后（`:authenticated`，或多因素验证／登记成功）经 `signed_in_destination(user)` 跳转——见**登录落点**。

`DELETE /auth/sign_out` 登出、清除多因素会话键、审计 `:logout`，并回到登录页。

`Authentication::SessionsController` 在成功结果的用户尚未确认时，会把邮箱放入 `session[:unconfirmed_email]` 并回到登录页。`allow_unconfirmed_access_for` 为 `0.days`，`PasswordVerification` 会拒绝未通过 `active_for_authentication?` 的用户，因此未确认用户的密码尝试在 `SignInFlow` 内就会失败，到不了这个分支。无密码路径上的 `SignInFlow.complete` 自己检查 `confirmed?`。

### 多因素门槛

决策只在 `Authentication::MfaObligation`：

- `mfa_required?` 且本会话尚未针对当前密钥出示验证码时，返回 `VERIFY`。
- 尚未进入强制状态，但 `mfa_configured?` 为真，或租户强制多因素适用时，返回 `ENROLL`。先前的 `verified` 标志不能代替登记。
- 其余返回 `NONE`。

租户多因素（`Settings#mfa_enabled?`）适用于管理员和所有者。`user.member? && !user.admin_or_owner?` 时该方法返回 false。成员在成员安全页面自行登记。

`Authentication::MfaSessionVerification` 保存 `session[:mfa_verified]` 和 `session[:mfa_secret_digest]`，后者是 `otp_secret` 的 SHA-256。两者与当前密钥一致时，`mfa_session_verified?` 才为真。`Authentication::User` 对 `otp_secret` 做静态加密。

`Authentication::EnforcesMfa` 是 `ApplicationController` 上的 `before_action`。`VERIFY` 时，除非 `controller_path` 在 `CHALLENGE_EXEMPT_CONTROLLERS`（`authentication/sessions`、`authentication/customer_registrations`、`authentication/mfa_sessions`、`authentication/mfa_recoveries`、`locales`、`oauth/authorizations`），否则重定向到 `mfa_session_path`。`ENROLL` 另外允许 `authentication/mfa_setups`、`authentication/mfas` 和 `member/mfa`。重定向里的客户编号是 `current_customer_id`，没有则用用户自己的编号，因此平台所有者在 URL 租户上完成多因素。

`Authentication::MfaSessionsController`（引入 `RequiresSignIn`）用 `User#verify_otp` 验证。ROTP 的签发方为 `"Anysys"`，前后漂移各 15 秒，并传入 `after: last_otp_at`。`claim_otp_timecode` 用带条件的 `UPDATE` 推进 `last_otp_at`，使一个验证码只能被消耗一次。`Authentication::Throttle.mfa` 为每位用户每 15 分钟 5 次失败，登记和关闭共用这个桶。勾选信任设备时调用 `TrustedDevice.issue!`，并设置签名、httponly 的 cookie `trusted_device`，有效期为 `TrustedDevice::DEFAULT_TTL`（30 天）。数据行只保存 SHA-256 摘要、`customer_id` 和 `user_id`。

`Authentication::MfaSetupsController` 引入 `Authentication::MfaEnrollment`。`ensure_otp_secret!` 仅在密钥为空时调用 `generate_otp_secret!`。预取 GET（`Purpose`、`Sec-Purpose` 或 `X-Sec-Purpose: prefetch`）不写入密钥；密钥仍为空时返回 `204`。用户菜单和会员安全页链接设置 `data-turbo-prefetch="false"`。`create` 验证通过后，`enable_mfa!` 把 `otp_required_for_login` 设为真。已经 `mfa_required?` 时设置页会直接离开，已完成的密钥不会再次渲染。响应带 `no_store`。

`Authentication::MfasController#destroy` 只有在重新通过 OTP，或用 `PasswordVerification` 核对 `current_password` 之后，才关闭多因素，并受同一套节流约束。它会清掉会话标志。`Authentication::MfaRecoveriesController` 是丢失验证器后的邮件路径，页面始终相同。实际工作在 `Member::Mfa::Operation::RequestResetLink` 与 `ConsumeResetLink`。`consume` 的 `GET` 不消耗令牌。`POST` 成功后会重置会话并登出。

### 邮件登录链接

`POST /auth/sign_in_link` 与登录表单上的链接意图都进入 `IssuesSignInLink#issue_sign_in_link`。无论地址是否存在，响应都是「请查收邮件」页。`Authentication::IssueSignInLink` 用 `find_by_normalized_email` 查找。找不到、已停用，或认证模块关闭时，什么都不做。已确认用户通过 `update_columns` 写入 Devise 生成的 `sign_in_token`（不更新 `updated_at`，也不触发凭据吊销回调），并由 `SignInLinkMailer.sign_in_link(...).deliver_later` 投递。有效期 `15.minutes`。未确认用户走 `User.send_confirmation_instructions`，成员重发仍受租户注册开关约束。

`GET /auth/sign_in_link` 对 `HEAD` 返回 `200`，不消耗令牌。签发与 `Authentication::ConsumeSignInLink` 按当前账户快照同步；消费在锁内重新检查资格，并有条件地清空令牌，只有一个请求能成功。随后仍由 `SignInFlow.complete` 决定授权。

### 客户注册与成员注册

公开创建租户由 `Authentication::CustomerRegistrationsController` 处理：

1. `Authentication::PlatformSettings.customer_signup_enabled?` 为真时（表 `authentication_platform_settings.allow_customer_signup`，首次读取时种成 true），`GET /auth/sign_up` 与 `POST /auth/sign_up` 收集邮箱。
2. `Authentication::IssueCustomerSignup` 发信。控制器一律转到查收邮件页。
3. `GET /auth/sign_up/confirm` 的 `HEAD` 不消耗令牌。`Authentication::CustomerSignupToken.verify` 返回邮箱。令牌是无状态的，没有「已使用」标记，因此已经确认过的地址会被送回登录页，而不是再次登录。
4. 新地址运行 `Authentication::CustomerSignup`：创建活跃 `Customer`（`industry: "technology"`、`role: :admin`、`tier: :basic`），跳过认证模块的 provisioner，并保存一位没有密码、已经确认的管理员。随机编号若等于 `PLATFORM_CUSTOMER_ID`，事务回滚。`assign_admin!` 挂上系统角色 `admin`。
5. 接着 `SignInFlow.complete` 与 `finish_sign_in`。

成员自助注册是 `Authentication::RegistrationsController` 上的 `GET /:customer_id/auth/sign_up` 与 `POST /:customer_id/auth`。`check_auth_enabled` 要求认证模块已启用。`check_registration_allowed` 要求 `Authentication::Settings#signup_enabled?`（`allow_registration`，默认 false）。`create` 调用 `Authentication::RegisterMember`（见下）。此时不登录。用户经 `Authentication::ConfirmationsController#show` 确认，该方法同样调用 `SignInFlow.complete`，成功后再走 `finish_sign_in`——因此无密码确认会直接登录该会员。已登录访问者会被带离这个 `show`，避免一个人的确认链接换掉另一个人的会话。`GET /auth/confirmation/new` 回到登录页。重发由 `Authentication::EmailFloodThrottled` 节流。

### RegisterMember

`Authentication::RegisterMember.call(customer:, attributes:, request: nil, passwordless: false)` 是公开注册表单与流程图 `register_member` 步骤共用的写入器。返回 `Result(status:, user:, errors:)`，`status` 为 `:created`、`:invalid`、`:quota_exceeded` 之一。

它**不**检查 `signup_enabled?`。由调用方把关：控制器用 `check_registration_allowed`，步骤用 `Authentication::Settings#signup_enabled?` 与认证模块。属性只取 `first_name`、`last_name`、`email`、`password`、`password_confirmation`。`passwordless: true` 会设置 `allow_blank_password`，以便步骤创建没有密码的未确认会员。

在 `customer.with_lock(requires_new: true)` 内执行 `Billing::Quota::Guard.check(..., item_key: "member")`、保存用户，并挂上系统角色 `member`（`assign_member_role!`）。Devise `:confirmable` 在最外层事务提交后把确认邮件放入队列。保留角色失败记为 `:invalid`，文案为 `auth.errors.reserved_role_required`。配额拒绝记为 `:quota_exceeded`，不持久化用户。并发写入撞上邮箱唯一索引时记为 `:invalid`，带 `email` 的 `:taken` 错误，不会抛出异常。

注册表单带密码调用（`passwordless: false`）。`register_member` 步骤以 `passwordless: true` 只传入身份属性。见[受众流程](audience-flows)与[流程图运行时](flowchart-runtime)。

### 注册不暴露账号是否存在

两条注册路径对已占用的地址与新地址给出完全相同的响应：

- **表单。** 唯一的错误是 `email` 的 `:taken` 时，`RegistrationsController#create` 去掉该错误，返回与新建账号相同的重定向和 `auth.flash.confirmation_sent` 闪讯。存在其他错误时照常显示，但绝不显示“已被占用”。配额检查在校验之前，配额已满时所有地址得到同一结果。
- **通知。** `Authentication::NotifyExistingMember.call(user:, customer_id:)` 决定已占用地址收到什么：本租户已确认的有效会员经 `IssueSignInLink` 收到登录链接，计入登录链接页按地址的防轰炸限额（`EmailFloodThrottled.email_throttle("sign_in_link", email, tenant_key: "global")`）；其他人什么都不收到。`register_member` 步骤使用同一服务。
- **邮件。** `Authentication::User#send_devise_notification` 使用 `deliver_later`，所有 Devise 邮件（确认、重置、解锁）都不在请求内等待 SMTP。
- **耗时。** `Authentication::UniformTiming` 把响应补齐到 `FLOOR`（0.4 秒），从查询邮箱之前开始计时。只在事务提交后补齐，事务未结束时从不等待，因此等待期间不持有锁（事务型测试也不会等待）。该下限须高于最慢的分支，即创建账号。

### 登录落点

`Authentication::FinishesSignIn#signed_in_destination(user)` 是登录后唯一的落点辅助方法。密码登录、邮件登录链接、确认、多因素验证与多因素登记，都在会话完全建立后调用它——多因素尚未完成时不会调用（`finish_sign_in` 先把用户送到 `/auth/mfa/session` 或 `/auth/mfa/setup`；这两个控制器在第二因素通过后再调用 `signed_in_destination`）。

它总是先完成待认领的人员条目（`People::Claim.complete!(user)`），再按以下顺序选路径：

1. 安全的已保存返回地址（`safe_return_path_for(user, stored_location_for(:user))`），例如 OAuth 授权回跳；
2. 认领上的续接（用户所属租户下的 `/:cid/actions/:key`，带已记录的预填）；
3. `Authentication::LandingPath.for(user)`。

已保存地址优先，因为任何人都可以用别人的邮箱触发 `register_member` 的“已有账号”分支，这不得覆盖对方原先要返回的位置。先完成认领仍会关联学生条目（若有）并消费该行。认领存在数据库中，因此在另一台设备上打开确认信或登录链接同样会完成。见[人员关联](person-linking)。

账户编辑是 `GET /auth/edit` 与 `PATCH/PUT /auth`。已有密码的用户先经 `Authentication::PasswordVerification.authenticate` 复核，再赋入提交的凭据；保留 Lockable 计数及表单错误，不保存被拒绝的凭据。无密码创办人可不提供 `current_password` 设置密码；密码存在前去掉 `email`（`reconfirmable` 为 false）。

成员配额按实际成员分配计数，不包含开通时创建的管理员或其他管理员账户。付费权益上限来自已接受订阅的 `plan_snapshot`，后续目录变更不会修改既有额度。认证配额回归测试在创建订阅时明确构造该快照，并用成员数据消耗额度。

### 重置密码

`Authentication::PasswordsController` 用共用的邮件洪水限制器节流 `create`。`User.send_reset_password_instructions` 走 `recover_by_email`：未知邮箱返回带 `:not_found` 的空对象（paranoid 模式不把这一点暴露出去）；已知用户只有在 `password_reset_available?` 为真时才发信（认证模块开启，且 `Settings#password_reset_enabled?`，默认 true）。`edit` 与 `update` 从重置令牌解析用户，若该谓词此时为假，则渲染 `:disabled`，状态 `403`。`sign_in_after_reset_password?` 返回 false，邮箱证明不能跳过多因素。成功后回到登录页。密码变更仍会经用户回调吊销受信任设备和 OAuth 令牌。

## 需要特别注意

### 路由审计：凭据与验证凭证不变量

密码重置编辑检查查询令牌；更新检查 Devise 实际消费的允许参数 `user[reset_password_token]`，忽略冲突的顶层令牌。`Authentication::MfaMutation` 检查当前凭据快照。恢复令牌绑定会员、租户及当前密钥指纹，并在重置锁内重新校验。`Authentication::OwnerIdentity` 固定既有所有者的邮箱／客户身份。裸 `code` 参数及其嵌套键按大小写不敏感方式过滤，`postal_code` 不受影响。

`Authentication::HandlesCredentialConflicts` 仅处理 User 过时对象错误：HTTP `409`、no-store／no-referrer、本地化纯文本或 JSON `{ error: "stale_credentials", message: ... }`。重试前须重新加载。相关边界见 [OAuth](oauth)、[访问授权](access-grants)、[会员与公开页面](member-and-public)。

MFA 恢复消费 GET／HEAD／POST 及令牌缺失／无效／过期分支均带 private／no-store 及 no-referrer。`Authentication::MutationAudit.mfa(user:, request: nil, actor: nil, source:)` 在凭据锁内记录 required／configured 前后事实；`roles(user:, before_role_ids:, request: nil, actor: nil)` 在调用方修改锁内记录角色 ID 差集。角色编辑／分配／移除、认证／会员 MFA、管理端重置及恢复共用该写入器。结果行参与修改事务，日志等待全部外层事务提交；拒绝／无操作／回滚不产生成功事件，元数据不包含凭据、验证码、令牌或请求参数哈希。

已挂载的会员／管理员／客户注册及 provisioner 路径原子保存账户与唯一保留角色。直接模型创建仍是无自动角色回调的底层 API，独立调用方使用开通／分配 API。Bearer 在 Devise 账户资格检查后设置无回调主体，不修改浏览器登录历史，见 [OAuth](oauth)。

:::note
上述 API 及路由接入已按源码记载。2026-10-12 并行 RSpec 通过 **25,266 个示例，0 个失败**。超出该套件的浏览器与并发验收仍须单独确认。
:::

:::attention
客户的 `"authentication"` 模块在 `FeatureModules::Module.enabled?` 为假时，`Authentication::SignInFlow` 返回 `:invalid_credentials`。登录页显示的是与密码错误相同的 Devise 文案。不要在 `Authentication::SessionsController#create` 上另做「模块已关闭」的响应。
:::

:::attention
`Authentication::MfaObligation` 与 `SignInFlow#tenant_mfa_enforced?` 在 `user.member? && !user.admin_or_owner?` 时跳过租户强制多因素。`FeatureModules::Authentication::Registration` 的模式说明写成面向全体用户。真正执行的是上述谓词。
:::

:::attention
`Authentication::PasswordVerification` 必须留在 `valid_for_authentication?` 上。`Authentication::MfasController` 用它做密码复核，关闭多因素的尝试才会计入 Devise 的锁定次数。单独的 `valid_password?` 不会。
:::

:::attention
Devise 初始化提供回退超时 30 分钟及失败上限 10 次。已启用租户覆盖对浏览器空闲到期、Lockable 警告／计数及 PasswordVerification 生效，按账户解析，不改变其他租户。
:::

:::note
`Authentication::User` 的密码经 Devise 使用 bcrypt。`FlowchartRuntime::PasswordHash` 是流程图步骤用的 bcrypt、scrypt、argon2 封装。流程图哈希不能用来登录用户。
:::

:::attention
`signed_in_destination` 先执行 `People::Claim.complete!(user)`，再看已保存的返回地址。OAuth 回跳仍优先作为重定向目标，但学生条目会被关联，认领行会被消费。`next_action` 为 `:mfa_required` 或 `:mfa_setup_required` 时，不要在 `finish_sign_in` 里完成认领。
:::

:::attention
`Authentication::RegisterMember` 不读取 `signup_enabled?`。绕过控制器或 `register_member` 步骤的调用方必须自行把关注册。Devise 在最外层提交之后才发确认邮件，不在锁内发送。
:::

## 关键代码

```ruby
# config/initializers/devise.rb
  config.stretches = Rails.env.test? ? 1 : 12

  config.reconfirmable = false

  config.expire_all_remember_me_on_sign_out = true

  config.password_length = 8..128

  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  config.lock_strategy = :failed_attempts
  config.unlock_keys = [:email]
  config.unlock_strategy = :time
  config.maximum_attempts = 10
  config.unlock_in = 30.minutes
```

```ruby
# config/initializers/devise.rb
  config.confirm_within = 3.days
  config.allow_unconfirmed_access_for = 0.days

  # ==========================================================================
  # :timeoutable
  # ==========================================================================
   # Default idle-session expiry; User::TenantSecurityPolicy resolves
   # active account overrides without changing process-global configuration.
  config.timeout_in = 30.minutes

  # Paranoid mode: do not reveal whether an email exists (password reset,
  # unlock instructions). Mitigates user enumeration during account recovery.
  config.paranoid = true

  config.sign_out_via = :delete

  config.responder.error_status = :unprocessable_content
  config.responder.redirect_status = :see_other

  # Email is globally unique. find_for_database_authentication looks up by
  # email alone; tenant comes from the matched user row.
  config.authentication_keys = [:email]
```

```ruby
# app/services/authentication/password_verification.rb
    def self.call(user:, password:, on_comparison: nil)
      user.valid_for_authentication? do
        matches = user.valid_password?(password)
        on_comparison&.call(matches)
        matches
      end
    end
```

```ruby
# app/services/authentication/sign_in_flow.rb
    def post_auth_action(user)
      if user.mfa_required?
        return :authenticated if trusted_device?(user)
        return :mfa_required
      end
      # Tenant-wide MFA for admins/owners: send them to setup *before*
      # marking the session verified. Otherwise visiting GET mfa/setup
      # plants otp_secret (mfa_configured? becomes true) while
      # session[:mfa_verified] is already true from password login, and
      # both enforce_mfa! gates treat enrollment as done.
      return :mfa_setup_required if tenant_mfa_enforced?(user)
      return :mfa_setup_required if user.mfa_configured?

      :authenticated
    end

    def tenant_mfa_enforced?(user)
      return false if user.member? && !user.admin_or_owner?

      Authentication::Settings.for(user.customer_id).mfa_enabled?
    end
```

```ruby
# app/services/authentication/mfa_obligation.rb
    def call
      return NONE unless user.respond_to?(:mfa_required?)

      return verified ? NONE : VERIFY if user.mfa_required?

      # An enrolment obligation is NOT satisfiable by a session flag — only by
      # actually enrolling. Honouring `verified` here was a real bypass: a
      # session established before the tenant switched MFA on (or before an
      # admin reset the user's secret) carried `verified = true` for its whole
      # life, and the gate short-circuited on it, so the mandate never applied
      # to anyone already signed in.
      return ENROLL if user.mfa_configured?
      return ENROLL if tenant_enforced?

      NONE
    end
```

```ruby
# app/controllers/concerns/authentication/enforces_mfa.rb
    CHALLENGE_EXEMPT_CONTROLLERS = %w[
      authentication/sessions
      authentication/customer_registrations
      authentication/mfa_sessions
      authentication/mfa_recoveries
      locales
      oauth/authorizations
    ].freeze
```

```ruby
# app/services/flowchart_runtime/password_hash.rb
    PASSWORD_ALGORITHMS = %w[bcrypt scrypt argon2].freeze
    DEFAULT_BCRYPT_COST = 12
```

```ruby
# app/services/authentication/register_member.rb
    def self.call(customer:, attributes:, request: nil, passwordless: false)
      # :created / :invalid / :quota_exceeded
    end
```

```ruby
# app/controllers/concerns/authentication/finishes_sign_in.rb
    def signed_in_destination(user)
      continuation = People::Claim.complete!(user)
      stored = stored_location_for(:user)
      safe_return_path_for(user, stored) || continuation || default_signed_in_path_for(user)
    end
```
