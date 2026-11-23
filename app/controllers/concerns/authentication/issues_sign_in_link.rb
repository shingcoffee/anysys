# frozen_string_literal: true

module Authentication
  # The one implementation of "email me a sign-in link", shared by the two
  # entry points that reach it:
  #
  #   * POST /auth/sign_in_link          — SignInLinksController#create
  #   * POST /auth/sign_in (intent=…)    — SessionsController#create
  #
  # There are two entry points because Rails per-form CSRF tokens are bound to
  # the form action, so the sign-in form's secondary button has to post to the
  # sign-in URL; the check-email page posts to the dedicated URL. Both must
  # normalize the address identically, share one throttle bucket, and leave
  # the visitor on the same page — hence one method rather than two.
  module IssuesSignInLink
    extend ActiveSupport::Concern
    include Authentication::EmailFloodThrottled

    private

    # Halts by redirecting in every branch: to sign-in on a throttle breach,
    # to the check-email page otherwise (identical for registered and unknown
    # addresses).
    def issue_sign_in_link(email)
      normalized = email.to_s.strip.downcase

      return unless throttle_email_flood!(
        flow:          "sign_in_link",
        email:         normalized,
        redirect_path: new_user_session_path,
        alert:         t("auth.flash.sign_in_link.throttled")
      )

      Authentication::IssueSignInLink.call(email: normalized)
      session[:sign_in_link_email] = normalized
      redirect_to sign_in_link_check_email_path
    end
  end
end
