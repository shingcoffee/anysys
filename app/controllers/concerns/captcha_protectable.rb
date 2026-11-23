# frozen_string_literal: true

# Reusable, action-aware captcha protection for any controller.
#
# Declarative usage:
#   protect_with_captcha only: :submit, action: :page_submit
#   protect_with_captcha only: :create, action: :sign_up, fail: :closed
#
# `action` names the protected flow (drives audit + fail policy). `fail:`
# overrides the platform fail policy for this action (:open or :closed);
# auth-grade flows should pass `fail: :closed`.
#
# Caller responsibilities:
#   - Provide `current_customer_id`.
#   - For :page_submit, set @page (responding to #captcha_enabled?) first.
#   - Render :show (or override #handle_captcha_rejection) when verification
#     fails — @captcha_failed is set to true.
module CaptchaProtectable
  extend ActiveSupport::Concern

  # Outcome → end-user flash message. Never leaks vendor/internal detail.
  REJECTION_KEYS = {
    invalid:             "captcha.errors.invalid",
    replayed:            "captcha.errors.invalid",
    unreachable:         "captcha.errors.unavailable",
    configuration_error: "captcha.errors.unavailable"
  }.freeze

  # Informational notice shown when a request is let through under fail-open.
  FAIL_OPEN_NOTICE_KEYS = {
    unreachable:         "captcha.errors.unreachable",
    configuration_error: "captcha.errors.configuration"
  }.freeze

  class_methods do
    def protect_with_captcha(action:, fail: nil, **filter_opts)
      before_action(filter_opts) do
        verify_captcha!(action: action, fail_override: fail)
      end
    end
  end

  private

  def verify_captcha!(action: :page_submit, fail_override: nil)
    return unless captcha_required_for_request?(action)

    context = Captcha::VerificationContext.new(
      verify_param: params[:captcha_verify_param].to_s,
      remoteip:     request.remote_ip,
      user_agent:   request.user_agent,
      hostname:     request.host,
      action:       action
    )
    result = Captcha::Activities::Verify.call(context: context)

    if result.passed? || result.disabled?
      # Verified, or captcha intentionally off — let the request through.
    elsif result.blocked_hard?
      reject_captcha!(result.outcome)
    elsif captcha_fail_closed?(fail_override, result)
      reject_captcha!(result.outcome)
    else
      Rails.logger.warn("[captcha] fail-open: #{result.outcome}")
      notice_key = FAIL_OPEN_NOTICE_KEYS[result.outcome]
      flash.now[:notice] = I18n.t(notice_key) if notice_key
    end
  end

  def reject_captcha!(outcome)
    @captcha_failed = true
    flash.now[:alert] = I18n.t(REJECTION_KEYS.fetch(outcome, REJECTION_KEYS[:invalid]))
    handle_captcha_rejection(outcome)
  end

  # Default rejection rendering; controllers may override.
  def handle_captcha_rejection(_outcome)
    render :show, status: :unprocessable_entity
  end

  # Unscoped /auth/* forms have no tenant. When captcha is configured at the
  # platform, these actions gate on that row instead of a per-customer module.
  PLATFORM_AUTH_ACTIONS = %i[sign_up sign_in password_reset].freeze

  def captcha_required_for_request?(action)
    if PLATFORM_AUTH_ACTIONS.include?(action.to_sym) && current_customer_id.blank?
      return Captcha::ProviderSettings.active.present?
    end

    return false unless FeatureModules::Module.enabled?(key: "captcha", customer_id: current_customer_id)

    case action.to_sym
    when :page_submit
      @page&.respond_to?(:captcha_enabled?) && @page.captcha_enabled?
    else
      true
    end
  end

  # `result.fail_policy` is the platform policy resolved by Verify (no re-query).
  def captcha_fail_closed?(fail_override, result)
    return fail_override.to_sym == :closed if fail_override

    result.fail_policy.to_s == "closed"
  end
end
