# frozen_string_literal: true

Devise.setup do |config|
  config.mailer_sender = "noreply@anysys.com"

  # Make Devise mail inherit from ApplicationMailer so the lambda
  # `default from: -> { Devise.mailer_sender }` (defined in ApplicationMailer)
  # actually applies to Devise's confirmation/reset emails. Without this,
  # ApplicationMailer's defaults are bypassed by Devise::Mailer.
  config.parent_mailer = "ApplicationMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]

  config.skip_session_storage = [:http_auth]

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

  config.reset_password_within = 6.hours

  # ==========================================================================
  # :confirmable
  # ==========================================================================
  # Strict policy: confirmation required before any sign-in. The toggle
  # `allow_registration` (per-customer) gates whether the sign-up form +
  # confirmation routes are available; once a user signs up, they cannot
  # sign in until they click the link in the email.
  config.confirm_within = 3.days
  config.allow_unconfirmed_access_for = 0.days

  # ==========================================================================
  # :timeoutable
  # ==========================================================================
  # Default idle-session expiry. User::TenantSecurityPolicy resolves an active
  # account's session_timeout/max_login_attempts overrides without changing
  # process-global Devise configuration.
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
end
