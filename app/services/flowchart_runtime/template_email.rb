# frozen_string_literal: true

module FlowchartRuntime
  # Sends a named Emails template (send_template_email) through Emails::Gateway
  # for the run's customer. Locale wrapping stays here so generated steps stay
  # under BodyLint's line budget.
  module TemplateEmail
    class Error < StandardError; end

    module_function

    def deliver(ctx, to:, template_id:, vars: {}, cc: nil, bcc: nil, reply_to: nil,
                idempotency_key: nil, locale: nil)
      customer = Customer.find_by(id: ctx[:customer_id])
      chosen = locale.presence || ctx[:locale].presence || I18n.locale
      I18n.with_locale(chosen) do
        Emails::Gateway.send(
          customer: customer,
          to: to,
          template_id: template_id,
          vars: vars || {},
          cc: cc,
          bcc: bcc,
          reply_to: reply_to,
          idempotency_key: idempotency_key
        )&.id
      end
    end
  end
end
