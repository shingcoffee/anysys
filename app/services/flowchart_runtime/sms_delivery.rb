# frozen_string_literal: true

module FlowchartRuntime
  # Maps SMS gateway admission rejections onto translated send_sms step codes.
  # FlowchartRuntime::Sms.send_template stays a pass-through so transport
  # identity is preserved; this helper is what generated send_sms steps call.
  module SmsDelivery
    class Error < StandardError; end

    module_function

    def deliver(ctx, customer:, to:, template_key:, vars: {}, idempotency_key: nil)
      raise Error, "customer is required" if customer.nil?

      message = FlowchartRuntime::Sms.send_template(
        customer: customer,
        to: to,
        template_key: template_key,
        vars: vars || {},
        idempotency_key: idempotency_key
      )
      return Step.fail(ctx, :"send_sms.suppressed") if message.respond_to?(:status) && message.status.to_s == "suppressed"

      message.id
    rescue ::Sms::Errors::RateLimited, ::Sms::Errors::DailyCapExceeded
      Step.fail(ctx, :"send_sms.quota")
    rescue ::Sms::Errors::Suppressed
      Step.fail(ctx, :"send_sms.suppressed")
    rescue ::Sms::Errors::CredentialsMissing
      Step.fail(ctx, :"send_sms.credentials_missing")
    rescue ::Sms::Errors::ModuleDisabled
      Step.fail(ctx, :"send_sms.module_disabled")
    rescue ::Sms::Errors::IdempotencyConflict
      Step.fail(ctx, :"send_sms.idempotency_conflict")
    rescue ::Sms::Errors::MarketingIneligible
      Step.fail(ctx, :"send_sms.marketing_ineligible")
    rescue ::Sms::Errors::TemplateNotFound
      Step.fail(ctx, :"send_sms.template_missing")
    rescue ::Sms::Errors::ApiError
      Step.fail(ctx, :"send_sms.api_error")
    rescue ::Sms::Errors::TemplateVarsInvalid => error
      Step.fail(ctx, :"send_sms.#{template_vars_code(error)}")
    rescue ::Sms::Errors::Error
      Step.fail(ctx, :"send_sms.failed", reason: "Error")
    end

    def template_vars_code(error)
      text = error.message.to_s
      return :invalid_number if text.match?(/To is invalid|收件号码无效/)
      return :template_missing if text.match?(/not a registered active template|不是已注册且启用的模板/)
      return :provider_code_missing if text.match?(/provider|通道/)

      :invalid_vars
    end
    private_class_method :template_vars_code
  end
end
